#import "DG2Parser.h"

@implementation DG2Parser

+ (UIImage *)extractImageFromDG2Data:(NSData *)dg2Data {
    if (!dg2Data || dg2Data.length < 4) return nil;

    NSInteger offset = [self findImageOffsetInData:dg2Data];
    if (offset < 0) {
        NSLog(@"[DG2Parser] Không tìm thấy header JPEG / JPEG2000 trong DG2.");
        return nil;
    }

    NSData *imageData = [dg2Data subdataWithRange:NSMakeRange(offset, dg2Data.length - offset)];

    const uint8_t *h = (const uint8_t *)imageData.bytes;
    NSLog(@"[DG2Parser] Image data offset=%ld, length=%lu bytes, header: %02X %02X %02X %02X",
          (long)offset, (unsigned long)imageData.length, h[0], h[1], h[2], h[3]);

    // Dump ảnh thô để phân tích định dạng/kích thước thực tế
    [imageData writeToFile:@"/var/mobile/Library/Caches/dg2_face_raw.bin" atomically:YES];
    [dg2Data writeToFile:@"/var/mobile/Library/Caches/dg2_full_tlv.bin" atomically:YES];
    NSLog(@"[DG2Parser] Dumped raw image (%lu bytes) and full DG2 (%lu bytes) to Caches",
          (unsigned long)imageData.length, (unsigned long)dg2Data.length);

    // Khởi tạo UIImage từ dữ liệu ảnh (iOS hỗ trợ cả JPEG và JPEG 2000 native)
    UIImage *image = [UIImage imageWithData:imageData];
    if (image) {
        CGImageRef cg = image.CGImage;
        NSLog(@"[DG2Parser] Decoded: %zux%zu px, scale=%.1f",
              CGImageGetWidth(cg), CGImageGetHeight(cg), image.scale);
        return image;
    }

    // Cắt đuôi theo EOF JPEG: FF D9 nếu có metadata thừa ở cuối
    NSData *trimmed = [self trimJPEGData:imageData];
    if (trimmed) {
        image = [UIImage imageWithData:trimmed];
        if (image) return image;
    }

    return nil;
}

+ (NSData *)exportToJPG:(UIImage *)image quality:(CGFloat)quality {
    if (!image) return nil;
    return UIImageJPEGRepresentation(image, quality);
}

// MARK: - Private Helpers

+ (NSInteger)findImageOffsetInData:(NSData *)data {
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger count = data.length;

    // 1. JPEG Magic: FF D8 FF
    for (NSUInteger i = 0; i + 3 <= count; i++) {
        if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8 && bytes[i + 2] == 0xFF) {
            return (NSInteger)i;
        }
    }

    // 2. JPEG 2000 Codestream: FF 4F FF 51
    for (NSUInteger i = 0; i + 4 <= count; i++) {
        if (bytes[i] == 0xFF && bytes[i + 1] == 0x4F && bytes[i + 2] == 0xFF && bytes[i + 3] == 0x51) {
            return (NSInteger)i;
        }
    }

    // 3. JPEG 2000 JP2 Container: 00 00 00 0C 6A 50 20 20
    for (NSUInteger i = 0; i + 8 <= count; i++) {
        if (bytes[i] == 0x00 && bytes[i + 1] == 0x00 && bytes[i + 2] == 0x00 && bytes[i + 3] == 0x0C &&
            bytes[i + 4] == 0x6A && bytes[i + 5] == 0x50 && bytes[i + 6] == 0x20 && bytes[i + 7] == 0x20) {
            return (NSInteger)i;
        }
    }

    return -1;
}

+ (NSData *)trimJPEGData:(NSData *)data {
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSInteger count = (NSInteger)data.length;

    for (NSInteger i = count - 2; i >= 0; i--) {
        if (bytes[i] == 0xFF && bytes[i + 1] == 0xD9) {
            return [data subdataWithRange:NSMakeRange(0, i + 2)];
        }
    }
    return nil;
}

@end
