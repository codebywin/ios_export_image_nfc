#import "BACSession.h"
#import "CryptoUtils.h"

@interface BACSession ()
@property (nonatomic, assign) uint64_t ssc;
@end

@implementation BACSession

+ (NFCISO7816APDU *)createAPDUWithCla:(uint8_t)cla
                                  ins:(uint8_t)ins
                                   p1:(uint8_t)p1
                                   p2:(uint8_t)p2
                                 data:(NSData *)data
                                   le:(NSInteger)le {
    NSMutableData *apdu = [NSMutableData data];
    uint8_t header[] = {cla, ins, p1, p2};
    [apdu appendBytes:header length:4];

    if (data && data.length > 0) {
        if (data.length <= 255) {
            uint8_t lc = (uint8_t)data.length;
            [apdu appendBytes:&lc length:1];
            [apdu appendData:data];
        } else {
            uint8_t lcExtended[] = {0x00, (uint8_t)(data.length >> 8), (uint8_t)(data.length & 0xFF)};
            [apdu appendBytes:lcExtended length:3];
            [apdu appendData:data];
        }
    }

    if (le >= 0) {
        uint8_t leByte = (le == 256 || le == 0) ? 0x00 : (uint8_t)le;
        [apdu appendBytes:&leByte length:1];
    }

    return [[NFCISO7816APDU alloc] initWithData:apdu];
}

- (instancetype)initWithKsEnc:(NSData *)ksEnc ksMac:(NSData *)ksMac initialSSC:(uint64_t)initialSSC {
    self = [super init];
    if (self) {
        _ksEnc = ksEnc;
        _ksMac = ksMac;
        _ssc = initialSSC;
    }
    return self;
}

- (void)incrementSSC {
    _ssc++;
}

- (NSData *)sscData {
    uint64_t bigSSC = CFSwapInt64HostToBig(_ssc);
    return [NSData dataWithBytes:&bigSSC length:sizeof(uint64_t)];
}

// Helper ASN.1 Length encoding
- (NSData *)encodeASN1Length:(NSUInteger)length {
    NSMutableData *d = [NSMutableData data];
    if (length < 128) {
        uint8_t l = (uint8_t)length;
        [d appendBytes:&l length:1];
    } else if (length <= 255) {
        uint8_t hdr[2] = {0x81, (uint8_t)length};
        [d appendBytes:hdr length:2];
    } else {
        uint8_t hdr[3] = {0x82, (uint8_t)(length >> 8), (uint8_t)(length & 0xFF)};
        [d appendBytes:hdr length:3];
    }
    return [d copy];
}

// MARK: - Wrap Command (Secure Messaging ISO/IEC 7816-4)
- (NFCISO7816APDU *)wrapCommandWithCla:(uint8_t)cla
                                   ins:(uint8_t)ins
                                    p1:(uint8_t)p1
                                    p2:(uint8_t)p2
                                  data:(NSData *)data
                                    le:(NSInteger)le {
    [self incrementSSC];

    NSMutableData *do87 = [NSMutableData data];
    if (data && data.length > 0) {
        NSData *paddedData = [CryptoUtils padISO9797Method2:data blockSize:8];
        NSData *encrypted = [CryptoUtils tripleDESEncryptCBC:paddedData key:self.ksEnc iv:nil];
        if (!encrypted) return nil;

        NSMutableData *do87Payload = [NSMutableData dataWithBytes:"\x01" length:1];
        [do87Payload appendData:encrypted];

        uint8_t tag = 0x87;
        [do87 appendBytes:&tag length:1];
        [do87 appendData:[self encodeASN1Length:do87Payload.length]];
        [do87 appendData:do87Payload];
    }

    NSMutableData *do97 = [NSMutableData data];
    if (le >= 0) {
        uint8_t leVal = (le == 256 || le == 0) ? 0x00 : (uint8_t)le;
        uint8_t do97Bytes[3] = {0x97, 0x01, leVal};
        [do97 appendBytes:do97Bytes length:3];
    }

    // Masked Header (CLA = 0x0C indicates Secure Messaging)
    uint8_t maskedHeaderBytes[4] = {0x0C, ins, p1, p2};
    NSData *maskedHeader = [NSData dataWithBytes:maskedHeaderBytes length:4];
    NSData *paddedHeader = [CryptoUtils padISO9797Method2:maskedHeader blockSize:8];

    // Compute MAC on SSC || Padded Header || DO87 || DO97
    NSMutableData *macInput = [[self sscData] mutableCopy];
    [macInput appendData:paddedHeader];
    [macInput appendData:do87];
    [macInput appendData:do97];

    NSData *mac = [CryptoUtils calculateRetailMAC:macInput key:self.ksMac];
    if (!mac || mac.length < 8) return nil;

    NSMutableData *do8E = [NSMutableData dataWithBytes:"\x8E\x08" length:2];
    [do8E appendData:mac];

    NSMutableData *protectedData = [NSMutableData data];
    [protectedData appendData:do87];
    [protectedData appendData:do97];
    [protectedData appendData:do8E];

    return [BACSession createAPDUWithCla:0x0C ins:ins p1:p1 p2:p2 data:protectedData le:0];
}

// MARK: - Unwrap Response
- (NSData *)unwrapResponseData:(NSData *)respData sw1:(uint8_t *)outSw1 sw2:(uint8_t *)outSw2 {
    if (!respData || respData.length < 2) return nil;

    [self incrementSSC];

    const uint8_t *bytes = (const uint8_t *)respData.bytes;
    NSUInteger totalLen = respData.length;
    NSUInteger offset = 0;

    NSData *encData = nil;

    while (offset < totalLen) {
        uint8_t tag = bytes[offset++];
        if (offset >= totalLen) break;

        NSUInteger length = 0;
        uint8_t lenByte = bytes[offset++];
        if (lenByte < 0x80) {
            length = lenByte;
        } else if (lenByte == 0x81 && offset < totalLen) {
            length = bytes[offset++];
        } else if (lenByte == 0x82 && offset + 1 < totalLen) {
            length = ((NSUInteger)bytes[offset] << 8) | bytes[offset + 1];
            offset += 2;
        }

        if (offset + length > totalLen) break;
        NSData *val = [respData subdataWithRange:NSMakeRange(offset, length)];
        offset += length;

        if (tag == 0x87) {
            if (val.length > 1) {
                // Skip 0x01 indicator byte
                encData = [val subdataWithRange:NSMakeRange(1, val.length - 1)];
            }
        }
    }

    if (encData) {
        NSData *decrypted = [CryptoUtils tripleDESDecryptCBC:encData key:self.ksEnc iv:nil];
        if (decrypted) {
            return [CryptoUtils unpadISO9797Method2:decrypted];
        }
    }

    return [NSData data];
}

@end
