#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreNFC/CoreNFC.h>

@protocol CCCDReaderManagerDelegate <NSObject>
- (void)cccdReaderDidStartScanning;
- (void)cccdReaderDidUpdateStatus:(NSString *)status;
- (void)cccdReaderDidFinishWithSuccess:(UIImage *)image rawData:(NSData *)rawData;
- (void)cccdReaderDidFailWithError:(NSString *)error;
@end

@interface CCCDReaderManager : NSObject <NFCTagReaderSessionDelegate>

@property (nonatomic, weak) id<CCCDReaderManagerDelegate> delegate;
@property (nonatomic, copy) NSArray<NSData *> *candidateSeeds;

- (instancetype)initWithCandidateSeeds:(NSArray<NSData *> *)candidateSeeds;
- (instancetype)initWithSeed:(NSData *)seed;
- (void)updateCandidateSeeds:(NSArray<NSData *> *)candidateSeeds;
- (void)updateSeed:(NSData *)seed;
- (void)startScanning;
- (void)stopScanning;

@end
