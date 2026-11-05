# Changelog

## 2.0.8 — 2026-11-05

### 简体中文

- 修复 iOS 18 关闭 iPad 应用切换器后，Respring 可能进入安全模式的问题，保留台前调度与切换器联动。
- 更新 Discord 社区入口。

### English

- Fixed a possible Safe Mode after respring with iPad App Switcher disabled on iOS 18, while preserving Stage Manager switcher linking.
- Updated the Discord community link.

## 2.0.7 — 2026-11-04

### 简体中文

- 改善 iOS 16–18 的 iPhone 应用切换体验。
- iOS 16–18 台前调度自动开启 iPad 应用切换器；关闭该切换器会退出台前调度并选择分屏。切换器变更需 Respring。

### English

- Improved iPhone app switching on iOS 16–18.
- On iOS 16–18, Stage Manager enables iPad App Switcher; turning it off selects Split View. Respring to apply switcher changes.

## 2.0.3 — 2026-10-12

### English

- Support native iOS 26 Stage Manager and Windowed Apps, including resizing,
  strip-side controls and switcher mirroring.
- Add an independent iPad App Switcher option, enabled by default. Turning it
  off restores iPhone cards without disabling the native window modes.
- Replace forced app scaling with iOS-26-only **Allow Smaller Windows**, letting
  apps manage their layouts below the normal minimum size.
- Repair missing phone-switcher context queries and copied window-adapter state
  that could cause Safe Mode or freeze while removing the last card/returning Home.
- Add targeted recovery for a ready in-app Floating Dock when app-level policy denies
  its reveal gesture. Native hiding behavior and other policy levels are preserved.
- Add an alternative respring action and community/repository links, with all
  new Settings text localized in English, Simplified Chinese and Traditional Chinese.

### 简体中文

- 增加 iOS 26 原生 Stage Manager 和 Windowed Apps 支持，保留窗口调整、侧栏位置与切换器镜像控制。
- 增加独立 iPad App Switcher 开关，默认开启；关闭后使用 iPhone 卡片，不关闭原生多窗口模式。
- 将强制缩放改为仅限 iOS 26 的 Allow Smaller Windows，突破原生最小窗口尺寸后由 App 自行布局。
- 修复关闭 iPad 切换器后，清除最后一张卡片或返回桌面时可能触发的 Safe Mode／卡死。
- 增加已就绪悬浮 Dock 的应用层手势恢复，保留系统正常隐藏行为。
- 增加备用 Respring 按钮和社区／越狱源入口，并保留英、简中、繁中设置文本。

### Validation

Rootless iOS 26.1 vphone: observer-free cold start, card removal to empty,
Home/relaunch, resizing and covered-Dock reveal passed in both window modes.
The original iPad grid also passed after restoration. A user subsequently
reported that respring/Safe Mode symptoms were resolved; this is user feedback,
not a substitute for independently captured physical-device evidence.
Physical diagnostic records identified KillBackground13 intercepting the Dock
reveal query while the native controller allows gestures. The maintainer accepted
iOS 26 support for release and identified this as a tweak conflict. This does not
claim independent post-disable device validation or universal tweak compatibility.
Temporary Dock diagnostic controls and collection code are removed from 2.0.3.
RootHide and older systems retain build/source checks rather than equivalent
physical-device runtime coverage. Publication status is recorded in the release result.
