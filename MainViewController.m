#import "MainViewController.h"
#import "CCCDReaderManager.h"
#import "MRZScannerViewController.h"
#import "CryptoUtils.h"
#import "DG2Parser.h"
#import <Photos/Photos.h>

@interface MainViewController () <CCCDReaderManagerDelegate, MRZScannerDelegate, UITextFieldDelegate>

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;

@property (nonatomic, strong) UIView *photoCardView;
@property (nonatomic, strong) UIImageView *portraitImageView;
@property (nonatomic, strong) UILabel *photoPlaceholderLabel;

@property (nonatomic, strong) UISegmentedControl *segmentAuth;

// 1. Camera
@property (nonatomic, strong) UIView *cameraContainer;
@property (nonatomic, strong) UIButton *scanCameraButton;
@property (nonatomic, strong) UILabel *scannedInfoLabel;

// 2. CAN
@property (nonatomic, strong) UIView *canContainer;
@property (nonatomic, strong) UITextField *canTextField;

// 3. Manual MRZ
@property (nonatomic, strong) UIView *mrzContainer;
@property (nonatomic, strong) UITextField *docNumberTextField;
@property (nonatomic, strong) UITextField *dobTextField;
@property (nonatomic, strong) UITextField *doeTextField;

// NFC Scan
@property (nonatomic, strong) UIButton *scanNFCButton;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UILabel *statusLabel;

// Export buttons
@property (nonatomic, strong) UIStackView *exportContainer;
@property (nonatomic, strong) UIButton *saveToPhotosButton;
@property (nonatomic, strong) UIButton *shareJPGButton;

// State
@property (nonatomic, copy) NSString *scannedDocNumber;
@property (nonatomic, copy) NSString *scannedDOB;
@property (nonatomic, copy) NSString *scannedDOE;
@property (nonatomic, strong) UIImage *extractedImage;

@property (nonatomic, strong) CCCDReaderManager *cccdReader;

@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.title = @"CCCD NFC Export";

    self.scannedDocNumber = @"";
    self.scannedDOB = @"";
    self.scannedDOE = @"";

    [self setupUI];
    [self setupActions];
    [self updateAuthMode];

    // Chạm bất kỳ đâu ra ngoài để ẩn bàn phím
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];

    // Lắng nghe sự kiện bàn phím để cuộn UIScrollView
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)keyboardWillShow:(NSNotification *)notification {
    NSDictionary *info = [notification userInfo];
    CGSize kbSize = [[info objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size;
    UIEdgeInsets insets = UIEdgeInsetsMake(0.0, 0.0, kbSize.height + 20.0, 0.0);
    self.scrollView.contentInset = insets;
    self.scrollView.scrollIndicatorInsets = insets;
}

- (void)keyboardWillHide:(NSNotification *)notification {
    self.scrollView.contentInset = UIEdgeInsetsZero;
    self.scrollView.scrollIndicatorInsets = UIEdgeInsetsZero;
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)addDoneButtonToTextField:(UITextField *)textField {
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 44)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithTitle:@"✕ Xong (Ẩn bàn phím)" style:UIBarButtonItemStyleDone target:self action:@selector(dismissKeyboard)];
    toolbar.items = @[flex, done];
    textField.inputAccessoryView = toolbar;
    textField.delegate = self;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)setupUI {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] init];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    // Title & Subtitle
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.text = @"Quét Thẻ CCCD & Xuất Ảnh JPG";
    self.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    self.titleLabel.textColor = [UIColor labelColor];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.text = @"Dành cho Jailbreak Dopamine & RootHide";
    self.subtitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    self.subtitleLabel.textColor = [UIColor secondaryLabelColor];
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:self.subtitleLabel];

    // Card Ảnh chân dung
    self.photoCardView = [[UIView alloc] init];
    self.photoCardView.translatesAutoresizingMaskIntoConstraints = NO;
    self.photoCardView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.photoCardView.layer.cornerRadius = 16.0;
    self.photoCardView.layer.borderWidth = 1.0;
    self.photoCardView.layer.borderColor = [UIColor separatorColor].CGColor;
    self.photoCardView.clipsToBounds = YES;
    [self.contentView addSubview:self.photoCardView];

    self.portraitImageView = [[UIImageView alloc] init];
    self.portraitImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.portraitImageView.contentMode = UIViewContentModeScaleAspectFit;
    [self.photoCardView addSubview:self.portraitImageView];

    self.photoPlaceholderLabel = [[UILabel alloc] init];
    self.photoPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.photoPlaceholderLabel.text = @"Ảnh chân dung CCCD\nsẽ hiển thị tại đây";
    self.photoPlaceholderLabel.numberOfLines = 2;
    self.photoPlaceholderLabel.textAlignment = NSTextAlignmentCenter;
    self.photoPlaceholderLabel.textColor = [UIColor tertiaryLabelColor];
    self.photoPlaceholderLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [self.photoCardView addSubview:self.photoPlaceholderLabel];

    // Segment
    self.segmentAuth = [[UISegmentedControl alloc] initWithItems:@[@"Camera Mặt Sau", @"Mã CAN (6 số)", @"Nhập Tay MRZ"]];
    self.segmentAuth.translatesAutoresizingMaskIntoConstraints = NO;
    self.segmentAuth.selectedSegmentIndex = 0;
    [self.contentView addSubview:self.segmentAuth];

    // 1. Camera View
    self.cameraContainer = [[UIView alloc] init];
    self.cameraContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.cameraContainer];

    self.scanCameraButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.scanCameraButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scanCameraButton setTitle:@"📸 Mở Camera Quét Mặt Sau Thẻ" forState:UIControlStateNormal];
    self.scanCameraButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.scanCameraButton.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.12];
    self.scanCameraButton.layer.cornerRadius = 10.0;
    [self.cameraContainer addSubview:self.scanCameraButton];

    self.scannedInfoLabel = [[UILabel alloc] init];
    self.scannedInfoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.scannedInfoLabel.text = @"Chưa quét mặt sau thẻ";
    self.scannedInfoLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    self.scannedInfoLabel.textColor = [UIColor secondaryLabelColor];
    self.scannedInfoLabel.textAlignment = NSTextAlignmentCenter;
    self.scannedInfoLabel.numberOfLines = 2;
    [self.cameraContainer addSubview:self.scannedInfoLabel];

    // 2. CAN View
    self.canContainer = [[UIView alloc] init];
    self.canContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.canContainer];

    self.canTextField = [[UITextField alloc] init];
    self.canTextField.translatesAutoresizingMaskIntoConstraints = NO;
    self.canTextField.placeholder = @"Nhập 6 số CAN ở góc dưới mặt trước CCCD";
    self.canTextField.borderStyle = UITextBorderStyleRoundedRect;
    self.canTextField.keyboardType = UIKeyboardTypeNumberPad;
    self.canTextField.textAlignment = NSTextAlignmentCenter;
    self.canTextField.font = [UIFont systemFontOfSize:15];
    [self addDoneButtonToTextField:self.canTextField];
    [self.canContainer addSubview:self.canTextField];

    // 3. Manual MRZ View
    self.mrzContainer = [[UIView alloc] init];
    self.mrzContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.mrzContainer];

    self.docNumberTextField = [[UITextField alloc] init];
    self.docNumberTextField.placeholder = @"Số CCCD (12 số)";
    self.docNumberTextField.borderStyle = UITextBorderStyleRoundedRect;
    self.docNumberTextField.keyboardType = UIKeyboardTypeNumberPad;
    [self addDoneButtonToTextField:self.docNumberTextField];

    self.dobTextField = [[UITextField alloc] init];
    self.dobTextField.placeholder = @"Ngày sinh (YYMMDD ví dụ: 980512)";
    self.dobTextField.borderStyle = UITextBorderStyleRoundedRect;
    self.dobTextField.keyboardType = UIKeyboardTypeNumberPad;
    [self addDoneButtonToTextField:self.dobTextField];

    self.doeTextField = [[UITextField alloc] init];
    self.doeTextField.placeholder = @"Ngày hết hạn (YYMMDD ví dụ: 380512)";
    self.doeTextField.borderStyle = UITextBorderStyleRoundedRect;
    self.doeTextField.keyboardType = UIKeyboardTypeNumberPad;
    [self addDoneButtonToTextField:self.doeTextField];

    UIStackView *mrzStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.docNumberTextField, self.dobTextField, self.doeTextField]];
    mrzStack.translatesAutoresizingMaskIntoConstraints = NO;
    mrzStack.axis = UILayoutConstraintAxisVertical;
    mrzStack.spacing = 8.0;
    [self.mrzContainer addSubview:mrzStack];

    // NFC Button
    self.scanNFCButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.scanNFCButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scanNFCButton setTitle:@"📡 Bắt Đầu Quét NFC CCCD" forState:UIControlStateNormal];
    [self.scanNFCButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.scanNFCButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    self.scanNFCButton.backgroundColor = [UIColor systemBlueColor];
    self.scanNFCButton.layer.cornerRadius = 14.0;
    [self.contentView addSubview:self.scanNFCButton];

    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    self.activityIndicator.hidesWhenStopped = YES;
    [self.contentView addSubview:self.activityIndicator];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.text = @"Bước 1: Quét mặt sau (hoặc nhập CAN/MRZ)\nBước 2: Bấm nút trên và áp sát lưng iPhone vào chip";
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    self.statusLabel.font = [UIFont systemFontOfSize:13];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 3;
    [self.contentView addSubview:self.statusLabel];

    // Export Stack
    self.exportContainer = [[UIStackView alloc] init];
    self.exportContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.exportContainer.axis = UILayoutConstraintAxisHorizontal;
    self.exportContainer.spacing = 12.0;
    self.exportContainer.distribution = UIStackViewDistributionFillEqually;

    self.saveToPhotosButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.saveToPhotosButton setTitle:@"💾 Lưu Vào Album" forState:UIControlStateNormal];
    self.saveToPhotosButton.backgroundColor = [UIColor systemGreenColor];
    [self.saveToPhotosButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.saveToPhotosButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.saveToPhotosButton.layer.cornerRadius = 10.0;
    self.saveToPhotosButton.enabled = NO;
    self.saveToPhotosButton.alpha = 0.5;

    self.shareJPGButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.shareJPGButton setTitle:@"📤 Xuất File .JPG" forState:UIControlStateNormal];
    self.shareJPGButton.backgroundColor = [UIColor systemOrangeColor];
    [self.shareJPGButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.shareJPGButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.shareJPGButton.layer.cornerRadius = 10.0;
    self.shareJPGButton.enabled = NO;
    self.shareJPGButton.alpha = 0.5;

    [self.exportContainer addArrangedSubview:self.saveToPhotosButton];
    [self.exportContainer addArrangedSubview:self.shareJPGButton];
    [self.contentView addSubview:self.exportContainer];

    // Layout Constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor],

        [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],

        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],

        [self.photoCardView.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:16],
        [self.photoCardView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
        [self.photoCardView.widthAnchor constraintEqualToConstant:160],
        [self.photoCardView.heightAnchor constraintEqualToConstant:200],

        [self.portraitImageView.topAnchor constraintEqualToAnchor:self.photoCardView.topAnchor],
        [self.portraitImageView.leadingAnchor constraintEqualToAnchor:self.photoCardView.leadingAnchor],
        [self.portraitImageView.trailingAnchor constraintEqualToAnchor:self.photoCardView.trailingAnchor],
        [self.portraitImageView.bottomAnchor constraintEqualToAnchor:self.photoCardView.bottomAnchor],

        [self.photoPlaceholderLabel.centerXAnchor constraintEqualToAnchor:self.photoCardView.centerXAnchor],
        [self.photoPlaceholderLabel.centerYAnchor constraintEqualToAnchor:self.photoCardView.centerYAnchor],

        [self.segmentAuth.topAnchor constraintEqualToAnchor:self.photoCardView.bottomAnchor constant:20],
        [self.segmentAuth.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.segmentAuth.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],

        // Camera
        [self.cameraContainer.topAnchor constraintEqualToAnchor:self.segmentAuth.bottomAnchor constant:14],
        [self.cameraContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.cameraContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
        [self.scanCameraButton.topAnchor constraintEqualToAnchor:self.cameraContainer.topAnchor],
        [self.scanCameraButton.leadingAnchor constraintEqualToAnchor:self.cameraContainer.leadingAnchor],
        [self.scanCameraButton.trailingAnchor constraintEqualToAnchor:self.cameraContainer.trailingAnchor],
        [self.scanCameraButton.heightAnchor constraintEqualToConstant:44],
        [self.scannedInfoLabel.topAnchor constraintEqualToAnchor:self.scanCameraButton.bottomAnchor constant:8],
        [self.scannedInfoLabel.leadingAnchor constraintEqualToAnchor:self.cameraContainer.leadingAnchor],
        [self.scannedInfoLabel.trailingAnchor constraintEqualToAnchor:self.cameraContainer.trailingAnchor],
        [self.scannedInfoLabel.bottomAnchor constraintEqualToAnchor:self.cameraContainer.bottomAnchor],

        // CAN
        [self.canContainer.topAnchor constraintEqualToAnchor:self.segmentAuth.bottomAnchor constant:14],
        [self.canContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.canContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
        [self.canTextField.topAnchor constraintEqualToAnchor:self.canContainer.topAnchor],
        [self.canTextField.leadingAnchor constraintEqualToAnchor:self.canContainer.leadingAnchor],
        [self.canTextField.trailingAnchor constraintEqualToAnchor:self.canContainer.trailingAnchor],
        [self.canTextField.bottomAnchor constraintEqualToAnchor:self.canContainer.bottomAnchor],
        [self.canTextField.heightAnchor constraintEqualToConstant:44],

        // MRZ
        [self.mrzContainer.topAnchor constraintEqualToAnchor:self.segmentAuth.bottomAnchor constant:14],
        [self.mrzContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.mrzContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
        [mrzStack.topAnchor constraintEqualToAnchor:self.mrzContainer.topAnchor],
        [mrzStack.leadingAnchor constraintEqualToAnchor:self.mrzContainer.leadingAnchor],
        [mrzStack.trailingAnchor constraintEqualToAnchor:self.mrzContainer.trailingAnchor],
        [mrzStack.bottomAnchor constraintEqualToAnchor:self.mrzContainer.bottomAnchor],

        // NFC Button
        [self.scanNFCButton.topAnchor constraintEqualToAnchor:self.cameraContainer.bottomAnchor constant:24],
        [self.scanNFCButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.scanNFCButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
        [self.scanNFCButton.heightAnchor constraintEqualToConstant:50],

        [self.activityIndicator.topAnchor constraintEqualToAnchor:self.scanNFCButton.bottomAnchor constant:12],
        [self.activityIndicator.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],

        [self.statusLabel.topAnchor constraintEqualToAnchor:self.activityIndicator.bottomAnchor constant:8],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],

        [self.exportContainer.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:20],
        [self.exportContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
        [self.exportContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
        [self.exportContainer.heightAnchor constraintEqualToConstant:46],
        [self.exportContainer.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-30]
    ]];
}

- (void)setupActions {
    [self.segmentAuth addTarget:self action:@selector(handleAuthSegmentChange) forControlEvents:UIControlEventValueChanged];
    [self.scanCameraButton addTarget:self action:@selector(handleOpenMRZCamera) forControlEvents:UIControlEventTouchUpInside];
    [self.scanNFCButton addTarget:self action:@selector(handleStartNFC) forControlEvents:UIControlEventTouchUpInside];
    [self.saveToPhotosButton addTarget:self action:@selector(handleSaveToPhotos) forControlEvents:UIControlEventTouchUpInside];
    [self.shareJPGButton addTarget:self action:@selector(handleShareJPG) forControlEvents:UIControlEventTouchUpInside];
}

- (void)handleAuthSegmentChange {
    [self updateAuthMode];
    [self dismissKeyboard];
}

- (void)updateAuthMode {
    self.cameraContainer.hidden = (self.segmentAuth.selectedSegmentIndex != 0);
    self.canContainer.hidden = (self.segmentAuth.selectedSegmentIndex != 1);
    self.mrzContainer.hidden = (self.segmentAuth.selectedSegmentIndex != 2);
}

- (void)handleOpenMRZCamera {
    [self dismissKeyboard];
    MRZScannerViewController *scanner = [[MRZScannerViewController alloc] init];
    scanner.delegate = self;
    [self presentViewController:scanner animated:YES completion:nil];
}

// MARK: - MRZScannerDelegate
- (void)mrzScannerDidScanDoc:(NSString *)doc birth:(NSString *)birth expiry:(NSString *)expiry {
    self.scannedDocNumber = doc;
    self.scannedDOB = birth;
    self.scannedDOE = expiry;

    self.scannedInfoLabel.text = [NSString stringWithFormat:@"✓ Đã nhận diện:\nCCCD: %@ | NS: %@ | HSD: %@", doc, birth, expiry];
    self.scannedInfoLabel.textColor = [UIColor systemGreenColor];

    self.docNumberTextField.text = doc;
    self.dobTextField.text = birth;
    self.doeTextField.text = expiry;

    self.statusLabel.text = @"Đã có thông tin mặt sau! Nhấn 'Bắt Đầu Quét NFC CCCD' và áp lưng iPhone vào chip.";
}

// MARK: - Handle NFC Scan
- (void)handleStartNFC {
    [self dismissKeyboard];
    NSData *seed = nil;

    switch (self.segmentAuth.selectedSegmentIndex) {
        case 0: {
            if (self.scannedDocNumber.length > 0 && self.scannedDOB.length > 0 && self.scannedDOE.length > 0) {
                seed = [CryptoUtils calculateBACSeedWithDoc:self.scannedDocNumber birth:self.scannedDOB expiry:self.scannedDOE];
            } else {
                [self showAlertWithTitle:@"Chưa quét mặt sau" message:@"Vui lòng bấm 'Mở Camera Quét Mặt Sau Thẻ' trước khi quét NFC."];
                return;
            }
            break;
        }
        case 1: {
            NSString *can = [self.canTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (can.length != 6) {
                [self showAlertWithTitle:@"Mã CAN không hợp lệ" message:@"Vui lòng nhập đủ 6 chữ số CAN in ở mặt trước CCCD."];
                return;
            }
            seed = [CryptoUtils calculateCANSeed:can];
            break;
        }
        case 2: {
            NSString *doc = [self.docNumberTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *dob = [self.dobTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *doe = [self.doeTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (doc.length == 0 || dob.length == 0 || doe.length == 0) {
                [self showAlertWithTitle:@"Thiếu thông tin" message:@"Vui lòng nhập đủ 3 trường: Số CCCD, Ngày sinh và Ngày hết hạn."];
                return;
            }
            self.scannedDocNumber = doc;
            seed = [CryptoUtils calculateBACSeedWithDoc:doc birth:dob expiry:doe];
            break;
        }
        default:
            break;
    }

    if (!seed) return;

    [self.activityIndicator startAnimating];
    self.statusLabel.text = @"Đang kích hoạt NFC... Vui lòng áp sát thẻ vào đầu máy iPhone.";

    self.cccdReader = [[CCCDReaderManager alloc] initWithSeed:seed];
    self.cccdReader.delegate = self;
    [self.cccdReader startScanning];
}

// MARK: - CCCDReaderManagerDelegate
- (void)cccdReaderDidStartScanning {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = @"Sẵn sàng! Hãy áp lưng iPhone sát chip tròn CCCD...";
    });
}

- (void)cccdReaderDidUpdateStatus:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = status;
    });
}

- (void)cccdReaderDidFinishWithSuccess:(UIImage *)image rawData:(NSData *)rawData {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.activityIndicator stopAnimating];
        self.extractedImage = image;
        self.portraitImageView.image = image;
        self.photoPlaceholderLabel.hidden = YES;

        self.statusLabel.text = [NSString stringWithFormat:@"✅ Đọc ảnh chân dung thành công! Kích thước: %lu KB.", (unsigned long)(rawData.length / 1024)];
        self.statusLabel.textColor = [UIColor systemGreenColor];

        self.saveToPhotosButton.enabled = YES;
        self.saveToPhotosButton.alpha = 1.0;

        self.shareJPGButton.enabled = YES;
        self.shareJPGButton.alpha = 1.0;

        UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
        [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
    });
}

- (void)cccdReaderDidFailWithError:(NSString *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.activityIndicator stopAnimating];
        self.statusLabel.text = [NSString stringWithFormat:@"❌ %@", error];
        self.statusLabel.textColor = [UIColor systemRedColor];
    });
}

// MARK: - Export Handlers
- (void)handleSaveToPhotos {
    if (!self.extractedImage) return;

    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showAlertWithTitle:@"Quyền truy cập" message:@"Ứng dụng chưa được cấp quyền thêm ảnh vào Album."];
            });
            return;
        }

        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromImage:self.extractedImage];
        } completionHandler:^(BOOL success, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success) {
                    [self showAlertWithTitle:@"Thành công" message:@"Đã lưu ảnh chân dung CCCD vào Album ảnh (JPG)."];
                } else {
                    [self showAlertWithTitle:@"Lỗi" message:error.localizedDescription ?: @"Không thể lưu ảnh."];
                }
            });
        }];
    }];
}

- (void)handleShareJPG {
    if (!self.extractedImage) return;

    NSData *jpgData = [DG2Parser exportToJPG:self.extractedImage quality:0.95];
    if (!jpgData) {
        [self showAlertWithTitle:@"Lỗi" message:@"Không thể nén ảnh sang định dạng JPG."];
        return;
    }

    NSString *fileName = [NSString stringWithFormat:@"CCCD_%@_%ld.jpg",
                          self.scannedDocNumber.length > 0 ? self.scannedDocNumber : @"AnhChanDung",
                          (long)[[NSDate date] timeIntervalSince1970]];
    NSURL *tempURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];

    NSError *writeErr = nil;
    [jpgData writeToURL:tempURL options:NSDataWritingAtomic error:&writeErr];

    if (writeErr) {
        [self showAlertWithTitle:@"Lỗi ghi file" message:writeErr.localizedDescription];
        return;
    }

    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[tempURL] applicationActivities:nil];
    if (activityVC.popoverPresentationController) {
        activityVC.popoverPresentationController.sourceView = self.view;
        activityVC.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 0, 0);
    }
    [self presentViewController:activityVC animated:YES completion:nil];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
