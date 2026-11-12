//
//  main.m
//  KBPulse
//
//  Created by EthanRDoesMC on 10/20/21.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import "KBPPulseManager.h"
#import "KBPAnimator.h"
#import "KBPProfile.h"

static NSArray<NSURL *> * themeFileURLs(void) {
    NSURL * dir = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask][0];
    dir = [dir URLByAppendingPathComponent:@"KBPulse"];
    return [NSFileManager.defaultManager contentsOfDirectoryAtURL:dir
        includingPropertiesForKeys:nil
        options:NSDirectoryEnumerationSkipsHiddenFiles
        error:nil] ?: @[];
}

static int handleCommand(NSString * cmd, NSString * arg) {
    if ([cmd isEqualToString:@"list"]) {
        for (NSURL * url in themeFileURLs()) {
            NSString * name = url.lastPathComponent;
            if ([name hasSuffix:@".json"] && ![name isEqualToString:@"hooks.json"]) {
                printf("%s\n", [name substringToIndex:name.length - 5].UTF8String);
            }
        }
        return 0;
    }
    if ([cmd isEqualToString:@"validate"]) {
        if (!arg) {
            printf("Usage: kbpulse validate <file>\n");
            return 1;
        }
        NSData * data = [NSData dataWithContentsOfFile:arg.stringByExpandingTildeInPath];
        NSError * error = nil;
        [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (error || !data) {
            printf("Invalid theme JSON: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }
        printf("Valid theme JSON.\n");
        return 0;
    }
    if ([cmd isEqualToString:@"set"] || [cmd isEqualToString:@"flash"] || [cmd isEqualToString:@"off"]) {
        if ([cmd isEqualToString:@"set"] && !arg) {
            printf("Usage: kbpulse set <profile>\n");
            return 1;
        }
        if ([NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.ethanrdoesmc.kbpulseapp"].count == 0) {
            printf("KBPulseApp is not running — launch it first\n");
            return 1;
        }
        NSMutableDictionary * userInfo = [NSMutableDictionary dictionaryWithObject:cmd forKey:@"command"];
        if (arg) userInfo[@"profile"] = arg;
        [NSDistributedNotificationCenter.defaultCenter
            postNotificationName:@"com.ethanrdoesmc.kbpulse.command"
            object:nil userInfo:userInfo deliverImmediately:YES];
        printf("Sent '%s' command to KBPulseApp\n", cmd.UTF8String);
        return 0;
    }
    printf("Usage: kbpulse [set <profile> | flash | off | list | validate <file>]\n");
    printf("Run without a command to animate the default profile directly.\n");
    return 1;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc > 1) {
            return handleCommand(@(argv[1]), argc > 2 ? @(argv[2]) : nil);
        }
        printf("KBPulse by EthanRDoesMC\n");
        [KBPPulseManager configure];
        printf("Animating keyboard. Press ctrl-c or close terminal to stop.\n");

        [KBPProfile createYawnJSON];
        KBPProfile * myProfile = [[KBPProfile alloc]  initWithFileURL:[[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask][0] URLByAppendingPathComponent:[KBPPulseManager configurationFile]]];

        double interval = [myProfile totalDuration].doubleValue;
        if (interval <= 0) interval = 1.0;
        [NSTimer scheduledTimerWithTimeInterval:interval repeats:true block:^(NSTimer * _Nonnull timer) {
            for (KBPAnimation * animation in myProfile.animations) {
                [KBPAnimator setBrightness:animation.brightness.floatValue withDuration:animation.fadeDuration.intValue];
                [NSThread sleepForTimeInterval:(animation.totalDuration.doubleValue)/1000];

            }
        }];
    dispatch_source_t signalSourceInt = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, dispatch_get_main_queue());
    dispatch_source_t signalSourceTerm = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
    // Closing a terminal sends SIGHUP, which previously left idle dimming
    // disabled because only INT/TERM were handled.
    dispatch_source_t signalSourceHup = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGHUP, 0, dispatch_get_main_queue());
    signal(SIGINT, SIG_IGN);
    signal(SIGTERM, SIG_IGN);
    signal(SIGHUP, SIG_IGN);
    dispatch_source_set_event_handler(signalSourceInt, ^{
        [KBPPulseManager restoreBacklightSettings];
        exit(0);
    });
    dispatch_source_set_event_handler(signalSourceTerm, ^{
        [KBPPulseManager restoreBacklightSettings];
        exit(0);
    });
    dispatch_source_set_event_handler(signalSourceHup, ^{
        [KBPPulseManager restoreBacklightSettings];
        exit(0);
    });
    dispatch_resume(signalSourceInt);
    dispatch_resume(signalSourceTerm);
    dispatch_resume(signalSourceHup);
    }
    [[NSRunLoop currentRunLoop] run];
    return 0;
}
