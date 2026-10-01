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
@property (nonatomic, strong) UIButton *closeButton;
@end

@implementation MRZScannerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    [self setupCamera];
    [self setupUI];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.previewLayer.frame = self.view.bounds;
}

- (void)setupCamera {
    self.captureSession = [[AVCaptureSession alloc] init];
    self.captureSession.sessionPreset = AVCaptureSessionPreset1920x1080;

    AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                                 mediaType:AVMediaTypeVideo
                                                                  position:AVCaptureDevicePositionBack];
    if (!camera) return;

    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error];
    if (input && [self.captureSession canAddInput:input]) {
        [self.captureSession addInput:input];
    }

    self.videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    dispatch_queue_t queue = dispatch_queue_create("camera.mrz.queue", DISPATCH_QUEUE_SERIAL);
    [self.videoOutput setSampleBufferDelegate:self queue:queue];
    if ([self.captureSession canAddOutput:self.videoOutput]) {
        [self.captureSession addOutput:self.videoOutput];
    }

    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer addSublayer:self.previewLayer];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_USER_INITIATED, 0), ^{
        [self.captureSession startRunning];
    });
}

- (void)setupUI {
    self.overlayGuideView = [[UIView alloc] init];
    self.overlayGuideView.translatesAutoresizingMaskIntoConstraints = NO;
    self.overlayGuideView.layer.borderColor = [UIColor systemGreenColor].CGColor;
    self.overlayGuideView.layer.borderWidth = 2.0;
    self.overlayGuideView.layer.cornerRadius = 12.0;
    self.overlayGuideView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.overlayGuideView];

    self.instructionLabel = [[UILabel alloc] init];
    self.instructionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.instructionLabel.text = @"Căn chỉnh 3 dòng mã vạch MRZ ở mặt sau CCCD vào khung hình";
    self.instructionLabel.textColor = [UIColor whiteColor];
    self.instructionLabel.textAlignment = NSTextAlignmentCenter;
    self.instructionLabel.numberOfLines = 2;
    self.instructionLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    self.instructionLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
    self.instructionLabel.layer.cornerRadius = 8.0;
    self.instructionLabel.clipsToBounds = YES;
    [self.view addSubview:self.instructionLabel];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.closeButton setTitle:@"✕ Đóng" forState:UIControlStateNormal];
    [self.closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.closeButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    self.closeButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
    self.closeButton.layer.cornerRadius = 18.0;
    [self.closeButton addTarget:self action:@selector(handleClose) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.closeButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.overlayGuideView.centerXAnchor.constraintEqualToAnchor:self.view.centerXAnchor],
        [self.overlayGuideView.centerYAnchor.constraintEqualToAnchor:self.view.centerYAnchor],
        [self.overlayGuideView.widthAnchor.constraintEqualToAnchor:self.view.widthAnchor multiplier:0.88],
        [self.overlayGuideView.heightAnchor.constraintEqualToConstant:160],

        [self.instructionLabel.topAnchor.constraintEqualToAnchor:self.overlayGuideView.bottomAnchor constant:20],
        [self.instructionLabel.leadingAnchor.constraintEqualToAnchor:self.view.leadingAnchor constant:30],
        [self.instructionLabel.trailingAnchor.constraintEqualToAnchor:self.view.trailingAnchor constant:-30],
        [self.instructionLabel.heightAnchor.constraintGreaterThanOrEqualToConstant:44],

        [self.closeButton.topAnchor.constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [self.closeButton.trailingAnchor.constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.closeButton.widthAnchor.constraintEqualToConstant:80],
        [self.closeButton.heightAnchor.constraintEqualToConstant:36]
    ]];
}

- (void)handleClose {
    [self.captureSession stopRunning];
    [self dismissViewControllerAnimated:YES completion:nil];
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

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
                NSString *clean = [[top.string stringByReplacingOccurrencesOfString:@" " withString:@""] uppercaseString];
                [lines addObject:clean];
            }
        }

        [self parseMRZLines:lines];
    }];

    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = NO;

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer orientation:kCGImagePropertyOrientationRight options:@{}];
    [handler performRequests:@[request] error:nil];
}

- (void)parseMRZLines:(NSArray<NSString *> *)lines {
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];
        if ([line containsString:@"IDVNM"] || [line containsString:@"I<VNM"] || [line hasPrefix:@"ID"] || [line hasPrefix:@"I<"]) {
            if (i + 1 < lines.count) {
                NSString *nextLine = lines[i + 1];
                if (nextLine.length >= 15) {
                    NSString *docNum = [self extractDocNumberFromLine:line];
                    NSString *dob = @"";
                    NSString *doe = @"";
                    [self extractDatesFromLine:nextLine outDOB:&dob outDOE:&doe];

                    if (docNum.length >= 9 && dob.length == 6 && doe.length == 6) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self.captureSession stopRunning];
                            UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
                            [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];

                            if ([self.delegate respondsToSelector:@selector(mrzScannerDidScanDoc:birth:expiry:)]) {
                                [self.delegate mrzScannerDidScanDoc:docNum birth:dob expiry:doe];
                            }
                            [self dismissViewControllerAnimated:YES completion:nil];
                        });
                        return;
                    }
                }
            }
        }
    }
}

- (NSString *)extractDocNumberFromLine:(NSString *)line {
    NSString *clean = [line stringByReplacingOccurrencesOfString:@"<" withString:@""];
    NSRange range = [clean rangeOfString:@"VNM"];
    if (range.location != NSNotFound) {
        clean = [clean substringFromIndex:range.location + range.length];
    }
    NSMutableString *digits = [NSMutableString string];
    for (NSUInteger i = 0; i < clean.length; i++) {
        unichar c = [clean characterAtIndex:i];
        if (c >= '0' && c <= '9') {
            [digits appendFormat:@"%C", c];
        }
    }
    if (digits.length >= 12) {
        return [digits substringToIndex:12];
    }
    return digits;
}

- (void)extractDatesFromLine:(NSString *)line outDOB:(NSString **)outDOB outDOE:(NSString **)outDOE {
    NSMutableString *digits = [NSMutableString string];
    for (NSUInteger i = 0; i < line.length; i++) {
        unichar c = [line characterAtIndex:i];
        if (c >= '0' && c <= '9') {
            [digits appendFormat:@"%C", c];
        }
    }
    if (digits.length >= 13) {
        *outDOB = [digits substringToIndex:6];
        *outDOE = [digits substringWithRange:NSMakeRange(7, 6)];
    }
}

@end
