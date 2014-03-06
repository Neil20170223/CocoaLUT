//
//  LUTPreviewView.h
//  
//
//  Created by Wil Gieseler on 12/15/13.
//
//

#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import "LUT.h"

@interface LUTPreviewView : NSView

@property (assign, nonatomic) float maskAmount;
@property (strong, nonatomic) LUT *lut;
@property (strong, nonatomic) NSImage *previewImage;
@property (strong, nonatomic) AVPlayer *avPlayer;

@end