#import "RippleOverlay.h"
#import <QuartzCore/QuartzCore.h>

@interface RippleOverlay () {
    NSPanel *_overlayPanel;
    NSView *_contentView;
}
@end

@implementation RippleOverlay

+ (instancetype)sharedOverlay {
    static RippleOverlay *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[RippleOverlay alloc] init];
    });
    return instance;
}

+ (NSString *)nameForRippleColor:(ClackityRippleColor)theme {
    switch (theme) {
        case ClackityRippleColorElectricCyan: return @"Electric Cyan";
        case ClackityRippleColorMinimalWhite: return @"Minimal White";
        case ClackityRippleColorWarmAmber:    return @"Warm Amber";
        case ClackityRippleColorRosePink:     return @"Rose Pink";
        case ClackityRippleColorEmeraldGreen: return @"Emerald Green";
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _enabled = YES;
        _colorTheme = ClackityRippleColorElectricCyan;
        [self setupOverlayWindow];
    }
    return self;
}

- (NSColor *)strokeColorForCurrentTheme:(BOOL)isRightClick {
    if (isRightClick) {
        return [NSColor colorWithCalibratedRed:1.0 green:0.35 blue:0.35 alpha:0.65];
    }
    switch (_colorTheme) {
        case ClackityRippleColorElectricCyan:
            return [NSColor colorWithCalibratedRed:0.0 green:0.82 blue:1.0 alpha:0.55];
        case ClackityRippleColorMinimalWhite:
            return [NSColor colorWithCalibratedWhite:1.0 alpha:0.65];
        case ClackityRippleColorWarmAmber:
            return [NSColor colorWithCalibratedRed:1.0 green:0.65 blue:0.10 alpha:0.60];
        case ClackityRippleColorRosePink:
            return [NSColor colorWithCalibratedRed:1.0 green:0.25 blue:0.55 alpha:0.60];
        case ClackityRippleColorEmeraldGreen:
            return [NSColor colorWithCalibratedRed:0.20 green:0.88 blue:0.45 alpha:0.60];
    }
}

- (void)setupOverlayWindow {
    // Span across all visible screens
    NSRect totalFrame = NSZeroRect;
    for (NSScreen *screen in [NSScreen screens]) {
        totalFrame = NSUnionRect(totalFrame, screen.frame);
    }
    
    _overlayPanel = [[NSPanel alloc] initWithContentRect:totalFrame
                                               styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
    
    _overlayPanel.backgroundColor = [NSColor clearColor];
    _overlayPanel.opaque = NO;
    _overlayPanel.hasShadow = NO;
    _overlayPanel.level = NSPopUpMenuWindowLevel;
    _overlayPanel.ignoresMouseEvents = YES;
    _overlayPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                       NSWindowCollectionBehaviorStationary |
                                       NSWindowCollectionBehaviorIgnoresCycle;
    
    _contentView = [[NSView alloc] initWithFrame:totalFrame];
    _contentView.wantsLayer = YES;
    _overlayPanel.contentView = _contentView;
    
    [_overlayPanel orderFrontRegardless];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(screenParametersChanged:)
                                                 name:NSApplicationDidChangeScreenParametersNotification
                                               object:nil];
}

- (void)screenParametersChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSRect totalFrame = NSZeroRect;
        for (NSScreen *screen in [NSScreen screens]) {
            totalFrame = NSUnionRect(totalFrame, screen.frame);
        }
        [self->_overlayPanel setFrame:totalFrame display:YES];
        self->_contentView.frame = totalFrame;
    });
}

- (void)showRippleAtScreenPoint:(CGPoint)cgPoint isRightClick:(BOOL)isRightClick {
    if (!_enabled) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // CGEventGetLocation is in top-left coordinates of primary display.
        // Convert to Cocoa bottom-left coordinates.
        NSScreen *primaryScreen = [NSScreen screens].firstObject;
        CGFloat primaryHeight = primaryScreen.frame.size.height;
        NSPoint cocoaPoint = NSMakePoint(cgPoint.x, primaryHeight - cgPoint.y);
        
        // Convert screen coordinates to overlay content view coordinates
        NSPoint viewPoint = [self->_overlayPanel convertPointFromScreen:cocoaPoint];
        
        // Create expanding ripple shape layer
        CAShapeLayer *rippleLayer = [CAShapeLayer layer];
        CGFloat startRadius = 6.0;
        CGFloat endRadius = isRightClick ? 42.0 : 36.0;
        
        CGRect startRect = CGRectMake(viewPoint.x - startRadius, viewPoint.y - startRadius, startRadius * 2, startRadius * 2);
        CGRect endRect = CGRectMake(viewPoint.x - endRadius, viewPoint.y - endRadius, endRadius * 2, endRadius * 2);
        
        CGPathRef startPath = CGPathCreateWithEllipseInRect(startRect, NULL);
        CGPathRef endPath = CGPathCreateWithEllipseInRect(endRect, NULL);
        
        rippleLayer.path = startPath;
        rippleLayer.fillColor = [NSColor clearColor].CGColor;
        
        NSColor *strokeColor = [self strokeColorForCurrentTheme:isRightClick];
        rippleLayer.strokeColor = strokeColor.CGColor;
        rippleLayer.lineWidth = 2.5;
        
        [self->_contentView.layer addSublayer:rippleLayer];
        
        // Path animation (expanding ring)
        CABasicAnimation *pathAnim = [CABasicAnimation animationWithKeyPath:@"path"];
        pathAnim.fromValue = (__bridge id)startPath;
        pathAnim.toValue = (__bridge id)endPath;
        
        // Opacity animation (fade out)
        CABasicAnimation *opacityAnim = [CABasicAnimation animationWithKeyPath:@"opacity"];
        opacityAnim.fromValue = @(1.0);
        opacityAnim.toValue = @(0.0);
        
        // Line width animation (thins out as it expands)
        CABasicAnimation *widthAnim = [CABasicAnimation animationWithKeyPath:@"lineWidth"];
        widthAnim.fromValue = @(2.8);
        widthAnim.toValue = @(0.5);
        
        CAAnimationGroup *group = [CAAnimationGroup animation];
        group.animations = @[pathAnim, opacityAnim, widthAnim];
        group.duration = 0.32;
        group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        group.removedOnCompletion = NO;
        group.fillMode = kCAFillModeForwards;
        
        [CATransaction begin];
        [CATransaction setCompletionBlock:^{
            [rippleLayer removeFromSuperlayer];
            CGPathRelease(startPath);
            CGPathRelease(endPath);
        }];
        [rippleLayer addAnimation:group forKey:@"ripple"];
        [CATransaction commit];
    });
}

@end
