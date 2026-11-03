# TrollPadEx 2.0.6

## 更新

- 修复 iOS 17 关闭 iPad 应用切换器后仍显示网格的问题，恢复 iPhone 卡片与切换动画。
- 修复 iOS 17 切换器停留后重新进入时的预览异常与模糊跳变，改善重复切换稳定性。

## Changes

- Fixed iOS 17 continuing to show a grid after disabling iPad App Switcher, restoring iPhone cards and transitions.
- Fixed preview glitches and blur jumps when reopening the switcher after a pause on iOS 17, with improved repeated-switching stability.

## Validation boundary

The user accepted the latest test5 candidate on iPhone 15 Pro / iOS 17.3.1
RootHide and authorized release. Host contracts exercise the production factory,
floor lifecycle, idle Home/Deck pairing, gesture and transition callbacks with
fixtures, including default/master/ABI and OS boundaries. Those contracts are
not execution of other iOS versions' SpringBoard UI.

The production repair remains limited to the iOS 17 Main root and preserves
the existing iOS 26 implementation. Settings resources and preference keys are
unchanged. No diagnostic probes or recordings are packaged. Earlier versions
are retained in the APT repository for rollback.
