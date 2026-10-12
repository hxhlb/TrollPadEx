#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <sys/utsname.h>
#include <math.h>

// Separate VRESEARCH-only Phone experiment. Not built into TrollPadEx packages.

static NSMutableArray *events;
static BOOL writePending;
static NSHashTable *sceneViews;
static NSHashTable *layerHosts;
static NSMapTable *presentationOwners;
static NSMapTable *layerOwners;
static __thread BOOL applyingScale;
static __thread NSUInteger presentationDepth;
static char scaledHost;
static NSString *const outputPath = @"/var/mobile/Library/Caches/TrollPadEx-scaling-events.json";
static char phoneRestriction;
@interface NSObject (TPScalingRestriction)
- (instancetype)_initWithLayoutRestrictions:(NSUInteger)mask restrictedSize:(CGSize)size __attribute__((objc_method_family(init)));
@end
static void captureViews(UIView *view, NSMutableArray *rows) {
    NSString *name = NSStringFromClass(view.class);
    if ([name containsString:@"SwitcherItemContainer"] || [name containsString:@"ResizeGrabber"] || [name containsString:@"SceneHost"]) {
        CGRect frame = [view convertRect:view.bounds toView:nil];
        [rows addObject:@{@"class":name, @"frame":@[@(frame.origin.x), @(frame.origin.y), @(frame.size.width), @(frame.size.height)],
            @"bounds":@[@(view.bounds.size.width), @(view.bounds.size.height)]}];
    }
    for (UIView *child in view.subviews) captureViews(child, rows);
}
static void captureNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableArray *rows = [NSMutableArray array];
        for (UIView *view in sceneViews.allObjects) {
            captureViews(view, rows);
            CGRect frame = [view convertRect:view.bounds toView:nil];
            [rows addObject:@{@"class":NSStringFromClass(view.class), @"frame":@[@(frame.origin.x), @(frame.origin.y), @(frame.size.width), @(frame.size.height)],
                @"bounds":@[@(view.bounds.size.width), @(view.bounds.size.height)],
                @"visible":@(((BOOL (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"isVisible"))),
                @"active":@(((BOOL (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"isActive")))}];
        }
        for (UIView *host in layerHosts.allObjects) {
            CGRect frame = [host convertRect:host.bounds toView:nil];
            UIView *owner = [layerOwners objectForKey:host];
            BOOL detached = host.superview == nil;
            if (detached && owner) {
                CGRect viewport = [owner convertRect:owner.bounds toView:nil];
                frame = CGRectOffset(host.frame, viewport.origin.x, viewport.origin.y);
            }
            id context = ((id (*)(id, SEL))objc_msgSend)(host, NSSelectorFromString(@"_presentationContext"));
            [rows addObject:@{@"class":NSStringFromClass(host.class), @"frame":@[@(frame.origin.x), @(frame.origin.y), @(frame.size.width), @(frame.size.height)],
                @"bounds":@[@(host.bounds.size.width), @(host.bounds.size.height)], @"context":context ? [context description] : @"nil",
                @"parent":host.superview ? NSStringFromClass(host.superview.class) : @"nil", @"onScreen":@(host.window != nil),
                @"ownedProjection":@(owner != nil), @"detachedLayer":@(detached),
                @"geometrySpace":detached ? @"owner-relative-layer" : @"UIView"}];
        }
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            if ([scene respondsToSelector:NSSelectorFromString(@"switcherController")]) {
                id switcher = [scene valueForKey:@"switcherController"];
                id context = [switcher valueForKey:@"windowManagementContext"];
                if (context) [rows addObject:@{@"class":@"TPWindowManagementContext",
                    @"baseStyle":[context valueForKey:@"baseStyle"],
                    @"automaticStageCreationEnabled":[context valueForKey:@"automaticStageCreationEnabled"]}];
            }
            for (UIWindow *window in ((UIWindowScene *)scene).windows) captureViews(window, rows);
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:rows options:NSJSONWritingPrettyPrinted error:nil];
        [data writeToFile:@"/var/mobile/Library/Caches/TrollPadEx-scaling-views.json" atomically:YES];
    });
}
static BOOL targeted(id item) {
    SEL selector = NSSelectorFromString(@"bundleIdentifier");
    return [item respondsToSelector:selector] &&
        [((id (*)(id, SEL))objc_msgSend)(item, selector) isEqual:@"com.apple.mobilephone"];
}
static BOOL enabled(void) {
    return [NSUserDefaults.standardUserDefaults boolForKey:@"TPTrollPadExPhoneHostScaling"] &&
        ([NSUserDefaults.standardUserDefaults boolForKey:@"SBMedusaMultitaskingEnabled"] ||
         [NSUserDefaults.standardUserDefaults boolForKey:@"SBChamoisWindowingEnabled"]);
}
static CGSize adjust(CGSize size) {
    if (!enabled() || size.width <= 0 || size.height <= 0) return size;
    CGSize canvas = UIScreen.mainScreen.bounds.size;
    return CGSizeMake(MIN(size.width, 300 * canvas.width / canvas.height), MIN(size.height, 300));
}
static void record(NSString *method, CGSize before, CGSize after) {
    @synchronized(events) {
        NSDictionary *event = @{@"method":method, @"enabled":@(enabled()),
            @"original":@[@(before.width), @(before.height)],
            @"result":@[@(after.width), @(after.height)]};
        if ([events containsObject:event]) return;
        [events addObject:event];
        if (events.count > 128) [events removeObjectAtIndex:0];
        if (writePending) return;
        writePending = YES;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        @synchronized(events) {
            NSData *data = [NSJSONSerialization dataWithJSONObject:events options:NSJSONWritingPrettyPrinted error:nil];
            [data writeToFile:outputPath atomically:YES];
            writePending = NO;
        }
    });
}
static BOOL targetedHandle(id handle) {
    SEL sel = NSSelectorFromString(@"displayItemRepresentation");
    return [handle respondsToSelector:sel] && targeted(((id (*)(id, SEL))objc_msgSend)(handle, sel));
}
static id sceneHandle(id view) {
    return ((id (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"sceneHandle"));
}
static void (*originalSceneSettings)(id, SEL, id, id, id);
static void sceneSettings(id self, SEL cmd, id settings, id context, id entity) {
    originalSceneSettings(self, cmd, settings, context, entity);
    if (!enabled() || !targetedHandle(self)) return;
    CGRect before = ((CGRect (*)(id, SEL))objc_msgSend)(settings, NSSelectorFromString(@"frame"));
    CGRect after = CGRectMake(before.origin.x, before.origin.y, UIScreen.mainScreen.bounds.size.width, UIScreen.mainScreen.bounds.size.height);
    ((void (*)(id, SEL, CGRect))objc_msgSend)(settings, NSSelectorFromString(@"setFrame:"), after);
    record(@"forcedSceneFrame", before.size, after.size);
}
static void (*originalHostLayout)(id, SEL, UIView *);
static void applyScale(id owner, UIView *host) {
    if (!enabled() || !host || applyingScale) return;
    CGSize canvas = UIScreen.mainScreen.bounds.size;
    // UIKit can manage the backing layer without attaching its UIView wrapper.
    CGRect area = host.superview ? [((UIView *)owner) convertRect:((UIView *)owner).bounds toView:host.superview] : ((UIView *)owner).bounds;
    if (!isfinite(area.origin.x) || !isfinite(area.origin.y) ||
        !isfinite(area.size.width) || !isfinite(area.size.height) ||
        area.size.width <= 0 || area.size.height <= 0 || canvas.width <= 0 || canvas.height <= 0) return;
    applyingScale = YES;
    CGFloat scale = MIN(1, MIN(area.size.width / canvas.width, area.size.height / canvas.height));
    CGRect bounds = (CGRect){CGPointZero, canvas};
    CGPoint center = CGPointMake(CGRectGetMidX(area), CGRectGetMidY(area));
    CGAffineTransform transform = CGAffineTransformMakeScale(scale, scale);
    if (!CGRectEqualToRect(host.bounds, bounds)) host.bounds = bounds;
    if (!CGPointEqualToPoint(host.center, center)) host.center = center;
    if (!CGAffineTransformEqualToTransform(host.transform, transform)) host.transform = transform;
    objc_setAssociatedObject(host, &scaledHost, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    record(@"hostUniformScale", canvas, CGSizeMake(canvas.width * scale, canvas.height * scale));
    applyingScale = NO;
}
static void updatePresentation(id owner, id presentation) {
    SEL getter = NSSelectorFromString(@"hostContainerView");
    if (![presentation respondsToSelector:getter]) return;
    UIView *container = ((id (*)(id, SEL))objc_msgSend)(presentation, getter);
    if (!container) return;
    [layerOwners setObject:owner forKey:container];
    [layerHosts addObject:container];
    applyScale(owner, container);
}
static void hostLayout(id self, SEL cmd, UIView *host) {
    BOOL target = targetedHandle(sceneHandle(self));
    if (target) {
        [sceneViews addObject:self];
        if (host) [presentationOwners setObject:self forKey:host];
    }
    originalHostLayout(self, cmd, host);
    if (target) updatePresentation(self, host);
}
static void (*originalPresentationUpdate)(id, SEL);
static void presentationUpdate(id self, SEL cmd) {
    id owner = [presentationOwners objectForKey:self];
    UIView *container = owner ? ((id (*)(id, SEL))objc_msgSend)(self, NSSelectorFromString(@"hostContainerView")) : nil;
    if (owner && !applyingScale && [objc_getAssociatedObject(container, &scaledHost) boolValue]) {
        container.transform = CGAffineTransformIdentity;
        if (!enabled()) objc_setAssociatedObject(container, &scaledHost, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    presentationDepth++;
    originalPresentationUpdate(self, cmd);
    presentationDepth--;
    if (owner && !applyingScale) updatePresentation(owner, self);
}
static void (*originalLayerFrame)(id, SEL, CGRect);
static void layerFrame(id self, SEL cmd, CGRect frame) {
    UIView *container = self;
    BOOL marked = [objc_getAssociatedObject(container, &scaledHost) boolValue];
    if (marked && !applyingScale) {
        container.transform = CGAffineTransformIdentity;
        if (!enabled()) objc_setAssociatedObject(container, &scaledHost, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    originalLayerFrame(self, cmd, frame);
    if (!applyingScale && presentationDepth == 0) {
        id owner = [layerOwners objectForKey:self];
        if (owner) applyScale(owner, container);
    }
}
static void (*originalHostMove)(id, SEL);
static void hostMove(id self, SEL cmd) {
    originalHostMove(self, cmd);
    id owner = [layerOwners objectForKey:self];
    if (owner) applyScale(owner, self);
}
static id (*originalRestrictions)(id, SEL, id);
static id restrictions(id self, SEL cmd, id item) {
    id info = originalRestrictions(self, cmd, item);
    if (!enabled() || !targeted(item)) return info;
    NSUInteger mask = ((NSUInteger (*)(id, SEL))objc_msgSend)(info, NSSelectorFromString(@"layoutRestrictions"));
    CGSize size = ((CGSize (*)(id, SEL))objc_msgSend)(info, NSSelectorFromString(@"restrictedSize"));
    if (mask != 0) return info;
    id fresh = [[[info class] alloc] _initWithLayoutRestrictions:mask restrictedSize:size];
    if (fresh) objc_setAssociatedObject(fresh, &phoneRestriction, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    record(@"phoneRestriction", size, size);
    return fresh ?: info;
}
static id (*originalGrid)(id, SEL, CGRect, NSInteger, id, CGFloat, id);
static id grid(id self, SEL cmd, CGRect bounds, NSInteger orientation, id info, CGFloat scale, id config) {
    if (enabled() && [objc_getAssociatedObject(info, &phoneRestriction) boolValue]) {
        id copied = [config copy];
        CGSize before = CGSizeMake(((CGFloat (*)(id, SEL))objc_msgSend)(copied, NSSelectorFromString(@"minimumWindowWidth")),
            ((CGFloat (*)(id, SEL))objc_msgSend)(copied, NSSelectorFromString(@"minimumWindowHeight")));
        CGSize after = adjust(before);
        ((void (*)(id, SEL, CGFloat))objc_msgSend)(copied, NSSelectorFromString(@"setMinimumWindowWidth:"), after.width);
        ((void (*)(id, SEL, CGFloat))objc_msgSend)(copied, NSSelectorFromString(@"setMinimumWindowHeight:"), after.height);
        record(@"gridConfiguration", before, after);
        return originalGrid(self, cmd, bounds, orientation, info, scale, copied);
    }
    return originalGrid(self, cmd, bounds, orientation, info, scale, config);
}
__attribute__((constructor)) static void start(void) {
    struct utsname system;
    if (uname(&system) != 0 || !strstr(system.version, "VRESEARCH") || ![NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"]) return;
    if (@available(iOS 26.0, *)) {
        events = [NSMutableArray array];
        sceneViews = [NSHashTable weakObjectsHashTable];
        layerHosts = [NSHashTable weakObjectsHashTable];
        presentationOwners = [NSMapTable weakToWeakObjectsMapTable];
        layerOwners = [NSMapTable weakToWeakObjectsMapTable];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, captureNotification,
            CFSTR("com.banana.trollpadex/scaling-capture"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        void (*hook)(Class, SEL, IMP, IMP *) = dlsym(RTLD_DEFAULT, "MSHookMessageEx");
        if (!hook) { record(@"missingHookAPI", CGSizeZero, CGSizeZero); return; }
        struct { const char *cls; const char *sel; IMP replacement; IMP *original; } hooks[] = {
            {"SBDisplayItemLayoutAttributesCalculator", "layoutRestrictionInfoForItem:", (IMP)restrictions, (IMP *)&originalRestrictions}
            ,{"SBDisplayItemLayoutGrid", "_gridForBounds:contentOrientation:layoutRestrictionInfo:screenScale:windowingConfiguration:", (IMP)grid, (IMP *)&originalGrid}
            ,{"SBDeviceApplicationSceneHandle", "_modifyApplicationSceneSettings:fromRequestContext:entity:", (IMP)sceneSettings, (IMP *)&originalSceneSettings}
            ,{"SBDeviceApplicationSceneView", "_layoutLiveHostView:", (IMP)hostLayout, (IMP *)&originalHostLayout}
            ,{"_UIScenePresentationView", "_updateFrameAndTransform", (IMP)presentationUpdate, (IMP *)&originalPresentationUpdate}
            ,{"_UISceneLayerHostContainerView", "didMoveToSuperview", (IMP)hostMove, (IMP *)&originalHostMove}
            ,{"_UISceneLayerHostContainerView", "setFrame:", (IMP)layerFrame, (IMP *)&originalLayerFrame}
        };
        for (unsigned i = 0; i < sizeof(hooks)/sizeof(hooks[0]); i++) {
            Class cls = objc_getClass(hooks[i].cls); SEL sel = sel_registerName(hooks[i].sel);
            if (class_getInstanceMethod(cls, sel)) hook(cls, sel, hooks[i].replacement, hooks[i].original);
        }
        record(@"loadedFrameRestore", CGSizeZero, CGSizeZero);
    }
}
