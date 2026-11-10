//
//  KBPAnimator.m
//  KBPulse
//
//  Created by EthanRDoesMC on 10/20/21.
//

#import "KBPAnimator.h"
#import "KBPPulseManager.h"

@implementation KBPAnimator

+(void)setBrightness:(float)brightness withDuration:(int)duration {
    unsigned long long kb = [KBPPulseManager keyboardID];
    [KBPPulseManager.brightnessClient setBrightness:brightness fadeSpeed:duration commit:true forKeyboard:kb];
}

+(void)brightenWithDuration:(int)duration {
    [self setBrightness:1 withDuration:duration];
}

+(void)dimWithDuration:(int)duration {
    [self setBrightness:0 withDuration:duration];
}

+(float)currentBrightness {
    unsigned long long kb = [KBPPulseManager keyboardID];
    return [KBPPulseManager.brightnessClient brightnessForKeyboard:kb];
}

+(BOOL)isBright {
    return self.currentBrightness == 1.0;
}

@end
