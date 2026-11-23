#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const ClackitySoundPacksDidChangeNotification;

@interface CommunityPackItem : NSObject

@property (nonatomic, copy) NSString *packId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *switchType;      // Linear, Tactile, Clicky
@property (nonatomic, copy) NSString *acousticProfile; // e.g. "Crisp click jacket..."
@property (nonatomic, copy) NSString *license;         // e.g. "MIT Open Source"
@property (nonatomic, copy) NSString *author;          // e.g. "Mechvibes / Cherry"
@property (nonatomic, copy) NSString *previewFile;     // e.g. "cherry-mx-blue.wav"
@property (nonatomic, copy) NSString *previewUrl;      // Remote audio URL
@property (nonatomic, copy) NSString *downloadUrl;     // Zip download URL
@property (nonatomic, copy) NSString *folderName;      // Subdirectory name in SoundPacks
@property (nonatomic, assign) BOOL isBundled;          // Pre-shipped in Clackity bundle
@property (nonatomic, assign) BOOL isInstalled;        // Exists on disk
@property (nonatomic, assign) BOOL isDownloading;
@property (nonatomic, assign) float downloadProgress;

- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (void)refreshInstalledStatus;

@end

@interface CommunitySoundPacksManager : NSObject

@property (nonatomic, strong, readonly) NSArray<CommunityPackItem *> *allPacks;
@property (nonatomic, strong, nullable) CommunityPackItem *currentlyPlayingPack;

+ (instancetype)sharedManager;

- (void)loadCatalog;
- (NSArray<CommunityPackItem *> *)filteredPacksWithQuery:(nullable NSString *)query
                                            categoryType:(nullable NSString *)categoryType;

- (void)playPreviewForPack:(CommunityPackItem *)pack completion:(nullable void (^)(void))completion;
- (void)stopPreview;

- (void)downloadAndInstallPack:(CommunityPackItem *)pack
                      progress:(nullable void (^)(float progress))progressBlock
                    completion:(void (^)(BOOL success, NSString * _Nullable errorMsg))completionBlock;

- (void)uninstallPack:(CommunityPackItem *)pack
           completion:(void (^)(BOOL success))completionBlock;

@end

NS_ASSUME_NONNULL_END
