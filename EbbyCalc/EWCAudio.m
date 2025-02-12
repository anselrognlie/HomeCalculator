//
//  EWCAudio.m
//  EbbyCalc
//
//  Created by Ansel Rognlie on 2/11/25.
//  Copyright © 2025 Ansel Rognlie. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

#import "EWCAudio.h"

@implementation EWCAudio

- (void)config {
  AVAudioSession *session = AVAudioSession.sharedInstance;
  [session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:AVAudioSessionCategoryOptionMixWithOthers error:nil];
  [session setActive:TRUE error:nil];
}

@end
