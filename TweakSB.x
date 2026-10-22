#import <Foundation/Foundation.h>
#import <MobileGestalt/MobileGestalt.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import "SpringBoard.h"
#import "TPPrefsObserver.h"
#import "TPWindowScaling.h"
#import "TPDockLibrary.h"
#import "UIKitPrivate.h"

#include <assert.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <unistd.h>
#include <dispatch/dispatch.h>

// #define DEBUG_LOG_IDIOM
#ifdef DEBUG_LOG_IDIOM
@interface NSThread(private)
+ (NSString *)ams_symbolicatedCallStackSymbols;
@end
#endif

static TPPrefsObserver* pref;
static BOOL trollPadEnabled;
// Controller/gesture-manager changes are applied only after a respring.
static BOOL useiPadAppSwitcher;
static void TPRefreshWindowingGestures(void);
static id (*TPSettingForSelector)(Class, SEL);

static BOOL TPShouldHideDockLibrary(void) {
    return trollPadEnabled && pref && !pref.appLibraryInDockEnabled;
}

static void loadTrollPadEnabled() {
    Boolean keyExists = false;
    CFPreferencesAppSynchronize(CFSTR("com.kdt.trollpad"));
    trollPadEnabled = CFPreferencesGetAppBooleanValue(
        CFSTR("TPTrollPadEnabled"), CFSTR("com.kdt.trollpad"), &keyExists);
    if (!keyExists) {
        trollPadEnabled = YES;
    }
}

static void trollPadPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    loadTrollPadEnabled();
    if (@available(iOS 26.0, *)) {
        // Let TPPrefsObserver finish refreshing before rebuilding cached gesture edges.
        dispatch_async(dispatch_get_main_queue(), ^{
            TPRefreshWindowingGestures();
        });
    }
}

typedef NS_ENUM(NSInteger, TPStageManagerSide) {
    TPStageManagerSideLeft = 0,
    TPStageManagerSideRight = 1,
};

typedef struct {
    double leadingAlpha;
    double trailingAlpha;
} TPSwitcherGradientWallpaperAttributes;

// iOS 26's SBWindowingItemFrame contains a CGRect followed by four CGPoints.
typedef struct {
    CGRect frame;
    CGPoint components[4];
} TPWindowingItemFrame;

static BOOL isStageManagerEnabled() {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:@"SBChamoisWindowingEnabled"];
    return value ? [value boolValue] : NO;
}

static BOOL isMultitaskingActive() {
    if (!trollPadEnabled) {
        return NO;
    }
    if (@available(iOS 17.0, *)) {
        id medusa = [NSUserDefaults.standardUserDefaults objectForKey:@"SBMedusaMultitaskingEnabled"];
        BOOL medusaEnabled = medusa ? [medusa boolValue] : YES;
        return medusaEnabled || isStageManagerEnabled();
    }
    return YES;
}

static BOOL isStageManagerActive() {
    return trollPadEnabled && isStageManagerEnabled();
}

static BOOL isWindowingActive() {
    if (@available(iOS 26.0, *)) {
        return isMultitaskingActive();
    }
    return isStageManagerActive();
}

static BOOL shouldUseRightStageManagerSide() {
    return isStageManagerActive() && pref.stageManagerSide == TPStageManagerSideRight;
}

static BOOL shouldScaleAppWindows(void) {
    return pref.scaleAppWindows && isWindowingActive();
}

static BOOL shouldMirrorAppSwitcher() {
    return trollPadEnabled && useiPadAppSwitcher && pref.mirrorAppSwitcher;
}

static BOOL isContinuousExposeObject(id object) {
    return [NSStringFromClass(object_getClass(object)) containsString:@"ContinuousExpose"];
}

static BOOL isStageManagerAppSwitcherObject(id object) {
    NSString *className = NSStringFromClass(object_getClass(object));
    return [className isEqualToString:@"SBAppSwitcherContinuousExposeSwitcherModifier"] ||
        [className isEqualToString:@"SBContinuousExposeHomeGestureSwitcherModifier"] ||
        [className isEqualToString:@"SBContinuousExposeSwitcherToAppModifier"] ||
        [className isEqualToString:@"SBContinuousExposeToHomeSwitcherModifier"] ||
        [className isEqualToString:@"SBHomeToGridSwitcherModifier"];
}

static BOOL shouldForceStageManagerRightToLeft(id object) {
    if (@available(iOS 26.0, *)) {
        NSString *className = NSStringFromClass(object_getClass(object));
        if ([className isEqualToString:@"SBStripLayoutWindowingModifier"]) {
            return shouldUseRightStageManagerSide();
        }
        if ([className isEqualToString:@"SBFlexibleWindowingHomeGestureSwitcherModifier"] ||
            [className isEqualToString:@"SBExposeWindowingModifier"] ||
            [className isEqualToString:@"SBFlexibleWindowingToAppExposeWindowingModifier"] ||
            [className isEqualToString:@"SBFlexibleWindowingExposeToHomePeekWindowingModifier"]) {
            return shouldMirrorAppSwitcher();
        }
    }
    if (isStageManagerAppSwitcherObject(object)) {
        return shouldMirrorAppSwitcher();
    }
    return isContinuousExposeObject(object) && shouldUseRightStageManagerSide();
}

static __thread NSUInteger forceStageManagerRightToLeft = 0;
static NSHashTable *windowingGestureManagers;
static NSInteger lastWindowingGestureSide;
static BOOL lastWindowingGestureEnabled;

static void TPRegisterWindowingGestureManager(id manager) {
    if (!windowingGestureManagers) {
        windowingGestureManagers = [NSHashTable weakObjectsHashTable];
        lastWindowingGestureSide = pref.stageManagerSide;
        lastWindowingGestureEnabled = trollPadEnabled;
    }
    [windowingGestureManagers addObject:manager];
}

static void TPRefreshWindowingGestures(void) {
    if (!windowingGestureManagers ||
        (lastWindowingGestureSide == pref.stageManagerSide &&
         lastWindowingGestureEnabled == trollPadEnabled)) {
        return;
    }
    lastWindowingGestureSide = pref.stageManagerSide;
    lastWindowingGestureEnabled = trollPadEnabled;

    Ivar switcherIvar = class_getInstanceVariable(
        objc_getClass("SBFluidSwitcherGestureManager"), "_switcherController");
    if (!switcherIvar) {
        return;
    }
    for (id manager in windowingGestureManagers.allObjects) {
        id switcher = object_getIvar(manager, switcherIvar);
        id context = [switcher valueForKey:@"windowManagementContext"];
        if (!context) {
            continue;
        }
        ((void (*)(id, SEL))objc_msgSend)(manager,
            @selector(_tearDownFloatingApplicationGestureRecognizers));
        ((void (*)(id, SEL))objc_msgSend)(manager,
            @selector(_tearDownChamoisGestureRecognizers));
        ((void (*)(id, SEL, id))objc_msgSend)(manager,
            @selector(updateForWindowManagementContext:), context);
    }
}

#define TPBeginStageManagerRightToLeft() \
    BOOL tpShouldForceStageManagerRightToLeft = shouldForceStageManagerRightToLeft(self); \
    if (tpShouldForceStageManagerRightToLeft) { \
        forceStageManagerRightToLeft++; \
    }

#define TPEndStageManagerRightToLeft() \
    if (tpShouldForceStageManagerRightToLeft) { \
        forceStageManagerRightToLeft--; \
    }

static BOOL canInstallStageManagerSwitcherHook() {
    Class switcherControllerClass = objc_getClass("SBSwitcherController");

    return switcherControllerClass &&
        class_getInstanceMethod(switcherControllerClass, @selector(windowManagementStyle));
}

static BOOL canInstallInAppDockGestureHook(void) {
    const struct { const char *className; const char *selector; const char *types; } methods[] = {
        {"SBFluidSwitcherViewController", "isSoftwareKeyboardVisible", "B16@0:8"},
        {"SBWindowScene", "isMainDisplayWindowScene", "B16@0:8"},
        {"SBWindowScene", "switcherController", "@16@0:8"},
        {"SBSwitcherController", "isAnySwitcherVisible", "B16@0:8"},
        {"SBSwitcherController", "unlockedEnvironmentMode", "q16@0:8"},
        {"SBSwitcherController", "contentViewController", "@16@0:8"},
        {"SBFloatingDockController", "windowScene", "@16@0:8"},
        {"SBFloatingDockController", "isInvalidated", "B16@0:8"},
        {"SBFloatingDockController", "isFloatingDockPresented", "B16@0:8"},
        {"SBFloatingDockController", "activeAssertion", "@16@0:8"},
        {"SBFloatingDockController", "remoteContentManager", "@16@0:8"},
        {"SBFloatingDockRemoteContentManager", "isContentReady", "B16@0:8"},
        {"SBFloatingDockBehaviorAssertion", "level", "Q16@0:8"},
        {"SBFloatingDockBehaviorAssertion", "floatingDockController", "@16@0:8"},
        {"SBFloatingDockBehaviorAssertion", "gesturePossible", "B16@0:8"},
    };
    for (NSUInteger i = 0; i < sizeof(methods) / sizeof(methods[0]); i++) {
        Method method = class_getInstanceMethod(objc_getClass(methods[i].className),
            sel_registerName(methods[i].selector));
        if (!method || strcmp(method_getTypeEncoding(method), methods[i].types) != 0) return NO;
    }
    return YES;
}

static BOOL shouldRecoverInAppDockGesture(id assertion) {
    if (!isWindowingActive() || !pref.isFloatingDockSupported ||
        !UIApplication.sharedApplication.protectedDataAvailable) return NO;
    // Level 9 is app/switcher layout policy. Preserve every other policy level.
    if (!assertion || ((NSUInteger (*)(id, SEL))objc_msgSend)(assertion, @selector(level)) != 9) return NO;
    id dock = ((id (*)(id, SEL))objc_msgSend)(assertion, @selector(floatingDockController));
    if (!dock || ((BOOL (*)(id, SEL))objc_msgSend)(dock, @selector(isInvalidated)) ||
        ((BOOL (*)(id, SEL))objc_msgSend)(dock, @selector(isFloatingDockPresented))) return NO;
    if (((id (*)(id, SEL))objc_msgSend)(dock, @selector(activeAssertion)) != assertion) return NO;
    id scene = ((id (*)(id, SEL))objc_msgSend)(dock, @selector(windowScene));
    if (!scene || !((BOOL (*)(id, SEL))objc_msgSend)(scene, @selector(isMainDisplayWindowScene))) return NO;
    id switcher = ((id (*)(id, SEL))objc_msgSend)(scene, @selector(switcherController));
    // Native mode 3 is application. The content controller's environmentMode is a stub.
    if (!switcher || ((NSInteger (*)(id, SEL))objc_msgSend)(switcher, @selector(unlockedEnvironmentMode)) != 3 ||
        ((BOOL (*)(id, SEL))objc_msgSend)(switcher, @selector(isAnySwitcherVisible))) return NO;
    id content = ((id (*)(id, SEL))objc_msgSend)(switcher, @selector(contentViewController));
    if (![content isKindOfClass:objc_getClass("SBFluidSwitcherViewController")] ||
        ((BOOL (*)(id, SEL))objc_msgSend)(content, @selector(isSoftwareKeyboardVisible))) return NO;
    id remote = ((id (*)(id, SEL))objc_msgSend)(dock, @selector(remoteContentManager));
    return remote && ((BOOL (*)(id, SEL))objc_msgSend)(remote, @selector(isContentReady));
}

static id TPDeckOrganicExposeAppLayout(id self, SEL command) {
    // A deck has no organic App Expose pile. The native home gesture treats
    // nil as "no pile to reorder/filter", while retaining its normal elements.
    return nil;
}

@interface NSObject (TPPhoneWindowingAdapter)
- (instancetype)initWithSwitcherModifier:(id)modifier;
@end
static Class TPPhoneDeckWindowingClass;
static Class TPPhoneDeckClass;
static char TPPhoneDeckAssociation;

static id TPPhoneDeckWindowingCopy(id self, SEL command, NSZone *zone) NS_RETURNS_RETAINED;
static id TPPhoneDeckWindowingCopy(id self, SEL command, NSZone *zone) {
    // SBChainableModifier's default copy is alloc/init. Root adapters require
    // their designated initializer to rebuild the contained legacy query tree.
    id deck = [objc_getAssociatedObject(self, &TPPhoneDeckAssociation) copyWithZone:zone];
    id adapter = [[object_getClass(self) allocWithZone:zone] initWithSwitcherModifier:deck];
    objc_setAssociatedObject(adapter, &TPPhoneDeckAssociation, deck, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return adapter;
}

static id (*TPOriginalGridMultitaskingModifier)(id, SEL);
static id TPPhoneGridMultitaskingModifier(id self, SEL command) {
    id modifier = TPOriginalGridMultitaskingModifier(self, command);
    if (trollPadEnabled && !useiPadAppSwitcher &&
        object_getClass(self) == objc_getClass("SBHomeToGridSwitcherModifier") &&
        TPPhoneDeckWindowingClass && object_getClass(modifier) == TPPhoneDeckWindowingClass) {
        // The outer Expose transition needs the modern adapter. Its legacy Grid
        // child must temporarily attach only the Deck, not reparent the adapter.
        return objc_getAssociatedObject(modifier, &TPPhoneDeckAssociation) ?: modifier;
    }
    return modifier;
}

static id TPPhoneDeckView(id modifier) {
    Class windowing = objc_getClass("SBWindowingSwitcherPersonality");
    Class fluid = objc_getClass("SBFluidSwitcherPersonality");
    for (NSUInteger depth = 0; modifier && depth < 32; depth++) {
        if ((windowing && [modifier isKindOfClass:windowing]) ||
            (fluid && [modifier isKindOfClass:fluid])) {
            return ((id (*)(id, SEL))objc_msgSend)(modifier, @selector(view));
        }
        modifier = ((id (*)(id, SEL))objc_msgSend)(modifier, @selector(parentModifier));
    }
    return nil;
}

static id TPPhoneDeckObjectQuery(id self, SEL command) {
    return ((id (*)(id, SEL))objc_msgSend)(TPPhoneDeckView(self), command);
}

static CGPoint TPPhoneDeckPointQuery(id self, SEL command) {
    return ((CGPoint (*)(id, SEL))objc_msgSend)(TPPhoneDeckView(self), command);
}

static CGRect TPPhoneDeckRectQuery(id self, SEL command) {
    return ((CGRect (*)(id, SEL))objc_msgSend)(TPPhoneDeckView(self), command);
}

static BOOL TPPhoneDeckBoolQuery(id self, SEL command) {
    return ((BOOL (*)(id, SEL))objc_msgSend)(TPPhoneDeckView(self), command);
}

static CGFloat TPPhoneDeckFloatQuery(id self, SEL command) {
    return ((CGFloat (*)(id, SEL))objc_msgSend)(TPPhoneDeckView(self), command);
}

static NSInteger TPPhoneDeckIntegerQuery(id self, SEL command) {
    return ((NSInteger (*)(id, SEL))objc_msgSend)(TPPhoneDeckView(self), command);
}

static CGPoint TPPhoneDeckScrollablePointQuery(id self, SEL command, id modifier, CGPoint point) {
    return ((CGPoint (*)(id, SEL, id, CGPoint))objc_msgSend)(TPPhoneDeckView(self), command, modifier, point);
}

static id TPPhoneDeckInQueryChain(id modifier) {
    for (NSUInteger depth = 0; modifier && depth < 32; depth++) {
        if (TPPhoneDeckClass && object_getClass(modifier) == TPPhoneDeckClass) return modifier;
        modifier = ((id (*)(id, SEL))objc_msgSend)(modifier, @selector(nextQueryModifier));
    }
    return nil;
}

static id (*TPOriginalHomeFloorAppLayouts)(id, SEL);
static id TPPhoneHomeFloorAppLayouts(id self, SEL command) {
    if (trollPadEnabled && !useiPadAppSwitcher) {
        id deck = TPPhoneDeckInQueryChain(self);
        if (deck) return TPPhoneDeckObjectQuery(deck, command);
    }
    return TPOriginalHomeFloorAppLayouts(self, command);
}

static BOOL (*TPOriginalHomeFloorReduceMotion)(id, SEL);
static BOOL TPPhoneHomeFloorReduceMotion(id self, SEL command) {
    if (trollPadEnabled && !useiPadAppSwitcher) {
        id deck = TPPhoneDeckInQueryChain(self);
        if (deck) return TPPhoneDeckBoolQuery(deck, command);
    }
    return TPOriginalHomeFloorReduceMotion(self, command);
}

static void TPPreparePhoneSwitcherCompatibility(void) {
    Class deckClass = objc_getClass("SBDeckSwitcherModifier");
    SEL selector = NSSelectorFromString(@"organicExposeAppLayout");
    if (deckClass && !class_getInstanceMethod(deckClass, selector)) {
        class_addMethod(deckClass, selector, (IMP)TPDeckOrganicExposeAppLayout, "@16@0:8");
    }
    if (deckClass && !TPPhoneDeckClass) {
        if (@available(iOS 26.0, *)) {} else {
            TPPhoneDeckClass = deckClass;
            return;
        }
        // Native Deck methods request these content-view data queries. Temporary
        // modern transitions can drop the legacy context cache, so keep the
        // data source explicit without changing the Deck's layout algorithms.
        const struct { const char *selector; const char *types; IMP implementation; } queries[] = {
            {"appLayouts", "@16@0:8", (IMP)TPPhoneDeckObjectQuery},
            {"containerViewBounds", "{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8", (IMP)TPPhoneDeckRectQuery},
            {"displayCornerRadius", "d16@0:8", (IMP)TPPhoneDeckFloatQuery},
            {"homeGrabberSettings", "@16@0:8", (IMP)TPPhoneDeckObjectQuery},
            {"isRTLEnabled", "B16@0:8", (IMP)TPPhoneDeckBoolQuery},
            {"isReduceMotionEnabled", "B16@0:8", (IMP)TPPhoneDeckBoolQuery},
            {"isShowingSpotlightOrTodayView", "B16@0:8", (IMP)TPPhoneDeckBoolQuery},
            {"isSystemAssistantExperiencePersistentSiriEnabled", "B16@0:8", (IMP)TPPhoneDeckBoolQuery},
            {"screenScale", "d16@0:8", (IMP)TPPhoneDeckFloatQuery},
            {"scrollViewContentOffset", "{CGPoint=dd}16@0:8", (IMP)TPPhoneDeckPointQuery},
            {"scrollableQueryModifier:contentOffsetVelocityConsideringNextContentOffset:", "{CGPoint=dd}40@0:8@16{CGPoint=dd}24", (IMP)TPPhoneDeckScrollablePointQuery},
            {"scrollableQueryModifier:convertScrollViewPointToContainerViewCoordinateSpace:", "{CGPoint=dd}40@0:8@16{CGPoint=dd}24", (IMP)TPPhoneDeckScrollablePointQuery},
            {"switcherInterfaceOrientation", "q16@0:8", (IMP)TPPhoneDeckIntegerQuery},
            {"switcherSettings", "@16@0:8", (IMP)TPPhoneDeckObjectQuery},
            {"switcherViewBounds", "{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8", (IMP)TPPhoneDeckRectQuery},
        };
        for (NSUInteger i = 0; i < sizeof(queries) / sizeof(queries[0]); i++) {
            Method method = class_getInstanceMethod(objc_getClass("SBFluidSwitcherViewController"),
                sel_registerName(queries[i].selector));
            if (!method || strcmp(method_getTypeEncoding(method), queries[i].types) != 0) return;
        }
        TPPhoneDeckClass = objc_getClass("TPPhoneDeckSwitcherModifier");
        if (!TPPhoneDeckClass) {
            TPPhoneDeckClass = objc_allocateClassPair(deckClass, "TPPhoneDeckSwitcherModifier", 0);
            if (TPPhoneDeckClass) {
                for (NSUInteger i = 0; i < sizeof(queries) / sizeof(queries[0]); i++) {
                    class_addMethod(TPPhoneDeckClass, sel_registerName(queries[i].selector),
                        queries[i].implementation, queries[i].types);
                }
                objc_registerClassPair(TPPhoneDeckClass);
            }
        }
    }
    if (@available(iOS 26.0, *)) {
        // Home-floor completion queries use the legacy selector directly, while
        // the modern query cache excludes it. Preserve normal queries elsewhere.
        Class floorClass = objc_getClass("_SBHomeScreenFloorSwitcherModifier");
        Method layouts = class_getInstanceMethod(floorClass, @selector(appLayouts));
        if (TPPhoneDeckClass && !TPOriginalHomeFloorAppLayouts && layouts &&
            strcmp(method_getTypeEncoding(layouts), "@16@0:8") == 0) {
            MSHookMessageEx(floorClass, @selector(appLayouts), (IMP)TPPhoneHomeFloorAppLayouts,
                (IMP *)&TPOriginalHomeFloorAppLayouts);
        }
        Method motion = class_getInstanceMethod(floorClass, @selector(isReduceMotionEnabled));
        if (TPPhoneDeckClass && !TPOriginalHomeFloorReduceMotion && motion &&
            strcmp(method_getTypeEncoding(motion), "B16@0:8") == 0) {
            MSHookMessageEx(floorClass, @selector(isReduceMotionEnabled), (IMP)TPPhoneHomeFloorReduceMotion,
                (IMP *)&TPOriginalHomeFloorReduceMotion);
        }
        Class rootClass = objc_getClass("SBRootWindowingModifier");
        Method initializer = class_getInstanceMethod(rootClass, @selector(initWithSwitcherModifier:));
        Method copy = class_getInstanceMethod(rootClass, @selector(copyWithZone:));
        if (!rootClass || !initializer || strcmp(method_getTypeEncoding(initializer), "@24@0:8@16") != 0 ||
            !copy || strcmp(method_getTypeEncoding(copy), "@24@0:8^{_NSZone=}16") != 0) return;
        TPPhoneDeckWindowingClass = objc_getClass("TPPhoneDeckWindowingModifier");
        if (!TPPhoneDeckWindowingClass) {
            TPPhoneDeckWindowingClass = objc_allocateClassPair(rootClass, "TPPhoneDeckWindowingModifier", 0);
            if (TPPhoneDeckWindowingClass) {
                class_addMethod(TPPhoneDeckWindowingClass, selector, (IMP)TPDeckOrganicExposeAppLayout, "@16@0:8");
                class_addMethod(TPPhoneDeckWindowingClass, @selector(copyWithZone:),
                    (IMP)TPPhoneDeckWindowingCopy, "@24@0:8^{_NSZone=}16");
                objc_registerClassPair(TPPhoneDeckWindowingClass);
            }
        }
        Class gridClass = objc_getClass("SBHomeToGridSwitcherModifier");
        SEL multitasking = @selector(multitaskingModifier);
        Method getter = class_getInstanceMethod(gridClass, multitasking);
        if (TPPhoneDeckWindowingClass && !TPOriginalGridMultitaskingModifier && getter &&
            strcmp(method_getTypeEncoding(getter), "@16@0:8") == 0) {
            MSHookMessageEx(gridClass, multitasking, (IMP)TPPhoneGridMultitaskingModifier,
                (IMP *)&TPOriginalGridMultitaskingModifier);
        }
    }
}

static id (*TPOriginalContinuousExposeFactory)(id, SEL, id);
static id TPPhoneContinuousExposeFactory(id self, SEL command, id event) {
    id proposed = TPOriginalContinuousExposeFactory(self, command, event);
    if (!trollPadEnabled || useiPadAppSwitcher) return proposed;
    Class exposedClass = objc_getClass("SBExposeWindowingModifier");
    Class legacyExposedClass = objc_getClass("SBAppSwitcherContinuousExposeSwitcherModifier");
    if ((exposedClass && object_getClass(proposed) == exposedClass) ||
        (legacyExposedClass && object_getClass(proposed) == legacyExposedClass)) {
        TPPreparePhoneSwitcherCompatibility();
        if (!TPPhoneDeckClass) return proposed;
        id deck = [[TPPhoneDeckClass alloc] init];
        if (@available(iOS 26.0, *)) {
            // iOS 26.0.x still returns a legacy switcher for non-flexible
            // Stage Manager. Only modern windowing results need this adapter.
            if (exposedClass && object_getClass(proposed) == exposedClass) {
                if (!TPPhoneDeckWindowingClass) return proposed;
                id adapter = [[TPPhoneDeckWindowingClass alloc] initWithSwitcherModifier:deck];
                objc_setAssociatedObject(adapter, &TPPhoneDeckAssociation, deck, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                return adapter;
            }
        }
        return deck ?: proposed;
    }
    // The native factory returns its cached modifier on subsequent events.
    return proposed;
}

typedef id TPMainSwitcherFactoryFunction(id, SEL, NSInteger) NS_RETURNS_RETAINED;
static TPMainSwitcherFactoryFunction *TPOriginalMainSwitcherFactory;
static id TPPhoneMainSwitcherFactory(id self, SEL command, NSInteger mode) NS_RETURNS_RETAINED;
static id TPPhoneMainSwitcherFactory(id self, SEL command, NSInteger mode) {
    if (trollPadEnabled && !useiPadAppSwitcher && mode == 2) {
        TPPreparePhoneSwitcherCompatibility();
        if (TPPhoneDeckClass) return [[TPPhoneDeckClass alloc] init];
    }
    return TPOriginalMainSwitcherFactory(self, command, mode);
}

static BOOL canInstallStageManagerCapabilityHooks() {
    Class appSwitcherDefaultsClass = objc_getClass("SBAppSwitcherDefaults");
    Class applicationClass = objc_getClass("SBApplication");

    return appSwitcherDefaultsClass &&
        class_getInstanceMethod(appSwitcherDefaultsClass, @selector(medusaMultitaskingEnabled)) &&
        class_getInstanceMethod(appSwitcherDefaultsClass, @selector(chamoisWindowingEnabled)) &&
        applicationClass &&
        class_getInstanceMethod(applicationClass, @selector(supportsChamoisSceneResizing)) &&
        class_getInstanceMethod(applicationClass, @selector(supportsChamoisViewResizing)) &&
        class_getInstanceMethod(applicationClass, @selector(alwaysMaximizedInChamois));
}

static BOOL canInstallStageManagerSideHooks() {
    Class switcherModifierClass = objc_getClass("SBSwitcherModifier");
    Class stripModifierClass = objc_getClass("SBStripContinuousExposeSwitcherModifier");

    if (switcherModifierClass) {
        (void)[(id)switcherModifierClass class];
    }

    return switcherModifierClass &&
        class_getInstanceMethod(switcherModifierClass, @selector(isRTLEnabled)) &&
        stripModifierClass &&
        class_getInstanceMethod(stripModifierClass, @selector(_appStripOriginX)) &&
        class_getInstanceMethod(UIApplication.class, @selector(userInterfaceLayoutDirection));
}

static BOOL canInstallStageManagerSwitcherTransitionHooks() {
    Class switcherToAppModifierClass = objc_getClass("SBContinuousExposeSwitcherToAppModifier");

    return switcherToAppModifierClass &&
        class_getInstanceMethod(switcherToAppModifierClass, @selector(frameForIndex:)) &&
        class_getInstanceMethod(switcherToAppModifierClass, @selector(contentOffsetForIndex:alignment:));
}

static BOOL hasWindowingItemFrameMethod(Class modifierClass) {
    Method method = class_getInstanceMethod(modifierClass, @selector(frameForItem:));
    if (!method) {
        return NO;
    }
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:
        method_getTypeEncoding(method)];
    return signature.numberOfArguments == 3 &&
        signature.methodReturnType[0] == '{' &&
        signature.methodReturnLength == sizeof(TPWindowingItemFrame) &&
        [signature getArgumentTypeAtIndex:2][0] == '@';
}

// Since some methods explicitly check for user interface idiom, I have no better way to fool them
// so I just hook them, set iPad idiom when necessary and set back to iPhone after calling original

static uint16_t forcePadIdiom = 0;

%hook UIDevice
- (UIUserInterfaceIdiom)userInterfaceIdiom {
    if (!trollPadEnabled) {
        return %orig;
    }
    // Ever wondered how I obtained those random functions to hook? This is my way
#ifdef DEBUG_LOG_IDIOM
    {
        static NSFileHandle *fileHandle;
        static int left = 100;
        static NSString *tmpOut = @"/var/mobile/Documents/stack.txt";
        static NSString *realOut = @"/var/mobile/Documents/stack_out.txt";
        if (!fileHandle) {
            fileHandle = [NSFileHandle fileHandleForWritingAtPath:tmpOut];
            if (!fileHandle) {
                if (forcePadIdiom > 0) {
                    return UIUserInterfaceIdiomPad;
                } else {
                    return %orig;
                }
            }
            [fileHandle seekToEndOfFile];
        }

        // Log every single call stack to file
        NSString *stackTrace = [NSThread ams_symbolicatedCallStackSymbols];
        [fileHandle writeData:[stackTrace dataUsingEncoding:NSUTF8StringEncoding]];
        
        if (left-- == 0) {
            left = 100;
            [fileHandle closeFile];
            fileHandle = nil;
            [NSFileManager.defaultManager removeItemAtPath:realOut error:nil];
            [NSFileManager.defaultManager moveItemAtPath:tmpOut toPath:realOut error:nil];
        }
        return UIUserInterfaceIdiomPad;
    }
#endif

    if (forcePadIdiom > 0) {
        return UIUserInterfaceIdiomPad;
    } else {
        return %orig;
    }
}
%end

/*
%hook SBFloatingDockView
- (CGFloat)contentHeightForBounds:(CGRect)frame {
    if (frame.size.width > frame.size.height) {
        CGFloat width = frame.size.height;
        frame.size.height = frame.size.width;
        frame.size.width = width;
    }
    return %orig;
}
%end
*/

// Fix status bar for the external display
%hook _UIStatusBar
- (void)_prepareVisualProviderIfNeeded {
    if (!trollPadEnabled) {
        return %orig;
    }
    UIScreen *screen = self.targetScreen ?: self._effectiveTargetScreen;
    if (screen._isExternal) {
        // For performance reason, we're gonna overwrite userInterfaceIdiom directly
        // userInterfaceIdiom: ldr x0, [x0, #0x8]
        uint64_t *collection = (uint64_t *)(__bridge void *)screen.traitCollection;
        if (collection) {
            collection[1] = UIUserInterfaceIdiomPad;
        }
    }
    %orig;
}
%end
%hook UIStatusBarWindow
- (void)setStatusBar:(UIStatusBar *)statusBar {
    if (!trollPadEnabled) {
        return %orig;
    }
    if (self.windowScene.screen._isExternal) {
        statusBar.statusBar.targetScreen = self.windowScene.screen;
    }
    %orig;
}
%end

/*
%hook SBSystemShellExtendedDisplayControllerPolicy
-(void)displayController:(id)arg1 didBeginTransaction:(id)arg2 sceneManager:(id)arg3 displayConfiguration:(id)arg4 deactivationReasons:(unsigned long long)arg5 {
    forcePadIdiom++;
    %orig;
    forcePadIdiom--;
}
%end
*/

// Enable Medusa multitasking (three-dots) button on top
%hook SBFullScreenSwitcherLiveContentOverlayCoordinator
-(void)layoutStateTransitionCoordinator:(id)arg1 transitionDidBeginWithTransitionContext:(id)arg2 {
    if (!trollPadEnabled) {
        return %orig;
    }
    forcePadIdiom++;
    %orig;
    forcePadIdiom--;
}
%end
/*
%hook SBShelfLiveContentOverlayCoordinator
-(void)layoutStateTransitionCoordinator:(id)arg1 transitionDidBeginWithTransitionContext:(id)arg2 {
    forcePadIdiom++;
    %orig;
    forcePadIdiom--;
}
%end
*/

// Fix iOS 16 multitasking (split screen, slide over, stage manager)
%hook SBMainSwitcherControllerCoordinator
- (void)_loadContentViewControllerIfNecessaryForWindowScene:(id)scene {
    if (!trollPadEnabled) {
        return %orig;
    }
    forcePadIdiom++;
    %orig;
    forcePadIdiom--;
}
%end

// Fix iOS 18 app switcher animation
%hook SBSwitcherController
- (void)_updateContentViewControllerIfNeeded {
    if (!trollPadEnabled) {
        return %orig;
    }
    forcePadIdiom++;
    %orig;
    forcePadIdiom--;
}
%end

%group TPStageManagerSwitcherHook
%hook SBSwitcherController
- (NSUInteger)windowManagementStyle {
    if (!trollPadEnabled) {
        return %orig;
    }
    if (isStageManagerActive()) {
        return 2;
    }
    return isMultitaskingActive() ? 1 : 0;
}
%end
%end

%group TPAppSwitcherRawStyleHooks
%hook SBAppSwitcherSettings
- (NSInteger)switcherStyle {
    if (!trollPadEnabled) return %orig;
    if (!useiPadAppSwitcher) return 1;
    // iOS 26's controller factory reads the raw style before effectiveSwitcherStyle.
    if (@available(iOS 26.0, *)) return 2;
    return %orig;
}
%end
%end

%group TPFlexibleWindowingHooks
%hook SBWindowScene
- (BOOL)supportsMultitasking {
    return trollPadEnabled ? YES : %orig;
}
%end
%end

%group TPFlexibleWindowingSideHooks
%hook SBWindowingModifier
- (BOOL)isRTLEnabled {
    return shouldForceStageManagerRightToLeft(self) ? YES : %orig;
}

- (id)flexibleAutoLayoutSpaceForAppLayout:(id)appLayout {
    TPBeginStageManagerRightToLeft();
    id result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}
%end

%hook SBFluidSwitcherGestureManager
- (void)_setUpFloatingApplicationGestureRecognizers {
    TPRegisterWindowingGestureManager(self);
    BOOL useRightEdge = trollPadEnabled && pref.stageManagerSide == TPStageManagerSideRight;
    if (useRightEdge) {
        forceStageManagerRightToLeft++;
    }
    %orig;
    if (useRightEdge) {
        forceStageManagerRightToLeft--;
    }
}

- (void)_setUpChamoisGestureRecognizers {
    TPRegisterWindowingGestureManager(self);
    BOOL useRightEdge = trollPadEnabled && pref.stageManagerSide == TPStageManagerSideRight;
    if (useRightEdge) {
        forceStageManagerRightToLeft++;
    }
    %orig;
    if (useRightEdge) {
        forceStageManagerRightToLeft--;
    }
}

- (NSUInteger)_continuousExposeStripEdge {
    return trollPadEnabled && pref.stageManagerSide == TPStageManagerSideRight ? UIRectEdgeRight : %orig;
}
%end

%hook SBStripLayoutWindowingModifier
- (double)_stripOriginX {
    TPBeginStageManagerRightToLeft();
    double result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}

- (TPWindowingItemFrame)frameForItem:(id)item {
    TPBeginStageManagerRightToLeft();
    TPWindowingItemFrame result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}

- (CGRect)frameForLayoutRole:(NSInteger)layoutRole inAppLayout:(id)appLayout withBounds:(CGRect)bounds {
    TPBeginStageManagerRightToLeft();
    CGRect result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}

- (void)layoutViewModelsIfNeeded {
    TPBeginStageManagerRightToLeft();
    %orig;
    TPEndStageManagerRightToLeft();
}
%end
%end

%group TPFlexibleWindowingMirrorHooks
%hook SBExposeWindowingModifier
- (TPWindowingItemFrame)frameForItem:(id)item {
    TPBeginStageManagerRightToLeft();
    TPWindowingItemFrame result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}
%end

%hook SBSwitcherModifier
- (BOOL)isRTLEnabled {
    return shouldForceStageManagerRightToLeft(self) ? YES : %orig;
}

- (CGRect)scaledFrameForLayoutRole:(NSInteger)layoutRole inAppLayout:(id)appLayout atIndex:(NSUInteger)index {
    TPBeginStageManagerRightToLeft();
    CGRect result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}
%end

%hook SBAppSwitcherContinuousExposeSwitcherModifier
- (CGRect)_frameForAppLayout:(id)appLayout withScaledApplied:(BOOL)scaled scrollOffsetApplied:(BOOL)scrolled {
    TPBeginStageManagerRightToLeft();
    CGRect result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}

- (CGPoint)contentOffsetForIndex:(NSUInteger)index alignment:(NSInteger)alignment {
    TPBeginStageManagerRightToLeft();
    CGPoint result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}
%end

%hook SBFlexibleWindowingHomeGestureSwitcherModifier
- (void)_updateTranslationAdjustmentForGestureFromHomeScreenIfNeededWithEvent:(id)event {
    TPBeginStageManagerRightToLeft();
    %orig;
    TPEndStageManagerRightToLeft();
}

- (CGRect)frameForIndex:(NSUInteger)index {
    TPBeginStageManagerRightToLeft();
    CGRect result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}

- (CGPoint)perspectiveAngleForIndex:(NSUInteger)index {
    TPBeginStageManagerRightToLeft();
    CGPoint result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}
%end
%end

// Min width and height are 150, smaller may crash the app
%hook SBSwitcherChamoisLayoutAttributes
- (void)setGridWidths:(NSArray<NSNumber *> *)values {
    if (!trollPadEnabled) {
        return %orig;
    }
    NSUInteger maxValue = values.lastObject.unsignedIntValue;
    NSMutableArray *array = [NSMutableArray array];
    for (int i = 150; i < maxValue; i += 20) {
        [array addObject:@(i)];
    }
    [array addObject:@(maxValue)];
    %orig(array);
}

- (void)setGridHeights:(NSArray<NSNumber *> *)values {
    if (!trollPadEnabled) {
        return %orig;
    }
    NSUInteger maxValue = values.lastObject.unsignedIntValue;
    NSMutableArray *array = [NSMutableArray array];
    for (int i = 150; i < maxValue; i += 20) {
        [array addObject:@(i)];
    }
    [array addObject:@(maxValue)];
    %orig(array);
}
%end

// Override app limit, I don't think this is healthy for battery, so I won't make it unlimited...
%hook SBSwitcherChamoisSettings
- (NSUInteger)maximumNumberOfAppsOnStage {
    return trollPadEnabled ? 5 : %orig;
}
%end

// FIXME: Is this needed?
%hook SBTraitsPipelineManager
-(id)defaultOrientationAnimationSettingsAnimatable:(BOOL)animatable {
    if (!trollPadEnabled) {
        return %orig;
    }
    forcePadIdiom++;
    id result = %orig;
    forcePadIdiom--;
    return result;
}
%end

%hook SBTraitsSceneParticipantDelegate
// Allow upside down
- (BOOL)_isAllowedToHavePortraitUpsideDown {
    return trollPadEnabled ? YES : %orig;
}

// Fix orientation issue for portrait-only apps
- (NSInteger)_orientationMode {
    if (!trollPadEnabled) {
        return %orig;
    }
    forcePadIdiom++;
    NSInteger result = %orig;
    forcePadIdiom--;
    return result;
}
%end

// Workaround for iPhones with home button not being able to open Control Center
%hook CCSControlCenterDefaults
- (NSUInteger)_defaultPresentationGesture {
    return trollPadEnabled ? 1 : %orig;
}
%end
%hook SBHomeGestureSettings
- (BOOL)isHomeGestureEnabled {
    return trollPadEnabled ? YES : %orig;
}
%end
%hook SBControlCenterController
-(NSUInteger)presentingEdge {
    return trollPadEnabled ? 1 : %orig;
}
%end

// Forcibly enable resizable as iOS somehow disabled it in the external display
%hook SBFluidSwitcherItemContainer
- (void)setAllowedTouchResizeCorners:(NSUInteger)cornerMask {
    if (!trollPadEnabled) {
        return %orig;
    }
    // !self.isResizingAllowed && 
    if (self._screen != UIScreen.mainScreen || isWindowingActive()) {
        %orig(0b1111);
        // 1100: enable resizing for bottoms
        // 1111: enable resizing for all corners
    } else {
        %orig;
    }
}
%end

%hook SBAppResizeGrabberView
- (void)setAlpha:(CGFloat)alpha {
    %orig;
    if (trollPadEnabled) {
        self.hidden = pref.hideStageManagerResizeCorners;
    }
}
%end

%hook SBFluidSwitcherViewController
// Use iPadOS app switching animation instead
- (BOOL)isDevicePad {
    return trollPadEnabled ? (useiPadAppSwitcher && pref.useiPadAppSwitchingAnimation) : %orig;
}

%end

// Fix truncated app name in app switcher
%hook SBAppSwitcherSettings
- (void)setDefaultValues {
    %orig;
    if (!trollPadEnabled || !useiPadAppSwitcher) {
        return;
    }
    self.spacingBetweenLeadingEdgeAndIcon = 0;
    self.spacingBetweenTrailingEdgeAndLabels = 0;
}
%end

%hook UIApplication
- (UIUserInterfaceLayoutDirection)userInterfaceLayoutDirection {
    return trollPadEnabled && forceStageManagerRightToLeft > 0 ? UIUserInterfaceLayoutDirectionRightToLeft : %orig;
}

- (id)_defaultSupportedInterfaceOrientations {
    if (!trollPadEnabled) {
        return %orig;
    }
    forcePadIdiom++;
    id result = %orig;
    forcePadIdiom--;
    return result;
}
%end

// Allow upside down Home Screen
%hook SBHomeScreenViewController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return trollPadEnabled ? (%orig | UIInterfaceOrientationMaskPortraitUpsideDown) : %orig;
}
%end

// Allow upside down Lock Screen
%hook SBCoverSheetPrimarySlidingViewController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return trollPadEnabled ? (%orig | UIInterfaceOrientationMaskPortraitUpsideDown) : %orig;
}
%end

// Pass true to supportAppSceneRequests
%hook UISApplicationInitializationContext
- (id)initWithMainDisplayContext:(id)arg1 launchDisplayContext:(id)arg2 deviceContext:(id)arg3 persistedSceneIdentifiers:(id)arg4 supportAppSceneRequests:(BOOL)arg5 {
    return trollPadEnabled ? %orig(arg1, arg2, arg3, arg4, YES) : %orig;
}
%end

// The following hooks are taken from various sources, please refer to tweaks that enable Slide Over.
%hook SpringBoard
- (NSInteger)homeScreenRotationStyle {
    return trollPadEnabled && pref.allowLandscapeHomeScreen ? 1 : %orig;
}
%end

%hook SBMedusaConfigurationUsageMetric
- (BOOL)_isFloatingActive {
    return isMultitaskingActive() ? YES : %orig;
}
%end

%hook SBPlatformController
- (BOOL)isHomeGestureEnabled {
    return trollPadEnabled ? YES : %orig;
}

- (NSInteger)medusaCapabilities {
    return trollPadEnabled ? 2 : %orig;
}
%end

%group TPStageManagerCapabilityHooks
%hook SBAppSwitcherDefaults
- (BOOL)medusaMultitaskingEnabled {
    return isMultitaskingActive() ? YES : %orig;
}

- (BOOL)chamoisWindowingEnabled {
    return trollPadEnabled ? isStageManagerActive() : %orig;
}
%end

%hook SBApplication
- (BOOL)supportsChamoisSceneResizing {
    return isWindowingActive() ? YES : %orig;
}

- (BOOL)supportsChamoisViewResizing {
    return isWindowingActive() ? YES : %orig;
}

- (BOOL)alwaysMaximizedInChamois {
    return isWindowingActive() ? NO : %orig;
}
%end
%end

%group TPStageManagerSideHooks
%hook SBSwitcherModifier
- (BOOL)isRTLEnabled {
    if (shouldForceStageManagerRightToLeft(self)) {
        return YES;
    }
    return %orig;
}

- (CGRect)scaledFrameForLayoutRole:(NSInteger)layoutRole inAppLayout:(id)appLayout atIndex:(NSUInteger)index {
    TPBeginStageManagerRightToLeft();
    CGRect result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}
%end

%hook SBFluidSwitcherGestureManager
- (NSUInteger)_continuousExposeStripEdge {
    return shouldUseRightStageManagerSide() ? UIRectEdgeRight : %orig;
}
%end

%hook SBContinuousExposeAutoLayoutController
- (id)spaceByPerformingAutoLayoutWithSpace:(id)space previousSpace:(id)previousSpace configuration:(id)configuration options:(NSUInteger)options {
    TPBeginStageManagerRightToLeft();
    id result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}
%end

%hook SBContinuousExposeAppToInlineAppExposeSwitcherModifier
- (CGRect)frameForIndex:(NSUInteger)index {
    TPBeginStageManagerRightToLeft();
    CGRect result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}
%end

%hook SBContinuousExposeFullScreenCrossblurTransitionSwitcherModifier
- (CGPoint)anchorPointForIndex:(NSUInteger)index {
    TPBeginStageManagerRightToLeft();
    CGPoint result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}

- (double)perspectiveAngleForAppLayout:(id)appLayout {
    TPBeginStageManagerRightToLeft();
    double result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}
%end

%hook SBContinuousExposeHomeGestureSwitcherModifier
- (void)_updateTranslationAdjustmentForGestureFromHomeScreenIfNeededWithEvent:(id)event {
    TPBeginStageManagerRightToLeft();
    %orig;
    TPEndStageManagerRightToLeft();
}

- (CGRect)frameForIndex:(NSUInteger)index {
    TPBeginStageManagerRightToLeft();
    CGRect result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}

- (double)perspectiveAngleForAppLayout:(id)appLayout {
    TPBeginStageManagerRightToLeft();
    double result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}

- (double)_rangeForPerspectiveAngleProgressOfAppLayout:(id)appLayout outMin:(double)minimum outMax:(double)maximum {
    TPBeginStageManagerRightToLeft();
    double result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}

- (double)_maxPerspectiveAngleForSelectedAppLayout {
    TPBeginStageManagerRightToLeft();
    double result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}
%end

%hook SBFullScreenContinuousExposeSwitcherModifier
- (unsigned int)_continuousExposeStripEdge {
    TPBeginStageManagerRightToLeft();
    unsigned int result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}
%end

%hook SBInlineAppExposeContinuousExposeSwitcherModifier
- (CGRect)frameForIndex:(NSUInteger)index {
    TPBeginStageManagerRightToLeft();
    CGRect result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}

- (CGRect)frameForLayoutRole:(NSInteger)layoutRole inAppLayout:(id)appLayout withBounds:(CGRect)bounds {
    TPBeginStageManagerRightToLeft();
    CGRect result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}

- (CGRect)_inlineAppExposeSwitcherFrame {
    TPBeginStageManagerRightToLeft();
    CGRect result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}
%end

%hook SBRevealContinuousExposeStripOverflowGestureModifier
- (CGRect)frameForIndex:(NSUInteger)index {
    TPBeginStageManagerRightToLeft();
    CGRect result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}
%end

%hook SBStripContinuousExposeSwitcherModifier
- (CGPoint)anchorPointForIndex:(NSUInteger)index {
    TPBeginStageManagerRightToLeft();
    CGPoint result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}

- (CGPoint)adjustedSpaceAccessoryViewAnchorPoint:(CGPoint)anchorPoint forAppLayout:(id)appLayout {
    TPBeginStageManagerRightToLeft();
    CGPoint result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}

- (TPSwitcherGradientWallpaperAttributes)wallpaperGradientAttributesForIndex:(NSUInteger)index {
    TPBeginStageManagerRightToLeft();
    TPSwitcherGradientWallpaperAttributes result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}

- (double)perspectiveAngleForAppLayout:(id)appLayout {
    TPBeginStageManagerRightToLeft();
    double result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}

- (double)_appStripOriginX {
    TPBeginStageManagerRightToLeft();
    double result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}

- (CGRect)_stripFrame {
    TPBeginStageManagerRightToLeft();
    CGRect result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}

- (CGRect)_cachedOrFallbackFrameForIndex:(NSUInteger)index cacheValidityToken:(id)token {
    TPBeginStageManagerRightToLeft();
    CGRect result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}
%end
%end

%group TPStageManagerSwitcherTransitionHooks
%hook SBContinuousExposeSwitcherToAppModifier
- (CGRect)frameForIndex:(NSUInteger)index {
    TPBeginStageManagerRightToLeft();
    CGRect result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}

- (CGPoint)contentOffsetForIndex:(NSUInteger)index alignment:(NSInteger)alignment {
    TPBeginStageManagerRightToLeft();
    CGPoint result = %orig;
    TPEndStageManagerRightToLeft();
    return result;
}
%end
%end

%hook SBApplication
- (BOOL)isMedusaCapable {
    if (!isMultitaskingActive()) {
        return %orig;
    }
    return pref.forceEnableMedusaForLandscapeOnlyApps ||
        (self.info.supportedInterfaceOrientations & UIInterfaceOrientationMaskPortrait) != 0;
}

- (BOOL)_supportsApplicationType:(int)arg1 {
	return isMultitaskingActive() ? YES : %orig;
}
%end

%hook SBMainWorkspace
- (BOOL)isMedusaEnabled {
    return isMultitaskingActive() ? YES : %orig;
}
%end

%hook SBFloatingDockController
+ (BOOL)isFloatingDockSupported {
    if (trollPadEnabled && pref.isFloatingDockSupported) {
        if (@available(iOS 26.0, *)) {
            // Legacy backgrounding hooks can prevent FrontBoard from registering
            // this required UIKit property. Do not create an invalid remote Dock.
            Class settingsClass = objc_getClass("UIMutableApplicationSceneSettings");
            if (!settingsClass || !TPSettingForSelector ||
                !TPSettingForSelector(settingsClass, @selector(deactivationReasons))) {
                static BOOL loggedMissingSetting;
                if (!loggedMissingSetting) {
                    loggedMissingSetting = YES;
                    NSLog(@"[TrollPadEx] Floating Dock unavailable: deactivationReasons is not registered; check legacy backgrounding hooks");
                }
                return NO;
            }
        }
        return YES;
    }
    return %orig;
}
%end

%group TPInAppDockGestureHooks
%hook SBFloatingDockBehaviorAssertion
- (BOOL)gesturePossible {
    return %orig || shouldRecoverInAppDockGesture(self);
}
%end
%end

// Switcher presentation is independent of the native window management mode.
%hook SBAppSwitcherSettings
- (NSInteger)effectiveSwitcherStyle {
    return trollPadEnabled ? (useiPadAppSwitcher ? 2 : 1) : %orig;
}

// Scales the grid switcher
- (void)setGridSwitcherPageScale:(CGFloat)arg1 {
    return trollPadEnabled && useiPadAppSwitcher && pref.scaleGridSwitcher ? %orig(0.38) : %orig;
}

- (void)setGridSwitcherVerticalNaturalSpacingPortrait:(CGFloat)arg1 {
    return trollPadEnabled && useiPadAppSwitcher && pref.scaleGridSwitcher ? %orig(65) : %orig;
}

- (void)setGridSwitcherVerticalNaturalSpacingLandscape:(CGFloat)arg1 {
    return trollPadEnabled && useiPadAppSwitcher && pref.scaleGridSwitcher ? %orig(40) : %orig;
}

- (void)setGridSwitcherHorizontalInterpageSpacingPortrait:(CGFloat)arg1 {
    return trollPadEnabled && useiPadAppSwitcher && pref.scaleGridSwitcher ? %orig(30) : %orig;
}

- (void)setGridSwitcherHorizontalInterpageSpacingLandscape:(CGFloat)arg1 {
    return trollPadEnabled && useiPadAppSwitcher && pref.scaleGridSwitcher ? %orig(10) : %orig;
}
%end

// Unlock external display support for MDC versions
static int (*originalExtDisplayEnabledFunc)(void);
static BOOL (*originalFlexibleWindowingUIAvailable)(void);
static BOOL (*originalChamoisWindowingUIAvailable)(void);

static BOOL hookedFlexibleWindowingUIAvailable(void) {
    return trollPadEnabled ? YES : originalFlexibleWindowingUIAvailable();
}

static BOOL hookedChamoisWindowingUIAvailable(void) {
    return trollPadEnabled ? YES : originalChamoisWindowingUIAvailable();
}

int hookedExtDisplayEnabledFunc() {
    // clang forgets to PAC this function, so we need this ugly line
    int hack = 0; if (hack) { printf(""); }

    return trollPadEnabled ? 1 : (originalExtDisplayEnabledFunc ? originalExtDisplayEnabledFunc() : 0);
}

// Bypass Keyboard & Mouse requirement
%hook SBExternalDisplayRuntimeAvailabilitySettings
- (void)setDefaultValues {
    if (!trollPadEnabled) {
        return %orig;
    }
    self.requireHardwareKeyboard = NO;
    self.requirePointer = NO;
}
%end

static BOOL isEnhancedMultitaskingProperty(CFStringRef property) {
    if (!property) {
        return NO;
    }

    return CFEqual(property, CFSTR("DeviceSupportsEnhancedMultitasking")) ||
        CFEqual(property, CFSTR("qeaj75wk3HF4DwQ8qbIi7g")) ||
        CFEqual(property, CFSTR("DeviceSupportsSingleDisplayEnhancedMultitasking")) ||
        CFEqual(property, CFSTR("fbpzGGoBNcvDLt4LlZGnfA"));
}

static BOOL isMedusaCapabilityProperty(CFStringRef property) {
    if (!property) {
        return NO;
    }

    // These are the four MobileGestalt capabilities required for iPadOS
    // windowing. Do not spoof the iPad bit or DeviceClassNumber here: those also
    // change unrelated phone UI such as the status bar and keyboard.
    return CFEqual(property, CFSTR("MedusaFloatingLiveAppCapability")) ||
        CFEqual(property, CFSTR("mG0AnH/Vy1veoqoLRAIgTA")) ||
        CFEqual(property, CFSTR("MedusaOverlayAppCapability")) ||
        CFEqual(property, CFSTR("UCG5MkVahJxG1YULbbd5Bg")) ||
        CFEqual(property, CFSTR("MedusaPinnedAppCapability")) ||
        CFEqual(property, CFSTR("ZYqko/XM5zD3XBfN5RmaXA")) ||
        CFEqual(property, CFSTR("MedusaPIPCapability")) ||
        CFEqual(property, CFSTR("nVh/gwNpy7Jv1NOk00CMrw"));
}

static BOOL shouldForceMultitaskingProperty(CFStringRef property) {
    return trollPadEnabled && (isEnhancedMultitaskingProperty(property) ||
        isMedusaCapabilityProperty(property));
}

%hookf(bool, MGGetBoolAnswer, CFStringRef property) {
    if (shouldForceMultitaskingProperty(property)) {
        return true;
    }
    return %orig;
}

%group TPMobileGestaltCopyAnswerHooks
%hookf(CFTypeRef, MGCopyAnswer, CFStringRef property, CFDictionaryRef options) {
    if (shouldForceMultitaskingProperty(property)) {
        return CFRetain(kCFBooleanTrue);
    }
    return %orig;
}

%hookf(CFTypeRef, MGCopyAnswerWithError, CFStringRef property, CFDictionaryRef options, int *error) {
    if (shouldForceMultitaskingProperty(property)) {
        if (error) {
            *error = 0;
        }
        return CFRetain(kCFBooleanTrue);
    }
    return %orig;
}
%end

%ctor {
    loadTrollPadEnabled();
    if (@available(iOS 26.0, *)) {
        TPSettingForSelector = dlsym(RTLD_DEFAULT, "FBSSettingForSelector");
    }
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        trollPadPrefsChanged, CFSTR("com.kdt.trollpad/saved"), NULL,
        CFNotificationSuspensionBehaviorCoalesce);
    pref = [TPPrefsObserver new];
    useiPadAppSwitcher = pref.useiPadAppSwitcher;
    if (trollPadEnabled && !useiPadAppSwitcher) {
        TPPreparePhoneSwitcherCompatibility();
    }
    %init;
    TPInstallDockLibraryHooks(TPShouldHideDockLibrary);
    TPInstallWindowScaling(shouldScaleAppWindows);
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26 &&
        canInstallInAppDockGestureHook()) {
        %init(TPInAppDockGestureHooks);
    }
    if (class_getInstanceMethod(objc_getClass("SBAppSwitcherSettings"), @selector(switcherStyle))) {
        %init(TPAppSwitcherRawStyleHooks);
    }
    Method phonePresentation = class_getInstanceMethod(objc_getClass("SBContinuousExposeRootSwitcherModifier"),
        @selector(multitaskingModifierForEvent:));
    if (phonePresentation && strcmp(method_getTypeEncoding(phonePresentation), "@24@0:8@16") == 0 &&
        objc_getClass("SBDeckSwitcherModifier")) {
        MSHookMessageEx(objc_getClass("SBContinuousExposeRootSwitcherModifier"),
            @selector(multitaskingModifierForEvent:),
            (IMP)TPPhoneContinuousExposeFactory, (IMP *)&TPOriginalContinuousExposeFactory);
    }
    if (@available(iOS 26.0, *)) {
        Method mainPresentation = class_getInstanceMethod(objc_getClass("SBMainSwitcherRootSwitcherModifier"),
            @selector(_newMultitaskingModifierForEnvironmentMode:));
        if (mainPresentation && strcmp(method_getTypeEncoding(mainPresentation), "@24@0:8q16") == 0 &&
            objc_getClass("SBDeckSwitcherModifier")) {
            MSHookMessageEx(objc_getClass("SBMainSwitcherRootSwitcherModifier"),
                @selector(_newMultitaskingModifierForEnvironmentMode:),
                (IMP)TPPhoneMainSwitcherFactory, (IMP *)&TPOriginalMainSwitcherFactory);
        }
    }

    if (@available(iOS 26.0, *)) {
        Class windowSceneClass = objc_getClass("SBWindowScene");
        if (windowSceneClass && class_getInstanceMethod(windowSceneClass,
            @selector(supportsMultitasking))) {
            %init(TPFlexibleWindowingHooks);
        }
        Class stripClass = objc_getClass("SBStripLayoutWindowingModifier");
        Class gestureClass = objc_getClass("SBFluidSwitcherGestureManager");
        Class windowingModifierClass = objc_getClass("SBWindowingModifier");
        (void)[(id)gestureClass class];
        (void)[(id)windowingModifierClass class];
        if (stripClass && class_getInstanceMethod(stripClass, @selector(_stripOriginX)) &&
            hasWindowingItemFrameMethod(stripClass) &&
            windowingModifierClass && class_getInstanceMethod(windowingModifierClass, @selector(isRTLEnabled)) &&
            class_getInstanceMethod(windowingModifierClass, @selector(flexibleAutoLayoutSpaceForAppLayout:)) &&
            gestureClass && class_getInstanceMethod(gestureClass,
                @selector(_continuousExposeStripEdge)) &&
            class_getInstanceMethod(gestureClass, @selector(_setUpFloatingApplicationGestureRecognizers)) &&
            class_getInstanceMethod(gestureClass, @selector(_setUpChamoisGestureRecognizers)) &&
            class_getInstanceMethod(gestureClass, @selector(_tearDownFloatingApplicationGestureRecognizers)) &&
            class_getInstanceMethod(gestureClass, @selector(_tearDownChamoisGestureRecognizers)) &&
            class_getInstanceMethod(gestureClass, @selector(updateForWindowManagementContext:))) {
            %init(TPFlexibleWindowingSideHooks);
        }
        Class homeGestureClass = objc_getClass("SBFlexibleWindowingHomeGestureSwitcherModifier");
        Class appSwitcherClass = objc_getClass("SBAppSwitcherContinuousExposeSwitcherModifier");
        Class exposeClass = objc_getClass("SBExposeWindowingModifier");
        if (homeGestureClass && class_getInstanceMethod(homeGestureClass,
                @selector(perspectiveAngleForIndex:)) &&
            hasWindowingItemFrameMethod(exposeClass) &&
            appSwitcherClass && class_getInstanceMethod(appSwitcherClass,
                @selector(_frameForAppLayout:withScaledApplied:scrollOffsetApplied:))) {
            %init(TPFlexibleWindowingMirrorHooks);
        }
    }

    if (@available(iOS 18.0, *)) {
        // These private MobileGestalt functions are unsafe to hook on iOS 18.
    } else {
        %init(TPMobileGestaltCopyAnswerHooks);
    }

    if (canInstallStageManagerSwitcherHook()) {
        %init(TPStageManagerSwitcherHook);
    }
    if (canInstallStageManagerCapabilityHooks()) {
        %init(TPStageManagerCapabilityHooks);
    }
    if (canInstallStageManagerSideHooks()) {
        %init(TPStageManagerSideHooks);
    }
    if (canInstallStageManagerSwitcherTransitionHooks()) {
        %init(TPStageManagerSwitcherTransitionHooks);
    }

    // Unlock external display support for MDC versions
    void *sbFoundationHandle = dlopen("/System/Library/PrivateFrameworks/SpringBoardFoundation.framework/SpringBoardFoundation", RTLD_GLOBAL);
    if (@available(iOS 26.0, *)) {
        // iOS 26 replaces windowManagementStyle with a window management context.
        // Let the system build that context from its own multitasking preferences.
        void *flexibleWindowingUIAvailable = dlsym(sbFoundationHandle,
            "SBFIsFlexibleWindowingUIAvailable");
        if (flexibleWindowingUIAvailable) {
            MSHookFunction(flexibleWindowingUIAvailable,
                (void *)hookedFlexibleWindowingUIAvailable,
                (void **)&originalFlexibleWindowingUIAvailable);
        }
        void *chamoisWindowingUIAvailable = dlsym(sbFoundationHandle,
            "SBFIsChamoisWindowingUIAvailable");
        if (chamoisWindowingUIAvailable) {
            MSHookFunction(chamoisWindowingUIAvailable,
                (void *)hookedChamoisWindowingUIAvailable,
                (void **)&originalChamoisWindowingUIAvailable);
        }
    }
    // iOS 16.0
    void *extDisplayEnabledFunc = dlsym(sbFoundationHandle, "SBChamoisExternalDisplayControllerIsEnabled");
    if (!extDisplayEnabledFunc) {
        // iOS 16.1.x
        extDisplayEnabledFunc = dlsym(sbFoundationHandle, "SBFIsChamoisExternalDisplayControllerAvailable");
    }
    if (extDisplayEnabledFunc) {
        MSHookFunction((void *)extDisplayEnabledFunc, (void *)hookedExtDisplayEnabledFunc,
            (void **)&originalExtDisplayEnabledFunc);
    }

}
