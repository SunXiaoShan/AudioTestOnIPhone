//
//  AudioPlayerManager.h
//  AudioTest
//
//  Created by Phineas.Huang on 2019/7/10.
//  Copyright © 2019 Phineas. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AudioPlayerManager : NSObject

- (void)playAudio:(NSString *)audioFileName;

- (void)pausAudio;
- (void)stopAudio;

- (void)setupValume:(Float32)gain;



@end

NS_ASSUME_NONNULL_END
