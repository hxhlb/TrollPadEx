#import <Foundation/Foundation.h>
#import "TPPrefsObserver.h"

// Standalone executable defaults domain, not SpringBoard's preferences.
int main(void) {
    @autoreleasepool {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSString *key = @"TPUseiPadAppSwitcher";
        id previous = [defaults objectForKey:key];
        @try {
            [defaults removeObjectForKey:key];
            TPPrefsObserver *prefs = [TPPrefsObserver new];
            NSCAssert(prefs.useiPadAppSwitcher, @"Missing preference must preserve the iPad switcher");
            puts("PASS missing -> enabled");
            [defaults setBool:NO forKey:key];
            [prefs observeValueForKeyPath:nil ofObject:nil change:nil context:nil];
            NSCAssert(!prefs.useiPadAppSwitcher, @"Explicit NO must select the iPhone switcher");
            puts("PASS explicit NO -> disabled");
            [defaults setBool:YES forKey:key];
            [prefs observeValueForKeyPath:nil ofObject:nil change:nil context:nil];
            NSCAssert(prefs.useiPadAppSwitcher, @"Explicit YES must select the iPad switcher");
            puts("PASS explicit YES -> enabled");
        } @finally {
            if (previous) [defaults setObject:previous forKey:key];
            else [defaults removeObjectForKey:key];
            [defaults synchronize];
        }
    }
    return 0;
}
