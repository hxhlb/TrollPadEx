#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <sys/utsname.h>

// Read-only VM geometry observer. Never included in a DEB.
static NSMapTable *presentations;
static void (*originalLayout)(id, SEL, UIView *);
static void layout(id self, SEL cmd, UIView *host) {
    if (host) [presentations setObject:host forKey:self];
    originalLayout(self, cmd, host);
}
static id get(id object, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    return [object respondsToSelector:sel] ? ((id (*)(id, SEL))objc_msgSend)(object, sel) : nil;
}
static NSArray *rect(CGRect frame) {
    return @[@(frame.origin.x), @(frame.origin.y), @(frame.size.width), @(frame.size.height)];
}
static id field(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable([object class], name);
    return ivar && ivar_getTypeEncoding(ivar)[0] == '@' ? object_getIvar(object, ivar) : nil;
}
static NSArray *queryChain(id personality) {
    NSMutableArray *nodes = [NSMutableArray array];
    id node = field(personality, "_rootModifier");
    for (int i=0; node && i<32; i++) {
        NSMutableDictionary *row = [@{@"class":NSStringFromClass([node class]),
            @"parent":NSStringFromClass([field(node, "_parentModifier") class]) ?: @"nil"} mutableCopy];
        Ivar flag = class_getInstanceVariable([node class], "_switcherModifierInteroperabilityEnabled");
        if (flag) row[@"interop"] = @(*(BOOL *)((uint8_t *)(__bridge void *)node+ivar_getOffset(flag)));
        [nodes addObject:row];
        id next = field(node, "_nextQueryModifier");
        if (next == node) break;
        node = next;
    }
    return nodes;
}
static void capture(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableArray *rows = [NSMutableArray array];
        for (UIView *owner in presentations.keyEnumerator.allObjects) {
            id handle = get(owner, @"sceneHandle");
            id item = get(handle, @"displayItemRepresentation");
            UIView *host = get([presentations objectForKey:owner], @"hostContainerView");
            id settings = get(get(handle, @"sceneIfExists"), @"settings");
            CGRect scene = [settings respondsToSelector:@selector(frame)] ? ((CGRect (*)(id, SEL))objc_msgSend)(settings, @selector(frame)) : CGRectZero;
            CGRect viewport = [owner convertRect:owner.bounds toView:nil];
            CGRect frame = host.superview ? [host convertRect:host.bounds toView:nil] : CGRectOffset(host.frame, viewport.origin.x, viewport.origin.y);
            [rows addObject:@{@"bundle":get(item, @"bundleIdentifier") ?: @"", @"scene":get(handle, @"sceneIdentifier") ?: @"",
                @"viewport":rect(viewport), @"canvas":rect(scene), @"host":rect(frame),
                @"bounds":rect(host.bounds), @"scale":@[@(host.transform.a), @(host.transform.d)],
                @"attached":@(owner.window != nil)}];
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:rows options:NSJSONWritingPrettyPrinted error:nil];
        [data writeToFile:@"/var/mobile/Library/Caches/TrollPadEx-window-scaling.json" atomically:YES];
        NSMutableArray *switchers = [NSMutableArray array];
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            id switcher = get(scene, @"switcherController");
            if (!switcher) continue;
            id content = get(switcher, @"contentViewController");
            id context = get(switcher, @"windowManagementContext");
            id settings = get(switcher, @"settings");
            [switchers addObject:@{@"content":content ? NSStringFromClass([content class]) : @"nil",
                @"queryChain":queryChain(get(content, @"personality")),
                @"gestureManager":NSStringFromClass([get(switcher, @"gestureManager") class]) ?: @"nil",
                @"personality":NSStringFromClass([get(content, @"personality") class]) ?: @"nil",
                @"rawStyle":[settings valueForKey:@"switcherStyle"] ?: @"nil",
                @"effectiveStyle":[settings valueForKey:@"effectiveSwitcherStyle"] ?: @"nil",
                @"baseStyle":[context valueForKey:@"baseStyle"] ?: @"nil",
                @"automaticStageCreationEnabled":[context valueForKey:@"automaticStageCreationEnabled"] ?: @"nil"}];
        }
        data = [NSJSONSerialization dataWithJSONObject:switchers options:NSJSONWritingPrettyPrinted error:nil];
        [data writeToFile:@"/var/mobile/Library/Caches/TrollPadEx-switcher-capture.json" atomically:YES];
    });
}
__attribute__((constructor)) static void start(void) {
    struct utsname system;
    if (uname(&system) != 0 || !strstr(system.version, "VRESEARCH") ||
        ![NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"]) return;
    presentations = [NSMapTable weakToWeakObjectsMapTable];
    void (*hook)(Class, SEL, IMP, IMP *) = dlsym(RTLD_DEFAULT, "MSHookMessageEx");
    Class cls = objc_getClass("SBDeviceApplicationSceneView");
    SEL sel = NSSelectorFromString(@"_layoutLiveHostView:");
    if (!hook || !class_getInstanceMethod(cls, sel)) return;
    hook(cls, sel, (IMP)layout, (IMP *)&originalLayout);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, capture,
        CFSTR("com.banana.trollpadex/window-scaling-capture"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
