#import "UpdateManager.h"
#import <Cocoa/Cocoa.h>
#import <CommonCrypto/CommonDigest.h>
#import <spawn.h>
#import <sys/stat.h>

NSString * const ClackityUpdateCheckCompletedNotification = @"ClackityUpdateCheckCompletedNotification";
static NSString * const kGitHubReleasesURL = @"https://api.github.com/repos/jojoyboy/Clackityclack/releases/latest";
static NSString * const kAutoCheckKey = @"autoCheckForUpdates";

@implementation ClackityReleaseInfo
@end

@interface UpdateManager ()

@property (nonatomic, strong, nullable) ClackityReleaseInfo *latestRelease;
@property (nonatomic, assign) BOOL isChecking;
@property (nonatomic, assign) BOOL isDownloading;
@property (nonatomic, assign) float downloadProgress;
@property (nonatomic, strong) NSTimer *periodicTimer;
@property (nonatomic, strong, nullable) NSWindow *progressWindow;
@property (nonatomic, strong, nullable) NSProgressIndicator *progressBar;
@property (nonatomic, strong, nullable) NSTextField *progressLabel;

@end

@implementation UpdateManager

+ (instancetype)sharedManager {
    static UpdateManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[UpdateManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        [defs registerDefaults:@{ kAutoCheckKey: @YES }];
        _autoCheckEnabled = [defs boolForKey:kAutoCheckKey];
    }
    return self;
}

- (void)setAutoCheckEnabled:(BOOL)autoCheckEnabled {
    _autoCheckEnabled = autoCheckEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:autoCheckEnabled forKey:kAutoCheckKey];
    if (autoCheckEnabled) {
        [self startPeriodicChecks];
    } else {
        [self.periodicTimer invalidate];
        self.periodicTimer = nil;
    }
}

+ (NSString *)currentAppVersion {
    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    return version ?: @"1.0.0";
}

+ (NSComparisonResult)compareVersion:(NSString *)v1 toVersion:(NSString *)v2 {
    NSString *clean1 = [v1 stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"vV "]];
    NSString *clean2 = [v2 stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"vV "]];
    
    NSArray *parts1 = [clean1 componentsSeparatedByString:@"."];
    NSArray *parts2 = [clean2 componentsSeparatedByString:@"."];
    
    NSUInteger maxLen = MAX(parts1.count, parts2.count);
    for (NSUInteger i = 0; i < maxLen; i++) {
        NSInteger n1 = (i < parts1.count) ? [parts1[i] integerValue] : 0;
        NSInteger n2 = (i < parts2.count) ? [parts2[i] integerValue] : 0;
        if (n1 > n2) return NSOrderedDescending;
        if (n1 < n2) return NSOrderedAscending;
    }
    return NSOrderedSame;
}

- (void)startPeriodicChecks {
    if (!self.autoCheckEnabled) return;
    
    // Check 6 seconds after launch to ensure ultra-fast non-blocking app startup
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self checkForUpdatesUserInitiated:NO];
    });
    
    // Then check once every 24 hours
    [self.periodicTimer invalidate];
    self.periodicTimer = [NSTimer scheduledTimerWithTimeInterval:86400.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        [self checkForUpdatesUserInitiated:NO];
    }];
}

- (void)checkForUpdatesUserInitiated:(BOOL)userInitiated {
    if (self.isChecking) return;
    self.isChecking = YES;
    
    NSURL *url = [NSURL URLWithString:kGitHubReleasesURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"Clackity-AutoUpdater/1.0" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/vnd.github.v3+json" forHTTPHeaderField:@"Accept"];
    request.timeoutInterval = 15.0;
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isChecking = NO;
            
            if (error || !data) {
                if (userInitiated) {
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = @"Unable to Check for Updates";
                    alert.informativeText = error ? error.localizedDescription : @"Could not connect to GitHub to check for updates.";
                    [alert addButtonWithTitle:@"OK"];
                    [alert runModal];
                }
                return;
            }
            
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (![json isKindOfClass:[NSDictionary class]]) {
                return;
            }
            
            NSString *tagName = json[@"tag_name"];
            if (!tagName) return;
            
            NSString *versionStr = [tagName stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"vV "]];
            NSString *currentVersion = [UpdateManager currentAppVersion];
            
            ClackityReleaseInfo *info = [[ClackityReleaseInfo alloc] init];
            info.version = versionStr;
            info.releaseNotes = json[@"body"] ?: @"";
            info.htmlURL = json[@"html_url"] ?: @"https://github.com/jojoyboy/Clackityclack/releases";
            
            NSArray *assets = json[@"assets"];
            if ([assets isKindOfClass:[NSArray class]]) {
                for (NSDictionary *asset in assets) {
                    NSString *name = asset[@"name"];
                    NSString *downloadURL = asset[@"browser_download_url"];
                    if ([name hasSuffix:@".zip"] || [name containsString:@"Clackity-macOS"]) {
                        info.zipDownloadURL = downloadURL;
                        NSString *digest = asset[@"digest"];
                        if ([digest isKindOfClass:[NSString class]] && [digest hasPrefix:@"sha256:"]) {
                            info.zipSHA256 = [[digest substringFromIndex:7] lowercaseString];
                        }
                    } else if ([name hasSuffix:@".pkg"]) {
                        info.pkgDownloadURL = downloadURL;
                    }
                }
            }
            
            info.isNewerVersion = ([UpdateManager compareVersion:versionStr toVersion:currentVersion] == NSOrderedDescending);
            self.latestRelease = info;
            
            [[NSNotificationCenter defaultCenter] postNotificationName:ClackityUpdateCheckCompletedNotification object:info];
            
            if (userInitiated) {
                if (info.isNewerVersion) {
                    [self showUpdatePromptForRelease:info];
                } else {
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.messageText = @"You're Up to Date!";
                    alert.informativeText = [NSString stringWithFormat:@"Clackity %@ is currently the latest available version.", currentVersion];
                    [alert addButtonWithTitle:@"OK"];
                    [alert runModal];
                }
            }
        });
    }] resume];
}

- (void)showUpdatePromptForRelease:(ClackityReleaseInfo *)info {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Clackity %@ is Available!", info.version];
    
    NSString *notes = info.releaseNotes.length > 0 ? [NSString stringWithFormat:@"\n\nRelease Notes:\n%@", info.releaseNotes] : @"";
    alert.informativeText = [NSString stringWithFormat:@"A new version of Clackity is available (current: %@). Would you like to update now?%@", [UpdateManager currentAppVersion], notes];
    
    [alert addButtonWithTitle:@"Update & Relaunch"];
    [alert addButtonWithTitle:@"Later"];
    [alert addButtonWithTitle:@"View on GitHub"];
    
    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        [self downloadAndInstallRelease:info completion:nil];
    } else if (response == NSAlertThirdButtonReturn) {
        if (info.htmlURL) {
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:info.htmlURL]];
        }
    }
}

#pragma mark - Progress Window Helper

- (void)showProgressWindowWithStatus:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.progressWindow) {
            NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 360, 110)
                                                        styleMask:(NSWindowStyleMaskTitled)
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO];
            win.title = @"Clackity Auto-Update";
            [win center];
            win.level = NSFloatingWindowLevel;
            
            NSView *content = win.contentView;
            
            self.progressLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 56, 320, 22)];
            self.progressLabel.editable = NO;
            self.progressLabel.bezeled = NO;
            self.progressLabel.drawsBackground = NO;
            self.progressLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
            self.progressLabel.alignment = NSTextAlignmentCenter;
            [content addSubview:self.progressLabel];
            
            self.progressBar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(30, 24, 300, 20)];
            self.progressBar.style = NSProgressIndicatorStyleBar;
            self.progressBar.indeterminate = YES;
            [content addSubview:self.progressBar];
            
            self.progressWindow = win;
        }
        
        self.progressLabel.stringValue = status;
        [self.progressBar startAnimation:nil];
        [self.progressWindow makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
    });
}

- (void)hideProgressWindow {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.progressBar stopAnimation:nil];
        [self.progressWindow orderOut:nil];
        self.progressWindow = nil;
    });
}

- (void)downloadAndInstallRelease:(ClackityReleaseInfo *)releaseInfo completion:(void (^ _Nullable)(BOOL success, NSString * _Nullable errorMessage))completion {
    if (self.isDownloading) return;
    
    NSString *targetURLStr = releaseInfo.zipDownloadURL ?: releaseInfo.pkgDownloadURL;
    if (!targetURLStr) {
        if (releaseInfo.htmlURL) {
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:releaseInfo.htmlURL]];
        }
        if (completion) completion(NO, @"No download assets available.");
        return;
    }
    
    self.isDownloading = YES;
    self.downloadProgress = 0.0f;
    [self showProgressWindowWithStatus:[NSString stringWithFormat:@"Downloading Clackity v%@...", releaseInfo.version]];
    
    NSURL *downloadURL = [NSURL URLWithString:targetURLStr];
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 60.0;
    config.timeoutIntervalForResource = 300.0;
    config.HTTPAdditionalHeaders = @{
        @"User-Agent": @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        @"Accept": @"*/*"
    };
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:downloadURL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60.0];
    
    [[session downloadTaskWithRequest:req completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error || !location) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.isDownloading = NO;
                [self hideProgressWindow];
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Download Failed";
                alert.informativeText = error ? [NSString stringWithFormat:@"%@\n\nWould you like to open the GitHub Releases page to download manually?", error.localizedDescription] : @"Could not download the update package.";
                [alert addButtonWithTitle:@"Open Download Page"];
                [alert addButtonWithTitle:@"Cancel"];
                NSModalResponse resp = [alert runModal];
                if (resp == NSAlertFirstButtonReturn && releaseInfo.htmlURL) {
                    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:releaseInfo.htmlURL]];
                }
                if (completion) completion(NO, error.localizedDescription);
            });
            return;
        }
        
        // CRITICAL: Must synchronously move/copy location to a stable file BEFORE completionHandler returns,
        // otherwise NSURLSession immediately unlinks and deletes the temporary download file.
        NSString *stagedDownloadPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"Clackity-Downloaded-Asset.tmp"];
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm removeItemAtPath:stagedDownloadPath error:nil];
        
        NSError *stageErr = nil;
        [fm moveItemAtURL:location toURL:[NSURL fileURLWithPath:stagedDownloadPath] error:&stageErr];
        if (stageErr) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.isDownloading = NO;
                [self hideProgressWindow];
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = @"Download Staging Failed";
                alert.informativeText = stageErr.localizedDescription;
                [alert addButtonWithTitle:@"OK"];
                [alert runModal];
                if (completion) completion(NO, stageErr.localizedDescription);
            });
            return;
        }
        
        BOOL isZip = [targetURLStr containsString:@".zip"] || [response.suggestedFilename containsString:@".zip"];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isDownloading = NO;
            [self showProgressWindowWithStatus:@"Installing update & relaunching..."];
            if (isZip) {
                [self applyZipUpdateFromLocation:[NSURL fileURLWithPath:stagedDownloadPath] expectedSHA256:releaseInfo.zipSHA256 completion:completion];
            } else {
                [self hideProgressWindow];
                [self applyPkgUpdateFromLocation:[NSURL fileURLWithPath:stagedDownloadPath] suggestedName:response.suggestedFilename completion:completion];
            }
        });
    }] resume];
}

- (nullable NSString *)sha256ForFileAtPath:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!data) return nil;
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return hex;
}

- (nullable NSDictionary<NSString *, NSString *> *)codeSigningInfoForBundleAtPath:(NSString *)bundlePath {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/codesign";
    task.arguments = @[@"-dvv", bundlePath];
    NSPipe *errPipe = [NSPipe pipe];
    task.standardError = errPipe;
    task.standardOutput = [NSPipe pipe];
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *ex) {
        return nil;
    }
    if (task.terminationStatus != 0) return nil;
    NSData *errData = [errPipe.fileHandleForReading readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding];
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    for (NSString *line in [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSRange eq = [line rangeOfString:@"="];
        if (eq.location != NSNotFound) {
            NSString *k = [line substringToIndex:eq.location];
            NSString *v = [line substringFromIndex:eq.location + 1];
            info[k] = v;
        }
    }
    return info;
}

- (BOOL)verifyExtractedApp:(NSString *)newAppPath expectedBundleId:(NSString *)expectedBundleId errorMessage:(NSString **)errorOut {
    // 1. Strict deep signature verification on the downloaded bundle as published
    NSTask *verifyTask = [[NSTask alloc] init];
    verifyTask.launchPath = @"/usr/bin/codesign";
    verifyTask.arguments = @[@"--verify", @"--deep", @"--strict", newAppPath];
    verifyTask.standardOutput = [NSPipe pipe];
    verifyTask.standardError = [NSPipe pipe];
    [verifyTask launch];
    [verifyTask waitUntilExit];
    if (verifyTask.terminationStatus != 0) {
        if (errorOut) *errorOut = @"The downloaded application failed strict code signature verification.";
        return NO;
    }
    
    // 2. Verify bundle identifier & signing metadata match the running publisher
    NSBundle *newBundle = [NSBundle bundleWithPath:newAppPath];
    if (![newBundle.bundleIdentifier isEqualToString:expectedBundleId]) {
        if (errorOut) *errorOut = @"The downloaded application's bundle identifier does not match Clackity.";
        return NO;
    }
    
    NSDictionary<NSString *, NSString *> *newSignInfo = [self codeSigningInfoForBundleAtPath:newAppPath];
    if (![newSignInfo[@"Identifier"] isEqualToString:expectedBundleId]) {
        if (errorOut) *errorOut = @"The downloaded application's signed identifier does not match Clackity.";
        return NO;
    }
    
    NSString *currentBundlePath = [[NSBundle mainBundle] bundlePath];
    NSDictionary<NSString *, NSString *> *currentSignInfo = [self codeSigningInfoForBundleAtPath:currentBundlePath];
    NSString *currentTeam = currentSignInfo[@"TeamIdentifier"];
    if (currentTeam && currentTeam.length > 0 && ![currentTeam isEqualToString:@"not set"]) {
        NSString *newTeam = newSignInfo[@"TeamIdentifier"];
        if (![newTeam isEqualToString:currentTeam]) {
            if (errorOut) *errorOut = @"The downloaded application is not signed by the same publisher team.";
            return NO;
        }
    }
    
    return YES;
}

- (void)failZipUpdateWithTitle:(NSString *)title message:(NSString *)message cleanupPaths:(NSArray<NSString *> *)paths completion:(void (^ _Nullable)(BOOL, NSString * _Nullable))completion {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *p in paths) {
        [fm removeItemAtPath:p error:nil];
    }
    [self hideProgressWindow];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
    if (completion) completion(NO, message);
}

- (void)applyZipUpdateFromLocation:(NSURL *)tempLocation expectedSHA256:(nullable NSString *)expectedSHA256 completion:(void (^ _Nullable)(BOOL success, NSString * _Nullable errorMessage))completion {
    NSString *tempDir = NSTemporaryDirectory();
    NSString *zipPath = [tempDir stringByAppendingPathComponent:@"Clackity-Update.zip"];
    NSString *extractDir = [tempDir stringByAppendingPathComponent:@"Clackity-Update-Extracted"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:zipPath error:nil];
    [fm removeItemAtPath:extractDir error:nil];
    
    NSError *moveErr = nil;
    [fm moveItemAtURL:tempLocation toURL:[NSURL fileURLWithPath:zipPath] error:&moveErr];
    if (moveErr) {
        [self failZipUpdateWithTitle:@"Update Failed" message:moveErr.localizedDescription cleanupPaths:@[zipPath, extractDir] completion:completion];
        return;
    }
    
    // Verify cryptographic SHA-256 digest from GitHub Release API if provided
    if (expectedSHA256 && expectedSHA256.length == 64) {
        NSString *actualSHA256 = [self sha256ForFileAtPath:zipPath];
        if (![actualSHA256 isEqualToString:expectedSHA256.lowercaseString]) {
            [self failZipUpdateWithTitle:@"Update Integrity Check Failed"
                                 message:@"The downloaded archive's SHA-256 checksum does not match the official release."
                            cleanupPaths:@[zipPath, extractDir]
                              completion:completion];
            return;
        }
    }
    
    [fm createDirectoryAtPath:extractDir withIntermediateDirectories:YES attributes:nil error:nil];
    
    // Extract using ditto
    NSTask *unzipTask = [[NSTask alloc] init];
    unzipTask.launchPath = @"/usr/bin/ditto";
    unzipTask.arguments = @[@"-x", @"-k", zipPath, extractDir];
    [unzipTask launch];
    [unzipTask waitUntilExit];
    if (unzipTask.terminationStatus != 0) {
        [self failZipUpdateWithTitle:@"Corrupt Update Archive"
                             message:@"Failed to extract the downloaded update archive."
                        cleanupPaths:@[zipPath, extractDir]
                          completion:completion];
        return;
    }
    
    NSString *newAppPath = [extractDir stringByAppendingPathComponent:@"Clackity.app"];
    if (![fm fileExistsAtPath:newAppPath]) {
        NSArray *subpaths = [fm subpathsAtPath:extractDir];
        for (NSString *sub in subpaths) {
            if ([sub hasSuffix:@"Clackity.app"]) {
                newAppPath = [extractDir stringByAppendingPathComponent:sub];
                break;
            }
        }
    }
    
    if (![fm fileExistsAtPath:newAppPath]) {
        [self failZipUpdateWithTitle:@"Corrupt Update Archive"
                             message:@"The downloaded update package did not contain a valid Clackity.app bundle."
                        cleanupPaths:@[zipPath, extractDir]
                          completion:completion];
        return;
    }
    
    // Verify publisher signature and bundle identity BEFORE modifying or installing anything
    NSString *expectedBundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"com.jojoyboy.Clackity";
    NSString *verifyErr = nil;
    if (![self verifyExtractedApp:newAppPath expectedBundleId:expectedBundleId errorMessage:&verifyErr]) {
        [self failZipUpdateWithTitle:@"Update Signature Verification Failed"
                             message:(verifyErr ?: @"Could not verify the publisher signature of the update.")
                        cleanupPaths:@[zipPath, extractDir]
                          completion:completion];
        return;
    }
    
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *targetAppPath = @"/Applications/Clackity.app";
    if ([bundlePath hasPrefix:@"/Applications"]) {
        targetAppPath = bundlePath;
    }
    NSString *backupAppPath = [targetAppPath stringByAppendingString:@".backup"];
    
    // Atomic backup-and-replace synchronously so we never report success or lose the working app on failure
    [fm removeItemAtPath:backupAppPath error:nil];
    BOOL hadExistingTarget = [fm fileExistsAtPath:targetAppPath];
    BOOL replaced = NO;
    NSError *replaceErr = nil;
    
    if (!hadExistingTarget || [fm moveItemAtPath:targetAppPath toPath:backupAppPath error:&replaceErr]) {
        NSTask *copyTask = [[NSTask alloc] init];
        copyTask.launchPath = @"/usr/bin/ditto";
        copyTask.arguments = @[newAppPath, targetAppPath];
        [copyTask launch];
        [copyTask waitUntilExit];
        
        NSString *execPath = [targetAppPath stringByAppendingPathComponent:@"Contents/MacOS/Clackity"];
        if (copyTask.terminationStatus == 0 && [fm isExecutableFileAtPath:execPath]) {
            replaced = YES;
        } else {
            // Roll back immediately so the working app is preserved
            [fm removeItemAtPath:targetAppPath error:nil];
            if (hadExistingTarget && [fm fileExistsAtPath:backupAppPath]) {
                [fm moveItemAtPath:backupAppPath toPath:targetAppPath error:nil];
            }
        }
    } else if (replaceErr.code == NSFileWriteNoPermissionError || replaceErr.code == NSFileReadNoPermissionError) {
        // Request administrator authorization for atomic swap with rollback
        NSString *escTarget = [targetAppPath stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
        NSString *escBackup = [backupAppPath stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
        NSString *escNew = [newAppPath stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
        NSString *shellCmd = [NSString stringWithFormat:
            @"rm -rf '%@' && mv '%@' '%@' && ( /usr/bin/ditto '%@' '%@' && rm -rf '%@' || ( rm -rf '%@'; mv '%@' '%@'; exit 1 ) )",
            escBackup, escTarget, escBackup, escNew, escTarget, escBackup, escTarget, escBackup, escTarget];
        NSString *escAppleScript = [shellCmd stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
        escAppleScript = [escAppleScript stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        
        NSTask *adminTask = [[NSTask alloc] init];
        adminTask.launchPath = @"/usr/bin/osascript";
        adminTask.arguments = @[@"-e", [NSString stringWithFormat:@"do shell script \"%@\" with administrator privileges", escAppleScript]];
        [adminTask launch];
        [adminTask waitUntilExit];
        
        NSString *execPath = [targetAppPath stringByAppendingPathComponent:@"Contents/MacOS/Clackity"];
        if (adminTask.terminationStatus == 0 && [fm isExecutableFileAtPath:execPath]) {
            replaced = YES;
        }
    }
    
    if (!replaced) {
        [self failZipUpdateWithTitle:@"Update Installation Failed"
                             message:@"Could not replace Clackity.app. Your previous working version has been preserved."
                        cleanupPaths:@[zipPath, extractDir]
                          completion:completion];
        return;
    }
    
    // Clear quarantine only after verification and successful installation
    NSTask *xattrTask = [[NSTask alloc] init];
    xattrTask.launchPath = @"/usr/bin/xattr";
    xattrTask.arguments = @[@"-dr", @"com.apple.quarantine", targetAppPath];
    [xattrTask launch];
    [xattrTask waitUntilExit];
    
    [fm removeItemAtPath:backupAppPath error:nil];
    [fm removeItemAtPath:extractDir error:nil];
    [fm removeItemAtPath:zipPath error:nil];
    
    // Report success only after the replacement bundle is verified in place
    if (completion) completion(YES, nil);
    
    // Relaunch the newly installed bundle after this process exits
    NSString *escTarget = [targetAppPath stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    NSString *relaunchCmd = [NSString stringWithFormat:@"nohup /bin/sh -c 'sleep 0.4; /usr/bin/open -n \"$1\"' _ '%@' >/dev/null 2>&1 &", escTarget];
    system([relaunchCmd UTF8String]);
    
    [NSApp terminate:nil];
}

- (void)applyPkgUpdateFromLocation:(NSURL *)tempLocation suggestedName:(NSString *)suggestedName completion:(void (^ _Nullable)(BOOL success, NSString * _Nullable errorMessage))completion {
    NSString *filename = suggestedName ?: @"Clackity-Installer.pkg";
    NSString *pkgPath = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:pkgPath error:nil];
    [fm moveItemAtURL:tempLocation toURL:[NSURL fileURLWithPath:pkgPath] error:nil];
    
    // Open macOS Installer
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:pkgPath]];
    
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Installer Launched";
    alert.informativeText = @"The Clackity installer has been launched. Please follow the on-screen instructions to complete the update.";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
    
    if (completion) completion(YES, nil);
}

@end
