//
//  ViewController.m
//  AudioTestOnIPhone
//
//  Created by Phineas on 2019/6/27.
//  Copyright © 2019 Phineas. All rights reserved.
//

#import "ViewController.h"

#import "AudioPlayerManager.h"

@interface ViewController ()

@property (nonatomic, retain) AudioPlayerManager *audio1;
@property (nonatomic, retain) AudioPlayerManager *audio2;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.audio1 = [AudioPlayerManager new];
    self.audio2 = [AudioPlayerManager new];
}

- (IBAction)actionAudioPlay:(id)sender {
    NSString *path1 = [NSString stringWithFormat:@"%@", [[NSBundle mainBundle] pathForResource:@"success-notification-alert_A_major" ofType:@"wav"]];
    [self.audio1 loadAudio:path1];
    [self.audio1 playAudio];
}

- (IBAction)actionAudioPlay2:(id)sender {
    NSString *path2 = [NSString stringWithFormat:@"%@", [[NSBundle mainBundle] pathForResource:@"07076051" ofType:@"wav"]];
    [self.audio2 loadAudio:path2];
    [self.audio2 playAudio];
}

@end
