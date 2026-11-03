#!/usr/bin/env python3.11
"""Run production factory/installation code with host-only native-path fixtures."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
RTK = ['/opt/homebrew/bin/rtk', 'proxy']


def contract(source):
    start = source.index('typedef id TPMainSwitcherFactoryFunction')
    factory = source[start:source.index('\nstatic BOOL canInstallStageManagerCapabilityHooks', start)]
    anchor = source.index('        Method mainPresentation =')
    start = source.rfind('\n    if (', 0, anchor) + 1
    declaration = source.rfind('\n    NSInteger mainSwitcherVersion =', 0, start)
    if declaration >= 0 and source[declaration:start].count('\n') <= 2:
        start = declaration + 1
    end = source.index('\n\n    if (', anchor)
    install = source[start:end].replace('@available(iOS 26.0, *)', 'testMajor >= 26')
    fixture = r'''
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdio.h>
static BOOL trollPadEnabled, useiPadAppSwitcher, missingDeck, wrongABI, missingFactory;
static NSInteger testMajor;
static unsigned hookCalls, originalCalls, floorCalls;
static id nativeMultitaskingFixture;
static Class TPPhoneDeckClass;
@interface SBDeckSwitcherModifier : NSObject
@property(nonatomic,weak) id parentModifier;
@property(nonatomic) NSInteger state;
@end
@implementation SBDeckSwitcherModifier @end
@interface SBMixedGridSwitcherModifier : NSObject @end
@implementation SBMixedGridSwitcherModifier @end
@interface AppExposeFloor : SBMixedGridSwitcherModifier @end
@implementation AppExposeFloor @end
static id nativeFloor(id root);
@interface SBMainSwitcherRootSwitcherModifier : NSObject
@property(nonatomic,strong) id floorFixture;
@property(nonatomic,strong) SBDeckSwitcherModifier *currentFloor;
@property(nonatomic,strong) SBDeckSwitcherModifier *currentMultitasking;
- (id)floorModifier;
- (id)multitaskingModifier;
- (id)multitaskingModifierForEvent:(id)event;
- (id)_newMultitaskingModifierForEnvironmentMode:(NSInteger)mode;
- (id)floorModifierForTransitionEvent:(id)event;
- (id)floorModifierForGestureEvent:(id)event;
@end
@implementation SBMainSwitcherRootSwitcherModifier
- (id)floorModifier { return self.currentFloor; }
- (id)multitaskingModifier { return self.currentMultitasking; }
- (id)multitaskingModifierForEvent:(id)event { return nativeMultitaskingFixture; }
- (id)_newMultitaskingModifierForEnvironmentMode:(NSInteger)mode {
    originalCalls++;
    // iOS 17.3.1 IPSW: mode 2 precedes the effectiveSwitcherStyle check.
    return mode == 2 ? [SBMixedGridSwitcherModifier new] : [NSObject new];
}
- (id)floorModifierForTransitionEvent:(id)event { return nativeFloor(self); }
// The native gesture selector branches straight to the floor implementation.
- (id)floorModifierForGestureEvent:(id)event { return nativeFloor(self); }
@end
static id nativeFloor(id root) { floorCalls++; return [root floorFixture]; }
@interface WrongFactory : NSObject
- (id)_newMultitaskingModifierForEnvironmentMode:(id)mode;
- (id)floorModifierForTransitionEvent:(NSInteger)event;
- (id)floorModifierForGestureEvent:(NSInteger)event;
@end
@implementation WrongFactory
- (id)_newMultitaskingModifierForEnvironmentMode:(id)mode { return nil; }
- (id)floorModifierForTransitionEvent:(NSInteger)event { return nil; }
- (id)floorModifierForGestureEvent:(NSInteger)event { return nil; }
@end
@interface TestProcessInfo : NSObject
+ (instancetype)processInfo;
- (NSOperatingSystemVersion)operatingSystemVersion;
@end
@implementation TestProcessInfo
+ (instancetype)processInfo { return [self new]; }
- (NSOperatingSystemVersion)operatingSystemVersion { return (NSOperatingSystemVersion){testMajor,0,0}; }
@end
static Class TestClass(const char *name) {
    if (!strcmp(name,"SBMainSwitcherRootSwitcherModifier"))
        return missingFactory ? Nil : (wrongABI ? WrongFactory.class : SBMainSwitcherRootSwitcherModifier.class);
    if (!strcmp(name,"SBDeckSwitcherModifier") && missingDeck) return Nil;
    return objc_getClass(name);
}
static void TPPreparePhoneSwitcherCompatibility(void) {
    TPPhoneDeckClass = missingDeck ? Nil : SBDeckSwitcherModifier.class;
}
static void MSHookMessageEx(Class cls, SEL sel, IMP imp, IMP *original) {
    Method method = class_getInstanceMethod(cls,sel);
    *original = method_getImplementation(method);
    class_replaceMethod(cls,sel,imp,method_getTypeEncoding(method)); hookCalls++;
}
#define objc_getClass TestClass
#define NSProcessInfo TestProcessInfo
'''
    main = r'''
#define CHECK(e,message) do { if (!(e)) { fprintf(stderr,"FAIL %s; iOS=%ld\n",message,(long)testMajor); return 1; } } while (0)
int main(void) { @autoreleasepool {
    Class cls = SBMainSwitcherRootSwitcherModifier.class;
    SEL sel = @selector(_newMultitaskingModifierForEnvironmentMode:);
    Method method = class_getInstanceMethod(cls,sel);
    IMP native = method_getImplementation(method);
    SEL transition = @selector(floorModifierForTransitionEvent:), gesture = @selector(floorModifierForGestureEvent:);
    Method transitionMethod = class_getInstanceMethod(cls,transition), gestureMethod = class_getInstanceMethod(cls,gesture);
    IMP nativeTransition = method_getImplementation(transitionMethod), nativeGesture = method_getImplementation(gestureMethod);
    for (NSNumber *version in @[@16,@17,@18,@26,@27]) {
        testMajor = version.integerValue; hookCalls = 0;
        class_replaceMethod(cls,sel,native,method_getTypeEncoding(method));
        install();
        BOOL expectedHook = testMajor == 17 || testMajor >= 26;
        TPMainSwitcherFactoryFunction *call = (TPMainSwitcherFactoryFunction *)method_getImplementation(method);
        SBMainSwitcherRootSwitcherModifier *root = [cls new];
        root.floorFixture = [SBMixedGridSwitcherModifier new];
        id cachedFloor = nil;
        for (unsigned mask=0; mask<4; mask++) {
            trollPadEnabled = mask & 1; useiPadAppSwitcher = !!(mask & 2);
            originalCalls = 0;
            id result = call(root,sel,2);
            BOOL phone = expectedHook && trollPadEnabled && !useiPadAppSwitcher;
            CHECK([result isMemberOfClass:phone ? SBDeckSwitcherModifier.class : SBMixedGridSwitcherModifier.class],
                "mode 2 must create phone Deck only for enabled tweak + disabled iPad option");
            CHECK(originalCalls == (phone ? 0 : 1), "original called once on passthrough");
            floorCalls = 0;
            BOOL phoneFloor = testMajor == 17 && trollPadEnabled && !useiPadAppSwitcher;
            id t = [root floorModifierForTransitionEvent:nil];
            if (phoneFloor) {
                root.currentFloor = t; root.currentFloor.parentModifier = root;
            } else if (root.currentFloor) {
                root.currentFloor.state = 1; root.currentFloor.parentModifier = nil; root.currentFloor = nil;
            }
            id g = [root floorModifierForGestureEvent:nil];
            CHECK([t isMemberOfClass:phoneFloor ? SBDeckSwitcherModifier.class : SBMixedGridSwitcherModifier.class],
                "actual transition floor must replace direct MixedGrid allocation on iOS17");
            CHECK(g == (phoneFloor ? t : root.floorFixture) && floorCalls == 2,
                "direct gesture path shares cached Deck and calls each original once");
            if (phoneFloor) cachedFloor = t;
            if (!phoneFloor) CHECK(t == root.floorFixture,"native floor identity retained on passthrough");
        }
        CHECK(hookCalls == (testMajor == 17 ? 3 : (expectedHook ? 1 : 0)), "floor hooks iOS17 only; existing 26+ hook preserved");
        trollPadEnabled = YES; useiPadAppSwitcher = NO; originalCalls = 0;
        if (testMajor == 17) {
            SBDeckSwitcherModifier *second = [root floorModifierForTransitionEvent:nil];
            CHECK(second != cachedFloor && second.state == 0,"second opening must not reuse a removed/completed Deck");
            root.currentFloor = second; second.parentModifier = root;
            CHECK([root floorModifierForGestureEvent:nil] == second,"attached active floor reused within one session");
            for (unsigned cycle=0;cycle<3;cycle++) {
                SBDeckSwitcherModifier *previous = root.currentFloor;
                previous.state = 1; previous.parentModifier = nil; root.currentFloor = nil;
                SBDeckSwitcherModifier *next = [root floorModifierForTransitionEvent:nil];
                CHECK(next != previous && next.state == 0,"repeated entry creates a live Deck after native removal");
                root.currentFloor = next; next.parentModifier = root;
            }
            SBMainSwitcherRootSwitcherModifier *other = [cls new]; other.floorFixture = [SBMixedGridSwitcherModifier new];
            SBDeckSwitcherModifier *otherFloor = [other floorModifierForTransitionEvent:nil];
            other.currentFloor = otherFloor; otherFloor.parentModifier = other;
            CHECK([otherFloor isMemberOfClass:SBDeckSwitcherModifier.class] && otherFloor != root.currentFloor,
                "different roots never share their Deck");
            root.currentFloor = otherFloor;
            CHECK([root floorModifierForTransitionEvent:nil] != otherFloor,"never reuse a Deck owned by another root");
            root.currentFloor = second; second.parentModifier = root; second.state = 1;
            CHECK([root floorModifierForTransitionEvent:nil] != second,"completed floor is not reused even before detach");
            root.currentFloor = nil;
        }
        root.floorFixture = [AppExposeFloor new];
        CHECK([root floorModifierForTransitionEvent:nil] == root.floorFixture &&
            [root floorModifierForGestureEvent:nil] == root.floorFixture,"specialized grid/App Expose results untouched");
        root.floorFixture = nil;
        CHECK([root floorModifierForTransitionEvent:nil] == nil &&
            [root floorModifierForGestureEvent:nil] == nil,"nil floor preserved");
        CHECK([call(root,sel,3) isMemberOfClass:NSObject.class] && originalCalls == 1,
            "other environment modes preserve original factory");
        if (expectedHook) {
            missingDeck = YES; originalCalls = 0;
            CHECK([call(root,sel,2) isMemberOfClass:SBMixedGridSwitcherModifier.class] && originalCalls == 1,
                "missing Deck falls back to original");
            missingDeck = NO;
        }
        class_replaceMethod(cls,sel,native,method_getTypeEncoding(method));
        class_replaceMethod(cls,transition,nativeTransition,method_getTypeEncoding(transitionMethod));
        class_replaceMethod(cls,gesture,nativeGesture,method_getTypeEncoding(gestureMethod));
    }
    testMajor = 17; hookCalls = 0;
    wrongABI = YES; install(); wrongABI = NO;
    missingFactory = YES; install(); missingFactory = NO;
    missingDeck = YES; install(); missingDeck = NO;
    CHECK(hookCalls == 0,"wrong ABI and missing classes skipped");
    puts("PASS production factories/lifetime: direct floor -> active owned Deck; removed/completed/cross-root floors replaced; repeated sessions; specialized/nil/original/OS/default/ABI fallbacks");
} return 0; }
'''
    return fixture + factory + '\nstatic void install(void) {\n' + install + '\n}\n' + main


def run(source):
    with tempfile.TemporaryDirectory(prefix='trollpad-switcher-contract-') as directory:
        path = Path(directory)
        (path / 'test.m').write_text(contract(source))
        result = subprocess.run(RTK + ['clang', '-fobjc-arc', '-framework', 'Foundation',
            str(path / 'test.m'), '-o', str(path / 'test')], capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stderr)
        return subprocess.run(RTK + [str(path / 'test')], capture_output=True, text=True, timeout=10)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--baseline-ref')
    args = parser.parse_args()
    if args.baseline_ref:
        source = subprocess.check_output(RTK + ['git', 'show', args.baseline_ref + ':TweakSB.x'], cwd=ROOT, text=True)
        old = run(source)
        assert old.returncode and 'iOS=17' in old.stderr, old.stdout + old.stderr
        print('PASS baseline regression reproduced: ' + old.stderr.strip())
    fixed = run((ROOT / 'TweakSB.x').read_text())
    assert fixed.returncode == 0, fixed.stdout + fixed.stderr
    print(fixed.stdout.strip())


if __name__ == '__main__':
    main()
