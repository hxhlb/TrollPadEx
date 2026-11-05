#import <Foundation/Foundation.h>

static inline BOOL TPHasStageSwitcherCoupling(void) {
    NSInteger major = NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
    return major >= 16 && major <= 18;
}

static inline BOOL TPShouldHookStageSwitcherCFWrites(void) {
    NSInteger major = NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
    // Keep iOS 18 on settings transactions and defaults observation, without CF detours.
    return major >= 16 && major <= 17;
}

BOOL TPBeginStageSwitcherWrite(NSString *key, id value);
void TPEndStageSwitcherWrite(void);
void TPReconcileStageSwitcherPolicy(NSString *changedKey);
BOOL TPStoredStageManagerEnabled(void);
BOOL TPStorediPadSwitcherEnabled(void);
BOOL TPStageSwitcherNeedsRespring(void);
void TPStageSwitcherAppliedAtBoot(BOOL iPadSwitcher);
