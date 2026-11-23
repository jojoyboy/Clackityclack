#import "AudioEngine.h"
#import <mach/mach_time.h>

#define VOICE_POOL_SIZE 24

@interface AudioEngine () {
    AVAudioEngine *_engine;
    AVAudioMixerNode *_mixerNode;
    AVAudioMixerNode *_subMixer;
    AVAudioUnitEQ *_eqNode;
    NSMutableArray<AVAudioPlayerNode *> *_playerNodes;
    NSUInteger _currentPlayerIndex;
    
    // Cached buffers: key = "category_isKeyUp"
    NSMutableDictionary<NSString *, AVAudioPCMBuffer *> *_bufferCache;
    
    AVAudioPCMBuffer *_typewriterBellBuffer;
    AVAudioPCMBuffer *_typewriterRatchetBuffer;
    
    dispatch_queue_t _audioQueue;
}
@end

@implementation AudioEngine

+ (instancetype)sharedEngine {
    static AudioEngine *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AudioEngine alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _currentProfile = ClackitySoundProfileGateronOilKing;
        _masterVolume = 0.85f;
        _keySoundsEnabled = YES;
        _keyUpSoundsEnabled = YES;
        _mouseSoundsEnabled = YES;
        _scrollSoundsEnabled = YES;
        _muteModifiers = NO;
        _toneBalance = 0.0f;
        _velocityDynamicsEnabled = YES;
        _forceClickSoundEnabled = YES;
        
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        [defs registerDefaults:@{
            @"typewriterModeEnabled": @NO,
            @"typewriterBellEnabled": @YES,
            @"typewriterRatchetEnabled": @YES,
        }];
        _typewriterModeEnabled = [defs boolForKey:@"typewriterModeEnabled"];
        _typewriterBellEnabled = [defs boolForKey:@"typewriterBellEnabled"];
        _typewriterRatchetEnabled = [defs boolForKey:@"typewriterRatchetEnabled"];
        
        _typewriterBellBuffer = [SoundSynthesizer typewriterCarriageReturnBellBuffer];
        _typewriterRatchetBuffer = [SoundSynthesizer typewriterRatchetBuffer];
        
        _audioQueue = dispatch_queue_create("com.clackity.audio", DISPATCH_QUEUE_SERIAL);
        _bufferCache = [NSMutableDictionary dictionary];
        
        [self setupAudioEngine];
        [self reloadBuffers];
    }
    return self;
}

- (void)setupAudioEngine {
    _engine = [[AVAudioEngine alloc] init];
    _mixerNode = _engine.mainMixerNode;
    _mixerNode.outputVolume = _masterVolume;
    
    // Intermediate mixer: allows individual voice panning and unlimited voice inputs
    _subMixer = [[AVAudioMixerNode alloc] init];
    [_engine attachNode:_subMixer];
    
    // Parametric Tone Filter: Thock (PE Foam) <---> Clack (Brass Plate)
    _eqNode = [[AVAudioUnitEQ alloc] initWithNumberOfBands:2];
    [_engine attachNode:_eqNode];
    
    AVAudioUnitEQFilterParameters *lowBand = _eqNode.bands[0];
    lowBand.filterType = AVAudioUnitEQFilterTypeLowShelf;
    lowBand.frequency = 320.0f; // 320 Hz deep body acoustic
    lowBand.bandwidth = 1.0f;
    lowBand.bypass = NO;
    
    AVAudioUnitEQFilterParameters *highBand = _eqNode.bands[1];
    highBand.filterType = AVAudioUnitEQFilterTypeHighShelf;
    highBand.frequency = 3800.0f; // 3.8 kHz switch actuation snap
    highBand.bandwidth = 1.0f;
    highBand.bypass = NO;
    
    [self applyToneBalance:_toneBalance];
    
    AVAudioFormat *stereoFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
    AVAudioFormat *monoFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:1];
    
    // Connect audio pipeline: subMixer -> eqNode -> mainMixerNode
    [_engine connect:_subMixer to:_eqNode format:stereoFormat];
    [_engine connect:_eqNode to:_mixerNode format:stereoFormat];
    
    _playerNodes = [NSMutableArray arrayWithCapacity:VOICE_POOL_SIZE];
    for (int i = 0; i < VOICE_POOL_SIZE; i++) {
        AVAudioPlayerNode *player = [[AVAudioPlayerNode alloc] init];
        [_engine attachNode:player];
        [_engine connect:player to:_subMixer format:monoFormat];
        [_playerNodes addObject:player];
    }
    _currentPlayerIndex = 0;
    
    // Automatically restart engine when output audio route changes (headphones, AirPods, Bluetooth)
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleEngineConfigurationChange:)
                                                 name:AVAudioEngineConfigurationChangeNotification
                                               object:_engine];
}

- (void)setToneBalance:(float)toneBalance {
    _toneBalance = fmaxf(-1.0f, fminf(1.0f, toneBalance));
    [self applyToneBalance:_toneBalance];
}

- (void)applyToneBalance:(float)tone {
    if (!_eqNode || _eqNode.bands.count < 2) return;
    
    AVAudioUnitEQFilterParameters *lowBand = _eqNode.bands[0];
    AVAudioUnitEQFilterParameters *highBand = _eqNode.bands[1];
    
    if (fabsf(tone) < 0.05f) {
        lowBand.gain = 0.0f;
        highBand.gain = 0.0f;
    } else if (tone < 0) {
        // Thock (Foam Mod): boost warmth (+8dB) and soften highs (-6dB)
        float t = -tone;
        lowBand.gain = t * 8.0f;
        highBand.gain = -t * 6.0f;
    } else {
        // Clack (Brass/Polycarbonate): tighten lows and boost crisp snap (+7.5dB)
        float t = tone;
        lowBand.gain = -t * 3.0f;
        highBand.gain = t * 7.5f;
    }
}

- (void)handleEngineConfigurationChange:(NSNotification *)notification {
    dispatch_async(_audioQueue, ^{
        NSError *error = nil;
        if ([self->_engine isRunning]) {
            [self->_engine stop];
        }
        
        AVAudioFormat *stereoFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
        AVAudioFormat *monoFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:1];
        
        [self->_engine disconnectNodeOutput:self->_eqNode];
        [self->_engine connect:self->_eqNode to:self->_mixerNode format:stereoFormat];
        
        [self->_engine disconnectNodeOutput:self->_subMixer];
        [self->_engine connect:self->_subMixer to:self->_eqNode format:stereoFormat];
        
        for (AVAudioPlayerNode *player in self->_playerNodes) {
            [self->_engine disconnectNodeOutput:player];
            [self->_engine connect:player to:self->_subMixer format:monoFormat];
        }
        
        [self->_engine startAndReturnError:&error];
        if (!error) {
            for (AVAudioPlayerNode *player in self->_playerNodes) {
                @try {
                    if (!player.isPlaying) {
                        [player play];
                    }
                } @catch (NSException *e) {
                    // Suppress and continue
                }
            }
        }
    });
}

- (void)start {
    NSError *error = nil;
    if (![_engine isRunning]) {
        [_engine startAndReturnError:&error];
        if (error) {
            NSLog(@"[Clackity] Audio engine start error: %@", error);
        } else {
            for (AVAudioPlayerNode *player in _playerNodes) {
                @try {
                    if (!player.isPlaying) {
                        [player play];
                    }
                } @catch (NSException *e) {
                    // Node ready on next scheduleBuffer
                }
            }
        }
    }
}

- (void)stop {
    if ([_engine isRunning]) {
        [_engine stop];
    }
}

- (void)setMasterVolume:(float)masterVolume {
    _masterVolume = masterVolume;
    _mixerNode.outputVolume = masterVolume;
}

- (void)setCurrentProfile:(ClackitySoundProfile)currentProfile {
    _currentProfile = currentProfile;
    [self reloadBuffers];
}

- (void)reloadBuffers {
    dispatch_async(_audioQueue, ^{
        [self->_bufferCache removeAllObjects];
        
        // Cache combinations of category and KeyDown/KeyUp
        NSArray *categories = @[
            @(ClackityKeyCategoryStandard),
            @(ClackityKeyCategorySpacebar),
            @(ClackityKeyCategoryEnter),
            @(ClackityKeyCategoryBackspace),
            @(ClackityKeyCategoryModifier),
            @(ClackityKeyCategoryMouseLeft),
            @(ClackityKeyCategoryMouseRight),
            @(ClackityKeyCategoryMouseScroll)
        ];
        
        for (NSNumber *catNum in categories) {
            ClackityKeyCategory cat = (ClackityKeyCategory)[catNum integerValue];
            
            // Pre-cache 4 micro-variations for KeyDown & KeyUp
            for (int v = 0; v < 4; v++) {
                AVAudioPCMBuffer *downBuf = [SoundSynthesizer bufferForProfile:self->_currentProfile
                                                                      category:cat
                                                                       isKeyUp:NO
                                                                     variation:v];
                if (downBuf) {
                    self->_bufferCache[[NSString stringWithFormat:@"%ld_0_%d", (long)cat, v]] = downBuf;
                }
                
                AVAudioPCMBuffer *upBuf = [SoundSynthesizer bufferForProfile:self->_currentProfile
                                                                    category:cat
                                                                     isKeyUp:YES
                                                                   variation:v];
                if (upBuf) {
                    self->_bufferCache[[NSString stringWithFormat:@"%ld_1_%d", (long)cat, v]] = upBuf;
                }
            }
        }
    });
}

- (float)panForKeyCode:(int64_t)keyCode {
    switch (keyCode) {
        // Far Left
        case 50: case 18: case 12: case 0: case 6: case 48: case 57: case 56: case 59:
            return -0.35f;
        // Mid-Left
        case 19: case 13: case 1: case 7:
            return -0.25f;
        case 20: case 14: case 2: case 8:
            return -0.15f;
        case 21: case 23: case 15: case 3: case 9:
            return -0.07f;
            
        // Center
        case 22: case 17: case 5: case 11: case 49:
            return 0.0f;
            
        // Mid-Right
        case 26: case 16: case 4: case 45:
            return 0.07f;
        case 28: case 32: case 38: case 46:
            return 0.15f;
        case 25: case 34: case 40: case 43:
            return 0.22f;
        case 29: case 31: case 37: case 47:
            return 0.28f;
        // Far Right
        case 27: case 24: case 35: case 33: case 30: case 42: case 41: case 39: case 44: case 36: case 51: case 60:
            return 0.35f;
            
        default:
            return 0.0f;
    }
}

- (void)playBufferWithCategory:(ClackityKeyCategory)category keyCode:(int64_t)keyCode isKeyUp:(BOOL)isKeyUp {
    if (_isMeetingMuted) return;
    if (!_keySoundsEnabled && category <= ClackityKeyCategoryModifier) return;
    if (isKeyUp && !_keyUpSoundsEnabled) return;
    if (category == ClackityKeyCategoryModifier && _muteModifiers) return;
    
    int variant = arc4random_uniform(4);
    NSString *cacheKey = [NSString stringWithFormat:@"%ld_%d_%d", (long)category, isKeyUp ? 1 : 0, variant];
    
    float pan = _spatialAudioEnabled ? [self panForKeyCode:keyCode] : 0.0f;
    
    // Dynamic Typing Velocity & Strike Momentum
    float velocityMultiplier = 1.0f;
    if (_velocityDynamicsEnabled && !isKeyUp && category <= ClackityKeyCategoryModifier) {
        static uint64_t lastKeyTime = 0;
        static mach_timebase_info_data_t tb;
        if (tb.denom == 0) mach_timebase_info(&tb);
        
        uint64_t now = mach_absolute_time();
        if (lastKeyTime > 0) {
            uint64_t deltaNs = (now - lastKeyTime) * tb.numer / tb.denom;
            double deltaMs = deltaNs / 1000000.0;
            
            if (deltaMs < 130.0) {
                // Fast flow-state typing burst (<130ms between keys): punchier bottom-out (+5% to +15% volume)
                float ratio = (float)(1.0 - (deltaMs / 130.0));
                velocityMultiplier = 1.0f + (ratio * 0.15f);
            } else if (deltaMs > 400.0) {
                // Slower deliberate typing: softer key glide
                velocityMultiplier = 0.90f;
            }
        }
        lastKeyTime = now;
    }
    
    dispatch_async(_audioQueue, ^{
        AVAudioPCMBuffer *buffer = nil;
        if (self->_customPack) {
            buffer = [self->_customPack bufferForCategory:category isKeyUp:isKeyUp];
        }
        if (!buffer) {
            buffer = self->_bufferCache[cacheKey];
        }
        if (!buffer) return;
        
        // Grab next player in pool
        AVAudioPlayerNode *player = self->_playerNodes[self->_currentPlayerIndex];
        self->_currentPlayerIndex = (self->_currentPlayerIndex + 1) % VOICE_POOL_SIZE;
        
        // Apply spatial pan (left/right hand audio positioning)
        if (self->_spatialAudioEnabled) {
            player.pan = pan;
        } else {
            player.pan = 0.0f;
        }
        
        // Micro-gain dynamic acoustic randomization + velocity strike
        float randomVolumeVariance = 0.94f + (float)arc4random_uniform(120) / 1000.0f; // 0.94 - 1.06
        player.volume = self->_masterVolume * randomVolumeVariance * velocityMultiplier;
        
        // Schedule and trigger buffer
        [player scheduleBuffer:buffer atTime:nil options:AVAudioPlayerNodeBufferInterrupts completionHandler:nil];
        if (!player.isPlaying) {
            [player play];
        }
    });
}

- (void)setTypewriterModeEnabled:(BOOL)typewriterModeEnabled {
    _typewriterModeEnabled = typewriterModeEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:typewriterModeEnabled forKey:@"typewriterModeEnabled"];
}

- (void)setTypewriterBellEnabled:(BOOL)typewriterBellEnabled {
    _typewriterBellEnabled = typewriterBellEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:typewriterBellEnabled forKey:@"typewriterBellEnabled"];
}

- (void)setTypewriterRatchetEnabled:(BOOL)typewriterRatchetEnabled {
    _typewriterRatchetEnabled = typewriterRatchetEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:typewriterRatchetEnabled forKey:@"typewriterRatchetEnabled"];
}

- (void)playTypewriterBell {
    if (!_typewriterBellBuffer || _isMeetingMuted) return;
    dispatch_async(_audioQueue, ^{
        AVAudioPlayerNode *player = self->_playerNodes[self->_currentPlayerIndex];
        self->_currentPlayerIndex = (self->_currentPlayerIndex + 1) % VOICE_POOL_SIZE;
        // In physical typewriters, the margin bell is mounted on the far right carriage rail
        player.pan = self->_spatialAudioEnabled ? 0.35f : 0.0f;
        player.volume = self->_masterVolume * 0.95f;
        [player scheduleBuffer:self->_typewriterBellBuffer atTime:nil options:AVAudioPlayerNodeBufferInterrupts completionHandler:nil];
        if (!player.isPlaying) {
            [player play];
        }
    });
}

- (void)playTypewriterRatchet {
    if (!_typewriterRatchetBuffer || _isMeetingMuted) return;
    dispatch_async(_audioQueue, ^{
        AVAudioPlayerNode *player = self->_playerNodes[self->_currentPlayerIndex];
        self->_currentPlayerIndex = (self->_currentPlayerIndex + 1) % VOICE_POOL_SIZE;
        player.pan = self->_spatialAudioEnabled ? 0.25f : 0.0f;
        player.volume = self->_masterVolume * 0.90f;
        [player scheduleBuffer:self->_typewriterRatchetBuffer atTime:nil options:AVAudioPlayerNodeBufferInterrupts completionHandler:nil];
        if (!player.isPlaying) {
            [player play];
        }
    });
}

- (void)playKeyWithCategory:(ClackityKeyCategory)category keyCode:(int64_t)keyCode isKeyUp:(BOOL)isKeyUp {
    [self playBufferWithCategory:category keyCode:keyCode isKeyUp:isKeyUp];
    
    // Vintage Typewriter Mechanical Overlays
    if (_typewriterModeEnabled && !isKeyUp && !_isMeetingMuted && _keySoundsEnabled) {
        if (category == ClackityKeyCategoryEnter && _typewriterBellEnabled) {
            [self playTypewriterBell];
        } else if (category == ClackityKeyCategoryBackspace && _typewriterRatchetEnabled) {
            [self playTypewriterRatchet];
        }
    }
}

- (void)playKeyWithCategory:(ClackityKeyCategory)category isKeyUp:(BOOL)isKeyUp {
    [self playBufferWithCategory:category keyCode:49 isKeyUp:isKeyUp];
}

- (void)playMouseClick:(BOOL)isRightClick isUp:(BOOL)isUp {
    if (_isMeetingMuted || !_mouseSoundsEnabled) return;
    ClackityKeyCategory cat = isRightClick ? ClackityKeyCategoryMouseRight : ClackityKeyCategoryMouseLeft;
    int64_t dummyCode = isRightClick ? 36 : 48; // slight spatial stereo offset for mouse buttons
    [self playBufferWithCategory:cat keyCode:dummyCode isKeyUp:isUp];
}

- (void)playScroll {
    if (_isMeetingMuted || !_scrollSoundsEnabled) return;
    [self playBufferWithCategory:ClackityKeyCategoryMouseScroll keyCode:49 isKeyUp:NO];
}

- (void)playForceClickSound {
    if (_isMeetingMuted || !_mouseSoundsEnabled || !_forceClickSoundEnabled) return;
    [self playBufferWithCategory:ClackityKeyCategoryEnter keyCode:36 isKeyUp:NO];
}

- (void)toggleMute {
    _keySoundsEnabled = !_keySoundsEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:_keySoundsEnabled forKey:@"keySoundsEnabled"];
}

@end
