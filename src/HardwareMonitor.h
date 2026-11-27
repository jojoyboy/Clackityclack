#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const ClackityHardwareDidChangeNotification;

typedef NS_ENUM(NSInteger, ClackityExternalKeyboardAction) {
    ClackityExternalKeyboardActionSuppressHaptics = 0, // Suppress Trackpad Haptics only (keep audio)
    ClackityExternalKeyboardActionSoftenAudio     = 1, // Suppress Haptics & soften audio (50% volume)
    ClackityExternalKeyboardActionMuteAll         = 2  // Suppress Haptics & mute audio (no double-clack)
};

@interface HardwareMonitor : NSObject

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) ClackityExternalKeyboardAction externalAction;
@property (nonatomic, readonly) BOOL hasExternalKeyboard;
@property (nonatomic, readonly, nullable) NSString *externalKeyboardName;

+ (instancetype)sharedMonitor;
- (void)start;
- (void)stop;
- (BOOL)shouldSuppressHaptics;
- (BOOL)shouldMuteAudio;
- (float)volumeMultiplier;

@end

NS_ASSUME_NONNULL_END
