#import <Foundation/Foundation.h>

static inline BOOL TPHasStageSwitcherCoupling(void) {
    NSInteger major = NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
    return major >= 16 && major <= 18;
}

BOOL TPBeginStageSwitcherWrite(NSString *key, id value);
void TPEndStageSwitcherWrite(void);
void TPReconcileStageSwitcherPolicy(NSString *changedKey);
BOOL TPStoredStageManagerEnabled(void);
BOOL TPStorediPadSwitcherEnabled(void);
BOOL TPStageSwitcherNeedsRespring(void);
void TPStageSwitcherAppliedAtBoot(BOOL iPadSwitcher);
