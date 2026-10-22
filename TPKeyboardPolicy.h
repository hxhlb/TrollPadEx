#import <UIKit/UIKit.h>

// A phone window can carry Pad traits while the keyboard option is disabled.
// Restore only that idiom; preserve real iPads and non-phone keyboard contexts.
static inline UIUserInterfaceIdiom TPPhoneKeyboardIdiom(UIUserInterfaceIdiom idiom,
    BOOL enabled, BOOL iPadKeyboardEnabled, BOOL phoneHardware) {
    return enabled && !iPadKeyboardEnabled && phoneHardware && idiom == UIUserInterfaceIdiomPad
        ? UIUserInterfaceIdiomPhone : idiom;
}
