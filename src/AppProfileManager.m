#import "AppProfileManager.h"
#import "AudioEngine.h"
#import "SoundPackManager.h"
#import "SoundSynthesizer.h"
#import "MenuBarController.h"

NSString * const ClackityAppProfileCategoryCode = @"code";
NSString * const ClackityAppProfileCategoryWriting = @"writing";
NSString * const ClackityAppProfileCategoryChat = @"chat";
NSString * const ClackityAppProfileCategoryBrowser = @"browser";
NSString * const ClackityAppProfileCategoryDefault = @"default";

NSString * const ClackityAppProfileDidChangeNotification = @"ClackityAppProfileDidChangeNotification";

static NSString * const kPrefAppSpecificEnabled = @"appSpecificProfilesEnabled";
static NSString * const kPrefCategoryProfiles = @"appCategoryProfiles";
static NSString * const kPrefCustomAppRules = @"customAppRules";
static NSString * const kPrefGlobalDefaultSwitch = @"globalDefaultSwitch";

@interface AppProfileManager ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *categories;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *customRules;
@end

@implementation AppProfileManager

+ (instancetype)sharedManager {
    static AppProfileManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[AppProfileManager alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        
        // Master enable toggle
        if ([defs objectForKey:kPrefAppSpecificEnabled]) {
            _enabled = [defs boolForKey:kPrefAppSpecificEnabled];
        } else if ([defs objectForKey:@"contextAwareProfiles"]) {
            _enabled = [defs boolForKey:@"contextAwareProfiles"];
        } else {
            _enabled = NO;
        }
        
        // Category Profiles
        NSDictionary *savedCats = [defs dictionaryForKey:kPrefCategoryProfiles];
        _categories = [NSMutableDictionary dictionary];
        _categories[ClackityAppProfileCategoryCode] = savedCats[ClackityAppProfileCategoryCode] ?: @"Holy Panda";
        _categories[ClackityAppProfileCategoryWriting] = savedCats[ClackityAppProfileCategoryWriting] ?: @"Underwood Typewriter";
        _categories[ClackityAppProfileCategoryChat] = savedCats[ClackityAppProfileCategoryChat] ?: @"Turquoise Tealios";
        _categories[ClackityAppProfileCategoryBrowser] = savedCats[ClackityAppProfileCategoryBrowser] ?: @"Gateron Oil King";
        _categories[ClackityAppProfileCategoryDefault] = savedCats[ClackityAppProfileCategoryDefault] ?: @"NovelKeys Cream";
        
        // Custom per-app rules
        NSDictionary *savedRules = [defs dictionaryForKey:kPrefCustomAppRules];
        if (savedRules) {
            _customRules = [savedRules mutableCopy];
        } else {
            _customRules = [NSMutableDictionary dictionary];
        }
        
        // Global Default Switch
        _globalDefaultSwitch = [defs stringForKey:kPrefGlobalDefaultSwitch];
        if (!_globalDefaultSwitch || _globalDefaultSwitch.length == 0) {
            _globalDefaultSwitch = _categories[ClackityAppProfileCategoryDefault];
        }
    }
    return self;
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kPrefAppSpecificEnabled];
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"contextAwareProfiles"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    if (enabled) {
        // Immediately apply profile for currently frontmost app
        NSRunningApplication *frontApp = [NSWorkspace sharedWorkspace].frontmostApplication;
        if (frontApp) {
            [self handleActiveApplicationChanged:frontApp];
        }
    } else {
        // Revert to global switch
        if (self.globalDefaultSwitch) {
            [self switchToProfileNamed:self.globalDefaultSwitch isAutoSwitch:YES];
        }
    }
}

- (void)setGlobalDefaultSwitch:(NSString *)globalDefaultSwitch {
    if (!globalDefaultSwitch || globalDefaultSwitch.length == 0) return;
    _globalDefaultSwitch = [globalDefaultSwitch copy];
    [[NSUserDefaults standardUserDefaults] setObject:_globalDefaultSwitch forKey:kPrefGlobalDefaultSwitch];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Category Profiles

- (NSString *)profileForCategory:(NSString *)categoryKey {
    if (!categoryKey) return self.globalDefaultSwitch;
    return self.categories[categoryKey] ?: self.globalDefaultSwitch;
}

- (void)setProfile:(NSString *)profileName forCategory:(NSString *)categoryKey {
    if (!categoryKey || !profileName) return;
    self.categories[categoryKey] = profileName;
    [[NSUserDefaults standardUserDefaults] setObject:self.categories forKey:kPrefCategoryProfiles];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    // If currently in an app matching this category, switch immediately
    if (self.enabled) {
        NSRunningApplication *frontApp = [NSWorkspace sharedWorkspace].frontmostApplication;
        if (frontApp) {
            NSString *cat = nil;
            NSString *effective = [self effectiveProfileForApplication:frontApp categoryOut:&cat];
            if ([cat isEqualToString:categoryKey] && effective) {
                [self switchToProfileNamed:effective isAutoSwitch:YES];
            }
        }
    }
}

#pragma mark - Custom App Rules

- (NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)customAppRules {
    return [self.customRules copy];
}

- (void)setProfile:(NSString *)profileName forBundleId:(NSString *)bundleId appName:(NSString *)appName {
    if (!bundleId || bundleId.length == 0 || !profileName) return;
    NSString *safeName = (appName && appName.length > 0) ? appName : bundleId;
    self.customRules[bundleId] = @{
        @"appName": safeName,
        @"profileName": profileName
    };
    [[NSUserDefaults standardUserDefaults] setObject:self.customRules forKey:kPrefCustomAppRules];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    if (self.enabled) {
        NSRunningApplication *frontApp = [NSWorkspace sharedWorkspace].frontmostApplication;
        if (frontApp && [frontApp.bundleIdentifier isEqualToString:bundleId]) {
            [self switchToProfileNamed:profileName isAutoSwitch:YES];
        }
    }
}

- (void)removeCustomRuleForBundleId:(NSString *)bundleId {
    if (!bundleId) return;
    [self.customRules removeObjectForKey:bundleId];
    [[NSUserDefaults standardUserDefaults] setObject:self.customRules forKey:kPrefCustomAppRules];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    if (self.enabled) {
        NSRunningApplication *frontApp = [NSWorkspace sharedWorkspace].frontmostApplication;
        if (frontApp && [frontApp.bundleIdentifier isEqualToString:bundleId]) {
            [self handleActiveApplicationChanged:frontApp];
        }
    }
}

#pragma mark - Application Evaluation

- (NSString *)effectiveProfileForApplication:(NSRunningApplication *)app categoryOut:(NSString **)categoryOut {
    if (!app) {
        if (categoryOut) *categoryOut = ClackityAppProfileCategoryDefault;
        return [self profileForCategory:ClackityAppProfileCategoryDefault];
    }
    
    NSString *bundleId = app.bundleIdentifier.lowercaseString ?: @"";
    NSString *appName = app.localizedName.lowercaseString ?: @"";
    
    // 1. Specific Custom App Rules (Highest Priority)
    for (NSString *key in self.customRules) {
        if ([key.lowercaseString isEqualToString:bundleId] || [key.lowercaseString isEqualToString:appName]) {
            if (categoryOut) *categoryOut = @"custom";
            return self.customRules[key][@"profileName"];
        }
    }
    
    // 2. Code & Terminals
    if ([bundleId containsString:@"xcode"] || [bundleId containsString:@"vscode"] ||
        [bundleId containsString:@"terminal"] || [bundleId containsString:@"iterm"] ||
        [appName containsString:@"cursor"] || [appName containsString:@"warp"] ||
        [appName containsString:@"zed"] || [appName containsString:@"ghostty"] ||
        [bundleId containsString:@"sublime"] || [bundleId containsString:@"jetbrains"] ||
        [appName containsString:@"pycharm"] || [appName containsString:@"webstorm"] ||
        [appName containsString:@"clion"] || [appName containsString:@"android studio"] ||
        [appName containsString:@"alacritty"] || [appName containsString:@"kitty"] ||
        [appName containsString:@"neovim"] || [appName containsString:@"emacs"] ||
        [appName containsString:@"macvim"] || [appName containsString:@"bbedit"] ||
        [appName containsString:@"nova"]) {
        if (categoryOut) *categoryOut = ClackityAppProfileCategoryCode;
        return [self profileForCategory:ClackityAppProfileCategoryCode];
    }
    
    // 3. Writing & Documentation
    if ([bundleId containsString:@"notion"] || [bundleId containsString:@"obsidian"] ||
        [bundleId containsString:@"notes"] || [bundleId containsString:@"pages"] ||
        [bundleId containsString:@"word"] || [bundleId containsString:@"craft"] ||
        [appName containsString:@"scrivener"] || [appName containsString:@"bear"] ||
        [appName containsString:@"ulysses"] || [appName containsString:@"textedit"] ||
        [appName containsString:@"typora"] || [appName containsString:@"ia writer"] ||
        [appName containsString:@"byword"] || [appName containsString:@"marked"]) {
        if (categoryOut) *categoryOut = ClackityAppProfileCategoryWriting;
        return [self profileForCategory:ClackityAppProfileCategoryWriting];
    }
    
    // 4. Chat & Communication
    if ([bundleId containsString:@"slack"] || [bundleId containsString:@"discord"] ||
        [bundleId containsString:@"messages"] || [bundleId containsString:@"telegram"] ||
        [bundleId containsString:@"whatsapp"] || [bundleId containsString:@"signal"] ||
        [bundleId containsString:@"wechat"] || [bundleId containsString:@"teams"] ||
        [bundleId containsString:@"mattermost"] || [bundleId containsString:@"element"]) {
        if (categoryOut) *categoryOut = ClackityAppProfileCategoryChat;
        return [self profileForCategory:ClackityAppProfileCategoryChat];
    }
    
    // 5. Web Browsing
    if ([bundleId containsString:@"safari"] || [bundleId containsString:@"chrome"] ||
        [bundleId containsString:@"firefox"] || [appName containsString:@"arc"] ||
        [appName containsString:@"brave"] || [bundleId containsString:@"edge"] ||
        [appName containsString:@"orion"] || [appName containsString:@"opera"] ||
        [appName containsString:@"vivaldi"]) {
        if (categoryOut) *categoryOut = ClackityAppProfileCategoryBrowser;
        return [self profileForCategory:ClackityAppProfileCategoryBrowser];
    }
    
    // 6. Default Fallback
    if (categoryOut) *categoryOut = ClackityAppProfileCategoryDefault;
    return [self profileForCategory:ClackityAppProfileCategoryDefault] ?: self.globalDefaultSwitch;
}

- (void)handleActiveApplicationChanged:(NSRunningApplication *)app {
    if (!self.enabled || !app) return;
    
    // Ignore Clackity itself so clicking Settings doesn't thrash profile
    if ([app.bundleIdentifier isEqualToString:[NSBundle mainBundle].bundleIdentifier]) return;
    
    NSString *category = nil;
    NSString *targetSwitch = [self effectiveProfileForApplication:app categoryOut:&category];
    if (targetSwitch && targetSwitch.length > 0) {
        [self switchToProfileNamed:targetSwitch isAutoSwitch:YES];
    }
}

#pragma mark - Switch Execution

- (BOOL)switchToProfileNamed:(NSString *)name isAutoSwitch:(BOOL)isAutoSwitch {
    if (!name || name.length == 0) return NO;
    AudioEngine *audio = [AudioEngine sharedEngine];
    BOOL matched = NO;
    
    // 1. Search custom studio packs
    for (CustomSoundPack *pack in [SoundPackManager sharedManager].customPacks) {
        if ([pack.name localizedCaseInsensitiveContainsString:name]) {
            if (audio.customPack != pack) {
                audio.customPack = pack;
                [[NSUserDefaults standardUserDefaults] setObject:pack.name forKey:@"selectedCustomPack"];
            }
            matched = YES;
            break;
        }
    }
    
    // 2. Search synthesized profiles
    if (!matched) {
        for (NSNumber *num in [SoundSynthesizer allProfiles]) {
            ClackitySoundProfile p = (ClackitySoundProfile)[num integerValue];
            NSString *pName = [SoundSynthesizer nameForProfile:p];
            if ([pName localizedCaseInsensitiveContainsString:name]) {
                if (audio.customPack != nil || audio.currentProfile != p) {
                    audio.customPack = nil;
                    audio.currentProfile = p;
                    [[NSUserDefaults standardUserDefaults] setInteger:p forKey:@"selectedProfile"];
                    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"selectedCustomPack"];
                }
                matched = YES;
                break;
            }
        }
    }
    
    if (matched) {
        if (!isAutoSwitch) {
            // User manually selected this profile, remember as global fallback
            self.globalDefaultSwitch = name;
            [audio playKeyWithCategory:ClackityKeyCategoryEnter isKeyUp:NO];
        }
        [[MenuBarController sharedController] updateStatusItem];
        [[NSNotificationCenter defaultCenter] postNotificationName:ClackityAppProfileDidChangeNotification object:name];
        return YES;
    }
    
    return NO;
}

- (NSArray<NSString *> *)allAvailableSwitchNames {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    
    // Studio Sound Packs
    for (CustomSoundPack *pack in [SoundPackManager sharedManager].customPacks) {
        [names addObject:pack.name];
    }
    
    // Synthesized Models
    for (NSNumber *num in [SoundSynthesizer allProfiles]) {
        ClackitySoundProfile p = (ClackitySoundProfile)[num integerValue];
        [names addObject:[SoundSynthesizer nameForProfile:p]];
    }
    
    return [names copy];
}

@end
