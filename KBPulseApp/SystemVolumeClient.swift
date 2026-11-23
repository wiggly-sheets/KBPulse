//
//  SystemVolumeClient.swift
//  KBPulseApp
//
//  Helper to access system output volume via CoreAudio
//

import CoreAudio

enum SystemVolumeClient {
    static func systemOutputVolume() -> Float {
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: 0
        )

        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceAddress,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return 0 }

        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: 0
        )
        var volume = Float32(0)
        size = UInt32(MemoryLayout<Float32>.size)
        status = AudioObjectGetPropertyData(deviceID, &volumeAddress, 0, nil, &size, &volume)

        if status != noErr {
            var left = Float32(0)
            var right = Float32(0)
            var channelSize = UInt32(MemoryLayout<Float32>.size)
            var leftAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: 1
            )
            var rightAddress = leftAddress
            rightAddress.mElement = 2

            guard AudioObjectGetPropertyData(deviceID, &leftAddress, 0, nil, &channelSize, &left) == noErr else {
                return 0
            }
            channelSize = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(deviceID, &rightAddress, 0, nil, &channelSize, &right) == noErr {
                volume = (left + right) / 2
            } else {
                volume = left
            }
        }

        return min(1, max(0, volume))
    }
}
