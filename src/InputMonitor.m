#import "InputMonitor.h"
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#import <mach/mach_time.h>

@interface InputMonitor () {
@public
    CFMachPortRef _eventTap;
    CFRunLoopSourceRef _runLoopSource;
    CGEventFlags _previousFlags;
}
- (void)handleEvent:(CGEventRef)event type:(CGEventType)type;
@end

static CGEventRef eventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    InputMonitor *self = (__bridge InputMonitor *)refcon;
    
    // Handle tap disabled by system timeout
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (self->_eventTap) {
            CGEventTapEnable(self->_eventTap, true);
        }
        return event;
    }
    
    [self handleEvent:event type:type];
    return event;
}

@implementation InputMonitor

+ (instancetype)sharedMonitor {
    static InputMonitor *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[InputMonitor alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _secureInputProtectionEnabled = YES;
        _forceClickSoundEnabled = YES;
    }
    return self;
}

+ (BOOL)isAccessibilityGranted {
    NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @NO};
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

+ (BOOL)isSecureEventInputActive {
    return IsSecureEventInputEnabled() ? YES : NO;
}

+ (void)promptSystemAccessibilitySheet {
    NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

+ (void)openAccessibilitySettings {
    [self promptSystemAccessibilitySheet];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
}

- (BOOL)start {
    if (_eventTap) return YES;
    
    CGEventMask eventMask = (
        CGEventMaskBit(kCGEventKeyDown) |
        CGEventMaskBit(kCGEventKeyUp) |
        CGEventMaskBit(kCGEventFlagsChanged) |
        CGEventMaskBit(kCGEventLeftMouseDown) |
        CGEventMaskBit(kCGEventLeftMouseUp) |
        CGEventMaskBit(kCGEventRightMouseDown) |
        CGEventMaskBit(kCGEventRightMouseUp) |
        CGEventMaskBit(kCGEventOtherMouseDown) |
        CGEventMaskBit(kCGEventOtherMouseUp) |
        CGEventMaskBit(kCGEventScrollWheel)
    );
    
    // Use session event tap which directly binds to macOS Accessibility permissions
    _eventTap = CGEventTapCreate(
        kCGSessionEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionListenOnly,
        eventMask,
        eventTapCallback,
        (__bridge void *)self
    );
    
    // Fallback to HID tap if session tap fails
    if (!_eventTap) {
        _eventTap = CGEventTapCreate(
            kCGHIDEventTap,
            kCGHeadInsertEventTap,
            kCGEventTapOptionListenOnly,
            eventMask,
            eventTapCallback,
            (__bridge void *)self
        );
    }
    
    if (!_eventTap) {
        NSLog(@"[Clackity] Failed to create CGEventTap. Accessibility permission may be required.");
        return NO;
    }
    
    _runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), _runLoopSource, kCFRunLoopCommonModes);
    CGEventTapEnable(_eventTap, true);
    
    _isRunning = YES;
    return YES;
}

- (BOOL)restart {
    [self stop];
    return [self start];
}

- (void)stop {
    if (_eventTap) {
        CGEventTapEnable(_eventTap, false);
        if (_runLoopSource) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), _runLoopSource, kCFRunLoopCommonModes);
            CFRelease(_runLoopSource);
            _runLoopSource = NULL;
        }
        CFRelease(_eventTap);
        _eventTap = NULL;
    }
    _isRunning = NO;
}

- (void)handleEvent:(CGEventRef)event type:(CGEventType)type {
    // 1. Password Field Protection: Auto-mute all keystrokes during macOS Secure Event Input
    if (_secureInputProtectionEnabled && IsSecureEventInputEnabled()) {
        if (type == kCGEventKeyDown || type == kCGEventKeyUp || type == kCGEventFlagsChanged) {
            return;
        }
    }

    switch (type) {
        case kCGEventKeyDown: {
            int64_t keyCode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
            CGEventFlags flags = CGEventGetFlags(event);
            
            // Global Shortcut: Cmd + Shift + \ (keyCode 42)
            BOOL hasCmd = (flags & kCGEventFlagMaskCommand) != 0;
            BOOL hasShift = (flags & kCGEventFlagMaskShift) != 0;
            if (keyCode == 42 && hasCmd && hasShift) {
                if ([self.delegate respondsToSelector:@selector(inputMonitorDidTriggerGlobalMuteShortcut)]) {
                    [self.delegate inputMonitorDidTriggerGlobalMuteShortcut];
                }
                break;
            }
            
            ClackityKeyCategory cat = [self categoryForKeyCode:keyCode];
            if ([self.delegate respondsToSelector:@selector(inputMonitorDidDetectKeyWithCategory:keyCode:isKeyUp:)]) {
                [self.delegate inputMonitorDidDetectKeyWithCategory:cat keyCode:keyCode isKeyUp:NO];
            } else if ([self.delegate respondsToSelector:@selector(inputMonitorDidDetectKeyWithCategory:isKeyUp:)]) {
                [self.delegate inputMonitorDidDetectKeyWithCategory:cat isKeyUp:NO];
            }
            break;
        }
            
        case kCGEventKeyUp: {
            int64_t keyCode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
            ClackityKeyCategory cat = [self categoryForKeyCode:keyCode];
            if ([self.delegate respondsToSelector:@selector(inputMonitorDidDetectKeyWithCategory:keyCode:isKeyUp:)]) {
                [self.delegate inputMonitorDidDetectKeyWithCategory:cat keyCode:keyCode isKeyUp:YES];
            } else if ([self.delegate respondsToSelector:@selector(inputMonitorDidDetectKeyWithCategory:isKeyUp:)]) {
                [self.delegate inputMonitorDidDetectKeyWithCategory:cat isKeyUp:YES];
            }
            break;
        }
            
        case kCGEventFlagsChanged: {
            CGEventFlags currentFlags = CGEventGetFlags(event);
            int64_t keyCode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
            ClackityKeyCategory cat = [self categoryForKeyCode:keyCode];
            
            BOOL isKeyUp = [self isModifierKeyUpForCode:keyCode flags:currentFlags];
            
            if ([self.delegate respondsToSelector:@selector(inputMonitorDidDetectKeyWithCategory:keyCode:isKeyUp:)]) {
                [self.delegate inputMonitorDidDetectKeyWithCategory:cat keyCode:keyCode isKeyUp:isKeyUp];
            } else if ([self.delegate respondsToSelector:@selector(inputMonitorDidDetectKeyWithCategory:isKeyUp:)]) {
                [self.delegate inputMonitorDidDetectKeyWithCategory:cat isKeyUp:isKeyUp];
            }
            break;
        }
            
        case kCGEventLeftMouseDown: {
            CGPoint location = CGEventGetLocation(event);
            double pressure = CGEventGetDoubleValueField(event, kCGMouseEventPressure);
            int64_t clickState = CGEventGetIntegerValueField(event, kCGMouseEventClickState);
            
            // Detect Trackpad Force Touch / deep press
            if (_forceClickSoundEnabled && (pressure >= 0.85 || clickState >= 3)) {
                if ([self.delegate respondsToSelector:@selector(inputMonitorDidDetectForceClickAtPoint:)]) {
                    [self.delegate inputMonitorDidDetectForceClickAtPoint:location];
                }
            } else {
                if ([self.delegate respondsToSelector:@selector(inputMonitorDidDetectMouseClickAtPoint:isRightClick:isUp:)]) {
                    [self.delegate inputMonitorDidDetectMouseClickAtPoint:location isRightClick:NO isUp:NO];
                }
            }
            break;
        }
            
        case kCGEventLeftMouseUp: {
            CGPoint location = CGEventGetLocation(event);
            if ([self.delegate respondsToSelector:@selector(inputMonitorDidDetectMouseClickAtPoint:isRightClick:isUp:)]) {
                [self.delegate inputMonitorDidDetectMouseClickAtPoint:location isRightClick:NO isUp:YES];
            }
            break;
        }
            
        case kCGEventRightMouseDown: {
            CGPoint location = CGEventGetLocation(event);
            if ([self.delegate respondsToSelector:@selector(inputMonitorDidDetectMouseClickAtPoint:isRightClick:isUp:)]) {
                [self.delegate inputMonitorDidDetectMouseClickAtPoint:location isRightClick:YES isUp:NO];
            }
            break;
        }
            
        case kCGEventRightMouseUp: {
            CGPoint location = CGEventGetLocation(event);
            if ([self.delegate respondsToSelector:@selector(inputMonitorDidDetectMouseClickAtPoint:isRightClick:isUp:)]) {
                [self.delegate inputMonitorDidDetectMouseClickAtPoint:location isRightClick:YES isUp:YES];
            }
            break;
        }
            
        case kCGEventScrollWheel: {
            // Rate-limit scroll wheel sounds so continuous trackpad scrolls sound like discrete mechanical ratchets
            static uint64_t lastScrollTime = 0;
            uint64_t now = mach_absolute_time();
            static mach_timebase_info_data_t timebase;
            if (timebase.denom == 0) mach_timebase_info(&timebase);
            uint64_t elapsedNs = (now - lastScrollTime) * timebase.numer / timebase.denom;
            
            // At least 40ms between scroll ratchet clicks (~25 clicks per sec max)
            if (elapsedNs > 40000000) {
                lastScrollTime = now;
                if ([self.delegate respondsToSelector:@selector(inputMonitorDidDetectScroll)]) {
                    [self.delegate inputMonitorDidDetectScroll];
                }
            }
            break;
        }
            
        default:
            break;
    }
}

- (BOOL)isModifierKeyUpForCode:(int64_t)keyCode flags:(CGEventFlags)flags {
    CGEventFlags mask = 0;
    switch (keyCode) {
        case 56: case 60: mask = kCGEventFlagMaskShift; break;
        case 54: case 55: mask = kCGEventFlagMaskCommand; break;
        case 58: case 61: mask = kCGEventFlagMaskAlternate; break;
        case 59: case 62: mask = kCGEventFlagMaskControl; break;
        case 57: mask = kCGEventFlagMaskAlphaShift; break;
        case 63: mask = kCGEventFlagMaskSecondaryFn; break;
        default: return NO;
    }
    return (flags & mask) == 0;
}

- (ClackityKeyCategory)categoryForKeyCode:(int64_t)keyCode {
    switch (keyCode) {
        case 49: // Space
            return ClackityKeyCategorySpacebar;
            
        case 36: // Return
        case 76: // Numpad Enter
            return ClackityKeyCategoryEnter;
            
        case 51: // Delete/Backspace
        case 117: // Forward Delete
            return ClackityKeyCategoryBackspace;
            
        case 54: // Right Cmd
        case 55: // Left Cmd
        case 56: // Left Shift
        case 60: // Right Shift
        case 58: // Left Option
        case 61: // Right Option
        case 59: // Left Control
        case 62: // Right Control
        case 57: // CapsLock
        case 48: // Tab
        case 53: // Escape
            return ClackityKeyCategoryModifier;
            
        default:
            return ClackityKeyCategoryStandard;
    }
}

@end
