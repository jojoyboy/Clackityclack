#import "HardwareMonitor.h"
#import <IOKit/hid/IOHIDManager.h>

NSString * const ClackityHardwareDidChangeNotification = @"ClackityHardwareDidChangeNotification";

static NSString * const kPrefHardwareAwareEnabled = @"hardwareAwareEnabled";
static NSString * const kPrefExternalKeyboardAction = @"externalKeyboardAction";

@interface HardwareMonitor ()
@property (nonatomic, assign, readwrite) BOOL hasExternalKeyboard;
@property (nonatomic, copy, readwrite, nullable) NSString *externalKeyboardName;
- (void)refreshConnectedKeyboards;
@end

static void ClackityHIDDeviceMatched(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    HardwareMonitor *monitor = (__bridge HardwareMonitor *)context;
    [monitor refreshConnectedKeyboards];
}

static void ClackityHIDDeviceRemoved(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    HardwareMonitor *monitor = (__bridge HardwareMonitor *)context;
    [monitor refreshConnectedKeyboards];
}

@implementation HardwareMonitor {
    IOHIDManagerRef _hidManager;
}

+ (instancetype)sharedMonitor {
    static HardwareMonitor *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[HardwareMonitor alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        [defs registerDefaults:@{
            kPrefHardwareAwareEnabled: @YES,
            kPrefExternalKeyboardAction: @(ClackityExternalKeyboardActionSuppressHaptics)
        }];
        _enabled = [defs boolForKey:kPrefHardwareAwareEnabled];
        _externalAction = (ClackityExternalKeyboardAction)[defs integerForKey:kPrefExternalKeyboardAction];
    }
    return self;
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kPrefHardwareAwareEnabled];
    [[NSNotificationCenter defaultCenter] postNotificationName:ClackityHardwareDidChangeNotification object:nil];
}

- (void)setExternalAction:(ClackityExternalKeyboardAction)externalAction {
    _externalAction = externalAction;
    [[NSUserDefaults standardUserDefaults] setInteger:externalAction forKey:kPrefExternalKeyboardAction];
    [[NSNotificationCenter defaultCenter] postNotificationName:ClackityHardwareDidChangeNotification object:nil];
}

- (void)start {
    if (_hidManager) return;
    
    _hidManager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!_hidManager) return;
    
    NSDictionary *matching = @{
        @(kIOHIDDeviceUsagePageKey): @(kHIDPage_GenericDesktop),
        @(kIOHIDDeviceUsageKey): @(kHIDUsage_GD_Keyboard)
    };
    IOHIDManagerSetDeviceMatching(_hidManager, (__bridge CFDictionaryRef)matching);
    IOHIDManagerRegisterDeviceMatchingCallback(_hidManager, ClackityHIDDeviceMatched, (__bridge void *)self);
    IOHIDManagerRegisterDeviceRemovalCallback(_hidManager, ClackityHIDDeviceRemoved, (__bridge void *)self);
    IOHIDManagerScheduleWithRunLoop(_hidManager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    IOHIDManagerOpen(_hidManager, kIOHIDOptionsTypeNone);
    
    [self refreshConnectedKeyboards];
}

- (void)stop {
    if (_hidManager) {
        IOHIDManagerUnscheduleFromRunLoop(_hidManager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
        IOHIDManagerClose(_hidManager, kIOHIDOptionsTypeNone);
        CFRelease(_hidManager);
        _hidManager = NULL;
    }
}

- (void)dealloc {
    [self stop];
}

- (void)refreshConnectedKeyboards {
    if (!_hidManager) return;
    
    CFSetRef devices = IOHIDManagerCopyDevices(_hidManager);
    BOOL foundExternal = NO;
    NSString *extName = nil;
    
    if (devices) {
        NSSet *devSet = (__bridge NSSet *)devices;
        for (id obj in devSet) {
            IOHIDDeviceRef dev = (__bridge IOHIDDeviceRef)obj;
            
            CFTypeRef builtInProp = IOHIDDeviceGetProperty(dev, CFSTR(kIOHIDBuiltInKey));
            if (builtInProp && CFGetTypeID(builtInProp) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)builtInProp)) {
                continue; // Internal MacBook keyboard
            }
            
            NSString *transport = (__bridge NSString *)IOHIDDeviceGetProperty(dev, CFSTR(kIOHIDTransportKey));
            NSString *product = (__bridge NSString *)IOHIDDeviceGetProperty(dev, CFSTR(kIOHIDProductKey));
            NSString *lowerTransport = transport.lowercaseString ?: @"";
            NSString *lowerProduct = product.lowercaseString ?: @"";
            
            // Ignore internal Apple SPI/FIFO and virtual software keyboards
            if ([lowerTransport isEqualToString:@"spi"] ||
                [lowerTransport isEqualToString:@"fifo"] ||
                [lowerTransport isEqualToString:@"virtual"] ||
                [lowerProduct containsString:@"apple internal"] ||
                [lowerProduct containsString:@"karabiner"]) {
                continue;
            }
            
            // Accept USB / Bluetooth / BLE external keyboards
            if ([lowerTransport isEqualToString:@"usb"] ||
                [lowerTransport containsString:@"bluetooth"] ||
                product.length > 0) {
                foundExternal = YES;
                extName = product.length > 0 ? product : @"External Keyboard";
                break;
            }
        }
        CFRelease(devices);
    }
    
    BOOL changed = (self.hasExternalKeyboard != foundExternal) ||
                   (self.externalKeyboardName != extName && ![self.externalKeyboardName isEqualToString:extName]);
    self.hasExternalKeyboard = foundExternal;
    self.externalKeyboardName = extName;
    
    if (changed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:ClackityHardwareDidChangeNotification object:nil];
        });
    }
}

- (BOOL)shouldSuppressHaptics {
    return self.enabled && self.hasExternalKeyboard;
}

- (BOOL)shouldMuteAudio {
    return self.enabled && self.hasExternalKeyboard && self.externalAction == ClackityExternalKeyboardActionMuteAll;
}

- (float)volumeMultiplier {
    if (!self.enabled || !self.hasExternalKeyboard) return 1.0f;
    if (self.externalAction == ClackityExternalKeyboardActionMuteAll) return 0.0f;
    if (self.externalAction == ClackityExternalKeyboardActionSoftenAudio) return 0.5f;
    return 1.0f;
}

@end
