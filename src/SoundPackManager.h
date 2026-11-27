#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CustomSoundPack : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *folderPath;
@property (nonatomic, strong) NSMutableDictionary<NSString *, AVAudioPCMBuffer *> *buffers;

- (instancetype)initWithName:(NSString *)name folderPath:(NSString *)folderPath;
- (BOOL)loadBuffers;
- (nullable AVAudioPCMBuffer *)bufferForCategory:(NSInteger)category isKeyUp:(BOOL)isKeyUp;
@end

@interface SoundPackManager : NSObject

@property (nonatomic, strong, readonly) NSMutableArray<CustomSoundPack *> *customPacks;

+ (instancetype)sharedManager;
- (void)rescanPacks;
- (NSString *)soundPacksDirectory;
- (nullable CustomSoundPack *)importPackFromURL:(NSURL *)url error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
