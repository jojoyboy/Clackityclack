#import "MenuBarController.h"
#import "AudioEngine.h"
#import "InputMonitor.h"
#import "RippleOverlay.h"
#import "SoundPackManager.h"
#import "AppDelegate.h"
#import "UpdateManager.h"
#import "SettingsWindowController.h"
#import "CommunitySoundPacks.h"
#import <ServiceManagement/ServiceManagement.h>

@interface MenuBarController () {
    NSStatusItem *_statusItem;
    NSMenu *_menu;
}
@end

@implementation MenuBarController

+ (instancetype)sharedController {
    static MenuBarController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MenuBarController alloc] init];
    });
    return instance;
}

- (NSImage *)statusItemIcon {
    NSImage *icon = [NSImage imageNamed:@"MenuBarIcon"];
    if (!icon) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"MenuBarIcon" ofType:@"png"];
        if (path) {
            icon = [[NSImage alloc] initWithContentsOfFile:path];
        }
    }
    if (!icon) {
        icon = [self createKeycapIcon];
    }
    icon.size = NSMakeSize(18.0, 18.0);
    icon.template = YES;
    return icon;
}

- (void)setupStatusItem {
    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    
    NSImage *icon = [self statusItemIcon];
    _statusItem.button.image = icon;
    _statusItem.button.imagePosition = NSImageOnly;
    _statusItem.button.toolTip = @"Clackity - Keyboard Acoustics";
    
    _menu = [[NSMenu alloc] initWithTitle:@"Clackity"];
    _menu.delegate = self;
    _statusItem.menu = _menu;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(rebuildMenu)
                                                 name:ClackitySoundPacksDidChangeNotification
                                               object:nil];
    
    [self rebuildMenu];
}

- (NSImage *)createKeycapIcon {
    // Pixel-perfect vector rendering for all display resolutions (Retina, 4K, 5K) & dynamic dark/light mode
    NSSize size = NSMakeSize(18.0, 18.0);
    NSImage *image = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        // Outer keycap border (beveled trapezoid / rounded rect)
        NSRect outerRect = NSMakeRect(1.5, 2.0, 15.0, 14.0);
        NSBezierPath *outerPath = [NSBezierPath bezierPathWithRoundedRect:outerRect xRadius:3.0 yRadius:3.0];
        outerPath.lineWidth = 1.4;
        [[NSColor blackColor] setStroke];
        [outerPath stroke];
        
        // Inner keycap top face
        NSRect topFace = NSMakeRect(4.0, 5.0, 10.0, 8.5);
        NSBezierPath *innerPath = [NSBezierPath bezierPathWithRoundedRect:topFace xRadius:1.5 yRadius:1.5];
        innerPath.lineWidth = 1.0;
        [innerPath stroke];
        
        // Center mechanical cross stem (+)
        NSRect ch = NSMakeRect(7.0, 8.5, 4.0, 1.3);
        NSRect cv = NSMakeRect(8.35, 7.15, 1.3, 4.0);
        [[NSColor blackColor] setFill];
        NSRectFill(ch);
        NSRectFill(cv);
        
        return YES;
    }];
    [image setTemplate:YES]; // Seamless macOS Dark Mode and Light Mode automatic tinting
    return image;
}

- (void)menuWillOpen:(NSMenu *)menu {
    if ([InputMonitor isAccessibilityGranted] && ![InputMonitor sharedMonitor].isRunning) {
        [[InputMonitor sharedMonitor] restart];
    }
    [[SoundPackManager sharedManager] rescanPacks];
    [self rebuildMenu];
}

- (void)rebuildMenu {
    [_menu removeAllItems];
    
    AudioEngine *audio = [AudioEngine sharedEngine];
    BOOL hasAccess = [InputMonitor isAccessibilityGranted];
    UpdateManager *updater = [UpdateManager sharedManager];
    
    // 1. App Header: Title & Version
    NSString *appVersion = [UpdateManager currentAppVersion];
    NSMenuItem *titleItem = [[NSMenuItem alloc] initWithTitle:@"Clackity" action:nil keyEquivalent:@""];
    titleItem.attributedTitle = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"Clackity  v%@", appVersion]
                                                                attributes:@{NSFontAttributeName: [NSFont boldSystemFontOfSize:13]}];
    [_menu addItem:titleItem];
    
    // 2. Status / Meeting / Gaming Mode Indicator
    if (hasAccess) {
        if (audio.isGamingMuted) {
            NSMenuItem *gameNotice = [[NSMenuItem alloc] initWithTitle:@"🎮 Gaming Mode Active (Silenced)" action:nil keyEquivalent:@""];
            gameNotice.attributedTitle = [[NSAttributedString alloc] initWithString:@"🎮 Gaming Mode Active (Silenced)"
                                                                         attributes:@{
                NSForegroundColorAttributeName: [NSColor systemPurpleColor],
                NSFontAttributeName: [NSFont boldSystemFontOfSize:11]
            }];
            [_menu addItem:gameNotice];
        } else if (audio.isMeetingMuted) {
            NSMenuItem *muteNotice = [[NSMenuItem alloc] initWithTitle:@"🔇 Muted (Meeting in Foreground)" action:nil keyEquivalent:@""];
            muteNotice.attributedTitle = [[NSAttributedString alloc] initWithString:@"🔇 Muted (Meeting Active)"
                                                                         attributes:@{
                NSForegroundColorAttributeName: [NSColor systemOrangeColor],
                NSFontAttributeName: [NSFont boldSystemFontOfSize:11]
            }];
            [_menu addItem:muteNotice];
        } else if (audio.masterVolume <= 0.001f) {
            NSMenuItem *muteNotice = [[NSMenuItem alloc] initWithTitle:@"🔇 Typing Sounds Muted" action:nil keyEquivalent:@""];
            muteNotice.attributedTitle = [[NSAttributedString alloc] initWithString:@"🔇 Audio Muted"
                                                                         attributes:@{
                NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
                NSFontAttributeName: [NSFont systemFontOfSize:11]
            }];
            [_menu addItem:muteNotice];
        } else {
            NSMenuItem *status = [[NSMenuItem alloc] initWithTitle:@"● Ready & Listening" action:nil keyEquivalent:@""];
            status.attributedTitle = [[NSAttributedString alloc] initWithString:@"● Ready & Listening"
                                                                     attributes:@{NSForegroundColorAttributeName: [NSColor systemGreenColor],
                                                                                  NSFontAttributeName: [NSFont systemFontOfSize:11]}];
            [_menu addItem:status];
        }
    } else {
        NSMenuItem *warning = [[NSMenuItem alloc] initWithTitle:@"⚠️ Grant Accessibility Permission..."
                                                         action:@selector(openAccessibilitySettings:)
                                                  keyEquivalent:@""];
        warning.target = self;
        warning.attributedTitle = [[NSAttributedString alloc] initWithString:@"⚠️ Enable Accessibility (Click Here)"
                                                                  attributes:@{NSForegroundColorAttributeName: [NSColor systemOrangeColor],
                                                                               NSFontAttributeName: [NSFont boldSystemFontOfSize:12]}];
        [_menu addItem:warning];
    }
    
    // Update banner if new release detected
    if (updater.latestRelease && updater.latestRelease.isNewerVersion) {
        NSMenuItem *updateBanner = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"✨ Update Available (v%@)...", updater.latestRelease.version]
                                                              action:@selector(installAvailableUpdate:)
                                                       keyEquivalent:@""];
        updateBanner.target = self;
        updateBanner.attributedTitle = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"✨ Update to v%@...", updater.latestRelease.version]
                                                                       attributes:@{
            NSForegroundColorAttributeName: [NSColor systemBlueColor],
            NSFontAttributeName: [NSFont boldSystemFontOfSize:12]
        }];
        [_menu addItem:updateBanner];
    }
    
    [_menu addItem:[NSMenuItem separatorItem]];
    
    // 3. Quick Switch Profiles Submenu
    NSString *currentProfileName = audio.customPack ? [NSString stringWithFormat:@"📁 %@", audio.customPack.name] : [SoundSynthesizer nameForProfile:audio.currentProfile];
    NSMenuItem *profileSubmenuItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Switch: %@", currentProfileName] action:nil keyEquivalent:@""];
    NSMenu *profileMenu = [[NSMenu alloc] initWithTitle:@"Switch Profiles"];
    
    // 1. Studio Mechanical Switch Recordings (Top Priority Authentic Hardware)
    NSArray<CustomSoundPack *> *customPacks = [SoundPackManager sharedManager].customPacks;
    if (customPacks.count > 0) {
        NSMenuItem *customHeader = [[NSMenuItem alloc] initWithTitle:@"STUDIO MECHANICAL SWITCHES (AUTHENTIC)" action:nil keyEquivalent:@""];
        customHeader.enabled = NO;
        customHeader.attributedTitle = [[NSAttributedString alloc] initWithString:@"STUDIO MECHANICAL SWITCHES (AUTHENTIC)"
                                                                     attributes:@{
            NSFontAttributeName: [NSFont boldSystemFontOfSize:10],
            NSForegroundColorAttributeName: [NSColor systemBlueColor]
        }];
        [profileMenu addItem:customHeader];
        
        for (CustomSoundPack *pack in customPacks) {
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"🎙️ %@", pack.name]
                                                          action:@selector(selectCustomPack:)
                                                   keyEquivalent:@""];
            item.target = self;
            item.representedObject = pack;
            item.state = (audio.customPack == pack) ? NSControlStateValueOn : NSControlStateValueOff;
            [profileMenu addItem:item];
        }
        [profileMenu addItem:[NSMenuItem separatorItem]];
    }
    
    NSArray *profileGroups = @[
        @{@"header": @"SYNTHESIZED LINEAR", @"items": @[
            @(ClackitySoundProfileGateronOilKing),
            @(ClackitySoundProfileAlpaca),
            @(ClackitySoundProfileNKCream),
            @(ClackitySoundProfileCherryMXBlack)
        ]},
        @{@"header": @"SYNTHESIZED TACTILE", @"items": @[
            @(ClackitySoundProfileBobaU4T),
            @(ClackitySoundProfileHolyPanda),
            @(ClackitySoundProfileAppleALPS)
        ]},
        @{@"header": @"CLICKY & SPRING", @"items": @[
            @(ClackitySoundProfileKailhBoxWhite),
            @(ClackitySoundProfileModelM)
        ]},
        @{@"header": @"ELECTRO-CAPACITIVE", @"items": @[
            @(ClackitySoundProfileTopre)
        ]},
        @{@"header": @"RETRO & NOVELTY", @"items": @[
            @(ClackitySoundProfileTypewriter),
            @(ClackitySoundProfilePop)
        ]}
    ];
    
    for (NSDictionary *group in profileGroups) {
        NSMenuItem *headerItem = [[NSMenuItem alloc] initWithTitle:group[@"header"] action:nil keyEquivalent:@""];
        headerItem.enabled = NO;
        headerItem.attributedTitle = [[NSAttributedString alloc] initWithString:group[@"header"]
                                                                     attributes:@{
            NSFontAttributeName: [NSFont boldSystemFontOfSize:10],
            NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
        }];
        [profileMenu addItem:headerItem];
        
        for (NSNumber *num in group[@"items"]) {
            ClackitySoundProfile prof = (ClackitySoundProfile)[num integerValue];
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[SoundSynthesizer nameForProfile:prof]
                                                          action:@selector(selectProfile:)
                                                   keyEquivalent:@""];
            item.target = self;
            item.tag = prof;
            item.toolTip = [SoundSynthesizer subtitleForProfile:prof];
            item.state = (audio.customPack == nil && audio.currentProfile == prof) ? NSControlStateValueOn : NSControlStateValueOff;
            [profileMenu addItem:item];
        }
    }
    
    [profileMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *downloadPacksItem = [[NSMenuItem alloc] initWithTitle:@"⬇️  Download Sound Packs..." action:@selector(openSoundPacksStore:) keyEquivalent:@""];
    downloadPacksItem.target = self;
    [profileMenu addItem:downloadPacksItem];
    
    profileSubmenuItem.submenu = profileMenu;
    [_menu addItem:profileSubmenuItem];
    
    // 4. Quick Volume Submenu
    int volPercent = (int)roundf(audio.masterVolume * 100);
    NSMenuItem *volSubmenuItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Volume: %d%%", volPercent] action:nil keyEquivalent:@""];
    NSMenu *volMenu = [[NSMenu alloc] initWithTitle:@"Volume"];
    NSArray *volumeSteps = @[
        @{@"title": @"100% (Full)", @"vol": @(1.0f)},
        @{@"title": @"85% (Default)", @"vol": @(0.85f)},
        @{@"title": @"70% (Balanced)", @"vol": @(0.70f)},
        @{@"title": @"50% (Subtle)", @"vol": @(0.50f)},
        @{@"title": @"25% (Quiet)", @"vol": @(0.25f)},
        @{@"title": @"Mute (0%)", @"vol": @(0.0f)}
    ];
    for (NSDictionary *dict in volumeSteps) {
        float val = [dict[@"vol"] floatValue];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:dict[@"title"]
                                                      action:@selector(selectVolume:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = dict[@"vol"];
        BOOL isMatch = fabs(audio.masterVolume - val) < 0.05f;
        item.state = isMatch ? NSControlStateValueOn : NSControlStateValueOff;
        [volMenu addItem:item];
    }
    volSubmenuItem.submenu = volMenu;
    [_menu addItem:volSubmenuItem];
    
    // 5. Quick Mute Audio & Gaming Mode Toggles
    NSMenuItem *muteItem = [[NSMenuItem alloc] initWithTitle:@"Mute Audio (⌘⇧\\)"
                                                      action:@selector(toggleMuteAudio:)
                                               keyEquivalent:@""];
    muteItem.target = self;
    muteItem.state = (audio.masterVolume <= 0.001f || audio.isMeetingMuted || audio.isGamingMuted) ? NSControlStateValueOn : NSControlStateValueOff;
    [_menu addItem:muteItem];
    
    AppDelegate *delegate = (AppDelegate *)[NSApp delegate];
    NSMenuItem *gamingItem = [[NSMenuItem alloc] initWithTitle:@"🎮 Gaming Mode (Mute All)"
                                                        action:@selector(toggleGamingMode:)
                                                 keyEquivalent:@"g"];
    gamingItem.target = self;
    gamingItem.state = delegate.manualGamingModeEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [_menu addItem:gamingItem];
    
    [_menu addItem:[NSMenuItem separatorItem]];
    
    // 5.5 Download Sound Packs...
    NSMenuItem *downloadMenuItem = [[NSMenuItem alloc] initWithTitle:@"Download Sound Packs..."
                                                              action:@selector(openSoundPacksStore:)
                                                       keyEquivalent:@"d"];
    downloadMenuItem.target = self;
    [_menu addItem:downloadMenuItem];
    
    // 6. Settings... (Cmd + Comma)
    NSMenuItem *settingsItem = [[NSMenuItem alloc] initWithTitle:@"Settings..."
                                                          action:@selector(openSettings:)
                                                   keyEquivalent:@","];
    settingsItem.target = self;
    [_menu addItem:settingsItem];
    
    [_menu addItem:[NSMenuItem separatorItem]];
    
    // 7. Quit Clackity
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit Clackity"
                                                      action:@selector(quitApp:)
                                               keyEquivalent:@"q"];
    quitItem.target = self;
    [_menu addItem:quitItem];
}

#pragma mark - Actions

- (void)selectProfile:(NSMenuItem *)sender {
    AudioEngine *audio = [AudioEngine sharedEngine];
    audio.customPack = nil;
    audio.currentProfile = (ClackitySoundProfile)sender.tag;
    [[NSUserDefaults standardUserDefaults] setInteger:sender.tag forKey:@"selectedProfile"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"selectedCustomPack"];
    [self rebuildMenu];
    
    // Play a preview clack of the chosen profile
    [audio playKeyWithCategory:ClackityKeyCategoryEnter isKeyUp:NO];
}

- (void)selectCustomPack:(NSMenuItem *)sender {
    CustomSoundPack *pack = sender.representedObject;
    AudioEngine *audio = [AudioEngine sharedEngine];
    audio.customPack = pack;
    [[NSUserDefaults standardUserDefaults] setObject:pack.name forKey:@"selectedCustomPack"];
    [self rebuildMenu];
    
    [audio playKeyWithCategory:ClackityKeyCategoryEnter isKeyUp:NO];
}

- (void)selectVolume:(NSMenuItem *)sender {
    float vol = [sender.representedObject floatValue];
    AudioEngine *audio = [AudioEngine sharedEngine];
    audio.masterVolume = vol;
    [[NSUserDefaults standardUserDefaults] setFloat:vol forKey:@"masterVolume"];
    [self rebuildMenu];
    
    [audio playKeyWithCategory:ClackityKeyCategoryStandard isKeyUp:NO];
}

- (void)toggleMuteAudio:(id)sender {
    [[AudioEngine sharedEngine] toggleMute];
    [self rebuildMenu];
}

- (void)toggleGamingMode:(id)sender {
    AppDelegate *del = (AppDelegate *)[NSApp delegate];
    del.manualGamingModeEnabled = !del.manualGamingModeEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:del.manualGamingModeEnabled forKey:@"manualGamingMode"];
    [del refreshGamingModeForApp:nil];
    [self rebuildMenu];
}

- (void)openSettings:(id)sender {
    [[SettingsWindowController sharedController] showSettingsWindow:nil];
}

- (void)openSoundPacksStore:(id)sender {
    SettingsWindowController *settings = [SettingsWindowController sharedController];
    [settings showSettingsWindow:sender];
    [settings selectTabAtIndex:1];
}

- (void)openAccessibilitySettings:(id)sender {
    [InputMonitor openAccessibilitySettings];
}

- (void)installAvailableUpdate:(id)sender {
    UpdateManager *updater = [UpdateManager sharedManager];
    if (updater.latestRelease) {
        [updater showUpdatePromptForRelease:updater.latestRelease];
    } else {
        [updater checkForUpdatesUserInitiated:YES];
    }
}

- (void)quitApp:(id)sender {
    [NSApp terminate:nil];
}

- (void)updateStatusItemTitle {
    dispatch_async(dispatch_get_main_queue(), ^{
        AppDelegate *delegate = (AppDelegate *)[NSApp delegate];
        self->_statusItem.button.image = [self statusItemIcon];
        if (delegate.menuBarDisplayStyle == 1) {
            NSUInteger count = delegate.sessionClackCount;
            NSString *countStr;
            if (count >= 1000) countStr = [NSString stringWithFormat:@"%.1fk", count / 1000.0];
            else countStr = [NSString stringWithFormat:@"%lu", (unsigned long)count];
            
            self->_statusItem.button.title = [NSString stringWithFormat:@" %@", countStr];
            self->_statusItem.button.imagePosition = NSImageLeft;
        } else if (delegate.menuBarDisplayStyle == 2) {
            self->_statusItem.button.title = [NSString stringWithFormat:@" %lu wpm", (unsigned long)delegate.currentWPM];
            self->_statusItem.button.imagePosition = NSImageLeft;
        } else {
            self->_statusItem.button.title = @"";
            self->_statusItem.button.imagePosition = NSImageOnly;
        }
    });
}

- (void)updateStatusItem {
    [self updateStatusItemTitle];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self rebuildMenu];
    });
}

@end
