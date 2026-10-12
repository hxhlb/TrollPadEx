#import <Foundation/Foundation.h>
#include <notify.h>
#include <unistd.h>

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 2 || getuid() != 501) {
            fputs("Run as mobile: PhoneHostScalingControl enable|disable|capture\n", stderr);
            return 2;
        }
        if (strcmp(argv[1], "capture") == 0) {
            return notify_post("com.banana.trollpadex/scaling-capture") == NOTIFY_STATUS_OK ? 0 : 1;
        }
        BOOL enable = strcmp(argv[1], "enable") == 0;
        if (!enable && strcmp(argv[1], "disable") != 0) return 2;
        CFPreferencesSetAppValue(CFSTR("TPTrollPadExPhoneHostScaling"),
            enable ? kCFBooleanTrue : NULL, CFSTR("com.apple.springboard"));
        Boolean saved = CFPreferencesAppSynchronize(CFSTR("com.apple.springboard"));
        if (saved) notify_post("com.kdt.trollpad/saved");
        return saved ? 0 : 1;
    }
}
