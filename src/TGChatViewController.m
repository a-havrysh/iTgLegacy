#import "TGChatViewController.h"
#import "TGClient.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kInputHeight = 44.0f;
static const CGFloat kBubbleMaxW  = 240.0f;
static const CGFloat kPadH        = 10.0f;
static const CGFloat kPadV        = 7.0f;
static const CGFloat kImageMax    = 200.0f;

#pragma mark - bubble cell

@interface TGBubbleCell : UITableViewCell
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UILabel *body;
@property (nonatomic, strong) UIImageView *picture;
@property (nonatomic, strong) UILabel *time;
@end

@implementation TGBubbleCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	self.backgroundColor = [UIColor clearColor];
	self.contentView.backgroundColor = [UIColor clearColor];
	self.selectionStyle = UITableViewCellSelectionStyleNone;

	self.bubble = [[UIView alloc] init];
	self.bubble.layer.cornerRadius = 14;
	self.bubble.layer.borderWidth = 1.0f;
	self.bubble.clipsToBounds = YES;
	[self.contentView addSubview:self.bubble];

	self.picture = [[UIImageView alloc] init];
	self.picture.contentMode = UIViewContentModeScaleAspectFill;
	self.picture.clipsToBounds = YES;
	[self.bubble addSubview:self.picture];

	self.body = [[UILabel alloc] init];
	self.body.numberOfLines = 0;
	self.body.font = [UIFont systemFontOfSize:15];
	self.body.backgroundColor = [UIColor clearColor];
	[self.bubble addSubview:self.body];

	self.time = [[UILabel alloc] init];
	self.time.font = [UIFont systemFontOfSize:11];
	self.time.backgroundColor = [UIColor clearColor];
	self.time.textAlignment = NSTextAlignmentRight;
	[self.bubble addSubview:self.time];

	return self;
}

@end

#pragma mark - controller

@interface TGChatViewController ()
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIView *inputBar;
@property (nonatomic, strong) UITextField *input;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) NSArray *messages;          // flattened TDLib dicts
@property (nonatomic, strong) NSMutableDictionary *images; // fileId -> UIImage
@property (nonatomic, strong) NSMutableSet *imagesRequested;
@end

@implementation TGChatViewController

#pragma mark - layout

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = self.chatTitle ?: @"Chat";
	self.messages = @[];
	self.images = [NSMutableDictionary dictionary];
	self.imagesRequested = [NSMutableSet set];
	self.view.backgroundColor = [UIColor colorWithRed:0.85f green:0.87f blue:0.83f alpha:1.0f];

	CGRect b = self.view.bounds;

	self.table = [[UITableView alloc] initWithFrame:
			CGRectMake(0, 0, b.size.width, b.size.height - kInputHeight)];
	self.table.dataSource = self;
	self.table.delegate = self;
	self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.table.backgroundColor = [UIColor clearColor];
	self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.view addSubview:self.table];

	[self buildInputBar:b];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:)
			name:UIKeyboardWillShowNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:)
			name:UIKeyboardWillHideNotification object:nil];

	[self reload];
}

- (void)buildInputBar:(CGRect)b {
	self.inputBar = [[UIView alloc] initWithFrame:
			CGRectMake(0, b.size.height - kInputHeight, b.size.width, kInputHeight)];
	self.inputBar.backgroundColor = [UIColor colorWithWhite:0.93f alpha:1.0f];
	self.inputBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;

	UIView *hair = [[UIView alloc] initWithFrame:CGRectMake(0, 0, b.size.width, 1)];
	hair.backgroundColor = [UIColor colorWithWhite:0.75f alpha:1.0f];
	hair.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.inputBar addSubview:hair];

	self.input = [[UITextField alloc] initWithFrame:
			CGRectMake(8, 7, b.size.width - 76, kInputHeight - 14)];
	self.input.borderStyle = UITextBorderStyleRoundedRect;
	self.input.placeholder = @"Message";
	self.input.font = [UIFont systemFontOfSize:15];
	self.input.returnKeyType = UIReturnKeySend;
	self.input.delegate = self;
	self.input.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.inputBar addSubview:self.input];

	// UIButtonTypeSystem is iOS 7; RoundedRect is its iOS 6 equivalent and is
	// merely deprecated later, not absent.
	UIButtonType sendType = UIButtonTypeRoundedRect;
	if (NSFoundationVersionNumber > 993.00 /* NSFoundationVersionNumber_iOS_6_1 */)
		sendType = UIButtonTypeSystem;
	self.sendButton = [UIButton buttonWithType:sendType];
	self.sendButton.frame = CGRectMake(b.size.width - 64, 6, 58, kInputHeight - 12);
	[self.sendButton setTitle:@"Send" forState:UIControlStateNormal];
	self.sendButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
	self.sendButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[self.sendButton addTarget:self action:@selector(sendTapped)
			forControlEvents:UIControlEventTouchUpInside];
	[self.inputBar addSubview:self.sendButton];

	[self.view addSubview:self.inputBar];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - data

- (void)reload {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] historyForChat:self.chatId limit:60 completion:^(NSArray *messages){
		TGChatViewController *me = weakSelf;
		if (!me)
			return;
		me.messages = messages;
		[me.table reloadData];
		[me scrollToBottomAnimated:NO];
		[me fetchMissingImages];

		NSMutableArray *ids = [NSMutableArray array];
		for (NSDictionary *m in messages)
			[ids addObject:m[@"id"]];
		[[TGClient shared] markRead:ids inChat:me.chatId];
	}];
}

- (void)fetchMissingImages {
	__weak typeof(self) weakSelf = self;
	for (NSDictionary *m in self.messages){
		NSNumber *fileId = m[@"photoId"];
		if (![fileId isKindOfClass:NSNumber.class])
			continue;
		if (self.images[fileId] || [self.imagesRequested containsObject:fileId])
			continue;
		[self.imagesRequested addObject:fileId];

		[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *path){
			TGChatViewController *me = weakSelf;
			if (!me || !path)
				return;
			UIImage *img = [UIImage imageWithContentsOfFile:path];
			if (!img)
				return;
			me.images[fileId] = img;
			[me.table reloadData];
		}];
	}
}

- (void)scrollToBottomAnimated:(BOOL)animated {
	if (!self.messages.count)
		return;
	NSIndexPath *last = [NSIndexPath indexPathForRow:self.messages.count - 1 inSection:0];
	[self.table scrollToRowAtIndexPath:last
					  atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

#pragma mark - sending

- (void)sendTapped {
	NSString *text = [self.input.text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!text.length)
		return;

	[[TGClient shared] sendText:text toChat:self.chatId];
	self.input.text = @"";

	// TDLib echoes the message back as an update; refresh shortly after.
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
			dispatch_get_main_queue(), ^{
		[self reload];
	});
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[self sendTapped];
	return NO;
}

#pragma mark - geometry

/// Size of the text inside a bubble, and of the bubble itself.
- (CGSize)bodySizeFor:(NSDictionary *)m {
	NSString *text = m[@"text"] ?: @"";
	if (!text.length)
		return CGSizeZero;
	return [text sizeWithFont:[UIFont systemFontOfSize:15]
			constrainedToSize:CGSizeMake(kBubbleMaxW - 2 * kPadH, 10000)
				lineBreakMode:NSLineBreakByWordWrapping];
}

- (CGSize)imageSizeFor:(NSDictionary *)m {
	NSNumber *fileId = m[@"photoId"];
	UIImage *img = [fileId isKindOfClass:NSNumber.class] ? self.images[fileId] : nil;
	if (!img)
		return CGSizeZero;

	CGFloat scale = MIN(kImageMax / img.size.width, kImageMax / img.size.height);
	scale = MIN(scale, 1.0f);
	return CGSizeMake(floorf(img.size.width * scale), floorf(img.size.height * scale));
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *m = self.messages[indexPath.row];
	CGSize body = [self bodySizeFor:m];
	CGSize pic  = [self imageSizeFor:m];

	CGFloat h = kPadV * 2 + 14;                 // padding + time line
	if (pic.height > 0) h += pic.height + 4;
	if (body.height > 0) h += body.height;
	return MAX(h + 6, 40);
}

#pragma mark - table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGBubbleCell";
	TGBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGBubbleCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];

	NSDictionary *m = self.messages[indexPath.row];
	BOOL mine = [m[@"outgoing"] boolValue];

	CGSize body = [self bodySizeFor:m];
	CGSize pic  = [self imageSizeFor:m];

	CGFloat contentW = MAX(body.width, pic.width);
	CGFloat bubbleW  = MAX(contentW + 2 * kPadH, 56);
	CGFloat bubbleH  = kPadV * 2 + 14 + (pic.height ? pic.height + 4 : 0) + body.height;

	CGFloat x = mine ? (tableView.bounds.size.width - bubbleW - 8) : 8;
	cell.bubble.frame = CGRectMake(x, 3, bubbleW, bubbleH);

	// Outgoing green, incoming white - the convention every client uses.
	cell.bubble.backgroundColor = mine
		? [UIColor colorWithRed:0.85f green:0.96f blue:0.76f alpha:1.0f]
		: [UIColor whiteColor];
	cell.bubble.layer.borderColor = [UIColor colorWithWhite:0.0f alpha:0.12f].CGColor;

	CGFloat y = kPadV;
	if (pic.height > 0){
		NSNumber *fileId = m[@"photoId"];
		cell.picture.hidden = NO;
		cell.picture.image = self.images[fileId];
		cell.picture.frame = CGRectMake(kPadH, y, pic.width, pic.height);
		cell.picture.layer.cornerRadius = 8;
		y += pic.height + 4;
	} else {
		cell.picture.hidden = YES;
		cell.picture.image = nil;
	}

	cell.body.hidden = (body.height == 0);
	cell.body.text = m[@"text"];
	cell.body.textColor = [UIColor colorWithWhite:0.08f alpha:1.0f];
	cell.body.frame = CGRectMake(kPadH, y, body.width, body.height);

	static NSDateFormatter *hm = nil;
	if (!hm){ hm = [[NSDateFormatter alloc] init]; [hm setDateFormat:@"HH:mm"]; }
	cell.time.text = [hm stringFromDate:
			[NSDate dateWithTimeIntervalSince1970:[m[@"date"] doubleValue]]];
	cell.time.textColor = [UIColor colorWithWhite:0.45f alpha:1.0f];
	cell.time.frame = CGRectMake(bubbleW - 44 - kPadH + 6, bubbleH - kPadV - 12, 44, 12);

	return cell;
}

#pragma mark - keyboard

- (void)keyboardWillShow:(NSNotification *)note {
	CGRect kb = [[note.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
	[self shiftForKeyboardHeight:kb.size.height];
}

- (void)keyboardWillHide:(NSNotification *)note {
	[self shiftForKeyboardHeight:0];
}

- (void)shiftForKeyboardHeight:(CGFloat)height {
	CGRect b = self.view.bounds;
	[UIView animateWithDuration:0.25 animations:^{
		self.inputBar.frame = CGRectMake(0, b.size.height - kInputHeight - height,
				b.size.width, kInputHeight);
		self.table.frame = CGRectMake(0, 0, b.size.width,
				b.size.height - kInputHeight - height);
	} completion:^(BOOL done){
		[self scrollToBottomAnimated:NO];
	}];
}

@end

// vim:ft=objc
