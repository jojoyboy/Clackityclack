#import "AppDelegate.h"
#import "AudioEngine.h"
#import "InputMonitor.h"
#import "RippleOverlay.h"
#import "MenuBarController.h"
#import "UpdateManager.h"
#import "SettingsWindowController.h"
#import "HapticEngine.h"
#import <mach/mach_time.h>

@interface AppDelegate () {
    NSMutableArray<NSNumber *> *_keystrokeTimestamps;
    NSTimer *_wpmDecayTimer;
}
@property (nonatomic, assign) NSUInteger sessionClackCount;
@property (nonatomic, assign) NSUInteger currentWPM;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    _keystrokeTimestamps = [NSMutableArray array];
    
    // Disable automatic termination since Clackity is a standing menu bar utility
    [[NSProcessInfo processInfo] disableAutomaticTermination:@"Clackity runs continuously in the menu bar"];
    
    // Hide dock icon, run cleanly as menu bar accessory
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    
    // Load persisted settings
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    [defs registerDefaults:@{
        @"selectedProfile": @(ClackitySoundProfileGateronOilKing),
        @"masterVolume": @(0.85f),
        @"keySoundsEnabled": @YES,
        @"keyUpSoundsEnabled": @YES,
        @"mouseSoundsEnabled": @YES,
        @"scrollSoundsEnabled": @YES,
        @"muteModifiers": @NO,
        @"spatialAudioEnabled": @YES,
        @"autoMuteInMeetings": @YES,
        @"rippleEnabled": @YES,
        @"rippleColorTheme": @(ClackityRippleColorElectricCyan),
        @"secureInputProtection": @YES,
        @"toneBalance": @(0.0f),
        @"velocityDynamics": @YES,
        @"forceClickSound": @YES,
        @"contextAwareProfiles": @NO,
        @"menuBarDisplayStyle": @(0),
        @"showInDock": @NO
    }];
    
    BOOL showInDock = [defs boolForKey:@"showInDock"];
    if (!showInDock) {
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    }
    
    AudioEngine *audio = [AudioEngine sharedEngine];
    audio.currentProfile = (ClackitySoundProfile)[defs integerForKey:@"selectedProfile"];
    
    NSString *customPackName = [defs stringForKey:@"selectedCustomPack"];
    if (customPackName) {
        for (CustomSoundPack *pack in [SoundPackManager sharedManager].customPacks) {
            if ([pack.name isEqualToString:customPackName]) {
                audio.customPack = pack;
                break;
            }
        }
    }
    
    // If not found or stale preference, default to authentic Holy Panda studio pack
    if (!audio.customPack && [SoundPackManager sharedManager].customPacks.count > 0) {
        for (CustomSoundPack *pack in [SoundPackManager sharedManager].customPacks) {
            if ([pack.name containsString:@"Holy Panda"] || [pack.name containsString:@"NovelKeys Cream"]) {
                audio.customPack = pack;
                [defs setObject:pack.name forKey:@"selectedCustomPack"];
                break;
            }
        }
        if (!audio.customPack) {
            audio.customPack = [SoundPackManager sharedManager].customPacks.firstObject;
            [defs setObject:audio.customPack.name forKey:@"selectedCustomPack"];
        }
    }
    
    audio.masterVolume = [defs floatForKey:@"masterVolume"];
    audio.keySoundsEnabled = [defs boolForKey:@"keySoundsEnabled"];
    audio.keyUpSoundsEnabled = [defs boolForKey:@"keyUpSoundsEnabled"];
    audio.mouseSoundsEnabled = [defs boolForKey:@"mouseSoundsEnabled"];
    audio.scrollSoundsEnabled = [defs boolForKey:@"scrollSoundsEnabled"];
    audio.muteModifiers = [defs boolForKey:@"muteModifiers"];
    audio.spatialAudioEnabled = [defs boolForKey:@"spatialAudioEnabled"];
    audio.toneBalance = [defs floatForKey:@"toneBalance"];
    audio.velocityDynamicsEnabled = [defs boolForKey:@"velocityDynamics"];
    audio.forceClickSoundEnabled = [defs boolForKey:@"forceClickSound"];
    
    self.autoMuteInMeetingsEnabled = [defs boolForKey:@"autoMuteInMeetings"];
    self.contextAwareProfilesEnabled = [defs boolForKey:@"contextAwareProfiles"];
    self.menuBarDisplayStyle = [defs integerForKey:@"menuBarDisplayStyle"];
    
    RippleOverlay *ripple = [RippleOverlay sharedOverlay];
    ripple.enabled = [defs boolForKey:@"rippleEnabled"];
    ripple.colorTheme = (ClackityRippleColor)[defs integerForKey:@"rippleColorTheme"];
    
    // Setup and start input monitoring
    InputMonitor *monitor = [InputMonitor sharedMonitor];
    monitor.delegate = self;
    monitor.secureInputProtectionEnabled = [defs boolForKey:@"secureInputProtection"];
    monitor.forceClickSoundEnabled = [defs boolForKey:@"forceClickSound"];
    
    // Listen for meeting app switches and context-aware profiles
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(activeApplicationChanged:)
                                                               name:NSWorkspaceDidActivateApplicationNotification
                                                             object:nil];
    
    // Listen for background update check completions to refresh menu bar
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateCheckCompleted:)
                                                 name:ClackityUpdateCheckCompletedNotification
                                               object:nil];
    
    // Start audio engine
    [audio start];
    
    // Setup status item menu
    [[MenuBarController sharedController] setupStatusItem];
    
    // Start background auto-updater checks
    [[UpdateManager sharedManager] startPeriodicChecks];
    
    BOOL started = [monitor start];
    if (!started || ![InputMonitor isAccessibilityGranted]) {
        NSLog(@"[Clackity] Accessibility permission needed for global input interception.");
        [InputMonitor promptSystemAccessibilitySheet];
        
        [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
            if ([InputMonitor isAccessibilityGranted]) {
                NSLog(@"[Clackity] Accessibility granted! Recreating global event tap.");
                [monitor restart];
                [[MenuBarController sharedController] updateStatusItem];
                [timer invalidate];
            }
        }];
    }
    
    // Show settings window on launch and activate app so the user sees it immediately
    dispatch_async(dispatch_get_main_queue(), ^{
        [[SettingsWindowController sharedController] showSettingsWindow:nil];
    });
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [[SettingsWindowController sharedController] showSettingsWindow:nil];
    return YES;
}

- (void)activeApplicationChanged:(NSNotification *)notification {
    NSRunningApplication *app = notification.userInfo[NSWorkspaceApplicationKey];
    NSString *bundleId = app.bundleIdentifier.lowercaseString ?: @"";
    NSString *appName = app.localizedName.lowercaseString ?: @"";
    
    // 1. Meeting Auto-Mute Check
    if (self.autoMuteInMeetingsEnabled) {
        NSSet *meetingBundleIds = [NSSet setWithObjects:
            @"us.zoom.xos",
            @"com.microsoft.teams",
            @"com.microsoft.teams2",
            @"com.apple.facetime",
            @"cisco-systems.spark",
            @"com.cisco.webexmeetingsapp",
            @"com.discord",
            @"com.tinyspeck.slackmacgap",
            nil
        ];
        
        BOOL isMeeting = [meetingBundleIds containsObject:bundleId];
        if ([AudioEngine sharedEngine].isMeetingMuted != isMeeting) {
            [AudioEngine sharedEngine].isMeetingMuted = isMeeting;
            [[MenuBarController sharedController] updateStatusItem];
        }
    } else if ([AudioEngine sharedEngine].isMeetingMuted) {
        [AudioEngine sharedEngine].isMeetingMuted = NO;
        [[MenuBarController sharedController] updateStatusItem];
    }
    
    // 2. Context-Aware Profile Switching
    if (self.contextAwareProfilesEnabled && app) {
        AudioEngine *audio = [AudioEngine sharedEngine];
        NSString *targetPackName = nil;
        
        // Development / IDEs: Tactile Thock (Holy Panda / Topre)
        if ([bundleId containsString:@"xcode"] || [bundleId containsString:@"vscode"] ||
            [bundleId containsString:@"terminal"] || [bundleId containsString:@"iterm"] ||
            [appName containsString:@"cursor"] || [appName containsString:@"warp"] ||
            [appName containsString:@"zed"] || [appName containsString:@"ghostty"] ||
            [bundleId containsString:@"sublime"] || [bundleId containsString:@"jetbrains"]) {
            targetPackName = @"Holy Panda";
        }
        // Writing / Notes: Crisp Classic / Tactile Snap (Buckling Spring / Box White / Cream)
        else if ([bundleId containsString:@"notion"] || [bundleId containsString:@"obsidian"] ||
                 [bundleId containsString:@"notes"] || [bundleId containsString:@"pages"] ||
                 [bundleId containsString:@"word"] || [bundleId containsString:@"craft"]) {
            targetPackName = @"NovelKeys Cream";
        }
        // Browsing / Chat: Ultra Smooth Linear (Tealios / Apex Pro)
        else if ([bundleId containsString:@"safari"] || [bundleId containsString:@"chrome"] ||
                 [bundleId containsString:@"firefox"] || [bundleId containsString:@"slack"] ||
                 [bundleId containsString:@"discord"] || [bundleId containsString:@"messages"]) {
            targetPackName = @"Turquoise Tealios";
        }
        
        if (targetPackName) {
            for (CustomSoundPack *pack in [SoundPackManager sharedManager].customPacks) {
                if ([pack.name containsString:targetPackName] && audio.customPack != pack) {
                    audio.customPack = pack;
                    [[NSUserDefaults standardUserDefaults] setObject:pack.name forKey:@"selectedCustomPack"];
                    [[MenuBarController sharedController] updateStatusItem];
                    break;
                }
            }
        }
    }
}

- (void)updateCheckCompleted:(NSNotification *)notification {
    [[MenuBarController sharedController] updateStatusItem];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    [[InputMonitor sharedMonitor] stop];
    [[AudioEngine sharedEngine] stop];
}

- (void)resetSessionStats {
    _sessionClackCount = 0;
    _currentWPM = 0;
    [_keystrokeTimestamps removeAllObjects];
    [[MenuBarController sharedController] updateStatusItem];
}

#pragma mark - InputMonitorDelegate

- (void)inputMonitorDidDetectKeyWithCategory:(ClackityKeyCategory)category keyCode:(int64_t)keyCode isKeyUp:(BOOL)isKeyUp {
    [[AudioEngine sharedEngine] playKeyWithCategory:category keyCode:keyCode isKeyUp:isKeyUp];
    
    if (!isKeyUp) {
        [[HapticEngine sharedEngine] triggerKeyHaptic];
    }
    
    // Keystroke Counter & WPM calculation (KeyDown only)
    if (!isKeyUp && category <= ClackityKeyCategoryModifier) {
        _sessionClackCount++;
        
        uint64_t now = mach_absolute_time();
        static mach_timebase_info_data_t tb;
        if (tb.denom == 0) mach_timebase_info(&tb);
        
        [_keystrokeTimestamps addObject:@(now)];
        
        // Remove timestamps older than 5 seconds (5,000,000,000 ns)
        uint64_t windowNs = 5000000000ULL;
        while (_keystrokeTimestamps.count > 0) {
            uint64_t ts = [_keystrokeTimestamps.firstObject unsignedLongLongValue];
            uint64_t deltaNs = (now - ts) * tb.numer / tb.denom;
            if (deltaNs > windowNs) {
                [_keystrokeTimestamps removeObjectAtIndex:0];
            } else {
                break;
            }
        }
        
        // Calculate WPM: (keystrokes in 5s / 5 chars per word) * (60s / 5s) = keystrokes * 2.4
        NSUInteger calculatedWPM = (NSUInteger)round(_keystrokeTimestamps.count * 2.4);
        _currentWPM = calculatedWPM;
        
        if (self.menuBarDisplayStyle > 0) {
            [[MenuBarController sharedController] updateStatusItemTitle];
            
            // Schedule WPM decay timer
            [_wpmDecayTimer invalidate];
            _wpmDecayTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:NO block:^(NSTimer * _Nonnull timer) {
                [self->_keystrokeTimestamps removeAllObjects];
                self.currentWPM = 0;
                [[MenuBarController sharedController] updateStatusItemTitle];
            }];
        }
    }
}

- (void)inputMonitorDidDetectKeyWithCategory:(ClackityKeyCategory)category isKeyUp:(BOOL)isKeyUp {
    [self inputMonitorDidDetectKeyWithCategory:category keyCode:49 isKeyUp:isKeyUp];
}

- (void)inputMonitorDidTriggerGlobalMuteShortcut {
    [[AudioEngine sharedEngine] toggleMute];
    [[MenuBarController sharedController] updateStatusItem];
}

- (void)inputMonitorDidDetectMouseClickAtPoint:(CGPoint)screenPoint isRightClick:(BOOL)isRightClick isUp:(BOOL)isUp {
    [[AudioEngine sharedEngine] playMouseClick:isRightClick isUp:isUp];
    
    if (!isUp) {
        [[HapticEngine sharedEngine] triggerMouseHaptic];
        [[RippleOverlay sharedOverlay] showRippleAtScreenPoint:screenPoint isRightClick:isRightClick];
    }
}

- (void)inputMonitorDidDetectForceClickAtPoint:(CGPoint)screenPoint {
    [[AudioEngine sharedEngine] playForceClickSound];
    [[HapticEngine sharedEngine] triggerMouseHaptic];
    [[RippleOverlay sharedOverlay] showRippleAtScreenPoint:screenPoint isRightClick:YES];
}

- (void)inputMonitorDidDetectScroll {
    [[AudioEngine sharedEngine] playScroll];
}

@end
