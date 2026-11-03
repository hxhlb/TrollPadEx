#!/usr/bin/env python3.11
"""Production animation callbacks with isolated host fixtures, no device UI."""
import argparse
from pathlib import Path
import subprocess
import tempfile
from test_main_switcher_factory import contract, ROOT, RTK

FIXTURES = r'''
static id nativeTransition, nativeGesture;
@interface SBTransitionSwitcherModifierEvent : NSObject
@property NSInteger fromEnvironmentMode,toEnvironmentMode,fromPeekConfiguration,toPeekConfiguration;
@property NSUInteger phase;
@property(strong) id fromAppLayout,toAppLayout,fromFloatingAppLayout,toFloatingAppLayout;
@property(strong) id fromAppExposeBundleID,toAppExposeBundleID,transitionID;
@property BOOL isBannerUnfurlTransition,isContinuityTransition,isMoveDisplaysTransition;
@property BOOL toFloatingSwitcherVisible;
@end
@implementation SBTransitionSwitcherModifierEvent @end
@interface SBGestureSwitcherModifierEvent : NSObject
@property NSInteger gestureType;
@end
@implementation SBGestureSwitcherModifierEvent @end
@interface SBMainSwitcherRoutingSwitcherModifier : NSObject @end
@implementation SBMainSwitcherRoutingSwitcherModifier @end
@interface _SBHomeScreenFloorSwitcherModifier : NSObject
@property(nonatomic,weak) id parentModifier;
@property NSInteger state;
@end
@implementation _SBHomeScreenFloorSwitcherModifier @end
@interface SBHomeGestureRootSwitcherModifier : NSObject
@property NSInteger mode;
@property(strong) id deck;
@property BOOL resignsTransitionIntoAppSwitcher;
- (instancetype)initWithStartingEnvironmentMode:(NSInteger)mode multitaskingModifier:(id)deck;
@end
@implementation SBHomeGestureRootSwitcherModifier
- (instancetype)initWithStartingEnvironmentMode:(NSInteger)mode multitaskingModifier:(id)deck {
    self=[super init];if(self){_mode=mode;_deck=deck;}return self;
}
@end
@interface SBHomeToDeckSwitcherModifier : NSObject
@property NSInteger direction;
@property(strong) id identifier,deck;
- (instancetype)initWithTransitionID:(id)identifier direction:(NSInteger)direction multitaskingModifier:(id)deck;
@end
@implementation SBHomeToDeckSwitcherModifier
- (instancetype)initWithTransitionID:(id)identifier direction:(NSInteger)direction multitaskingModifier:(id)deck {
    self=[super init];if(self){_identifier=identifier;_direction=direction;_deck=deck;}return self;
}
@end
@interface SBDeckToFullScreenSwitcherModifier : SBHomeToDeckSwitcherModifier
@property(strong) id layout;
- (instancetype)initWithTransitionID:(id)identifier direction:(NSInteger)direction fullScreenAppLayout:(id)layout deckModifier:(id)deck;
@end
@implementation SBDeckToFullScreenSwitcherModifier
- (instancetype)initWithTransitionID:(id)identifier direction:(NSInteger)direction fullScreenAppLayout:(id)layout deckModifier:(id)deck {
    self=[super initWithTransitionID:identifier direction:direction multitaskingModifier:deck];
    if(self)_layout=layout;return self;
}
@end
@interface SBMainSwitcherRootSwitcherModifier (AnimationFixtures)
- (id)transitionModifierForMainTransitionEvent:(id)event;
- (id)gestureModifierForGestureEvent:(id)event;
@end
@implementation SBMainSwitcherRootSwitcherModifier (AnimationFixtures)
// iPad root returns nil for these ordinary events when effective style is Phone.
- (id)transitionModifierForMainTransitionEvent:(id)event { return nativeTransition; }
- (id)gestureModifierForGestureEvent:(id)event { return nativeGesture; }
@end
'''

MAIN = r'''
#define CHECK(e,message) do {if(!(e)){fprintf(stderr,"FAIL %s; iOS=%ld\n",message,(long)testMajor);return 1;}}while(0)
int main(void){@autoreleasepool{
    Class rootClass=SBMainSwitcherRootSwitcherModifier.class;
    SEL selectors[]={@selector(_newMultitaskingModifierForEnvironmentMode:),@selector(floorModifierForTransitionEvent:),
        @selector(floorModifierForGestureEvent:),@selector(transitionModifierForMainTransitionEvent:),@selector(gestureModifierForGestureEvent:),@selector(multitaskingModifierForEvent:)};
    IMP originals[6];for(unsigned i=0;i<6;i++)originals[i]=class_getMethodImplementation(rootClass,selectors[i]);
    for(NSNumber *version in @[@16,@17,@18,@26,@27]){
        testMajor=version.integerValue;hookCalls=0;install();
        SBMainSwitcherRootSwitcherModifier *root=[rootClass new];root->_environmentMode=1;
        SBGestureSwitcherModifierEvent *gesture=[SBGestureSwitcherModifierEvent new];gesture.gestureType=1;
        SBTransitionSwitcherModifierEvent *event=[SBTransitionSwitcherModifierEvent new];event.transitionID=NSObject.new;
        event.fromEnvironmentMode=1;event.toEnvironmentMode=2;
        for(unsigned mask=0;mask<4;mask++){
            trollPadEnabled=mask&1;useiPadAppSwitcher=!!(mask&2);BOOL active=testMajor==17&&trollPadEnabled&&!useiPadAppSwitcher;
            SBDeckSwitcherModifier *subtree=[root multitaskingModifierForEvent:nil];
            CHECK(active?[subtree isMemberOfClass:SBDeckSwitcherModifier.class]:subtree==nil,"native phone Deck subtree present during Home idle");
            if(active){root.currentMultitasking=subtree;subtree.parentModifier=root;}
            else if(root.currentMultitasking){root.currentMultitasking.state=1;root.currentMultitasking.parentModifier=nil;root.currentMultitasking=nil;}
            root.floorFixture=SBMainSwitcherRoutingSwitcherModifier.new;
            event.toEnvironmentMode=1;event.toPeekConfiguration=1;
            id home=[root floorModifierForTransitionEvent:event];
            CHECK(active?[home isMemberOfClass:_SBHomeScreenFloorSwitcherModifier.class]:home==root.floorFixture,
                "ordinary idle Home uses the native phone Home floor instead of the iPad route");
            if(active){
                ((_SBHomeScreenFloorSwitcherModifier *)home).parentModifier=root;
                root.currentFloor=(SBDeckSwitcherModifier *)home;
                CHECK([root floorModifierForGestureEvent:nil]==home,"active Home floor reused before re-entry");
                CHECK([root multitaskingModifierForEvent:nil]==subtree&&subtree.state==0,"Home floor does not retire the native Deck child");
                root.floorFixture=SBMixedGridSwitcherModifier.new;
                CHECK([root floorModifierForGestureEvent:nil]==subtree,"switcher floor uses the same native Deck child");
            }
            SBHomeGestureRootSwitcherModifier *g=[root gestureModifierForGestureEvent:gesture];
            CHECK(active?[g isMemberOfClass:SBHomeGestureRootSwitcherModifier.class]:g==nil,"bottom-edge gesture needs a native Deck driver");
            if(active)CHECK(g.mode==1&&g.resignsTransitionIntoAppSwitcher&&[g.deck isMemberOfClass:SBDeckSwitcherModifier.class],"native gesture initializer/flag/Deck preserved");
            for(NSArray *pair in @[@[@1,@2],@[@2,@1],@[@3,@2],@[@2,@3]]){
                event.fromEnvironmentMode=[pair[0] integerValue];event.toEnvironmentMode=[pair[1] integerValue];
                event.fromAppLayout=NSObject.new;event.toAppLayout=NSObject.new;
                SBHomeToDeckSwitcherModifier *t=[root transitionModifierForMainTransitionEvent:event];
                BOOL home=event.fromEnvironmentMode==1||event.toEnvironmentMode==1;
                CHECK(active?[t isMemberOfClass:home?SBHomeToDeckSwitcherModifier.class:SBDeckToFullScreenSwitcherModifier.class]:t==nil,"ordinary entry/exit must return native transition instead of nil");
                if(active){
                    CHECK(t.identifier==event.transitionID&&t.direction==(event.toEnvironmentMode==2?1:0),"native transition ID and direction retained");
                    CHECK([t.deck isMemberOfClass:SBDeckSwitcherModifier.class]&&((SBDeckSwitcherModifier *)t.deck).state==0,"transition gets a fresh live Deck");
                    if(!home)CHECK(((SBDeckToFullScreenSwitcherModifier *)t).layout==(event.toEnvironmentMode==2?event.fromAppLayout:event.toAppLayout),"correct entering/exiting app layout");
                    CHECK(((SBHomeToDeckSwitcherModifier *)[root transitionModifierForMainTransitionEvent:event]).deck!=t.deck,"transition Deck never retained across requests");
                }
            }
        }
        CHECK(hookCalls==(testMajor==17?6:(testMajor>=26?1:0)),"phone subtree and animation hooks confined to iOS17; other paths unchanged");
        trollPadEnabled=YES;useiPadAppSwitcher=NO;
        root.floorFixture=SBMainSwitcherRoutingSwitcherModifier.new;
        // Main root writes toEnvironmentMode before processing transition phases.
        root->_environmentMode=1;
        event.fromEnvironmentMode=3;event.toEnvironmentMode=1;event.toPeekConfiguration=1;
        for(NSNumber *phase in @[@0,@1,@2]){
            event.phase=phase.unsignedIntegerValue;
            CHECK([root floorModifierForTransitionEvent:event]==root.floorFixture,
                "foreground App minimization must retain its native floor until transitionDidEnd");
            CHECK([root floorModifierForGestureEvent:nil]==root.floorFixture,
                "gesture-floor queries must also preserve an unfinished App return after root mode becomes Home");
        }
        event.fromEnvironmentMode=1;event.phase=1;
        CHECK([root floorModifierForTransitionEvent:event]==root.floorFixture,
            "nested Home update cannot prematurely finish an App return");
        event.fromEnvironmentMode=3;
        event.phase=3;
        id settled=[root floorModifierForTransitionEvent:event];
        CHECK(testMajor==17?[settled isMemberOfClass:_SBHomeScreenFloorSwitcherModifier.class]:settled==root.floorFixture,
            "idle Home policy is restored after App minimization completes");
        event.fromEnvironmentMode=3;event.toEnvironmentMode=1;event.phase=1;
        CHECK([root floorModifierForTransitionEvent:event]==root.floorFixture,"new App return begins natively");
        event.toEnvironmentMode=3;event.phase=3;
        CHECK([root floorModifierForTransitionEvent:event]==root.floorFixture,"cancelled return stays in native App route");
        event.fromEnvironmentMode=1;event.toEnvironmentMode=1;event.phase=1;
        id afterCancel=[root floorModifierForTransitionEvent:event];
        CHECK(testMajor==17?[afterCancel isMemberOfClass:_SBHomeScreenFloorSwitcherModifier.class]:afterCancel==root.floorFixture,
            "cancellation clears the pending App-return guard");
        event.fromEnvironmentMode=2;event.phase=1;
        id switcherExit=[root floorModifierForTransitionEvent:event];
        CHECK(testMajor==17?[switcherExit isMemberOfClass:_SBHomeScreenFloorSwitcherModifier.class]:switcherExit==root.floorFixture,
            "existing switcher-to-Home animation path stays enabled");
        event.fromEnvironmentMode=1;event.phase=0;
        event.toEnvironmentMode=1;event.toPeekConfiguration=1;
        event.toFloatingSwitcherVisible=YES;
        CHECK([root floorModifierForTransitionEvent:event]==root.floorFixture,"Home with floating switcher keeps native window route");
        event.toFloatingSwitcherVisible=NO;event.toPeekConfiguration=2;
        CHECK([root floorModifierForTransitionEvent:event]==root.floorFixture,"Home Peek keeps native route");
        event.toPeekConfiguration=1;event.toEnvironmentMode=3;
        CHECK([root floorModifierForTransitionEvent:event]==root.floorFixture,"App mode keeps native window route");
        root->_environmentMode=1;root->_floatingSwitcherVisible=YES;
        CHECK([root floorModifierForGestureEvent:nil]==root.floorFixture,"gesture Home with floating switcher keeps native route");
        root->_floatingSwitcherVisible=NO;root->_isInPeekState=YES;
        CHECK([root floorModifierForGestureEvent:nil]==root.floorFixture,"gesture Home Peek keeps native route");
        root->_isInPeekState=NO;
        if(testMajor==17){
            _SBHomeScreenFloorSwitcherModifier *old=[root floorModifierForGestureEvent:nil];
            old.state=1;old.parentModifier=nil;root.currentFloor=nil;
            id fresh=[root floorModifierForGestureEvent:nil];
            CHECK([fresh isMemberOfClass:_SBHomeScreenFloorSwitcherModifier.class]&&fresh!=old,
                "released/completed Home floor is not kept alive or reused");
            SBDeckSwitcherModifier *retired=root.currentMultitasking;
            retired.state=1;retired.parentModifier=nil;root.currentMultitasking=nil;
            SBDeckSwitcherModifier *replacement=[root multitaskingModifierForEvent:nil];
            CHECK(replacement!=retired&&replacement.state==0,"retired Deck subtree is rebuilt through the native factory");
        }
        event.fromEnvironmentMode=1;event.toEnvironmentMode=2;
        id native=NSObject.new;nativeTransition=native;nativeGesture=native;
        CHECK([root transitionModifierForMainTransitionEvent:event]==native&&[root gestureModifierForGestureEvent:gesture]==native,"non-nil native specialized result retains identity");
        nativeTransition=nil;nativeGesture=nil;
        nativeMultitaskingFixture=native;
        CHECK([root multitaskingModifierForEvent:nil]==native,"non-nil native subtree preserved");
        nativeMultitaskingFixture=nil;
        for(NSString *key in @[@"fromFloatingAppLayout",@"toFloatingAppLayout",@"fromAppExposeBundleID",@"toAppExposeBundleID"]){
            [event setValue:native forKey:key];CHECK([root transitionModifierForMainTransitionEvent:event]==nil,"floating/App Expose transitions untouched");[event setValue:nil forKey:key];
        }
        for(NSString *key in @[@"isBannerUnfurlTransition",@"isContinuityTransition",@"isMoveDisplaysTransition"]){
            [event setValue:@YES forKey:key];CHECK([root transitionModifierForMainTransitionEvent:event]==nil,"special native transition routes untouched");[event setValue:@NO forKey:key];
        }
        for(NSNumber *peek in @[@2,@3]){
            event.toPeekConfiguration=peek.integerValue;CHECK([root transitionModifierForMainTransitionEvent:event]==nil,"peek route untouched");
        }
        event.toPeekConfiguration=0;event.fromEnvironmentMode=1;event.toEnvironmentMode=3;
        CHECK([root transitionModifierForMainTransitionEvent:event]==nil,"unrelated environment transition untouched");
        gesture.gestureType=3;CHECK([root gestureModifierForGestureEvent:gesture]==nil,"other gestures untouched");
        gesture.gestureType=1;root->_environmentMode=0;CHECK([root gestureModifierForGestureEvent:gesture]==nil,"unknown root mode untouched");
        root->_environmentMode=2;root.currentFloor=nil;CHECK([root gestureModifierForGestureEvent:gesture]==nil,"App Expose/non-Deck switcher gesture untouched");
        root.currentFloor=SBDeckSwitcherModifier.new;
        id g=[root gestureModifierForGestureEvent:gesture];CHECK(testMajor==17?g!=nil:g==nil,"active phone switcher gesture supported");
        for(unsigned i=0;i<6;i++){Method m=class_getInstanceMethod(rootClass,selectors[i]);class_replaceMethod(rootClass,selectors[i],originals[i],method_getTypeEncoding(m));}
    }
    puts("PASS production animation/idle Home factories: native Home floor, phone gesture + four entry/exit routes; released-floor/float/Peek/native/OS/master/default fallbacks");
}return 0;}
'''


def run(source):
    generated = contract(source).split('#define CHECK', 1)[0]
    generated = generated.replace('@interface SBMainSwitcherRootSwitcherModifier : NSObject\n',
        '@interface SBMainSwitcherRootSwitcherModifier : NSObject { @public NSInteger _environmentMode; BOOL _floatingSwitcherVisible, _isInPeekState; }\n')
    generated = generated.replace('#define objc_getClass TestClass', FIXTURES + '\n#define objc_getClass TestClass')
    with tempfile.TemporaryDirectory(prefix='trollpad-animation-contract-') as directory:
        p = Path(directory)
        (p / 'test.m').write_text(generated + MAIN)
        r = subprocess.run(RTK + ['clang', '-fobjc-arc', '-framework', 'Foundation', str(p / 'test.m'), '-o', str(p / 'test')], capture_output=True, text=True)
        if r.returncode:
            raise RuntimeError(r.stderr)
        return subprocess.run(RTK + [str(p / 'test')], capture_output=True, text=True, timeout=10)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--baseline-ref')
    args = parser.parse_args()
    if args.baseline_ref:
        old = subprocess.check_output(RTK + ['git', 'show', args.baseline_ref + ':TweakSB.x'], cwd=ROOT, text=True)
        result = run(old)
        assert result.returncode and 'iOS=17' in result.stderr, result.stdout + result.stderr
        print('PASS baseline regression reproduced: ' + result.stderr.strip())
    result = run((ROOT / 'TweakSB.x').read_text())
    assert result.returncode == 0, result.stdout + result.stderr
    print(result.stdout.strip())


if __name__ == '__main__':
    main()
