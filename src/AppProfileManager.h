#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

extern NSString * const ClackityAppProfileCategoryCode;
extern NSString * const ClackityAppProfileCategoryWriting;
extern NSString * const ClackityAppProfileCategoryChat;
extern NSString * const ClackityAppProfileCategoryBrowser;
extern NSString * const ClackityAppProfileCategoryDefault;

extern NSString * const ClackityAppProfileDidChangeNotification;

@interface AppProfileManager : NSObject

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy) NSString *globalDefaultSwitch;

+ (instancetype)sharedManager;

// Category profile getters/setters
- (NSString *)profileForCategory:(NSString *)categoryKey;
- (void)setProfile:(NSString *)profileName forCategory:(NSString *)categoryKey;

// Custom per-app rules: bundleId -> @{ @"appName": @"...", @"profileName": @"..." }
- (NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)customAppRules;
- (void)setProfile:(NSString *)profileName forBundleId:(NSString *)bundleId appName:(NSString *)appName;
- (void)removeCustomRuleForBundleId:(NSString *)bundleId;

// Active application handling
- (void)handleActiveApplicationChanged:(NSRunningApplication *)app;
- (NSString *)effectiveProfileForApplication:(NSRunningApplication *)app categoryOut:(NSString **)categoryOut;

// Utility list of all switch options (studio sound packs + synthesized models)
- (NSArray<NSString *> *)allAvailableSwitchNames;

// Direct switch helper
- (BOOL)switchToProfileNamed:(NSString *)name isAutoSwitch:(BOOL)isAutoSwitch;

@end
