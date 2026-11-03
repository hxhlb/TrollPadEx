#!/usr/bin/env python3.11
"""Production entry/idiom/style/startup code with host native-factory fixtures."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
RTK = ['/opt/homebrew/bin/rtk', 'proxy']


def block(source, marker, start=0):
    a=source.index(marker,start);a=source.index('{',a);depth=1;b=a+1
    while depth:
        depth += (source[b]=='{')-(source[b]=='}');b+=1
    return source[a+1:b-1],b


def contract(source):
    helper=''
    if 'static BOOL shouldCreateNativePhoneSwitcher' in source:
        body,_=block(source,'static BOOL shouldCreateNativePhoneSwitcher')
        helper='static BOOL shouldCreateNativePhoneSwitcher(id scene){'+body+'}\n'
    idiom,_=block(source,'- (UIUserInterfaceIdiom)userInterfaceIdiom')
    factory,_=block(source,'- (void)_loadContentViewControllerIfNecessaryForWindowScene:')
    raw,_=block(source,'- (NSInteger)switcherStyle')
    effective,_=block(source,'- (NSInteger)effectiveSwitcherStyle')
    ctor=source.index('%ctor {')
    start=source.index('    useiPadAppSwitcher = pref.useiPadAppSwitcher;',ctor)
    start=source.index('\n',start)+1
    end=source.index('    %init;',start)
    startup=source[start:end]
    start=source.index('    Method phonePresentation =',ctor)
    guard=source.index('    if (@available(iOS 26.0, *))',start)
    _,end=block(source,'    if (@available(iOS 26.0, *))',guard)
    startup+=source[start:end]
    return FIXTURE+helper+'\nstatic UIUserInterfaceIdiom observedIdiom(void){'+idiom.replace('%orig','hardwareIdiom')+'}\n'+\
        'static NSInteger rawStyle(void){'+raw.replace('%orig','originalStyle')+'}\n'+\
        'static NSInteger effectiveStyle(void){'+effective.replace('%orig','originalStyle')+'}\n'+\
        NATIVE+'\nstatic void create(id scene){'+factory.replace('%orig','NativeFactory(scene)')+'}\n'+\
        'static void installPresentation(void){'+startup+'}\n'+MAIN


FIXTURE=r'''
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdio.h>
typedef NSInteger UIUserInterfaceIdiom;
enum{UIUserInterfaceIdiomPhone=0,UIUserInterfaceIdiomPad=1};
static BOOL trollPadEnabled,useiPadAppSwitcher,throwFactory;
static NSInteger testMajor,originalStyle,hardwareIdiom,windowMode;
static uint16_t forcePadIdiom,observedForce;
static unsigned factoryCalls,prepareCalls,hookCalls;
static BOOL nativePhoneRoot,deckController;
@interface Scene : NSObject
@property BOOL isMainDisplayWindowScene;
@end
@implementation Scene @end
@interface TestProcessInfo : NSObject
+ (instancetype)processInfo;
- (NSOperatingSystemVersion)operatingSystemVersion;
@end
@implementation TestProcessInfo
+ (instancetype)processInfo{return [self new];}
- (NSOperatingSystemVersion)operatingSystemVersion{return (NSOperatingSystemVersion){testMajor,0,0};}
@end
@interface SBContinuousExposeRootSwitcherModifier : NSObject
- (id)multitaskingModifierForEvent:(id)event;
@end
@implementation SBContinuousExposeRootSwitcherModifier
- (id)multitaskingModifierForEvent:(id)event{return nil;}
@end
@interface SBMainSwitcherRootSwitcherModifier : NSObject
- (id)_newMultitaskingModifierForEnvironmentMode:(NSInteger)mode;
@end
@implementation SBMainSwitcherRootSwitcherModifier
- (id)_newMultitaskingModifierForEnvironmentMode:(NSInteger)mode{return nil;}
@end
@interface SBDeckSwitcherModifier : NSObject @end
@implementation SBDeckSwitcherModifier @end
static void TPPreparePhoneSwitcherCompatibility(void){prepareCalls++;}
static IMP TPOriginalContinuousExposeFactory,TPOriginalMainSwitcherFactory;
static id TPPhoneContinuousExposeFactory(id self,SEL command,id event){return nil;}
static id TPPhoneMainSwitcherFactory(id self,SEL command,NSInteger mode){return nil;}
static void MSHookMessageEx(Class cls,SEL command,IMP replacement,IMP *original){
 *original=class_getMethodImplementation(cls,command);hookCalls++;
}
#define NSProcessInfo TestProcessInfo
'''

NATIVE=r'''
static void NativeFactory(id scene){
 // 21D61 factory independently selects controller by raw style and root by idiom.
 factoryCalls++;observedForce=forcePadIdiom;
 UIUserInterfaceIdiom idiom=observedIdiom();NSInteger style=rawStyle();
 deckController=style==1||(style==0&&idiom==UIUserInterfaceIdiomPhone);
 nativePhoneRoot=idiom==UIUserInterfaceIdiomPhone;
 if(throwFactory)@throw [NSException exceptionWithName:@"fixture" reason:nil userInfo:nil];
}
'''

MAIN=r'''
#define CHECK(e,message) do{if(!(e)){fprintf(stderr,"FAIL %s OS=%ld\n",message,(long)testMajor);return 1;}}while(0)
int main(void){@autoreleasepool{
 Scene *main=Scene.new;main.isMainDisplayWindowScene=YES;Scene *external=Scene.new;
 for(NSNumber *version in @[@16,@17,@18,@26]){
  testMajor=version.integerValue;
  for(NSNumber *maskValue in @[@1,@0,@2,@3]){
   unsigned mask=maskValue.unsignedIntValue;
   trollPadEnabled=mask&1;useiPadAppSwitcher=!!(mask&2);hardwareIdiom=0;originalStyle=0;
   BOOL nativeEntry=testMajor==17&&trollPadEnabled&&!useiPadAppSwitcher;
   for(id scene in @[main,external,NSObject.new]){
    for(NSNumber *scope in @[@0,@7]){
     forcePadIdiom=scope.unsignedShortValue;uint16_t before=forcePadIdiom;
     for(NSNumber *mode in @[@0,@1,@2]){
      windowMode=mode.integerValue;factoryCalls=0;create(scene);
      BOOL target=nativeEntry&&scene==main;
      CHECK(factoryCalls==1&&forcePadIdiom==before,"one native factory call; surrounding iPad scope restored");
      CHECK(nativePhoneRoot==(!trollPadEnabled||target),"phone option must select the native phone root, not only Deck cards");
      CHECK(observedForce==(!trollPadEnabled?before:(target?0:before+1)),"iPad suppression confined to iOS17 main-display phone choice");
      CHECK(windowMode==mode.integerValue,"multitasking mode never changed by the entry hook");
      if(trollPadEnabled&&!useiPadAppSwitcher)CHECK(deckController&&rawStyle()==1&&effectiveStyle()==1,"phone choice reaches both raw and effective style selectors");
     }
    }
   }
   prepareCalls=hookCalls=0;installPresentation();
   CHECK(prepareCalls==(trollPadEnabled&&!useiPadAppSwitcher?1:0),"2.0.5 shared compatibility preparation remains unchanged");
   CHECK(hookCalls==(testMajor>=26?2:1),"base Continuous Expose hook retained for external roots; Main replacement stays 26-only");
  }
 }
 testMajor=17;trollPadEnabled=YES;useiPadAppSwitcher=NO;originalStyle=2;
 forcePadIdiom=4;factoryCalls=0;create(main);
 CHECK(deckController&&nativePhoneRoot&&forcePadIdiom==4,"explicit old grid preference cannot create a mixed phone/Pad stack");
 hardwareIdiom=1;create(main);CHECK(!nativePhoneRoot&&forcePadIdiom==4,"physical iPad identity is never forged into a phone");hardwareIdiom=0;
 for(NSNumber *scope in @[@0,@9]){
  forcePadIdiom=scope.unsignedShortValue;throwFactory=YES;BOOL caught=NO;
  @try{create(main);}@catch(NSException *error){caught=YES;}
  CHECK(caught&&forcePadIdiom==scope.unsignedShortValue,"native factory exception cannot leak an idiom override into later animations");
 }
 puts("PASS production native entry: phone-root/style decision; nested/exception scope restoration; no later iOS17 shims; external/default/OS/hardware guards; window-mode inputs preserved");
}return 0;}
'''


def run(source):
    generated=contract(source).replace('@available(iOS 26.0, *)','testMajor >= 26')
    with tempfile.TemporaryDirectory(prefix='trollpad-native-entry-') as directory:
        p=Path(directory);(p/'test.m').write_text(generated)
        built=subprocess.run(RTK+['clang','-fobjc-arc','-framework','Foundation',str(p/'test.m'),'-o',str(p/'test')],capture_output=True,text=True)
        if built.returncode:raise RuntimeError(built.stderr)
        return subprocess.run(RTK+[str(p/'test')],capture_output=True,text=True,timeout=10)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--baseline-ref');args=parser.parse_args()
    if args.baseline_ref:
        baseline=subprocess.check_output(RTK+['git','show',args.baseline_ref+':TweakSB.x'],cwd=ROOT,text=True)
        old=run(baseline);assert old.returncode and 'OS=17' in old.stderr,old.stdout+old.stderr
        print('PASS baseline mixed-stack selection reproduced: '+old.stderr.strip())
    source=(ROOT/'TweakSB.x').read_text()
    for obsolete in ['TPPhoneLegacyFloor','TPPhoneLegacyTransition','TPPhoneLegacyGesture','TPPhoneLegacySurfaceRetention','TPLegacyDeckQueryOwner']:
        assert obsolete not in source,obsolete
    result=run(source);assert result.returncode==0,result.stdout+result.stderr
    print(result.stdout.strip())

if __name__=='__main__':main()
