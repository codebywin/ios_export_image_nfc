#import "MRZScannerViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>

@interface MRZScannerViewController () <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, assign) BOOL isProcessing;

@property (nonatomic, strong) UIView *overlayGuideView;
@property (nonatomic, strong) UILabel *instructionLabel;
@property (nonatomic, strong) UILabel *liveDetectLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *torchButton;
@property (nonatomic, assign) BOOL isTorchOn;

@end

@implementation MRZScannerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    [self setupUI];
    [self checkCameraPermissionAndSetup];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.previewLayer.frame = self.view.bounds;
}

- (void)checkCameraPermissionAndSetup {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusAuthorized) {
        [self setupCamera];
    } else if (status == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (granted) {
                    [self setupCamera];
                } else {
                    [self showPermissionAlert];
                }
            });
        }];
    } else {
        [self showPermissionAlert];
    }
}

- (void)showPermissionAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Chưa cấp quyền Camera"
                                                                   message:@"Vui lòng cho phép quyền Camera trong Cài đặt để quét mặt sau CCCD."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        [self handleClose];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setupCamera {
    self.captureSession = [[AVCaptureSession alloc] init];
    self.captureSession.sessionPreset = AVCaptureSessionPreset1920x1080;

    AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!camera) {
        camera = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                    mediaType:AVMediaTypeVideo
                                                     position:AVCaptureDevicePositionBack];
    }
    if (!camera) return;

    // Bật Auto Focus liên tục
    NSError *lockErr = nil;
    if ([camera lockForConfiguration:&lockErr]) {
        if ([camera isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
            camera.focusMode = AVCaptureFocusModeContinuousAutoFocus;
        }
        [camera unlockForConfiguration];
    }

    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error];
    if (input && [self.captureSession canAddInput:input]) {
        [self.captureSession addInput:input];
    }

    self.videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    self.videoOutput.alwaysDiscardsLateVideoFrames = YES;
    dispatch_queue_t queue = dispatch_queue_create("camera.mrz.queue", DISPATCH_QUEUE_SERIAL);
    [self.videoOutput setSampleBufferDelegate:self queue:queue];
    if ([self.captureSession canAddOutput:self.videoOutput]) {
        [self.captureSession addOutput:self.videoOutput];
    }

    // Thiết lập Orientation chuẩn Portrait
    AVCaptureConnection *conn = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
    if (conn.isVideoOrientationSupported) {
        conn.videoOrientation = AVCaptureVideoOrientationPortrait;
    }

    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer insertSublayer:self.previewLayer atIndex:0];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self.captureSession startRunning];
    });
}

- (void)setupUI {
    self.overlayGuideView = [[UIView alloc] init];
    self.overlayGuideView.translatesAutoresizingMaskIntoConstraints = NO;
    self.overlayGuideView.layer.borderColor = [UIColor systemGreenColor].CGColor;
    self.overlayGuideView.layer.borderWidth = 2.5;
    self.overlayGuideView.layer.cornerRadius = 12.0;
    self.overlayGuideView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.overlayGuideView];

    self.instructionLabel = [[UILabel alloc] init];
    self.instructionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.instructionLabel.text = @"Căn chỉnh 3 dòng mã vạch MRZ ở mặt sau CCCD vào khung hình";
    self.instructionLabel.textColor = [UIColor whiteColor];
    self.instructionLabel.textAlignment = NSTextAlignmentCenter;
    self.instructionLabel.numberOfLines = 2;
    self.instructionLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.instructionLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.65];
    self.instructionLabel.layer.cornerRadius = 8.0;
    self.instructionLabel.clipsToBounds = YES;
    [self.view addSubview:self.instructionLabel];

    self.liveDetectLabel = [[UILabel alloc] init];
    self.liveDetectLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.liveDetectLabel.text = @"Đang quét văn bản...";
    self.liveDetectLabel.textColor = [UIColor systemYellowColor];
    self.liveDetectLabel.textAlignment = NSTextAlignmentCenter;
    self.liveDetectLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    self.liveDetectLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    self.liveDetectLabel.layer.cornerRadius = 6.0;
    self.liveDetectLabel.clipsToBounds = YES;
    [self.view addSubview:self.liveDetectLabel];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.closeButton setTitle:@"✕ Đóng" forState:UIControlStateNormal];
    [self.closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.closeButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    self.closeButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.65];
    self.closeButton.layer.cornerRadius = 18.0;
    [self.closeButton addTarget:self action:@selector(handleClose) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.closeButton];

    self.torchButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.torchButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.torchButton setTitle:@"💡 Bật Đèn" forState:UIControlStateNormal];
    [self.torchButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.torchButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.torchButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.65];
    self.torchButton.layer.cornerRadius = 18.0;
    [self.torchButton addTarget:self action:@selector(toggleTorch) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.torchButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.overlayGuideView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.overlayGuideView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.overlayGuideView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.90],
        [self.overlayGuideView.heightAnchor constraintEqualToConstant:150],

        [self.instructionLabel.topAnchor constraintEqualToAnchor:self.overlayGuideView.bottomAnchor constant:16],
        [self.instructionLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [self.instructionLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [self.instructionLabel.heightAnchor constraintGreaterThanOrEqualToConstant:40],

        [self.liveDetectLabel.topAnchor constraintEqualToAnchor:self.instructionLabel.bottomAnchor constant:8],
        [self.liveDetectLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [self.liveDetectLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [self.liveDetectLabel.heightAnchor constraintEqualToConstant:26],

        [self.closeButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [self.closeButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.closeButton.widthAnchor constraintEqualToConstant:76],
        [self.closeButton.heightAnchor constraintEqualToConstant:36],

        [self.torchButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [self.torchButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.torchButton.widthAnchor constraintEqualToConstant:90],
        [self.torchButton.heightAnchor constraintEqualToConstant:36]
    ]];
}

- (void)toggleTorch {
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if ([device hasTorch]) {
        [device lockForConfiguration:nil];
        if (self.isTorchOn) {
            [device setTorchMode:AVCaptureTorchModeOff];
            self.isTorchOn = NO;
            [self.torchButton setTitle:@"💡 Bật Đèn" forState:UIControlStateNormal];
        } else {
            [device setTorchMode:AVCaptureTorchModeOn];
            self.isTorchOn = YES;
            [self.torchButton setTitle:@"🔦 Tắt Đèn" forState:UIControlStateNormal];
        }
        [device unlockForConfiguration];
    }
}

- (void)handleClose {
    [self.captureSession stopRunning];
    [self dismissViewControllerAnimated:YES completion:nil];
}

// MARK: - Sample Buffer Delegate

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (self.isProcessing) return;
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer) return;

    self.isProcessing = YES;

    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest * _Nonnull req, NSError * _Nullable error) {
        self.isProcessing = NO;
        if (error || !req.results) return;

        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        for (VNRecognizedTextObservation *obs in req.results) {
            VNRecognizedText *top = [[obs topCandidates:1] firstObject];
            if (top) {
                // Làm sạch chuỗi: bỏ khoảng trắng, chuyển chữ hoa, đổi dấu < thành chữ
                NSString *clean = [[top.string stringByReplacingOccurrencesOfString:@" " withString:@""] uppercaseString];
                if (clean.length > 5) {
                    [lines addObject:clean];
                }
            }
        }

        if (lines.count > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.liveDetectLabel.text = [NSString stringWithFormat:@"Nhận diện: %@", [lines.firstObject substringToIndex:MIN(25, lines.firstObject.length)]];
            });
        }

        [self parseMRZFromLines:lines];
    }];

    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = NO;

    // Pixel buffer đã được định hướng Portrait từ connection nên dùng Up
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer orientation:kCGImagePropertyOrientationUp options:@{}];
    [handler performRequests:@[request] error:nil];
}

// MARK: - Robust MRZ Parser

- (void)parseMRZFromLines:(NSArray<NSString *> *)lines {
    NSString *foundDocNumber = nil;
    NSString *foundDOB = nil;
    NSString *foundDOE = nil;

    // 1. Tìm Số CCCD:
    // Dòng 1 thường có dạng: IDVNM0012000000002<<<<<<<<<<<< hoặc chứa 12 số CCCD
    for (NSString *line in lines) {
        // Tìm 12 chữ số liên tiếp
        NSRegularExpression *docRegex = [NSRegularExpression regularExpressionWithPattern:@"(\\d{12})" options:0 error:nil];
        NSTextCheckingResult *match = [docRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (match) {
            foundDocNumber = [line substringWithRange:[match rangeAtIndex:1]];
            break;
        }

        // Nếu bắt đầu bằng VNM hoặc ID và có ít nhất 9 số
        if ([line containsString:@"VNM"] || [line containsString:@"ID"] || [line containsString:@"I<"]) {
            NSMutableString *digits = [NSMutableString string];
            for (NSUInteger i = 0; i < line.length; i++) {
                unichar c = [line characterAtIndex:i];
                if (c >= '0' && c <= '9') [digits appendFormat:@"%C", c];
            }
            if (digits.length >= 12) {
                foundDocNumber = [digits substringToIndex:12];
                break;
            } else if (digits.length >= 9 && !foundDocNumber) {
                foundDocNumber = digits;
            }
        }
    }

    // 2. Tìm Ngày sinh & Ngày hết hạn từ Dòng 2:
    // Dạng chuẩn ICAO TD1: [DOB: 6 số][Check: 1][Giới tính: M/F/<][DOE: 6 số][Check: 1]...
    // Ví dụ: 9805125M3805126VNM...
    NSRegularExpression *dateRegex = [NSRegularExpression regularExpressionWithPattern:@"(\\d{6})[0-9A-Z<]{1,3}(\\d{6})" options:0 error:nil];

    for (NSString *line in lines) {
        NSTextCheckingResult *match = [dateRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (match) {
            NSString *rawDOB = [line substringWithRange:[match rangeAtIndex:1]];
            NSString *rawDOE = [line substringWithRange:[match rangeAtIndex:2]];

            // Kiểm tra tính hợp lệ sơ bộ của ngày tháng (tháng 01-12, ngày 01-31)
            if ([self isValidYYMMDD:rawDOB] && [self isValidYYMMDD:rawDOE]) {
                foundDOB = rawDOB;
                foundDOE = rawDOE;
                break;
            }
        }

        // Cách 2: Trích xuất toàn bộ số từ dòng chứa chữ M/F và kiểm tra
        if ([line containsString:@"M"] || [line containsString:@"F"] || [line containsString:@"VNM"]) {
            NSMutableString *digits = [NSMutableString string];
            for (NSUInteger i = 0; i < line.length; i++) {
                unichar c = [line characterAtIndex:i];
                if (c >= '0' && c <= '9') [digits appendFormat:@"%C", c];
            }
            if (digits.length >= 13) {
                NSString *cDOB = [digits substringToIndex:6];
                NSString *cDOE = [digits substringWithRange:NSMakeRange(7, 6)];
                if ([self isValidYYMMDD:cDOB] && [self isValidYYMMDD:cDOE]) {
                    foundDOB = cDOB;
                    foundDOE = cDOE;
                    break;
                }
            }
        }
    }

    // Nếu đã tìm thấy đầy đủ 3 trường hợp lệ:
    if (foundDocNumber.length >= 9 && foundDOB.length == 6 && foundDOE.length == 6) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.captureSession stopRunning];
            UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
            [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];

            if ([self.delegate respondsToSelector:@selector(mrzScannerDidScanDoc:birth:expiry:)]) {
                [self.delegate mrzScannerDidScanDoc:foundDocNumber birth:foundDOB expiry:foundDOE];
            }
            [self dismissViewControllerAnimated:YES completion:nil];
        });
    }
}

- (BOOL)isValidYYMMDD:(NSString *)dateStr {
    if (dateStr.length != 6) return NO;
    int mm = [[dateStr substringWithRange:NSMakeRange(2, 2)] intValue];
    int dd = [[dateStr substringWithRange:NSMakeRange(4, 2)] intValue];
    return (mm >= 1 && mm <= 12 && dd >= 1 && dd <= 31);
}

@end
