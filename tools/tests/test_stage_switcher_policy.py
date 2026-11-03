#!/usr/bin/env python3.11
"""Production preference transactions against an isolated CFPreferences store."""
from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
RTK=['/opt/homebrew/bin/rtk','proxy']
FIXTURE=r'''
#import <Foundation/Foundation.h>
#include <stdio.h>
static NSInteger major;
static NSMutableDictionary *store;
static unsigned notices,writes,callbackDepth,syncs;
static void (*writeObserver)(NSString *);
@interface FakeProcessInfo:NSObject
+ (instancetype)processInfo;
- (NSOperatingSystemVersion)operatingSystemVersion;
@end
@implementation FakeProcessInfo
+ (instancetype)processInfo{return [self new];}
- (NSOperatingSystemVersion)operatingSystemVersion{return (NSOperatingSystemVersion){major,0,0};}
@end
static NSMutableDictionary *domain(CFStringRef app){
 NSString *name=(__bridge NSString *)app;NSMutableDictionary *d=store[name];
 if(!d){d=NSMutableDictionary.new;store[name]=d;}return d;
}
static CFPropertyListRef fakeCopy(CFStringRef key,CFStringRef app){return CFBridgingRetain(domain(app)[(__bridge NSString *)key]);}
static void fakeSet(CFStringRef key,CFPropertyListRef value,CFStringRef app){
 writes++;if(value)domain(app)[(__bridge NSString *)key]=(__bridge id)value;else[domain(app) removeObjectForKey:(__bridge NSString *)key];
 if(writeObserver&&CFEqual(app,CFSTR("com.apple.springboard"))){if(++callbackDepth>12)abort();writeObserver((__bridge NSString *)key);callbackDepth--;}
}
static Boolean fakeBool(CFStringRef key,CFStringRef app,Boolean *exists){id v=domain(app)[(__bridge NSString *)key];if(exists)*exists=v!=nil;return[v boolValue];}
static Boolean fakeSync(CFStringRef app){syncs++;return true;}
static void fakeNotify(CFNotificationCenterRef c,CFStringRef n,const void *o,CFDictionaryRef d,Boolean immediate){notices++;}
#define NSProcessInfo FakeProcessInfo
#define CFPreferencesCopyAppValue fakeCopy
#define CFPreferencesSetAppValue fakeSet
#define CFPreferencesGetAppBooleanValue fakeBool
#define CFPreferencesAppSynchronize fakeSync
#define CFNotificationCenterPostNotification fakeNotify
'''
MAIN=r'''
#define CHECK(e,message) do{if(!(e)){fprintf(stderr,"FAIL %s OS=%ld\n",message,(long)major);return 1;}}while(0)
static void reset(BOOL stage,BOOL pad,BOOL enabled){
 store=NSMutableDictionary.new;notices=writes=syncs=0;writeObserver=NULL;TPPolicyWriteDepth=0;TPPolicyBootChoiceKnown=NO;
 domain(CFSTR("com.kdt.trollpad"))[@"TPTrollPadEnabled"]=@(enabled);
 domain(TPPolicyDomain)[TPPolicyStageKey]=@(stage);domain(TPPolicyDomain)[TPPolicyPadKey]=@(pad);
 domain(TPPolicyDomain)[@"unrelated"]=@"preserved";
}
static void set(NSString *key,BOOL value){BOOL linked=TPBeginStageSwitcherWrite(key,@(value));fakeSet((__bridge CFStringRef)key,value?kCFBooleanTrue:kCFBooleanFalse,TPPolicyDomain);if(linked)TPEndStageSwitcherWrite();}
static void reenter(NSString *key){TPReconcileStageSwitcherPolicy(key);}
int main(void){@autoreleasepool{
 for(NSNumber *version in @[@15,@16,@17,@18,@19,@26,@27]){
  major=version.integerValue;BOOL coupled=major>=16&&major<=18;
  reset(NO,NO,YES);set(TPPolicyStageKey,YES);
  CHECK(TPStoredStageManagerEnabled()&&TPStorediPadSwitcherEnabled()==coupled,"Stage ON forces Pad only on 16/17/18");
  CHECK(TPStageSwitcherNeedsRespring()==coupled,"linked Pad enable records restart requirement");
  reset(YES,YES,YES);writeObserver=reenter;set(TPPolicyPadKey,NO);writeObserver=NULL;
  CHECK(!TPStorediPadSwitcherEnabled()&&TPStoredStageManagerEnabled()==!coupled,"Pad OFF exits Stage without observer re-entry undoing it");
  CHECK(TPPolicyRead(@"SBMedusaMultitaskingEnabled",NO)==coupled,"Pad OFF selects Split View only in policy scope");
  CHECK([domain(TPPolicyDomain)[@"unrelated"] isEqual:@"preserved"],"unrelated preference untouched");
  CHECK(TPPolicyWriteDepth==0,"transaction depth restored");
  reset(NO,NO,YES);set(TPPolicyStageKey,NO);CHECK(!TPStorediPadSwitcherEnabled(),"Split/fullscreen keeps independent phone choice");
  reset(NO,NO,YES);set(TPPolicyPadKey,YES);CHECK(!TPStoredStageManagerEnabled(),"Pad ON does not force Stage");
  reset(YES,NO,YES);TPReconcileStageSwitcherPolicy(nil);
  CHECK(TPStorediPadSwitcherEnabled()==coupled,"startup resolves old Stage+phone conflict only in scope");
  reset(YES,NO,NO);set(TPPolicyStageKey,YES);TPReconcileStageSwitcherPolicy(nil);
  CHECK(!TPStorediPadSwitcherEnabled(),"disabled tweak leaves system choices alone");
 }
 major=17;reset(NO,NO,YES);TPStageSwitcherAppliedAtBoot(NO);set(TPPolicyStageKey,YES);
 CHECK(TPStageSwitcherNeedsRespring(),"enabling Stage from phone stack stays pending until restart");
 TPStageSwitcherAppliedAtBoot(YES);CHECK(!TPStageSwitcherNeedsRespring(),"boot application clears restart state");
 set(TPPolicyPadKey,NO);CHECK(TPStageSwitcherNeedsRespring()&&!TPStoredStageManagerEnabled(),"reverse transition persists Split before restart");
 set(TPPolicyPadKey,YES);TPReconcileStageSwitcherPolicy(TPPolicyPadKey);CHECK(!TPStageSwitcherNeedsRespring(),"return to already applied stack clears pending state");
 reset(YES,NO,YES);TPReconcileStageSwitcherPolicy(TPPolicyPadKey);CHECK(!TPStoredStageManagerEnabled()&&!TPStorediPadSwitcherEnabled(),"external explicit Pad OFF wins over stale Stage value");
 reset(NO,NO,YES);BOOL linked=TPBeginStageSwitcherWrite(TPPolicyStageKey,@YES);
 CHECK(linked&&!TPBeginStageSwitcherWrite(TPPolicyPadKey,@NO),"nested writers are suppressed");TPEndStageSwitcherWrite();
 CHECK(TPPolicyWriteDepth==0,"nested writer does not leave guard armed");
 reset(NO,YES,YES);CHECK(!TPBeginStageSwitcherWrite(@"unrelated",@NO)&&writes==0&&syncs==0,"other keys never coupled");
 reset(NO,NO,YES);cfAppWrite(CFSTR("SBChamoisWindowingEnabled"),kCFBooleanTrue,CFSTR("another.domain"));
 CHECK(!TPStorediPadSwitcherEnabled(),"CF writes in other domains do not couple SpringBoard");
 cfAppWrite(CFSTR("SBChamoisWindowingEnabled"),kCFBooleanTrue,TPPolicyDomain);
 CHECK(TPStorediPadSwitcherEnabled()&&TPStoredStageManagerEnabled(),"native CF writer entry performs linkage");
 cfValueWrite(CFSTR("TPUseiPadAppSwitcher"),kCFBooleanFalse,TPPolicyDomain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
 CHECK(!TPStorediPadSwitcherEnabled()&&!TPStoredStageManagerEnabled(),"Preferences CF value writer selects Split");
 puts("PASS production CF policy: 16/17/18 bidirectional coupling, Split selection, 15/19/26/27 isolation, master/default/boot/re-entry guards and preserved unrelated values");
}return 0;}
'''

def body(source,marker):
 a=source.index(marker);a=source.index('{',a);depth=1;b=a+1
 while depth:depth+=(source[b]=='{')-(source[b]=='}');b+=1
 return source[a+1:b-1]

def main():
 source=(ROOT/'TrollPadPrefs/NSUserDefaults+hook.x').read_text()
 core=source[:source.index('%group TPStageSwitcherWriteHooks')]
 core=core.replace('#import "../TPStageSwitcherPolicy.h"','#import "TPStageSwitcherPolicy.h"')
 with tempfile.TemporaryDirectory(prefix='trollpad-stage-policy-') as directory:
  app=body(source,'%hookf(void, CFPreferencesSetAppValue').replace('%orig','fakeSet(key,value,applicationID)')
  value=body(source,'%hookf(void, CFPreferencesSetValue').replace('%orig','fakeSet(key,value,applicationID)')
  writers='static void cfAppWrite(CFStringRef key,CFPropertyListRef value,CFStringRef applicationID){'+app+'}\n'
  writers+='static void cfValueWrite(CFStringRef key,CFPropertyListRef value,CFStringRef applicationID,CFStringRef user,CFStringRef host){'+value+'}\n'
  p=Path(directory);(p/'test.m').write_text(FIXTURE+core+writers+MAIN)
  r=subprocess.run(RTK+['clang','-fobjc-arc','-framework','Foundation','-I',str(ROOT),str(p/'test.m'),'-o',str(p/'test')],capture_output=True,text=True)
  if r.returncode:raise RuntimeError(r.stderr)
  r=subprocess.run(RTK+[str(p/'test')],capture_output=True,text=True,timeout=10)
  assert r.returncode==0,r.stdout+r.stderr;print(r.stdout.strip())
if __name__=='__main__':main()
