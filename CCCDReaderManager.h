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

- (instancetype)initWithSeed:(NSData *)seed;
- (void)updateSeed:(NSData *)seed;
- (void)startScanning;
- (void)stopScanning;

@end
