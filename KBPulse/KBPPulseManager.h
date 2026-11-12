//
//  KBPPulseManager.h
//  KBPulse
//
//  Created by EthanRDoesMC on 10/20/21.
//

#import <Foundation/Foundation.h>
#import "KeyboardBrightnessClient.h"
#import "OSDManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface KBPPulseManager : NSObject
@property(nonatomic,strong) KeyboardBrightnessClient * brightnessClient;
@property(atomic,readwrite) BOOL paused;
+(id)sharedInstance;
+(void)loadPrivateFrameworks;
+(void)modifyBacklightSettings;
+(void)configure;
+(KeyboardBrightnessClient *)brightnessClient;
+(NSString *)configurationFile;
+(void)restoreBacklightSettings;
/// Restores settings left modified by a previous run that did not quit cleanly.
+(void)restoreOrphanedSettings;
+(unsigned long long)keyboardID;
@end

NS_ASSUME_NONNULL_END
