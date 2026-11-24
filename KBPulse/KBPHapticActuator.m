//
//  KBPHapticActuator.m
//  KBPulse
//

#import "KBPHapticActuator.h"

#import <CoreFoundation/CoreFoundation.h>
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>

typedef CFTypeRef (*KBPMTActuatorCreateFromDeviceID)(uint64_t);
typedef IOReturn (*KBPMTActuatorOpen)(CFTypeRef);
typedef IOReturn (*KBPMTActuatorActuate)(CFTypeRef, int32_t, uint32_t, float, float);
typedef void *(*KBPMTActuationCreateFromDictionary)(CFDictionaryRef, int32_t);
typedef IOReturn (*KBPMTActuationActuate)(void *, void *, uint32_t, float, float);

static void *sHandle;
static KBPMTActuatorCreateFromDeviceID sCreate;
static KBPMTActuatorOpen sOpen;
static KBPMTActuatorActuate sActuate;
static KBPMTActuationCreateFromDictionary sCreateActuation;
static KBPMTActuationActuate sActuateActuation;
static NSMutableArray *sActuators;
static dispatch_once_t sOnce;

@implementation KBPHapticActuator

+ (BOOL)prepare {
    dispatch_once(&sOnce, ^{
        sHandle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
                         RTLD_LAZY | RTLD_LOCAL);
        if (!sHandle) return;

        sCreate = (KBPMTActuatorCreateFromDeviceID)dlsym(sHandle, "MTActuatorCreateFromDeviceID");
        sOpen = (KBPMTActuatorOpen)dlsym(sHandle, "MTActuatorOpen");
        sActuate = (KBPMTActuatorActuate)dlsym(sHandle, "MTActuatorActuate");
        sCreateActuation = (KBPMTActuationCreateFromDictionary)dlsym(sHandle, "MTActuationCreateFromDictionary");
        sActuateActuation = (KBPMTActuationActuate)dlsym(sHandle, "MTActuationActuate");
        if (!sCreate || !sOpen || !sActuate) return;

        sActuators = [NSMutableArray array];
        io_iterator_t iter = 0;
        CFMutableDictionaryRef matching = IOServiceMatching("AppleMultitouchDevice");
        if (!matching) return;
        if (IOServiceGetMatchingServices(0, matching, &iter) != KERN_SUCCESS) return;

        io_object_t device;
        while ((device = IOIteratorNext(iter)) != 0) {
            CFTypeRef idRef = IORegistryEntryCreateCFProperty(device, CFSTR("Multitouch ID"),
                                                              kCFAllocatorDefault, 0);
            if (idRef && CFGetTypeID(idRef) == CFNumberGetTypeID()) {
                int64_t deviceID = 0;
                if (CFNumberGetValue((CFNumberRef)idRef, kCFNumberSInt64Type, &deviceID)) {
                    CFTypeRef actuator = sCreate((uint64_t)deviceID);
                    if (actuator) {
                        if (sOpen(actuator) == kIOReturnSuccess) {
                            [sActuators addObject:(__bridge id)actuator];
                        }
                        CFRelease(actuator);
                    }
                }
            }
            if (idRef) CFRelease(idRef);
            IOObjectRelease(device);
        }
        if (iter) IOObjectRelease(iter);
    });
    return sActuators.count > 0;
}

+ (BOOL)isAvailable {
    return [self prepare];
}

+ (BOOL)tap {
    return [self tapWithIntensity:1.0f];
}

+ (BOOL)tapWithIntensity:(float)intensity {
    if (![self prepare]) return NO;

    float level = fminf(1.0f, fmaxf(0.05f, intensity));

    // The waveform path matches nospeaker: a short sine burst on a silent
    // Gaussian base. It is stronger than the stock actuation IDs and works
    // without a finger resting on the trackpad.
    if (sCreateActuation && sActuateActuation) {
        NSDictionary *shape = @{
            @"BaseWaveform": @{
                @"Type": @"Gaussian",
                @"Amplitude": @(0.0),
                @"DurationMS": @(28.0)
            },
            @"Tones": @[@{
                @"Type": @"Sine",
                @"Amplitude": @(level),
                @"DurationMS": @(28.0),
                @"DelayMS": @(0.0),
                @"FrequencykHz": @(0.12)
            }]
        };
        void *actuation = sCreateActuation((__bridge CFDictionaryRef)shape, 0);
        if (actuation) {
            BOOL any = NO;
            @synchronized (sActuators) {
                for (id actuator in sActuators) {
                    if (sActuateActuation(actuation, (__bridge void *)actuator, 0, level, 0) == kIOReturnSuccess) {
                        any = YES;
                    }
                }
            }
            CFRelease((CFTypeRef)actuation);
            if (any) return YES;
        }
    }

    @synchronized (sActuators) {
        BOOL any = NO;
        for (id actuator in sActuators) {
            // 6 is the strong level-change actuation in the built-in plist.
            if (sActuate((__bridge CFTypeRef)actuator, 6, 0, level, 0.0f) == kIOReturnSuccess) {
                any = YES;
            }
        }
        return any;
    }
}

@end
