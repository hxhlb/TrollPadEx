# TrollPadEx 2.0.4

## 更新

- 修复关闭 iPad 键盘后，部分 App 仍使用全键盘、无法选择系统中文九宫格的问题。
- 改善键盘设置在 App 中的生效与刷新。

## Changes

- Fixed some apps continuing to use a full keyboard and hiding the system Chinese 9-Key option after the iPad keyboard was disabled.
- Improved how keyboard settings apply and refresh in apps.

## Validation

- iPhone 15 Pro, iOS 17.3.1, RootHide: user confirmed portrait Safari nine-key
  restored with the iPad keyboard option off. Runtime state agreed with the
  saved setting in Safari, Preferences, and SpringBoard.
- Isolated production-callback regression tests cover startup off/on,
  inaccessible CFPreferences with a shared settings snapshot, saved false,
  missing-key defaults, master off, real iPad, and other idioms.
- Other physical OS versions, Messages, and orientation changes are not covered
  by this device acceptance result.
- The separate Dock Library candidate is excluded. No diagnostic probes are
  included in the release packages. Existing keyboard selection and settings
  resources remain unchanged.
