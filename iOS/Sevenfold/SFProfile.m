//
//  SFProfile.m
//  Sevenfold
//

#import "SFProfile.h"
#import "SFLocalization.h"
#import "SFTheme.h"
#import "SFSettings.h"
#import "SFDevice.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *SFInitials(void) {
    NSString *source = [SFSettings profileName] ?: [SFSettings appleIDEmail] ?: @"?";
    NSMutableString *initials = [NSMutableString string];
    for (NSString *word in [source componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" .@_-"]]) {
        if (word.length == 0) continue;
        [initials appendString:[[word substringToIndex:1] uppercaseString]];
        if (initials.length == 2 || [SFSettings profileName] == nil) break;
    }
    return initials.length ? initials : @"?";
}

static UIImage *SFAvatarWithPhoto(CGFloat size, UIImage *photo) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGRect rect = CGRectMake(0, 0, size, size);
        [[UIBezierPath bezierPathWithOvalInRect:rect] addClip];
        if (photo) {
            [photo drawInRect:rect];
        } else {
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            NSArray *colors = @[(id)[UIColor colorWithRed:0.23 green:0.16 blue:0.33 alpha:1].CGColor,
                                (id)[UIColor colorWithRed:0.55 green:0.29 blue:0.18 alpha:1].CGColor,
                                (id)[SFTheme amber].CGColor];
            CGFloat locations[] = {0, 0.55, 1};
            CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, locations);
            CGContextDrawLinearGradient(ctx.CGContext, gradient, CGPointZero, CGPointMake(size * 0.6, size), 0);
            CGGradientRelease(gradient);
            CGColorSpaceRelease(space);
            NSString *text = SFInitials();
            NSDictionary *attrs = @{ NSFontAttributeName: [UIFont systemFontOfSize:size * 0.38 weight:UIFontWeightBold],
                                     NSForegroundColorAttributeName: [UIColor whiteColor] };
            CGSize textSize = [text sizeWithAttributes:attrs];
            [text drawAtPoint:CGPointMake((size - textSize.width) / 2, (size - textSize.height) / 2) withAttributes:attrs];
        }
    }];
}

UIImage *SFProfileAvatar(CGFloat size) { return SFAvatarWithPhoto(size, [SFSettings profileImage]); }

static UIButton *SFEyeButton(BOOL hidden) {
    UIButtonConfiguration *config = [UIButtonConfiguration tintedButtonConfiguration];
    config.image = [UIImage systemImageNamed:hidden ? @"eye.slash" : @"eye"
                           withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold]];
    config.baseBackgroundColor = [SFTheme amber];
    config.baseForegroundColor = [SFTheme amber];
    config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    config.contentInsets = NSDirectionalEdgeInsetsMake(6, 6, 6, 6);
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
    button.accessibilityLabel = hidden ? SFL(@"Show email") : SFL(@"Hide email");
    [button.widthAnchor constraintEqualToConstant:30].active = YES;
    [button.heightAnchor constraintEqualToConstant:30].active = YES;
    return button;
}

// MARK: - Settings card

@interface SFProfileCell ()
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *emailLabel;
@property (nonatomic, strong) UILabel *modelLabel;
@property (nonatomic, strong) UIStackView *emailRow;
@property (nonatomic, strong) UIStackView *titleRow;
@property (nonatomic, strong) UIButton *eye;
@property (nonatomic, strong) UILabel *editLabel;
@end

@implementation SFProfileCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = [SFTheme card];
        _avatar = [UIImageView new];
        _avatar.translatesAutoresizingMaskIntoConstraints = NO;
        _avatar.layer.cornerRadius = 30;
        _avatar.clipsToBounds = YES;
        [_avatar.widthAnchor constraintEqualToConstant:60].active = YES;
        [_avatar.heightAnchor constraintEqualToConstant:60].active = YES;

        _nameLabel = [SFTheme labelWithSize:19 weight:UIFontWeightBold color:[UIColor labelColor]];
        _nameLabel.numberOfLines = 0;
        _nameLabel.lineBreakMode = NSLineBreakByCharWrapping;
        // Full width under the name, so the whole address fits (long ones wrap, never "…").
        _emailLabel = [SFTheme labelWithSize:13 weight:UIFontWeightRegular color:[UIColor labelColor]];
        _emailLabel.numberOfLines = 0;
        _emailLabel.lineBreakMode = NSLineBreakByCharWrapping;
        _modelLabel = [SFTheme labelWithSize:13 weight:UIFontWeightRegular color:[SFTheme secondaryText]];
        _modelLabel.numberOfLines = 1;

        _emailRow = [[UIStackView alloc] initWithArrangedSubviews:@[_emailLabel]];
        _emailRow.spacing = 8;
        _emailRow.alignment = UIStackViewAlignmentCenter;

        // Name on the left, eye on the right of the same line.
        _titleRow = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel]];
        _titleRow.spacing = 8;
        _titleRow.alignment = UIStackViewAlignmentCenter;
        UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[_titleRow, _emailRow, _modelLabel]];
        texts.axis = UILayoutConstraintAxisVertical;
        texts.spacing = 3;
        texts.alignment = UIStackViewAlignmentFill;

        _editLabel = [SFTheme labelWithSize:14 weight:UIFontWeightSemibold color:[SFTheme amber]];
        _editLabel.text = SFL(@"Edit");
        [_editLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [_editLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        _editLabel.hidden = YES;   // "Edit profile" is its own row now
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_avatar, texts]];
        row.spacing = 14;
        row.alignment = UIStackViewAlignmentCenter;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:row];
        UILayoutGuide *m = self.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
            [row.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
            [row.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:14],
            [row.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-14],
        ]];
    }
    return self;
}

- (void)toggleEmail {
    [SFSettings setHideEmail:![SFSettings hideEmail]];
    if (self.onToggleEmail) self.onToggleEmail();
    else [self refresh];
}

- (void)refresh {
    BOOL signedIn = [SFSettings isSignedIn];
    self.avatar.image = SFProfileAvatar(60);
    NSString *name = [SFSettings profileName];
    NSString *email = [SFSettings displayEmail];
    if (!signedIn) {
        self.nameLabel.text = name ?: SFL(@"Not signed in");
        self.emailLabel.text = SFL(@"Sign in to start signing apps");
        self.emailLabel.textColor = [SFTheme secondaryText];
        self.modelLabel.text = [SFDevice modelName];
    } else if (name) {
        self.nameLabel.text = name;
        self.emailLabel.text = email ?: SFL(@"Signed in");
        self.emailLabel.textColor = [UIColor labelColor];
        self.modelLabel.text = [SFDevice modelName];
    } else {
        // No name: the email is the title.
        self.nameLabel.text = email ?: SFL(@"Signed in");
        self.emailLabel.text = [SFDevice modelName];
        self.emailLabel.textColor = [SFTheme secondaryText];
        self.modelLabel.text = nil;
    }
    self.modelLabel.hidden = self.modelLabel.text.length == 0;

    // Eye goes next to wherever the email is shown.
    [self.eye removeFromSuperview];
    self.eye = nil;
    if (signedIn && email) {
        self.eye = SFEyeButton([SFSettings hideEmail]);
        [self.eye addTarget:self action:@selector(toggleEmail) forControlEvents:UIControlEventTouchUpInside];
        [self.eye setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self.eye setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [self.titleRow addArrangedSubview:self.eye];
    }
    self.nameLabel.font = [UIFont systemFontOfSize:name || !signedIn ? 19 : 16 weight:UIFontWeightBold];
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", self.nameLabel.text ?: @"", self.emailLabel.text ?: @""];
}

@end

// MARK: - Edit profile

@interface SFEditProfileViewController () <PHPickerViewControllerDelegate, UIDocumentPickerDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UIImageView *bigAvatar;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong, nullable) UIImage *pendingImage;
@property (nonatomic) BOOL removePhoto;
@end

@implementation SFEditProfileViewController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SFL(@"Edit profile");
    self.tableView.backgroundColor = [SFTheme background];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 176)];
    self.bigAvatar = [UIImageView new];
    self.bigAvatar.translatesAutoresizingMaskIntoConstraints = NO;
    self.bigAvatar.layer.cornerRadius = 64;
    self.bigAvatar.clipsToBounds = YES;
    self.bigAvatar.image = SFProfileAvatar(128);
    [header addSubview:self.bigAvatar];

    UIButtonConfiguration *camera = [UIButtonConfiguration filledButtonConfiguration];
    camera.image = [UIImage systemImageNamed:@"camera.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]];
    camera.baseBackgroundColor = [SFTheme amber];
    camera.baseForegroundColor = [UIColor colorWithRed:0.10 green:0.07 blue:0.02 alpha:1];
    camera.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    UIButton *cameraButton = [UIButton buttonWithConfiguration:camera primaryAction:nil];
    cameraButton.translatesAutoresizingMaskIntoConstraints = NO;
    cameraButton.accessibilityLabel = SFL(@"Change photo");
    cameraButton.layer.borderWidth = 3;
    cameraButton.layer.borderColor = [SFTheme background].CGColor;
    cameraButton.layer.cornerRadius = 21;
    [cameraButton addTarget:self action:@selector(choosePhotos) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:cameraButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.bigAvatar.widthAnchor constraintEqualToConstant:128],
        [self.bigAvatar.heightAnchor constraintEqualToConstant:128],
        [self.bigAvatar.centerXAnchor constraintEqualToAnchor:header.centerXAnchor],
        [self.bigAvatar.topAnchor constraintEqualToAnchor:header.topAnchor constant:24],
        [cameraButton.widthAnchor constraintEqualToConstant:42],
        [cameraButton.heightAnchor constraintEqualToConstant:42],
        [cameraButton.trailingAnchor constraintEqualToAnchor:self.bigAvatar.trailingAnchor constant:2],
        [cameraButton.bottomAnchor constraintEqualToAnchor:self.bigAvatar.bottomAnchor constant:2],
    ]];
    self.tableView.tableHeaderView = header;

    self.nameField = [UITextField new];
    self.nameField.text = [SFSettings profileName];
    self.nameField.placeholder = SFL(@"Your name (optional)");
    self.nameField.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.nameField.returnKeyType = UIReturnKeyDone;
    self.nameField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.nameField.delegate = self;
    self.nameField.accessibilityLabel = SFL(@"Display name");

    [[NSNotificationCenter defaultCenter] addObserver:self.tableView selector:@selector(reloadData) name:SFSettingsDidChangeNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self.tableView]; }

- (BOOL)textFieldShouldReturn:(UITextField *)textField { [textField resignFirstResponder]; return YES; }

- (void)updateAvatarPreview {
    if (self.pendingImage) {
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(128, 128)];
        UIImage *image = self.pendingImage;
        CGFloat side = MIN(image.size.width, image.size.height);
        self.bigAvatar.image = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            CGFloat scale = 128 / side;
            [image drawInRect:CGRectMake(-(image.size.width - side) / 2 * scale, -(image.size.height - side) / 2 * scale, image.size.width * scale, image.size.height * scale)];
        }];
    } else if (self.removePhoto) {
        self.bigAvatar.image = SFAvatarWithPhoto(128, nil);   // preview only until Done
    } else {
        self.bigAvatar.image = SFProfileAvatar(128);
    }
}

- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)done {
    [SFSettings setProfileName:self.nameField.text];
    if (self.pendingImage) [SFSettings setProfileImage:self.pendingImage];
    else if (self.removePhoto) [SFSettings setProfileImage:nil];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)choosePhotos {
    PHPickerConfiguration *config = [PHPickerConfiguration new];
    config.filter = [PHPickerFilter imagesFilter];
    config.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)chooseFiles {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)usePickedImage:(UIImage *)image {
    if (!image) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.pendingImage = image;
        self.removePhoto = NO;
        [self updateAvatarPreview];
        [self.tableView reloadData];
    });
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSItemProvider *provider = results.firstObject.itemProvider;
    if (![provider canLoadObjectOfClass:[UIImage class]]) return;
    [provider loadObjectOfClass:[UIImage class] completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
        if ([(NSObject *)object isKindOfClass:[UIImage class]]) [self usePickedImage:(UIImage *)object];
    }];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSData *data = [NSData dataWithContentsOfURL:urls.firstObject];
    [self usePickedImage:data ? [UIImage imageWithData:data] : nil];
}

// MARK: Table: 0 photo actions · 1 name · 2 account

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return ([SFSettings profileImage] || self.pendingImage) && !self.removePhoto ? 3 : 2;
    if (section == 1) return 1;
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[SFL(@"Photo"), SFL(@"Name"), SFL(@"Account")][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return SFL(@"The photo is cropped to a circle from its middle.");
    if (section == 1) return SFL(@"Leave it empty to show your email as the title.");
    return SFL(@"Your name and photo stay on this iPhone only. Apple never sees them.");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.backgroundColor = [SFTheme card];
    if (indexPath.section == 0) {
        NSArray *titles = @[SFL(@"Choose from Photos"), SFL(@"Choose from Files"), SFL(@"Remove photo")];
        cell.textLabel.text = titles[indexPath.row];
        cell.textLabel.textColor = indexPath.row == 2 ? [SFTheme danger] : [SFTheme amber];
        return cell;
    }
    if (indexPath.section == 1) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        self.nameField.translatesAutoresizingMaskIntoConstraints = NO;
        [self.nameField removeFromSuperview];
        [cell.contentView addSubview:self.nameField];
        UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [self.nameField.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
            [self.nameField.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
            [self.nameField.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
            [self.nameField.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
            [self.nameField.heightAnchor constraintGreaterThanOrEqualToConstant:52],
        ]];
        return cell;
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (indexPath.row == 0) {
        // "Apple ID" label with the full address on its own line under it; eye on the right.
        UILabel *label = [SFTheme labelWithSize:13 weight:UIFontWeightRegular color:[SFTheme secondaryText]];
        label.text = SFL(@"Apple ID");
        UILabel *email = [SFTheme labelWithSize:15 weight:UIFontWeightRegular color:[UIColor labelColor]];
        email.text = [SFSettings displayEmail] ?: SFL(@"Not signed in");
        email.numberOfLines = 0;
        email.lineBreakMode = NSLineBreakByCharWrapping;
        UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[label, email]];
        texts.axis = UILayoutConstraintAxisVertical;
        texts.spacing = 3;
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[texts]];
        row.spacing = 10;
        row.alignment = UIStackViewAlignmentCenter;
        if ([SFSettings appleIDEmail]) {
            UIButton *eye = SFEyeButton([SFSettings hideEmail]);
            [eye addTarget:self action:@selector(toggleEmail) forControlEvents:UIControlEventTouchUpInside];
            [row addArrangedSubview:eye];
        }
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:row];
        UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
            [row.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
            [row.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:11],
            [row.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-11],
        ]];
    } else {
        cell.textLabel.text = SFL(@"This iPhone");
        cell.textLabel.textColor = [SFTheme secondaryText];
        cell.detailTextLabel.text = [SFDevice modelName];
        cell.detailTextLabel.textColor = [UIColor labelColor];
    }
    return cell;
}

- (void)toggleEmail {
    [SFSettings setHideEmail:![SFSettings hideEmail]];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 0) return;
    if (indexPath.row == 0) [self choosePhotos];
    else if (indexPath.row == 1) [self chooseFiles];
    else {
        self.pendingImage = nil;
        self.removePhoto = YES;
        [self updateAvatarPreview];
        [self.tableView reloadData];
    }
}

@end
