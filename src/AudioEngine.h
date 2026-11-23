#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "SoundSynthesizer.h"
#import "SoundPackManager.h"

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

+ (instancetype)sharedEngine;

- (void)start;
- (void)stop;

- (void)playKeyWithCategory:(ClackityKeyCategory)category keyCode:(int64_t)keyCode isKeyUp:(BOOL)isKeyUp;
- (void)playKeyWithCategory:(ClackityKeyCategory)category isKeyUp:(BOOL)isKeyUp;
- (void)playMouseClick:(BOOL)isRightClick isUp:(BOOL)isUp;
- (void)playScroll;
- (void)playForceClickSound;
- (void)playTypewriterBell;
- (void)playTypewriterRatchet;
- (void)toggleMute;

- (void)reloadBuffers;

@end
