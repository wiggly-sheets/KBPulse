//
//  SystemVolumeClient.h
//  KBPulseApp
//
//  Helper to access system output volume via CoreAudio
//

#import <Foundation/Foundation.h>

@interface SystemVolumeClient : NSObject
+ (float)systemOutputVolume;
@end