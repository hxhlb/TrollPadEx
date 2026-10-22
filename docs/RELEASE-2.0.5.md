# TrollPadEx 2.0.5

## 更新

- 修复关闭 iPad 键盘后部分 App 无法选择系统中文九宫格的问题，改善键盘设置生效。
- 改善关闭 Dock 中 App 资源库入口的行为。

## Changes

- Fixed the system Chinese 9-Key option being unavailable in some apps after disabling the iPad keyboard, and improved keyboard settings application.
- Improved hiding the App Library entry when its Dock option is turned off.

## Scope and validation

Combines the phone keyboard fix from 2.0.4 with the separately developed Dock
Library restriction. The master-off and option-on cases preserve native Dock
behavior. Option-off restricts native enabled/visible requests without forcing
the Dock to appear or rebuilding it. The existing respring requirement remains.

Keyboard acceptance: portrait Safari on iPhone 15 Pro / iOS 17.3.1 RootHide.
The user's Dock switch check was performed on keyboard-test2, which did not
include the additional Dock hooks; it verifies existing native behavior only.
The additional Dock restriction has host callback/observer contract coverage,
not physical rendering acceptance. No diagnostic probes are packaged.

Version 2.0.4 had already reached the APT repository when the scope expanded;
2.0.5 preserves that published artifact and does not overwrite it.
