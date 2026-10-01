#import "CryptoUtils.h"
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonDigest.h>

@implementation CryptoUtils

// MARK: - SHA-1
+ (NSData *)sha1:(NSData *)data {
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
    return [NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH];
}

// MARK: - DES Parity Adjustment
+ (NSData *)adjustDESParity:(NSData *)key {
    const uint8_t *bytes = (const uint8_t *)key.bytes;
    NSMutableData *result = [NSMutableData dataWithCapacity:key.length];
    for (NSUInteger i = 0; i < key.length; i++) {
        uint8_t b = bytes[i] & 0xFE;
        int bits = 0;
        for (int bit = 1; bit <= 7; bit++) {
            if ((b >> bit) & 1) {
                bits++;
            }
        }
        if (bits % 2 == 0) {
            b |= 1;
        }
        [result appendBytes:&b length:1];
    }
    return [result copy];
}

// MARK: - Padding ISO 9797-1 Method 2
+ (NSData *)padISO9797Method2:(NSData *)data blockSize:(NSUInteger)blockSize {
    NSMutableData *padded = [data mutableCopy];
    uint8_t padByte = 0x80;
    [padded appendBytes:&padByte length:1];
    uint8_t zero = 0x00;
    while (padded.length % blockSize != 0) {
        [padded appendBytes:&zero length:1];
    }
    return [padded copy];
}

+ (NSData *)unpadISO9797Method2:(NSData *)data {
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSInteger idx = (NSInteger)data.length - 1;
    while (idx >= 0 && bytes[idx] == 0x00) {
        idx--;
    }
    if (idx >= 0 && bytes[idx] == 0x80) {
        return [data subdataWithRange:NSMakeRange(0, idx)];
    }
    return nil;
}

// MARK: - Triple DES (CBC Mode)
+ (NSData *)tripleDESEncryptCBC:(NSData *)data key:(NSData *)key iv:(NSData *)iv {
    NSMutableData *expandedKey = [key mutableCopy];
    if (expandedKey.length == 16) {
        [expandedKey appendData:[key subdataWithRange:NSMakeRange(0, 8)]];
    }
    
    NSMutableData *ivData = iv ? [iv mutableCopy] : [NSMutableData dataWithLength:8];
    size_t outMoved = 0;
    NSMutableData *outData = [NSMutableData dataWithLength:data.length + 16];
    
    CCCryptorStatus status = CCCrypt(
        kCCEncrypt,
        kCCAlgorithm3DES,
        0, // CBC, no auto padding
        expandedKey.bytes,
        expandedKey.length,
        ivData.bytes,
        data.bytes,
        data.length,
        outData.mutableBytes,
        outData.length,
        &outMoved
    );
    
    if (status == kCCSuccess) {
        [outData setLength:outMoved];
        return outData;
    }
    return nil;
}

+ (NSData *)tripleDESDecryptCBC:(NSData *)data key:(NSData *)key iv:(NSData *)iv {
    NSMutableData *expandedKey = [key mutableCopy];
    if (expandedKey.length == 16) {
        [expandedKey appendData:[key subdataWithRange:NSMakeRange(0, 8)]];
    }
    
    NSMutableData *ivData = iv ? [iv mutableCopy] : [NSMutableData dataWithLength:8];
    size_t outMoved = 0;
    NSMutableData *outData = [NSMutableData dataWithLength:data.length + 16];
    
    CCCryptorStatus status = CCCrypt(
        kCCDecrypt,
        kCCAlgorithm3DES,
        0, // CBC
        expandedKey.bytes,
        expandedKey.length,
        ivData.bytes,
        data.bytes,
        data.length,
        outData.mutableBytes,
        outData.length,
        &outMoved
    );
    
    if (status == kCCSuccess) {
        [outData setLength:outMoved];
        return outData;
    }
    return nil;
}

// MARK: - Single DES ECB
+ (NSData *)desEncryptECB:(NSData *)data key:(NSData *)key {
    size_t outMoved = 0;
    NSMutableData *outData = [NSMutableData dataWithLength:data.length + 8];
    
    CCCryptorStatus status = CCCrypt(
        kCCEncrypt,
        kCCAlgorithmDES,
        kCCOptionECBMode,
        key.bytes,
        key.length,
        NULL,
        data.bytes,
        data.length,
        outData.mutableBytes,
        outData.length,
        &outMoved
    );
    
    if (status == kCCSuccess) {
        [outData setLength:outMoved];
        return outData;
    }
    return nil;
}

+ (NSData *)desDecryptECB:(NSData *)data key:(NSData *)key {
    size_t outMoved = 0;
    NSMutableData *outData = [NSMutableData dataWithLength:data.length + 8];
    
    CCCryptorStatus status = CCCrypt(
        kCCDecrypt,
        kCCAlgorithmDES,
        kCCOptionECBMode,
        key.bytes,
        key.length,
        NULL,
        data.bytes,
        data.length,
        outData.mutableBytes,
        outData.length,
        &outMoved
    );
    
    if (status == kCCSuccess) {
        [outData setLength:outMoved];
        return outData;
    }
    return nil;
}

// MARK: - Retail MAC (ISO 9797-1 MAC Algorithm 3)
+ (NSData *)calculateRetailMAC:(NSData *)data key:(NSData *)key {
    if (key.length != 16) return nil;
    NSData *kA = [key subdataWithRange:NSMakeRange(0, 8)];
    NSData *kB = [key subdataWithRange:NSMakeRange(8, 8)];
    
    NSData *padded = [self padISO9797Method2:data blockSize:8];
    uint8_t currentBlock[8] = {0};
    NSUInteger blockCount = padded.length / 8;
    const uint8_t *paddedBytes = (const uint8_t *)padded.bytes;
    
    for (NSUInteger i = 0; i < blockCount; i++) {
        uint8_t xorBlock[8];
        for (int j = 0; j < 8; j++) {
            xorBlock[j] = currentBlock[j] ^ paddedBytes[i * 8 + j];
        }
        NSData *enc = [self desEncryptECB:[NSData dataWithBytes:xorBlock length:8] key:kA];
        if (!enc || enc.length < 8) return nil;
        memcpy(currentBlock, enc.bytes, 8);
    }
    
    NSData *lastData = [NSData dataWithBytes:currentBlock length:8];
    NSData *decB = [self desDecryptECB:lastData key:kB];
    if (!decB) return nil;
    NSData *finalMAC = [self desEncryptECB:decB key:kA];
    return finalMAC;
}

// MARK: - BAC Key Derivation
+ (BOOL)deriveBACKeysWithSeed:(NSData *)seed kEnc:(NSData **)outEnc kMac:(NSData **)outMac {
    if (seed.length < 16) return NO;
    NSData *seedSlice = [seed subdataWithRange:NSMakeRange(0, 16)];
    
    // kEnc
    NSMutableData *encInput = [seedSlice mutableCopy];
    uint8_t encSuffix[4] = {0x00, 0x00, 0x00, 0x01};
    [encInput appendBytes:encSuffix length:4];
    NSData *hashEnc = [self sha1:encInput];
    *outEnc = [self adjustDESParity:[hashEnc subdataWithRange:NSMakeRange(0, 16)]];
    
    // kMac
    NSMutableData *macInput = [seedSlice mutableCopy];
    uint8_t macSuffix[4] = {0x00, 0x00, 0x00, 0x02};
    [macInput appendBytes:macSuffix length:4];
    NSData *hashMac = [self sha1:macInput];
    *outMac = [self adjustDESParity:[hashMac subdataWithRange:NSMakeRange(0, 16)]];
    
    return YES;
}

// MARK: - ICAO Check Digit
+ (NSString *)calculateCheckDigit:(NSString *)input {
    int weights[] = {7, 3, 1};
    int sum = 0;
    NSString *upper = [input uppercaseString];
    for (NSUInteger i = 0; i < upper.length; i++) {
        unichar c = [upper characterAtIndex:i];
        int val = 0;
        if (c >= '0' && c <= '9') {
            val = c - '0';
        } else if (c >= 'A' && c <= 'Z') {
            val = c - 'A' + 10;
        } else if (c == '<') {
            val = 0;
        }
        sum += val * weights[i % 3];
    }
    return [NSString stringWithFormat:@"%d", sum % 10];
}

+ (NSString *)normalizeDateToYYMMDD:(NSString *)dateStr {
    if (!dateStr || dateStr.length == 0) return nil;
    
    NSMutableString *digits = [NSMutableString string];
    for (NSUInteger i = 0; i < dateStr.length; i++) {
        unichar c = [dateStr characterAtIndex:i];
        if (c >= '0' && c <= '9') {
            [digits appendFormat:@"%C", c];
        }
    }
    
    if (digits.length == 8) {
        NSString *first4 = [digits substringToIndex:4];
        if ([first4 hasPrefix:@"19"] || [first4 hasPrefix:@"20"]) {
            return [digits substringFromIndex:2];
        } else {
            NSString *dd = [digits substringWithRange:NSMakeRange(0, 2)];
            NSString *mm = [digits substringWithRange:NSMakeRange(2, 2)];
            NSString *yy = [digits substringWithRange:NSMakeRange(6, 2)];
            return [NSString stringWithFormat:@"%@%@%@", yy, mm, dd];
        }
    } else if (digits.length == 6) {
        int first2 = [[digits substringWithRange:NSMakeRange(0, 2)] intValue];
        int mid2 = [[digits substringWithRange:NSMakeRange(2, 2)] intValue];
        int last2 = [[digits substringWithRange:NSMakeRange(4, 2)] intValue];
        
        if (last2 > 31 && first2 >= 1 && first2 <= 31 && mid2 >= 1 && mid2 <= 12) {
            NSString *dd = [digits substringWithRange:NSMakeRange(0, 2)];
            NSString *mm = [digits substringWithRange:NSMakeRange(2, 2)];
            NSString *yy = [digits substringWithRange:NSMakeRange(4, 2)];
            return [NSString stringWithFormat:@"%@%@%@", yy, mm, dd];
        }
        return digits;
    }
    return digits.length > 0 ? digits : nil;
}

+ (NSArray<NSData *> *)generateCandidateBACSeedsWithDoc:(NSString *)doc birth:(NSString *)birth expiry:(NSString *)expiry {
    NSMutableArray<NSData *> *seeds = [NSMutableArray array];
    
    NSMutableString *cleanDoc = [NSMutableString string];
    for (NSUInteger i = 0; i < doc.length; i++) {
        unichar c = [doc characterAtIndex:i];
        if ((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) {
            [cleanDoc appendFormat:@"%C", [doc characterAtIndex:i]];
        }
    }
    NSString *docStr = [cleanDoc uppercaseString];
    
    NSMutableArray<NSString *> *docCandidates = [NSMutableArray array];
    if (docStr.length == 12) {
        // Ưu tiên 1: 9 số cuối (Chuẩn Document Number dòng MRZ 1 của CCCD Việt Nam)
        [docCandidates addObject:[docStr substringFromIndex:3]];
        // Ưu tiên 2: Toàn bộ 12 số CCCD
        [docCandidates addObject:docStr];
        // Ưu tiên 3: 9 số đầu (Chuẩn ICAO TD1)
        [docCandidates addObject:[docStr substringToIndex:9]];
    } else if (docStr.length > 0) {
        [docCandidates addObject:docStr];
        if (docStr.length > 9) {
            [docCandidates addObject:[docStr substringFromIndex:docStr.length - 9]];
            [docCandidates addObject:[docStr substringToIndex:9]];
        }
    }
    
    NSString *normDob = [self normalizeDateToYYMMDD:birth];
    NSString *normDoe = [self normalizeDateToYYMMDD:expiry];
    
    NSMutableArray<NSArray<NSString *> *> *datePairs = [NSMutableArray array];
    if (normDob.length == 6 && normDoe.length == 6) {
        [datePairs addObject:@[normDob, normDoe]];
    }
    
    NSMutableString *digitsDob = [NSMutableString string];
    for (NSUInteger i = 0; i < birth.length; i++) {
        unichar c = [birth characterAtIndex:i];
        if (c >= '0' && c <= '9') [digitsDob appendFormat:@"%C", c];
    }
    NSMutableString *digitsDoe = [NSMutableString string];
    for (NSUInteger i = 0; i < expiry.length; i++) {
        unichar c = [expiry characterAtIndex:i];
        if (c >= '0' && c <= '9') [digitsDoe appendFormat:@"%C", c];
    }
    
    if (digitsDob.length == 6 && digitsDoe.length == 6) {
        NSString *swappedDob = [NSString stringWithFormat:@"%@%@%@", [digitsDob substringWithRange:NSMakeRange(4, 2)], [digitsDob substringWithRange:NSMakeRange(2, 2)], [digitsDob substringWithRange:NSMakeRange(0, 2)]];
        NSString *swappedDoe = [NSString stringWithFormat:@"%@%@%@", [digitsDoe substringWithRange:NSMakeRange(4, 2)], [digitsDoe substringWithRange:NSMakeRange(2, 2)], [digitsDoe substringWithRange:NSMakeRange(0, 2)]];
        if (![digitsDob isEqualToString:normDob]) {
            [datePairs addObject:@[digitsDob, digitsDoe]];
        }
        if (![swappedDob isEqualToString:normDob]) {
            [datePairs addObject:@[swappedDob, swappedDoe]];
        }
    }
    
    if (datePairs.count == 0 && birth.length > 0 && expiry.length > 0) {
        [datePairs addObject:@[birth, expiry]];
    }
    
    for (NSString *d in docCandidates) {
        for (NSArray<NSString *> *pair in datePairs) {
            NSData *s = [self calculateBACSeedWithDoc:d birth:pair[0] expiry:pair[1]];
            if (s && ![seeds containsObject:s]) {
                [seeds addObject:s];
            }
        }
    }
    
    return [seeds copy];
}

+ (NSData *)calculateBACSeedWithDoc:(NSString *)doc birth:(NSString *)birth expiry:(NSString *)expiry {
    NSString *cleanDoc = [doc stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *cleanBirth = [birth stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *cleanExpiry = [expiry stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    NSString *docCheck = [self calculateCheckDigit:cleanDoc];
    NSString *birthCheck = [self calculateCheckDigit:cleanBirth];
    NSString *expiryCheck = [self calculateCheckDigit:cleanExpiry];
    
    NSString *mrzString = [NSString stringWithFormat:@"%@%@%@%@%@%@", cleanDoc, docCheck, cleanBirth, birthCheck, cleanExpiry, expiryCheck];
    NSData *hash = [self sha1:[mrzString dataUsingEncoding:NSUTF8StringEncoding]];
    if (hash.length >= 16) {
        return [hash subdataWithRange:NSMakeRange(0, 16)];
    }
    return nil;
}

+ (NSData *)calculateCANSeed:(NSString *)can {
    NSString *cleanCAN = [can stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSData *hash = [self sha1:[cleanCAN dataUsingEncoding:NSUTF8StringEncoding]];
    return [hash subdataWithRange:NSMakeRange(0, 16)];
}

@end
