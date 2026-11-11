#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

int main() {
    @autoreleasepool {
        NSRunningApplication *app = nil;
        for (NSRunningApplication *ra in [[NSWorkspace sharedWorkspace] runningApplications]) {
            if ([ra.bundleIdentifier isEqualToString:@"com.ethanrdoesmc.kbpulseapp"]) {
                app = ra;
                break;
            }
        }
        if (app) {
            NSLog(@"App found: %@", app.localizedName);
            NSLog(@"Activation policy: %ld", (long)app.activationPolicy);
            NSLog(@"PID: %ld", (long)app.processIdentifier);
        } else {
            NSLog(@"App not found");
        }
    }
    return 0;
}
