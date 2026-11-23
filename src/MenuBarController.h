#import <Cocoa/Cocoa.h>

@interface MenuBarController : NSObject <NSMenuDelegate>

+ (instancetype)sharedController;

- (void)setupStatusItem;
- (void)updateStatusItem;
- (void)updateStatusItemTitle;

@end
