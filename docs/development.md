# 开发与构建

## 本地构建

在 Apple 芯片 Mac 上安装 Xcode 或命令行工具，然后在项目目录运行以下命令。

```sh
Scripts/LocalBuild
```

执行 `python3 Scripts/PackageDMG.py --output-dir build/github` 可在 `build/github/` 生成 DMG 和中英文下载说明。脚本会只读挂载安装包，核对固定安装路径、应用版本、图标、签名和磁盘内安装包的完整性。

产物为 `build/MouseEasy.pkg`，安装器始终更新 `/Applications/MouseEasy.app`。构建 37 起，分发的 DMG 里也只放这个安装包。请使用预览包调试界面，避免以正式版身份启动构建目录中的副本。当前本地构建面向 Apple Silicon。构建脚本编译本地 Swift 源码，按上游锁定版本获取依赖，并复用官方 MIT 发布包中已编译的界面资源。基础代码与官方界面资源取自 LinearMouse 0.13.0；资源、依赖和构建产物不进入 Git。

当前使用独立应用标识 `io.github.yyfan.MouseWorkbench.dev`。设置保存在 `~/Library/Application Support/MouseWorkbenchDev/settings.json`，与原版 LinearMouse、Mos 分开。首次运行请按提示授权设备控制。在「通用」中可导入或导出 JSON 配置。导入时，应用会先备份当前配置。

## 预览设置界面

运行 `Scripts/LocalBuild --preview` 后打开 `build/MouseEasy Preview.app`。预览包使用独立应用标识和示例配置，可以测试开关、按钮动作菜单、模拟录制及页面切换。预览时的改动在退出后丢弃，实际滚轮和侧键功能通过正式包验收。

## 验证

```sh
Scripts/validate-local-core.zsh
Scripts/validate-iphone-mirroring-scroll.zsh
python3 Scripts/validate-smoothing-core.py
Scripts/validate-keyboard-bindings.zsh
Scripts/validate-key-layout-threading.zsh
Scripts/validate-scroll-hotkeys.zsh
Scripts/validate-json-comments.zsh
Scripts/validate-common-actions.zsh
python3 Scripts/validate-mirroring-smoothing.py
python3 Scripts/validate-portable-mouse-defaults.py
npm run generate:json-schema
```

核心验证只构造事件和运行纯逻辑，不向真实应用发送输入。当前结果及真实设备验收见[功能与验收](功能与验收.md)。

## 许可与来源

上游没有明确许可声明的 JSONPatcher 已从构建和工程依赖移除，配置注释与尾随逗号由独立实现解析。

项目继续采用 [MIT 许可证](../LICENSE)，保留 LinearMouse 及各依赖的版权、许可声明。独立新增代码采用 MIT。源代码中的 Apple、Sindre Sorhus 等第三方声明继续保留；打包时附带第三方许可证。

MouseEasy 的项目地址为 `YY-FAN/MouseEasy`。维护者可运行 `python3 Scripts/LinkRepository.py YY-FAN/MouseEasy` 同步本地 `origin` 和应用内的「源码与许可」入口。`upstream` 用于跟踪 LinearMouse。

打赏的 PayPal 邮箱和主页在 [ProjectLinks.plist](../LinearMouse/ProjectLinks.plist) 的 `paypalAccount` 与 `paypal` 字段维护。弹窗显示打开 PayPal 按钮、邮箱复制按钮和感谢语。

应用及菜单栏图标独立绘制，几何与颜色统一维护在 [WheelEase.svg](../Branding/WheelEase.svg)，[生成脚本](../Scripts/GenerateWheelEaseIcon.swift) 同步输出 ICNS、彩色菜单栏图标及 Xcode 图标集。发布包使用临时签名，用户可从项目的 GitHub Releases 下载更新。
