#import <Foundation/Foundation.h>

@interface TPPrefsObserver : NSObject
@property(nonatomic, assign) BOOL allowLandscapeHomeScreen, forceEnableMedusaForLandscapeOnlyApps, hideStageManagerResizeCorners, useiPadAppSwitchingAnimation, isFloatingDockSupported, scaleGridSwitcher, mirrorAppSwitcher;
@property(nonatomic, assign) NSInteger stageManagerSide;
@property(nonatomic, assign) BOOL scaleAppWindows;
@property(nonatomic, assign) BOOL useiPadAppSwitcher;
@end
