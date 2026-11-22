# 如何拿到 IPA 并自签安装（不用 Xcode、不用 Mac）

## 先说明一件事

我无法在当前这台 Windows 电脑上直接生成 IPA。原因很实在：

- IPA 不是压缩包改名，它是**编译产物**——里面的 `WatermarkCamera.app` 是真正的 arm64 二进制，必须由苹果的编译器（Xcode + iOS SDK）在 macOS 上编译出来。
- 这台机器没有 Xcode，也没有 macOS，所以我不能凭空造出一个能装的 IPA。给你一个改名假文件只会浪费你的时间。

**解决办法**：用 GitHub 免费提供的云端 Mac 帮你编译，你在网页上点几下，就能下载到未签名 IPA，然后用你会的自签工具签名安装。全程不需要你装 Xcode。

---

## 方案 A：GitHub 云端编译（推荐，全程网页操作）

### 第 1 步：建一个仓库

1. 打开 <https://github.com>，登录（没有账号就先注册，免费的）。
2. 点右上角 **`+`** → **New repository**。
3. Repository name 填：`watermark-camera`
4. 选 **Public**（公开仓库，macOS 编译免费额度最充足）。
5. **不要**勾选 "Add a README file"、".gitignore"、"license"——保持空仓库。
6. 点 **Create repository**。

### 第 2 步：上传工程文件

1. 在刚建好的仓库页面，点 **"uploading an existing file"**（或 Add file → Upload files）。
2. 打开电脑上的 `WatermarkCamera` 文件夹，把**里面的所有内容**全选拖进去：
   - `README.md`
   - `WatermarkCamera.xcodeproj`（文件夹）
   - `WatermarkCamera`（文件夹）
   - `.github`（文件夹）← **务必包含，这是自动编译的配置**
   - `build-unsigned-ipa.sh`
3. 点 **Commit changes**。

> ⚠️ 如果漏传 `.github` 文件夹，第 3 步就看不到自动编译。Windows 上以点开头的文件夹可能被隐藏，上传前确认一下。

### 第 3 步：触发编译

1. 点仓库顶部的 **Actions** 标签。
2. 左侧列表点 **"自动编译未签名 IPA"**。
3. 右侧点 **Run workflow** → 再点绿色的 **Run workflow** 按钮。
4. 等 3～8 分钟（首次可能更久），刷新页面，出现绿色 ✔ 就是编译成功。
   - 如果是红色 ✘，点进去看日志，把报错内容发给我，我来修。

### 第 4 步：下载 IPA

1. 点进这次成功的运行记录。
2. 页面拉到最下面 **Artifacts** 区域，找到 **`WatermarkCamera-IPA-未签名`**，点击下载。
3. 下载到的是一个 zip，解压后得到 **`WatermarkCamera-unsigned.ipa`**。

这就是你要的 IPA 了，可以直接拿去自签。

---

## 方案 B：如果你身边有 Mac

把整个 `WatermarkCamera` 文件夹拷到 Mac 上，打开"终端"，执行：

```bash
cd 文件夹路径/WatermarkCamera
chmod +x build-unsigned-ipa.sh
./build-unsigned-ipa.sh
```

跑完会在同目录生成 `WatermarkCamera-unsigned.ipa`。不需要 Xcode 界面，不需要开发者账号。

---

## 拿到 IPA 后：自签安装（以 Windows + Sideloadly 为例）

任何自签工具（Sideloadly / AltStore / 爱思助手）都接受**未签名 IPA**——它们会用自己的证书重新签名，所以 IPA 未签名是正常的，不是坏了。

1. 下载安装 **Sideloadly**：<https://sideloadly.io>（选 Windows 版）。它依赖 iTunes 的驱动，若提示缺驱动就先装 iTunes。
2. iPhone 数据线连电脑，手机上点 **信任此电脑**，并解锁屏幕。
3. 打开 Sideloadly：
   - 上方框里拖入 `WatermarkCamera-unsigned.ipa`（或点 Browse 选它）。
   - **Apple ID** 填你的苹果账号（**建议注册一个小号专门用来签**，别用有重要数据的主账号）。
4. 点 **Start**。
5. 首次会要求输入 Apple ID 密码。若开了两步验证，需要去 <https://appleid.apple.com> → 安全 → 生成 **App 专用密码**，用那个密码填进去。
6. 等待显示 **Done / Installed**。
7. 手机上：**设置 → 通用 → VPN与设备管理**（旧系统叫"描述文件与设备管理"）→ 点你的 Apple ID → **信任**。
8. 回桌面打开「极速水印相机」，允许相机和相册权限即可使用。

> 免费 Apple ID 签名有效期 **7 天**。到期后 App 打不开，不用重新编译 IPA——把手机连上电脑，在 Sideloadly 里再点一次 Start 重签即可。

---

## 常见问题

**Actions 页面空白 / 没有"自动编译未签名 IPA"**
仓库必须是 Public，且要包含 `.github/workflows/build-ipa.yml`。检查分支名是不是 `main` 或 `master`。

**编译红叉失败**
点进运行记录看日志，把红色报错文字复制发给我，我改配置。

**Sideloadly 报 "Failed to install" / "Could not find device"**
确认手机已解锁、点了"信任此电脑"、iTunes 驱动已装、数据线能传数据（不是只能充电的线）。

**IPA 打开显示"未签名"，是不是坏了？**
不是。这正是给自签工具用的标准输入，签名由 Sideloadly 等工具完成。

**能不能不要自签，直接装？**
可以，但那需要你的开发者证书参与编译（Mac + Xcode 直接连手机 Run），跟"自签 IPA"是两条路。按上面走最省事。
