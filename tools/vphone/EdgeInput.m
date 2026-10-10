#import <UIKit/UIKit.h>
#import <objc/message.h>
#include <sys/utsname.h>
#include <string.h>

// Test fixture only. This file is not part of either TrollPadEx package.
static id edgeInputAssertion;
static __weak id assertionManager;

static void enableVirtualEdgeInput(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        SEL managerSelector = NSSelectorFromString(@"systemGestureManager");
        if (![scene respondsToSelector:managerSelector]) {
            continue;
        }
        id manager = ((id (*)(id, SEL))objc_msgSend)(scene, managerSelector);
        if (manager == assertionManager && edgeInputAssertion) {
            continue;
        }
        SEL acquire = NSSelectorFromString(@"acquireSystemEdgeGesturesIgnoreHIDEdgeFlagsForReason:");
        if ([manager respondsToSelector:acquire]) {
            id assertion = ((id (*)(id, SEL, id))objc_msgSend)(manager, acquire,
                @"vphone synthetic touchscreen verification");
            if (assertion) {
                edgeInputAssertion = assertion;
                assertionManager = manager;
            }
        }
    }
}

__attribute__((constructor)) static void initializeVirtualEdgeInput(void) {
    struct utsname systemInfo;
    if (uname(&systemInfo) != 0 || !strstr(systemInfo.version, "VRESEARCH")) {
        return;
    }
    for (NSNotificationName name in @[UIApplicationDidFinishLaunchingNotification,
         UISceneDidActivateNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
                enableVirtualEdgeInput();
            }];
    }
    dispatch_async(dispatch_get_main_queue(), ^{ enableVirtualEdgeInput(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{ enableVirtualEdgeInput(); });
}
