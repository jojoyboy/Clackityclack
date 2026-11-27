#import "AppDelegate.h"
#import "AudioEngine.h"
#import "InputMonitor.h"
#import "RippleOverlay.h"
#import "MenuBarController.h"
#import "UpdateManager.h"
#import "SettingsWindowController.h"
#import "HapticEngine.h"
#import "HardwareMonitor.h"
#import "AppProfileManager.h"
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
        @"autoMuteInGames": @YES,
        @"manualGamingMode": @NO,
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
    
    AudioEngine *audio = [AudioEngine sharedEngine];
    audio.currentProfile = (ClackitySoundProfile)[defs integerForKey:@"selectedProfile"];
    
    id savedCustomPackObj = [defs objectForKey:@"selectedCustomPack"];
    id savedProfileObj = [defs objectForKey:@"selectedProfile"];
    
    if ([savedCustomPackObj isKindOfClass:[NSString class]] && [(NSString *)savedCustomPackObj length] > 0) {
        NSString *customPackName = (NSString *)savedCustomPackObj;
        for (CustomSoundPack *pack in [SoundPackManager sharedManager].customPacks) {
            if ([pack.name isEqualToString:customPackName]) {
                audio.customPack = pack;
                break;
            }
        }
    }
    
    // Only auto-select a default studio pack if the user has never explicitly chosen a synthesized profile
    BOOL hasExplicitSynthesizedSelection = (savedCustomPackObj == nil && savedProfileObj != nil);
    if (!audio.customPack && !hasExplicitSynthesizedSelection && [SoundPackManager sharedManager].customPacks.count > 0) {
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
    self.autoMuteInGamesEnabled = [defs boolForKey:@"autoMuteInGames"];
    self.manualGamingModeEnabled = [defs boolForKey:@"manualGamingMode"];
    self.contextAwareProfilesEnabled = [defs boolForKey:@"contextAwareProfiles"];
    self.menuBarDisplayStyle = [defs integerForKey:@"menuBarDisplayStyle"];
    [self refreshGamingModeForApp:[NSWorkspace sharedWorkspace].frontmostApplication];
    
    RippleOverlay *ripple = [RippleOverlay sharedOverlay];
    ripple.enabled = [defs boolForKey:@"rippleEnabled"];
    ripple.colorTheme = (ClackityRippleColor)[defs integerForKey:@"rippleColorTheme"];
    
    // Setup and start input monitoring & hardware detection
    [[HardwareMonitor sharedMonitor] start];
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
    
    // Register custom URL scheme handler (clackity://)
    [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self
                                                       andSelector:@selector(handleGetURLEvent:withReplyEvent:)
                                                     forEventClass:kInternetEventClass
                                                        andEventID:kAEGetURL];
    
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
    
    // 2. Gaming Mode Auto-Mute Check
    [self refreshGamingModeForApp:app];
    
    // 3. App-Specific & Context-Aware Profile Switching
    [[AppProfileManager sharedManager] handleActiveApplicationChanged:app];
}

- (BOOL)isGameApplication:(nullable NSRunningApplication *)app {
    if (!app) return NO;
    NSString *bundleId = app.bundleIdentifier.lowercaseString ?: @"";
    NSString *bundlePath = app.bundleURL.path.lowercaseString ?: @"";
    
    if ([bundlePath containsString:@"/steamapps/"] ||
        [bundlePath containsString:@"/epic games/"] ||
        [bundlePath containsString:@"/riot games/"] ||
        [bundlePath containsString:@"/applications/games/"]) {
        return YES;
    }
    
    NSArray<NSString *> *gamePrefixes = @[
        @"com.valvesoftware.", @"com.epicgames.", @"com.riotgames.",
        @"net.battle.", @"com.blizzard.", @"com.roblox.",
        @"com.mojang.", @"net.minecraft", @"com.nvidia.gfnpc",
        @"org.openemu.", @"org.dolphin-emu.", @"com.libretro.retroarch",
        @"com.feralinteractive.", @"com.aspyr.", @"com.larian.",
        @"com.larianstudios.", @"jp.co.capcom."
    ];
    for (NSString *prefix in gamePrefixes) {
        if ([bundleId hasPrefix:prefix]) return YES;
    }
    
    if (app.bundleURL) {
        NSBundle *bundle = [NSBundle bundleWithURL:app.bundleURL];
        NSString *category = [bundle.infoDictionary[@"LSApplicationCategoryType"] lowercaseString];
        if ([category containsString:@"games"]) {
            return YES;
        }
    }
    return NO;
}

- (void)refreshGamingModeForApp:(nullable NSRunningApplication *)app {
    NSRunningApplication *targetApp = app ?: [NSWorkspace sharedWorkspace].frontmostApplication;
    BOOL autoGameDetected = self.autoMuteInGamesEnabled && [self isGameApplication:targetApp];
    BOOL shouldMute = self.manualGamingModeEnabled || autoGameDetected;
    
    AudioEngine *audio = [AudioEngine sharedEngine];
    if (audio.isGamingMuted != shouldMute) {
        audio.isGamingMuted = shouldMute;
        [[MenuBarController sharedController] updateStatusItem];
    }
}

- (void)updateCheckCompleted:(NSNotification *)notification {
    [[MenuBarController sharedController] updateStatusItem];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    [[HardwareMonitor sharedMonitor] stop];
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
    AudioEngine *audio = [AudioEngine sharedEngine];
    [audio playKeyWithCategory:category keyCode:keyCode isKeyUp:isKeyUp];
    
    if (!isKeyUp && !audio.isGamingMuted && ![[HardwareMonitor sharedMonitor] shouldSuppressHaptics]) {
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
    AudioEngine *audio = [AudioEngine sharedEngine];
    [audio playMouseClick:isRightClick isUp:isUp];
    
    if (!isUp && !audio.isGamingMuted) {
        if (![[HardwareMonitor sharedMonitor] shouldSuppressHaptics]) {
            [[HapticEngine sharedEngine] triggerMouseHaptic];
        }
        [[RippleOverlay sharedOverlay] showRippleAtScreenPoint:screenPoint isRightClick:isRightClick];
    }
}

- (void)inputMonitorDidDetectForceClickAtPoint:(CGPoint)screenPoint {
    AudioEngine *audio = [AudioEngine sharedEngine];
    [audio playForceClickSound];
    if (!audio.isGamingMuted) {
        if (![[HardwareMonitor sharedMonitor] shouldSuppressHaptics]) {
            [[HapticEngine sharedEngine] triggerMouseHaptic];
        }
        [[RippleOverlay sharedOverlay] showRippleAtScreenPoint:screenPoint isRightClick:YES];
    }
}

- (void)inputMonitorDidDetectScroll {
    [[AudioEngine sharedEngine] playScroll];
}

#pragma mark - Custom URL Scheme (clackity://)

- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent {
    NSString *urlString = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
    if (urlString) {
        NSURL *url = [NSURL URLWithString:urlString];
        if (url) {
            [self handleIncomingURL:url];
        }
    }
}

- (void)handleIncomingURL:(NSURL *)url {
    if (![url.scheme.lowercaseString isEqualToString:@"clackity"]) return;
    
    NSString *host = url.host.lowercaseString;
    if (!host || host.length == 0) {
        host = [[url.path stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]] lowercaseString];
    }
    
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSMutableDictionary<NSString *, NSString *> *params = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in components.queryItems) {
        if (item.name && item.value) {
            params[item.name.lowercaseString] = item.value;
        }
    }
    
    AudioEngine *audio = [AudioEngine sharedEngine];
    
    if ([host isEqualToString:@"switch"]) {
        NSString *name = params[@"name"] ?: params[@"profile"];
        if (name) {
            BOOL ok = [[AppProfileManager sharedManager] switchToProfileNamed:name isAutoSwitch:NO];
            if (ok) {
                NSLog(@"[Clackity] Switched switch profile to '%@' via URL", name);
            }
        }
    } else if ([host isEqualToString:@"profile"]) {
        NSString *action = params[@"action"] ?: params[@"state"];
        if ([action isEqualToString:@"on"] || [action isEqualToString:@"enable"] || [action isEqualToString:@"true"]) {
            [AppProfileManager sharedManager].enabled = YES;
        } else if ([action isEqualToString:@"off"] || [action isEqualToString:@"disable"] || [action isEqualToString:@"false"]) {
            [AppProfileManager sharedManager].enabled = NO;
        }
        
        NSString *cat = params[@"category"];
        NSString *sw = params[@"switch"] ?: params[@"name"];
        if (cat && sw) {
            [[AppProfileManager sharedManager] setProfile:sw forCategory:cat.lowercaseString];
        }
        
        NSString *appId = params[@"app"] ?: params[@"bundle"];
        if (appId && sw) {
            [[AppProfileManager sharedManager] setProfile:sw forBundleId:appId appName:nil];
        }
    } else if ([host isEqualToString:@"mute"]) {
        audio.keySoundsEnabled = NO;
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"keySoundsEnabled"];
        [[MenuBarController sharedController] updateStatusItem];
    } else if ([host isEqualToString:@"unmute"]) {
        audio.keySoundsEnabled = YES;
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"keySoundsEnabled"];
        [[MenuBarController sharedController] updateStatusItem];
    } else if ([host isEqualToString:@"toggle-mute"] || [host isEqualToString:@"toggle"]) {
        [audio toggleMute];
        [[MenuBarController sharedController] updateStatusItem];
    } else if ([host isEqualToString:@"volume"]) {
        NSString *lvl = params[@"level"] ?: params[@"val"];
        if (lvl) {
            float val = [lvl floatValue];
            if (val > 1.0f) val /= 100.0f;
            val = fmaxf(0.0f, fminf(1.0f, val));
            audio.masterVolume = val;
            [[NSUserDefaults standardUserDefaults] setFloat:val forKey:@"masterVolume"];
            [[MenuBarController sharedController] updateStatusItem];
            [audio playKeyWithCategory:ClackityKeyCategoryStandard isKeyUp:NO];
        }
    } else if ([host isEqualToString:@"haptics"]) {
        NSString *profile = params[@"profile"] ?: params[@"intensity"];
        if (profile) {
            if ([profile localizedCaseInsensitiveContainsString:@"subtle"]) {
                [HapticEngine sharedEngine].intensity = ClackityHapticIntensitySubtle;
            } else if ([profile localizedCaseInsensitiveContainsString:@"heavy"]) {
                [HapticEngine sharedEngine].intensity = ClackityHapticIntensityHeavy;
            } else {
                [HapticEngine sharedEngine].intensity = ClackityHapticIntensityCrisp;
            }
            [[HapticEngine sharedEngine] triggerKeyHaptic];
        }
        NSString *enabled = params[@"enabled"];
        if (enabled) {
            BOOL on = [enabled boolValue] || [enabled isEqualToString:@"1"] || [enabled localizedCaseInsensitiveContainsString:@"true"];
            [HapticEngine sharedEngine].enabled = on;
        }
    } else if ([host isEqualToString:@"typewriter"]) {
        NSString *enabled = params[@"enabled"];
        if (enabled) {
            BOOL on = [enabled boolValue] || [enabled isEqualToString:@"1"] || [enabled localizedCaseInsensitiveContainsString:@"true"];
            audio.typewriterModeEnabled = on;
            if (on) [audio playTypewriterCarriageReturn];
        }
    } else if ([host isEqualToString:@"gaming"]) {
        NSString *enabled = params[@"enabled"] ?: params[@"state"];
        if ([enabled isEqualToString:@"toggle"]) {
            self.manualGamingModeEnabled = !self.manualGamingModeEnabled;
        } else if (enabled) {
            self.manualGamingModeEnabled = [enabled boolValue] || [enabled isEqualToString:@"1"] || [enabled localizedCaseInsensitiveContainsString:@"true"] || [enabled localizedCaseInsensitiveContainsString:@"on"];
        } else {
            self.manualGamingModeEnabled = !self.manualGamingModeEnabled;
        }
        [[NSUserDefaults standardUserDefaults] setBool:self.manualGamingModeEnabled forKey:@"manualGamingMode"];
        [self refreshGamingModeForApp:nil];
        [[MenuBarController sharedController] updateStatusItem];
    } else if ([host isEqualToString:@"settings"]) {
        [NSApp activateIgnoringOtherApps:YES];
        [[SettingsWindowController sharedController] showSettingsWindow:nil];
    }
}

@end
