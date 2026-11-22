# 极速水印相机（iOS 原生）

一款为送货拍照设计的极简相机：打开即取景、后置主摄常亮手电筒、左下角可编辑时间/备注水印、一次快门自动保存到系统相册并立即继续拍摄。

**双界面联动**：相机界面 + 配送路单排序界面。在路单里点「复制水印文案」，文案自动带入相机备注并切回相机，直接拍照——形成"排序→送达→拍照留证"的完整送货闭环。路单页完全离线可用（内置 xlsx 库），支持 App 内导入 Excel/CSV 路单。

> **只会自签、想要 IPA 文件？** 先看 [如何拿到 IPA 并自签安装.md](./如何拿到IPA并自签安装.md)。里面是用 GitHub 云端编译自动产出未签名 IPA 的完整傻瓜步骤，全程不用装 Xcode、不用 Mac。


- 技术栈：Swift 5 + SwiftUI + AVFoundation + PhotoKit + CoreGraphics
- 最低系统：iOS 16.0
- 目标设备：iPhone / iPad（摄像头功能以真机为准）
- 依赖：无第三方库
- Bundle ID：默认 `com.example.watermarkcamera`（可在 Xcode 中修改）

## 一、文件清单

```
WatermarkCamera/
├── WatermarkCamera.xcodeproj/
│   └── project.pbxproj
└── WatermarkCamera/
    ├── AppEntry.swift          # @main 入口，WindowGroup 直接进 CameraView，无启动页
    ├── CameraView.swift        # 主界面容器：相机/路单切换、联动、快门、保存反馈
    ├── CameraManager.swift     # AVCaptureSession / AVCapturePhotoOutput / torch 常亮 / 中断恢复
    ├── CameraPreview.swift     # AVCaptureVideoPreviewLayer 取景 + 点击对焦 + 横竖屏方向
    ├── WatermarkView.swift     # 时间/备注实时预览与原生编辑弹层
    ├── WatermarkRenderer.swift # 按原始照片分辨率合成水印（时间在上、备注在下，去重前缀）
    ├── PhotoSaveManager.swift  # PhotoKit addOnly 权限写入系统相册
    ├── SettingsStore.swift     # UserDefaults 保存备注、时间模式、自定义时间、手电筒强度
    ├── RouteView.swift         # WKWebView 加载本地路单 HTML + JS 桥接（文案带入备注/返回相机/文件导入）
    ├── RouteWeb/               # 内置网页资源（作为 folder reference 打包）
    │   ├── index.html          # 配送路单自动排序（离线版，含原生桥接）
    │   └── xlsx.full.min.js    # 内置 SheetJS，离线解析 Excel
    └── Info.plist              # 相机 / 相册添加 权限说明，屏幕方向，启动配置
```

## 一之二、双界面联动用法

1. 相机界面**左上角「路单」按钮** → 进入配送路单排序界面。
2. 路单界面点顶部导入区，从 iPhone 文件/微信里选 `.xlsx / .xls / .csv` 路单文件（App 内文件选择，无需网络）。
3. 路单按组团自动排好序。点某单的「水印文案」或「送达后自动备好下一单」→ 文案经桥接**自动填入相机备注，并切回相机界面**。
4. 相机界面确认备注无误，按快门拍照，水印（时间 + 该单文案）自动合成并保存到相册。
5. 路单界面顶部「📷 返回相机」可随时切回。

> 路单界面数据（路单、备注、送达进度）继续存在 HTML 自己的 localStorage 里，与 App 备注互相独立：路单负责"选哪一单"，相机负责"拍这一单"。

## 二、Xcode 打开与运行

1. 在 Mac 上安装 Xcode 14 或更高版本。
2. 双击 `WatermarkCamera.xcodeproj` 打开工程。
3. 选中 Target `WatermarkCamera` → `Signing & Capabilities`：
   - 勾选 **Automatically manage signing**。
   - 在 **Team** 中选择你自己的 Apple ID / 开发者团队。
   - 如需改 Bundle Identifier，请使用唯一值（例如 `com.yourname.watermarkcamera`）。
4. 在 Xcode 顶部设备下拉框选择一台**真实 iPhone**（相机与手电筒在模拟器上不可用）。
5. 点击 ▶ Run。首次安装会弹出相机权限与相册添加权限请求，选择「允许」。

> 工程内 `DEVELOPMENT_TEAM` 留空是刻意为之：打开后用你自己的团队签名即可。若要用命令行打包，可执行：
>
> ```bash
> xcodebuild -project WatermarkCamera.xcodeproj \
>   -scheme WatermarkCamera \
>   -configuration Release \
>   -destination 'generic/platform=iOS' \
>   DEVELOPMENT_TEAM=你的TEAMID \
>   PRODUCT_BUNDLE_IDENTIFIER=com.yourname.watermarkcamera \
>   archive -archivePath ./build/WatermarkCamera.xcarchive
> ```

## 三、真机安装步骤

1. 用数据线将 iPhone 连接到 Mac，在 iPhone 上点「信任此电脑」。
2. Xcode → `Window` → `Devices and Simulators`，确认设备已连接且处于开发者模式（iOS 16+ 需在「设置 → 隐私与安全性 → 开发者模式」开启）。
3. 选择该设备，点 Run，Xcode 会自动签名并安装。
4. 首次打开：允许相机权限、允许「添加照片」权限。之后打开不再弹引导。
5. 若使用免费 Apple ID 签名，应用 7 天后需重新用 Xcode 运行一次以续签。

## 四、功能实现说明

| 需求 | 实现位置 | 说明 |
| --- | --- | --- |
| 打开即取景，无启动页 | `AppEntry.swift` / `CameraView.swift` | `WindowGroup` 直接加载 `CameraView`；使用 `UILaunchScreen` 系统默认启动画面，无自定义动画/导航/登录 |
| 默认常亮手电筒 | `CameraManager.applyTorch` | `AVCaptureDevice.setTorchModeOn(level:)` 持续照明；`flashMode = .off` 避免闪光打断 |
| 拍照后 torch 不灭 | `PhotoCaptureDelegate` | 处理完成与拍摄完成两个回调均重新应用 torch，兼容部分机型拍照瞬间中断 |
| 后台/锁屏释放 | `appDidEnterBackground` / `appWillEnterForeground` | 后台停 session 并关 torch，回前台自动重建并开启；另处理 `AVCaptureSession.interruptionNotification` |
| 亮度可调 | `SettingsStore.torchPresets` + 手电筒按钮长按菜单 | 三档（0.35 / 0.65 / 1.0），实际亮度受 `AVCaptureDevice.maxAvailableTorchLevel` 限制，默认 0.65 |
| 水印时间 | `WatermarkRenderer.format` | `yyyy年MM月dd日 HH:mm:ss`，预览每秒刷新，拍照瞬间冻结为快照；自定义时间用原生 DatePicker + 秒选择 |
| 水印备注 | `WatermarkView.NoteEditorView` | 中文/英文/数字/标点，上限 100 字符，自动换行，UserDefaults 持久化，可清空；为空时照片不显示「备注：」 |
| 水印合成 | `WatermarkRenderer.render` | 按原始照片像素尺寸与方向绘制，左 3% / 下 4%，白色粗体时间 + 白色备注 + 深色阴影 + 半透明渐变 |
| 保存相册 | `PhotoSaveManager` | `PHPhotoLibrary.requestAuthorization(for: .addOnly)`，异步写入，不打开相册、不弹确认、不阻塞预览 |
| 连拍不错位 | `WatermarkSnapshot` | 每次快门立即生成独立快照，随该张照片一路传递到合成，异步不串扰 |
| 失败重试 | `CameraView.toastView` | 保存失败保留已合成图片，显示「重试保存」按钮；成功才播成功反馈 |
| 点击对焦 | `CameraPreview.handleTap` | `captureDevicePointConverted(fromLayerRect:)` 转为设备坐标，设置 focus/exposure 点为自动模式 |

## 五、验收测试清单

1. 打开 App 直接进入后置摄像头实时取景。
2. 首次授权后手电筒自动常亮；右上角按钮可关闭/再开启。
3. 拍照过程中 torch 保持连续照明，不被闪光打断。
4. 连拍多张后手电筒仍处于开启状态。
5. 左下角时间默认每秒自动更新。
6. 点击时间可修改日期、时、分、秒，并可「恢复当前时间」。
7. 点击备注可输入中文，输入后立即反映在实时预览。
8. 退出重进 App，上一次备注仍然保留。
9. 每次快门自动保存一张照片到系统相册（不弹确认、不打开相册）。
10. 相册中打开照片，左下角水印清晰存在、方向正确、无裁切。
11. 连拍多张，每张水印时间与备注均与当次快门一致。
12. 保存完成后仍停留在取景界面，可立即继续拍下一张。
13. 长按手电筒按钮可切换三档亮度；无手电筒的机型按钮隐藏但仍可拍照。
14. App 进入后台/锁屏后相机与手电筒释放，回前台自动恢复。
15. 无启动动画、广告、会员、登录、社交等冗余页面。

## 六、已知限制与兼容性说明

- **模拟器不支持相机/手电筒**：必须在真机验证；模拟器上会显示权限提示或黑屏。
- **torch 中断差异**：不同 iPhone 在静态拍照瞬间对 torch 的处理不同，代码已在两个回调中重复恢复；个别机型可能出现极短暂闪烁，不影响成像与保存。
- **高温/低电量**：系统可能限制 torch，`torchAvailable` 会变为 false，此时按钮状态更新但拍照完全可用。
- **自定义时间**：系统原生日期时间选择器不直接展示「秒」轮，已用独立秒数选择器补齐，可精确到秒。
- **水印位置**：实时预览中的水印是屏幕坐标展示，最终照片按照片实际尺寸等比例合成到左下 3% / 下 4%；因取景为 `resizeAspectFill`，两者在视觉上接近但不逐像素重合。
- **屏幕方向**：支持竖屏与左右横屏，取景层会随界面方向调整；水印依据 `UIImage` 方向摆正后合成，不会出现文字倒置。
- **照片格式**：使用 `AVCapturePhotoSettings` 默认的 JPEG 输出与 `.photo` 会话预设，保留原始分辨率，不采用视频截图方案。

## 七、隐私

无网络请求，不上传照片，不收集个人信息。仅使用相机、相册添加权限，备注与设置保存在本机 `UserDefaults`。
