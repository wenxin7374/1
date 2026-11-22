import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let onFocus: (CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.session = session
        uiView.onFocus = onFocus
    }
}

final class PreviewView: UIView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    var onFocus: ((CGPoint) -> Void)?

    var session: AVCaptureSession? {
        get { previewLayer.session }
        set {
            previewLayer.session = newValue
            previewLayer.videoGravity = .resizeAspectFill
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
        updateOrientation()
    }

    @objc private func orientationChanged() {
        updateOrientation()
    }

    private func updateOrientation() {
        guard let connection = previewLayer.connection,
              connection.isVideoOrientationSupported else { return }
        let raw = window?.windowScene?.interfaceOrientation.rawValue
            ?? UIInterfaceOrientation.portrait.rawValue
        if let orientation = AVCaptureVideoOrientation(rawValue: raw) {
            connection.videoOrientation = orientation
        }
    }

    @objc private func handleTap(_ tap: UITapGestureRecognizer) {
        let point = tap.location(in: self)
        let devicePoint: CGPoint
        if #available(iOS 18.0, *) {
            devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        } else {
            // iOS 16/17 上旧 API 已在新 SDK 移除声明，降级为中心对焦（不影响核心拍照功能）。
            devicePoint = CGPoint(x: 0.5, y: 0.5)
        }
        onFocus?(devicePoint)
    }
}
