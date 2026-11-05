// Read-only Core Audio metadata. No stream start, rate change or USB command.
#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>

static int readProperty(AudioObjectID object, AudioObjectPropertySelector selector,
                        AudioObjectPropertyScope scope, UInt32 *size, void *value) {
    AudioObjectPropertyAddress address = {selector, scope, kAudioObjectPropertyElementMain};
    return AudioObjectGetPropertyData(object, &address, 0, NULL, size, value) == noErr;
}
static void integerProperty(AudioObjectID object, AudioObjectPropertySelector selector, AudioObjectPropertyScope scope) {
    UInt32 value = 0, size = sizeof value;
    if (readProperty(object, selector, scope, &size, &value)) printf("%u", (unsigned)value);
    else fputs("null", stdout);
}
static void streams(AudioDeviceID device, AudioObjectPropertyScope scope) {
    AudioObjectPropertyAddress address = {kAudioDevicePropertyStreams, scope, kAudioObjectPropertyElementMain};
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(device, &address, 0, NULL, &size) || !size) { fputs("[]", stdout); return; }
    AudioStreamID *items = malloc(size);
    if (!items) { fputs("null", stdout); return; }
    if (!readProperty(device, kAudioDevicePropertyStreams, scope, &size, items)) { free(items); fputs("null", stdout); return; }
    putchar('[');
    for (unsigned i = 0; i < size / sizeof *items; ++i) {
        if (i) putchar(',');
        fputs("{\"latency_frames\":", stdout);
        integerProperty(items[i], kAudioStreamPropertyLatency, kAudioObjectPropertyScopeGlobal);
        for (unsigned format = 0; format < 2; ++format) {
            AudioStreamBasicDescription value = {0}; UInt32 bytes = sizeof value;
            fputs(format ? ",\"physical_format\":" : ",\"virtual_format\":", stdout);
            if (readProperty(items[i], format ? kAudioStreamPropertyPhysicalFormat : kAudioStreamPropertyVirtualFormat,
                             kAudioObjectPropertyScopeGlobal, &bytes, &value))
                printf("{\"rate_hz\":%.0f,\"channels\":%u,\"bits_per_channel\":%u}", value.mSampleRate, (unsigned)value.mChannelsPerFrame, (unsigned)value.mBitsPerChannel);
            else fputs("null", stdout);
        }
        putchar('}');
    }
    putchar(']'); free(items);
}
int main(void) {
    AudioObjectPropertyAddress address = {kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size) || !size) return 1;
    AudioDeviceID *items = malloc(size), device = 0;
    if (!items) return 1;
    if (!readProperty(kAudioObjectSystemObject, kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal, &size, items)) { free(items); return 1; }
    for (unsigned i = 0; i < size / sizeof *items; ++i) {
        CFStringRef name = NULL; UInt32 bytes = sizeof name;
        if (readProperty(items[i], kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal, &bytes, &name) && name) {
            if (CFEqual(name, CFSTR("Duet USB"))) {
                if (device) { CFRelease(name); free(items); fputs("Multiple Duet devices; no report.\n", stderr); return 1; }
                device = items[i];
            }
            CFRelease(name);
        }
    }
    free(items);
    if (!device) { fputs("Duet USB not found.\n", stderr); return 1; }
    Float64 rate = 0; size = sizeof rate;
    if (!readProperty(device, kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, &size, &rate)) return 1;
    printf("{\"device\":\"Duet USB\",\"sample_rate_hz\":%.0f,\"buffer_frames\":", rate);
    integerProperty(device, kAudioDevicePropertyBufferFrameSize, kAudioObjectPropertyScopeGlobal);
    for (unsigned direction = 0; direction < 2; ++direction) {
        AudioObjectPropertyScope scope = direction ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput;
        fputs(direction ? ",\"output\":{" : ",\"input\":{", stdout);
        fputs("\"device_latency_frames\":", stdout); integerProperty(device, kAudioDevicePropertyLatency, scope);
        fputs(",\"safety_offset_frames\":", stdout); integerProperty(device, kAudioDevicePropertySafetyOffset, scope);
        fputs(",\"streams\":", stdout); streams(device, scope); putchar('}');
    }
    fputs(",\"note\":\"Reported metadata only; not measured analog round-trip latency. No identifying device UID or serial included.\"}\n", stdout);
    return ferror(stdout) ? 1 : 0;
}
