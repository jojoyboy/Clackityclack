#import "AudioEngine.h"
#import "HardwareMonitor.h"
#import <mach/mach_time.h>

#define VOICE_POOL_SIZE 24

@interface AudioEngine () {
    AVAudioEngine *_engine;
    AVAudioMixerNode *_mixerNode;
    AVAudioMixerNode *_subMixer;
    AVAudioUnitReverb *_reverbNode;
    AVAudioUnitEQ *_eqNode;
    NSMutableArray<AVAudioPlayerNode *> *_playerNodes;
    NSUInteger _currentPlayerIndex;
    
    // Cached buffers: key = "category_isKeyUp"
    NSMutableDictionary<NSString *, AVAudioPCMBuffer *> *_bufferCache;
    
    AVAudioPCMBuffer *_typewriterBellBuffer;
    AVAudioPCMBuffer *_typewriterReturnBuffer;
    AVAudioPCMBuffer *_typewriterRatchetBuffer;
    AVAudioPCMBuffer *_springPingBuffer;
    NSInteger _currentLineCharCount;
    BOOL _marginBellFired;
    
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
            @"typewriterReturnGlideEnabled": @YES,
            @"typewriterMarginBellOnly": @YES,
            @"typewriterMarginLength": @72,
            @"keyPitchRowMapping": @YES,
            @"krytoxLube": @NO,
            @"springPing": @NO,
            @"roomAcousticPreset": @(0),
        }];
        _typewriterModeEnabled = [defs boolForKey:@"typewriterModeEnabled"];
        _typewriterBellEnabled = [defs boolForKey:@"typewriterBellEnabled"];
        _typewriterRatchetEnabled = [defs boolForKey:@"typewriterRatchetEnabled"];
        _typewriterReturnGlideEnabled = [defs boolForKey:@"typewriterReturnGlideEnabled"];
        _typewriterMarginBellOnly = [defs boolForKey:@"typewriterMarginBellOnly"];
        _typewriterMarginLength = [defs integerForKey:@"typewriterMarginLength"] ?: 72;
        
        _keyPitchRowMappingEnabled = [defs boolForKey:@"keyPitchRowMapping"];
        _krytoxLubeEnabled = [defs boolForKey:@"krytoxLube"];
        _springPingEnabled = [defs boolForKey:@"springPing"];
        _roomAcousticPreset = (ClackityRoomAcousticPreset)[defs integerForKey:@"roomAcousticPreset"];
        
        _typewriterBellBuffer = [SoundSynthesizer typewriterMarginBellBuffer];
        _typewriterReturnBuffer = [SoundSynthesizer typewriterCarriageReturnBuffer];
        _typewriterRatchetBuffer = [SoundSynthesizer typewriterBackspaceRatchetBuffer];
        _springPingBuffer = [SoundSynthesizer springPingBuffer];
        _currentLineCharCount = 0;
        _marginBellFired = NO;
        
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
    
    // Spatial Room Acoustics Reverb Unit
    _reverbNode = [[AVAudioUnitReverb alloc] init];
    [_engine attachNode:_reverbNode];
    [self applyRoomAcousticPreset:_roomAcousticPreset];
    
    // Parametric Tone & Krytox Lube Filter (4-band CoreAudio DSP)
    _eqNode = [[AVAudioUnitEQ alloc] initWithNumberOfBands:4];
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
    
    // Band 2: Krytox scratch filter (2.6 kHz peak attenuator)
    AVAudioUnitEQFilterParameters *scratchBand = _eqNode.bands[2];
    scratchBand.filterType = AVAudioUnitEQFilterTypeParametric;
    scratchBand.frequency = 2600.0f;
    scratchBand.bandwidth = 1.2f;
    scratchBand.gain = 0.0f;
    scratchBand.bypass = YES;
    
    // Band 3: Krytox low-pass ceiling filter
    AVAudioUnitEQFilterParameters *cutoffBand = _eqNode.bands[3];
    cutoffBand.filterType = AVAudioUnitEQFilterTypeLowPass;
    cutoffBand.frequency = 7200.0f;
    cutoffBand.bypass = YES;
    
    [self applyToneBalance:_toneBalance];
    [self applyKrytoxLube:_krytoxLubeEnabled];
    
    AVAudioFormat *stereoFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:2];
    AVAudioFormat *monoFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:1];
    
    // Connect audio pipeline: subMixer -> reverbNode -> eqNode -> mixerNode
    [_engine connect:_subMixer to:_reverbNode format:stereoFormat];
    [_engine connect:_reverbNode to:_eqNode format:stereoFormat];
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

- (void)setKrytoxLubeEnabled:(BOOL)krytoxLubeEnabled {
    _krytoxLubeEnabled = krytoxLubeEnabled;
    [self applyKrytoxLube:krytoxLubeEnabled];
    [[NSUserDefaults standardUserDefaults] setBool:krytoxLubeEnabled forKey:@"krytoxLube"];
}

- (void)applyKrytoxLube:(BOOL)lubed {
    if (!_eqNode || _eqNode.bands.count < 4) return;
    
    AVAudioUnitEQFilterParameters *scratchBand = _eqNode.bands[2];
    AVAudioUnitEQFilterParameters *cutoffBand = _eqNode.bands[3];
    
    if (lubed) {
        // Krytox GPL 205g0: Dampens friction scratch (-5.5dB at 2600 Hz) and rounds harsh high clatter
        scratchBand.gain = -5.5f;
        scratchBand.bypass = NO;
        
        cutoffBand.filterType = AVAudioUnitEQFilterTypeLowPass;
        cutoffBand.frequency = 7200.0f;
        cutoffBand.bypass = NO;
    } else {
        scratchBand.gain = 0.0f;
        scratchBand.bypass = YES;
        cutoffBand.bypass = YES;
    }
}

- (void)setRoomAcousticPreset:(ClackityRoomAcousticPreset)roomAcousticPreset {
    _roomAcousticPreset = roomAcousticPreset;
    [self applyRoomAcousticPreset:roomAcousticPreset];
    [[NSUserDefaults standardUserDefaults] setInteger:roomAcousticPreset forKey:@"roomAcousticPreset"];
}

- (void)applyRoomAcousticPreset:(ClackityRoomAcousticPreset)preset {
    if (!_reverbNode) return;
    
    switch (preset) {
        case ClackityRoomAcousticHardwoodDesk:
            [_reverbNode loadFactoryPreset:AVAudioUnitReverbPresetSmallRoom];
            _reverbNode.wetDryMix = 18.0f;
            _reverbNode.bypass = NO;
            break;
            
        case ClackityRoomAcousticStudioFoam:
            [_reverbNode loadFactoryPreset:AVAudioUnitReverbPresetMediumChamber];
            _reverbNode.wetDryMix = 28.0f;
            _reverbNode.bypass = NO;
            break;
            
        case ClackityRoomAcousticOpenLoft:
            [_reverbNode loadFactoryPreset:AVAudioUnitReverbPresetLargeRoom];
            _reverbNode.wetDryMix = 40.0f;
            _reverbNode.bypass = NO;
            break;
            
        case ClackityRoomAcousticDirect:
        default:
            _reverbNode.wetDryMix = 0.0f;
            _reverbNode.bypass = YES;
            break;
    }
}

- (void)setKeyPitchRowMappingEnabled:(BOOL)keyPitchRowMappingEnabled {
    _keyPitchRowMappingEnabled = keyPitchRowMappingEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:keyPitchRowMappingEnabled forKey:@"keyPitchRowMapping"];
}

- (void)setSpringPingEnabled:(BOOL)springPingEnabled {
    _springPingEnabled = springPingEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:springPingEnabled forKey:@"springPing"];
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
        
        [self->_engine disconnectNodeOutput:self->_reverbNode];
        [self->_engine connect:self->_reverbNode to:self->_eqNode format:stereoFormat];
        
        [self->_engine disconnectNodeOutput:self->_subMixer];
        [self->_engine connect:self->_subMixer to:self->_reverbNode format:stereoFormat];
        
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

- (float)pitchMultiplierForKeyCode:(int64_t)keyCode {
    if (!_keyPitchRowMappingEnabled) return 1.0f;
    
    switch (keyCode) {
        // Row 0: Function & Esc keys (+8% crisp snap)
        case 53: // Esc
        case 122: case 120: case 99: case 118: case 96: case 97:
        case 98: case 100: case 101: case 109: case 103: case 111:
            return 1.08f;
            
        // Row 1: Number Row (`~` through `=`) (+5% higher pitch)
        case 50: // `~
        case 18: case 19: case 20: case 21: case 23: case 22:
        case 26: case 28: case 25: case 29: case 27: case 24:
            return 1.05f;
            
        // Row 2: Upper QWERTY Row (+2.5% slightly brighter)
        case 48: // Tab
        case 12: case 13: case 14: case 15: case 17: case 16:
        case 32: case 34: case 31: case 35: case 33: case 30: case 42:
            return 1.025f;
            
        // Row 3: Home ASDF Row (Reference 1.00x)
        case 57: // CapsLock
        case 0: case 1: case 2: case 3: case 5: case 4:
        case 38: case 40: case 37: case 41: case 39: case 36:
            return 1.00f;
            
        // Row 4: Lower ZXCV Row (-3.5% deeper thock)
        case 56: case 60: // Shift
        case 6: case 7: case 8: case 9: case 11:
        case 45: case 46: case 43: case 47: case 44:
            return 0.965f;
            
        // Row 5: Bottom Modifier & Spacebar Row (-8% deep cavity resonance)
        case 59: case 58: case 55: case 49: case 54: case 61: // Ctrl, Opt, Cmd, Space
        case 123: case 124: case 125: case 126: // Arrows
            return 0.92f;
            
        default:
            return 1.00f;
    }
}

- (AVAudioPCMBuffer *)pitchShiftBuffer:(AVAudioPCMBuffer *)srcBuffer ratio:(float)ratio {
    if (fabsf(ratio - 1.0f) < 0.005f || !srcBuffer) return srcBuffer;
    
    AVAudioFrameCount srcFrames = srcBuffer.frameLength;
    if (srcFrames == 0) return srcBuffer;
    
    AVAudioFrameCount destFrames = (AVAudioFrameCount)roundf((float)srcFrames / ratio);
    if (destFrames == 0) return srcBuffer;
    
    AVAudioFormat *format = srcBuffer.format;
    AVAudioPCMBuffer *destBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:destFrames];
    destBuffer.frameLength = destFrames;
    
    float *src = srcBuffer.floatChannelData[0];
    float *dest = destBuffer.floatChannelData[0];
    
    for (AVAudioFrameCount i = 0; i < destFrames; i++) {
        float srcPos = (float)i * ratio;
        AVAudioFrameCount idx0 = (AVAudioFrameCount)srcPos;
        if (idx0 >= srcFrames - 1) {
            dest[i] = src[srcFrames - 1];
        } else {
            float frac = srcPos - (float)idx0;
            dest[i] = src[idx0] + frac * (src[idx0 + 1] - src[idx0]);
        }
    }
    
    return destBuffer;
}

- (void)playSpringPing {
    if (!_springPingBuffer || _isMeetingMuted || _isGamingMuted || [[HardwareMonitor sharedMonitor] shouldMuteAudio]) return;
    dispatch_async(_audioQueue, ^{
        AVAudioPlayerNode *player = self->_playerNodes[self->_currentPlayerIndex];
        self->_currentPlayerIndex = (self->_currentPlayerIndex + 1) % VOICE_POOL_SIZE;
        player.pan = 0.0f;
        player.volume = self->_masterVolume * 0.40f;
        [player scheduleBuffer:self->_springPingBuffer atTime:nil options:AVAudioPlayerNodeBufferInterrupts completionHandler:nil];
        if (!player.isPlaying) {
            [player play];
        }
    });
}

- (void)playBufferWithCategory:(ClackityKeyCategory)category keyCode:(int64_t)keyCode isKeyUp:(BOOL)isKeyUp {
    if (_isMeetingMuted || _isGamingMuted || [[HardwareMonitor sharedMonitor] shouldMuteAudio]) return;
    if (!_keySoundsEnabled && category <= ClackityKeyCategoryModifier) return;
    if (isKeyUp && !_keyUpSoundsEnabled) return;
    if (category == ClackityKeyCategoryModifier && _muteModifiers) return;
    
    int variant = arc4random_uniform(4);
    NSString *cacheKey = [NSString stringWithFormat:@"%ld_%d_%d", (long)category, isKeyUp ? 1 : 0, variant];
    
    float pan = _spatialAudioEnabled ? [self panForKeyCode:keyCode] : 0.0f;
    float rowPitchRatio = (category <= ClackityKeyCategoryModifier) ? [self pitchMultiplierForKeyCode:keyCode] : 1.0f;
    
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
        
        // Apply key-pitch row mapping (resample buffer to geometric row pitch)
        if (fabsf(rowPitchRatio - 1.0f) > 0.005f) {
            buffer = [self pitchShiftBuffer:buffer ratio:rowPitchRatio];
        }
        
        // Grab next player in pool
        AVAudioPlayerNode *player = self->_playerNodes[self->_currentPlayerIndex];
        self->_currentPlayerIndex = (self->_currentPlayerIndex + 1) % VOICE_POOL_SIZE;
        
        // Apply spatial pan (left/right hand audio positioning)
        if (self->_spatialAudioEnabled) {
            player.pan = pan;
        } else {
            player.pan = 0.0f;
        }
        
        // Micro-gain dynamic acoustic randomization + velocity strike + hardware-aware scaling
        float hwScale = [[HardwareMonitor sharedMonitor] volumeMultiplier];
        float randomVolumeVariance = 0.94f + (float)arc4random_uniform(120) / 1000.0f; // 0.94 - 1.06
        player.volume = self->_masterVolume * randomVolumeVariance * velocityMultiplier * hwScale;
        
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

- (void)setTypewriterReturnGlideEnabled:(BOOL)typewriterReturnGlideEnabled {
    _typewriterReturnGlideEnabled = typewriterReturnGlideEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:typewriterReturnGlideEnabled forKey:@"typewriterReturnGlideEnabled"];
}

- (void)setTypewriterMarginBellOnly:(BOOL)typewriterMarginBellOnly {
    _typewriterMarginBellOnly = typewriterMarginBellOnly;
    [[NSUserDefaults standardUserDefaults] setBool:typewriterMarginBellOnly forKey:@"typewriterMarginBellOnly"];
}

- (void)setTypewriterMarginLength:(NSInteger)typewriterMarginLength {
    _typewriterMarginLength = typewriterMarginLength;
    [[NSUserDefaults standardUserDefaults] setInteger:typewriterMarginLength forKey:@"typewriterMarginLength"];
}

- (void)playTypewriterBell {
    if (!_typewriterBellBuffer || _isMeetingMuted || _isGamingMuted) return;
    dispatch_async(_audioQueue, ^{
        AVAudioPlayerNode *player = self->_playerNodes[self->_currentPlayerIndex];
        self->_currentPlayerIndex = (self->_currentPlayerIndex + 1) % VOICE_POOL_SIZE;
        // In physical typewriters, the margin bell is mounted on the far right carriage rail
        player.pan = self->_spatialAudioEnabled ? 0.35f : 0.0f;
        player.volume = self->_masterVolume * 0.90f;
        [player scheduleBuffer:self->_typewriterBellBuffer atTime:nil options:AVAudioPlayerNodeBufferInterrupts completionHandler:nil];
        if (!player.isPlaying) {
            [player play];
        }
    });
}

- (void)playTypewriterCarriageReturn {
    if (!_typewriterReturnBuffer || _isMeetingMuted || _isGamingMuted) return;
    dispatch_async(_audioQueue, ^{
        AVAudioPlayerNode *player = self->_playerNodes[self->_currentPlayerIndex];
        self->_currentPlayerIndex = (self->_currentPlayerIndex + 1) % VOICE_POOL_SIZE;
        // Carriage return physically slides the carriage across from right to left
        player.pan = self->_spatialAudioEnabled ? -0.15f : 0.0f;
        player.volume = self->_masterVolume * 0.95f;
        [player scheduleBuffer:self->_typewriterReturnBuffer atTime:nil options:AVAudioPlayerNodeBufferInterrupts completionHandler:nil];
        if (!player.isPlaying) {
            [player play];
        }
    });
}

- (void)playTypewriterRatchet {
    if (!_typewriterRatchetBuffer || _isMeetingMuted || _isGamingMuted) return;
    dispatch_async(_audioQueue, ^{
        AVAudioPlayerNode *player = self->_playerNodes[self->_currentPlayerIndex];
        self->_currentPlayerIndex = (self->_currentPlayerIndex + 1) % VOICE_POOL_SIZE;
        player.pan = self->_spatialAudioEnabled ? 0.20f : 0.0f;
        player.volume = self->_masterVolume * 0.85f;
        [player scheduleBuffer:self->_typewriterRatchetBuffer atTime:nil options:AVAudioPlayerNodeBufferInterrupts completionHandler:nil];
        if (!player.isPlaying) {
            [player play];
        }
    });
}

- (void)playKeyWithCategory:(ClackityKeyCategory)category keyCode:(int64_t)keyCode isKeyUp:(BOOL)isKeyUp {
    [self playBufferWithCategory:category keyCode:keyCode isKeyUp:isKeyUp];
    
    // Helical Spring Ping Resonance on Switch Release (KeyUp)
    if (isKeyUp && _springPingEnabled && !_isMeetingMuted && !_isGamingMuted && _keySoundsEnabled && category <= ClackityKeyCategoryModifier) {
        [self playSpringPing];
    }
    
    // Authentic Vintage Typewriter Mechanics
    if (_typewriterModeEnabled && !isKeyUp && !_isMeetingMuted && !_isGamingMuted && _keySoundsEnabled) {
        if (category == ClackityKeyCategoryEnter) {
            // Carriage Return on Enter
            if (_typewriterReturnGlideEnabled) {
                [self playTypewriterCarriageReturn];
            }
            if (!_typewriterMarginBellOnly && _typewriterBellEnabled) {
                [self playTypewriterBell];
            }
            _currentLineCharCount = 0;
            _marginBellFired = NO;
        } else if (category == ClackityKeyCategoryBackspace) {
            if (_typewriterRatchetEnabled) {
                [self playTypewriterRatchet];
            }
            if (_currentLineCharCount > 0) {
                _currentLineCharCount--;
            }
            if (_currentLineCharCount < _typewriterMarginLength) {
                _marginBellFired = NO;
            }
        } else if (category <= ClackityKeyCategoryModifier) {
            _currentLineCharCount++;
            if (_typewriterBellEnabled && !_marginBellFired && _currentLineCharCount >= _typewriterMarginLength) {
                _marginBellFired = YES;
                [self playTypewriterBell];
            }
        }
    }
}

- (void)playKeyWithCategory:(ClackityKeyCategory)category isKeyUp:(BOOL)isKeyUp {
    [self playBufferWithCategory:category keyCode:49 isKeyUp:isKeyUp];
}

- (void)playMouseClick:(BOOL)isRightClick isUp:(BOOL)isUp {
    if (_isMeetingMuted || _isGamingMuted || !_mouseSoundsEnabled) return;
    ClackityKeyCategory cat = isRightClick ? ClackityKeyCategoryMouseRight : ClackityKeyCategoryMouseLeft;
    int64_t dummyCode = isRightClick ? 36 : 48; // slight spatial stereo offset for mouse buttons
    [self playBufferWithCategory:cat keyCode:dummyCode isKeyUp:isUp];
}

- (void)playScroll {
    if (_isMeetingMuted || _isGamingMuted || !_scrollSoundsEnabled) return;
    [self playBufferWithCategory:ClackityKeyCategoryMouseScroll keyCode:49 isKeyUp:NO];
}

- (void)playForceClickSound {
    if (_isMeetingMuted || _isGamingMuted || !_mouseSoundsEnabled || !_forceClickSoundEnabled) return;
    [self playBufferWithCategory:ClackityKeyCategoryEnter keyCode:36 isKeyUp:NO];
}

- (void)toggleMute {
    _keySoundsEnabled = !_keySoundsEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:_keySoundsEnabled forKey:@"keySoundsEnabled"];
}

@end
