// Native Core Audio stream check. Sends silence, stores no samples, restores rate.
#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <math.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static AudioDeviceID device;
static AudioDeviceIOProcID proc;
static double originalRate;
static int started, changed, restoreFailed;
static volatile sig_atomic_t interrupted;
typedef struct { uint64_t callbacks, inputFrames, outputFrames; unsigned inputChannels, outputChannels; unsigned inputBytes, outputBytes; int floatInput; float peak; } Counters;
static Counters counts;
static AudioObjectPropertyAddress property(AudioObjectPropertySelector selector, AudioObjectPropertyScope scope) {
    return (AudioObjectPropertyAddress){selector, scope, kAudioObjectPropertyElementMain};
}
static OSStatus readProperty(AudioObjectID object, AudioObjectPropertySelector selector, AudioObjectPropertyScope scope, UInt32 *size, void *value) {
    AudioObjectPropertyAddress p=property(selector,scope);
    return AudioObjectGetPropertyData(object,&p,0,NULL,size,value);
}
static int setRate(double rate) {
    AudioObjectPropertyAddress p=property(kAudioDevicePropertyNominalSampleRate,kAudioObjectPropertyScopeGlobal);
    OSStatus status=AudioObjectSetPropertyData(device,&p,0,NULL,sizeof rate,&rate);
    if(status) {fprintf(stderr,"Set sample rate failed: %d\n",(int)status);return 0;}
    for(unsigned attempt=0;attempt<40;++attempt) {
        double actual=0;UInt32 size=sizeof actual;
        if(!readProperty(device,kAudioDevicePropertyNominalSampleRate,kAudioObjectPropertyScopeGlobal,&size,&actual) && fabs(actual-rate)<0.5)return 1;
        usleep(50000);
    }
    return 0;
}
static void cleanup(void) {
    if(started){AudioDeviceStop(device,proc);started=0;}
    if(proc){AudioDeviceDestroyIOProcID(device,proc);proc=NULL;}
    if(changed){int restored=setRate(originalRate);restoreFailed=!restored;printf("Restored sample rate: %s (%.0f Hz)\n",restored?"confirmed":"FAILED",originalRate);changed=0;}
}
static void interrupt(int signal){(void)signal;interrupted=1;}
static unsigned channels(AudioObjectPropertyScope scope) {
    AudioObjectPropertyAddress p=property(kAudioDevicePropertyStreamConfiguration,scope);
    UInt32 size=0;if(AudioObjectGetPropertyDataSize(device,&p,0,NULL,&size)||!size)return 0;
    AudioBufferList *list=malloc(size);if(!list)return 0;
    unsigned result=0;if(!AudioObjectGetPropertyData(device,&p,0,NULL,&size,list))
        for(UInt32 i=0;i<list->mNumberBuffers;++i)result+=list->mBuffers[i].mNumberChannels;
    free(list);return result;
}
static int streamFormat(AudioObjectPropertyScope scope, AudioStreamBasicDescription *format) {
    AudioObjectPropertyAddress p=property(kAudioDevicePropertyStreams,scope);
    UInt32 size=0;if(AudioObjectGetPropertyDataSize(device,&p,0,NULL,&size)||!size)return 0;
    AudioStreamID *streams=malloc(size);if(!streams)return 0;
    OSStatus status=AudioObjectGetPropertyData(device,&p,0,NULL,&size,streams);
    if(!status){UInt32 bytes=sizeof *format;status=readProperty(streams[0],kAudioStreamPropertyVirtualFormat,kAudioObjectPropertyScopeGlobal,&bytes,format);}
    free(streams);return status==0;
}
static OSStatus io(AudioObjectID id,const AudioTimeStamp *now,const AudioBufferList *input,
                   const AudioTimeStamp *inputTime,AudioBufferList *output,const AudioTimeStamp *outputTime,void *context) {
    (void)id;(void)now;(void)inputTime;(void)outputTime;
    Counters *c=context;unsigned inputFrames=0,outputFrames=0;
    ++c->callbacks;
    if(input)for(UInt32 i=0;i<input->mNumberBuffers;++i) {
        const AudioBuffer *b=&input->mBuffers[i];if(!b->mData)continue;
        unsigned frames=c->inputBytes?b->mDataByteSize/c->inputBytes:0;if(frames>inputFrames)inputFrames=frames;
        if(c->floatInput)for(unsigned j=0;j<b->mDataByteSize/sizeof(float);++j){float v=fabsf(((const float *)b->mData)[j]);if(v>c->peak)c->peak=v;}
    }
    if(output)for(UInt32 i=0;i<output->mNumberBuffers;++i){AudioBuffer *b=&output->mBuffers[i];if(!b->mData)continue;
        memset(b->mData,0,b->mDataByteSize);unsigned frames=c->outputBytes?b->mDataByteSize/c->outputBytes:0;if(frames>outputFrames)outputFrames=frames;}
    c->inputFrames+=inputFrames;c->outputFrames+=outputFrames;return noErr;
}
int main(int argc,char **argv) {
    if(argc!=2 || strcmp(argv[1],"96000")){fputs("Usage: native-duplex-check 96000\n",stderr);return 64;}
    AudioObjectPropertyAddress p=property(kAudioHardwarePropertyDevices,kAudioObjectPropertyScopeGlobal);
    UInt32 size=0;if(AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,&p,0,NULL,&size)||!size)return 1;
    AudioDeviceID *devices=malloc(size);if(!devices)return 1;
    if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&p,0,NULL,&size,devices)){free(devices);return 1;}
    for(unsigned i=0;i<size/sizeof(AudioDeviceID);++i){CFStringRef name=NULL;UInt32 bytes=sizeof name;
        if(!readProperty(devices[i],kAudioObjectPropertyName,kAudioObjectPropertyScopeGlobal,&bytes,&name)&&name){
            if(CFEqual(name,CFSTR("Duet USB"))){if(device){CFRelease(name);free(devices);fputs("Multiple Duet devices\n",stderr);return 1;}device=devices[i];}CFRelease(name);}}
    free(devices);if(!device){fputs("Duet USB unavailable in Core Audio\n",stderr);return 1;}
    size=sizeof originalRate;if(readProperty(device,kAudioDevicePropertyNominalSampleRate,kAudioObjectPropertyScopeGlobal,&size,&originalRate))return 1;
    counts.inputChannels=channels(kAudioObjectPropertyScopeInput);counts.outputChannels=channels(kAudioObjectPropertyScopeOutput);
    if(counts.inputChannels!=2||counts.outputChannels!=4){fputs("Unexpected channel layout\n",stderr);return 1;}
    atexit(cleanup);signal(SIGINT,interrupt);signal(SIGTERM,interrupt);
    changed=1;if(!setRate(96000))return 1;
    AudioStreamBasicDescription in={0},out={0};
    if(!streamFormat(kAudioObjectPropertyScopeInput,&in)||!streamFormat(kAudioObjectPropertyScopeOutput,&out))return 1;
    counts.inputBytes=in.mBytesPerFrame;counts.outputBytes=out.mBytesPerFrame;
    counts.floatInput=(in.mFormatFlags&kAudioFormatFlagIsFloat)&&in.mBitsPerChannel==32;
    printf("Configured rate: 96000 Hz; input %.0f Hz, output %.0f Hz; channels %u/%u\n",in.mSampleRate,out.mSampleRate,counts.inputChannels,counts.outputChannels);fflush(stdout);
    OSStatus status=AudioDeviceCreateIOProcID(device,io,&counts,&proc);
    if(status){fprintf(stderr,"Create audio callback failed: %d\n",(int)status);return 1;}
    status=AudioDeviceStart(device,proc);if(status){fprintf(stderr,"Start audio failed: %d\n",(int)status);return 1;}
    started=1;for(unsigned i=0;i<40&&!interrupted;++i)usleep(50000);
    status=AudioDeviceStop(device,proc);if(!status)started=0;
    if(status){fprintf(stderr,"Stop audio failed: %d\n",(int)status);return 1;}
    printf("Callbacks: %llu; input frames: %llu; output frames: %llu; input peak: %.2f dBFS\n",(unsigned long long)counts.callbacks,(unsigned long long)counts.inputFrames,(unsigned long long)counts.outputFrames,counts.peak>0?20*log10f(counts.peak):-INFINITY);
    int valid=!interrupted&&counts.callbacks>0&&counts.inputFrames>100000&&counts.outputFrames>100000&&fabs(in.mSampleRate-96000)<0.5&&fabs(out.mSampleRate-96000)<0.5;
    printf("Native 96 kHz duplex callback check: %s (silence output; no recording saved)\n",valid?"PASS":"FAIL");
    cleanup();return valid&&!restoreFailed?0:1;
}
