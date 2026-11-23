#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const ClackityUpdateCheckCompletedNotification;

@interface ClackityReleaseInfo : NSObject

@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *releaseNotes;
@property (nonatomic, copy) NSString *htmlURL;
@property (nonatomic, copy) NSString *zipDownloadURL;
@property (nonatomic, copy) NSString *pkgDownloadURL;
@property (nonatomic, assign) BOOL isNewerVersion;

@end

@interface UpdateManager : NSObject

@property (nonatomic, readonly, nullable) ClackityReleaseInfo *latestRelease;
@property (nonatomic, readonly) BOOL isChecking;
@property (nonatomic, readonly) BOOL isDownloading;
@property (nonatomic, readonly) float downloadProgress;
@property (nonatomic, assign) BOOL autoCheckEnabled;

+ (instancetype)sharedManager;

- (void)startPeriodicChecks;
- (void)checkForUpdatesUserInitiated:(BOOL)userInitiated;
- (void)showUpdatePromptForRelease:(ClackityReleaseInfo *)info;
- (void)downloadAndInstallRelease:(ClackityReleaseInfo *)releaseInfo completion:(void (^ _Nullable)(BOOL success, NSString * _Nullable errorMessage))completion;

+ (NSString *)currentAppVersion;
+ (NSComparisonResult)compareVersion:(NSString *)v1 toVersion:(NSString *)v2;

@end

NS_ASSUME_NONNULL_END
