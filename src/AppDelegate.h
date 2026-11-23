#import <Cocoa/Cocoa.h>
#import "InputMonitor.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, InputMonitorDelegate>

@property (nonatomic, assign) BOOL autoMuteInMeetingsEnabled;
@property (nonatomic, assign) BOOL contextAwareProfilesEnabled;
@property (nonatomic, assign) NSInteger menuBarDisplayStyle; // 0: Icon Only, 1: Icon + Clacks, 2: Icon + WPM
@property (nonatomic, readonly) NSUInteger sessionClackCount;
@property (nonatomic, readonly) NSUInteger currentWPM;

- (void)resetSessionStats;

@end
