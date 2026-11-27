#import "HapticEngine.h"
#import <mach/mach_time.h>
#import <dlfcn.h>

typedef CFArrayRef (*ClackityMTDeviceCreateListFunc)(void);
typedef OSStatus (*ClackityMTDeviceGetDeviceIDFunc)(CFTypeRef device, uint64_t *deviceID);
typedef CFTypeRef (*ClackityMTActuatorCreateFromDeviceIDFunc)(uint64_t deviceID);
typedef IOReturn (*ClackityMTActuatorOpenFunc)(CFTypeRef actuator);
typedef IOReturn (*ClackityMTActuatorActuateFunc)(CFTypeRef actuator, SInt32 actuationID, UInt32 unknown1, Float32 unknown2, Float32 unknown3);
typedef IOReturn (*ClackityMTActuatorCloseFunc)(CFTypeRef actuator);

@implementation HapticEngine {
    uint64_t _lastHapticTimestamp;
    mach_timebase_info_data_t _timebase;
    void *_mtHandle;
    CFTypeRef _actuator;
    ClackityMTActuatorOpenFunc _mtOpen;
    ClackityMTActuatorActuateFunc _mtActuate;
    ClackityMTActuatorCloseFunc _mtClose;
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
        
        [self setupDirectActuator];
    }
    return self;
}

- (void)setupDirectActuator {
    _mtHandle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY);
    if (!_mtHandle) return;
    
    ClackityMTDeviceCreateListFunc createList = (ClackityMTDeviceCreateListFunc)dlsym(_mtHandle, "MTDeviceCreateList");
    ClackityMTDeviceGetDeviceIDFunc getDevID = (ClackityMTDeviceGetDeviceIDFunc)dlsym(_mtHandle, "MTDeviceGetDeviceID");
    ClackityMTActuatorCreateFromDeviceIDFunc createActuator = (ClackityMTActuatorCreateFromDeviceIDFunc)dlsym(_mtHandle, "MTActuatorCreateFromDeviceID");
    _mtOpen = (ClackityMTActuatorOpenFunc)dlsym(_mtHandle, "MTActuatorOpen");
    _mtActuate = (ClackityMTActuatorActuateFunc)dlsym(_mtHandle, "MTActuatorActuate");
    _mtClose = (ClackityMTActuatorCloseFunc)dlsym(_mtHandle, "MTActuatorClose");
    
    if (!createList || !getDevID || !createActuator || !_mtOpen || !_mtActuate || !_mtClose) return;
    
    CFArrayRef devices = createList();
    if (devices && CFArrayGetCount(devices) > 0) {
        CFTypeRef dev = CFArrayGetValueAtIndex(devices, 0);
        uint64_t devID = 0;
        if (getDevID(dev, &devID) == 0) {
            _actuator = createActuator(devID);
            if (_actuator) {
                if (_mtOpen(_actuator) != kIOReturnSuccess) {
                    CFRelease(_actuator);
                    _actuator = NULL;
                }
            }
        }
    }
    if (devices) CFRelease(devices);
}

- (void)dealloc {
    if (_actuator && _mtClose) {
        _mtClose(_actuator);
        CFRelease(_actuator);
        _actuator = NULL;
    }
    if (_mtHandle) {
        dlclose(_mtHandle);
        _mtHandle = NULL;
    }
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
    
    // Prefer direct Force Touch actuator (works globally even when typing in other apps)
    if (_actuator && _mtActuate) {
        SInt32 actuationID = 6;
        switch (self.intensity) {
            case ClackityHapticIntensitySubtle:
                actuationID = 3;
                break;
            case ClackityHapticIntensityCrisp:
                actuationID = 6;
                break;
            case ClackityHapticIntensityHeavy:
                actuationID = 5;
                break;
            default:
                return;
        }
        IOReturn res = _mtActuate(_actuator, actuationID, 0, 0.0f, 0.0f);
        if (res == kIOReturnSuccess) {
            return;
        }
        // Attempt reconnect once (e.g. after system sleep/wake)
        if (_mtOpen && _mtOpen(_actuator) == kIOReturnSuccess) {
            if (_mtActuate(_actuator, actuationID, 0, 0.0f, 0.0f) == kIOReturnSuccess) {
                return;
            }
        }
    }
    
    // Fallback to AppKit NSHapticFeedbackManager
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
