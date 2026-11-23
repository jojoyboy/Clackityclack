#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, ClackityRippleColor) {
    ClackityRippleColorElectricCyan = 0,
    ClackityRippleColorMinimalWhite = 1,
    ClackityRippleColorWarmAmber = 2,
    ClackityRippleColorRosePink = 3,
    ClackityRippleColorEmeraldGreen = 4
};

@interface RippleOverlay : NSObject

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) ClackityRippleColor colorTheme;

+ (instancetype)sharedOverlay;
+ (NSString *)nameForRippleColor:(ClackityRippleColor)theme;

- (void)showRippleAtScreenPoint:(CGPoint)cgPoint isRightClick:(BOOL)isRightClick;

@end
