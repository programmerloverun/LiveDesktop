# 小雷壁纸 (XiaoLeiWallpaper)

把 MP4 视频设为 Mac 桌面壁纸，支持多显示器、随机切换。

## 效果展示

![主界面](docs/screenshot.png)

### 演示视频

<video src="https://github.com/programmerloverun/XiaoLeiWallpaper/raw/main/docs/demo.mp4" controls width="100%"></video>

[下载演示视频](docs/demo.mp4)

- **视频桌面壁纸**：将任意 MP4 视频设为桌面壁纸，静音循环播放
- **多显示器支持**：所有外接屏幕同步显示，插拔显示器自动适配
- **壁纸库**：上传管理多个视频壁纸，一键切换
- **随机切换**：支持定时随机切换（1 分钟 / 5 分钟 / 15 分钟 / 30 分钟 / 1 小时）
- **自动恢复**：睡眠唤醒、解锁后自动恢复播放
- **资源优化**：限制视频码率、显示器休眠自动暂停，减少 CPU/GPU 占用

## 系统要求

- macOS 13+
- Swift 5.9

## 下载安装

从 [Releases](https://github.com/programmerloverun/XiaoLeiWallpaper/releases) 下载最新 DMG，拖入 `/Applications` 即可。

首次打开时，如果系统提示「无法验证开发者」，请到 **系统设置 → 隐私与安全性** 中点击「仍要打开」。

## 构建

```bash
# 仅构建（未签名）
make app

# 输出：.build/小雷壁纸.app
```

## 技术实现

- **SwiftUI + AppKit**：界面用 SwiftUI，壁纸引擎用 AppKit（`NSWindow` + `AVPlayerLayer`）
- **窗口层级**：`CGWindowLevelForKey(.desktopIconWindow) - 1`，位于桌面图标下方
- **热切换**：使用 `AVPlayer.replaceCurrentItem` 替换视频，无需销毁重建窗口
- **多屏**：共享 `AVPlayer`，每个屏幕独立 `AVPlayerLayer`
- **节能**：`preferredPeakBitRate = 4Mbps`，显示器休眠时暂停播放

## 许可

MIT License — 详见 [LICENSE](LICENSE)
