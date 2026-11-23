#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ClackityHapticIntensity) {
    ClackityHapticIntensityOff = 0,
    ClackityHapticIntensitySubtle = 1,   // Alignment pattern (soft tactile snap)
    ClackityHapticIntensityCrisp = 2,    // Generic pattern (mechanical tactile click)
    ClackityHapticIntensityHeavy = 3     // LevelChange pattern (deep actuation kick)
};

@interface HapticEngine : NSObject

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) ClackityHapticIntensity intensity;
@property (nonatomic, assign) BOOL hapticOnKeyPress;
@property (nonatomic, assign) BOOL hapticOnMouseClick;

+ (instancetype)sharedEngine;

/// Returns YES if the Mac hardware supports Force Touch haptic feedback.
+ (BOOL)isForceTouchHardwareAvailable;

/// Trigger a crisp mechanical haptic kick on the MacBook trackpad for a key press
- (void)triggerKeyHaptic;

/// Trigger a haptic feedback on a mouse click
- (void)triggerMouseHaptic;

@end

NS_ASSUME_NONNULL_END
