import SwiftUI
import UIKit

/// 主界面：相机 + 路单排序两个视图，可互相切换并联动。
/// 路单里复制的水印文案会自动带入相机备注，形成送货拍照闭环。
struct CameraView: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var settings = SettingsStore()

    @State private var now = Date()
    @State private var toast: String?
    @State private var failedImage: UIImage?
    @State private var showRoute = false   // false=相机, true=路单

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var displayTime: String {
        WatermarkRenderer.format(settings.timeMode == .current ? now : settings.customDate)
    }

    var body: some View {
        ZStack {
            // 相机界面常驻：切换路单时不销毁相机，手电筒与会话保持原状
            cameraScreen
                .opacity(showRoute ? 0 : 1)
                .allowsHitTesting(!showRoute)

            // 路单界面常驻：保留 WKWebView 实例，返回时滚动位置与表单状态不丢失
            RouteView(
                onNoteCopied: { text in
                    settings.note = text
                    showRoute = false
                    showToast("已带入相机备注")
                },
                onBackToCamera: {
                    showRoute = false
                },
                onToggleTorch: {
                    camera.toggleTorch()
                },
                torchOn: camera.isTorchOn,
                torchSupported: camera.torchSupported
            )
            .ignoresSafeArea()
            .opacity(showRoute ? 1 : 0)
            .allowsHitTesting(showRoute)

            if let toast {
                toastView(text: toast)
            }
        }
        .onReceive(timer) { now = $0 }
    }

    // MARK: - 相机界面

    private var cameraScreen: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.access == .authorized {
                CameraPreview(session: camera.session) { point in
                    camera.focus(at: point)
                }
                .ignoresSafeArea()
            }

            if camera.access == .denied {
                permissionView
            } else if camera.access == .authorized {
                controls
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .onAppear {
            camera.updateTorchLevel(settings.torchLevel)
            camera.start()
        }
        .onChange(of: settings.torchLevel) { newValue in
            camera.updateTorchLevel(newValue)
        }
    }

    // MARK: - 控件层

    private var controls: some View {
        VStack(spacing: 0) {
            HStack {
                routeButton
                Spacer()
                torchButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Spacer(minLength: 0)

            HStack(alignment: .bottom) {
                WatermarkOverlay(settings: settings, timeText: displayTime)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 18)

            HStack {
                Spacer()
                shutterButton
                Spacer()
            }
            .padding(.top, 14)
            .padding(.bottom, 34)
        }
    }

    /// 左上角入口：进入路单排序界面
    private var routeButton: some View {
        Button { showRoute = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "list.number")
                Text("路单")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Capsule().fill(Color.black.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var torchButton: some View {
        if camera.torchSupported {
            Button { camera.toggleTorch() } label: {
                Image(systemName: camera.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(camera.isTorchOn ? .yellow : .white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.black.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .contextMenu {
                ForEach(SettingsStore.torchPresets) { preset in
                    Button {
                        settings.torchLevel = preset.level
                    } label: {
                        Label(preset.name,
                              systemImage: settings.torchLevel == preset.level ? "checkmark" : "sun.max")
                    }
                }
            }
        }
    }

    private var shutterButton: some View {
        Button { takePhoto() } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 3)
                    .frame(width: 92, height: 92)
                Circle()
                    .fill(Color.white)
                    .frame(width: 78, height: 78)
            }
            .shadow(radius: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 拍照与保存

    private func takePhoto() {
        // 在快门按下的这一刻冻结时间与备注，防止异步处理串照片。
        let snapshot = WatermarkSnapshot(
            timeText: displayTime,
            note: settings.note.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        camera.capture(snapshot: snapshot) { result in
            switch result {
            case .success(let image):
                PhotoSaveManager.shared.save(image) { saveResult in
                    switch saveResult {
                    case .success:
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        failedImage = nil
                        showToast("已保存到相册")
                    case .failure(let error):
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                        failedImage = image
                        showToast("保存失败：\(error.localizedDescription)")
                    }
                }
            case .failure(let error):
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                showToast("拍照失败：\(error.localizedDescription)")
            }
        }
    }

    private func retrySave(_ image: UIImage) {
        PhotoSaveManager.shared.save(image) { result in
            switch result {
            case .success:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                failedImage = nil
                showToast("已保存到相册")
            case .failure(let error):
                showToast("仍然失败：\(error.localizedDescription)")
            }
        }
    }

    private func showToast(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if toast == text { toast = nil }
        }
    }

    private func toastView(text: String) -> some View {
        VStack(spacing: 8) {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.black.opacity(0.75)))

            if failedImage != nil {
                Button("重试保存") { retrySave(failedImage!) }
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.yellow)
            }
        }
        .padding(.bottom, 130)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.15), value: text)
    }

    // MARK: - 权限提示

    private var permissionView: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
                .foregroundColor(.white)
            Text("需要相机权限")
                .font(.headline)
                .foregroundColor(.white)
            Text("请在 设置 → 隐私与安全性 → 相机 中为本应用开启权限。")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            Button("打开系统设置") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(30)
    }
}
