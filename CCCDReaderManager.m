#import "CCCDReaderManager.h"
#import "CryptoUtils.h"
#import "BACSession.h"
#import "DG2Parser.h"
#import <Security/SecRandom.h>

@interface CCCDReaderManager ()
@property (nonatomic, strong) NFCTagReaderSession *session;
@property (nonatomic, strong) BACSession *bacSession;
@property (nonatomic, assign) uint8_t lastErrorSW1;
@property (nonatomic, assign) uint8_t lastErrorSW2;
@end

@implementation CCCDReaderManager

// Ghi log ra file để đọc được qua SSH (thử nhiều path vì sandbox jailbreak khác nhau)
+ (void)log:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"[CCCD] %@", msg);

    static NSArray<NSString *> *logPaths = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        logPaths = @[
            @"/tmp/cccd_debug.log",
            [docs stringByAppendingPathComponent:@"cccd_debug.log"],
            [caches stringByAppendingPathComponent:@"cccd_debug.log"],
            @"/var/mobile/Library/Caches/cccd_debug.log",
        ];
    });

    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    dispatch_async(queue, ^{
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

- (instancetype)initWithCandidateSeeds:(NSArray<NSData *> *)candidateSeeds {
    self = [super init];
    if (self) {
        _candidateSeeds = [candidateSeeds copy];
    }
    return self;
}

- (instancetype)initWithSeed:(NSData *)seed {
    if (seed) {
        return [self initWithCandidateSeeds:@[seed]];
    }
    return [self initWithCandidateSeeds:@[]];
}

- (void)updateCandidateSeeds:(NSArray<NSData *> *)candidateSeeds {
    self.candidateSeeds = [candidateSeeds copy];
}

- (void)updateSeed:(NSData *)seed {
    if (seed) {
        self.candidateSeeds = @[seed];
    }
}

- (void)startScanning {
    [CCCDReaderManager log:@"startScanning called, NFC readingAvailable=%d", [NFCReaderSession readingAvailable]];
    if (![NFCReaderSession readingAvailable]) {
        if ([self.delegate respondsToSelector:@selector(cccdReaderDidFailWithError:)]) {
            [self.delegate cccdReaderDidFailWithError:@"Thiết bị không hỗ trợ NFC hoặc chưa bật NFC."];
        }
        return;
    }

    self.session = [[NFCTagReaderSession alloc] initWithPollingOption:NFCPollingISO14443
                                                             delegate:self
                                                                queue:dispatch_get_main_queue()];
    self.session.alertMessage = @"Áp phần trên lưng iPhone sát vào chip tròn ở mặt sau thẻ CCCD...";
    [self.session beginSession];

    if ([self.delegate respondsToSelector:@selector(cccdReaderDidStartScanning)]) {
        [self.delegate cccdReaderDidStartScanning];
    }
}

- (void)stopScanning {
    if (self.session) {
        [self.session invalidateSession];
        self.session = nil;
    }
}

// MARK: - NFCTagReaderSessionDelegate

- (void)tagReaderSessionDidBecomeActive:(NFCTagReaderSession *)session {
    // Sẵn sàng đọc thẻ
}

- (void)tagReaderSession:(NFCTagReaderSession *)session didInvalidateWithError:(NSError *)error {
    if (error.code != NFCReaderSessionInvalidationErrorUserCanceled) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(cccdReaderDidFailWithError:)]) {
                [self.delegate cccdReaderDidFailWithError:error.localizedDescription];
            }
        });
    }
}

- (void)tagReaderSession:(NFCTagReaderSession *)session didDetectTags:(NSArray<__kindof id<NFCTag>> *)tags {
    id<NFCTag> tag = tags.firstObject;
    if (!tag) return;

    id<NFCISO7816Tag> iso7816Tag = [tag asNFCISO7816Tag];
    if (!iso7816Tag) {
        [session invalidateSessionWithErrorMessage:@"Thẻ không đúng chuẩn ISO 7816."];
        return;
    }

    [session connectToTag:tag completionHandler:^(NSError * _Nullable error) {
        if (error) {
            [session invalidateSessionWithErrorMessage:[NSString stringWithFormat:@"Lỗi kết nối: %@", error.localizedDescription]];
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(cccdReaderDidUpdateStatus:)]) {
                [self.delegate cccdReaderDidUpdateStatus:@"Đã kết nối chip thẻ CCCD..."];
            }
        });

        [CCCDReaderManager log:@"Tag connected, starting BAC process"];
        [self processCCCDWithTag:iso7816Tag session:session];
    }];
}

// MARK: - Process CCCD

- (void)processCCCDWithTag:(id<NFCISO7816Tag>)tag session:(NFCTagReaderSession *)session {
    // 1. SELECT Application AID: A0 00 00 02 47 10 01 (eMRTD)
    uint8_t aidBytes[] = {0xA0, 0x00, 0x00, 0x02, 0x47, 0x10, 0x01};
    NSData *aidData = [NSData dataWithBytes:aidBytes length:sizeof(aidBytes)];

    NFCISO7816APDU *selectAID = [BACSession createAPDUWithCla:0x00
                                                          ins:0xA4
                                                           p1:0x04
                                                           p2:0x0C
                                                         data:aidData
                                                           le:-1];

    [tag sendCommandAPDU:selectAID completionHandler:^(NSData * _Nonnull responseData, uint8_t sw1, uint8_t sw2, NSError * _Nullable error) {
        if (sw1 != 0x90 || sw2 != 0x00) {
            [session invalidateSessionWithErrorMessage:@"Không tìm thấy applet eMRTD trên thẻ."];
            return;
        }

        if (self.candidateSeeds.count == 0) {
            [session invalidateSessionWithErrorMessage:@"Không có thông tin khóa xác thực BAC."];
            return;
        }

        [self tryBACWithCandidateIndex:0 tag:tag session:session completion:^(BOOL success) {
            if (success) {
                session.alertMessage = @"Đang đọc ảnh chân dung (DG2)... Giữ yên thẻ.";
                [CCCDReaderManager log:@"BAC OK, now reading DG2"];
                [self readDG2WithTag:tag session:session];
            } else {
                NSString *err = [NSString stringWithFormat:@"Xác thực chip thất bại (SW=%02X%02X). Vui lòng kiểm tra lại Số CCCD/Ngày sinh.", self.lastErrorSW1, self.lastErrorSW2];
                [session invalidateSessionWithErrorMessage:err];
            }
        }];
    }];
}

// MARK: - BAC Authentication (Multi-candidate retry loop)

- (void)tryBACWithCandidateIndex:(NSUInteger)index
                             tag:(id<NFCISO7816Tag>)tag
                         session:(NFCTagReaderSession *)session
                      completion:(void(^)(BOOL success))completion {

    if (index >= self.candidateSeeds.count) {
        completion(NO);
        return;
    }

    session.alertMessage = [NSString stringWithFormat:@"Đang xác thực chip CCCD (%lu/%lu)... Giữ yên thẻ.", (unsigned long)index + 1, (unsigned long)self.candidateSeeds.count];

    NSData *currentSeed = self.candidateSeeds[index];
    NSData *kEnc = nil;
    NSData *kMac = nil;
    if (![CryptoUtils deriveBACKeysWithSeed:currentSeed kEnc:&kEnc kMac:&kMac]) {
        [self tryBACWithCandidateIndex:index + 1 tag:tag session:session completion:completion];
        return;
    }

    void (^performChallengeAndAuth)(void) = ^{
        // GET CHALLENGE: 00 84 00 00 08
        NFCISO7816APDU *getChallenge = [BACSession createAPDUWithCla:0x00
                                                                 ins:0x84
                                                                  p1:0x00
                                                                  p2:0x00
                                                                data:nil
                                                                  le:8];

        [tag sendCommandAPDU:getChallenge completionHandler:^(NSData * _Nonnull respData, uint8_t sw1, uint8_t sw2, NSError * _Nullable error) {
            if (sw1 != 0x90 || sw2 != 0x00 || respData.length != 8) {
                self.lastErrorSW1 = sw1;
                self.lastErrorSW2 = sw2;
                [CCCDReaderManager log:@"GET CHALLENGE failed for candidate #%lu: sw1=%02X sw2=%02X, len=%lu", (unsigned long)index + 1, sw1, sw2, (unsigned long)respData.length];
                [self tryBACWithCandidateIndex:index + 1 tag:tag session:session completion:completion];
                return;
            }

            NSData *rndICC = respData;

            // Sinh ngẫu nhiên RND.IFD (8 bytes) và k_ifd (16 bytes)
            uint8_t rndIFDBytes[8];
            uint8_t kIFDBytes[16];
            (void)SecRandomCopyBytes(kSecRandomDefault, 8, rndIFDBytes);
            (void)SecRandomCopyBytes(kSecRandomDefault, 16, kIFDBytes);

            NSData *rndIFD = [NSData dataWithBytes:rndIFDBytes length:8];
            NSData *kIFD = [NSData dataWithBytes:kIFDBytes length:16];

            // S = RND.IFD || RND.ICC || k_ifd (32 bytes)
            NSMutableData *s = [NSMutableData data];
            [s appendData:rndIFD];
            [s appendData:rndICC];
            [s appendData:kIFD];

            NSData *eIFD = [CryptoUtils tripleDESEncryptCBC:s key:kEnc iv:nil];
            NSData *mIFD = [CryptoUtils calculateRetailMAC:eIFD key:kMac];
            if (!eIFD || !mIFD) {
                [self tryBACWithCandidateIndex:index + 1 tag:tag session:session completion:completion];
                return;
            }

            // EXTERNAL AUTHENTICATE: 00 82 00 00 28 [eIFD || mIFD] 28
            NSMutableData *authData = [NSMutableData data];
            [authData appendData:eIFD];
            [authData appendData:mIFD];

            NFCISO7816APDU *extAuth = [BACSession createAPDUWithCla:0x00
                                                                ins:0x82
                                                                 p1:0x00
                                                                 p2:0x00
                                                               data:authData
                                                                 le:0x28];

            [tag sendCommandAPDU:extAuth completionHandler:^(NSData * _Nonnull authResp, uint8_t aSw1, uint8_t aSw2, NSError * _Nullable aErr) {
                if (aSw1 == 0x90 && aSw2 == 0x00 && authResp.length >= 40) {
                    NSData *eICC = [authResp subdataWithRange:NSMakeRange(0, 32)];
                    NSData *mICC = [authResp subdataWithRange:NSMakeRange(32, 8)];

                    // Kiểm tra MAC từ thẻ
                    NSData *expectedMICC = [CryptoUtils calculateRetailMAC:eICC key:kMac];
                    if ([expectedMICC isEqualToData:mICC]) {
                        // Giải mã eICC
                        NSData *decryptedICC = [CryptoUtils tripleDESDecryptCBC:eICC key:kEnc iv:nil];
                        if (decryptedICC && decryptedICC.length >= 32) {
                            NSData *respRndICC = [decryptedICC subdataWithRange:NSMakeRange(0, 8)];
                            NSData *respRndIFD = [decryptedICC subdataWithRange:NSMakeRange(8, 8)];
                            NSData *kICC = [decryptedICC subdataWithRange:NSMakeRange(16, 16)];

                            if ([respRndIFD isEqualToData:rndIFD]) {
                                // K_seed_session = kIFD XOR kICC
                                const uint8_t *kIFDBytesPtr = (const uint8_t *)kIFD.bytes;
                                const uint8_t *kICCBytesPtr = (const uint8_t *)kICC.bytes;
                                uint8_t sessionSeedBytes[16];
                                for (int i = 0; i < 16; i++) {
                                    sessionSeedBytes[i] = kIFDBytesPtr[i] ^ kICCBytesPtr[i];
                                }
                                NSData *sessionSeed = [NSData dataWithBytes:sessionSeedBytes length:16];

                                NSData *ksEnc = nil;
                                NSData *ksMac = nil;
                                if ([CryptoUtils deriveBACKeysWithSeed:sessionSeed kEnc:&ksEnc kMac:&ksMac]) {
                                    // SSC ban đầu: RND.ICC[4..8] || RND.IFD[4..8]
                                    NSMutableData *sscData = [NSMutableData data];
                                    [sscData appendData:[respRndICC subdataWithRange:NSMakeRange(4, 4)]];
                                    [sscData appendData:[rndIFD subdataWithRange:NSMakeRange(4, 4)]];

                                    uint64_t initialSSC = 0;
                                    memcpy(&initialSSC, sscData.bytes, 8);
                                    initialSSC = CFSwapInt64BigToHost(initialSSC);

                                    self.bacSession = [[BACSession alloc] initWithKsEnc:ksEnc ksMac:ksMac initialSSC:initialSSC];
                                    [CCCDReaderManager log:@"BAC SUCCESS at candidate #%lu, initialSSC=0x%llX", (unsigned long)index + 1, initialSSC];
                                    completion(YES);
                                    return;
                                }
                            }
                        }
                    }
                }

                self.lastErrorSW1 = aSw1;
                self.lastErrorSW2 = aSw2;
                [CCCDReaderManager log:@"BAC candidate #%lu FAILED (SW: %02X %02X). Trying next...", (unsigned long)index + 1, aSw1, aSw2];
                [self tryBACWithCandidateIndex:index + 1 tag:tag session:session completion:completion];
            }];
        }];
    };

    if (index > 0) {
        // Re-select AID để reset security environment của thẻ sau lệnh thất bại
        uint8_t aidBytes[] = {0xA0, 0x00, 0x00, 0x02, 0x47, 0x10, 0x01};
        NSData *aidData = [NSData dataWithBytes:aidBytes length:sizeof(aidBytes)];
        NFCISO7816APDU *selectAID = [BACSession createAPDUWithCla:0x00
                                                              ins:0xA4
                                                               p1:0x04
                                                               p2:0x0C
                                                             data:aidData
                                                               le:-1];
        [tag sendCommandAPDU:selectAID completionHandler:^(NSData * _Nonnull resp, uint8_t sSw1, uint8_t sSw2, NSError * _Nullable sErr) {
            performChallengeAndAuth();
        }];
    } else {
        performChallengeAndAuth();
    }
}

// MARK: - Read DG2 (Data Group 2)

- (void)readDG2WithTag:(id<NFCISO7816Tag>)tag session:(NFCTagReaderSession *)session {
    if (!self.bacSession) return;

    // 1. SELECT FILE (01 02: DG2)
    uint8_t fileId[] = {0x01, 0x02};
    NFCISO7816APDU *selectDG2 = [self.bacSession wrapCommandWithCla:0x00
                                                                ins:0xA4
                                                                 p1:0x02
                                                                 p2:0x0C
                                                               data:[NSData dataWithBytes:fileId length:2]
                                                                 le:-1];

    [tag sendCommandAPDU:selectDG2 completionHandler:^(NSData * _Nonnull respData, uint8_t sw1, uint8_t sw2, NSError * _Nullable error) {
        [CCCDReaderManager log:@"SELECT DG2 (01 02) - SW=%02X%02X, response len=%lu, hex=%@", sw1, sw2, (unsigned long)respData.length, respData];
        
        // Bắt buộc unwrap response của SELECT để đồng bộ SSC.
        // Nếu bỏ qua, MAC của lệnh READ BINARY tiếp theo sẽ sai và thẻ trả 6988.
        uint8_t selSw1 = 0, selSw2 = 0;
        NSData *selPlain = [self.bacSession unwrapResponseData:respData sw1:&selSw1 sw2:&selSw2];
        [CCCDReaderManager log:@"SELECT DG2 unwrapped - SW=%02X%02X, plain len=%lu", selSw1, selSw2, (unsigned long)(selPlain ? selPlain.length : 0)];
        
        if (sw1 != 0x90 || sw2 != 0x00) {
            [CCCDReaderManager log:@"WARNING: SELECT DG2 returned SW=%02X%02X", sw1, sw2];
        }
        
        // 2. READ BINARY 8 bytes đầu để lấy TLV header: 61 75 <len>
        NFCISO7816APDU *readHdr = [self.bacSession wrapCommandWithCla:0x00
                                                                  ins:0xB0
                                                                   p1:0x00
                                                                   p2:0x00
                                                                 data:[NSData data]
                                                                   le:0x08];

        [tag sendCommandAPDU:readHdr completionHandler:^(NSData * _Nonnull hdrResp, uint8_t hSw1, uint8_t hSw2, NSError * _Nullable hErr) {
            [CCCDReaderManager log:@"READ BINARY header response - SW=%02X%02X, encrypted length=%lu, hex=%@", hSw1, hSw2, (unsigned long)hdrResp.length, hdrResp];
            
            uint8_t outSw1 = 0, outSw2 = 0;
            NSData *plainHdr = [self.bacSession unwrapResponseData:hdrResp sw1:&outSw1 sw2:&outSw2];
            
            [CCCDReaderManager log:@"After unwrap - SW=%02X%02X, plaintext length=%lu, hex=%@", outSw1, outSw2, (unsigned long)(plainHdr ? plainHdr.length : 0), plainHdr];
            
            if (!plainHdr || plainHdr.length < 4) {
                [CCCDReaderManager log:@"ERROR: Cannot read DG2 header. plainHdr=%@, len=%lu, SW=%02X%02X", plainHdr, (unsigned long)(plainHdr ? plainHdr.length : 0), outSw1, outSw2];
                [session invalidateSessionWithErrorMessage:@"Không thể đọc header kích thước DG2."];
                return;
            }

            NSUInteger totalLen = [self parseDG2Length:plainHdr];
            if (totalLen == 0) {
                [session invalidateSessionWithErrorMessage:@"Không thể parse kích thước DG2. Format header không hợp lệ."];
                return;
            }
            
            NSLog(@"[DG2] Tổng kích thước cần đọc: %lu bytes", (unsigned long)totalLen);
            [self readRemainingDG2WithTag:tag session:session totalLength:totalLen accumulated:[plainHdr mutableCopy]];
        }];
    }];
}

- (void)readRemainingDG2WithTag:(id<NFCISO7816Tag>)tag
                        session:(NFCTagReaderSession *)session
                    totalLength:(NSUInteger)totalLength
                    accumulated:(NSMutableData *)accumulated {

    NSUInteger offset = accumulated.length;
    if (offset >= totalLength) {
        // Hoàn thành đọc DG2
        [session setAlertMessage:@"Giải mã ảnh chân dung thành công!"];
        [session invalidateSession];

        dispatch_async(dispatch_get_main_queue(), ^{
            UIImage *image = [DG2Parser extractImageFromDG2Data:accumulated];
            if (image) {
                if ([self.delegate respondsToSelector:@selector(cccdReaderDidFinishWithSuccess:rawData:)]) {
                    [self.delegate cccdReaderDidFinishWithSuccess:image rawData:accumulated];
                }
            } else {
                if ([self.delegate respondsToSelector:@selector(cccdReaderDidFailWithError:)]) {
                    [self.delegate cccdReaderDidFailWithError:@"Đã tải xong DG2 nhưng không giải mã được ảnh."];
                }
            }
        });
        return;
    }

    NSUInteger chunkSize = MIN(224, totalLength - offset);
    uint8_t p1 = (uint8_t)((offset >> 8) & 0xFF);
    uint8_t p2 = (uint8_t)(offset & 0xFF);

    NFCISO7816APDU *readCmd = [self.bacSession wrapCommandWithCla:0x00
                                                              ins:0xB0
                                                               p1:p1
                                                               p2:p2
                                                             data:[NSData data]
                                                               le:chunkSize];

    NSUInteger progress = (NSUInteger)((double)offset / (double)totalLength * 100);
    session.alertMessage = [NSString stringWithFormat:@"Đang tải ảnh chân dung: %lu%%... Giữ yên thẻ.", (unsigned long)progress];

    [tag sendCommandAPDU:readCmd completionHandler:^(NSData * _Nonnull chunkResp, uint8_t sw1, uint8_t sw2, NSError * _Nullable error) {
        [CCCDReaderManager log:@"READ chunk offset=%lu, chunk=%lu -> response len=%lu, SW=%02X%02X, hex=%@", (unsigned long)offset, (unsigned long)chunkSize, (unsigned long)chunkResp.length, sw1, sw2, chunkResp];
        
        uint8_t oSw1 = 0, oSw2 = 0;
        NSData *plainChunk = [self.bacSession unwrapResponseData:chunkResp sw1:&oSw1 sw2:&oSw2];
        if (!plainChunk || plainChunk.length == 0) {
            [CCCDReaderManager log:@"READ chunk failed at offset %lu: plainChunk empty, unwrap SW=%02X%02X", (unsigned long)offset, oSw1, oSw2];
            [session invalidateSessionWithErrorMessage:@"Đứt kết nối khi đang tải ảnh."];
            return;
        }

        [accumulated appendData:plainChunk];
        [self readRemainingDG2WithTag:tag session:session totalLength:totalLength accumulated:accumulated];
    }];
}

- (NSUInteger)parseDG2Length:(NSData *)header {
    const uint8_t *bytes = (const uint8_t *)header.bytes;
    NSUInteger len = header.length;
    
    if (len < 4) {
        [CCCDReaderManager log:@"DG2 header too short (%lu bytes): %@", (unsigned long)len, header];
        return 0;
    }
    
    // Duyệt TLV: tag 0x75 = Biometric Reference Template
    NSUInteger offset = 0;
    while (offset + 2 < len) {
        uint8_t tag = bytes[offset];
        NSUInteger length = 0;
        NSUInteger lenBytePos = offset + 1;
        
        if (lenBytePos >= len) break;
        
        uint8_t lenByte = bytes[lenBytePos];
        NSUInteger lengthBytes = 1;
        
        if (lenByte < 0x80) {
            length = lenByte;
        } else if (lenByte == 0x81 && lenBytePos + 1 < len) {
            length = bytes[lenBytePos + 1];
            lengthBytes = 2;
        } else if (lenByte == 0x82 && lenBytePos + 2 < len) {
            length = ((NSUInteger)bytes[lenBytePos + 1] << 8) | bytes[lenBytePos + 2];
            lengthBytes = 3;
        } else {
            [CCCDReaderManager log:@"Invalid TLV length encoding at offset %lu", (unsigned long)offset];
            break;
        }
        
        // Nếu tag là 0x75, đây là Biometric Reference Template
        if (tag == 0x75 || tag == 0x7F) {
            NSUInteger totalLen = offset + 1 + lengthBytes + length;
            [CCCDReaderManager log:@"Found tag 0x%02X at offset %lu, length=%lu, total DG2 size=%lu", tag, (unsigned long)offset, (unsigned long)length, (unsigned long)totalLen];
            return totalLen;
        }
        
        // Di chuyển đến TLV tiếp theo
        offset = lenBytePos + lengthBytes + length;
    }
    
    // Fallback: parse kiểu cũ
    if (bytes[2] == 0x81 && len >= 4) {
        return (NSUInteger)bytes[3] + 4;
    }
    if (bytes[2] == 0x82 && len >= 5) {
        return (((NSUInteger)bytes[3]) << 8 | bytes[4]) + 5;
    }
    
    [CCCDReaderManager log:@"Cannot find tag 0x75/0x7F in DG2 header. Hex: %@", header];
    return 0;
}

@end
