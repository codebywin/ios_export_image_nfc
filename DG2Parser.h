#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface DG2Parser : NSObject

/// Trích xuất ảnh chân dung từ dữ liệu thô DG2
+ (UIImage *)extractImageFromDG2Data:(NSData *)dg2Data;

/// Chuyển đổi UIImage sang NSData định dạng JPG chất lượng cao
+ (NSData *)exportToJPG:(UIImage *)image quality:(CGFloat)quality;

@end
