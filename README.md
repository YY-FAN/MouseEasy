<p align="center"><img src="Branding/WheelEase.svg" width="96" height="96" alt="MouseEasy"></p>

# MouseEasy

[简体中文](#让鼠标按你的习惯工作) · [English](#english) · [下载 / Download](https://github.com/YY-FAN/MouseEasy/releases/latest)

**让 Mac 没有难用的鼠标。**

MouseEasy 基于 LinearMouse，为 **iPhone 镜像**增加了独立的滚轮设置：可以只在镜像窗口里调快滚动、缩短停滚后的滑行时间。普通刻度滚轮默认启用「流畅滚动」，两个侧键可以一键设为切换窗口和应用，换鼠标也能沿用这些设置。

Built on LinearMouse, MouseEasy adds dedicated wheel settings for **iPhone Mirroring**. You can scroll faster or shorten the glide after you stop turning the wheel in the mirrored window. It also smooths notched wheels by default, offers a window and app switching preset for side buttons, and lets you reuse those settings across mice.

## 让鼠标按你的习惯工作

- **单独调 iPhone 镜像。** 在「滚动 → iPhone 镜像」开启「使用镜像专用参数」。在「镜像滚动设置」选择平滑模式，就能分别调节速度、响应和收尾时间。
- **平滑滚轮，保留触控板手感。** 全新安装默认给普通刻度滚轮启用「流畅滚动」，纵向沿用系统方向。要反转鼠标滚轮，在「滚动」页切换方向即可。
- **让侧键切换窗口和应用。** 两个侧键都未绑定时，在「按钮」页套用「窗口切换」。短按 #3 切换当前应用的窗口，短按 #4 切换应用。点击操作名称可以直接换成其他动作。
- **换鼠标，接着用。** 把滚动和按键设置放在「所有鼠标」范围内。即使新鼠标没有侧键，也会继承滚动设置。还可以为某个应用单独调整手感。
- **微调指针和缩放。** 可以调整指针速度、加速度，也可以把 Ctrl＋滚轮设为缩放。

<img src="docs/mouseeasy-buttons.png" width="560" alt="MouseEasy 按钮设置。鼠标按钮 #3 切换当前应用窗口，#4 切换应用。">

## 下载与安装

MouseEasy 1.0 适用于 **Apple 芯片 Mac，macOS 12 或更高版本**，界面支持简体中文和英文。使用 iPhone 镜像另需满足 [Apple 的设备和系统要求](https://support.apple.com/zh-cn/120421)。

1. 在 [GitHub Releases](https://github.com/YY-FAN/MouseEasy/releases/latest) 的 **Assets** 中下载 `.dmg` 文件。
2. 打开 DMG，把 MouseEasy 拖入「应用程序」，推出磁盘映像，再从「应用程序」打开。升级时先退出旧版，再替换应用，原有配置会继续生效。
3. 此安装包采用临时签名，尚未经过 Apple 公证。若 macOS 提示无法验证开发者，请按 [Apple 的首次打开说明](https://support.apple.com/zh-cn/102445) 操作。启动后，按应用提示在系统设置中授予鼠标控制权限。

## 致谢与许可

MouseEasy 基于 [LinearMouse 0.13.0](https://github.com/linearmouse/linearmouse/tree/v0.13.0)，沿用其设备匹配、指针调节和按钮映射能力，并在此基础上开发了「流畅滚动」预设与 iPhone 镜像适配。感谢 LinearMouse 的贡献者，也感谢 Mos 在滚动手感上的启发。

MouseEasy 采用 [MIT 许可证](LICENSE)，安装包内附第三方许可声明。[开发与构建](docs/development.md)

## English

**Make every mouse feel at home on Mac.**

MouseEasy is an open-source macOS mouse utility built on LinearMouse. It gives iPhone Mirroring its own scrolling controls, smooths notched wheels out of the box, and lets you take your wheel and side-button settings from one mouse to the next.

### Make your mouse work the way you do

- **Tune the wheel for iPhone Mirroring.** Under **Scrolling → iPhone Mirroring**, turn on **Use mirroring settings**. Open **Mirroring scroll settings** and select smooth scrolling to adjust speed, responsiveness, and how long scrolling continues after you stop turning the wheel.
- **Smooth your wheel and keep your trackpad’s feel.** A fresh install enables the **Flow** preset for notched wheels and follows the system’s vertical scroll direction. To reverse your mouse wheel, change its direction under **Scrolling**.
- **Switch windows and apps with your side buttons.** If both side buttons are unassigned, choose **Use window switching preset** under **Buttons**. A short press on #3 cycles through windows of the current app, and #4 switches apps. Click either action name to choose a different one.
- **Take your settings to your next mouse.** Save wheel and button settings under **All mice**. A mouse without side buttons still inherits your scrolling preferences. You can also override the settings for individual apps.
- **Adjust the pointer and zoom.** Set pointer speed and acceleration, or assign zoom to Ctrl + scroll.

<img src="docs/mouseeasy-buttons.png" width="560" alt="MouseEasy’s Buttons pane, shown in Chinese. Button #3 switches windows in the current app, and #4 switches apps.">

### Download and install

MouseEasy 1.0 runs on **Apple silicon Macs with macOS 12 or later**. The interface is available in English and Simplified Chinese. iPhone Mirroring has its own [device and system requirements](https://support.apple.com/en-us/120421).

1. Download the `.dmg` file under **Assets** on [GitHub Releases](https://github.com/YY-FAN/MouseEasy/releases/latest).
2. Open the DMG, drag MouseEasy to **Applications**, eject the disk image, then open the app from **Applications**. When updating, quit MouseEasy before replacing it. Your existing settings carry over.
3. This build is ad hoc signed and has not been notarized by Apple. If macOS says it cannot verify the developer, follow [Apple’s first-launch instructions](https://support.apple.com/en-us/102445). Once MouseEasy opens, follow its prompt to grant mouse-control access in System Settings.

### Credits and license

MouseEasy builds on [LinearMouse 0.13.0](https://github.com/linearmouse/linearmouse/tree/v0.13.0), including its device matching, pointer controls, and button mapping. MouseEasy adds the Flow scrolling preset and dedicated iPhone Mirroring support. Thanks to the LinearMouse contributors, and to Mos for inspiring the scrolling feel.

MouseEasy is released under the [MIT License](LICENSE). The app includes third-party license notices. [Development and build guide (in Chinese)](docs/development.md)
