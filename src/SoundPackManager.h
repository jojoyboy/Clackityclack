#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface CustomSoundPack : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *folderPath;
@property (nonatomic, strong) NSMutableDictionary<NSString *, AVAudioPCMBuffer *> *buffers;

- (instancetype)initWithName:(NSString *)name folderPath:(NSString *)folderPath;
- (BOOL)loadBuffers;
- (AVAudioPCMBuffer *)bufferForCategory:(NSInteger)category isKeyUp:(BOOL)isKeyUp;
@end

@interface SoundPackManager : NSObject

@property (nonatomic, strong, readonly) NSMutableArray<CustomSoundPack *> *customPacks;

+ (instancetype)sharedManager;
- (void)rescanPacks;
- (NSString *)soundPacksDirectory;

@end
