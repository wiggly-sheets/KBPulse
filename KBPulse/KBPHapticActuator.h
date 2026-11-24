//
//  KBPHapticActuator.h
//  KBPulse
//
//  Private MultitouchSupport bridge. Public NSHapticFeedbackManager is silent
//  for a background app unless a finger is on the trackpad.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KBPHapticActuator : NSObject

/// Taps every open trackpad actuator. `intensity` scales the waveform and the
/// stock actuation, from a light tick (0.1) to a full click (1.0).
+ (BOOL)tapWithIntensity:(float)intensity;

@end

NS_ASSUME_NONNULL_END
