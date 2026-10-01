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
@property (nonatomic, strong) UIButton *captureManualButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *torchButton;
@property (nonatomic, assign) BOOL isTorchOn;
@property (nonatomic, assign) CVPixelBufferRef latestPixelBuffer;

@end

@implementation MRZScannerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    [self setupUI];
    [self checkCameraPermissionAndSetup];
}

- (void)dealloc {
    if (_latestPixelBuffer) {
        CVPixelBufferRelease(_latestPixelBuffer);
        _latestPixelBuffer = NULL;
    }
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

    // Tự động lấy nét Macro liên tục
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

    // Nút Bấm Chụp Nhận Diện Ngay
    self.captureManualButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.captureManualButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.captureManualButton setTitle:@"📸 Bấm Để Nhận Diện Ngay" forState:UIControlStateNormal];
    [self.captureManualButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.captureManualButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    self.captureManualButton.backgroundColor = [UIColor systemBlueColor];
    self.captureManualButton.layer.cornerRadius = 12.0;
    [self.captureManualButton addTarget:self action:@selector(handleManualCapture) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.captureManualButton];

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
        [self.overlayGuideView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-30],
        [self.overlayGuideView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.90],
        [self.overlayGuideView.heightAnchor constraintEqualToConstant:150],

        [self.instructionLabel.topAnchor constraintEqualToAnchor:self.overlayGuideView.bottomAnchor constant:14],
        [self.instructionLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [self.instructionLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [self.instructionLabel.heightAnchor constraintGreaterThanOrEqualToConstant:38],

        [self.liveDetectLabel.topAnchor constraintEqualToAnchor:self.instructionLabel.bottomAnchor constant:6],
        [self.liveDetectLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [self.liveDetectLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [self.liveDetectLabel.heightAnchor constraintEqualToConstant:24],

        [self.captureManualButton.topAnchor constraintEqualToAnchor:self.liveDetectLabel.bottomAnchor constant:16],
        [self.captureManualButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:30],
        [self.captureManualButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-30],
        [self.captureManualButton.heightAnchor constraintEqualToConstant:46],

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
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer) return;

    @synchronized(self) {
        if (self.latestPixelBuffer) {
            CVPixelBufferRelease(self.latestPixelBuffer);
        }
        self.latestPixelBuffer = CVPixelBufferRetain(pixelBuffer);
    }

    if (self.isProcessing) return;
    self.isProcessing = YES;

    // Luân phiên kiểm tra cả 2 hướng: Right (Landscape buffer của iPhone khi cầm dọc) và Up
    static int frameCounter = 0;
    frameCounter++;
    CGImagePropertyOrientation orientation = (frameCounter % 2 == 0) ? kCGImagePropertyOrientationRight : kCGImagePropertyOrientationUp;

    [self processPixelBuffer:pixelBuffer orientation:orientation isManual:NO];
}

- (void)handleManualCapture {
    CVPixelBufferRef bufferToProcess = NULL;
    @synchronized(self) {
        if (self.latestPixelBuffer) {
            bufferToProcess = CVPixelBufferRetain(self.latestPixelBuffer);
        }
    }

    if (!bufferToProcess) return;

    self.isProcessing = YES;
    self.liveDetectLabel.text = @"Đang phân tích chi tiết...";

    // Thử hướng Right trước
    [self processPixelBuffer:bufferToProcess orientation:kCGImagePropertyOrientationRight isManual:YES];
    CVPixelBufferRelease(bufferToProcess);
}

- (void)processPixelBuffer:(CVPixelBufferRef)pixelBuffer orientation:(CGImagePropertyOrientation)orientation isManual:(BOOL)isManual {
    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest * _Nonnull req, NSError * _Nullable error) {
        self.isProcessing = NO;
        if (error || !req.results) return;

        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        for (VNRecognizedTextObservation *obs in req.results) {
            VNRecognizedText *top = [[obs topCandidates:1] firstObject];
            if (top) {
                NSString *clean = [[top.string stringByReplacingOccurrencesOfString:@" " withString:@""] uppercaseString];
                if (clean.length >= 4) {
                    [lines addObject:clean];
                }
            }
        }

        if (lines.count > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.liveDetectLabel.text = [NSString stringWithFormat:@"Đọc: %@", [lines.firstObject substringToIndex:MIN(24, lines.firstObject.length)]];
            });
        }

        BOOL success = [self parseMRZFromLines:lines];
        if (!success && isManual) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *seen = lines.count > 0 ? [lines componentsJoinedByString:@"\n"] : @"(Không phát hiện văn bản)";
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Chưa nhận diện được mã MRZ"
                                                                               message:[NSString stringWithFormat:@"Camera nhìn thấy:\n%@\n\nHãy căn chỉnh sát 3 dòng chữ ở góc dưới thẻ hoặc nhập CAN.", seen]
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"Đã hiểu" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            });
        }
    }];

    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = NO;
    request.recognitionLanguages = @[@"en-US"];

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer orientation:orientation options:@{}];
    [handler performRequests:@[request] error:nil];
}

// MARK: - Robust MRZ Parser

- (BOOL)parseMRZFromLines:(NSArray<NSString *> *)lines {
    NSString *foundDocNumber = nil;
    NSString *foundDOB = nil;
    NSString *foundDOE = nil;

    // 1. Tìm Số CCCD:
    for (NSString *line in lines) {
        NSRegularExpression *docRegex = [NSRegularExpression regularExpressionWithPattern:@"(\\d{12})" options:0 error:nil];
        NSTextCheckingResult *match = [docRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (match) {
            foundDocNumber = [line substringWithRange:[match rangeAtIndex:1]];
            break;
        }

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
    NSRegularExpression *dateRegex = [NSRegularExpression regularExpressionWithPattern:@"(\\d{6})[0-9A-Z<]{1,3}(\\d{6})" options:0 error:nil];

    for (NSString *line in lines) {
        NSTextCheckingResult *match = [dateRegex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (match) {
            NSString *rawDOB = [line substringWithRange:[match rangeAtIndex:1]];
            NSString *rawDOE = [line substringWithRange:[match rangeAtIndex:2]];

            if ([self isValidYYMMDD:rawDOB] && [self isValidYYMMDD:rawDOE]) {
                foundDOB = rawDOB;
                foundDOE = rawDOE;
                break;
            }
        }

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

    // Nếu đã tìm thấy đầy đủ:
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
        return YES;
    }
    return NO;
}

- (BOOL)isValidYYMMDD:(NSString *)dateStr {
    if (dateStr.length != 6) return NO;
    int mm = [[dateStr substringWithRange:NSMakeRange(2, 2)] intValue];
    int dd = [[dateStr substringWithRange:NSMakeRange(4, 2)] intValue];
    return (mm >= 1 && mm <= 12 && dd >= 1 && dd <= 31);
}

@end
