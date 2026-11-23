#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

typedef NS_ENUM(NSInteger, ClackitySoundProfile) {
    // Custom Mechanical Switch Profiles
    ClackitySoundProfileGateronOilKing = 0,   // Deep Thock Linear
    ClackitySoundProfileBobaU4T = 1,          // Thocky Tactile (D-Bump)
    ClackitySoundProfileHolyPanda = 2,        // Snappy Pop Tactile
    ClackitySoundProfileAlpaca = 3,           // Marbly High-Pitched Linear
    ClackitySoundProfileTopre = 4,            // Electro-Capacitive Silent (HHKB)
    ClackitySoundProfileNKCream = 5,          // POM Creamy Linear
    ClackitySoundProfileCherryMXBlack = 6,    // Vintage Hyperglide Nylon
    ClackitySoundProfileKailhBoxWhite = 7,    // Precision Click-Bar
    ClackitySoundProfileModelM = 8,           // IBM Buckling Spring
    ClackitySoundProfileAppleALPS = 9,        // Vintage Apple Extended Keyboard (ALPS)
    
    // Retro & Novelty
    ClackitySoundProfileTypewriter = 10,      // Mechanical Typewriter
    ClackitySoundProfilePop = 11              // Modern Bubble Pop (ASMR)
};

typedef NS_ENUM(NSInteger, ClackityKeyCategory) {
    ClackityKeyCategoryStandard = 0,
    ClackityKeyCategorySpacebar = 1,
    ClackityKeyCategoryEnter = 2,
    ClackityKeyCategoryBackspace = 3,
    ClackityKeyCategoryModifier = 4,
    ClackityKeyCategoryMouseLeft = 5,
    ClackityKeyCategoryMouseRight = 6,
    ClackityKeyCategoryMouseScroll = 7
};

@interface SoundSynthesizer : NSObject

+ (AVAudioPCMBuffer *)bufferForProfile:(ClackitySoundProfile)profile
                              category:(ClackityKeyCategory)category
                               isKeyUp:(BOOL)isKeyUp
                             variation:(NSInteger)variation;

+ (NSString *)nameForProfile:(ClackitySoundProfile)profile;
+ (NSString *)subtitleForProfile:(ClackitySoundProfile)profile;
+ (NSArray<NSNumber *> *)allProfiles;

// Vintage Typewriter Acoustics
+ (AVAudioPCMBuffer *)typewriterCarriageReturnBellBuffer;
+ (AVAudioPCMBuffer *)typewriterRatchetBuffer;

@end
