#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "SoundSynthesizer.h"
#import "SoundPackManager.h"

typedef NS_ENUM(NSInteger, ClackityRoomAcousticPreset) {
    ClackityRoomAcousticDirect = 0,       // Dry / Direct close mic
    ClackityRoomAcousticHardwoodDesk = 1, // Hardwood Desk reflection (Close Boundary)
    ClackityRoomAcousticStudioFoam = 2,   // Acoustic Studio Foam (Tight Chamber)
    ClackityRoomAcousticOpenLoft = 3      // Open Loft Room (Natural Air Reverb)
};

@interface AudioEngine : NSObject

@property (nonatomic, assign) ClackitySoundProfile currentProfile;
@property (nonatomic, strong) CustomSoundPack *customPack;
@property (nonatomic, assign) float masterVolume;
@property (nonatomic, assign) BOOL keySoundsEnabled;
@property (nonatomic, assign) BOOL keyUpSoundsEnabled;
@property (nonatomic, assign) BOOL mouseSoundsEnabled;
@property (nonatomic, assign) BOOL scrollSoundsEnabled;
@property (nonatomic, assign) BOOL muteModifiers;
@property (nonatomic, assign) BOOL spatialAudioEnabled;
@property (nonatomic, assign) BOOL isMeetingMuted;
@property (nonatomic, assign) float toneBalance; // -1.0 (Thock / PE Foam) to +1.0 (Clack / Brass Plate)
@property (nonatomic, assign) BOOL velocityDynamicsEnabled;
@property (nonatomic, assign) BOOL forceClickSoundEnabled;
@property (nonatomic, assign) BOOL typewriterModeEnabled;
@property (nonatomic, assign) BOOL typewriterBellEnabled;
@property (nonatomic, assign) BOOL typewriterRatchetEnabled;
@property (nonatomic, assign) BOOL typewriterReturnGlideEnabled;
@property (nonatomic, assign) BOOL typewriterMarginBellOnly;
@property (nonatomic, assign) NSInteger typewriterMarginLength;

// Acoustic Innovations Suite
@property (nonatomic, assign) BOOL keyPitchRowMappingEnabled;
@property (nonatomic, assign) BOOL krytoxLubeEnabled;
@property (nonatomic, assign) BOOL springPingEnabled;
@property (nonatomic, assign) ClackityRoomAcousticPreset roomAcousticPreset;

+ (instancetype)sharedEngine;

- (void)start;
- (void)stop;

- (void)playKeyWithCategory:(ClackityKeyCategory)category keyCode:(int64_t)keyCode isKeyUp:(BOOL)isKeyUp;
- (void)playKeyWithCategory:(ClackityKeyCategory)category isKeyUp:(BOOL)isKeyUp;
- (void)playMouseClick:(BOOL)isRightClick isUp:(BOOL)isUp;
- (void)playScroll;
- (void)playForceClickSound;
- (void)playTypewriterBell;
- (void)playTypewriterCarriageReturn;
- (void)playTypewriterRatchet;
- (void)playSpringPing;
- (void)toggleMute;

- (void)reloadBuffers;

@end
