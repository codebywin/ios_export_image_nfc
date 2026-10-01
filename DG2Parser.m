#import "DG2Parser.h"

@implementation DG2Parser

+ (void)log:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    static NSArray<NSString *> *logPaths = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        logPaths = @[
            @"/var/mobile/Library/Caches/cccd_debug.log",
            [docs stringByAppendingPathComponent:@"cccd_debug.log"],
        ];
    });

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        for (NSString *path in logPaths) {
            NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
            if (!fh) {
                [[NSFileManager defaultManager] createFileAtPath:path contents:data attributes:nil];
            } else {
                [fh seekToEndOfFile];
                [fh writeData:data];
                [fh closeFile];
            }
        }
    });
}

+ (UIImage *)extractImageFromDG2Data:(NSData *)dg2Data {
    [DG2Parser log:@"extractImageFromDG2Data called, dg2 length=%lu", (unsigned long)(dg2Data ? dg2Data.length : 0)];
    if (!dg2Data || dg2Data.length < 4) return nil;

    NSInteger offset = [self findImageOffsetInData:dg2Data];
    if (offset < 0) {
        [DG2Parser log:@"No JPEG/JPEG2000 header found in DG2"];
        return nil;
    }

    NSData *imageData = [dg2Data subdataWithRange:NSMakeRange(offset, dg2Data.length - offset)];

    const uint8_t *h = (const uint8_t *)imageData.bytes;
    [DG2Parser log:@"Image offset=%ld, image length=%lu bytes, header: %02X %02X %02X %02X %02X %02X %02X %02X",
          (long)offset, (unsigned long)imageData.length, h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7]];

    // Dump ảnh thô ra nhiều vị trí để phân tích
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSArray<NSString *> *dumpPaths = @[
        @"/var/mobile/Library/Caches/dg2_face_raw.bin",
        [docs stringByAppendingPathComponent:@"dg2_face_raw.bin"],
    ];
    for (NSString *p in dumpPaths) {
        BOOL ok = [imageData writeToFile:p atomically:YES];
        [DG2Parser log:@"Dump to %@: %@", p, ok ? @"OK" : @"FAILED"];
    }

    // Khởi tạo UIImage từ dữ liệu ảnh (iOS hỗ trợ cả JPEG và JPEG 2000 native)
    UIImage *image = [UIImage imageWithData:imageData];
    if (image) {
        CGImageRef cg = image.CGImage;
        [DG2Parser log:@"Decoded OK: %zux%zu px, scale=%.1f", CGImageGetWidth(cg), CGImageGetHeight(cg), image.scale];
        return image;
    }
    [DG2Parser log:@"UIImage imageWithData returned nil, trying trim"];

    // Cắt đuôi theo EOF JPEG: FF D9 nếu có metadata thừa ở cuối
    NSData *trimmed = [self trimJPEGData:imageData];
    if (trimmed) {
        image = [UIImage imageWithData:trimmed];
        if (image) {
            CGImageRef cg = image.CGImage;
            [DG2Parser log:@"Decoded after trim: %zux%zu px", CGImageGetWidth(cg), CGImageGetHeight(cg)];
            return image;
        }
        [DG2Parser log:@"Trim data also failed to decode"];
    }

    [DG2Parser log:@"All decode attempts failed"];
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
