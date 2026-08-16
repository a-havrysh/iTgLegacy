#import "TGQRCodeViewController.h"
#import "TGQRImage.h"
#import "TGTheme.h"

@interface TGQRCodeViewController ()
@property (nonatomic, copy) NSString *link;
@property (nonatomic, copy) NSString *caption;
@property (nonatomic, strong) TGQRCodeView *codeView;
@property (nonatomic, strong) UILabel *linkLabel;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UIButton *actionButton;
@end

@implementation TGQRCodeViewController

- (id)initWithLink:(NSString *)link caption:(NSString *)caption {
	self = [super init];
	if (!self)
		return nil;
	_link = [link copy];
	_caption = [caption copy];
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	TGTheme *theme = [TGTheme shared];
	[theme styleNavigationBar:self.navigationController.navigationBar];
	self.title = @"QR Code";
	self.view.backgroundColor = [theme listBackgroundColour];
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	self.codeView = [[TGQRCodeView alloc] initWithFrame:CGRectZero];
	self.codeView.text = self.link;
	[self.view addSubview:self.codeView];

	self.captionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.captionLabel.text = self.caption.length
			? self.caption
			: @"Point another phone's camera at this code.";
	self.captionLabel.numberOfLines = 0;
	self.captionLabel.textAlignment = UITextAlignmentCenter;
	self.captionLabel.font = [UIFont systemFontOfSize:14];
	self.captionLabel.textColor = [theme secondaryTextColour];
	self.captionLabel.backgroundColor = [UIColor clearColor];
	[self.view addSubview:self.captionLabel];

	self.linkLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.linkLabel.text = self.link;
	self.linkLabel.numberOfLines = 0;
	self.linkLabel.lineBreakMode = UILineBreakModeCharacterWrap;
	self.linkLabel.textAlignment = UITextAlignmentCenter;
	self.linkLabel.font = [UIFont boldSystemFontOfSize:15];
	self.linkLabel.textColor = [theme primaryTextColour];
	self.linkLabel.backgroundColor = [UIColor clearColor];
	[self.view addSubview:self.linkLabel];

	UIImage *plate = [[UIImage imageNamed:@"GroupedActionButton.png"]
			stretchableImageWithLeftCapWidth:24 topCapHeight:0];
	UIImage *platePressed = [[UIImage imageNamed:@"GroupedActionButton_Highlighted.png"]
			stretchableImageWithLeftCapWidth:24 topCapHeight:0];
	self.actionButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.actionButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
	self.actionButton.titleLabel.shadowOffset = CGSizeMake(0, -1);
	[self.actionButton setBackgroundImage:plate forState:UIControlStateNormal];
	[self.actionButton setBackgroundImage:platePressed forState:UIControlStateHighlighted];
	[self.actionButton setTitle:@"Copy Link" forState:UIControlStateNormal];
	[self.actionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[self.actionButton setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.5f]
								forState:UIControlStateNormal];
	[self.actionButton addTarget:self action:@selector(copyLink)
			  forControlEvents:UIControlEventTouchUpInside];
	self.actionButton.hidden = !self.link.length;
	[self.view addSubview:self.actionButton];
}

- (void)viewWillLayoutSubviews {
	[super viewWillLayoutSubviews];
	[self layoutContent];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self layoutContent];
}

- (void)layoutContent {
	CGRect bounds = self.view.bounds;
	CGFloat width = bounds.size.width;
	CGFloat inset = 20;
	CGFloat side = MIN(width - inset * 2, bounds.size.height * 0.52f);

	if (side < 80)
		side = 80;

	CGSize captionSize = [self.captionLabel.text
			sizeWithFont:self.captionLabel.font
			constrainedToSize:CGSizeMake(width - inset * 2, 200)
			lineBreakMode:UILineBreakModeWordWrap];
	CGSize linkSize = [self.linkLabel.text
			sizeWithFont:self.linkLabel.font
			constrainedToSize:CGSizeMake(width - inset * 2, 200)
			lineBreakMode:UILineBreakModeCharacterWrap];

	CGFloat buttonHeight = 43;
	CGFloat total = captionSize.height + 16 + side + 14 + linkSize.height
			+ 18 + buttonHeight;
	CGFloat top = (int)MAX(16.0f, (bounds.size.height - total) / 2);

	self.captionLabel.frame = CGRectMake(inset, top, width - inset * 2,
										 captionSize.height);
	top += captionSize.height + 16;
	self.codeView.frame = CGRectMake((int)((width - side) / 2), (int)top,
									 (int)side, (int)side);
	top += side + 14;
	self.linkLabel.frame = CGRectMake(inset, (int)top, width - inset * 2,
									  linkSize.height);
	top += linkSize.height + 18;
	self.actionButton.frame = CGRectMake((int)((width - 148) / 2), (int)top,
									   148, buttonHeight);
}

- (void)copyLink {
	if (!self.link.length)
		return;
	[UIPasteboard generalPasteboard].string = self.link;
	[self.actionButton setTitle:@"Copied" forState:UIControlStateNormal];
	[self performSelector:@selector(restoreCopyTitle) withObject:nil afterDelay:1.2];
}

- (void)restoreCopyTitle {
	[self.actionButton setTitle:@"Copy Link" forState:UIControlStateNormal];
}

- (void)dealloc {
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
}

@end

// vim:ft=objc
