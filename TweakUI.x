#import "UIKitPrivate.h"
#import "TPKeyboardPolicy.h"
#import <objc/runtime.h>
#import <objc/message.h>
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
#import <roothide.h>
#endif

static BOOL trollPadEnabled = YES, enableiPadKeyboard = YES, forcePadKBIdiom = YES, showShortcutButtonsOnKeyboard;
static BOOL keyboardHooksInitialized;
static BOOL phoneHardware, keyboardReloadPending;

static UIUserInterfaceIdiom phoneKeyboardIdiom(UIUserInterfaceIdiom idiom) {
    return TPPhoneKeyboardIdiom(idiom, trollPadEnabled, enableiPadKeyboard, phoneHardware);
}

%group TPKeyboardIdiomHooks
// Unlock iPadOS keyboard
UIUserInterfaceIdiom UIKeyboardGetSafeDeviceIdiom();
%hookf(UIUserInterfaceIdiom, UIKeyboardGetSafeDeviceIdiom) {
    if (!enableiPadKeyboard) {
        return phoneKeyboardIdiom(%orig);
    }
    return forcePadKBIdiom ? UIUserInterfaceIdiomPad : %orig;
}
%end

%group TPPhoneKeyboardTraitsHooks
%hook UIKBScreenTraits
- (NSInteger)idiom {
    return phoneKeyboardIdiom(%orig);
}
%end
%end

%group TPiPadKeyboardHooks
// Allow UIHoverGestureRecognizer and pointer interaction on iPhone
%hook UIPointerInteraction
- (void)_updateInteractionIsEnabled {
    if (!enableiPadKeyboard) {
        %orig;
        return;
    }

    static Ivar observingPresentationNotificationIvar;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        observingPresentationNotificationIvar = class_getInstanceVariable(
            UIPointerInteraction.class,
            "_observingPresentationNotification"
        );
    });
    if (!observingPresentationNotificationIvar) {
        %orig;
        return;
    }

    UIView *view = self.view;
    BOOL enabled = self.enabled; // && view.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad
    for(id<_UIPointerInteractionDriver> driver in self.drivers) {
        driver.view = enabled ? view : nil;
    }
    // to keep it fast, ivar offset is cached for later direct access
    ptrdiff_t ivarOff = ivar_getOffset(observingPresentationNotificationIvar);

    BOOL *observingPresentationNotification = (BOOL *)((uint64_t)(__bridge void *)self + ivarOff);
    if(!enabled && *observingPresentationNotification) {
        [NSNotificationCenter.defaultCenter removeObserver:self name:UIPresentationControllerPresentationTransitionWillBeginNotification object:nil];
        *observingPresentationNotification = NO;
    }
}
%end

// Fix bottom padding
%hook UIKeyboardImpl
+ (UIEdgeInsets)deviceSpecificPaddingForInterfaceOrientation:(NSUInteger)arg1 inputMode:(id)arg2 {
    if (!enableiPadKeyboard) {
        return %orig;
    }
    forcePadKBIdiom = NO;
    UIEdgeInsets result = %orig;
    forcePadKBIdiom = YES;
    return result;
}
%end

// Fix bottom padding when floating
%hook UIKeyboardDockView
- (CGRect)bounds {
    CGRect bounds = %orig;
    if (!enableiPadKeyboard) {
        return bounds;
    }
    if (!UIDevice._hasHomeButton && UIKeyboardImpl.isFloating) {
        bounds.origin.y = -25;
    } else {
        bounds.origin.y = 0;
    }
    return bounds;
}
%end

%hook UISystemInputAssistantViewController
// Fix predictive bar not occupying entire area
- (CGFloat)_centerViewWidthForTraitCollection:(id)tc interfaceOrientation:(UIInterfaceOrientation)orientation {
    if (!enableiPadKeyboard) {
        return %orig;
    }
    forcePadKBIdiom = NO;
    NSInteger result = %orig;
    forcePadKBIdiom = YES;
    return result;
}

// Show assistant buttons when enabled
- (void)setInputAssistantButtonItemsForResponder:(id)item {
    if (!enableiPadKeyboard) {
        %orig;
        return;
    }
    forcePadKBIdiom = showShortcutButtonsOnKeyboard;
    %orig;
    forcePadKBIdiom = YES;
}
%end

%hook UIInputWindowControllerHosting
- (UIEdgeInsets)_inputViewPadding {
    UIEdgeInsets result = %orig;
    if (!enableiPadKeyboard) {
        return result;
    }
    if (!UIDevice._hasHomeButton && UIKeyboardImpl.isFloating) {
        result.bottom -= 25;
    }
    return result;
}
%end
%end

static BOOL keyboardBoolPreference(NSDictionary *prefs, NSString *key, BOOL defaultValue) {
    id value = prefs[key];
    if (value) return [value boolValue];
    Boolean keyExists = false;
    BOOL result = CFPreferencesGetAppBooleanValue((__bridge CFStringRef)key, CFSTR("com.kdt.trollpad"), &keyExists);
    return keyExists ? result : defaultValue;
}

static void loadPrefs() {
    NSString *path = @"/var/mobile/Library/Preferences/com.kdt.trollpad.plist";
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
    path = jbroot(path);
#endif
    // Sandboxed apps can receive an empty CFPreferences domain while
    // SpringBoard sees the saved values. Read the same shared plist first.
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
    CFPreferencesAppSynchronize(CFSTR("com.kdt.trollpad"));
    trollPadEnabled = keyboardBoolPreference(prefs, @"TPTrollPadEnabled", YES);
    enableiPadKeyboard = trollPadEnabled && keyboardBoolPreference(prefs, @"TPEnableiPadKeyboard", YES);
    showShortcutButtonsOnKeyboard = enableiPadKeyboard &&
        keyboardBoolPreference(prefs, @"TPShowShortcutButtonsOnKeyboard", NO);
}

static void initializeKeyboardHooksIfNeeded() {
    if (!enableiPadKeyboard || keyboardHooksInitialized) {
        return;
    }

    %init(TPiPadKeyboardHooks);
    keyboardHooksInitialized = YES;
}

static BOOL keyboardObjectGetter(id object, SEL selector) {
    Method method = object ? class_getInstanceMethod(object_getClass(object), selector) : NULL;
    return method && strcmp(method_getTypeEncoding(method), "@16@0:8") == 0;
}

static void reloadPhoneKeyboardIfNeeded(void) {
    if (!keyboardReloadPending || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    keyboardReloadPending = NO;
    Class cls = objc_getClass("UIKeyboardImpl");
    SEL active = @selector(activeInstance), delegate = @selector(delegateAsResponder);
    if (!keyboardObjectGetter(cls, active)) return;
    id keyboard = ((id (*)(id, SEL))objc_msgSend)(cls, active);
    if (!keyboardObjectGetter(keyboard, delegate)) return;
    id responder = ((id (*)(id, SEL))objc_msgSend)(keyboard, delegate);
    if ([responder isKindOfClass:UIResponder.class] && [responder isFirstResponder]) {
        [responder reloadInputViews];
    }
}

static void prefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL previousKeyboard = enableiPadKeyboard;
        BOOL previousMaster = trollPadEnabled;
        loadPrefs();
        initializeKeyboardHooksIfNeeded();
        if (phoneHardware && (previousKeyboard != enableiPadKeyboard || previousMaster != trollPadEnabled)) keyboardReloadPending = YES;
        reloadPhoneKeyboardIfNeeded();
    });
}

%ctor {
    NSString *model = UIDevice.currentDevice.model;
    phoneHardware = [model isEqualToString:@"iPhone"] || [model isEqualToString:@"iPod touch"];
    loadPrefs();
    // The disabled-at-startup path also needs idiom restoration. Keep the
    // existing iPad-only visual/pointer hooks lazy and guarded by their option.
    %init(TPKeyboardIdiomHooks);
    if (phoneHardware) {
        Method idiom = class_getInstanceMethod(objc_getClass("UIKBScreenTraits"), @selector(idiom));
        if (idiom && strcmp(method_getTypeEncoding(idiom), "q16@0:8") == 0) {
            %init(TPPhoneKeyboardTraitsHooks);
        }
    }
    initializeKeyboardHooksIfNeeded();
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
            reloadPhoneKeyboardIfNeeded();
        }];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, prefsChanged, CFSTR("com.kdt.trollpad/saved"), NULL, CFNotificationSuspensionBehaviorCoalesce);
}
