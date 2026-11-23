#import "CommunitySoundPacks.h"
#import "SoundPackManager.h"
#import "AudioEngine.h"

NSNotificationName const ClackitySoundPacksDidChangeNotification = @"ClackitySoundPacksDidChangeNotification";

@implementation CommunityPackItem

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _packId = [dict[@"id"] copy] ?: @"";
        _name = [dict[@"name"] copy] ?: @"";
        _switchType = [dict[@"switchType"] copy] ?: @"Mechanical";
        _acousticProfile = [dict[@"acousticProfile"] copy] ?: @"";
        _license = [dict[@"license"] copy] ?: @"Open Source";
        _author = [dict[@"author"] copy] ?: @"Community";
        _previewFile = [dict[@"previewFile"] copy] ?: @"";
        _previewUrl = [dict[@"previewUrl"] copy] ?: @"";
        _downloadUrl = [dict[@"downloadUrl"] copy] ?: @"";
        _folderName = [dict[@"folderName"] copy] ?: _name;
        _isBundled = [dict[@"isBundled"] boolValue];
        
        [self refreshInstalledStatus];
    }
    return self;
}

- (void)refreshInstalledStatus {
    if (_isBundled) {
        _isInstalled = YES;
        return;
    }
    
    NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString *userPacksDir = [appSupport stringByAppendingPathComponent:@"Clackity/SoundPacks"];
    NSString *packPath = [userPacksDir stringByAppendingPathComponent:_folderName];
    
    BOOL isDir = NO;
    _isInstalled = [[NSFileManager defaultManager] fileExistsAtPath:packPath isDirectory:&isDir] && isDir;
}

@end

@interface CommunitySoundPacksManager () <AVAudioPlayerDelegate>

@property (nonatomic, strong) NSMutableArray<CommunityPackItem *> *packsList;
@property (nonatomic, strong) AVAudioPlayer *audioPlayer;
@property (nonatomic, copy, nullable) void (^previewCompletion)(void);

@end

@implementation CommunitySoundPacksManager

+ (instancetype)sharedManager {
    static CommunitySoundPacksManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CommunitySoundPacksManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _packsList = [NSMutableArray array];
        [self loadCatalog];
    }
    return self;
}

- (NSArray<CommunityPackItem *> *)allPacks {
    return [_packsList copy];
}

- (void)loadCatalog {
    [_packsList removeAllObjects];
    
    // 1. Load from bundled community_soundpacks.json
    NSString *bundleJsonPath = [[NSBundle mainBundle] pathForResource:@"community_soundpacks" ofType:@"json"];
    if (!bundleJsonPath) {
        bundleJsonPath = @"Resources/community_soundpacks.json";
    }
    
    NSData *data = [NSData dataWithContentsOfFile:bundleJsonPath];
    if (data) {
        NSArray *items = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([items isKindOfClass:[NSArray class]]) {
            for (NSDictionary *d in items) {
                if ([d isKindOfClass:[NSDictionary class]]) {
                    CommunityPackItem *item = [[CommunityPackItem alloc] initWithDictionary:d];
                    [_packsList addObject:item];
                }
            }
        }
    }
    
    // 2. Refresh installed state for each pack
    for (CommunityPackItem *item in _packsList) {
        [item refreshInstalledStatus];
    }
}

- (NSArray<CommunityPackItem *> *)filteredPacksWithQuery:(nullable NSString *)query
                                            categoryType:(nullable NSString *)categoryType {
    NSMutableArray<CommunityPackItem *> *filtered = [NSMutableArray array];
    NSString *q = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
    BOOL filterCat = categoryType.length > 0 && ![categoryType isEqualToString:@"All"];
    
    for (CommunityPackItem *item in _packsList) {
        if (filterCat) {
            if (![item.switchType localizedCaseInsensitiveContainsString:categoryType]) {
                continue;
            }
        }
        if (q.length > 0) {
            BOOL matchName = [item.name.lowercaseString containsString:q];
            BOOL matchType = [item.switchType.lowercaseString containsString:q];
            BOOL matchProfile = [item.acousticProfile.lowercaseString containsString:q];
            BOOL matchAuthor = [item.author.lowercaseString containsString:q];
            if (!matchName && !matchType && !matchProfile && !matchAuthor) {
                continue;
            }
        }
        [filtered addObject:item];
    }
    return [filtered copy];
}

#pragma mark - Audio Preview

- (void)playPreviewForPack:(CommunityPackItem *)pack completion:(nullable void (^)(void))completion {
    [self stopPreview];
    
    _currentlyPlayingPack = pack;
    _previewCompletion = completion;
    
    // 1. Try local bundled preview
    NSString *bundlePreviewsDir = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Previews"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:bundlePreviewsDir]) {
        bundlePreviewsDir = @"Resources/Previews";
    }
    
    NSString *localPath = [bundlePreviewsDir stringByAppendingPathComponent:pack.previewFile];
    if ([[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
        [self playAudioFileAtPath:localPath];
        return;
    }
    
    // 2. Try cache directory
    NSString *cachesDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    NSString *clackityCache = [cachesDir stringByAppendingPathComponent:@"Clackity/Previews"];
    [[NSFileManager defaultManager] createDirectoryAtPath:clackityCache withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *cachedPath = [clackityCache stringByAppendingPathComponent:pack.previewFile];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:cachedPath]) {
        [self playAudioFileAtPath:cachedPath];
        return;
    }
    
    // 3. Download preview audio over network
    if (pack.previewUrl.length > 0) {
        NSURL *url = [NSURL URLWithString:pack.previewUrl];
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (data && !error) {
                [data writeToFile:cachedPath atomically:YES];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self.currentlyPlayingPack == pack) {
                        [self playAudioFileAtPath:cachedPath];
                    }
                });
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self stopPreview];
                });
            }
        }];
        [task resume];
    } else {
        [self stopPreview];
    }
}

- (void)playAudioFileAtPath:(NSString *)path {
    NSError *error = nil;
    _audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&error];
    if (_audioPlayer && !error) {
        _audioPlayer.delegate = self;
        _audioPlayer.volume = 1.0;
        [_audioPlayer prepareToPlay];
        [_audioPlayer play];
    } else {
        [self stopPreview];
    }
}

- (void)stopPreview {
    if (_audioPlayer) {
        [_audioPlayer stop];
        _audioPlayer = nil;
    }
    _currentlyPlayingPack = nil;
    if (_previewCompletion) {
        void (^comp)(void) = _previewCompletion;
        _previewCompletion = nil;
        comp();
    }
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    [self stopPreview];
}

#pragma mark - Download & Install

- (void)downloadAndInstallPack:(CommunityPackItem *)pack
                      progress:(nullable void (^)(float progress))progressBlock
                    completion:(void (^)(BOOL success, NSString * _Nullable errorMsg))completionBlock {
    if (pack.isBundled || pack.isInstalled) {
        completionBlock(YES, nil);
        return;
    }
    
    if (pack.downloadUrl.length == 0) {
        completionBlock(NO, @"No download URL specified for this pack.");
        return;
    }
    
    pack.isDownloading = YES;
    pack.downloadProgress = 0.05;
    if (progressBlock) progressBlock(0.05);
    
    NSURL *url = [NSURL URLWithString:pack.downloadUrl];
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    NSURLSessionDownloadTask *task = [session downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error || !location) {
            dispatch_async(dispatch_get_main_queue(), ^{
                pack.isDownloading = NO;
                pack.downloadProgress = 0.0;
                completionBlock(NO, error.localizedDescription ?: @"Download failed.");
            });
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            pack.downloadProgress = 0.70;
            if (progressBlock) progressBlock(0.70);
        });
        
        // Target directory: ~/Library/Application Support/Clackity/SoundPacks/
        NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
        NSString *soundPacksDir = [appSupport stringByAppendingPathComponent:@"Clackity/SoundPacks"];
        [[NSFileManager defaultManager] createDirectoryAtPath:soundPacksDir withIntermediateDirectories:YES attributes:nil error:nil];
        
        // Extract using macOS native ditto
        NSTask *unzipTask = [[NSTask alloc] init];
        unzipTask.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ditto"];
        unzipTask.arguments = @[@"-x", @"-k", location.path, soundPacksDir];
        
        NSError *unzipError = nil;
        [unzipTask launchAndReturnError:&unzipError];
        [unzipTask waitUntilExit];
        
        BOOL success = (unzipTask.terminationStatus == 0);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            pack.isDownloading = NO;
            pack.downloadProgress = 1.0;
            if (progressBlock) progressBlock(1.0);
            
            if (success) {
                [pack refreshInstalledStatus];
                [[SoundPackManager sharedManager] rescanPacks];
                [[NSNotificationCenter defaultCenter] postNotificationName:ClackitySoundPacksDidChangeNotification object:nil];
                completionBlock(YES, nil);
            } else {
                completionBlock(NO, @"Extraction failed.");
            }
        });
    }];
    
    [task resume];
}

- (void)uninstallPack:(CommunityPackItem *)pack
           completion:(void (^)(BOOL success))completionBlock {
    if (pack.isBundled) {
        completionBlock(NO);
        return;
    }
    
    NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString *soundPacksDir = [appSupport stringByAppendingPathComponent:@"Clackity/SoundPacks"];
    NSString *packPath = [soundPacksDir stringByAppendingPathComponent:pack.folderName];
    
    NSError *error = nil;
    BOOL removed = [[NSFileManager defaultManager] removeItemAtPath:packPath error:&error];
    [pack refreshInstalledStatus];
    
    [[SoundPackManager sharedManager] rescanPacks];
    [[NSNotificationCenter defaultCenter] postNotificationName:ClackitySoundPacksDidChangeNotification object:nil];
    
    completionBlock(removed);
}

@end
