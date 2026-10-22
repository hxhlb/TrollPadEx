#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#import "../../TPKeyboardPolicy.h"

// Standalone simulator/device process. No input preferences or windows changed.
int main(void) {
    @autoreleasepool {
        NSCAssert(TPPhoneKeyboardIdiom(UIUserInterfaceIdiomPad, YES, NO, YES) == UIUserInterfaceIdiomPhone, @"Disabled option must restore phone traits");
        NSCAssert(TPPhoneKeyboardIdiom(UIUserInterfaceIdiomPad, NO, NO, YES) == UIUserInterfaceIdiomPad, @"Master off must preserve native traits");
        NSCAssert(TPPhoneKeyboardIdiom(UIUserInterfaceIdiomPad, YES, YES, YES) == UIUserInterfaceIdiomPad, @"Enabled iPad keyboard must stay native");
        NSCAssert(TPPhoneKeyboardIdiom(UIUserInterfaceIdiomPad, YES, NO, NO) == UIUserInterfaceIdiomPad, @"Real iPad must keep Pad traits");
        NSCAssert(TPPhoneKeyboardIdiom(UIUserInterfaceIdiomPhone, YES, NO, YES) == UIUserInterfaceIdiomPhone, @"Native phone remains phone");
        NSCAssert(TPPhoneKeyboardIdiom(UIUserInterfaceIdiomCarPlay, YES, NO, YES) == UIUserInterfaceIdiomCarPlay, @"Other native idioms remain unchanged");
        NSArray *(*layouts)(NSString *, UIUserInterfaceIdiom) = dlsym(RTLD_DEFAULT, "UIKeyboardGetSupportedSoftwareKeyboardsForInputModeAndIdiom");
        NSCAssert(layouts != NULL, @"Native layout selection API is available");
        NSString *mode = @"zh_Hans-Pinyin";
        NSArray *phone = layouts(mode, UIUserInterfaceIdiomPhone);
        NSArray *pad = layouts(mode, UIUserInterfaceIdiomPad);
        NSArray *restored = layouts(mode, TPPhoneKeyboardIdiom(UIUserInterfaceIdiomPad, YES, NO, YES));
        NSLog(@"Native phone layouts: %@; Pad layouts: %@", phone, pad);
        NSCAssert([phone containsObject:@"Pinyin10-Simplified"], @"Phone layouts must include native 9-Key");
        NSCAssert([restored isEqual:phone], @"Restore UIKit's own phone layouts, without inventing a layout");
        Method idiom = class_getInstanceMethod(objc_getClass("UIKBScreenTraits"), @selector(idiom));
        NSCAssert(idiom && strcmp(method_getTypeEncoding(idiom), "q16@0:8") == 0, @"Checked native keyboard trait signature");
        NSDictionary *result = @{@"pass":@YES, @"model":UIDevice.currentDevice.model,
            @"phoneLayouts":phone, @"padLayouts":pad, @"restoredLayouts":restored,
            @"masterOffPreserved":@YES, @"iPadModePreserved":@YES, @"realIPadPreserved":@YES};
        NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
        puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
    }
    return 0;
}
