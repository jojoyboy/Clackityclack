#import "UpdateManager.h"
#import <Cocoa/Cocoa.h>
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
                [self applyZipUpdateFromLocation:[NSURL fileURLWithPath:stagedDownloadPath] completion:completion];
            } else {
                [self hideProgressWindow];
                [self applyPkgUpdateFromLocation:[NSURL fileURLWithPath:stagedDownloadPath] suggestedName:response.suggestedFilename completion:completion];
            }
        });
    }] resume];
}

- (void)applyZipUpdateFromLocation:(NSURL *)tempLocation completion:(void (^ _Nullable)(BOOL success, NSString * _Nullable errorMessage))completion {
    NSString *tempDir = NSTemporaryDirectory();
    NSString *zipPath = [tempDir stringByAppendingPathComponent:@"Clackity-Update.zip"];
    NSString *extractDir = [tempDir stringByAppendingPathComponent:@"Clackity-Update-Extracted"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:zipPath error:nil];
    [fm removeItemAtPath:extractDir error:nil];
    
    NSError *moveErr = nil;
    [fm moveItemAtURL:tempLocation toURL:[NSURL fileURLWithPath:zipPath] error:&moveErr];
    if (moveErr) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Update Failed";
        alert.informativeText = moveErr.localizedDescription;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        if (completion) completion(NO, moveErr.localizedDescription);
        return;
    }
    
    [fm createDirectoryAtPath:extractDir withIntermediateDirectories:YES attributes:nil error:nil];
    
    // Extract using ditto
    NSTask *unzipTask = [[NSTask alloc] init];
    unzipTask.launchPath = @"/usr/bin/ditto";
    unzipTask.arguments = @[@"-x", @"-k", zipPath, extractDir];
    [unzipTask launch];
    [unzipTask waitUntilExit];
    
    NSString *newAppPath = [extractDir stringByAppendingPathComponent:@"Clackity.app"];
    if (![fm fileExistsAtPath:newAppPath]) {
        // Search inside subdirectories
        NSArray *subpaths = [fm subpathsAtPath:extractDir];
        for (NSString *sub in subpaths) {
            if ([sub hasSuffix:@"Clackity.app"]) {
                newAppPath = [extractDir stringByAppendingPathComponent:sub];
                break;
            }
        }
    }
    
    if (![fm fileExistsAtPath:newAppPath]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Corrupt Update Archive";
        alert.informativeText = @"The downloaded update package did not contain a valid Clackity.app bundle.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        if (completion) completion(NO, @"Extracted archive did not contain Clackity.app");
        return;
    }
    
    // Clear quarantine attribute
    NSTask *xattrTask = [[NSTask alloc] init];
    xattrTask.launchPath = @"/usr/bin/xattr";
    xattrTask.arguments = @[@"-dr", @"com.apple.quarantine", newAppPath];
    [xattrTask launch];
    [xattrTask waitUntilExit];
    
    // Code sign extracted app bundle with persistent designated identifier
    NSTask *signTask = [[NSTask alloc] init];
    signTask.launchPath = @"/usr/bin/codesign";
    signTask.arguments = @[@"-s", @"-", @"--force", @"--deep", @"--identifier", @"com.jojoyboy.Clackity", @"-r", @"designated => identifier \"com.jojoyboy.Clackity\"", newAppPath];
    [signTask launch];
    [signTask waitUntilExit];
    
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *targetAppPath = @"/Applications/Clackity.app";
    if ([bundlePath hasPrefix:@"/Applications"]) {
        targetAppPath = bundlePath;
    }
    
    pid_t currentPid = [[NSProcessInfo processInfo] processIdentifier];
    
    // Create an atomic updater script
    NSString *scriptPath = [tempDir stringByAppendingPathComponent:@"clackity_relaunch.sh"];
    NSString *scriptContent = [NSString stringWithFormat:
        @"#!/bin/bash\n"
        @"exec > /tmp/clackity_update.log 2>&1\n"
        @"PID=%d\n"
        @"TARGET=\"%@\"\n"
        @"NEW_APP=\"%@\"\n"
        @"EXTRACT_DIR=\"%@\"\n"
        @"ZIP_PATH=\"%@\"\n\n"
        @"echo \"[Updater] Waiting for PID $PID to terminate...\"\n"
        @"while kill -0 $PID 2>/dev/null; do\n"
        @"    sleep 0.1\n"
        @"done\n\n"
        @"echo \"[Updater] Replacing $TARGET with $NEW_APP...\"\n"
        @"if ! rm -rf \"$TARGET\" 2>/dev/null; then\n"
        @"    echo \"[Updater] Permission denied. Requesting administrator authorization...\"\n"
        @"    /usr/bin/osascript -e \"do shell script \\\"rm -rf '$TARGET' && cp -R '$NEW_APP' '$TARGET' && /usr/bin/xattr -cr '$TARGET'\\\" with administrator privileges\"\n"
        @"else\n"
        @"    cp -R \"$NEW_APP\" \"$TARGET\"\n"
        @"    /usr/bin/xattr -cr \"$TARGET\" 2>/dev/null || true\n"
        @"fi\n\n"
        @"echo \"[Updater] Relaunching '$TARGET'...\"\n"
        @"/usr/bin/open \"$TARGET\"\n"
        @"rm -rf \"$EXTRACT_DIR\" \"$ZIP_PATH\" \"$0\"\n"
        @"echo \"[Updater] Completed successfully!\"\n",
        currentPid, targetAppPath, newAppPath, extractDir, zipPath];
    
    [scriptContent writeToFile:scriptPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    chmod([scriptPath UTF8String], 0755);
    
    // Execute detached script using system / background runner
    NSString *cmd = [NSString stringWithFormat:@"nohup /bin/bash \"%@\" > /dev/null 2>&1 &", scriptPath];
    system([cmd UTF8String]);
    
    if (completion) completion(YES, nil);
    
    // Terminate current app to allow seamless replacement
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
