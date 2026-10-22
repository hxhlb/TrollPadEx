#import <Foundation/Foundation.h>
// A restriction, never a capability force-enable. Applied by native setters.
void TPInstallDockLibraryHooks(BOOL (*shouldHide)(void));
