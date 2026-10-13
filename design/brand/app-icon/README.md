# macOS 开发预览图标

2026-10-10，用户选择候选 03「极简青绿水滴」作为开发预览图标。三张候选原图继续完整保留。

[方形源稿](minimal-wave-master.png)由内置 image_gen 根据[候选 03](../icon-candidates/03-minimal-wave.png)导出，保留浅青绿圆角底板、深青水滴和浅青波浪，外围为透明背景。生成提示词完整保存于 [export-prompt.txt](export-prompt.txt)。源稿用于后续导出，不直接引用 Codex 的生成目录。

执行 `python3 scripts/export-macos-icon.py`，使用系统 sips / iconutil 导出 16、32、128、256、512 pt 的 1× / 2× 图像并打包为 [Aqmino.icns](../../../apps/macos/Resources/Aqmino.icns)。源稿与候选原图不会被脚本覆盖。

本地打包脚本和 Xcode 工程均复制该资源；Info.plist 的 CFBundleIconFile 指定 Aqmino.icns，供 macOS 显示应用及通知图标。打包时缺少图标会停止构建，避免再次产生没有应用图标的预览包。

正式分发前仍可继续校准图形、边缘和小尺寸表现；此选择先用于开发预览。
