//
//  LUTPreviewView.m
//
//
//  Created by Wil Gieseler on 12/15/13.
//
//

#import "LUTPreviewView.h"
#import <QuartzCore/QuartzCore.h>

#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
#elif TARGET_OS_MAC
#import "NSImage+CocoaLUT.h"
#endif


@interface LUTPreviewView () {}

// Redefinitions to make it writable
@property (strong) AVPlayer *videoPlayer;
@property (assign) BOOL isVideo;

// Images
@property (strong) CALayer *normalImageLayer;
@property (strong) CALayer *lutImageLayer;

// Video
@property (strong) AVPlayerLayer *lutVideoLayer;
@property (strong) AVPlayerLayer *normalVideoLayer;

@property (strong) CALayer *maskLayer;

@property (strong) NSView  *borderView;

@property (strong) NSTextField *normalCaptionField;
@property (strong) NSTextField *lutCaptionField;

@end

@implementation LUTPreviewView

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self initialize];
    }
    return self;
}

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self initialize];
    }
    return self;
}

- (void)layout {
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue
                     forKey:kCATransactionDisableActions];

    _maskLayer.frame = CGRectMake(0, 0, self.bounds.size.width * self.maskAmount, self.bounds.size.height);
    self.normalImageLayer.frame = self.bounds;
    self.lutImageLayer.frame = self.bounds;
    self.normalVideoLayer.frame = self.bounds;
    self.lutVideoLayer.frame = self.bounds;

    _borderView.frame = CGRectMake(self.bounds.size.width * self.maskAmount, 0, 1, self.bounds.size.height);

    self.normalCaptionField.frame = CGRectMake(self.bounds.size.width * self.maskAmount - 100 - 5, 10, 100, 20);
    self.lutCaptionField.frame = CGRectMake(self.bounds.size.width * self.maskAmount + 5, 10, 100, 20);

    [CATransaction commit];

    [super layout];
}

- (void)setMaskAmount:(float)maskAmount {
    if (maskAmount > 1) {
        maskAmount = 1;
    }
    else if (maskAmount < 0) {
        maskAmount = 0;
    }
    _maskAmount = maskAmount;
    [self setNeedsLayout:YES];
}

- (void)setLut:(LUT *)lut {
    _lut = lut;
    [self updateImageViews];
    [self updateFilters];
}

- (void)updateFilters {
    if (self.lut) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            LUT *usedLUT = self.lut;
            if (self.lut.inputLowerBound != 0 || self.lut.inputUpperBound != 1) {
                //video will always be display-referred 0-1 (until it isn't)
                usedLUT = [self.lut LUTByChangingInputLowerBound:0 inputUpperBound:1];
            }
            CIFilter *filter = [usedLUT coreImageFilterWithCurrentColorSpace];
            //video layer filter always uses display's colorspace
            if (filter) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.lutVideoLayer.filters = @[filter];
                });
            }
        });
    }
}



- (void)updateImageViews {
    if (!self.previewImage) {
        return;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        NSImage *usedNormalImage = [self.previewImage cocoalut_imageByPreservingEmbeddedColorSpace:self.useImageEmbeddedColorspace];

        NSImage *lutImage = self.previewImage;
        if (self.lut && lutImage) {
            lutImage = [self.lut processNSImage:self.previewImage
                     preserveEmbeddedColorSpace:self.useImageEmbeddedColorspace
                                     renderPath:LUTImageRenderPathCoreImage];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.normalImageLayer.contents = usedNormalImage;
            self.lutImageLayer.contents = lutImage;
        });
    });
}

- (void)setUseImageEmbeddedColorspace:(BOOL)useImageEmbeddedColorspace{
    BOOL oldUseImageEmbeddedColorspace = self.useImageEmbeddedColorspace;
    _useImageEmbeddedColorspace = useImageEmbeddedColorspace;

    if (oldUseImageEmbeddedColorspace != self.useImageEmbeddedColorspace) {
        [self updateImageViews];
        [self updateFilters];
    }

}

- (void)setPreviewImage:(NSImage *)previewImage {
    _previewImage = previewImage;

    if (_previewImage) {
        self.videoURL = nil;
    }
    [self updateImageViews];
    [self setupPlaybackLayers];
}

- (void)setVideoURL:(NSURL *)videoURL {
    _videoURL = videoURL;

    if (videoURL) {

        AVPlayerItem *item = [AVPlayerItem playerItemWithURL:videoURL];
        [self.videoPlayer replaceCurrentItemWithPlayerItem:item];

        [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                          object:item
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            [[self.videoPlayer currentItem] seekToTime:kCMTimeZero];
        }];

        [self.videoPlayer play];

        self.previewImage = nil;
        self.isVideo = YES;
    }
    else {
        [self.videoPlayer pause];
        self.isVideo = NO;
    }

    [self setupPlaybackLayers];
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)isOpaque {
    return YES;
}

-(void)mouseDown:(NSEvent *)event {
    [self maskToEvent:event];
}

-(void)mouseDragged:(NSEvent *)event {
    [self maskToEvent:event];
}

- (void)maskToEvent:(NSEvent *)event {
    NSPoint newDragLocation = [self convertPoint:[event locationInWindow] fromView:nil];
    self.maskAmount = newDragLocation.x / self.bounds.size.width;
}

- (NSTextField *)textFieldWithSettings {
    NSTextField *textField = [[NSTextField alloc] initWithFrame:CGRectZero];
    textField.textColor = [NSColor whiteColor];
    [textField setBezeled:NO];
    [textField setDrawsBackground:NO];
    [textField setEditable:NO];
    [textField setSelectable:NO];
    [textField setWantsLayer:YES];
    textField.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSSmallControlSize]];
    textField.layer.shadowColor = [NSColor blackColor].CGColor;
    textField.layer.shadowOpacity = 1;
    textField.layer.shadowOffset = CGSizeMake(0, 1);
    textField.layer.shadowRadius = 0;
    textField.layer.masksToBounds = YES;
    textField.layer.opacity = 0.7;
    textField.layer.zPosition = 1;
    return textField;
}

- (NSImage *)previewImageAtCurrentTime{
    if (self.isVideo) {
        AVAssetImageGenerator *imageGenerator = [[AVAssetImageGenerator alloc]initWithAsset:self.videoPlayer.currentItem.asset];

        imageGenerator.requestedTimeToleranceBefore = kCMTimeZero;
        imageGenerator.requestedTimeToleranceAfter = kCMTimeZero;

        NSError *error;
        CGImageRef imageRef = [imageGenerator copyCGImageAtTime:self.videoPlayer.currentTime actualTime:NULL error:&error];

        if (error) {
            CGImageRelease(imageRef);
            return nil;
        }

        NSMutableData *mutableData = [NSMutableData data];

        CGImageDestinationRef dest = CGImageDestinationCreateWithData((CFMutableDataRef)mutableData, (CFStringRef)@"public.tiff", 1, NULL);

        CGImageDestinationAddImage(dest,imageRef,NULL);
        CGImageDestinationFinalize(dest);
        CFRelease(dest);

        CGImageRelease(imageRef);  // CGImageRef won't be released by ARC

        return [[NSImage alloc] initWithData:mutableData];
    }
    else{
        return self.previewImage.copy;
    }
}

- (NSImage *)lutPreviewImageAtCurrentTime{
    if (self.isVideo) {
        return [self.lut processNSImage:self.previewImageAtCurrentTime
             preserveEmbeddedColorSpace:self.useImageEmbeddedColorspace
                             renderPath:LUTImageRenderPathCoreImage];
    }
    else{
        return ((NSImage *)self.lutImageLayer.contents).copy;
    }
}

- (void)initialize {

    // Video Player
    self.videoPlayer = [[AVPlayer alloc] init];
    self.videoPlayer.muted = YES;
    self.videoPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;

    // Initial Mask
    self.maskAmount = 0.5;

    // Layer Settings
    self.wantsLayer = YES;
    self.layerUsesCoreImageFilters = YES;
    self.layer.backgroundColor = NSColor.blackColor.CGColor;

    // Caption Fields
    self.normalCaptionField = [self textFieldWithSettings];
    self.normalCaptionField.alignment = NSRightTextAlignment;
    self.normalCaptionField.stringValue = @"Original";
    [self addSubview:self.normalCaptionField];

    self.lutCaptionField = [self textFieldWithSettings];
    self.lutCaptionField.alignment = NSLeftTextAlignment;
    self.lutCaptionField.stringValue = @"LUT";
    [self addSubview:self.lutCaptionField];

    // Border Line
    self.borderView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 0, 0)];
    self.borderView.wantsLayer = YES;
    self.borderView.layer.backgroundColor = [NSColor colorWithWhite:1 alpha:0.5].CGColor;
    self.borderView.frame = CGRectMake(self.bounds.size.width * self.maskAmount, 0, 1, self.bounds.size.height);
    self.borderView.layer.zPosition = 1;
    [self addSubview:self.borderView];

    // Mask
    self.maskLayer = [CALayer layer];
    self.maskLayer.backgroundColor = NSColor.whiteColor.CGColor;
    self.maskLayer.frame = CGRectMake(0, 0, self.bounds.size.width * self.maskAmount, self.bounds.size.height);

    // Image Layers
    self.normalImageLayer = [[CALayer alloc] init];
    self.normalImageLayer.contentsGravity = kCAGravityResizeAspect;
    self.normalImageLayer.backgroundColor = NSColor.blackColor.CGColor;
    self.normalImageLayer.opaque = YES;
    self.lutImageLayer = [[CALayer alloc] init];
    self.lutImageLayer.contentsGravity = kCAGravityResizeAspect;
    self.lutImageLayer.backgroundColor = NSColor.blackColor.CGColor;
    self.lutImageLayer.opaque = YES;
    [self.layer addSublayer:self.lutImageLayer];
    [self.layer addSublayer:self.normalImageLayer];

    // Video Layers
    self.lutVideoLayer = [AVPlayerLayer playerLayerWithPlayer:self.videoPlayer];
    self.lutVideoLayer.backgroundColor = NSColor.blackColor.CGColor;
    self.lutVideoLayer.opaque = YES;
    self.normalVideoLayer = [AVPlayerLayer playerLayerWithPlayer:self.videoPlayer];
    self.normalVideoLayer.backgroundColor = NSColor.blackColor.CGColor;
    self.normalVideoLayer.opaque = YES;
    [self.layer addSublayer:self.lutVideoLayer];
    [self.layer addSublayer:self.normalVideoLayer];

    self.useImageEmbeddedColorspace = NO;

    [self setupPlaybackLayers];

}

- (void)setupPlaybackLayers {

    self.lutVideoLayer.hidden = !self.isVideo;
    self.normalVideoLayer.hidden = !self.isVideo;

    self.normalImageLayer.hidden = self.isVideo;
    self.lutImageLayer.hidden = self.isVideo;


    if (self.isVideo) {
        self.normalVideoLayer.mask = self.maskLayer;
    }
    else {
        self.normalImageLayer.mask = self.maskLayer;
    }
}

@end
