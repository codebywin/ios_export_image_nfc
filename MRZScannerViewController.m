#import "MRZScannerViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>

// Ghi log vào cùng file với CCCDReaderManager để debug qua SSH
static void MRZLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"[MRZ] %@", msg);

    NSString *line = [NSString stringWithFormat:@"[%@] [MRZ] %@\n", [NSDate date], msg];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSString *path = @"/var/mobile/Library/Caches/cccd_debug.log";

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:data attributes:nil];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:data];
        [fh closeFile];
    }
}

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
    MRZLog(@"MRZScannerViewController viewDidLoad");
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
    MRZLog(@"Camera authorization status = %d", (int)status);
    if (status == AVAuthorizationStatusAuthorized) {
        [self setupCamera];
    } else if (status == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            MRZLog(@"Camera permission request result: %@", granted ? @"GRANTED" : @"DENIED");
            dispatch_async(dispatch_get_main_queue(), ^{
                if (granted) {
                    [self setupCamera];
                } else {
                    [self showPermissionAlert];
                }
            });
        }];
    } else {
        MRZLog(@"Camera permission DENIED/RESTRICTED - showing alert");
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
    MRZLog(@"setupCamera starting...");
    self.captureSession = [[AVCaptureSession alloc] init];
    self.captureSession.sessionPreset = AVCaptureSessionPreset1920x1080;

    AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                                mediaType:AVMediaTypeVideo
                                                                 position:AVCaptureDevicePositionBack];
    if (!camera) {
        camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        MRZLog(@"Wide angle back camera not found, using default: %@", camera.localizedName);
    }
    if (!camera) {
        MRZLog(@"ERROR: No camera device available at all");
        return;
    }
    MRZLog(@"Using camera: %@ (position=%ld)", camera.localizedName, (long)camera.position);

    // Macro autofocus & zoom 1.6x để camera lấy nét nét nhất khi chụp CCCD
    NSError *lockErr = nil;
    if ([camera lockForConfiguration:&lockErr]) {
        if ([camera isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
            camera.focusMode = AVCaptureFocusModeContinuousAutoFocus;
        }
        if ([camera isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
            camera.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
        }
        if ([camera isAutoFocusRangeRestrictionSupported]) {
            camera.autoFocusRangeRestriction = AVCaptureAutoFocusRangeRestrictionNear;
        }
        if (camera.activeFormat.videoMaxZoomFactor >= 1.6) {
            camera.videoZoomFactor = 1.6;
        }
        [camera unlockForConfiguration];
        MRZLog(@"Camera config applied, zoom=%.2f", camera.videoZoomFactor);
    } else {
        MRZLog(@"WARNING: lockForConfiguration failed: %@", lockErr.localizedDescription);
    }

    NSError *inputError = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&inputError];
    if (!input) {
        MRZLog(@"ERROR: Cannot create device input: %@", inputError.localizedDescription);
        return;
    }
    if ([self.captureSession canAddInput:input]) {
        [self.captureSession addInput:input];
        MRZLog(@"Camera input added to session");
    } else {
        MRZLog(@"ERROR: Cannot add input to session");
        return;
    }

    self.videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    self.videoOutput.alwaysDiscardsLateVideoFrames = YES;
    dispatch_queue_t queue = dispatch_queue_create("camera.mrz.queue", DISPATCH_QUEUE_SERIAL);
    [self.videoOutput setSampleBufferDelegate:self queue:queue];
    if ([self.captureSession canAddOutput:self.videoOutput]) {
        [self.captureSession addOutput:self.videoOutput];
        MRZLog(@"Video output added to session");
    } else {
        MRZLog(@"ERROR: Cannot add video output to session");
        return;
    }

    // Thiết lập chiều xoay Portrait chuẩn xác cho cả luồng video và preview
    AVCaptureConnection *videoConnection = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
    if (videoConnection.isVideoOrientationSupported) {
        videoConnection.videoOrientation = AVCaptureVideoOrientationPortrait;
    }

    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    if (self.previewLayer.connection.isVideoOrientationSupported) {
        self.previewLayer.connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    }
    [self.view.layer insertSublayer:self.previewLayer atIndex:0];
    MRZLog(@"Preview layer added to view");

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self.captureSession startRunning];
        MRZLog(@"Capture session started running");
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
    self.instructionLabel.text = @"Căn chỉnh 3 dòng chữ MRZ ở góc dưới mặt sau CCCD vào khung hình";
    self.instructionLabel.textColor = [UIColor whiteColor];
    self.instructionLabel.textAlignment = NSTextAlignmentCenter;
    self.instructionLabel.numberOfLines = 2;
    self.instructionLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    self.instructionLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.65];
    self.instructionLabel.layer.cornerRadius = 8.0;
    self.instructionLabel.clipsToBounds = YES;
    [self.view addSubview:self.instructionLabel];

    self.liveDetectLabel = [[UILabel alloc] init];
    self.liveDetectLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.liveDetectLabel.text = @"CCCD: ... | NS: ... | HSD: ...";
    self.liveDetectLabel.textColor = [UIColor systemYellowColor];
    self.liveDetectLabel.textAlignment = NSTextAlignmentCenter;
    self.liveDetectLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    self.liveDetectLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.65];
    self.liveDetectLabel.layer.cornerRadius = 8.0;
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
        [self.overlayGuideView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-40],
        [self.overlayGuideView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.92],
        [self.overlayGuideView.heightAnchor constraintEqualToConstant:140],

        [self.instructionLabel.topAnchor constraintEqualToAnchor:self.overlayGuideView.bottomAnchor constant:12],
        [self.instructionLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.instructionLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.instructionLabel.heightAnchor constraintGreaterThanOrEqualToConstant:36],

        [self.liveDetectLabel.topAnchor constraintEqualToAnchor:self.instructionLabel.bottomAnchor constant:8],
        [self.liveDetectLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.liveDetectLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.liveDetectLabel.heightAnchor constraintEqualToConstant:32],

        [self.captureManualButton.topAnchor constraintEqualToAnchor:self.liveDetectLabel.bottomAnchor constant:16],
        [self.captureManualButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [self.captureManualButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
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
    MRZLog(@"Frame received: %ld x %ld px", CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer));

    [self processPixelBuffer:pixelBuffer isManual:NO];
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
    self.liveDetectLabel.text = @"Đang phân tích hình ảnh...";

    [self processPixelBuffer:bufferToProcess isManual:YES];
    CVPixelBufferRelease(bufferToProcess);
}

- (void)processPixelBuffer:(CVPixelBufferRef)pixelBuffer isManual:(BOOL)isManual {
    static NSUInteger frameCounter = 0;
    frameCounter++;

    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest * _Nonnull req, NSError * _Nullable error) {
        self.isProcessing = NO;
        if (error || !req.results || req.results.count == 0) {
            if (frameCounter % 30 == 0) {
                MRZLog(@"OCR frame #%lu: no text detected (error=%@, results=%lu)",
                       (unsigned long)frameCounter, error.localizedDescription, (unsigned long)(req.results ? req.results.count : 0));
            }
            if (isManual) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showManualResultAlertWithDoc:nil birth:nil expiry:nil lines:@[]];
                });
            }
            return;
        }

        NSArray<VNRecognizedTextObservation *> *observations = (NSArray<VNRecognizedTextObservation *> *)req.results;
        NSArray<NSString *> *lines = [self clusterObservationsIntoLines:observations];

        if (frameCounter % 30 == 0) {
            MRZLog(@"OCR frame #%lu: %lu observations -> %lu lines: %@",
                   (unsigned long)frameCounter, (unsigned long)observations.count, (unsigned long)lines.count, lines);
        }

        [self handleParsedLines:lines isManual:isManual];
    }];

    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = NO;
    request.recognitionLanguages = @[@"en-US"];

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer orientation:kCGImagePropertyOrientationUp options:@{}];
    NSError *performError = nil;
    [handler performRequests:@[request] error:&performError];
    if (performError) {
        MRZLog(@"performRequests ERROR: %@", performError.localizedDescription);
    }
}

// MARK: - Gom cụm các đoạn văn bản cùng hàng ngang (Y-clustering)
- (NSArray<NSString *> *)clusterObservationsIntoLines:(NSArray<VNRecognizedTextObservation *> *)observations {
    // Sắp xếp các đoạn văn bản từ trên xuống dưới theo trục Y
    NSArray *sortedByY = [observations sortedArrayUsingComparator:^NSComparisonResult(VNRecognizedTextObservation *a, VNRecognizedTextObservation *b) {
        CGFloat yA = a.boundingBox.origin.y + a.boundingBox.size.height / 2.0;
        CGFloat yB = b.boundingBox.origin.y + b.boundingBox.size.height / 2.0;
        if (yA < yB) return NSOrderedDescending;
        if (yA > yB) return NSOrderedAscending;
        return NSOrderedSame;
    }];

    NSMutableArray<NSMutableArray<VNRecognizedTextObservation *> *> *lineClusters = [NSMutableArray array];
    for (VNRecognizedTextObservation *obs in sortedByY) {
        CGFloat midY = obs.boundingBox.origin.y + obs.boundingBox.size.height / 2.0;
        BOOL added = NO;
        for (NSMutableArray<VNRecognizedTextObservation *> *cluster in lineClusters) {
            VNRecognizedTextObservation *first = cluster.firstObject;
            CGFloat clusterMidY = first.boundingBox.origin.y + first.boundingBox.size.height / 2.0;
            if (fabs(midY - clusterMidY) < 0.025) { // Ngưỡng cùng một dòng
                [cluster addObject:obs];
                added = YES;
                break;
            }
        }
        if (!added) {
            [lineClusters addObject:[NSMutableArray arrayWithObject:obs]];
        }
    }

    NSMutableArray<NSString *> *resultLines = [NSMutableArray array];
    for (NSMutableArray<VNRecognizedTextObservation *> *cluster in lineClusters) {
        // Sắp xếp các từ trong cùng một hàng từ trái sang phải theo trục X
        [cluster sortUsingComparator:^NSComparisonResult(VNRecognizedTextObservation *a, VNRecognizedTextObservation *b) {
            CGFloat xA = a.boundingBox.origin.x;
            CGFloat xB = b.boundingBox.origin.x;
            if (xA < xB) return NSOrderedAscending;
            if (xA > xB) return NSOrderedDescending;
            return NSOrderedSame;
        }];

        NSMutableString *lineStr = [NSMutableString string];
        for (VNRecognizedTextObservation *obs in cluster) {
            VNRecognizedText *top = [[obs topCandidates:1] firstObject];
            if (top) {
                NSString *clean = [[top.string stringByReplacingOccurrencesOfString:@" " withString:@""] uppercaseString];
                [lineStr appendString:clean];
            }
        }
        if (lineStr.length >= 4) {
            [resultLines addObject:lineStr];
        }
    }
    return resultLines;
}

// MARK: - Xử lý chuẩn hoá ký tự số bị OCR nhầm lẫn
- (NSString *)cleanDigits:(NSString *)input {
    NSMutableString *s = [input mutableCopy];
    [s replaceOccurrencesOfString:@"O" withString:@"0" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"o" withString:@"0" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"D" withString:@"0" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Q" withString:@"0" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"I" withString:@"1" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"l" withString:@"1" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"L" withString:@"1" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"S" withString:@"5" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"s" withString:@"5" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"B" withString:@"8" options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"Z" withString:@"2" options:0 range:NSMakeRange(0, s.length)];
    return s;
}

- (BOOL)isValidYYMMDD:(NSString *)dateStr {
    if (dateStr.length != 6) return NO;
    int mm = [[dateStr substringWithRange:NSMakeRange(2, 2)] intValue];
    int dd = [[dateStr substringWithRange:NSMakeRange(4, 2)] intValue];
    return (mm >= 1 && mm <= 12 && dd >= 1 && dd <= 31);
}

// MARK: - Trích xuất Số CCCD 12 số
- (NSString *)extractDocNumberFromLines:(NSArray<NSString *> *)lines {
    for (NSString *line in lines) {
        NSString *clean = [line stringByReplacingOccurrencesOfString:@" " withString:@""].uppercaseString;

        // Pattern 1: Dòng TD1 chuẩn với 9 số đầu + 1 check digit (hoặc <) + 3 số cuối (tổng 12 số CCCD)
        // Ví dụ: IDVNM0792010018234<<<<<<<<<<<< hoặc IDVNM079201001<8234
        if ([clean containsString:@"VNM"] || [clean containsString:@"ID"] || [clean containsString:@"I<"]) {
            NSRegularExpression *td1Regex = [NSRegularExpression regularExpressionWithPattern:@"(\\d{9})[0-9A-Z<]{1,2}(\\d{3})" options:0 error:nil];
            NSTextCheckingResult *match = [td1Regex firstMatchInString:clean options:0 range:NSMakeRange(0, clean.length)];
            if (match) {
                NSString *part1 = [clean substringWithRange:[match rangeAtIndex:1]];
                NSString *part2 = [clean substringWithRange:[match rangeAtIndex:2]];
                return [part1 stringByAppendingString:part2];
            }

            // Pattern 2: Dòng chứa 12 số liên tiếp
            NSRegularExpression *m12Regex = [NSRegularExpression regularExpressionWithPattern:@"(\\d{12})" options:0 error:nil];
            NSTextCheckingResult *m12 = [m12Regex firstMatchInString:clean options:0 range:NSMakeRange(0, clean.length)];
            if (m12) {
                return [clean substringWithRange:[m12 rangeAtIndex:1]];
            }

            // Pattern 3: Sau tiền tố VNM/ID, trích xuất tất cả chữ số
            for (NSString *prefix in @[@"IDVNM", @"I<VNM", @"VNM", @"ID"]) {
                NSRange r = [clean rangeOfString:prefix];
                if (r.location != NSNotFound) {
                    NSString *after = [clean substringFromIndex:r.location + r.length];
                    NSMutableString *digits = [NSMutableString string];
                    for (NSUInteger i = 0; i < MIN(after.length, 18); i++) {
                        unichar c = [after characterAtIndex:i];
                        if (c >= '0' && c <= '9') [digits appendFormat:@"%C", c];
                    }
                    if (digits.length >= 13) {
                        return [NSString stringWithFormat:@"%@%@", [digits substringToIndex:9], [digits substringWithRange:NSMakeRange(10, 3)]];
                    } else if (digits.length >= 12) {
                        return [digits substringToIndex:12];
                    } else if (digits.length >= 9) {
                        return digits;
                    }
                }
            }
        }
    }

    // Quét tìm bất kỳ chuỗi 12 số nào trên toàn bộ văn bản
    for (NSString *line in lines) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(\\d{12})" options:0 error:nil];
        NSTextCheckingResult *match = [regex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (match) {
            return [line substringWithRange:[match rangeAtIndex:1]];
        }
    }
    return nil;
}

// MARK: - Trích xuất Ngày sinh & Ngày hết hạn từ Dòng 2
- (void)extractDatesFromLines:(NSArray<NSString *> *)lines outDOB:(NSString **)outDOB outDOE:(NSString **)outDOE {
    *outDOB = nil;
    *outDOE = nil;

    for (NSString *line in lines) {
        NSString *clean = [line stringByReplacingOccurrencesOfString:@" " withString:@""].uppercaseString;

        // Định dạng Dòng 2 ICAO TD1: [DOB: 6 số][1 số kiểm tra][Giới tính M/F/<][DOE: 6 số]
        // Ví dụ: 0105204M4105205VNM<<<<<<<<<<<8 hoặc 9805124M3805125
        NSRegularExpression *dateRegex = [NSRegularExpression regularExpressionWithPattern:@"([0-9OISBZ]{6})[0-9OISBZ<][MF<0-9A-Z]([0-9OISBZ]{6})" options:0 error:nil];
        NSTextCheckingResult *match = [dateRegex firstMatchInString:clean options:0 range:NSMakeRange(0, clean.length)];
        if (!match) {
            dateRegex = [NSRegularExpression regularExpressionWithPattern:@"([0-9OISBZ]{6})[0-9A-Z<]{1,3}?([0-9OISBZ]{6})" options:0 error:nil];
            match = [dateRegex firstMatchInString:clean options:0 range:NSMakeRange(0, clean.length)];
        }

        if (match) {
            NSString *raw1 = [clean substringWithRange:[match rangeAtIndex:1]];
            NSString *raw2 = [clean substringWithRange:[match rangeAtIndex:2]];
            NSString *d1 = [self cleanDigits:raw1];
            NSString *d2 = [self cleanDigits:raw2];

            if ([self isValidYYMMDD:d1] && [self isValidYYMMDD:d2]) {
                *outDOB = d1;
                *outDOE = d2;
                return;
            }
        }
    }

    // Quét tìm các chuỗi 6 ký tự ngày hợp lệ nếu dòng bị cắt rời
    NSMutableArray<NSString *> *validDates = [NSMutableArray array];
    for (NSString *line in lines) {
        NSString *clean = [line stringByReplacingOccurrencesOfString:@" " withString:@""].uppercaseString;
        NSRegularExpression *sixRegex = [NSRegularExpression regularExpressionWithPattern:@"([0-9OISBZ]{6})" options:0 error:nil];
        NSArray<NSTextCheckingResult *> *matches = [sixRegex matchesInString:clean options:0 range:NSMakeRange(0, clean.length)];
        for (NSTextCheckingResult *m in matches) {
            NSString *d = [self cleanDigits:[clean substringWithRange:[m rangeAtIndex:1]]];
            if ([self isValidYYMMDD:d] && ![validDates containsObject:d]) {
                [validDates addObject:d];
            }
        }
    }

    if (validDates.count >= 2) {
        *outDOB = validDates[0];
        *outDOE = validDates[1];
    }
}

// MARK: - Tổng hợp kết quả nhận diện
- (void)handleParsedLines:(NSArray<NSString *> *)lines isManual:(BOOL)isManual {
    NSString *foundDoc = [self extractDocNumberFromLines:lines];
    NSString *foundDOB = nil;
    NSString *foundDOE = nil;
    [self extractDatesFromLines:lines outDOB:&foundDOB outDOE:&foundDOE];

    // Cập nhật trạng thái trực quan lên màn hình theo thời gian thực
    dispatch_async(dispatch_get_main_queue(), ^{
        self.liveDetectLabel.text = [NSString stringWithFormat:@"CCCD: %@ | NS: %@ | HSD: %@",
            foundDoc ? [NSString stringWithFormat:@"✓%@", [foundDoc substringToIndex:MIN(6, foundDoc.length)]] : @"...",
            foundDOB ? [NSString stringWithFormat:@"✓%@", foundDOB] : @"...",
            foundDOE ? [NSString stringWithFormat:@"✓%@", foundDOE] : @"..."];
    });

    if (foundDoc.length >= 9 && foundDOB.length == 6 && foundDOE.length == 6) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.captureSession stopRunning];
            UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
            [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];

            if ([self.delegate respondsToSelector:@selector(mrzScannerDidScanDoc:birth:expiry:)]) {
                [self.delegate mrzScannerDidScanDoc:foundDoc birth:foundDOB expiry:foundDOE];
            }
            [self dismissViewControllerAnimated:YES completion:nil];
        });
        return;
    }

    if (isManual) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showManualResultAlertWithDoc:foundDoc birth:foundDOB expiry:foundDOE lines:lines];
        });
    }
}

// MARK: - Hộp thoại kết quả khi bấm Chụp Thủ Công
- (void)showManualResultAlertWithDoc:(NSString *)doc birth:(NSString *)birth expiry:(NSString *)expiry lines:(NSArray<NSString *> *)lines {
    BOOL hasAny = (doc.length > 0 || birth.length > 0 || expiry.length > 0);
    NSString *title = hasAny ? @"Nhận diện được một phần thông tin" : @"Chưa nhận diện được mã MRZ";

    NSMutableString *msg = [NSMutableString string];
    [msg appendFormat:@"• Số CCCD: %@\n", doc ? doc : @"(Chưa rõ)"];
    [msg appendFormat:@"• Ngày sinh: %@\n", birth ? birth : @"(Chưa rõ)"];
    [msg appendFormat:@"• Ngày hết hạn: %@\n\n", expiry ? expiry : @"(Chưa rõ)"];

    if (lines.count > 0) {
        [msg appendFormat:@"Văn bản camera thấy:\n%@\n\n", [lines componentsJoinedByString:@"\n"]];
    }

    if (hasAny) {
        [msg appendString:@"Bạn có muốn tự động điền các thông tin này vào mục 'Nhập Tay' để hoàn thành nhanh không?"];
    } else {
        [msg appendString:@"Mẹo: Hãy giữ thẻ cách camera 15-20cm, tránh bị bóng phản chiếu hoặc bật đèn flash để camera lấy nét rõ."];
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];

    if (hasAny) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Điền vào Nhập Tay" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self.captureSession stopRunning];
            if ([self.delegate respondsToSelector:@selector(mrzScannerDidRequestManualFillWithDoc:birth:expiry:)]) {
                [self.delegate mrzScannerDidRequestManualFillWithDoc:doc birth:birth expiry:expiry];
            } else if ([self.delegate respondsToSelector:@selector(mrzScannerDidScanDoc:birth:expiry:)]) {
                [self.delegate mrzScannerDidScanDoc:doc ? doc : @"" birth:birth ? birth : @"" expiry:expiry ? expiry : @""];
            }
            [self dismissViewControllerAnimated:YES completion:nil];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Thử Lại" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

