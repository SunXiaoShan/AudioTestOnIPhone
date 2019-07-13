//
//  AudioPlayerManager.m
//  AudioTest
//
//  Created by Phineas.Huang on 2019/7/10.
//  Copyright © 2019 Phineas. All rights reserved.
//

#import "AudioPlayerManager.h"

#import <AudioToolbox/AudioToolbox.h>

static const UInt32 maxBufferSize = 0x10000;
static const UInt32 minBufferSize = 0x4000;
static const UInt32 maxBufferNum = 1;

@interface AudioPlayerManager() {
    AudioFileID _audioFile;
    AudioStreamBasicDescription _dataFormat;
    AudioQueueRef _queue;
    UInt32 numPacketsToRead;
    AudioStreamPacketDescription *packetDescs;
    AudioQueueBufferRef buffers[maxBufferNum];
    SInt64 packetIndex;
    UInt32 maxPacketSize;
    UInt32 outBufferSize;
}

@end

@implementation AudioPlayerManager

#pragma mark - Play audio

- (void)loadAudio:(NSString *)audioFileName {
    AudioFileClose(_audioFile);
    [self freeMemory];

    _audioFile = [self loadAudioFile:audioFileName];
    if (_audioFile == nil) {
        return;
    }

    NSError *error;
    _dataFormat = [self parseAudioFileData:_audioFile error:&error];
    if (error) {
        return;
    }

    [self prepareAudioFile:_audioFile dataFormat:_dataFormat];
}

#pragma mark - load data

- (AudioFileID)loadAudioFile:(NSString *)audioPath {
    AudioFileID audioFile;
    OSStatus status = AudioFileOpenURL(
                              (__bridge CFURLRef _Nonnull)([NSURL fileURLWithPath:audioPath]),
                              kAudioFileReadPermission,
                              0,
                              &audioFile);
    if (status != noErr) {
        NSLog(@"Load file failed %d", status);
        return nil;
    }

    return audioFile;
}

#pragma mark - parse data

- (OSStatus)parseAudioListFileData:(AudioFileID)audioFileID {
    UInt32 formatListSize = 0;
    OSStatus status = AudioFileGetPropertyInfo(audioFileID, kAudioFilePropertyFormatList, &formatListSize, NULL);
    if (status != noErr) NSLog(@"AudioFileGetPropertyInfo data format failed");
    if (status == noErr) {
        AudioFormatListItem *formatList = (AudioFormatListItem *)malloc(formatListSize);
        status = AudioFileGetProperty(audioFileID, kAudioFilePropertyFormatList, &formatListSize, formatList);
        if (status == noErr) {
            for (int i = 0; i * sizeof(AudioFormatListItem) < formatListSize; i += sizeof(AudioFormatListItem)) {
                AudioStreamBasicDescription pasbd = formatList[i].mASBD;
                NSLog(@"mFormatID = %d", (signed int)pasbd.mFormatID);
                NSLog(@"mFormatFlags = %d", (signed int)pasbd.mFormatFlags);
                NSLog(@"mSampleRate = %ld", (signed long int)pasbd.mSampleRate);
                NSLog(@"mBitsPerChannel = %d", (signed int)pasbd.mBitsPerChannel);
                NSLog(@"mBytesPerFrame = %d", (signed int)pasbd.mBytesPerFrame);
                NSLog(@"mBytesPerPacket = %d", (signed int)pasbd.mBytesPerPacket);
                NSLog(@"mChannelsPerFrame = %d", (signed int)pasbd.mChannelsPerFrame);
                NSLog(@"mFramesPerPacket = %d", (signed int)pasbd.mFramesPerPacket);
                NSLog(@"mReserved = %d", (signed int)pasbd.mReserved);
            }
        }
        free(formatList);
    }

    return status;
}

- (AudioStreamBasicDescription)parseAudioFileData:(AudioFileID)audioFileID
                                            error:(NSError **)error {
    AudioStreamBasicDescription buffDataFormat;
    UInt32 formatSize = sizeof(AudioStreamBasicDescription);
    OSStatus status = AudioFileGetProperty(audioFileID, kAudioFilePropertyDataFormat, &formatSize, &buffDataFormat);
    if (status != noErr) {
        NSLog(@"parseAudioFileData failed %d", status);
        *error = [NSError errorWithDomain:@"parse data format failed" code:-100 userInfo:nil];
    }

    return buffDataFormat;
}

- (OSStatus)parseAudioBitRate:(AudioFileID)audioFileID {
    UInt32 bitRate;
    UInt32 bitRateSize = sizeof(bitRate);
    OSStatus status = AudioFileGetProperty(audioFileID, kAudioFilePropertyBitRate, &bitRateSize, &bitRate);
    if (status != noErr) NSLog(@"AudioFileGetProperty bitrate failed %d", status);
    NSLog(@"bitRate = %d", bitRate);

    return status;
}

#pragma mark -

- (void)prepareAudioFile:(AudioFileID)audioFileID
           dataFormat:(AudioStreamBasicDescription)dataFormat {
    OSStatus status;

    // Step 1: Register callback
    // Callback function will fill buffer. Then add to buffer queue.
    status = AudioQueueNewOutput(
                        &dataFormat,
                        BufferCallback,
                        (__bridge void * _Nullable)(self),
                        nil,
                        nil,
                        0,
                        &_queue
                        );
    if (status != noErr) NSLog(@"AudioQueueNewOutput bitrate failed %d", status);

    // Step 2: Calculate the buffer size
    UInt32 size = sizeof(maxPacketSize);
    AudioFileGetProperty(
                         audioFileID,
                         kAudioFilePropertyPacketSizeUpperBound,
                         &size,
                         &maxPacketSize);
    if (status != noErr) NSLog(@"kAudioFilePropertyPacketSizeUpperBound failed %d", status);

    if (dataFormat.mFramesPerPacket != 0) {
        Float64 numPacketsPersecond = dataFormat.mSampleRate / dataFormat.mFramesPerPacket;
        outBufferSize = numPacketsPersecond * maxPacketSize;

    } else {
        outBufferSize = (maxBufferSize > maxPacketSize) ? maxBufferSize : maxPacketSize;
    }

    if (outBufferSize > maxBufferSize &&
        outBufferSize > maxPacketSize) {
        outBufferSize = maxBufferSize;

    } else {
        if (outBufferSize < minBufferSize) {
            outBufferSize = minBufferSize;
        }
    }

    // Step 3: Calculate the package count
    numPacketsToRead = outBufferSize / maxPacketSize;

    // Step 4: Alloc AudioStreamPacketDescription buffers
    packetDescs = (AudioStreamPacketDescription *)malloc(numPacketsToRead * sizeof (AudioStreamPacketDescription));

    // Step 5: Reset the packet index
    packetIndex = 0;

    // Step 6: Allocate buffer
    for (int i = 0; i < maxBufferNum; i++) {
        // Step 6.1: allock the buffer
        status = AudioQueueAllocateBuffer(
                                          _queue,
                                          outBufferSize,
                                          &buffers[i]
                                          );
        if (status != noErr) NSLog(@"AudioQueueAllocateBuffer failed %d", status);
    }
}

#pragma mark -

- (BOOL)isPlayingAudio {
    UInt32 running;
    UInt32 size;
    OSStatus status = AudioQueueGetProperty(_queue, kAudioQueueProperty_IsRunning, &running, &size);
    if (status != noErr) NSLog(@"kAudioQueueProperty_IsRunning failed %d", status);

    return (running > 0);
}

#pragma mark - valume

- (void)setupValume:(Float32)gain {
    OSStatus status = AudioQueueSetParameter(_queue, kAudioQueueParam_Volume, gain);
    if (status != noErr) NSLog(@"AudioQueueSetParameter failed %d", status);
}

#pragma mark -

- (void)playAudio {
    OSStatus status;
    for (int i = 0; i < maxBufferNum; i++) {
        [self audioQueueOutputWithQueue:_queue
                            queueBuffer:buffers[i]];
    }

    status = AudioQueueStart(_queue, nil);
    if (status != noErr) NSLog(@"AudioQueueStart failed %d", status);
}

- (void)pausAudio {
    OSStatus status = AudioQueuePause(_queue);
    if (status != noErr) NSLog(@"AudioQueuePause failed %d", status);
}

- (void)stopAudio {
    OSStatus status = AudioQueueStop(_queue, true);
    if (status != noErr) NSLog(@"AudioQueueStop failed %d", status);
}

#pragma mark -

- (void)audioQueueOutputWithQueue:(AudioQueueRef)audioQueue
                      queueBuffer:(AudioQueueBufferRef)audioQueueBuffer {
    OSStatus status;

    // Step 1: load audio data
    // If the packetIndex is out of range, the ioNumPackets will be 0
    UInt32 ioNumBytes = outBufferSize;
    UInt32 ioNumPackets = numPacketsToRead;
    status = AudioFileReadPacketData(
                            _audioFile,
                            NO,
                            &ioNumBytes,
                            packetDescs,
                            packetIndex,
                            &ioNumPackets,
                            audioQueueBuffer->mAudioData
                            );
    if (status != noErr) NSLog(@"AudioQueueSetParameter failed %d", status);

    // Step 2: prevent load audio data failed
    if (ioNumPackets <= 0) {
        return;
    }

    // Step 3: re-assign the data size
    audioQueueBuffer->mAudioDataByteSize = ioNumBytes;

    // Step 4: fill the buffer to AudioQueue
    status = AudioQueueEnqueueBuffer(
                            audioQueue,
                            audioQueueBuffer,
                            ioNumPackets,
                            packetDescs
                            );
    if (status != noErr) NSLog(@"AudioQueueEnqueueBuffer failed %d", status);

    // Step 5: Shift to followed index
    packetIndex += ioNumPackets;
}

#pragma mark - release memory

- (void)disposeAudioQueue {
    if (_queue == nil) {
        return;
    }
    OSStatus status = AudioQueueDispose(_queue, true);
    if (status != noErr) NSLog(@"AudioQueueDispose failed %d", status);
}

- (void)freeMemory {
    if (packetDescs) {
        free(packetDescs);
    }
    packetDescs = NULL;
}

#pragma mark -

- (OSStatus)close:(AudioFileID)audioFileID {
    OSStatus status = AudioFileClose( audioFileID );
    if (status != noErr) NSLog(@"AudioFileClose failed %d", status);

    return status;
}

#pragma mark -

- (void)dealloc {
    [self freeMemory];
}

#pragma mark - Play audio buffer complete callback

static void BufferCallback(void *inUserData,AudioQueueRef inAQ,
                           AudioQueueBufferRef buffer) {
    AudioPlayerManager *manager = (__bridge AudioPlayerManager *)inUserData;
    [manager audioQueueOutputWithQueue:inAQ queueBuffer:buffer];
}

#pragma mark -

@end
