#import <Foundation/Foundation.h>
#import "TPPrefsObserver.h"

// Run as a standalone iOS 26 executable. Its defaults domain is separate from
// SpringBoard, and the original value is restored before the process exits.
int main(void) {
    @autoreleasepool {
        if (@available(iOS 26.0, *)) {
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            NSString *key = @"TPIsFloatingDockSupported";
            id previous = [defaults objectForKey:key];
            @try {
                [defaults removeObjectForKey:key];
                TPPrefsObserver *prefs = [TPPrefsObserver new];
                NSCAssert(prefs.isFloatingDockSupported, @"Missing key must match Settings default YES");
                puts("PASS missing -> enabled");

                [defaults setBool:NO forKey:key];
                [prefs observeValueForKeyPath:nil ofObject:nil change:nil context:nil];
                NSCAssert(!prefs.isFloatingDockSupported, @"Explicit NO must remain disabled");
                puts("PASS explicit NO -> disabled");

                [defaults setBool:YES forKey:key];
                [prefs observeValueForKeyPath:nil ofObject:nil change:nil context:nil];
                NSCAssert(prefs.isFloatingDockSupported, @"Explicit YES must remain enabled");
                puts("PASS explicit YES -> enabled");
            } @finally {
                if (previous) {
                    [defaults setObject:previous forKey:key];
                } else {
                    [defaults removeObjectForKey:key];
                }
                [defaults synchronize];
            }
            return 0;
        }
        fputs("Requires iOS 26 or later\n", stderr);
        return 2;
    }
}
