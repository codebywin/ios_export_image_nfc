#import <Foundation/Foundation.h>

@interface CryptoUtils : NSObject

+ (NSData *)sha1:(NSData *)data;
+ (NSData *)adjustDESParity:(NSData *)key;
+ (NSData *)padISO9797Method2:(NSData *)data blockSize:(NSUInteger)blockSize;
+ (NSData *)unpadISO9797Method2:(NSData *)data;

+ (NSData *)tripleDESEncryptCBC:(NSData *)data key:(NSData *)key iv:(NSData *)iv;
+ (NSData *)tripleDESDecryptCBC:(NSData *)data key:(NSData *)key iv:(NSData *)iv;
+ (NSData *)desEncryptECB:(NSData *)data key:(NSData *)key;
+ (NSData *)desDecryptECB:(NSData *)data key:(NSData *)key;

+ (NSData *)calculateRetailMAC:(NSData *)data key:(NSData *)key;
+ (BOOL)deriveBACKeysWithSeed:(NSData *)seed kEnc:(NSData **)outEnc kMac:(NSData **)outMac;

+ (NSString *)calculateCheckDigit:(NSString *)input;
+ (NSData *)calculateBACSeedWithDoc:(NSString *)doc birth:(NSString *)birth expiry:(NSString *)expiry;
+ (NSData *)calculateCANSeed:(NSString *)can;

@end
