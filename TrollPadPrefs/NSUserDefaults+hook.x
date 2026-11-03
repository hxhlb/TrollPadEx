#import <Foundation/Foundation.h>
#import "../TPStageSwitcherPolicy.h"

static BOOL trollPadDefaultsHookEnabled;

static void loadTrollPadDefaultsHookEnabled(void) {
    Boolean keyExists = false;
    CFPreferencesAppSynchronize(CFSTR("com.kdt.trollpad"));
    trollPadDefaultsHookEnabled = CFPreferencesGetAppBooleanValue(
        CFSTR("TPTrollPadEnabled"), CFSTR("com.kdt.trollpad"), &keyExists);
    if (!keyExists) {
        trollPadDefaultsHookEnabled = YES;
    }
}

static void trollPadDefaultsPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    loadTrollPadDefaultsHookEnabled();
    TPReconcileStageSwitcherPolicy(nil);
}

static BOOL shouldRedirectChamoisKey(NSString *key) {
    return trollPadDefaultsHookEnabled && [key hasPrefix:@"SBChamois"] &&
        ![key isEqualToString:@"SBChamoisWindowingEnabled"];
}

static NSString *redirectedChamoisKey(NSString *key) {
    return [@"TP" stringByAppendingString:key];
}

static CFStringRef const TPPolicyDomain = CFSTR("com.apple.springboard");
static NSString *const TPPolicyPadKey = @"TPUseiPadAppSwitcher";
static NSString *const TPPolicyStageKey = @"SBChamoisWindowingEnabled";
static NSString *const TPPolicyPendingKey = @"TPStageSwitcherNeedsRespring";
static __thread NSUInteger TPPolicyWriteDepth;
static BOOL TPPolicyBootChoiceKnown, TPPolicyBootPad;

static BOOL TPPolicyRead(NSString *key, BOOL fallback) {
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, TPPolicyDomain));
    return value ? [value boolValue] : fallback;
}

static BOOL TPPolicyWrite(NSString *key, BOOL value, BOOL fallback) {
    if (TPPolicyRead(key, fallback) == value) return NO;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, value ? kCFBooleanTrue : kCFBooleanFalse, TPPolicyDomain);
    return YES;
}

static BOOL TPPolicyEnabled(void) {
    if (!TPHasStageSwitcherCoupling()) return NO;
    loadTrollPadDefaultsHookEnabled();
    return trollPadDefaultsHookEnabled;
}

BOOL TPStoredStageManagerEnabled(void) { return TPPolicyRead(TPPolicyStageKey, NO); }
BOOL TPStorediPadSwitcherEnabled(void) { return TPPolicyRead(TPPolicyPadKey, YES); }

static void TPPolicyNotify(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.kdt.trollpad/saved"), NULL, NULL, YES);
}

BOOL TPBeginStageSwitcherWrite(NSString *key, id value) {
    if (TPPolicyWriteDepth ||
        (![key isEqualToString:TPPolicyPadKey] && ![key isEqualToString:TPPolicyStageKey]) ||
        !TPPolicyEnabled()) return NO;
    TPPolicyWriteDepth++;
    if ([key isEqualToString:TPPolicyPadKey]) {
        BOOL enabled = value ? [value boolValue] : YES;
        if (!enabled) {
            // Persist Stage OFF before the phone-switcher choice can be observed.
            TPPolicyWrite(TPPolicyStageKey, NO, NO);
            TPPolicyWrite(@"SBMedusaMultitaskingEnabled", YES, NO);
        }
        BOOL restart = TPPolicyBootChoiceKnown ? enabled != TPPolicyBootPad : enabled != TPStorediPadSwitcherEnabled();
        if (restart) TPPolicyWrite(TPPolicyPendingKey, YES, NO);
    } else if ([value boolValue]) {
        if (!TPStorediPadSwitcherEnabled()) {
            TPPolicyWrite(TPPolicyPadKey, YES, YES);
            TPPolicyWrite(TPPolicyPendingKey, YES, NO);
        }
        TPPolicyWrite(@"SBMedusaMultitaskingEnabled", YES, NO);
    }
    // Other processes must see linked keys before the primary write/notification.
    CFPreferencesAppSynchronize(TPPolicyDomain);
    return YES;
}

void TPEndStageSwitcherWrite(void) {
    if (!TPPolicyWriteDepth) return;
    CFPreferencesAppSynchronize(TPPolicyDomain);
    TPPolicyWriteDepth--;
    TPPolicyNotify();
}

void TPReconcileStageSwitcherPolicy(NSString *changedKey) {
    if (TPPolicyWriteDepth || !TPPolicyEnabled()) return;
    CFPreferencesAppSynchronize(TPPolicyDomain);
    TPPolicyWriteDepth++;
    BOOL changed = NO;
    if ([changedKey isEqualToString:TPPolicyPadKey] && !TPStorediPadSwitcherEnabled()) {
        changed |= TPPolicyWrite(TPPolicyStageKey, NO, NO);
        changed |= TPPolicyWrite(@"SBMedusaMultitaskingEnabled", YES, NO);
    } else if (TPStoredStageManagerEnabled() && !TPStorediPadSwitcherEnabled()) {
        changed |= TPPolicyWrite(TPPolicyPadKey, YES, YES);
        changed |= TPPolicyWrite(TPPolicyPendingKey, YES, NO);
    }
    if (TPPolicyBootChoiceKnown) {
        changed |= TPPolicyWrite(TPPolicyPendingKey, TPStorediPadSwitcherEnabled() != TPPolicyBootPad, NO);
    }
    if (changed) CFPreferencesAppSynchronize(TPPolicyDomain);
    TPPolicyWriteDepth--;
    if (changed) TPPolicyNotify();
}

BOOL TPStageSwitcherNeedsRespring(void) {
    if (!TPPolicyEnabled()) return NO;
    CFPreferencesAppSynchronize(TPPolicyDomain);
    return TPPolicyRead(TPPolicyPendingKey, NO);
}

void TPStageSwitcherAppliedAtBoot(BOOL iPadSwitcher) {
    if (!TPHasStageSwitcherCoupling()) return;
    TPPolicyBootChoiceKnown = YES;
    TPPolicyBootPad = iPadSwitcher;
    TPPolicyWriteDepth++;
    TPPolicyWrite(TPPolicyPendingKey, NO, NO);
    CFPreferencesAppSynchronize(TPPolicyDomain);
    TPPolicyWriteDepth--;
}

static BOOL TPPolicyDomainMatches(CFStringRef applicationID) {
    if (!applicationID) return NO;
    return CFEqual(applicationID, TPPolicyDomain) ||
        (CFEqual(applicationID, kCFPreferencesCurrentApplication) &&
         [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]);
}

%group TPStageSwitcherWriteHooks
%hook NSUserDefaults
- (void)setBool:(BOOL)value forKey:(NSString *)key {
    BOOL linked = TPBeginStageSwitcherWrite(key, @(value));
    @try { %orig; }
    @finally { if (linked) { [self synchronize]; TPEndStageSwitcherWrite(); } }
}
- (void)setObject:(id)value forKey:(NSString *)key {
    BOOL linked = TPBeginStageSwitcherWrite(key, value);
    @try { %orig; }
    @finally { if (linked) { [self synchronize]; TPEndStageSwitcherWrite(); } }
}
%end
%hookf(void, CFPreferencesSetAppValue, CFStringRef key, CFPropertyListRef value, CFStringRef applicationID) {
    BOOL linked = TPPolicyDomainMatches(applicationID) &&
        TPBeginStageSwitcherWrite((__bridge NSString *)key, (__bridge id)value);
    @try { %orig; }
    @finally { if (linked) TPEndStageSwitcherWrite(); }
}
%hookf(void, CFPreferencesSetValue, CFStringRef key, CFPropertyListRef value, CFStringRef applicationID, CFStringRef user, CFStringRef host) {
    BOOL linked = TPPolicyDomainMatches(applicationID) &&
        user && CFEqual(user, kCFPreferencesCurrentUser) && host && CFEqual(host, kCFPreferencesAnyHost) &&
        TPBeginStageSwitcherWrite((__bridge NSString *)key, (__bridge id)value);
    @try { %orig; }
    @finally { if (linked) TPEndStageSwitcherWrite(); }
}
%end

// Hook this to avoid real keys from being set
%hook NSUserDefaults
- (void)setBool:(BOOL)value forKey:(NSString *)key {
    if ([key isEqualToString:@"SBChamoisHideDock"]) {
        // Never ever set this to YES, as it is known to respring loop
        %orig(NO, key);
    } else if (shouldRedirectChamoisKey(key)) {
        %orig(value, redirectedChamoisKey(key));
    } else {
        %orig;
    }
}

- (BOOL)boolForKey:(NSString *)key {
    if (shouldRedirectChamoisKey(key)) {
        return %orig(redirectedChamoisKey(key));
    } else {
        return %orig;
    }
}

- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)key options:(NSKeyValueObservingOptions)options context:(void *)context {
    if (shouldRedirectChamoisKey(key)) {
        %orig(observer, redirectedChamoisKey(key), options, context);
    } else {
        %orig;
    }
}

- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)key context:(void *)context {
    if (shouldRedirectChamoisKey(key)) {
        %orig(observer, redirectedChamoisKey(key), context);
    } else {
        %orig;
    }
}

- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)key {
    if (shouldRedirectChamoisKey(key)) {
        %orig(observer, redirectedChamoisKey(key));
    } else {
        %orig;
    }
}
%end

%ctor {
    loadTrollPadDefaultsHookEnabled();
    %init;
    if (TPHasStageSwitcherCoupling()) {
        %init(TPStageSwitcherWriteHooks);
        TPReconcileStageSwitcherPolicy(nil);
    }
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        trollPadDefaultsPrefsChanged, CFSTR("com.kdt.trollpad/saved"), NULL,
        CFNotificationSuspensionBehaviorCoalesce);
}
