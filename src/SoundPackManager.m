#import "SoundPackManager.h"

@implementation CustomSoundPack

- (instancetype)initWithName:(NSString *)name folderPath:(NSString *)folderPath {
    self = [super init];
    if (self) {
        _name = name;
        _folderPath = folderPath;
        _buffers = [NSMutableDictionary dictionary];
    }
    return self;
}

- (AVAudioPCMBuffer *)loadBufferFromFileNames:(NSArray<NSString *> *)candidates {
    NSFileManager *fm = [NSFileManager defaultManager];
    AVAudioFormat *standardFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100.0 channels:1];
    
    for (NSString *name in candidates) {
        NSArray<NSString *> *searchPaths = @[
            [_folderPath stringByAppendingPathComponent:name],
            [_folderPath stringByAppendingPathComponent:[@"press" stringByAppendingPathComponent:name]],
            [_folderPath stringByAppendingPathComponent:[@"release" stringByAppendingPathComponent:name]]
        ];
        
        for (NSString *path in searchPaths) {
            if ([fm fileExistsAtPath:path]) {
                NSURL *url = [NSURL fileURLWithPath:path];
                NSError *error = nil;
                AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&error];
                if (file && !error) {
                    AVAudioFormat *srcFormat = file.processingFormat;
                    AVAudioFrameCount capacity = (AVAudioFrameCount)file.length;
                    AVAudioPCMBuffer *srcBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:srcFormat frameCapacity:capacity];
                    if (![file readIntoBuffer:srcBuffer error:&error]) continue;
                    
                    if (srcFormat.sampleRate == 44100.0 && srcFormat.channelCount == 1) {
                        return srcBuffer;
                    }
                    
                    AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:srcFormat toFormat:standardFormat];
                    if (converter) {
                        double ratio = 44100.0 / srcFormat.sampleRate;
                        AVAudioFrameCount dstCapacity = (AVAudioFrameCount)(capacity * ratio) + 100;
                        AVAudioPCMBuffer *dstBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:standardFormat frameCapacity:dstCapacity];
                        
                        NSError *convError = nil;
                        [converter convertToBuffer:dstBuffer error:&convError withInputFromBlock:^AVAudioBuffer * _Nullable(AVAudioFrameCount inNumberOfFrames, AVAudioConverterInputStatus * _Nonnull outStatus) {
                            *outStatus = AVAudioConverterInputStatus_HaveData;
                            return srcBuffer;
                        }];
                        
                        if (!convError && dstBuffer.frameLength > 0) {
                            return dstBuffer;
                        }
                    }
                    return srcBuffer;
                }
            }
        }
    }
    return nil;
}

- (BOOL)loadBuffers {
    [_buffers removeAllObjects];
    
    // Check for config.json (Mechvibes / Klack format)
    NSString *configPath = [_folderPath stringByAppendingPathComponent:@"config.json"];
    NSData *configData = [NSData dataWithContentsOfFile:configPath];
    NSDictionary *defines = nil;
    NSArray *defaults = nil;
    if (configData) {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:configData options:0 error:nil];
        if ([json isKindOfClass:[NSDictionary class]]) {
            NSString *customName = json[@"name"];
            if (customName.length > 0) {
                _name = customName;
            }
            defines = json[@"defines"] ?: json[@"mappings"];
            defaults = json[@"defaults"];
        }
    }
    
    // Check defines/mappings from config.json first
    if ([defines isKindOfClass:[NSDictionary class]]) {
        // Space
        NSString *sp = defines[@"57"] ?: defines[@"SPACE"];
        if ([sp isKindOfClass:[NSString class]]) {
            AVAudioPCMBuffer *b = [self loadBufferFromFileNames:@[sp]];
            if (b) _buffers[@"1_0"] = b;
        }
        NSString *spUp = defines[@"57-up"] ?: defines[@"SPACE_UP"];
        if ([spUp isKindOfClass:[NSString class]]) {
            AVAudioPCMBuffer *b = [self loadBufferFromFileNames:@[spUp]];
            if (b) _buffers[@"1_1"] = b;
        }
        
        // Enter
        NSString *ent = defines[@"28"] ?: defines[@"ENTER"];
        if ([ent isKindOfClass:[NSString class]]) {
            AVAudioPCMBuffer *b = [self loadBufferFromFileNames:@[ent]];
            if (b) _buffers[@"2_0"] = b;
        }
        NSString *entUp = defines[@"28-up"] ?: defines[@"ENTER_UP"];
        if ([entUp isKindOfClass:[NSString class]]) {
            AVAudioPCMBuffer *b = [self loadBufferFromFileNames:@[entUp]];
            if (b) _buffers[@"2_1"] = b;
        }
        
        // Backspace
        NSString *bs = defines[@"14"] ?: defines[@"BACKSPACE"];
        if ([bs isKindOfClass:[NSString class]]) {
            AVAudioPCMBuffer *b = [self loadBufferFromFileNames:@[bs]];
            if (b) _buffers[@"3_0"] = b;
        }
        NSString *bsUp = defines[@"14-up"] ?: defines[@"BACKSPACE_UP"];
        if ([bsUp isKindOfClass:[NSString class]]) {
            AVAudioPCMBuffer *b = [self loadBufferFromFileNames:@[bsUp]];
            if (b) _buffers[@"3_1"] = b;
        }
        
        // Modifiers
        NSString *mod = defines[@"42"] ?: defines[@"15"] ?: defines[@"56"] ?: defines[@"29"] ?: defines[@"SHIFT"];
        if ([mod isKindOfClass:[NSString class]]) {
            AVAudioPCMBuffer *b = [self loadBufferFromFileNames:@[mod]];
            if (b) _buffers[@"4_0"] = b;
        }
        
        // Regular key variations (from keys 1..5 or 2..6)
        for (int v = 0; v < 5; v++) {
            NSString *k = [NSString stringWithFormat:@"%d", v + 2];
            NSString *f = defines[k] ?: defines[[NSString stringWithFormat:@"%d", v + 16]];
            if ([f isKindOfClass:[NSString class]]) {
                AVAudioPCMBuffer *b = [self loadBufferFromFileNames:@[f]];
                if (b) _buffers[[NSString stringWithFormat:@"0_0_%d", v]] = b;
            }
        }
    }
    
    // Fallback key from defaults array
    if ([defaults isKindOfClass:[NSArray class]] && defaults.count > 0) {
        NSString *defFile = defaults.firstObject;
        if ([defFile isKindOfClass:[NSString class]] && !_buffers[@"0_0"]) {
            AVAudioPCMBuffer *b = [self loadBufferFromFileNames:@[defFile]];
            if (b) _buffers[@"0_0"] = b;
        }
    }
    
    // Standard key variations
    NSArray *keyFiles = @[
        @[@"key_0.wav", @"GENERIC_R0.mp3", @"1.wav", @"down.wav", @"q.wav"],
        @[@"key_1.wav", @"GENERIC_R1.mp3", @"2.wav", @"w.wav"],
        @[@"key_2.wav", @"GENERIC_R2.mp3", @"3.wav", @"e.wav"],
        @[@"key_3.wav", @"GENERIC_R3.mp3", @"4.wav", @"r.wav"],
        @[@"key_4.wav", @"GENERIC_R4.mp3", @"5.wav", @"t.wav"]
    ];
    for (int v = 0; v < 5; v++) {
        AVAudioPCMBuffer *varBuf = [self loadBufferFromFileNames:keyFiles[v]];
        if (varBuf) {
            _buffers[[NSString stringWithFormat:@"0_0_%d", v]] = varBuf;
        }
    }
    
    // Standard key down & up
    AVAudioPCMBuffer *keyDown = _buffers[@"0_0_0"] ?: [self loadBufferFromFileNames:@[@"down.wav", @"press.wav", @"key_down.wav", @"key.wav", @"1.wav", @"GENERIC.mp3", @"q.wav"]];
    AVAudioPCMBuffer *keyUp = [self loadBufferFromFileNames:@[@"up.wav", @"release.wav", @"key_up.wav", @"keyup.wav", @"GENERIC.mp3"]];
    
    // Spacebar
    AVAudioPCMBuffer *spaceDown = [self loadBufferFromFileNames:@[@"space.wav", @"spacebar.wav", @"space_down.wav", @"SPACE.mp3"]] ?: keyDown;
    AVAudioPCMBuffer *spaceUp = [self loadBufferFromFileNames:@[@"space_up.wav", @"spacebar_up.wav", @"release/SPACE.mp3"]] ?: keyUp;
    
    // Enter
    AVAudioPCMBuffer *enterDown = [self loadBufferFromFileNames:@[@"enter.wav", @"return.wav", @"enter_down.wav", @"ENTER.mp3"]] ?: keyDown;
    AVAudioPCMBuffer *enterUp = [self loadBufferFromFileNames:@[@"enter_up.wav", @"return_up.wav", @"release/ENTER.mp3"]] ?: keyUp;
    
    // Backspace
    AVAudioPCMBuffer *backspaceDown = [self loadBufferFromFileNames:@[@"backspace.wav", @"delete.wav", @"backspace_down.wav", @"BACKSPACE.mp3"]] ?: keyDown;
    AVAudioPCMBuffer *backspaceUp = [self loadBufferFromFileNames:@[@"backspace_up.wav", @"delete_up.wav", @"release/BACKSPACE.mp3"]] ?: keyUp;
    
    // Modifier (Shift, Cmd, Opt)
    AVAudioPCMBuffer *modDown = [self loadBufferFromFileNames:@[@"shift.wav", @"modifier.wav", @"caps lock.wav", @"tab.wav"]] ?: keyDown;
    AVAudioPCMBuffer *modUp = [self loadBufferFromFileNames:@[@"shift_up.wav", @"modifier_up.wav"]] ?: keyUp;
    
    // Mouse click
    AVAudioPCMBuffer *click = [self loadBufferFromFileNames:@[@"click.wav", @"mouse.wav", @"mouse_down.wav"]];
    
    // Mouse scroll
    AVAudioPCMBuffer *scroll = [self loadBufferFromFileNames:@[@"scroll.wav", @"wheel.wav"]];
    
    if (keyDown) _buffers[@"0_0"] = keyDown;
    if (keyUp) _buffers[@"0_1"] = keyUp;
    if (spaceDown) _buffers[@"1_0"] = spaceDown;
    if (spaceUp) _buffers[@"1_1"] = spaceUp;
    if (enterDown) _buffers[@"2_0"] = enterDown;
    if (enterUp) _buffers[@"2_1"] = enterUp;
    if (backspaceDown) _buffers[@"3_0"] = backspaceDown;
    if (backspaceUp) _buffers[@"3_1"] = backspaceUp;
    if (modDown) _buffers[@"4_0"] = modDown;
    if (modUp) _buffers[@"4_1"] = modUp;
    if (click) {
        _buffers[@"5_0"] = click;
        _buffers[@"6_0"] = click;
    }
    if (scroll) _buffers[@"7_0"] = scroll;
    
    return (_buffers.count > 0);
}

- (AVAudioPCMBuffer *)bufferForCategory:(NSInteger)category isKeyUp:(BOOL)isKeyUp {
    if (category == 0 && !isKeyUp) {
        int v = arc4random_uniform(5);
        AVAudioPCMBuffer *varBuf = _buffers[[NSString stringWithFormat:@"0_0_%d", v]];
        if (varBuf) return varBuf;
    }
    
    NSString *key = [NSString stringWithFormat:@"%ld_%d", (long)category, isKeyUp ? 1 : 0];
    AVAudioPCMBuffer *buf = _buffers[key];
    
    // Mouse clicks (5, 6) and scroll (7) should only return dedicated mouse buffers, never fall back to keyboard keydown!
    if (category >= 5) {
        return buf;
    }
    
    if (!buf && isKeyUp) {
        buf = _buffers[@"0_1"];
    }
    if (!buf) {
        buf = _buffers[@"0_0"];
    }
    return buf;
}

@end

@implementation SoundPackManager

+ (instancetype)sharedManager {
    static SoundPackManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SoundPackManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _customPacks = [NSMutableArray array];
        [self rescanPacks];
    }
    return self;
}

- (NSString *)soundPacksDirectory {
    NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dir = [appSupport stringByAppendingPathComponent:@"Clackity/SoundPacks"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (void)rescanPacks {
    [_customPacks removeAllObjects];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // 1. Built-in Studio Sound Packs from Bundle Resources (or local development folder)
    NSString *bundlePacksDir = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"SoundPacks"];
    if (![fm fileExistsAtPath:bundlePacksDir]) {
        bundlePacksDir = @"Resources/SoundPacks";
    }
    NSArray *bundleItems = [fm contentsOfDirectoryAtPath:bundlePacksDir error:nil];
    for (NSString *item in bundleItems) {
        if ([item hasPrefix:@"."]) continue;
        NSString *fullPath = [bundlePacksDir stringByAppendingPathComponent:item];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:fullPath isDirectory:&isDir] && isDir) {
            CustomSoundPack *pack = [[CustomSoundPack alloc] initWithName:item folderPath:fullPath];
            if ([pack loadBuffers]) {
                [_customPacks addObject:pack];
            }
        }
    }
    
    // 2. User Custom Sound Packs from Application Support
    NSString *dir = [self soundPacksDirectory];
    NSArray *items = [fm contentsOfDirectoryAtPath:dir error:nil];
    for (NSString *item in items) {
        if ([item hasPrefix:@"."]) continue;
        NSString *fullPath = [dir stringByAppendingPathComponent:item];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:fullPath isDirectory:&isDir] && isDir) {
            // Avoid duplicate names if user copied a built-in pack
            BOOL exists = NO;
            for (CustomSoundPack *existing in _customPacks) {
                if ([existing.name isEqualToString:item]) { exists = YES; break; }
            }
            if (!exists) {
                CustomSoundPack *pack = [[CustomSoundPack alloc] initWithName:item folderPath:fullPath];
                if ([pack loadBuffers]) {
                    [_customPacks addObject:pack];
                }
            }
        }
    }
}

@end
