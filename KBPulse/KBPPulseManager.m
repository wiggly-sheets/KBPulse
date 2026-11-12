//
//  KBPPulseManager.m
//  KBPulse
//
//  Created by EthanRDoesMC on 10/20/21.
//

#import "KBPPulseManager.h"
#import "KBPAnimator.h"

static NSString * const KBPHasSavedSettingsKey = @"KBPulseHasSavedBacklightSettings";
static NSString * const KBPSavedIdleDimTimeKey = @"KBPulseSavedIdleDimTime";
static NSString * const KBPSavedAutoBrightnessKey = @"KBPulseSavedAutoBrightness";
static NSString * const KBPSavedBrightnessKey = @"KBPulseSavedBrightness";

@interface KBPPulseManager ()
@property (nonatomic) double savedIdleDimTime;
@property (nonatomic) BOOL savedAutoBrightness;
@property (nonatomic) float savedBrightness;
/// True only while KBPulse is actively holding the user's original settings.
@property (nonatomic) BOOL hasSavedSettings;
-(void)persistSavedSettings;
-(BOOL)loadPersistedSavedSettings;
-(void)clearPersistedSavedSettings;
+(NSUserDefaults *)savedSettingsDefaults;
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
    KBPPulseManager *manager = KBPPulseManager.sharedInstance;
    // Never overwrite the originals once we have taken control. This can be
    // called again after a transient stop, and the values on disk at that
    // point are KBPulse's, not the user's.
    if (manager.hasSavedSettings) return;

    unsigned long long kb = [self keyboardID];
    printf("Disabling idle-dimming and auto-brightness\n");
    // Save the current values so restore can put them back exactly.
    manager.savedBrightness = [KBPPulseManager.brightnessClient brightnessForKeyboard:kb];
    manager.savedIdleDimTime = [KBPPulseManager.brightnessClient idleDimTimeForKeyboard:kb];
    manager.savedAutoBrightness = [KBPPulseManager.brightnessClient isAutoBrightnessEnabledForKeyboard:kb];
    manager.hasSavedSettings = YES;
    [manager persistSavedSettings];

    [KBPPulseManager.brightnessClient setIdleDimTime:0 forKeyboard:kb];
    [KBPPulseManager.brightnessClient enableAutoBrightness:false forKeyboard:kb];
}

+(unsigned long long)keyboardID {
    // Cache the result: reactive mode calls this up to 60 times per second,
    // and -copyKeyboardBacklightIDs allocates on every call.
    static unsigned long long cachedID = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Prefer the built-in keyboard (ID 1) when present; otherwise fall
        // back to the first reported backlight ID (e.g. an external Magic
        // Keyboard); else 1.
        id ids = [KBPPulseManager.brightnessClient copyKeyboardBacklightIDs];
        cachedID = 1;
        if ([ids isKindOfClass:[NSArray class]] && ((NSArray *)ids).count > 0) {
            for (id entry in (NSArray *)ids) {
                if ([entry isKindOfClass:[NSNumber class]] && [entry unsignedLongLongValue] == 1) {
                    cachedID = 1;
                    return;
                }
            }
            id first = ((NSArray *)ids)[0];
            if ([first isKindOfClass:[NSNumber class]]) {
                cachedID = [first unsignedLongLongValue];
            }
        }
    });
    return cachedID;
}

+(void)showBezel {
    [[NSClassFromString(@"OSDManager") sharedManager] showImage:11 onDisplayID:1 priority:1 msecUntilFade:1000 withText:@"KBPulse"];
}

+(void)restoreBacklightSettings {
    if (KBPPulseManager.brightnessClient == nil) return;
    KBPPulseManager *manager = KBPPulseManager.sharedInstance;
    // Nothing was changed: leave the keyboard exactly as it is. This matters
    // when the engine starts disabled, or when KBPulse was launched only to
    // show its menu.
    if (!manager.hasSavedSettings) return;

    unsigned long long kb = [self keyboardID];
    // Put the keyboard back the way the user left it: restore the ambient
    // (auto-brightness) toggle, the idle-dim timeout, and the brightness level.
    [KBPPulseManager.brightnessClient enableAutoBrightness:manager.savedAutoBrightness forKeyboard:kb];
    [KBPPulseManager.brightnessClient setBrightness:manager.savedBrightness fadeSpeed:350 commit:true forKeyboard:kb];
    [KBPPulseManager.brightnessClient setIdleDimTime:manager.savedIdleDimTime forKeyboard:kb];

    manager.hasSavedSettings = NO;
    [manager clearPersistedSavedSettings];
}

+(void)restoreOrphanedSettings {
    if (KBPPulseManager.brightnessClient == nil) return;
    KBPPulseManager *manager = KBPPulseManager.sharedInstance;
    if (![manager loadPersistedSavedSettings]) return;
    unsigned long long kb = [self keyboardID];
    [KBPPulseManager.brightnessClient enableAutoBrightness:manager.savedAutoBrightness forKeyboard:kb];
    [KBPPulseManager.brightnessClient setBrightness:manager.savedBrightness fadeSpeed:350 commit:true forKeyboard:kb];
    [KBPPulseManager.brightnessClient setIdleDimTime:manager.savedIdleDimTime forKeyboard:kb];
    manager.hasSavedSettings = NO;
    [manager clearPersistedSavedSettings];
}

// MARK: - Persisted originals
//
// Saving the originals to UserDefaults means a crash, force-quit, or logout
// cannot leave idle dimming disabled forever: the next launch restores them
// before taking control again.

+ (NSUserDefaults *)savedSettingsDefaults {
    // A suite domain is shared by the app and the CLI regardless of which
    // bundle (if any) is hosting the process.
    static NSUserDefaults *defaults;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.ethanrdoesmc.kbpulseapp"];
    });
    return defaults ?: NSUserDefaults.standardUserDefaults;
}

-(void)persistSavedSettings {
    NSUserDefaults *defaults = [KBPPulseManager savedSettingsDefaults];
    [defaults setBool:self.savedAutoBrightness forKey:KBPSavedAutoBrightnessKey];
    [defaults setDouble:self.savedIdleDimTime forKey:KBPSavedIdleDimTimeKey];
    [defaults setDouble:self.savedBrightness forKey:KBPSavedBrightnessKey];
    [defaults setBool:YES forKey:KBPHasSavedSettingsKey];
}

-(BOOL)loadPersistedSavedSettings {
    NSUserDefaults *defaults = [KBPPulseManager savedSettingsDefaults];
    if (![defaults boolForKey:KBPHasSavedSettingsKey]) return NO;
    self.savedAutoBrightness = [defaults boolForKey:KBPSavedAutoBrightnessKey];
    self.savedIdleDimTime = [defaults doubleForKey:KBPSavedIdleDimTimeKey];
    self.savedBrightness = (float)[defaults doubleForKey:KBPSavedBrightnessKey];
    self.hasSavedSettings = YES;
    return YES;
}

-(void)clearPersistedSavedSettings {
    NSUserDefaults *defaults = [KBPPulseManager savedSettingsDefaults];
    [defaults removeObjectForKey:KBPHasSavedSettingsKey];
    [defaults removeObjectForKey:KBPSavedAutoBrightnessKey];
    [defaults removeObjectForKey:KBPSavedIdleDimTimeKey];
    [defaults removeObjectForKey:KBPSavedBrightnessKey];
}

+(void)configure {
    [self loadPrivateFrameworks];
    // Recover originals from a previous crash before overwriting the saved
    // snapshot with KBPulse's current (modified) values.
    [self restoreOrphanedSettings];
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