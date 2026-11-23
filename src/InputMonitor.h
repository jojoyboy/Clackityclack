#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import "SoundSynthesizer.h"

@protocol InputMonitorDelegate <NSObject>
@optional
- (void)inputMonitorDidDetectKeyWithCategory:(ClackityKeyCategory)category keyCode:(int64_t)keyCode isKeyUp:(BOOL)isKeyUp;
- (void)inputMonitorDidDetectKeyWithCategory:(ClackityKeyCategory)category isKeyUp:(BOOL)isKeyUp;
- (void)inputMonitorDidDetectMouseClickAtPoint:(CGPoint)screenPoint isRightClick:(BOOL)isRightClick isUp:(BOOL)isUp;
- (void)inputMonitorDidDetectScroll;
- (void)inputMonitorDidDetectForceClickAtPoint:(CGPoint)screenPoint;
- (void)inputMonitorDidTriggerGlobalMuteShortcut;
@end

@interface InputMonitor : NSObject

@property (nonatomic, weak) id<InputMonitorDelegate> delegate;
@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic, assign) BOOL secureInputProtectionEnabled;
@property (nonatomic, assign) BOOL forceClickSoundEnabled;

+ (instancetype)sharedMonitor;
+ (BOOL)isAccessibilityGranted;
+ (BOOL)isSecureEventInputActive;
+ (void)promptSystemAccessibilitySheet;
+ (void)openAccessibilitySettings;

- (BOOL)start;
- (void)stop;
- (BOOL)restart;

@end
