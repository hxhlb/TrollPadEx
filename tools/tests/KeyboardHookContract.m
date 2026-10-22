// Standalone production-hook regression; shims affect only this test process.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#include <stdlib.h>
static NSInteger testNativeIdiom=1;
static UIUserInterfaceIdiom (*safeReplacement)(void);
static NSInteger nativePadTraits(id self,SEL cmd){return testNativeIdiom;}
static UIUserInterfaceIdiom nativePadSafe(void){return (UIUserInterfaceIdiom)testNativeIdiom;}
static Boolean testPreferences(CFStringRef key,CFStringRef domain,Boolean *exists){
 if(getenv("TP_TEST_CF_MISSING")){if(exists)*exists=false;return false;}
 if(exists)*exists=true;
 if(CFEqual(key,CFSTR("TPTrollPadEnabled")))return true;
 if(CFEqual(key,CFSTR("TPEnableiPadKeyboard")))return getenv("TP_TEST_PAD_KEYBOARD")!=NULL;
 return false;
}
static IMP originalDictionaryReader;
static id testDictionaryReader(id cls,SEL cmd,NSString *path){
 if([path hasSuffix:@"/com.kdt.trollpad.plist"]){
  if(!getenv("TP_TEST_CF_MISSING"))return nil;
  return @{@"TPTrollPadEnabled":@(getenv("TP_TEST_MASTER_OFF")==NULL),@"TPEnableiPadKeyboard":@(getenv("TP_TEST_PAD_KEYBOARD")!=NULL),@"TPShowShortcutButtonsOnKeyboard":@NO};
 }
 return ((id(*)(id,SEL,id))originalDictionaryReader)(cls,cmd,path);
}
void MSHookMessageEx(Class cls,SEL sel,IMP replacement,IMP *original){
 Method m=class_getInstanceMethod(cls,sel);if(!m)return;
 *original=method_getImplementation(m);class_replaceMethod(cls,sel,replacement,method_getTypeEncoding(m));
}
void MSHookFunction(void *symbol,void *replacement,void **original){
 safeReplacement=(UIUserInterfaceIdiom(*)(void))replacement;*original=(void *)nativePadSafe;
}
__attribute__((constructor(101))) static void installNativePadContext(void){
 Class cls=objc_getClass("UIKBScreenTraits");Method m=class_getInstanceMethod(cls,@selector(idiom));
 if(!m)abort();class_replaceMethod(cls,@selector(idiom),(IMP)nativePadTraits,method_getTypeEncoding(m));
 Method reader=class_getClassMethod(NSDictionary.class,@selector(dictionaryWithContentsOfFile:));
 originalDictionaryReader=method_getImplementation(reader);
 class_replaceMethod(object_getClass(NSDictionary.class),@selector(dictionaryWithContentsOfFile:),(IMP)testDictionaryReader,method_getTypeEncoding(reader));
}
#define CFPreferencesAppSynchronize(domain) true
#define CFPreferencesGetAppBooleanValue testPreferences
#ifdef TP_TEST_BASELINE
static BOOL phoneHardware=YES;
#endif
#include "KeyboardTweakUnderTest.inc"
#undef CFPreferencesGetAppBooleanValue
int main(){@autoreleasepool{
 NSCAssert(phoneHardware && safeReplacement,@"Production cold-start hooks installed on phone");
 BOOL coldPad=getenv("TP_TEST_PAD_KEYBOARD")!=NULL;
 BOOL sandboxCFMissing=getenv("TP_TEST_CF_MISSING")!=NULL;
 NSCAssert(keyboardHooksInitialized==coldPad,@"iPad-only hooks stay lazy");
 id traits=((id(*)(id,SEL,id,NSInteger,BOOL,BOOL))objc_msgSend)([objc_getClass("UIKBScreenTraits") alloc],@selector(initWithScreen:orientation:allowFloating:ignoreRemoteKeyboard:),UIScreen.mainScreen,1,NO,YES);
 NSCAssert(traits,@"Real native traits initialized without presenting a window");
 NSInteger(*idiom)(id,SEL)=(NSInteger(*)(id,SEL))objc_msgSend;
 NSCAssert(idiom(traits,@selector(idiom))==(coldPad?1:0),@"Disabled-at-startup restores native render idiom");
 NSCAssert(safeReplacement()==(coldPad?1:0),@"Disabled-at-startup restores safe idiom");
 trollPadEnabled=YES;enableiPadKeyboard=NO;
 NSCAssert(idiom(traits,@selector(idiom))==0 && safeReplacement()==0,@"Both paths restore phone");
 enableiPadKeyboard=YES;
 NSCAssert(idiom(traits,@selector(idiom))==1 && safeReplacement()==1,@"iPad mode preserved");
 trollPadEnabled=NO;
 NSCAssert(idiom(traits,@selector(idiom))==1 && safeReplacement()==1,@"Master off preserves native");
 trollPadEnabled=YES;enableiPadKeyboard=NO;phoneHardware=NO;
 NSCAssert(idiom(traits,@selector(idiom))==1 && safeReplacement()==1,@"Real iPad preserved");
 phoneHardware=YES;testNativeIdiom=3;
 NSCAssert(idiom(traits,@selector(idiom))==3 && safeReplacement()==3,@"Other idioms preserved");
#ifndef TP_TEST_BASELINE
 NSCAssert(!keyboardBoolPreference(@{@"TPEnableiPadKeyboard":@NO},@"TPEnableiPadKeyboard",YES),@"Saved false overrides cached CFPreferences and default true");
 setenv("TP_TEST_CF_MISSING","1",1);
 NSCAssert(keyboardBoolPreference(nil,@"missing",YES),@"Missing preferences retain default true");
 NSCAssert(!keyboardBoolPreference(nil,@"missing",NO),@"Missing preferences retain default false");
 setenv("TP_TEST_MASTER_OFF","1",1);
 loadPrefs();
 NSCAssert(!trollPadEnabled && !enableiPadKeyboard && !showShortcutButtonsOnKeyboard,@"Shared master-off snapshot disables keyboard changes");
 unsetenv("TP_TEST_MASTER_OFF");
#endif
 printf("PASS production Logos hooks: cold-%s, sandbox-preferences-%s, native Pad render traits restored, toggles/master/real-iPad/other-idiom contracts\n",coldPad?"on":"off",sandboxCFMissing?"missing":"available");
}return 0;}
