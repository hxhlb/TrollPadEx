#import "TPDockLibrary.h"
#import <objc/runtime.h>
#import <substrate.h>
#include <string.h>

static BOOL (*TPHideDockLibrary)(void);
static BOOL TPLibraryRestricted(void) { return TPHideDockLibrary && TPHideDockLibrary(); }
#define TP_LIBRARY_GETTER(name) \
    static BOOL (*name##Original)(id,SEL); \
    static BOOL name(id object,SEL selector) { BOOL native=name##Original(object,selector);return native && !TPLibraryRestricted(); }
#define TP_LIBRARY_SETTER(name) \
    static void (*name##Original)(id,SEL,BOOL); \
    static void name(id object,SEL selector,BOOL value) { name##Original(object,selector,value && !TPLibraryRestricted()); }
TP_LIBRARY_GETTER(TPControllerLibraryEnabled)
TP_LIBRARY_GETTER(TPRootLibraryEnabled)
TP_LIBRARY_GETTER(TPViewLibraryEnabled)
TP_LIBRARY_SETTER(TPRootSetLibraryEnabled)
TP_LIBRARY_SETTER(TPRootSetLibraryVisible)
TP_LIBRARY_SETTER(TPViewSetLibraryEnabled)
TP_LIBRARY_SETTER(TPViewSetLibraryVisible)

static BOOL TPBooleanType(const char *type) { return !strcmp(type,"B") || !strcmp(type,"c"); }
static void TPLibraryHook(Class cls,const char *name,BOOL setter,IMP replacement,IMP *original) {
    SEL selector=sel_registerName(name);Method method=class_getInstanceMethod(cls,selector);char type[32]={0};
    if (!method || method_getNumberOfArguments(method)!=(setter?3:2)) { return; }
    method_getReturnType(method,type,sizeof(type));
    if (setter) {
        if (strcmp(type,"v")) { return; }
        method_getArgumentType(method,2,type,sizeof(type));if (!TPBooleanType(type)) { return; }
    } else if (!TPBooleanType(type)) { return; }
    class_addMethod(cls,selector,method_getImplementation(method),method_getTypeEncoding(method));
    MSHookMessageEx(cls,selector,replacement,original);
}
void TPInstallDockLibraryHooks(BOOL (*shouldHide)(void)) {
    TPHideDockLibrary=shouldHide;
    Class controller=NSClassFromString(@"SBFloatingDockController");
    Class root=NSClassFromString(@"SBFloatingDockRootViewController");
    Class view=NSClassFromString(@"SBFloatingDockViewController");
    TPLibraryHook(controller,"isLibraryPodIconEnabled",NO,(IMP)TPControllerLibraryEnabled,(IMP *)&TPControllerLibraryEnabledOriginal);
    TPLibraryHook(root,"isLibraryPodIconEnabled",NO,(IMP)TPRootLibraryEnabled,(IMP *)&TPRootLibraryEnabledOriginal);
    TPLibraryHook(root,"setLibraryPodIconEnabled:",YES,(IMP)TPRootSetLibraryEnabled,(IMP *)&TPRootSetLibraryEnabledOriginal);
    TPLibraryHook(root,"setLibraryPodIconVisible:",YES,(IMP)TPRootSetLibraryVisible,(IMP *)&TPRootSetLibraryVisibleOriginal);
    if (view!=root) {
        TPLibraryHook(view,"isLibraryPodIconEnabled",NO,(IMP)TPViewLibraryEnabled,(IMP *)&TPViewLibraryEnabledOriginal);
        TPLibraryHook(view,"setLibraryPodIconEnabled:",YES,(IMP)TPViewSetLibraryEnabled,(IMP *)&TPViewSetLibraryEnabledOriginal);
        TPLibraryHook(view,"setLibraryPodIconVisible:",YES,(IMP)TPViewSetLibraryVisible,(IMP *)&TPViewSetLibraryVisibleOriginal);
    }
}
