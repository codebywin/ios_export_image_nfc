#import <Foundation/Foundation.h>
#import <CoreNFC/CoreNFC.h>

@interface BACSession : NSObject

@property (nonatomic, strong, readonly) NSData *ksEnc;
@property (nonatomic, strong, readonly) NSData *ksMac;

- (instancetype)initWithKsEnc:(NSData *)ksEnc ksMac:(NSData *)ksMac initialSSC:(uint64_t)initialSSC;

// Helper tạo lệnh APDU chuẩn byte buffer cho NFCISO7816APDU
+ (NFCISO7816APDU *)createAPDUWithCla:(uint8_t)cla
                                  ins:(uint8_t)ins
                                   p1:(uint8_t)p1
                                   p2:(uint8_t)p2
                                 data:(NSData *)data
                                   le:(NSInteger)le;

// Wrap plain APDU into Secure Messaging APDU
- (NFCISO7816APDU *)wrapCommandWithCla:(uint8_t)cla
                                   ins:(uint8_t)ins
                                    p1:(uint8_t)p1
                                    p2:(uint8_t)p2
                                  data:(NSData *)data
                                    le:(NSInteger)le;

// Unwrap Secure Messaging Response APDU
- (NSData *)unwrapResponseData:(NSData *)respData sw1:(uint8_t *)outSw1 sw2:(uint8_t *)outSw2;

@end
