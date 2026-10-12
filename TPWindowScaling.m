#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "TPWindowScaling.h"
#include <dlfcn.h>
#include <string.h>

// Keep native scene sizing, hosting, input and application layout unchanged.
// Only relax the native resize minimum for ordinary app display items.
@interface NSObject (TPWindowScalingPrivate)
- (instancetype)_initWithLayoutRestrictions:(NSUInteger)mask restrictedSize:(CGSize)size __attribute__((objc_method_family(init)));
- (NSString *)bundleIdentifier;
- (BOOL)isHomeScreenDisplayItem;
- (BOOL)isAppLibraryDisplayItem;
- (CGFloat)minimumWindowWidth;
- (CGFloat)minimumWindowHeight;
- (void)setMinimumWindowWidth:(CGFloat)width;
- (void)setMinimumWindowHeight:(CGFloat)height;
@end

static BOOL (*smallerWindowsEnabled)(void);
static char smallerWindowRestriction;

static BOOL enabled(void) {
    return smallerWindowsEnabled && smallerWindowsEnabled();
}

static BOOL appItem(id item) {
    return [item respondsToSelector:@selector(bundleIdentifier)] && [item bundleIdentifier].length > 0 &&
        !([item respondsToSelector:@selector(isHomeScreenDisplayItem)] && [item isHomeScreenDisplayItem]) &&
        !([item respondsToSelector:@selector(isAppLibraryDisplayItem)] && [item isAppLibraryDisplayItem]);
}

static CGSize resizeFloor(void) {
    CGSize screen = UIScreen.mainScreen.bounds.size;
    return CGSizeMake(300 * MIN(screen.width, screen.height) / MAX(screen.width, screen.height), 300);
}

static id (*originalRestrictions)(id, SEL, id);
static id restrictions(id self, SEL cmd, id item) {
    id info = originalRestrictions(self, cmd, item);
    if (!enabled() || !appItem(item)) return info;
    // Native factories/copy can return shared instances; use a private object.
    id fresh = [[[info class] alloc] _initWithLayoutRestrictions:0 restrictedSize:CGSizeZero];
    if (fresh) objc_setAssociatedObject(fresh, &smallerWindowRestriction, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return fresh ?: info;
}

static id (*originalGrid)(id, SEL, CGRect, NSInteger, id, CGFloat, id);
static id grid(id self, SEL cmd, CGRect bounds, NSInteger orientation, id info, CGFloat scale, id config) {
    if (enabled() && [objc_getAssociatedObject(info, &smallerWindowRestriction) boolValue]) {
        id copied = [config copy];
        CGSize floor = resizeFloor();
        [copied setMinimumWindowWidth:MIN([copied minimumWindowWidth], floor.width)];
        [copied setMinimumWindowHeight:MIN([copied minimumWindowHeight], floor.height)];
        return originalGrid(self, cmd, bounds, orientation, info, scale, copied);
    }
    return originalGrid(self, cmd, bounds, orientation, info, scale, config);
}

static CGSize (*originalMinimum)(id, SEL, id, CGRect, id, id, NSInteger, CGFloat, id);
static CGSize minimum(id self, SEL cmd, id item, CGRect bounds, id layoutGrid, id info,
    NSInteger orientation, CGFloat scale, id config) {
    CGSize result = originalMinimum(self, cmd, item, bounds, layoutGrid, info, orientation, scale, config);
    if (enabled() && appItem(item)) {
        CGSize floor = resizeFloor();
        result.width = MIN(result.width, floor.width);
        result.height = MIN(result.height, floor.height);
    }
    return result;
}

void TPInstallWindowScaling(BOOL (*enabledCallback)(void)) {
    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion != 26) return;
    void (*hook)(Class, SEL, IMP, IMP *) = dlsym(RTLD_DEFAULT, "MSHookMessageEx");
    if (!hook) return;
    struct { const char *cls; const char *sel; IMP replacement; IMP *original; const char *types; } hooks[] = {
        {"SBDisplayItemLayoutAttributesCalculator", "layoutRestrictionInfoForItem:", (IMP)restrictions, (IMP *)&originalRestrictions, "@24@0:8@16"},
        {"SBDisplayItemLayoutGrid", "_gridForBounds:contentOrientation:layoutRestrictionInfo:screenScale:windowingConfiguration:", (IMP)grid, (IMP *)&originalGrid, "@80@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16q48@56d64@72"},
        {"SBDisplayItemLayoutAttributesCalculator", "_minSizeForDisplayItem:inContainerBounds:layoutGrid:layoutRestrictionInfo:contentOrientation:screenScale:windowingConfiguration:", (IMP)minimum, (IMP *)&originalMinimum, "{CGSize=dd}96@0:8@16{CGRect={CGPoint=dd}{CGSize=dd}}24@56@64q72d80@88"},
    };
    for (unsigned i = 0; i < sizeof(hooks)/sizeof(hooks[0]); i++) {
        Method method = class_getInstanceMethod(objc_getClass(hooks[i].cls), sel_registerName(hooks[i].sel));
        if (!method || strcmp(method_getTypeEncoding(method), hooks[i].types) != 0) {
            NSLog(@"[TrollPadEx] Smaller windows unavailable: incompatible %s %s", hooks[i].cls, hooks[i].sel);
            return;
        }
    }
    if (!class_getInstanceMethod(objc_getClass("SBDisplayItemGridLayoutRestrictionInfo"),
        @selector(_initWithLayoutRestrictions:restrictedSize:))) return;
    smallerWindowsEnabled = enabledCallback;
    for (unsigned i = 0; i < sizeof(hooks)/sizeof(hooks[0]); i++) {
        hook(objc_getClass(hooks[i].cls), sel_registerName(hooks[i].sel), hooks[i].replacement, hooks[i].original);
    }
}
