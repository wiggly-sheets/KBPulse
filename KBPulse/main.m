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

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        printf("KBPulse by EthanRDoesMC\n");
        [KBPPulseManager configure];
        printf("Animating keyboard. Press ctrl-c or close terminal to stop.\n");

        [KBPProfile createYawnJSON];
        KBPProfile * myProfile = [[KBPProfile alloc]  initWithFileURL:[[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask][0] URLByAppendingPathComponent:[KBPPulseManager configurationFile]]];

        [NSTimer scheduledTimerWithTimeInterval:[myProfile totalDuration].doubleValue repeats:true block:^(NSTimer * _Nonnull timer) {
            for (KBPAnimation * animation in myProfile.animations) {
                [KBPAnimator setBrightness:animation.brightness.floatValue withDuration:animation.fadeDuration.intValue];
                [NSThread sleepForTimeInterval:(animation.totalDuration.doubleValue)/1000];

            }
        }];
    dispatch_source_t signalSourceInt = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, dispatch_get_main_queue());
    dispatch_source_t signalSourceTerm = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
    signal(SIGINT, SIG_IGN);
    signal(SIGTERM, SIG_IGN);
    dispatch_source_set_event_handler(signalSourceInt, ^{
        [KBPPulseManager restoreBacklightSettings];
        exit(0);
    });
    dispatch_source_set_event_handler(signalSourceTerm, ^{
        [KBPPulseManager restoreBacklightSettings];
        exit(0);
    });
    dispatch_resume(signalSourceInt);
    dispatch_resume(signalSourceTerm);
    }
    [[NSRunLoop currentRunLoop] run];
    return 0;
}
