#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SettingsWindowController : NSWindowController

+ (instancetype)sharedController;

- (void)showSettingsWindow:(nullable id)sender;
- (void)selectTabAtIndex:(NSInteger)index;

@end

NS_ASSUME_NONNULL_END
