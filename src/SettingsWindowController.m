#import "SettingsWindowController.h"
#import "AudioEngine.h"
#import "RippleOverlay.h"
#import "SoundPackManager.h"
#import "CommunitySoundPacks.h"
#import "UpdateManager.h"
#import "AppDelegate.h"
#import "MenuBarController.h"
#import "HapticEngine.h"
#import <ServiceManagement/ServiceManagement.h>

#pragma mark - Flipped Views for Natural Top-Down Layout

@interface FlippedView : NSView
@end

@implementation FlippedView
- (BOOL)isFlipped {
    return YES;
}
@end

@interface FlippedCardView : NSView
@end

@implementation FlippedCardView
- (BOOL)isFlipped {
    return YES;
}
@end

@interface FlippedVisualEffectView : NSVisualEffectView
@end

@implementation FlippedVisualEffectView
- (BOOL)isFlipped {
    return YES;
}
@end

#pragma mark - Custom Sidebar Button with Generous Liquid Glass Padding

@interface SidebarButton : NSButton
@property (nonatomic, strong) NSImageView *iconView;
@property (nonatomic, strong) NSTextField *labelView;
@property (nonatomic, strong) CALayer *pillLayer;
@property (nonatomic, assign) BOOL isCurrent;
- (instancetype)initWithFrame:(NSRect)frame title:(NSString *)title systemSymbol:(NSString *)symbolName;
@end

@implementation SidebarButton

- (instancetype)initWithFrame:(NSRect)frame title:(NSString *)title systemSymbol:(NSString *)symbolName {
    self = [super initWithFrame:frame];
    if (self) {
        self.bezelStyle = NSBezelStyleRegularSquare;
        self.bordered = NO;
        self.title = @"";
        self.image = nil;
        self.wantsLayer = YES;
        
        // Background selection / hover pill
        _pillLayer = [CALayer layer];
        _pillLayer.frame = self.bounds;
        _pillLayer.cornerRadius = 8.0;
        _pillLayer.masksToBounds = YES;
        [self.layer addSublayer:_pillLayer];
        
        // Icon View with 14pt left inset (never stuck to the edge!)
        _iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(14, 8, 18, 18)];
        _iconView.imageScaling = NSImageScaleProportionallyDown;
        _iconView.image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
        _iconView.contentTintColor = [NSColor secondaryLabelColor];
        [self addSubview:_iconView];
        
        // Label with 10pt gap after icon
        _labelView = [[NSTextField alloc] initWithFrame:NSMakeRect(40, 8, frame.size.width - 50, 18)];
        _labelView.stringValue = title;
        _labelView.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        _labelView.editable = NO;
        _labelView.bezeled = NO;
        _labelView.drawsBackground = NO;
        _labelView.textColor = [NSColor labelColor];
        [self addSubview:_labelView];
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (NSView *)hitTest:(NSPoint)point {
    NSPoint localPoint = [self convertPoint:point fromView:self.superview];
    if (NSPointInRect(localPoint, self.bounds)) {
        return self;
    }
    return nil;
}

- (void)mouseDown:(NSEvent *)event {
    if (!_isCurrent) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _pillLayer.backgroundColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.14].CGColor;
        [CATransaction commit];
    }
}

- (void)mouseUp:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(loc, self.bounds)) {
        [self sendAction:self.action to:self.target];
    } else if (!_isCurrent) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _pillLayer.backgroundColor = [NSColor clearColor].CGColor;
        [CATransaction commit];
    }
}

- (void)setIsCurrent:(BOOL)isCurrent {
    _isCurrent = isCurrent;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (isCurrent) {
        // Liquid Glass Accent Pill
        _pillLayer.backgroundColor = [NSColor colorWithCalibratedRed:0.0 green:0.48 blue:1.0 alpha:0.95].CGColor;
        _pillLayer.borderWidth = 0.5;
        _pillLayer.borderColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.3].CGColor;
        _iconView.contentTintColor = [NSColor whiteColor];
        _labelView.textColor = [NSColor whiteColor];
        _labelView.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    } else {
        _pillLayer.backgroundColor = [NSColor clearColor].CGColor;
        _pillLayer.borderWidth = 0.0;
        _iconView.contentTintColor = [NSColor secondaryLabelColor];
        _labelView.textColor = [NSColor labelColor];
        _labelView.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    }
    [CATransaction commit];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) {
        [self removeTrackingArea:area];
    }
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                        options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp)
                                                          owner:self
                                                       userInfo:nil];
    [self addTrackingArea:area];
}

- (void)mouseEntered:(NSEvent *)event {
    if (!_isCurrent) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _pillLayer.backgroundColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.08].CGColor;
        [CATransaction commit];
    }
}

- (void)mouseExited:(NSEvent *)event {
    if (!_isCurrent) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        _pillLayer.backgroundColor = [NSColor clearColor].CGColor;
        [CATransaction commit];
    }
}

- (void)layout {
    [super layout];
    _pillLayer.frame = self.bounds;
}

@end

#pragma mark - Switch Profile Card View

@interface SwitchCardView : NSView
@property (nonatomic, copy) NSString *packName;
@property (nonatomic, assign) ClackitySoundProfile soundProfile;
@property (nonatomic, assign) BOOL isCustomPack;
@property (nonatomic, assign) BOOL isSelected;
@property (nonatomic, copy) void (^onCardSelected)(SwitchCardView *card);
@property (nonatomic, copy) void (^onCardPreview)(SwitchCardView *card);
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSTextField *typeTagLabel;
@property (nonatomic, strong) NSTextField *subLabel;
@property (nonatomic, strong) NSButton *playButton;
@end

@implementation SwitchCardView

- (instancetype)initWithFrame:(NSRect)frame
                         name:(NSString *)name
                      tagText:(NSString *)tagText
                     subtitle:(NSString *)subtitle
                 isCustomPack:(BOOL)isCustom
                     packName:(nullable NSString *)packName
                 soundProfile:(ClackitySoundProfile)profile {
    self = [super initWithFrame:frame];
    if (self) {
        _isCustomPack = isCustom;
        _packName = [packName copy];
        _soundProfile = profile;
        self.wantsLayer = YES;
        self.layer.cornerRadius = 6.0;
        
        // 1. Switch Name
        NSDictionary *nameAttrs = @{NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]};
        NSSize nameSize = [name sizeWithAttributes:nameAttrs];
        _nameLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(14, 7, nameSize.width + 2, 18)];
        _nameLabel.stringValue = name;
        _nameLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
        _nameLabel.editable = NO;
        _nameLabel.bezeled = NO;
        _nameLabel.drawsBackground = NO;
        [self addSubview:_nameLabel];
        
        // 2. Subtle Category & Weight Tag (Clean typography, zero neon bleeding boxes)
        CGFloat tagX = NSMaxX(_nameLabel.frame) + 6.0;
        _typeTagLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(tagX, 8, frame.size.width - tagX - 70, 16)];
        _typeTagLabel.stringValue = [NSString stringWithFormat:@"·  %@", tagText];
        _typeTagLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
        _typeTagLabel.textColor = [NSColor secondaryLabelColor];
        _typeTagLabel.editable = NO;
        _typeTagLabel.bezeled = NO;
        _typeTagLabel.drawsBackground = NO;
        [self addSubview:_typeTagLabel];
        
        // 3. Subtitle / Acoustic Description
        _subLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(14, 27, frame.size.width - 85, 16)];
        _subLabel.stringValue = subtitle;
        _subLabel.font = [NSFont systemFontOfSize:11];
        _subLabel.textColor = [NSColor secondaryLabelColor];
        _subLabel.editable = NO;
        _subLabel.bezeled = NO;
        _subLabel.drawsBackground = NO;
        [self addSubview:_subLabel];
        
        // 4. Play Preview button
        _playButton = [[NSButton alloc] initWithFrame:NSMakeRect(frame.size.width - 70, 12, 58, 26)];
        _playButton.title = @"Preview";
        _playButton.bezelStyle = NSBezelStyleRounded;
        _playButton.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium];
        _playButton.target = self;
        _playButton.action = @selector(playClicked:);
        [self addSubview:_playButton];
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)setSelected:(BOOL)selected {
    _isSelected = selected;
    if (selected) {
        self.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.0 green:0.48 blue:1.0 alpha:0.18].CGColor;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [NSColor colorWithCalibratedRed:0.0 green:0.48 blue:1.0 alpha:0.75].CGColor;
    } else {
        self.layer.backgroundColor = [NSColor clearColor].CGColor;
        self.layer.borderWidth = 0.0;
    }
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) {
        [self removeTrackingArea:area];
    }
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                        options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp)
                                                          owner:self
                                                       userInfo:nil];
    [self addTrackingArea:area];
}

- (void)mouseEntered:(NSEvent *)event {
    if (!_isSelected) {
        self.layer.backgroundColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.06].CGColor;
    }
}

- (void)mouseExited:(NSEvent *)event {
    if (!_isSelected) {
        self.layer.backgroundColor = [NSColor clearColor].CGColor;
    }
}

- (void)mouseUp:(NSEvent *)event {
    NSPoint loc = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(loc, self.bounds)) {
        if (self.onCardSelected) {
            self.onCardSelected(self);
        }
    }
}

- (void)playClicked:(id)sender {
    if (self.onCardPreview) {
        self.onCardPreview(self);
    }
}

@end

#pragma mark - Settings Window Controller Implementation

@interface SettingsWindowController () <NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate>

// Navigation & Layout
@property (nonatomic, strong) FlippedVisualEffectView *sidebarView;
@property (nonatomic, strong) NSVisualEffectView *detailContainerView;
@property (nonatomic, strong) NSMutableArray<SidebarButton *> *sidebarButtons;
@property (nonatomic, strong) NSTextField *sidebarOdometerLabel;
@property (nonatomic, strong) NSTextField *detailHeaderTitle;
@property (nonatomic, strong) NSScrollView *contentScrollView;
@property (nonatomic, assign) NSInteger currentSectionIndex;

// Section 0: Switches & Studio
@property (nonatomic, strong) FlippedView *switchesSectionView;
@property (nonatomic, strong) NSSlider *volumeSlider;
@property (nonatomic, strong) NSTextField *volumeLabel;
@property (nonatomic, strong) NSPopUpButton *profilePopUp;
@property (nonatomic, strong) NSMutableArray<SwitchCardView *> *switchCardViews;

// Section 1: Acoustics & EQ
@property (nonatomic, strong) FlippedView *acousticsSectionView;
@property (nonatomic, strong) NSSlider *toneSlider;
@property (nonatomic, strong) NSTextField *toneLabel;
@property (nonatomic, strong) NSTextField *toneLowDbLabel;
@property (nonatomic, strong) NSTextField *toneHighDbLabel;
@property (nonatomic, strong) NSButton *typewriterModeCheck;
@property (nonatomic, strong) NSButton *typewriterBellCheck;
@property (nonatomic, strong) NSButton *typewriterRatchetCheck;
@property (nonatomic, strong) NSButton *testBellBtn;
@property (nonatomic, strong) NSButton *testRatchetBtn;
@property (nonatomic, strong) NSButton *velocityDynamicsCheck;
@property (nonatomic, strong) NSButton *secureInputCheck;
@property (nonatomic, strong) NSButton *meetingMuteCheck;
@property (nonatomic, strong) NSButton *spatialAudioCheck;
@property (nonatomic, strong) NSButton *muteModifiersCheck;
@property (nonatomic, strong) NSButton *keyDownCheck;
@property (nonatomic, strong) NSButton *keyUpCheck;
@property (nonatomic, strong) NSButton *mouseClickCheck;
@property (nonatomic, strong) NSButton *mouseScrollCheck;

// Section 2: Haptics & Feedback
@property (nonatomic, strong) FlippedView *hapticsSectionView;
@property (nonatomic, strong) NSButton *hapticEnabledCheck;
@property (nonatomic, strong) NSSegmentedControl *hapticSegmentControl;
@property (nonatomic, strong) NSButton *hapticOnKeyCheck;
@property (nonatomic, strong) NSButton *hapticOnMouseCheck;
@property (nonatomic, strong) NSButton *testHapticBtn;
@property (nonatomic, strong) NSButton *forceClickCheck;

// Section 2: Click Visuals
@property (nonatomic, strong) FlippedView *visualsSectionView;
@property (nonatomic, strong) NSButton *rippleEnabledCheck;
@property (nonatomic, strong) NSPopUpButton *rippleColorPopUp;

// Section 3: Sound Packs Store
@property (nonatomic, strong) FlippedView *storeSectionView;
@property (nonatomic, strong) NSSearchField *packsSearchField;
@property (nonatomic, strong) NSSegmentedControl *packsCategoryControl;
@property (nonatomic, strong) NSTextField *packsCountLabel;
@property (nonatomic, strong) NSTableView *packsTableView;
@property (nonatomic, strong) NSArray<CommunityPackItem *> *displayedPacks;

// Section 4: General & Privacy
@property (nonatomic, strong) FlippedView *generalSectionView;
@property (nonatomic, strong) NSButton *launchAtLoginCheck;
@property (nonatomic, strong) NSButton *autoCheckUpdatesCheck;
@property (nonatomic, strong) NSButton *showInDockCheck;
@property (nonatomic, strong) NSPopUpButton *menuBarDisplayPopUp;
@property (nonatomic, strong) NSButton *contextAwareCheck;
@property (nonatomic, strong) NSTextField *accessibilityStatusLabel;
@property (nonatomic, strong) NSButton *accessibilityFixBtn;

@end

@implementation SettingsWindowController

+ (instancetype)sharedController {
    static SettingsWindowController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SettingsWindowController alloc] init];
    });
    return instance;
}

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskMiniaturizable |
                                                              NSWindowStyleMaskResizable |
                                                              NSWindowStyleMaskFullSizeContentView)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Clackity Settings";
    window.titlebarAppearsTransparent = YES;
    window.titleVisibility = NSWindowTitleHidden;
    window.releasedWhenClosed = NO;
    window.minSize = NSMakeSize(720, 500);
    [window center];
    
    self = [super initWithWindow:window];
    if (self) {
        window.delegate = self;
        [self buildUI];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(soundPacksDidChangeNotification:)
                                                     name:ClackitySoundPacksDidChangeNotification
                                                   object:nil];
    }
    return self;
}

#pragma mark - Main UI Construction

- (void)buildUI {
    NSView *root = self.window.contentView;
    root.wantsLayer = YES;
    
    CGFloat winWidth = 800.0;
    CGFloat winHeight = 600.0;
    CGFloat sidebarWidth = 205.0;
    CGFloat detailWidth = winWidth - sidebarWidth;
    
    // 1. Frosted Sidebar (BehindWindow blending for modern macOS translucency)
    self.sidebarView = [[FlippedVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, sidebarWidth, winHeight)];
    self.sidebarView.material = NSVisualEffectMaterialSidebar;
    self.sidebarView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    self.sidebarView.state = NSVisualEffectStateActive;
    self.sidebarView.autoresizingMask = NSViewHeightSizable | NSViewMaxXMargin;
    [root addSubview:self.sidebarView];
    
    [self buildSidebarContent];
    
    // 2. Subtle 0.5pt vertical divider
    NSBox *divider = [[NSBox alloc] initWithFrame:NSMakeRect(sidebarWidth - 0.5, 0, 0.5, winHeight)];
    divider.boxType = NSBoxCustom;
    divider.borderWidth = 0.5;
    divider.borderColor = [NSColor separatorColor];
    divider.fillColor = [NSColor separatorColor];
    divider.autoresizingMask = NSViewHeightSizable | NSViewMaxXMargin;
    [root addSubview:divider];
    
    // 3. Detail Canvas (Window Background Material)
    self.detailContainerView = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(sidebarWidth, 0, detailWidth, winHeight)];
    self.detailContainerView.material = NSVisualEffectMaterialWindowBackground;
    self.detailContainerView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    self.detailContainerView.state = NSVisualEffectStateActive;
    self.detailContainerView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [root addSubview:self.detailContainerView];
    
    // Detail Header Title (Pinned cleanly at the top, consistent Apple HIG window title)
    self.detailHeaderTitle = [self labelWithText:@"Mechanical Switches" bold:YES fontSize:17];
    self.detailHeaderTitle.frame = NSMakeRect(24, winHeight - 48, detailWidth - 48, 26);
    self.detailHeaderTitle.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [self.detailContainerView addSubview:self.detailHeaderTitle];
    
    // Scrollable Detail Canvas (Fills rest of area cleanly)
    self.contentScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, detailWidth, winHeight - 56)];
    self.contentScrollView.hasVerticalScroller = YES;
    self.contentScrollView.hasHorizontalScroller = NO;
    self.contentScrollView.borderType = NSNoBorder;
    self.contentScrollView.drawsBackground = NO;
    self.contentScrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.detailContainerView addSubview:self.contentScrollView];
    
    // Prebuild Detail Views with Flipped Coordinates
    self.switchesSectionView = [self buildSwitchesView];
    self.acousticsSectionView = [self buildAcousticsView];
    self.hapticsSectionView = [self buildHapticsView];
    self.visualsSectionView = [self buildVisualsView];
    self.storeSectionView = [self buildCommunityPacksView];
    self.generalSectionView = [self buildGeneralView];
    
    [self selectSectionAtIndex:0];
}

#pragma mark - Sidebar

- (void)buildSidebarContent {
    CGFloat w = self.sidebarView.frame.size.width;
    
    // Clean margin at top so macOS window traffic lights (Red, Yellow, Green)
    // have 100% unobstructed breathing room with zero text or icon overlap.
    NSArray *items = @[
        @{@"title": @"Switches", @"symbol": @"headphones"},
        @{@"title": @"Acoustics & EQ", @"symbol": @"slider.vertical.3"},
        @{@"title": @"Haptics", @"symbol": @"hand.tap"},
        @{@"title": @"Click Effects", @"symbol": @"cursorarrow.rays"},
        @{@"title": @"Sound Store", @"symbol": @"shippingbox"},
        @{@"title": @"General", @"symbol": @"gearshape"}
    ];
    
    self.sidebarButtons = [NSMutableArray array];
    CGFloat btnY = 52.0;
    for (NSInteger i = 0; i < items.count; i++) {
        NSDictionary *dict = items[i];
        SidebarButton *btn = [[SidebarButton alloc] initWithFrame:NSMakeRect(12, btnY, w - 24, 34)
                                                            title:dict[@"title"]
                                                     systemSymbol:dict[@"symbol"]];
        btn.target = self;
        btn.action = @selector(sidebarButtonClicked:);
        btn.tag = i;
        
        [self.sidebarView addSubview:btn];
        [self.sidebarButtons addObject:btn];
        btnY += 38.0;
    }
    
    // Bottom Odometer Pill
    FlippedCardView *statsBox = [self cardContainerWithFrame:NSMakeRect(12, 470, w - 24, 52)];
    statsBox.autoresizingMask = NSViewMinYMargin | NSViewWidthSizable;
    [self.sidebarView addSubview:statsBox];
    
    self.sidebarOdometerLabel = [self labelWithText:@"⚡ 0 clacks · 0 wpm" bold:YES fontSize:11];
    self.sidebarOdometerLabel.frame = NSMakeRect(4, 9, w - 32, 16);
    self.sidebarOdometerLabel.alignment = NSTextAlignmentCenter;
    [statsBox addSubview:self.sidebarOdometerLabel];
    
    NSTextField *statsSub = [self labelWithText:@"Flow-State Odometer" bold:NO fontSize:9.5];
    statsSub.textColor = [NSColor secondaryLabelColor];
    statsSub.frame = NSMakeRect(4, 27, w - 32, 14);
    statsSub.alignment = NSTextAlignmentCenter;
    [statsBox addSubview:statsSub];
    
    // Privacy Guarantee Tag
    NSTextField *privTag = [self labelWithText:@"🔒 100% Local · <2.5MB RAM" bold:NO fontSize:10];
    privTag.textColor = [NSColor tertiaryLabelColor];
    privTag.alignment = NSTextAlignmentCenter;
    privTag.frame = NSMakeRect(10, 532, w - 20, 16);
    privTag.autoresizingMask = NSViewMinYMargin | NSViewWidthSizable;
    [self.sidebarView addSubview:privTag];
}

- (void)sidebarButtonClicked:(SidebarButton *)sender {
    [self selectSectionAtIndex:sender.tag];
}

- (void)selectSectionAtIndex:(NSInteger)index {
    self.currentSectionIndex = index;
    
    for (SidebarButton *btn in self.sidebarButtons) {
        [btn setIsCurrent:(btn.tag == index)];
    }
    
    NSView *targetView = nil;
    NSString *title = @"";
    switch (index) {
        case 0:
            targetView = self.switchesSectionView;
            title = @"Mechanical Switches";
            break;
        case 1:
            targetView = self.acousticsSectionView;
            title = @"Acoustics & Equalizer";
            break;
        case 2:
            targetView = self.hapticsSectionView;
            title = @"Trackpad Haptics & Feedback";
            break;
        case 3:
            targetView = self.visualsSectionView;
            title = @"Cursor Effects";
            break;
        case 4:
            targetView = self.storeSectionView;
            title = @"Community Sound Packs";
            break;
        case 5:
            targetView = self.generalSectionView;
            title = @"General Preferences";
            break;
    }
    
    self.detailHeaderTitle.stringValue = title;
    self.contentScrollView.documentView = targetView;
    [self.contentScrollView.contentView scrollPoint:NSMakePoint(0, 0)];
}

- (void)selectTabAtIndex:(NSInteger)index {
    [self selectSectionAtIndex:index];
}

#pragma mark - HIG Card Container Helper

- (FlippedCardView *)cardContainerWithFrame:(NSRect)frame {
    FlippedCardView *card = [[FlippedCardView alloc] initWithFrame:frame];
    card.wantsLayer = YES;
    card.layer.cornerRadius = 12.0;
    card.layer.masksToBounds = YES;
    card.layer.borderWidth = 0.5;
    card.layer.borderColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.12].CGColor;
    card.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.20 alpha:0.28].CGColor;
    card.autoresizingMask = NSViewWidthSizable;
    return card;
}

#pragma mark - Section 0: Switches & Studio

- (FlippedView *)buildSwitchesView {
    self.switchesSectionView = [[FlippedView alloc] initWithFrame:NSMakeRect(0, 0, 535, 600)];
    self.switchCardViews = [NSMutableArray array];
    [self reloadSwitchesList];
    return self.switchesSectionView;
}

- (void)reloadSwitchesList {
    [[SoundPackManager sharedManager] rescanPacks];
    
    // Clear subviews of switchesSectionView
    for (NSView *v in [self.switchesSectionView.subviews copy]) {
        [v removeFromSuperview];
    }
    [self.switchCardViews removeAllObjects];
    
    CGFloat cardWidth = 495.0;
    CGFloat x = 20.0;
    CGFloat currentY = 15.0;
    
    // 1. Master Volume & Preview Card
    FlippedCardView *volCard = [self cardContainerWithFrame:NSMakeRect(x, currentY, cardWidth, 54)];
    [self.switchesSectionView addSubview:volCard];
    
    NSTextField *volTitle = [self labelWithText:@"Master Volume" bold:YES fontSize:13];
    volTitle.frame = NSMakeRect(16, 18, 105, 18);
    [volCard addSubview:volTitle];
    
    self.volumeSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(126, 15, 205, 24)];
    self.volumeSlider.minValue = 0.0;
    self.volumeSlider.maxValue = 1.0;
    self.volumeSlider.continuous = YES;
    self.volumeSlider.target = self;
    self.volumeSlider.action = @selector(volumeSliderChanged:);
    [volCard addSubview:self.volumeSlider];
    
    self.volumeLabel = [self labelWithText:@"85%" bold:YES fontSize:12];
    self.volumeLabel.textColor = [NSColor secondaryLabelColor];
    self.volumeLabel.frame = NSMakeRect(337, 18, 42, 18);
    [volCard addSubview:self.volumeLabel];
    
    NSButton *testBtn = [[NSButton alloc] initWithFrame:NSMakeRect(388, 13, 92, 28)];
    testBtn.title = @"Test Sound";
    testBtn.bezelStyle = NSBezelStyleRounded;
    testBtn.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
    testBtn.target = self;
    testBtn.action = @selector(testSoundClicked:);
    [volCard addSubview:testBtn];
    
    currentY += 68.0;
    
    // 2. Section Header: Studio Recorded Switches (Authentic Hardware Recordings)
    NSArray<CustomSoundPack *> *customPacks = [SoundPackManager sharedManager].customPacks;
    NSTextField *studioTitle = [self labelWithText:@"STUDIO RECORDED SWITCHES" bold:YES fontSize:11];
    studioTitle.textColor = [NSColor secondaryLabelColor];
    studioTitle.frame = NSMakeRect(x + 4, currentY, 350, 16);
    [self.switchesSectionView addSubview:studioTitle];
    
    currentY += 22.0;
    
    __weak typeof(self) weakSelf = self;
    
    if (customPacks.count > 0) {
        CGFloat boxHeight = customPacks.count * 52.0;
        FlippedCardView *studioBox = [self cardContainerWithFrame:NSMakeRect(x, currentY, cardWidth, boxHeight)];
        [self.switchesSectionView addSubview:studioBox];
        
        CGFloat rowY = 0.0;
        for (NSInteger i = 0; i < customPacks.count; i++) {
            CustomSoundPack *pack = customPacks[i];
            
            // Match with community metadata for clean tags and subtitles
            NSString *tagText = @"Studio Pack";
            NSString *subText = @"Authentic acoustic mechanical recording";
            
            for (CommunityPackItem *item in [CommunitySoundPacksManager sharedManager].allPacks) {
                if ([item.name isEqualToString:pack.name] || [item.folderName isEqualToString:pack.name]) {
                    tagText = [NSString stringWithFormat:@"%@ · Studio", item.switchType ?: @"Custom"];
                    if (item.acousticProfile.length > 0) {
                        subText = item.acousticProfile;
                    } else if (item.author.length > 0) {
                        subText = [NSString stringWithFormat:@"Authentic recording by %@", item.author];
                    }
                    break;
                }
            }
            
            SwitchCardView *card = [[SwitchCardView alloc] initWithFrame:NSMakeRect(4, rowY + 1, cardWidth - 8, 50)
                                                                    name:pack.name
                                                                 tagText:tagText
                                                                subtitle:subText
                                                            isCustomPack:YES
                                                                packName:pack.name
                                                            soundProfile:ClackitySoundProfileHolyPanda];
            
            card.onCardSelected = ^(SwitchCardView *c) {
                [weakSelf handleCardSelection:c];
            };
            card.onCardPreview = ^(SwitchCardView *c) {
                [weakSelf handleCardSelection:c];
            };
            
            [studioBox addSubview:card];
            [self.switchCardViews addObject:card];
            
            if (i < customPacks.count - 1) {
                NSBox *line = [[NSBox alloc] initWithFrame:NSMakeRect(14, rowY + 51.5, cardWidth - 28, 0.5)];
                line.boxType = NSBoxCustom;
                line.borderWidth = 0.5;
                line.borderColor = [NSColor separatorColor];
                [studioBox addSubview:line];
            }
            
            rowY += 52.0;
        }
        currentY += boxHeight + 18.0;
    }
    
    // 3. Section Header: Synthesized Switch Profiles
    NSTextField *synthTitle = [self labelWithText:@"SYNTHESIZED SWITCH PROFILES" bold:YES fontSize:11];
    synthTitle.textColor = [NSColor secondaryLabelColor];
    synthTitle.frame = NSMakeRect(x + 4, currentY, 350, 16);
    [self.switchesSectionView addSubview:synthTitle];
    
    currentY += 22.0;
    
    NSArray *synthSwitches = @[
        @{@"name": @"Gateron Oil King", @"tagText": @"Linear · Deep Thock", @"sub": @"Synthesized linear · Deep muted bottom-out for quiet focus", @"profile": @(ClackitySoundProfileGateronOilKing)},
        @{@"name": @"Boba U4T", @"tagText": @"Tactile · D-Bump", @"sub": @"Synthesized tactile · Ultra-tactile actuation with rounded thock", @"profile": @(ClackitySoundProfileBobaU4T)},
        @{@"name": @"IBM Model M", @"tagText": @"Clicky · Buckling Spring", @"sub": @"Synthesized clicky · Heavy mechanical spring buckling snap", @"profile": @(ClackitySoundProfileModelM)},
        @{@"name": @"Alpaca", @"tagText": @"Linear · Smooth Clack", @"sub": @"Synthesized linear · Smooth keystroke with crisp clack", @"profile": @(ClackitySoundProfileAlpaca)},
        @{@"name": @"Apple Extended II", @"tagText": @"Tactile · ALPS Cream", @"sub": @"Synthesized vintage tactile · ALPS damped keycaps", @"profile": @(ClackitySoundProfileAppleALPS)}
    ];
    
    CGFloat synthHeight = synthSwitches.count * 52.0;
    FlippedCardView *synthBox = [self cardContainerWithFrame:NSMakeRect(x, currentY, cardWidth, synthHeight)];
    [self.switchesSectionView addSubview:synthBox];
    
    CGFloat synthRowY = 0.0;
    for (NSInteger i = 0; i < synthSwitches.count; i++) {
        NSDictionary *dict = synthSwitches[i];
        ClackitySoundProfile prof = (ClackitySoundProfile)[dict[@"profile"] integerValue];
        
        SwitchCardView *card = [[SwitchCardView alloc] initWithFrame:NSMakeRect(4, synthRowY + 1, cardWidth - 8, 50)
                                                                name:dict[@"name"]
                                                             tagText:dict[@"tagText"]
                                                            subtitle:dict[@"sub"]
                                                        isCustomPack:NO
                                                            packName:nil
                                                        soundProfile:prof];
        
        card.onCardSelected = ^(SwitchCardView *c) {
            [weakSelf handleCardSelection:c];
        };
        card.onCardPreview = ^(SwitchCardView *c) {
            [weakSelf handleCardSelection:c];
        };
        
        [synthBox addSubview:card];
        [self.switchCardViews addObject:card];
        
        if (i < synthSwitches.count - 1) {
            NSBox *line = [[NSBox alloc] initWithFrame:NSMakeRect(14, synthRowY + 51.5, cardWidth - 28, 0.5)];
            line.boxType = NSBoxCustom;
            line.borderWidth = 0.5;
            line.borderColor = [NSColor separatorColor];
            [synthBox addSubview:line];
        }
        
        synthRowY += 52.0;
    }
    
    currentY += synthHeight + 18.0;
    
    // 4. Quick Switch Selector Dropdown & Folder Access
    NSTextField *quickTitle = [self labelWithText:@"QUICK SWITCH SELECTOR" bold:YES fontSize:11];
    quickTitle.textColor = [NSColor secondaryLabelColor];
    quickTitle.frame = NSMakeRect(x + 4, currentY, 300, 16);
    [self.switchesSectionView addSubview:quickTitle];
    
    currentY += 22.0;
    
    FlippedCardView *packCard = [self cardContainerWithFrame:NSMakeRect(x, currentY, cardWidth, 54)];
    [self.switchesSectionView addSubview:packCard];
    
    self.profilePopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(14, 14, 280, 26) pullsDown:NO];
    self.profilePopUp.target = self;
    self.profilePopUp.action = @selector(profileChanged:);
    [self reloadProfilePopUp];
    [packCard addSubview:self.profilePopUp];
    
    NSButton *openPacksBtn = [[NSButton alloc] initWithFrame:NSMakeRect(304, 13, 175, 28)];
    openPacksBtn.title = @"Open Packs Folder...";
    openPacksBtn.bezelStyle = NSBezelStyleRounded;
    openPacksBtn.target = self;
    openPacksBtn.action = @selector(openPacksDirectoryClicked:);
    [packCard addSubview:openPacksBtn];
    
    currentY += 75.0;
    
    self.switchesSectionView.frame = NSMakeRect(0, 0, 535, currentY);
}

#pragma mark - Section 1: Acoustics & EQ

- (FlippedView *)buildAcousticsView {
    CGFloat totalHeight = 720.0;
    FlippedView *container = [[FlippedView alloc] initWithFrame:NSMakeRect(0, 0, 535, totalHeight)];
    container.autoresizingMask = NSViewWidthSizable;
    CGFloat cardWidth = 495.0;
    CGFloat x = 20.0;
    
    // 1. Hardware Tone Filter EQ Card (Y = 18, height = 145)
    FlippedCardView *eqCard = [self cardContainerWithFrame:NSMakeRect(x, 18, cardWidth, 145)];
    [container addSubview:eqCard];
    
    NSTextField *eqTitle = [self labelWithText:@"Hardware Tone Balance (CoreAudio Parametric EQ)" bold:YES fontSize:13];
    eqTitle.frame = NSMakeRect(16, 14, 400, 18);
    [eqCard addSubview:eqTitle];
    
    self.toneSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(16, 42, 360, 24)];
    self.toneSlider.minValue = -1.0;
    self.toneSlider.maxValue = 1.0;
    self.toneSlider.continuous = YES;
    self.toneSlider.target = self;
    self.toneSlider.action = @selector(toneSliderChanged:);
    self.toneSlider.autoresizingMask = NSViewWidthSizable;
    [eqCard addSubview:self.toneSlider];
    
    self.toneLabel = [self labelWithText:@"Natural" bold:YES fontSize:12];
    self.toneLabel.frame = NSMakeRect(386, 44, 85, 18);
    self.toneLabel.autoresizingMask = NSViewMinXMargin;
    [eqCard addSubview:self.toneLabel];
    
    NSTextField *sliderHint = [self labelWithText:@"◄ PE Foam (Deep Thock)               Balanced               Brass Plate (Crisp Clack) ►" bold:NO fontSize:10];
    sliderHint.textColor = [NSColor secondaryLabelColor];
    sliderHint.frame = NSMakeRect(18, 72, 450, 15);
    sliderHint.autoresizingMask = NSViewWidthSizable;
    [eqCard addSubview:sliderHint];
    
    self.toneLowDbLabel = [self labelWithText:@"Low Shelf (320 Hz): 0.0 dB" bold:NO fontSize:11];
    self.toneLowDbLabel.textColor = [NSColor secondaryLabelColor];
    self.toneLowDbLabel.frame = NSMakeRect(18, 94, 210, 16);
    [eqCard addSubview:self.toneLowDbLabel];
    
    self.toneHighDbLabel = [self labelWithText:@"Actuation Snap (3.8 kHz): 0.0 dB" bold:NO fontSize:11];
    self.toneHighDbLabel.textColor = [NSColor secondaryLabelColor];
    self.toneHighDbLabel.frame = NSMakeRect(240, 94, 220, 16);
    [eqCard addSubview:self.toneHighDbLabel];
    
    NSTextField *eqDesc = [self labelWithText:@"Real-time low-shelf & high-shelf CoreAudio DSP filters acoustic response before output." bold:NO fontSize:10];
    eqDesc.textColor = [NSColor tertiaryLabelColor];
    eqDesc.frame = NSMakeRect(18, 118, 450, 16);
    eqDesc.autoresizingMask = NSViewWidthSizable;
    [eqCard addSubview:eqDesc];
    
    // 2. Vintage Typewriter Carriage Return & Ratchet Card (Y = 181, height = 152)
    FlippedCardView *twCard = [self cardContainerWithFrame:NSMakeRect(x, 181, cardWidth, 152)];
    [container addSubview:twCard];
    
    NSTextField *twTitle = [self labelWithText:@"Vintage Typewriter Carriage Return & Ratchet" bold:YES fontSize:13.5];
    twTitle.frame = NSMakeRect(18, 14, 400, 18);
    [twCard addSubview:twTitle];
    
    NSTextField *twDesc = [self labelWithText:@"Plays authentic brass margin bell chime on Return and mechanical pawl ratchet on Backspace." bold:NO fontSize:11];
    twDesc.textColor = [NSColor secondaryLabelColor];
    twDesc.frame = NSMakeRect(18, 36, 450, 16);
    twDesc.autoresizingMask = NSViewWidthSizable;
    [twCard addSubview:twDesc];
    
    self.typewriterModeCheck = [self checkboxWithTitle:@"Enable Vintage Typewriter Mode (Bell & Ratchet Overlay)" action:@selector(typewriterModeToggled:)];
    self.typewriterModeCheck.frame = NSMakeRect(18, 60, 450, 20);
    self.typewriterModeCheck.autoresizingMask = NSViewWidthSizable;
    [twCard addSubview:self.typewriterModeCheck];
    
    self.typewriterBellCheck = [self checkboxWithTitle:@"Carriage Return Bell Chime (Ding! on Enter)" action:@selector(typewriterBellToggled:)];
    self.typewriterBellCheck.frame = NSMakeRect(38, 86, 300, 20);
    self.typewriterBellCheck.autoresizingMask = NSViewWidthSizable;
    [twCard addSubview:self.typewriterBellCheck];
    
    self.testBellBtn = [[NSButton alloc] initWithFrame:NSMakeRect(cardWidth - 135, 83, 115, 26)];
    self.testBellBtn.title = @"Test Bell 🔔";
    self.testBellBtn.bezelStyle = NSBezelStyleRounded;
    self.testBellBtn.target = self;
    self.testBellBtn.action = @selector(testBellClicked:);
    self.testBellBtn.autoresizingMask = NSViewMinXMargin;
    [twCard addSubview:self.testBellBtn];
    
    self.typewriterRatchetCheck = [self checkboxWithTitle:@"Escapement Pawl Ratchet (on Backspace)" action:@selector(typewriterRatchetToggled:)];
    self.typewriterRatchetCheck.frame = NSMakeRect(38, 114, 300, 20);
    self.typewriterRatchetCheck.autoresizingMask = NSViewWidthSizable;
    [twCard addSubview:self.typewriterRatchetCheck];
    
    self.testRatchetBtn = [[NSButton alloc] initWithFrame:NSMakeRect(cardWidth - 135, 111, 115, 26)];
    self.testRatchetBtn.title = @"Test Ratchet ⚙️";
    self.testRatchetBtn.bezelStyle = NSBezelStyleRounded;
    self.testRatchetBtn.target = self;
    self.testRatchetBtn.action = @selector(testRatchetClicked:);
    self.testRatchetBtn.autoresizingMask = NSViewMinXMargin;
    [twCard addSubview:self.testRatchetBtn];
    
    // 3. Dynamic Strike Velocity & Spatial Audio (Y = 351, height = 115)
    FlippedCardView *dynCard = [self cardContainerWithFrame:NSMakeRect(x, 351, cardWidth, 115)];
    [container addSubview:dynCard];
    
    NSTextField *dynTitle = [self labelWithText:@"Dynamics & Spatial Stereo Acoustics" bold:YES fontSize:13];
    dynTitle.frame = NSMakeRect(16, 14, 350, 18);
    [dynCard addSubview:dynTitle];
    
    self.velocityDynamicsCheck = [self checkboxWithTitle:@"Dynamic Keystroke Velocity (punchier bottom-out on rapid typing bursts)" action:@selector(velocityDynamicsToggled:)];
    self.velocityDynamicsCheck.frame = NSMakeRect(18, 38, 450, 20);
    self.velocityDynamicsCheck.autoresizingMask = NSViewWidthSizable;
    [dynCard addSubview:self.velocityDynamicsCheck];
    
    self.spatialAudioCheck = [self checkboxWithTitle:@"Spatial Stereo Audio (pans keystrokes across headphones by key position)" action:@selector(spatialAudioToggled:)];
    self.spatialAudioCheck.frame = NSMakeRect(18, 62, 450, 20);
    self.spatialAudioCheck.autoresizingMask = NSViewWidthSizable;
    [dynCard addSubview:self.spatialAudioCheck];
    
    self.muteModifiersCheck = [self checkboxWithTitle:@"Mute modifier keys (Shift, Cmd, Opt, Ctrl)" action:@selector(muteModifiersToggled:)];
    self.muteModifiersCheck.frame = NSMakeRect(18, 86, 450, 20);
    self.muteModifiersCheck.autoresizingMask = NSViewWidthSizable;
    [dynCard addSubview:self.muteModifiersCheck];
    
    // 4. Privacy & Meeting Intelligence (Y = 484, height = 85)
    FlippedCardView *privCard = [self cardContainerWithFrame:NSMakeRect(x, 484, cardWidth, 85)];
    [container addSubview:privCard];
    
    NSTextField *privTitle = [self labelWithText:@"Privacy & Trigger Suppression" bold:YES fontSize:13];
    privTitle.frame = NSMakeRect(16, 14, 300, 18);
    [privCard addSubview:privTitle];
    
    self.secureInputCheck = [self checkboxWithTitle:@"Auto-mute in password fields (macOS Secure Event Input)" action:@selector(secureInputToggled:)];
    self.secureInputCheck.frame = NSMakeRect(18, 38, 450, 20);
    self.secureInputCheck.autoresizingMask = NSViewWidthSizable;
    [privCard addSubview:self.secureInputCheck];
    
    self.meetingMuteCheck = [self checkboxWithTitle:@"Auto-mute in meetings (Zoom, Teams, Google Meet, FaceTime...)" action:@selector(meetingMuteToggled:)];
    self.meetingMuteCheck.frame = NSMakeRect(18, 60, 450, 20);
    self.meetingMuteCheck.autoresizingMask = NSViewWidthSizable;
    [privCard addSubview:self.meetingMuteCheck];
    
    // 5. Acoustic Trigger Controls (Y = 587, height = 115)
    FlippedCardView *trigCard = [self cardContainerWithFrame:NSMakeRect(x, 587, cardWidth, 115)];
    [container addSubview:trigCard];
    
    NSTextField *trigTitle = [self labelWithText:@"Detailed Audio Triggers" bold:YES fontSize:13];
    trigTitle.frame = NSMakeRect(16, 14, 300, 18);
    [trigCard addSubview:trigTitle];
    
    self.keyDownCheck = [self checkboxWithTitle:@"Keystroke Down sound" action:@selector(keyDownToggled:)];
    self.keyDownCheck.frame = NSMakeRect(22, 42, 200, 20);
    [trigCard addSubview:self.keyDownCheck];
    
    self.keyUpCheck = [self checkboxWithTitle:@"Keystroke Up sound" action:@selector(keyUpToggled:)];
    self.keyUpCheck.frame = NSMakeRect(240, 42, 200, 20);
    [trigCard addSubview:self.keyUpCheck];
    
    self.mouseClickCheck = [self checkboxWithTitle:@"Mouse click sounds" action:@selector(mouseClickToggled:)];
    self.mouseClickCheck.frame = NSMakeRect(22, 74, 200, 20);
    [trigCard addSubview:self.mouseClickCheck];
    
    self.mouseScrollCheck = [self checkboxWithTitle:@"Mouse scroll clicks" action:@selector(mouseScrollToggled:)];
    self.mouseScrollCheck.frame = NSMakeRect(240, 74, 200, 20);
    [trigCard addSubview:self.mouseScrollCheck];
    
    return container;
}

#pragma mark - Section 2: Trackpad Haptics

- (FlippedView *)buildHapticsView {
    CGFloat totalHeight = 440.0;
    FlippedView *container = [[FlippedView alloc] initWithFrame:NSMakeRect(0, 0, 535, totalHeight)];
    container.autoresizingMask = NSViewWidthSizable;
    CGFloat cardWidth = 495.0;
    CGFloat x = 20.0;
    
    // 1. Force Touch Taptic Engine Kick Card (Y = 18, height = 250)
    FlippedCardView *hapticCard = [self cardContainerWithFrame:NSMakeRect(x, 18, cardWidth, 250)];
    hapticCard.autoresizingMask = NSViewWidthSizable;
    [container addSubview:hapticCard];
    
    NSTextField *hapticTitle = [self labelWithText:@"MacBook Trackpad Haptics (Force Touch Taptic Kick)" bold:YES fontSize:13.5];
    hapticTitle.frame = NSMakeRect(18, 16, 420, 18);
    [hapticCard addSubview:hapticTitle];
    
    NSTextField *hapticDesc = [self labelWithText:@"Delivers microsecond mechanical vibration under your palms as you type or click." bold:NO fontSize:11];
    hapticDesc.textColor = [NSColor secondaryLabelColor];
    hapticDesc.frame = NSMakeRect(18, 38, 450, 16);
    hapticDesc.autoresizingMask = NSViewWidthSizable;
    [hapticCard addSubview:hapticDesc];
    
    self.hapticEnabledCheck = [self checkboxWithTitle:@"Enable Trackpad Haptic Feedback (Mechanical Deck Resonance)" action:@selector(hapticEnabledToggled:)];
    self.hapticEnabledCheck.frame = NSMakeRect(18, 66, 450, 20);
    self.hapticEnabledCheck.autoresizingMask = NSViewWidthSizable;
    [hapticCard addSubview:self.hapticEnabledCheck];
    
    // Tactile Profile Header & Test Button
    NSTextField *hapticIntLabel = [self labelWithText:@"Tactile Feedback Profile:" bold:YES fontSize:11.5];
    hapticIntLabel.frame = NSMakeRect(20, 102, 200, 18);
    [hapticCard addSubview:hapticIntLabel];
    
    self.testHapticBtn = [[NSButton alloc] initWithFrame:NSMakeRect(cardWidth - 130, 97, 110, 26)];
    self.testHapticBtn.title = @"Test Haptic";
    self.testHapticBtn.bezelStyle = NSBezelStyleRounded;
    self.testHapticBtn.target = self;
    self.testHapticBtn.action = @selector(testHapticClicked:);
    self.testHapticBtn.autoresizingMask = NSViewMinXMargin;
    [hapticCard addSubview:self.testHapticBtn];
    
    // Segmented Control on its own dedicated full-width row (Never truncates)
    self.hapticSegmentControl = [NSSegmentedControl segmentedControlWithLabels:@[@"Subtle (Soft)", @"Crisp (Tactile)", @"Heavy (Deep)"]
                                                                 trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                       target:self
                                                                       action:@selector(hapticSegmentChanged:)];
    self.hapticSegmentControl.frame = NSMakeRect(18, 126, cardWidth - 36, 28);
    self.hapticSegmentControl.autoresizingMask = NSViewWidthSizable;
    [hapticCard addSubview:self.hapticSegmentControl];
    
    NSTextField *hapticTip = [self labelWithText:@"💡 Click any profile above to instantly actuate a tactile preview kick under your trackpad." bold:NO fontSize:10.5];
    hapticTip.textColor = [NSColor secondaryLabelColor];
    hapticTip.frame = NSMakeRect(20, 160, cardWidth - 40, 16);
    hapticTip.autoresizingMask = NSViewWidthSizable;
    [hapticCard addSubview:hapticTip];
    
    self.hapticOnKeyCheck = [self checkboxWithTitle:@"Actuate on Keystroke (simulates mechanical plate vibration)" action:@selector(hapticOnKeyToggled:)];
    self.hapticOnKeyCheck.frame = NSMakeRect(18, 188, 450, 20);
    self.hapticOnKeyCheck.autoresizingMask = NSViewWidthSizable;
    [hapticCard addSubview:self.hapticOnKeyCheck];
    
    self.hapticOnMouseCheck = [self checkboxWithTitle:@"Actuate on Mouse Click" action:@selector(hapticOnMouseToggled:)];
    self.hapticOnMouseCheck.frame = NSMakeRect(18, 214, 450, 20);
    self.hapticOnMouseCheck.autoresizingMask = NSViewWidthSizable;
    [hapticCard addSubview:self.hapticOnMouseCheck];
    
    // 2. Trackpad Force-Click Snap (Y = 286, height = 120)
    FlippedCardView *forceCard = [self cardContainerWithFrame:NSMakeRect(x, 286, cardWidth, 120)];
    forceCard.autoresizingMask = NSViewWidthSizable;
    [container addSubview:forceCard];
    
    NSTextField *forceTitle = [self labelWithText:@"Trackpad Force-Click Snap" bold:YES fontSize:13.5];
    forceTitle.frame = NSMakeRect(18, 16, 300, 18);
    [forceCard addSubview:forceTitle];
    
    NSTextField *forceDesc = [self labelWithText:@"Provides tactile acoustic pop and feedback when deep-pressing the Force Touch trackpad." bold:NO fontSize:11];
    forceDesc.textColor = [NSColor secondaryLabelColor];
    forceDesc.frame = NSMakeRect(18, 38, 450, 16);
    forceDesc.autoresizingMask = NSViewWidthSizable;
    [forceCard addSubview:forceDesc];
    
    self.forceClickCheck = [self checkboxWithTitle:@"Force-Click Acoustic Snap (deep press audio feedback)" action:@selector(forceClickToggled:)];
    self.forceClickCheck.frame = NSMakeRect(18, 66, 450, 20);
    self.forceClickCheck.autoresizingMask = NSViewWidthSizable;
    [forceCard addSubview:self.forceClickCheck];
    
    BOOL hasForceTouch = [HapticEngine isForceTouchHardwareAvailable];
    NSTextField *hwBadge = [self labelWithText:hasForceTouch ? @"✅ Apple Force Touch Hardware: Active & Ready" : @"ℹ️ No Force Touch hardware detected on this display" bold:NO fontSize:11];
    hwBadge.textColor = hasForceTouch ? [NSColor systemGreenColor] : [NSColor secondaryLabelColor];
    hwBadge.frame = NSMakeRect(20, 92, 430, 16);
    hwBadge.autoresizingMask = NSViewWidthSizable;
    [forceCard addSubview:hwBadge];
    
    container.frame = NSMakeRect(0, 0, 535, 430);
    return container;
}

#pragma mark - Section 2: Click Visuals

- (FlippedView *)buildVisualsView {
    FlippedView *container = [[FlippedView alloc] initWithFrame:NSMakeRect(0, 0, 535, 450)];
    CGFloat cardWidth = 495.0;
    CGFloat x = 20.0;
    
    FlippedCardView *card = [self cardContainerWithFrame:NSMakeRect(x, 15, cardWidth, 165)];
    [container addSubview:card];
    
    NSTextField *fxTitle = [self labelWithText:@"GPU-Accelerated Click Shockwave" bold:YES fontSize:13];
    fxTitle.frame = NSMakeRect(16, 14, 300, 18);
    [card addSubview:fxTitle];
    
    self.rippleEnabledCheck = [self checkboxWithTitle:@"Enable circular ripple effect on mouse click" action:@selector(rippleEnabledToggled:)];
    self.rippleEnabledCheck.frame = NSMakeRect(18, 40, 420, 20);
    [card addSubview:self.rippleEnabledCheck];
    
    NSTextField *fxDesc = [self labelWithText:@"Renders a smooth hardware-accelerated shockwave under your cursor on every click." bold:NO fontSize:11];
    fxDesc.textColor = [NSColor secondaryLabelColor];
    fxDesc.frame = NSMakeRect(20, 66, 440, 18);
    [card addSubview:fxDesc];
    
    NSTextField *colorTitle = [self labelWithText:@"Accent Color Theme:" bold:YES fontSize:12];
    colorTitle.frame = NSMakeRect(20, 94, 150, 18);
    [card addSubview:colorTitle];
    
    self.rippleColorPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(18, 118, 250, 26) pullsDown:NO];
    [self.rippleColorPopUp addItemsWithTitles:@[
        @"⚡  Electric Cyan (Default)",
        @"⚪  Minimal White",
        @"🍯  Warm Amber (Analog)",
        @"🌸  Rose Pink",
        @"🌿  Emerald Green"
    ]];
    self.rippleColorPopUp.target = self;
    self.rippleColorPopUp.action = @selector(rippleColorChanged:);
    [card addSubview:self.rippleColorPopUp];
    
    NSButton *testRippleBtn = [[NSButton alloc] initWithFrame:NSMakeRect(285, 117, 145, 28)];
    testRippleBtn.title = @"Preview Ripple";
    testRippleBtn.bezelStyle = NSBezelStyleRounded;
    testRippleBtn.target = self;
    testRippleBtn.action = @selector(testRippleClicked:);
    [card addSubview:testRippleBtn];
    
    return container;
}

#pragma mark - Section 3: Sound Packs Store

- (FlippedView *)buildCommunityPacksView {
    FlippedView *view = [[FlippedView alloc] initWithFrame:NSMakeRect(0, 0, 535, 520)];
    
    // Top Search Bar (Y = 12)
    self.packsSearchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(20, 12, 275, 28)];
    self.packsSearchField.placeholderString = @"Search switch name, type, profile...";
    self.packsSearchField.target = self;
    self.packsSearchField.action = @selector(packsFilterChanged:);
    [view addSubview:self.packsSearchField];
    
    // Category Filter Chips
    self.packsCategoryControl = [NSSegmentedControl segmentedControlWithLabels:@[@"All", @"Tactile", @"Linear", @"Clicky"]
                                                                  trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                        target:self
                                                                        action:@selector(packsFilterChanged:)];
    self.packsCategoryControl.selectedSegment = 0;
    self.packsCategoryControl.frame = NSMakeRect(305, 13, 205, 26);
    [view addSubview:self.packsCategoryControl];
    
    // Count Label
    self.packsCountLabel = [self labelWithText:@"" bold:NO fontSize:11];
    self.packsCountLabel.textColor = [NSColor secondaryLabelColor];
    self.packsCountLabel.frame = NSMakeRect(22, 44, 480, 16);
    [view addSubview:self.packsCountLabel];
    
    // ScrollView & TableView (Y = 66, height = 385)
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 66, 495, 385)];
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.borderType = NSBezelBorder;
    scrollView.drawsBackground = NO;
    
    self.packsTableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
    self.packsTableView.delegate = self;
    self.packsTableView.dataSource = self;
    self.packsTableView.rowHeight = 68.0;
    self.packsTableView.headerView = nil;
    self.packsTableView.intercellSpacing = NSMakeSize(0, 4);
    self.packsTableView.backgroundColor = [NSColor clearColor];
    
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"SoundPackColumn"];
    column.width = 490.0;
    [self.packsTableView addTableColumn:column];
    
    scrollView.documentView = self.packsTableView;
    [view addSubview:scrollView];
    
    // Bottom Controls (Y = 462)
    NSButton *openFolderBtn = [[NSButton alloc] initWithFrame:NSMakeRect(20, 462, 190, 28)];
    openFolderBtn.title = @"📁 Open Packs Folder...";
    openFolderBtn.bezelStyle = NSBezelStyleRounded;
    openFolderBtn.target = self;
    openFolderBtn.action = @selector(openPacksDirectoryClicked:);
    [view addSubview:openFolderBtn];
    
    NSButton *refreshBtn = [[NSButton alloc] initWithFrame:NSMakeRect(345, 462, 170, 28)];
    refreshBtn.title = @"↻ Refresh Catalog";
    refreshBtn.bezelStyle = NSBezelStyleRounded;
    refreshBtn.target = self;
    refreshBtn.action = @selector(refreshCommunityPacksClicked:);
    [view addSubview:refreshBtn];
    
    [self filterAndReloadPacksTable];
    return view;
}

#pragma mark - Section 4: General & Privacy

- (FlippedView *)buildGeneralView {
    FlippedView *container = [[FlippedView alloc] initWithFrame:NSMakeRect(0, 0, 535, 590)];
    CGFloat cardWidth = 495.0;
    CGFloat x = 20.0;
    
    // 1. Startup & System (Y = 15, height = 135)
    FlippedCardView *sysCard = [self cardContainerWithFrame:NSMakeRect(x, 15, cardWidth, 135)];
    [container addSubview:sysCard];
    
    NSTextField *sysTitle = [self labelWithText:@"Startup & Window Visibility" bold:YES fontSize:13];
    sysTitle.frame = NSMakeRect(16, 14, 300, 18);
    [sysCard addSubview:sysTitle];
    
    self.launchAtLoginCheck = [self checkboxWithTitle:@"Launch Clackity automatically at login" action:@selector(launchAtLoginToggled:)];
    self.launchAtLoginCheck.frame = NSMakeRect(18, 38, 400, 20);
    [sysCard addSubview:self.launchAtLoginCheck];
    
    self.showInDockCheck = [self checkboxWithTitle:@"Keep icon in macOS Dock (visible even if Menu Bar is full)" action:@selector(showInDockToggled:)];
    self.showInDockCheck.frame = NSMakeRect(18, 66, 440, 20);
    [sysCard addSubview:self.showInDockCheck];
    
    self.autoCheckUpdatesCheck = [self checkboxWithTitle:@"Automatically check for updates in background" action:@selector(autoCheckUpdatesToggled:)];
    self.autoCheckUpdatesCheck.frame = NSMakeRect(18, 94, 300, 20);
    [sysCard addSubview:self.autoCheckUpdatesCheck];
    
    NSButton *checkUpdatesBtn = [[NSButton alloc] initWithFrame:NSMakeRect(340, 90, 135, 26)];
    checkUpdatesBtn.title = @"Check Now";
    checkUpdatesBtn.bezelStyle = NSBezelStyleRounded;
    checkUpdatesBtn.target = self;
    checkUpdatesBtn.action = @selector(checkUpdatesClicked:);
    [sysCard addSubview:checkUpdatesBtn];
    
    // 2. Menu Bar Display & Profiles (Y = 162, height = 125)
    FlippedCardView *statsCard = [self cardContainerWithFrame:NSMakeRect(x, 162, cardWidth, 125)];
    [container addSubview:statsCard];
    
    NSTextField *statsTitle = [self labelWithText:@"Live Typing Odometer & Context Profiles" bold:YES fontSize:13];
    statsTitle.frame = NSMakeRect(16, 14, 350, 18);
    [statsCard addSubview:statsTitle];
    
    NSTextField *displayLabel = [self labelWithText:@"Menu Bar Item:" bold:NO fontSize:12];
    displayLabel.frame = NSMakeRect(20, 42, 95, 20);
    [statsCard addSubview:displayLabel];
    
    self.menuBarDisplayPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(118, 38, 220, 26) pullsDown:NO];
    [self.menuBarDisplayPopUp addItemsWithTitles:@[
        @"Icon Only",
        @"Icon + Session Clacks",
        @"Icon + Live Speed (WPM)"
    ]];
    self.menuBarDisplayPopUp.target = self;
    self.menuBarDisplayPopUp.action = @selector(menuBarDisplayChanged:);
    [statsCard addSubview:self.menuBarDisplayPopUp];
    
    NSButton *resetStatsBtn = [[NSButton alloc] initWithFrame:NSMakeRect(348, 37, 125, 26)];
    resetStatsBtn.title = @"Reset Clacks";
    resetStatsBtn.bezelStyle = NSBezelStyleRounded;
    resetStatsBtn.target = self;
    resetStatsBtn.action = @selector(resetStatsClicked:);
    [statsCard addSubview:resetStatsBtn];
    
    self.contextAwareCheck = [self checkboxWithTitle:@"Context-Aware Profiles (Auto-switch for IDEs, Writing, Chat)" action:@selector(contextAwareToggled:)];
    self.contextAwareCheck.frame = NSMakeRect(18, 78, 440, 20);
    [statsCard addSubview:self.contextAwareCheck];
    
    // 3. Accessibility Status (Y = 299, height = 75)
    FlippedCardView *permCard = [self cardContainerWithFrame:NSMakeRect(x, 299, cardWidth, 75)];
    [container addSubview:permCard];
    
    NSTextField *permTitle = [self labelWithText:@"macOS Accessibility Permission" bold:YES fontSize:13];
    permTitle.frame = NSMakeRect(16, 14, 300, 18);
    [permCard addSubview:permTitle];
    
    self.accessibilityStatusLabel = [self labelWithText:@"Checking..." bold:NO fontSize:12];
    self.accessibilityStatusLabel.frame = NSMakeRect(20, 38, 280, 20);
    [permCard addSubview:self.accessibilityStatusLabel];
    
    self.accessibilityFixBtn = [[NSButton alloc] initWithFrame:NSMakeRect(310, 34, 165, 26)];
    self.accessibilityFixBtn.title = @"Open System Settings";
    self.accessibilityFixBtn.bezelStyle = NSBezelStyleRounded;
    self.accessibilityFixBtn.target = self;
    self.accessibilityFixBtn.action = @selector(fixAccessibilityClicked:);
    [permCard addSubview:self.accessibilityFixBtn];
    
    // 4. Hotkeys & Privacy (Y = 386, height = 155)
    FlippedCardView *aboutCard = [self cardContainerWithFrame:NSMakeRect(x, 386, cardWidth, 155)];
    [container addSubview:aboutCard];
    
    NSTextField *hotTitle = [self labelWithText:@"Keyboard Shortcuts & Local Guarantee" bold:YES fontSize:13];
    hotTitle.frame = NSMakeRect(16, 14, 300, 18);
    [aboutCard addSubview:hotTitle];
    
    NSTextField *hk1 = [self labelWithText:@"• Toggle Mute Audio:  ⌘ ⇧ \\  (Cmd + Shift + Backslash)" bold:NO fontSize:11.5];
    hk1.frame = NSMakeRect(20, 36, 400, 16);
    [aboutCard addSubview:hk1];
    
    NSTextField *hk2 = [self labelWithText:@"• Open Settings:  ⌘ ,  (Cmd + Comma)" bold:NO fontSize:11.5];
    hk2.frame = NSMakeRect(20, 56, 400, 16);
    [aboutCard addSubview:hk2];
    
    NSTextField *privText = [self labelWithText:@"🔒 100% Native Cocoa & CoreAudio. Zero telemetry, zero web bloat, <2.5MB RAM footprint." bold:NO fontSize:11];
    privText.textColor = [NSColor secondaryLabelColor];
    privText.frame = NSMakeRect(20, 80, 450, 28);
    [aboutCard addSubview:privText];
    
    NSButton *ghBtn = [[NSButton alloc] initWithFrame:NSMakeRect(18, 114, 130, 26)];
    ghBtn.title = @"View on GitHub";
    ghBtn.bezelStyle = NSBezelStyleRounded;
    ghBtn.target = self;
    ghBtn.action = @selector(githubClicked:);
    [aboutCard addSubview:ghBtn];
    
    NSButton *contribBtn = [[NSButton alloc] initWithFrame:NSMakeRect(156, 114, 125, 26)];
    contribBtn.title = @"💖 Contribute";
    contribBtn.bezelStyle = NSBezelStyleRounded;
    contribBtn.target = self;
    contribBtn.action = @selector(contributeClicked:);
    [aboutCard addSubview:contribBtn];
    
    return container;
}

#pragma mark - UI State Synchronization

- (void)syncUIFromState {
    AudioEngine *audio = [AudioEngine sharedEngine];
    RippleOverlay *ripple = [RippleOverlay sharedOverlay];
    AppDelegate *delegate = (AppDelegate *)[NSApp delegate];
    
    [self reloadProfilePopUp];
    
    // Highlight active switch card
    for (SwitchCardView *card in self.switchCardViews) {
        if (audio.customPack) {
            [card setSelected:(card.isCustomPack && [card.packName isEqualToString:audio.customPack.name])];
        } else {
            [card setSelected:(!card.isCustomPack && card.soundProfile == audio.currentProfile)];
        }
    }
    
    // Select item in quick dropdown pop-up
    if (audio.customPack) {
        for (NSMenuItem *item in self.profilePopUp.itemArray) {
            if ([item.representedObject isKindOfClass:[CustomSoundPack class]]) {
                CustomSoundPack *p = (CustomSoundPack *)item.representedObject;
                if ([p.name isEqualToString:audio.customPack.name]) {
                    [self.profilePopUp selectItem:item];
                    break;
                }
            }
        }
    } else {
        for (NSMenuItem *item in self.profilePopUp.itemArray) {
            if (!item.representedObject && item.tag == audio.currentProfile) {
                [self.profilePopUp selectItem:item];
                break;
            }
        }
    }
    
    // Volume & Tone
    self.volumeSlider.floatValue = audio.masterVolume;
    self.volumeLabel.stringValue = [NSString stringWithFormat:@"%d%%", (int)roundf(audio.masterVolume * 100)];
    
    self.toneSlider.floatValue = audio.toneBalance;
    [self updateToneLabelsForValue:audio.toneBalance];
    
    // Audio toggles
    self.keyDownCheck.state = audio.keySoundsEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.keyUpCheck.state = audio.keyUpSoundsEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.mouseClickCheck.state = audio.mouseSoundsEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.mouseScrollCheck.state = audio.scrollSoundsEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    // Dynamics & Haptics
    self.velocityDynamicsCheck.state = audio.velocityDynamicsEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.forceClickCheck.state = audio.forceClickSoundEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    
    // Vintage Typewriter
    self.typewriterModeCheck.state = audio.typewriterModeEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.typewriterBellCheck.state = audio.typewriterBellEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.typewriterRatchetCheck.state = audio.typewriterRatchetEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [self updateTypewriterControlsState];
    
    HapticEngine *haptic = [HapticEngine sharedEngine];
    self.hapticEnabledCheck.state = haptic.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    
    NSInteger segIdx = 1;
    if (haptic.intensity == ClackityHapticIntensitySubtle) segIdx = 0;
    else if (haptic.intensity == ClackityHapticIntensityHeavy) segIdx = 2;
    self.hapticSegmentControl.selectedSegment = segIdx;
    
    self.hapticOnKeyCheck.state = haptic.hapticOnKeyPress ? NSControlStateValueOn : NSControlStateValueOff;
    self.hapticOnMouseCheck.state = haptic.hapticOnMouseClick ? NSControlStateValueOn : NSControlStateValueOff;
    [self updateHapticControlsState];
    self.secureInputCheck.state = [InputMonitor sharedMonitor].secureInputProtectionEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.muteModifiersCheck.state = audio.muteModifiers ? NSControlStateValueOn : NSControlStateValueOff;
    self.spatialAudioCheck.state = audio.spatialAudioEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.meetingMuteCheck.state = delegate.autoMuteInMeetingsEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    
    // Visuals
    self.rippleEnabledCheck.state = ripple.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    [self.rippleColorPopUp selectItemAtIndex:ripple.colorTheme];
    
    // General
    self.launchAtLoginCheck.state = ([SMAppService mainAppService].status == SMAppServiceStatusEnabled) ? NSControlStateValueOn : NSControlStateValueOff;
    self.autoCheckUpdatesCheck.state = [UpdateManager sharedManager].autoCheckEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.showInDockCheck.state = [[NSUserDefaults standardUserDefaults] boolForKey:@"showInDock"] ? NSControlStateValueOn : NSControlStateValueOff;
    [self.menuBarDisplayPopUp selectItemAtIndex:delegate.menuBarDisplayStyle];
    self.contextAwareCheck.state = delegate.contextAwareProfilesEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    
    // Accessibility
    BOOL hasAccess = [InputMonitor isAccessibilityGranted];
    if (hasAccess) {
        self.accessibilityStatusLabel.stringValue = @"✅ Accessibility: Granted (Active)";
        self.accessibilityStatusLabel.textColor = [NSColor systemGreenColor];
        self.accessibilityFixBtn.hidden = YES;
    } else {
        self.accessibilityStatusLabel.stringValue = @"⚠️ Accessibility: Not Granted (Blocked)";
        self.accessibilityStatusLabel.textColor = [NSColor systemOrangeColor];
        self.accessibilityFixBtn.hidden = NO;
    }
    
    // Live Sidebar Odometer
    NSUInteger count = delegate.sessionClackCount;
    NSString *cntStr = (count >= 1000) ? [NSString stringWithFormat:@"%.1fk", count / 1000.0] : [NSString stringWithFormat:@"%lu", (unsigned long)count];
    self.sidebarOdometerLabel.stringValue = [NSString stringWithFormat:@"⚡ %@ clacks · %lu wpm", cntStr, (unsigned long)delegate.currentWPM];
}

- (void)updateToneLabelsForValue:(float)val {
    if (val < -0.2f) {
        self.toneLabel.stringValue = [NSString stringWithFormat:@"Thock (%.0f%%)", fabs(val) * 100];
        self.toneLowDbLabel.stringValue = [NSString stringWithFormat:@"Low Shelf (320 Hz): +%.1f dB", fabs(val) * 8.0f];
        self.toneHighDbLabel.stringValue = [NSString stringWithFormat:@"Actuation Snap (3.8 kHz): -%.1f dB", fabs(val) * 6.0f];
    } else if (val > 0.2f) {
        self.toneLabel.stringValue = [NSString stringWithFormat:@"Clack (+%.0f%%)", val * 100];
        self.toneLowDbLabel.stringValue = [NSString stringWithFormat:@"Low Shelf (320 Hz): -%.1f dB", val * 3.0f];
        self.toneHighDbLabel.stringValue = [NSString stringWithFormat:@"Actuation Snap (3.8 kHz): +%.1f dB", val * 7.5f];
    } else {
        self.toneLabel.stringValue = @"Natural";
        self.toneLowDbLabel.stringValue = @"Low Shelf (320 Hz): 0.0 dB";
        self.toneHighDbLabel.stringValue = @"Actuation Snap (3.8 kHz): 0.0 dB";
    }
}

- (void)showSettingsWindow:(nullable id)sender {
    BOOL keepInDock = [[NSUserDefaults standardUserDefaults] boolForKey:@"showInDock"];
    if (keepInDock) {
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    } else {
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    }
    [self reloadSwitchesList];
    [self syncUIFromState];
    [self.window center];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window orderFrontRegardless];
    [self.window makeKeyAndOrderFront:nil];
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    return YES;
}

- (void)windowWillClose:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
}

#pragma mark - Actions

- (void)handleCardSelection:(SwitchCardView *)card {
    AudioEngine *audio = [AudioEngine sharedEngine];
    if (card.isCustomPack) {
        for (CustomSoundPack *pack in [SoundPackManager sharedManager].customPacks) {
            if ([pack.name isEqualToString:card.packName]) {
                audio.customPack = pack;
                audio.currentProfile = ClackitySoundProfileHolyPanda;
                [[NSUserDefaults standardUserDefaults] setObject:pack.name forKey:@"selectedCustomPack"];
                break;
            }
        }
    } else {
        audio.customPack = nil;
        audio.currentProfile = card.soundProfile;
        [[NSUserDefaults standardUserDefaults] setInteger:card.soundProfile forKey:@"selectedProfile"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"selectedCustomPack"];
    }
    
    [self syncUIFromState];
    [[MenuBarController sharedController] updateStatusItem];
    [audio playKeyWithCategory:ClackityKeyCategoryEnter isKeyUp:NO];
}

- (void)handleSwitchSelection:(NSInteger)tag {
    AudioEngine *audio = [AudioEngine sharedEngine];
    
    if (tag == 100 || tag == 101 || tag == 102) {
        NSString *match = (tag == 100) ? @"Holy Panda" : (tag == 101 ? @"NovelKeys Cream" : @"Tealios");
        for (CustomSoundPack *pack in [SoundPackManager sharedManager].customPacks) {
            if ([pack.name containsString:match]) {
                audio.customPack = pack;
                [[NSUserDefaults standardUserDefaults] setObject:pack.name forKey:@"selectedCustomPack"];
                break;
            }
        }
    } else {
        audio.customPack = nil;
        audio.currentProfile = (ClackitySoundProfile)tag;
        [[NSUserDefaults standardUserDefaults] setInteger:tag forKey:@"selectedProfile"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"selectedCustomPack"];
    }
    
    [self syncUIFromState];
    [[MenuBarController sharedController] updateStatusItem];
    [audio playKeyWithCategory:ClackityKeyCategoryEnter isKeyUp:NO];
}

- (void)reloadProfilePopUp {
    [self.profilePopUp removeAllItems];
    
    NSArray<CustomSoundPack *> *customPacks = [SoundPackManager sharedManager].customPacks;
    if (customPacks.count > 0) {
        NSMenuItem *custHeader = [[NSMenuItem alloc] initWithTitle:@"-- STUDIO MECHANICAL SWITCH RECORDINGS --" action:nil keyEquivalent:@""];
        custHeader.enabled = NO;
        [self.profilePopUp.menu addItem:custHeader];
        
        for (CustomSoundPack *pack in customPacks) {
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"🎙️ %@", pack.name] action:nil keyEquivalent:@""];
            item.representedObject = pack;
            [self.profilePopUp.menu addItem:item];
        }
        [self.profilePopUp.menu addItem:[NSMenuItem separatorItem]];
    }
    
    NSArray *profileGroups = @[
        @{@"header": @"-- SYNTHESIZED LINEAR --", @"items": @[
            @(ClackitySoundProfileGateronOilKing),
            @(ClackitySoundProfileAlpaca),
            @(ClackitySoundProfileNKCream),
            @(ClackitySoundProfileCherryMXBlack)
        ]},
        @{@"header": @"-- SYNTHESIZED TACTILE --", @"items": @[
            @(ClackitySoundProfileBobaU4T),
            @(ClackitySoundProfileHolyPanda),
            @(ClackitySoundProfileAppleALPS)
        ]},
        @{@"header": @"-- CLICKY & SPRING --", @"items": @[
            @(ClackitySoundProfileKailhBoxWhite),
            @(ClackitySoundProfileModelM)
        ]}
    ];
    
    for (NSDictionary *group in profileGroups) {
        NSMenuItem *header = [[NSMenuItem alloc] initWithTitle:group[@"header"] action:nil keyEquivalent:@""];
        header.enabled = NO;
        [self.profilePopUp.menu addItem:header];
        
        for (NSNumber *profNum in group[@"items"]) {
            ClackitySoundProfile p = [profNum integerValue];
            NSString *name = [SoundSynthesizer nameForProfile:p];
            NSString *sub = [SoundSynthesizer subtitleForProfile:p];
            NSString *title = [NSString stringWithFormat:@"%@ (%@)", name, sub];
            
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
            item.tag = p;
            [self.profilePopUp.menu addItem:item];
        }
    }
}

- (void)profileChanged:(NSPopUpButton *)sender {
    NSMenuItem *selected = sender.selectedItem;
    if (!selected) return;
    
    AudioEngine *audio = [AudioEngine sharedEngine];
    if (selected.representedObject && [selected.representedObject isKindOfClass:[CustomSoundPack class]]) {
        CustomSoundPack *pack = (CustomSoundPack *)selected.representedObject;
        audio.customPack = pack;
        [[NSUserDefaults standardUserDefaults] setObject:pack.name forKey:@"selectedCustomPack"];
    } else {
        audio.customPack = nil;
        audio.currentProfile = (ClackitySoundProfile)selected.tag;
        [[NSUserDefaults standardUserDefaults] setInteger:selected.tag forKey:@"selectedProfile"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"selectedCustomPack"];
    }
    
    [self syncUIFromState];
    [[MenuBarController sharedController] updateStatusItem];
    [audio playKeyWithCategory:ClackityKeyCategoryEnter isKeyUp:NO];
}

- (void)testSoundClicked:(id)sender {
    [[AudioEngine sharedEngine] playKeyWithCategory:ClackityKeyCategoryEnter isKeyUp:NO];
}

- (void)volumeSliderChanged:(NSSlider *)sender {
    float vol = sender.floatValue;
    [AudioEngine sharedEngine].masterVolume = vol;
    self.volumeLabel.stringValue = [NSString stringWithFormat:@"%d%%", (int)roundf(vol * 100)];
    [[NSUserDefaults standardUserDefaults] setFloat:vol forKey:@"masterVolume"];
    [[MenuBarController sharedController] updateStatusItem];
}

- (void)toneSliderChanged:(NSSlider *)sender {
    float val = sender.floatValue;
    [AudioEngine sharedEngine].toneBalance = val;
    [self updateToneLabelsForValue:val];
    [[NSUserDefaults standardUserDefaults] setFloat:val forKey:@"toneBalance"];
}

- (void)updateTypewriterControlsState {
    BOOL on = [AudioEngine sharedEngine].typewriterModeEnabled;
    self.typewriterBellCheck.enabled = on;
    self.typewriterRatchetCheck.enabled = on;
    self.testBellBtn.enabled = on;
    self.testRatchetBtn.enabled = on;
}

- (void)typewriterModeToggled:(NSButton *)sender {
    BOOL on = (sender.state == NSControlStateValueOn);
    [AudioEngine sharedEngine].typewriterModeEnabled = on;
    [self updateTypewriterControlsState];
    if (on) {
        [[AudioEngine sharedEngine] playTypewriterBell];
    }
}

- (void)typewriterBellToggled:(NSButton *)sender {
    BOOL on = (sender.state == NSControlStateValueOn);
    [AudioEngine sharedEngine].typewriterBellEnabled = on;
    if (on) {
        [[AudioEngine sharedEngine] playTypewriterBell];
    }
}

- (void)typewriterRatchetToggled:(NSButton *)sender {
    BOOL on = (sender.state == NSControlStateValueOn);
    [AudioEngine sharedEngine].typewriterRatchetEnabled = on;
    if (on) {
        [[AudioEngine sharedEngine] playTypewriterRatchet];
    }
}

- (void)testBellClicked:(NSButton *)sender {
    [[AudioEngine sharedEngine] playTypewriterBell];
}

- (void)testRatchetClicked:(NSButton *)sender {
    [[AudioEngine sharedEngine] playTypewriterRatchet];
}

- (void)updateHapticControlsState {
    BOOL on = [HapticEngine sharedEngine].enabled;
    self.hapticSegmentControl.enabled = on;
    self.hapticOnKeyCheck.enabled = on;
    self.hapticOnMouseCheck.enabled = on;
    self.testHapticBtn.enabled = on;
}

- (void)hapticEnabledToggled:(NSButton *)sender {
    BOOL on = (sender.state == NSControlStateValueOn);
    [HapticEngine sharedEngine].enabled = on;
    [self updateHapticControlsState];
    if (on) {
        [[HapticEngine sharedEngine] triggerKeyHaptic];
    }
}

- (void)hapticSegmentChanged:(NSSegmentedControl *)sender {
    ClackityHapticIntensity intensity = ClackityHapticIntensityCrisp;
    if (sender.selectedSegment == 0) {
        intensity = ClackityHapticIntensitySubtle;
    } else if (sender.selectedSegment == 2) {
        intensity = ClackityHapticIntensityHeavy;
    }
    [HapticEngine sharedEngine].intensity = intensity;
    [[HapticEngine sharedEngine] triggerKeyHaptic];
}

- (void)hapticOnKeyToggled:(NSButton *)sender {
    [HapticEngine sharedEngine].hapticOnKeyPress = (sender.state == NSControlStateValueOn);
}

- (void)hapticOnMouseToggled:(NSButton *)sender {
    [HapticEngine sharedEngine].hapticOnMouseClick = (sender.state == NSControlStateValueOn);
}

- (void)testHapticClicked:(NSButton *)sender {
    [[HapticEngine sharedEngine] triggerKeyHaptic];
}

- (void)velocityDynamicsToggled:(NSButton *)sender {
    BOOL on = (sender.state == NSControlStateValueOn);
    [AudioEngine sharedEngine].velocityDynamicsEnabled = on;
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"velocityDynamics"];
}

- (void)forceClickToggled:(NSButton *)sender {
    BOOL on = (sender.state == NSControlStateValueOn);
    [AudioEngine sharedEngine].forceClickSoundEnabled = on;
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"forceClickSound"];
}

- (void)secureInputToggled:(NSButton *)sender {
    BOOL on = (sender.state == NSControlStateValueOn);
    [InputMonitor sharedMonitor].secureInputProtectionEnabled = on;
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"secureInputProtection"];
}

- (void)keyDownToggled:(NSButton *)sender {
    BOOL on = (sender.state == NSControlStateValueOn);
    [AudioEngine sharedEngine].keySoundsEnabled = on;
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"keySoundsEnabled"];
    [[MenuBarController sharedController] updateStatusItem];
}

- (void)keyUpToggled:(NSButton *)sender {
    BOOL on = (sender.state == NSControlStateValueOn);
    [AudioEngine sharedEngine].keyUpSoundsEnabled = on;
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"keyUpSoundsEnabled"];
    [[MenuBarController sharedController] updateStatusItem];
}

- (void)mouseClickToggled:(NSButton *)sender {
    BOOL on = (sender.state == NSControlStateValueOn);
    [AudioEngine sharedEngine].mouseSoundsEnabled = on;
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"mouseSoundsEnabled"];
    [[MenuBarController sharedController] updateStatusItem];
}

- (void)mouseScrollToggled:(NSButton *)sender {
    BOOL on = (sender.state == NSControlStateValueOn);
    [AudioEngine sharedEngine].scrollSoundsEnabled = on;
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"scrollSoundsEnabled"];
    [[MenuBarController sharedController] updateStatusItem];
}

- (void)muteModifiersToggled:(NSButton *)sender {
    BOOL on = (sender.state == NSControlStateValueOn);
    [AudioEngine sharedEngine].muteModifiers = on;
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"muteModifiers"];
    [[MenuBarController sharedController] updateStatusItem];
}

- (void)spatialAudioToggled:(NSButton *)sender {
    BOOL on = (sender.state == NSControlStateValueOn);
    [AudioEngine sharedEngine].spatialAudioEnabled = on;
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"spatialAudioEnabled"];
    [[MenuBarController sharedController] updateStatusItem];
}

- (void)meetingMuteToggled:(NSButton *)sender {
    BOOL on = (sender.state == NSControlStateValueOn);
    AppDelegate *del = (AppDelegate *)[NSApp delegate];
    del.autoMuteInMeetingsEnabled = on;
    if (!on) {
        [AudioEngine sharedEngine].isMeetingMuted = NO;
    }
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"autoMuteInMeetings"];
    [[MenuBarController sharedController] updateStatusItem];
}

- (void)contextAwareToggled:(NSButton *)sender {
    BOOL on = (sender.state == NSControlStateValueOn);
    AppDelegate *del = (AppDelegate *)[NSApp delegate];
    del.contextAwareProfilesEnabled = on;
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"contextAwareProfiles"];
}

- (void)menuBarDisplayChanged:(NSPopUpButton *)sender {
    NSInteger idx = sender.indexOfSelectedItem;
    AppDelegate *del = (AppDelegate *)[NSApp delegate];
    del.menuBarDisplayStyle = idx;
    [[NSUserDefaults standardUserDefaults] setInteger:idx forKey:@"menuBarDisplayStyle"];
    [[MenuBarController sharedController] updateStatusItem];
}

- (void)resetStatsClicked:(id)sender {
    AppDelegate *del = (AppDelegate *)[NSApp delegate];
    [del resetSessionStats];
    [self syncUIFromState];
}

- (void)openPacksDirectoryClicked:(id)sender {
    NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString *packsDir = [appSupport stringByAppendingPathComponent:@"Clackity/SoundPacks"];
    [[NSFileManager defaultManager] createDirectoryAtPath:packsDir withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:packsDir]];
}

- (void)rippleEnabledToggled:(NSButton *)sender {
    BOOL on = (sender.state == NSControlStateValueOn);
    [RippleOverlay sharedOverlay].enabled = on;
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"rippleEnabled"];
    [[MenuBarController sharedController] updateStatusItem];
}

- (void)rippleColorChanged:(NSPopUpButton *)sender {
    NSInteger idx = sender.indexOfSelectedItem;
    [RippleOverlay sharedOverlay].colorTheme = (ClackityRippleColor)idx;
    [[NSUserDefaults standardUserDefaults] setInteger:idx forKey:@"rippleColorTheme"];
    [[MenuBarController sharedController] updateStatusItem];
}

- (void)testRippleClicked:(id)sender {
    NSRect winFrame = self.window.frame;
    CGPoint pt = CGPointMake(NSMidX(winFrame), NSMidY(winFrame));
    [[RippleOverlay sharedOverlay] showRippleAtScreenPoint:pt isRightClick:NO];
}

- (void)launchAtLoginToggled:(NSButton *)sender {
    SMAppService *service = [SMAppService mainAppService];
    NSError *error = nil;
    if (sender.state == NSControlStateValueOn) {
        [service registerAndReturnError:&error];
    } else {
        [service unregisterAndReturnError:&error];
    }
    [[MenuBarController sharedController] updateStatusItem];
}

- (void)showInDockToggled:(NSButton *)sender {
    BOOL on = (sender.state == NSControlStateValueOn);
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"showInDock"];
    if (on) {
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    } else {
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    }
}

- (void)autoCheckUpdatesToggled:(NSButton *)sender {
    BOOL on = (sender.state == NSControlStateValueOn);
    [UpdateManager sharedManager].autoCheckEnabled = on;
    [[MenuBarController sharedController] updateStatusItem];
}

- (void)checkUpdatesClicked:(NSButton *)sender {
    if ([sender respondsToSelector:@selector(setEnabled:)]) {
        sender.enabled = NO;
        sender.title = @"Checking...";
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            sender.enabled = YES;
            sender.title = @"Check Now";
        });
    }
    [[UpdateManager sharedManager] checkForUpdatesUserInitiated:YES];
}

- (void)fixAccessibilityClicked:(id)sender {
    [InputMonitor openAccessibilitySettings];
}

- (void)githubClicked:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/jojoyboy/Clackityclack"]];
}

- (void)contributeClicked:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://razorpay.me/@jojoyboy"]];
}

#pragma mark - Community Sound Packs Store

- (void)soundPacksDidChangeNotification:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reloadSwitchesList];
        [self filterAndReloadPacksTable];
        [self reloadProfilePopUp];
        [self syncUIFromState];
    });
}

- (void)filterAndReloadPacksTable {
    CommunitySoundPacksManager *manager = [CommunitySoundPacksManager sharedManager];
    NSString *search = self.packsSearchField.stringValue ?: @"";
    NSInteger catIdx = self.packsCategoryControl.selectedSegment;
    
    NSString *cat = nil;
    if (catIdx == 1) cat = @"Tactile";
    else if (catIdx == 2) cat = @"Linear";
    else if (catIdx == 3) cat = @"Clicky";
    
    self.displayedPacks = [manager filteredPacksWithQuery:search categoryType:cat];
    self.packsCountLabel.stringValue = [NSString stringWithFormat:@"Showing %lu community switch packs", (unsigned long)self.displayedPacks.count];
    [self.packsTableView reloadData];
}

- (void)packsFilterChanged:(id)sender {
    [self filterAndReloadPacksTable];
}

- (void)refreshCommunityPacksClicked:(id)sender {
    [[CommunitySoundPacksManager sharedManager] loadCatalog];
    [self filterAndReloadPacksTable];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.displayedPacks.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (row < 0 || row >= self.displayedPacks.count) return nil;
    CommunityPackItem *item = self.displayedPacks[row];
    
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"SoundPackCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 68)];
        cell.identifier = @"SoundPackCell";
    }
    
    for (NSView *sub in [cell.subviews copy]) [sub removeFromSuperview];
    
    FlippedCardView *card = [self cardContainerWithFrame:NSMakeRect(0, 2, tableColumn.width, 64)];
    [cell addSubview:card];
    
    NSTextField *icon = [self labelWithText:@"🎙️" bold:NO fontSize:20];
    icon.frame = NSMakeRect(12, 18, 30, 26);
    [card addSubview:icon];
    
    NSTextField *title = [self labelWithText:item.name bold:YES fontSize:13];
    title.frame = NSMakeRect(48, 12, 220, 18);
    [card addSubview:title];
    
    NSString *swType = item.switchType ?: @"Custom";
    NSTextField *catLabel = [self labelWithText:[swType uppercaseString] bold:YES fontSize:9.5];
    catLabel.textColor = [swType isEqualToString:@"Linear"] ? [NSColor systemCyanColor] : ([swType isEqualToString:@"Tactile"] ? [NSColor systemOrangeColor] : [NSColor systemBlueColor]);
    catLabel.frame = NSMakeRect(48, 34, 80, 16);
    [card addSubview:catLabel];
    
    NSTextField *author = [self labelWithText:[NSString stringWithFormat:@"by %@", item.author ?: @"Community"] bold:NO fontSize:11];
    author.textColor = [NSColor secondaryLabelColor];
    author.frame = NSMakeRect(135, 34, 140, 16);
    [card addSubview:author];
    
    NSButton *previewBtn = [[NSButton alloc] initWithFrame:NSMakeRect(tableColumn.width - 170, 18, 75, 28)];
    previewBtn.title = @"▶ Preview";
    previewBtn.bezelStyle = NSBezelStyleRounded;
    previewBtn.tag = row;
    previewBtn.target = self;
    previewBtn.action = @selector(previewPackClicked:);
    [card addSubview:previewBtn];
    
    NSButton *actionBtn = [[NSButton alloc] initWithFrame:NSMakeRect(tableColumn.width - 90, 18, 78, 28)];
    actionBtn.tag = row;
    actionBtn.target = self;
    actionBtn.bezelStyle = NSBezelStyleRounded;
    
    if (item.isInstalled) {
        actionBtn.title = @"Installed";
        actionBtn.enabled = NO;
    } else {
        actionBtn.title = @"Install";
        actionBtn.action = @selector(installPackClicked:);
        actionBtn.keyEquivalent = @"\r";
    }
    [card addSubview:actionBtn];
    
    return cell;
}

- (void)previewPackClicked:(NSButton *)sender {
    if (sender.tag < 0 || sender.tag >= self.displayedPacks.count) return;
    CommunityPackItem *item = self.displayedPacks[sender.tag];
    [[CommunitySoundPacksManager sharedManager] playPreviewForPack:item completion:nil];
}

- (void)installPackClicked:(NSButton *)sender {
    if (sender.tag < 0 || sender.tag >= self.displayedPacks.count) return;
    CommunityPackItem *item = self.displayedPacks[sender.tag];
    sender.enabled = NO;
    sender.title = @"...";
    
    [[CommunitySoundPacksManager sharedManager] downloadAndInstallPack:item progress:nil completion:^(BOOL success, NSString * _Nullable errorMsg) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                sender.title = @"Installed";
                sender.enabled = NO;
                [[SoundPackManager sharedManager] rescanPacks];
            } else {
                sender.title = @"Retry";
                sender.enabled = YES;
            }
        });
    }];
}

#pragma mark - UI Helpers

- (NSTextField *)labelWithText:(NSString *)text bold:(BOOL)bold fontSize:(CGFloat)size {
    NSTextField *label = [[NSTextField alloc] init];
    label.stringValue = text;
    label.editable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.font = bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];
    return label;
}

- (NSButton *)checkboxWithTitle:(NSString *)title action:(SEL)action {
    NSButton *check = [NSButton checkboxWithTitle:title target:self action:action];
    return check;
}

@end
