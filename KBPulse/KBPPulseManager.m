//
//  KBPPulseManager.m
//  KBPulse
//
//  Created by EthanRDoesMC on 10/20/21.
//

#import "KBPPulseManager.h"
#import "KBPAnimator.h"

@interface KBPPulseManager ()
@property (nonatomic) double savedIdleDimTime;
@property (nonatomic) BOOL savedAutoBrightness;
@property (nonatomic) float savedBrightness;
@end

@implementation KBPPulseManager

+ (id)sharedInstance {
    static KBPPulseManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

+(void)loadPrivateFrameworks {
    printf("Loading private frameworks\n");
    printf("CoreBrightness: %hhd\n",[[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/CoreBrightness.framework"] load]);
    [KBPPulseManager.sharedInstance setBrightnessClient:[[NSClassFromString(@"KeyboardBrightnessClient") alloc] init]];
    printf("OSD: %hhd\n",[[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/OSD.framework"] load]);
}

+(void)modifyBacklightSettings {
    if (KBPPulseManager.brightnessClient == nil) return;
    unsigned long long kb = [self keyboardID];
    printf("Disabling idle-dimming and auto-brightness\n");
    // Save the current values so restore can put them back exactly.
    KBPPulseManager *manager = KBPPulseManager.sharedInstance;
    manager.savedBrightness = [KBPPulseManager.brightnessClient brightnessForKeyboard:kb];
    manager.savedIdleDimTime = [KBPPulseManager.brightnessClient idleDimTimeForKeyboard:kb];
    manager.savedAutoBrightness = [KBPPulseManager.brightnessClient isAutoBrightnessEnabledForKeyboard:kb];
    [KBPPulseManager.brightnessClient setIdleDimTime:0 forKeyboard:kb];
    [KBPPulseManager.brightnessClient enableAutoBrightness:false forKeyboard:kb];
}

+(unsigned long long)keyboardID {
    // Prefer the built-in keyboard (ID 1) when present; otherwise fall back
    // to the first reported backlight ID (e.g. external Magic Keyboard); else 1.
    id ids = [KBPPulseManager.brightnessClient copyKeyboardBacklightIDs];
    if ([ids isKindOfClass:[NSArray class]] && ((NSArray *)ids).count > 0) {
        for (id entry in (NSArray *)ids) {
            if ([entry isKindOfClass:[NSNumber class]] && [entry unsignedLongLongValue] == 1) {
                return 1;
            }
        }
        id first = ((NSArray *)ids)[0];
        if ([first isKindOfClass:[NSNumber class]]) {
            return [first unsignedLongLongValue];
        }
    }
    return 1;
}

+(void)showBezel {
    [[NSClassFromString(@"OSDManager") sharedManager] showImage:11 onDisplayID:1 priority:1 msecUntilFade:1000 withText:@"KBPulse"];
}

+(void)restoreBacklightSettings {
    if (KBPPulseManager.brightnessClient == nil) return;
    unsigned long long kb = [self keyboardID];
    // Put the keyboard back the way the user left it: restore the ambient
    // (auto-brightness) toggle, the idle-dim timeout, and the brightness level.
    KBPPulseManager *manager = KBPPulseManager.sharedInstance;
    [KBPPulseManager.brightnessClient enableAutoBrightness:manager.savedAutoBrightness forKeyboard:kb];
    [KBPPulseManager.brightnessClient setBrightness:manager.savedBrightness fadeSpeed:350 commit:true forKeyboard:kb];
    [KBPPulseManager.brightnessClient setIdleDimTime:manager.savedIdleDimTime forKeyboard:kb];
}

+(void)configure {
    [self loadPrivateFrameworks];
    [self modifyBacklightSettings];
    [self showBezel];
}

+(KeyboardBrightnessClient *)brightnessClient {
    return [KBPPulseManager.sharedInstance brightnessClient];
}

+(NSString *)configurationFile {
    NSString * configuration = @"/KBPulse/Yawn.json";
    NSArray *arguments = NSProcessInfo.processInfo.arguments;
    if ([arguments count] > 1) {
        configuration = [NSString stringWithFormat:@"/KBPulse/%@.json", arguments[1] ];
    }
    return configuration;
}

- (id)init {
    if (self = [super init]) {
        self.paused = false;
    }
    return self;
}

@end