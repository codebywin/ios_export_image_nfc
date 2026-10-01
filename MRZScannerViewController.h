#import <UIKit/UIKit.h>

@protocol MRZScannerDelegate <NSObject>
- (void)mrzScannerDidScanDoc:(NSString *)doc birth:(NSString *)birth expiry:(NSString *)expiry;
@optional
- (void)mrzScannerDidRequestManualFillWithDoc:(NSString *)doc birth:(NSString *)birth expiry:(NSString *)expiry;
@end

@interface MRZScannerViewController : UIViewController

@property (nonatomic, weak) id<MRZScannerDelegate> delegate;

@end

