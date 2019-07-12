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
static const UInt32 maxBufferNum = 3;

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

- (void)playAudio:(NSString *)audioFileName {
    _audioFile = [self loadAudioFile:audioFileName];
    if (_audioFile == nil) {
        return;
    }

    NSError *error;
    _dataFormat = [self parseAudioFileData:_audioFile error:&error];
    if (error) {
        return;
    }

    [self playAudioFile:_audioFile dataFormat:_dataFormat];
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

- (void)playAudioFile:(AudioFileID)audioFileID
           dataFormat:(AudioStreamBasicDescription)dataFormat {
    // Step 1: Register callback
    OSStatus status = AudioQueueNewOutput(
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

        // Step 6.2:
        [self audioQueueOutputWithQueue:_queue
                            queueBuffer:buffers[i]];
    }

    // Step 7: Set up valume
    Float32 gain = 1.0;
    status = AudioQueueSetParameter(_queue, kAudioQueueParam_Volume, gain);
    if (status != noErr) NSLog(@"AudioQueueSetParameter failed %d", status);

    // Step 8: Start -> callback
    AudioQueueStart(_queue, nil);
}

- (void)audioQueueOutputWithQueue:(AudioQueueRef)audioQueue
                      queueBuffer:(AudioQueueBufferRef)audioQueueBuffer {
    OSStatus status;

    // load data
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
    
    //成功读取时
    if (ioNumPackets > 0) {
        //将缓冲的容量设置为与读取的音频数据一样大小(确保内存空间)
        audioQueueBuffer->mAudioDataByteSize = ioNumBytes;
        //完成给队列配置缓存的处理
        status = AudioQueueEnqueueBuffer(
                                audioQueue,
                                audioQueueBuffer,
                                ioNumPackets,
                                packetDescs
                                );
        if (status != noErr) NSLog(@"AudioQueueEnqueueBuffer failed %d", status);
        
        //移动包的位置
        packetIndex += ioNumPackets;
    }
}





#pragma mark -

- (OSStatus)close:(AudioFileID)audioFileID {
    OSStatus status = AudioFileClose( audioFileID );
    if (status != noErr) NSLog(@"AudioFileClose failed %d", status);

    return status;
}


#pragma mark - static function

static void BufferCallback(void *inUserData,AudioQueueRef inAQ,
                           AudioQueueBufferRef buffer){
    AudioPlayerManager *manager = (__bridge AudioPlayerManager *)inUserData;
    [manager audioQueueOutputWithQueue:inAQ queueBuffer:buffer];
}

#pragma mark -

@end
