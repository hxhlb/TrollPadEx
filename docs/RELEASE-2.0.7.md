# TrollPadEx 2.0.7

The user accepted `2.0.6-2~stage-policy-test1` and requested a formal paired
release, source merge/submission and APT publication. The accepted implementation
is source `576d01b`, based on 2.0.5 plus the native-entry experiment. This merge
replaces the superseded 2.0.6/2.0.6-1 iOS 17 presentation/animation/cache repairs;
it does not accumulate them with the accepted policy. Historical release docs
remain, while tests tied only to the removed factories are superseded.

## Changes

- Improved iPhone app switching on iOS 16–18.
- On iOS 16–18, Stage Manager enables iPad App Switcher. Turning the switcher off
  exits Stage Manager and selects Split View. Respring applies stack changes.

Coupling is confined to iOS 16/17/18. iOS 15 retains its independent switcher
choice, and other systems including iOS 26 retain existing behavior. The root
and settings policy, keyboard and Dock code match the accepted candidate.
Formal package code/resources must match the accepted RootHide candidate; both
schemes receive package/signature-structure checks. These are not independent
cryptographic verification or additional real-device acceptance. Rootless and
other OS versions have not received the same new physical-device validation.
Older APT packages are retained for rollback. No automatic device operation.
