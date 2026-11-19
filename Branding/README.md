# MouseEasy 图标

图标为本项目原创的双条滑动轨迹与短划，采用松绿底、浅薄荷及暖象牙色；不使用鼠标外形、箭头或其他应用的图形素材。源图为 [WheelEase.svg](WheelEase.svg)，生成脚本直接读取此 SVG 的几何与颜色，修改后运行：

```sh
swift -module-cache-path /tmp/wheelease-icon-module-cache \
  -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
  Scripts/GenerateWheelEaseIcon.swift
```

`Generated/WheelEase.icns` 用作应用图标；`Generated/WheelEaseMenuIcon.pdf` 是菜单栏用的彩色矢量图，使用独立松绿底以适配浅色和深色菜单栏。脚本同时更新 `LinearMouse/Assets.xcassets/WheelEase.appiconset` 中的标准十种尺寸和清单，供普通 Xcode 构建使用。PNG 与 iconset 是同一源图的导出产物。图形与脚本均采用项目的 MIT 许可证。

上面的 SDK 路径适配本机命令行工具；在其他开发环境中可替换为对应的 macOS SDK。
