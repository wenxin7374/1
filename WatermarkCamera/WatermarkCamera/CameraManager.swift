import AVFoundation
import UIKit

enum CameraAccess {
    case unknown
    case denied
    case authorized
}

/// 负责 AVCaptureSession、常亮手电筒、对焦与拍照。
/// 注意：torch（持续照明）与 flash（拍照瞬间闪光）是两套机制，这里始终关闭 flash，
/// 使用 torch 常亮，并在拍照完成后重新应用 torch，以兼容部分机型的中断行为。
final class CameraManager: ObservableObject {
    @Published var access: CameraAccess = .unknown
    @Published var isTorchOn = false
    @Published var torchAvailable = false
    @Published var torchSupported = false

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.watermarkcamera.session", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var configured = false
    private var torchLevel: Float = 0.65
    private var captureDelegate: PhotoCaptureDelegate?

    // MARK: - 生命周期

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: Notification.Name("AVCaptureSessionInterruptionNotification"),
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTorchAvailabilityChange(_:)),
            name: Notification.Name("AVCaptureDeviceTorchAvailabilityDidChangeNotification"),
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setAccess(.authorized)
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                self.setAccess(granted ? .authorized : .denied)
                if granted { self.configureAndStart() }
            }
        case .denied, .restricted:
            setAccess(.denied)
        @unknown default:
            setAccess(.denied)
        }
    }

    private func setAccess(_ value: CameraAccess) {
        DispatchQueue.main.async { self.access = value }
    }

    // MARK: - 会话配置

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if !self.configured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo

                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device),
                      self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    self.setAccess(.denied)
                    return
                }

                self.session.addInput(input)
                self.videoInput = input

                self.photoOutput.isHighResolutionCaptureEnabled = true
                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                }

                self.session.commitConfiguration()
                self.configured = true

                let supported = device.hasTorch
                DispatchQueue.main.async { self.torchSupported = supported }
            }

            self.startRunning()
            self.applyTorch(enabled: true)
        }
    }

    private func startRunning() {
        guard !session.isRunning else { return }
        session.startRunning()
    }

    private func stopRunning() {
        guard session.isRunning else { return }
        session.stopRunning()
    }

    // MARK: - 手电筒（torch 常亮）

    func updateTorchLevel(_ level: Float) {
        torchLevel = min(max(level, 0.05), 1.0)
        if isTorchOn { applyTorch(enabled: true) }
    }

    func toggleTorch() {
        applyTorch(enabled: !isTorchOn)
    }

    /// 拍照后恢复 torch；部分机型在静态拍照时会短暂中断常亮。
    func reapplyTorch() {
        if isTorchOn { applyTorch(enabled: true) }
    }

    private func applyTorch(enabled: Bool) {
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = self.videoInput?.device,
                  device.hasTorch else {
                DispatchQueue.main.async {
                    self?.isTorchOn = false
                    self?.torchAvailable = false
                }
                return
            }

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                if enabled && device.isTorchAvailable {
                    let level = min(max(self.torchLevel, 0.05), AVCaptureDevice.maxAvailableTorchLevel)
                    try device.setTorchModeOn(level: level)
                    DispatchQueue.main.async {
                        self.isTorchOn = true
                        self.torchAvailable = true
                    }
                } else {
                    device.torchMode = .off
                    DispatchQueue.main.async {
                        self.isTorchOn = false
                        self.torchAvailable = true
                    }
                }
            } catch {
                // 设备过热或硬件异常时仅更新状态，绝不阻止拍照。
                DispatchQueue.main.async {
                    self.isTorchOn = false
                    self.torchAvailable = device.isTorchAvailable
                }
            }
        }
    }

    // MARK: - 对焦 / 曝光

    func focus(at devicePoint: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            guard device.isFocusPointOfInterestSupported || device.isExposurePointOfInterestSupported else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .autoExpose
                }
            } catch {
                // 对焦失败不影响拍照。
            }
        }
    }

    // MARK: - 拍照

    func capture(snapshot: WatermarkSnapshot,
                 completion: @escaping (Result<UIImage, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else {
                let error = NSError(domain: "WatermarkCamera", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "相机尚未就绪，请稍候再拍"])
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off  // 关闭闪光，避免打断 torch 常亮

            let delegate = PhotoCaptureDelegate(
                snapshot: snapshot,
                completion: completion,
                onFinish: { [weak self] in self?.reapplyTorch() }
            )
            self.captureDelegate = delegate
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    // MARK: - 系统事件

    @objc private func appDidEnterBackground() {
        applyTorch(enabled: false)
        sessionQueue.async { [weak self] in self?.stopRunning() }
    }

    @objc private func appWillEnterForeground() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.startRunning()
            self.applyTorch(enabled: true)
        }
    }

    @objc private func handleInterruption(_ notification: Notification) {
        let isBegan = notification.userInfo?["AVCaptureSessionInterruptionReasonKey"] != nil
        if isBegan {
            applyTorch(enabled: false)
            sessionQueue.async { [weak self] in self?.stopRunning() }
        } else {
            sessionQueue.async { [weak self] in
                guard let self else { return }
                self.startRunning()
                self.applyTorch(enabled: true)
            }
        }
    }

    @objc private func handleTorchAvailabilityChange(_ notification: Notification) {
        if isTorchOn { reapplyTorch() }
        if let device = videoInput?.device {
            let available = device.isTorchAvailable
            DispatchQueue.main.async { self.torchAvailable = available }
        }
    }
}

// MARK: - 照片回调代理

final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let snapshot: WatermarkSnapshot
    private let completion: (Result<UIImage, Error>) -> Void
    private let onFinish: () -> Void
    private var delivered = false

    init(snapshot: WatermarkSnapshot,
         completion: @escaping (Result<UIImage, Error>) -> Void,
         onFinish: @escaping () -> Void) {
        self.snapshot = snapshot
        self.completion = completion
        self.onFinish = onFinish
    }

    private func deliver(_ result: Result<UIImage, Error>) {
        guard !delivered else { return }
        delivered = true
        DispatchQueue.main.async { self.completion(result) }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            deliver(.failure(error))
            DispatchQueue.main.async { self.onFinish() }
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let original = UIImage(data: data) else {
            let error = NSError(domain: "WatermarkCamera", code: -2,
                                userInfo: [NSLocalizedDescriptionKey: "无法读取照片数据"])
            deliver(.failure(error))
            DispatchQueue.main.async { self.onFinish() }
            return
        }

        // 水印合成放到回调线程执行，不阻塞主线程。
        let watermarked = WatermarkRenderer.render(image: original, snapshot: snapshot)
        deliver(.success(watermarked))
        DispatchQueue.main.async { self.onFinish() }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCapturingPhotoWith settings: AVCapturePhotoSettings) {
        // 某些机型在 didFinishProcessingPhoto 之后才会关闭 torch，这里再恢复一次。
        DispatchQueue.main.async { self.onFinish() }
    }
}
