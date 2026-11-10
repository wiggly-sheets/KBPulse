//
//  SystemVolumeClient.m
//  KBPulseApp
//
//  Helper to access system output volume via AudioToolbox
//

#import "SystemVolumeClient.h"
#import <AudioToolbox/AudioToolbox.h>

@implementation SystemVolumeClient

+ (float)systemOutputVolume {
    // Get the system output volume using AudioToolbox
    // AudioObjectPropertyAddress-based approach via AudioToolbox
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMaster
    };
    
    AudioObjectID deviceID = kAudioObjectUnknown;
    UInt32 size = sizeof(deviceID);
    OSStatus status = AudioObjectGetPropertyData(kAudioObjectPropertyClass, &address, 0, NULL, &size, &deviceID);
    
    if (status != noErr || deviceID == kAudioObjectUnknown) {
        return 0.0;
    }
    
    // Query the device's volume scalar (0.0 to 1.0)
    AudioObjectPropertyAddress volumeAddr = {
        kAudioDevicePropertyVolumeScalar,
        kAudioObjectPropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    
    float volume = 0.0;
    size = sizeof(volume);
    status = AudioObjectGetPropertyData(deviceID, &volumeAddr, 0, NULL, &size, &volume);
    
    if (status != noErr) {
        return 0.0;
    }
    
    // Clamp to valid range [0.0, 1.0]
    if (volume < 0.0) return 0.0;
    if (volume > 1.0) return 1.0;
    return volume;
}

@end