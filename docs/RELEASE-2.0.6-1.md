# TrollPadEx 2.0.6-1

## 更新

- 调整 iOS 17 的 iPhone 应用切换器兼容处理，恢复 App 最小化与 Dock 图标的系统动画路径。

## Changes

- Adjusted iPhone App Switcher compatibility on iOS 17 to restore the system animation path for App minimization and Dock icons.

## Release scope and validation

The user requested publication of the current scope-test1 candidate as a `-1`
revision, with source committed. This release removes the Home-floor replacement
and permanent Deck injection, preserves the original foreground App gesture
driver, and retains explicit switcher transitions with a Home-only native
asynchronous surface-retention request. iOS 26, keyboard, Settings resources,
preference keys and Dock Library behavior are unchanged.

The host production-callback contracts pass the switcher lifecycle, Home/App
floor identity, App gesture delegation and cache-policy guards. Both formal
schemes are built and checked against the candidate before publication. No new
physical combined-animation acceptance is claimed for this release: the user
requested shipping the current candidate before that additional device test.
Local diagnostic tools, symbols and recordings are excluded from the packages.
Older APT versions are retained for rollback.
