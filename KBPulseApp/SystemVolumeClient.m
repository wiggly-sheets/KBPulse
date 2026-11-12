//
//  SystemVolumeClient.m
//  KBPulseApp
//
//  Helper to access system output volume via AudioToolbox
//

#import "SystemVolumeClient.h"
#import <CoreAudio/CoreAudio.h>

@implementation SystemVolumeClient

+ (float)systemOutputVolume {
    // Query the default output device from the system object. Passing a
    // property selector (kAudioObjectPropertyClass) here, as an earlier
    // version did, always fails and silently returns 0.
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };

    AudioObjectID deviceID = kAudioObjectUnknown;
    UInt32 size = sizeof(deviceID);
    OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &deviceID);

    if (status != noErr || deviceID == kAudioObjectUnknown) {
        return 0.0f;
    }

    // Query the device's volume scalar (0.0 to 1.0).
    AudioObjectPropertyAddress volumeAddr = {
        kAudioDevicePropertyVolumeScalar,
        kAudioObjectPropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };

    Float32 volume = 0.0f;
    size = sizeof(volume);
    status = AudioObjectGetPropertyData(deviceID, &volumeAddr, 0, NULL, &size, &volume);

    if (status != noErr) {
        // Some devices only expose per-channel volume controls.
        Float32 left = 0.0f;
        Float32 right = 0.0f;
        UInt32 channelSize = sizeof(left);
        AudioObjectPropertyAddress leftAddr = {
            kAudioDevicePropertyVolumeScalar,
            kAudioObjectPropertyScopeOutput,
            1
        };
        AudioObjectPropertyAddress rightAddr = leftAddr;
        rightAddr.mElement = 2;

        if (AudioObjectGetPropertyData(deviceID, &leftAddr, 0, NULL, &channelSize, &left) != noErr) {
            return 0.0f;
        }
        channelSize = sizeof(right);
        if (AudioObjectGetPropertyData(deviceID, &rightAddr, 0, NULL, &channelSize, &right) == noErr) {
            volume = (left + right) / 2.0f;
        } else {
            volume = left;
        }
    }

    // Clamp to valid range [0.0, 1.0].
    if (volume < 0.0f) return 0.0f;
    if (volume > 1.0f) return 1.0f;
    return volume;
}

@end