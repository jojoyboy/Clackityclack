#import "HapticEngine.h"
#import <mach/mach_time.h>

@implementation HapticEngine {
    uint64_t _lastHapticTimestamp;
    mach_timebase_info_data_t _timebase;
}

+ (instancetype)sharedEngine {
    static HapticEngine *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HapticEngine alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        mach_timebase_info(&_timebase);
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        
        // Default to enabled with Crisp intensity if defaults are not set yet
        if ([defs objectForKey:@"hapticEnabled"] == nil) {
            _enabled = YES;
            _intensity = ClackityHapticIntensityCrisp;
            _hapticOnKeyPress = YES;
            _hapticOnMouseClick = NO; // Default mouse to off so trackpad physical clicks aren't doubled
            
            [defs setBool:_enabled forKey:@"hapticEnabled"];
            [defs setInteger:_intensity forKey:@"hapticIntensity"];
            [defs setBool:_hapticOnKeyPress forKey:@"hapticOnKeyPress"];
            [defs setBool:_hapticOnMouseClick forKey:@"hapticOnMouseClick"];
        } else {
            _enabled = [defs boolForKey:@"hapticEnabled"];
            _intensity = (ClackityHapticIntensity)[defs integerForKey:@"hapticIntensity"];
            _hapticOnKeyPress = [defs boolForKey:@"hapticOnKeyPress"];
            _hapticOnMouseClick = [defs boolForKey:@"hapticOnMouseClick"];
        }
    }
    return self;
}

+ (BOOL)isForceTouchHardwareAvailable {
    id<NSHapticFeedbackPerformer> performer = [NSHapticFeedbackManager defaultPerformer];
    return performer != nil;
}

- (void)triggerKeyHaptic {
    if (!self.enabled || !self.hapticOnKeyPress || self.intensity == ClackityHapticIntensityOff) {
        return;
    }
    [self performHapticActuation];
}

- (void)triggerMouseHaptic {
    if (!self.enabled || !self.hapticOnMouseClick || self.intensity == ClackityHapticIntensityOff) {
        return;
    }
    [self performHapticActuation];
}

- (void)performHapticActuation {
    // Prevent actuator coil saturation during fast rolling: minimum 30ms interval
    uint64_t now = mach_absolute_time();
    if (_lastHapticTimestamp > 0) {
        uint64_t elapsedNs = (now - _lastHapticTimestamp) * _timebase.numer / _timebase.denom;
        if (elapsedNs < 28000000ULL) { // 28ms throttle (allows ~35 Hz max cadence)
            return;
        }
    }
    _lastHapticTimestamp = now;
    
    id<NSHapticFeedbackPerformer> performer = [NSHapticFeedbackManager defaultPerformer];
    if (!performer) return;
    
    NSHapticFeedbackPattern pattern = NSHapticFeedbackPatternGeneric;
    switch (self.intensity) {
        case ClackityHapticIntensitySubtle:
            pattern = NSHapticFeedbackPatternAlignment;
            break;
        case ClackityHapticIntensityCrisp:
            pattern = NSHapticFeedbackPatternGeneric;
            break;
        case ClackityHapticIntensityHeavy:
            pattern = NSHapticFeedbackPatternLevelChange;
            break;
        default:
            return;
    }
    
    [performer performFeedbackPattern:pattern performanceTime:NSHapticFeedbackPerformanceTimeNow];
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"hapticEnabled"];
}

- (void)setIntensity:(ClackityHapticIntensity)intensity {
    _intensity = intensity;
    [[NSUserDefaults standardUserDefaults] setInteger:intensity forKey:@"hapticIntensity"];
}

- (void)setHapticOnKeyPress:(BOOL)hapticOnKeyPress {
    _hapticOnKeyPress = hapticOnKeyPress;
    [[NSUserDefaults standardUserDefaults] setBool:hapticOnKeyPress forKey:@"hapticOnKeyPress"];
}

- (void)setHapticOnMouseClick:(BOOL)hapticOnMouseClick {
    _hapticOnMouseClick = hapticOnMouseClick;
    [[NSUserDefaults standardUserDefaults] setBool:hapticOnMouseClick forKey:@"hapticOnMouseClick"];
}

@end
