"""Host contracts for production library hooks/observer. No phone or service access."""
from pathlib import Path
import subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parents[2]
class DockLibrary(unittest.TestCase):
    def run_code(self,code):
        with tempfile.TemporaryDirectory() as directory:
            p=Path(directory);(p/'test.m').write_text(code)
            result=subprocess.run(['/opt/homebrew/bin/rtk','proxy','clang','-fobjc-arc','-framework','Foundation','-I'+str(ROOT),str(p/'test.m'),'-o',str(p/'test')],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            result=subprocess.run(['/opt/homebrew/bin/rtk','proxy',str(p/'test')],capture_output=True,text=True,timeout=10)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
    def test_native_setter_and_getter_restrictions_preserve_passthrough_and_wrong_abi(self):
        code=r'''#import <Foundation/Foundation.h>
#import <objc/runtime.h>
static BOOL master,library,native;
static unsigned hooks;
static BOOL hidden(void){return master && !library;}
static void MSHookMessageEx(Class c,SEL s,IMP replacement,IMP *original){Method m=class_getInstanceMethod(c,s);*original=method_getImplementation(m);method_setImplementation(m,replacement);hooks++;}
@interface Base:NSObject
@property BOOL enabled,visible;
@property unsigned enabledWrites,visibleWrites;
- (BOOL)isLibraryPodIconEnabled;
- (void)setLibraryPodIconEnabled:(BOOL)v;
- (void)setLibraryPodIconVisible:(BOOL)v;
@end
@implementation Base
- (BOOL)isLibraryPodIconEnabled{return self.enabled;}
- (void)setLibraryPodIconEnabled:(BOOL)v{self.enabled=v;self.enabledWrites++;}
- (void)setLibraryPodIconVisible:(BOOL)v{self.visible=v;self.visibleWrites++;}
@end
@interface SBFloatingDockRootViewController:Base @end
@implementation SBFloatingDockRootViewController @end
@interface SBFloatingDockViewController:Base @end
@implementation SBFloatingDockViewController @end
@interface SBFloatingDockController:NSObject
- (BOOL)isLibraryPodIconEnabled;
@end
@implementation SBFloatingDockController
- (BOOL)isLibraryPodIconEnabled{return native;}
@end
@interface Wrong:NSObject
- (id)isLibraryPodIconEnabled;
- (void)setLibraryPodIconEnabled:(id)v;
@end
@implementation Wrong
- (id)isLibraryPodIconEnabled{return @"unchanged";}
- (void)setLibraryPodIconEnabled:(id)v{(void)v;}
@end
'''
        code+='\n'.join(line for line in (ROOT/'TPDockLibrary.m').read_text().splitlines() if line!='#import <substrate.h>')
        code+=r'''
int main(void){@autoreleasepool{
 SBFloatingDockRootViewController *root=[SBFloatingDockRootViewController new];SBFloatingDockViewController *view=[SBFloatingDockViewController new];SBFloatingDockController *controller=[SBFloatingDockController new];
 // A native YES alone ignores a saved OFF; the restriction must cover setters too.
 master=YES;library=NO;native=YES;[root setLibraryPodIconEnabled:YES];if(!root.isLibraryPodIconEnabled)return 1;
 TPInstallDockLibraryHooks(hidden);if(hooks!=7)return 2;
 unsigned expected=root.enabledWrites;
 for(unsigned mask=0;mask<8;mask++){
  master=mask&1;library=!!(mask&2);native=!!(mask&4);BOOL allowed=native && !(master && !library);
  [root setLibraryPodIconEnabled:native];[root setLibraryPodIconVisible:native];[view setLibraryPodIconEnabled:native];[view setLibraryPodIconVisible:native];expected++;
  if(root.isLibraryPodIconEnabled!=allowed || root.visible!=allowed || view.isLibraryPodIconEnabled!=allowed || view.visible!=allowed || controller.isLibraryPodIconEnabled!=allowed)return 3;
  if(root.enabledWrites!=expected)return 4;
 }
 IMP untouched=NULL;TPLibraryHook(Wrong.class,"isLibraryPodIconEnabled",NO,(IMP)TPControllerLibraryEnabled,&untouched);
 TPLibraryHook(Wrong.class,"setLibraryPodIconEnabled:",YES,(IMP)TPRootSetLibraryEnabled,&untouched);
 TPLibraryHook(Nil,"missing",NO,(IMP)TPControllerLibraryEnabled,&untouched);
 if(hooks!=7 || untouched || ![[[Wrong new] isLibraryPodIconEnabled] isEqual:@"unchanged"])return 5;
 puts("PASS local/remote-root library native setters+queries: OFF restricts YES; ON/master-OFF preserve native; native NO never forced; one original setter; inherited methods; bad/missing ABI skipped");
}return 0;}
'''
        self.run_code(code)
    def test_real_observer_missing_off_on_and_notification_metadata(self):
        code=r'''#import <Foundation/Foundation.h>
static NSMutableDictionary *store;
static NSMutableSet *observed;
@interface Defaults:NSObject
+ (instancetype)standardUserDefaults;
- (void)synchronize;
- (BOOL)boolForKey:(NSString *)key;
- (id)objectForKey:(NSString *)key;
- (NSInteger)integerForKey:(NSString *)key;
- (void)addObserver:(id)o forKeyPath:(NSString *)k options:(NSUInteger)options context:(void *)context;
@end
@implementation Defaults
+ (instancetype)standardUserDefaults{return [self new];}
- (void)synchronize{}
- (BOOL)boolForKey:(NSString *)key{return [store[key] boolValue];}
- (id)objectForKey:(NSString *)key{return store[key];}
- (NSInteger)integerForKey:(NSString *)key{return [store[key] integerValue];}
- (void)addObserver:(id)o forKeyPath:(NSString *)k options:(NSUInteger)options context:(void *)context{[observed addObject:k];}
@end
#define NSUserDefaults Defaults
#define CFPreferencesAppSynchronize(domain) ((void)(domain),true)
#define CFNotificationCenterAddObserver(...) ((void)0)
#define CFNotificationCenterRemoveObserver(...) ((void)0)
'''+(ROOT/'TPPrefsObserver.m').read_text()+r'''
int main(void){@autoreleasepool{
 store=[NSMutableDictionary new];observed=[NSMutableSet new];TPPrefsObserver *p=[TPPrefsObserver new];
 if(!p.appLibraryInDockEnabled || ![observed containsObject:@"SBAppLibraryInDockEnabled"])return 1;
 store[@"SBAppLibraryInDockEnabled"]=@NO;[p observeValueForKeyPath:nil ofObject:nil change:nil context:nil];if(p.appLibraryInDockEnabled)return 2;
 store[@"SBAppLibraryInDockEnabled"]=@YES;[p observeValueForKeyPath:nil ofObject:nil change:nil context:nil];if(!p.appLibraryInDockEnabled)return 3;
 [store removeObjectForKey:@"SBAppLibraryInDockEnabled"];[p observeValueForKeyPath:nil ofObject:nil change:nil context:nil];if(!p.appLibraryInDockEnabled)return 4;
 puts("PASS production observer missing YES/explicit NO/YES/remove; native key observed; no real defaults or Darwin observers touched");
}return 0;}
'''
        self.run_code(code)
        import plistlib
        rows=plistlib.loads((ROOT/'TrollPadPrefs/Resources/Root.plist').read_bytes())['items']
        row=next(r for r in rows if r.get('key')=='SBAppLibraryInDockEnabled')
        self.assertEqual(row['PostNotification'],'com.kdt.trollpad/saved');self.assertEqual(row['defaults'],'com.apple.springboard')
