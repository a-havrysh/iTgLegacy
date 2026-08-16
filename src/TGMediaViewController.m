#import "TGMediaViewController.h"
#import "TGLazyFramework.h"

#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>

#import "TGClient.h"
#import "TGClient+Files.h"
#import "TGClient+Messages.h"
#import "TGClient+Search.h"
#import "TGForwardPicker.h"
#import "TGIcons.h"
#import "TGImageDecode.h"
#import "TGRemoteImageView.h"
#import "TGTheme.h"
#import "TGViewRecycler.h"

static const CGFloat TGMediaTileSide    = 75.0f;
static const CGFloat TGMediaTileSpacing = 4.0f;
static const CGFloat TGMediaRowHeight   = 79.0f;
static const CGFloat TGMediaBannerHeight = 45.0f;
static const NSInteger TGMediaPageSize  = 50;
static const CGFloat TGMediaPageGap     = 40.0f;
static const CGFloat TGMediaScopeHeight = 44.0f;
static const CGFloat TGMediaScopeButtonHeight = 30.0f;
static const CGFloat TGMediaSearchBarHeight = 44.0f;
static const CGFloat TGMediaListRowHeight = 56.0f;
static const CGFloat TGMediaTopBarFallbackHeight = 44.0f;

static CGFloat TGMediaTopBarHeight(void) {
	UIImage *panel = [UIImage imageNamed:@"GalleryTopPanel.png"];
	return panel ? panel.size.height : TGMediaTopBarFallbackHeight;
}

static CGFloat TGMediaStatusBarInset(void) {
	CGRect frame = [UIApplication sharedApplication].statusBarFrame;
	CGFloat inset = MIN(frame.size.width, frame.size.height);
	if (inset < 1.0f)
		inset = 20.0f;
	return inset;
}

static UIColor *TGMediaPlaceholderColour(void) {
	static UIColor *colour = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		colour = [UIColor colorWithRed:0xdf / 255.0f green:0xe4 / 255.0f
								  blue:0xeb / 255.0f alpha:1.0f];
	});
	return colour;
}

enum {
	TGMediaScopeMedia = 0,
	TGMediaScopeFiles = 1,
	TGMediaScopeLinks = 2,
	TGMediaScopeMusic = 3,
};

static NSString *const TGMediaTileIdentifier = @"TGMediaTile";

static NSString *TGMediaFormatDuration(NSInteger seconds) {
	if (seconds < 0)
		seconds = 0;
	return [NSString stringWithFormat:@"%d:%02d", (int)(seconds / 60), (int)(seconds % 60)];
}

static NSString *TGMediaFormatBytes(long long bytes) {
	if (bytes < 1024)
		return [NSString stringWithFormat:@"%lld B", bytes];
	double kb = bytes / 1024.0;
	if (kb < 1024.0)
		return [NSString stringWithFormat:@"%.0f KB", kb];
	double mb = kb / 1024.0;
	if (mb < 1024.0)
		return [NSString stringWithFormat:@"%.1f MB", mb];
	return [NSString stringWithFormat:@"%.2f GB", mb / 1024.0];
}

static UIImage *TGMediaTilePlaceholder(void) {
	static UIImage *placeholder = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		placeholder = [UIImage imageNamed:@"FlatImagePlaceholder.png"];
		if (placeholder)
			return;
		CGSize size = CGSizeMake(TGMediaTileSide, TGMediaTileSide);
		UIGraphicsBeginImageContextWithOptions(size, YES, 0.0f);
		[TGMediaPlaceholderColour() setFill];
		UIRectFill(CGRectMake(0, 0, size.width, size.height));
		placeholder = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
	});
	return placeholder;
}

static UIImage *TGMediaMinithumbImage(NSDictionary *item) {
	NSDictionary *minithumb = item[@"minithumb"];
	if (![minithumb isKindOfClass:NSDictionary.class])
		return nil;

	NSString *key = minithumb[@"data"];
	if (![key isKindOfClass:NSString.class] || key.length == 0)
		return nil;

	static NSCache *cache = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		cache = [[NSCache alloc] init];
		cache.countLimit = 64;
		[[NSNotificationCenter defaultCenter]
				addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
							object:nil
							 queue:[NSOperationQueue mainQueue]
						usingBlock:^(NSNotification *__unused note){
			[cache removeAllObjects];
		}];
	});

	UIImage *image = [cache objectForKey:key];
	if (image)
		return image;

	NSData *bytes = [[TGClient shared] minithumbnailData:minithumb];
	if (bytes.length == 0)
		return nil;
	image = [UIImage imageWithData:bytes];
	if (!image)
		return nil;

	[cache setObject:image forKey:key];
	return image;
}

static CGFloat TGMediaFullScreenWidth(void) {
	CGSize screen = [UIScreen mainScreen].bounds.size;
	return MAX(screen.width, screen.height);
}

static NSMutableDictionary *TGMediaPhotoFields(NSDictionary *content, TGClient *client,
											   CGFloat scale) {
	NSArray *sizes = content[@"photo"][@"sizes"];
	if (![sizes isKindOfClass:NSArray.class] || sizes.count == 0)
		return nil;
	NSDictionary *small = [client bestPhotoSizeIn:sizes forWidth:TGMediaTileSide scale:scale];
	NSDictionary *large = [client bestPhotoSizeIn:sizes
										 forWidth:TGMediaFullScreenWidth() scale:scale];

	NSMutableDictionary *fields = [NSMutableDictionary dictionary];
	id thumbId = small[@"fileId"];
	if (thumbId)
		fields[@"thumbId"] = thumbId;
	id fullId = large[@"fileId"] ?: [sizes lastObject][@"photo"][@"id"];
	if (fullId)
		fields[@"fullId"] = fullId;
	fields[@"sizes"] = sizes;
	id minithumb = content[@"photo"][@"minithumbnail"];
	if (minithumb)
		fields[@"minithumb"] = minithumb;
	fields[@"fileType"] = TGFileTypePhoto;
	return fields;
}

static NSMutableDictionary *TGMediaMovingImageFields(NSDictionary *content, TGClient *client,
													 NSString *key, NSString *fileType) {
	NSDictionary *media = content[key];
	NSDictionary *thumb = [client decodableThumbnail:media[@"thumbnail"]];

	NSMutableDictionary *fields = [NSMutableDictionary dictionary];
	id thumbId = thumb[@"fileId"];
	if (thumbId)
		fields[@"thumbId"] = thumbId;
	id fullId = media[key][@"id"];
	if (fullId)
		fields[@"fullId"] = fullId;
	fields[@"duration"] = @([media[@"duration"] integerValue]);
	id minithumb = media[@"minithumbnail"];
	if (minithumb)
		fields[@"minithumb"] = minithumb;
	fields[@"fileType"] = fileType;
	fields[@"isVideo"] = @(YES);
	return fields;
}

static NSDictionary *TGMediaItemFromMessage(NSDictionary *message) {
	if (![message isKindOfClass:NSDictionary.class])
		return nil;

	NSDictionary *content = message[@"content"];
	NSString *kind = content[@"@type"];
	if (![kind isKindOfClass:NSString.class])
		return nil;

	CGFloat scale = [UIScreen mainScreen].scale;
	TGClient *client = [TGClient shared];

	NSMutableDictionary *fields = nil;
	if ([kind isEqualToString:@"messagePhoto"])
		fields = TGMediaPhotoFields(content, client, scale);
	else if ([kind isEqualToString:@"messageVideo"])
		fields = TGMediaMovingImageFields(content, client, @"video", TGFileTypeVideo);
	else if ([kind isEqualToString:@"messageAnimation"])
		fields = TGMediaMovingImageFields(content, client, @"animation", TGFileTypeAnimation);
	else
		return nil;

	if (!fields)
		return nil;

	NSNumber *thumbId = fields[@"thumbId"];
	NSNumber *fullId = fields[@"fullId"];
	NSInteger duration = [fields[@"duration"] integerValue];
	BOOL isVideo = [fields[@"isVideo"] boolValue];
	NSArray *photoSizes = fields[@"sizes"];
	NSDictionary *minithumb = fields[@"minithumb"];
	NSString *fileType = fields[@"fileType"];

	if (![thumbId isKindOfClass:NSNumber.class] && ![fullId isKindOfClass:NSNumber.class])
		return nil;

	NSString *caption = content[@"caption"][@"text"];
	if (![caption isKindOfClass:NSString.class])
		caption = @"";

	NSMutableDictionary *item = [NSMutableDictionary dictionaryWithDictionary:@{
		@"messageId" : message[@"id"] ?: @(0),
		@"thumbId"   : [thumbId isKindOfClass:NSNumber.class] ? thumbId : (fullId ?: @(0)),
		@"fullId"    : [fullId isKindOfClass:NSNumber.class] ? fullId : (thumbId ?: @(0)),
		@"duration"  : @(duration),
		@"isVideo"   : @(isVideo),
		@"caption"   : caption,
		@"fileType"  : fileType,
		@"date"      : message[@"date"] ?: @(0),
	}];
	if ([photoSizes isKindOfClass:NSArray.class])
		item[@"sizes"] = photoSizes;
	if ([minithumb isKindOfClass:NSDictionary.class])
		item[@"minithumb"] = minithumb;
	return item;
}

static NSArray *TGMediaScopeTitles(void) {
	static NSArray *titles = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		titles = @[@"Media", @"Files", @"Links", @"Music"];
	});
	return titles;
}

static NSString *TGMediaFilterForScope(NSInteger scope) {
	switch (scope){
		case TGMediaScopeFiles: return @"searchMessagesFilterDocument";
		case TGMediaScopeLinks: return @"searchMessagesFilterUrl";
		case TGMediaScopeMusic: return @"searchMessagesFilterAudio";
		default: return @"searchMessagesFilterPhotoAndVideo";
	}
}

static BOOL TGMediaScopeIsGrid(NSInteger scope) {
	return scope == TGMediaScopeMedia;
}

static NSString *TGMediaEmptyTextForScope(NSInteger scope) {
	switch (scope){
		case TGMediaScopeFiles: return @"No shared files";
		case TGMediaScopeLinks: return @"No shared links";
		case TGMediaScopeMusic: return @"No shared music";
		default: return @"No Photos in this Conversation";
	}
}

static NSString *TGMediaMonthForDate(NSInteger date) {
	if (date <= 0)
		return @"";
	static NSDateFormatter *formatter = nil;
	if (!formatter){
		formatter = [[NSDateFormatter alloc] init];
		[formatter setDateFormat:@"LLLL yyyy"];
	}
	return [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:date]];
}

static NSString *TGMediaDayForDate(NSInteger date) {
	if (date <= 0)
		return @"";
	return [NSDateFormatter localizedStringFromDate:
			[NSDate dateWithTimeIntervalSince1970:date]
										  dateStyle:NSDateFormatterMediumStyle
										  timeStyle:NSDateFormatterShortStyle];
}

static NSString *TGMediaFirstUrlInText(NSString *text, NSDictionary *content) {
	NSString *pageUrl = content[@"web_page"][@"url"];
	if ([pageUrl isKindOfClass:NSString.class] && pageUrl.length)
		return pageUrl;

	if (![text isKindOfClass:NSString.class] || text.length == 0)
		return nil;

	static NSDataDetector *detector = nil;
	if (!detector){
		detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:NULL];
	}
	NSTextCheckingResult *match = [detector firstMatchInString:text
													   options:0
														 range:NSMakeRange(0, text.length)];
	if (match && match.URL)
		return [match.URL absoluteString];
	return nil;
}

static NSMutableDictionary *TGMediaDocumentFields(NSDictionary *content) {
	NSDictionary *document = content[@"document"];
	NSString *name = document[@"file_name"];
	NSDictionary *file = document[@"document"];
	long long size = [file[@"size"] longLongValue];
	if (size <= 0)
		size = [file[@"expected_size"] longLongValue];

	NSMutableDictionary *fields = [NSMutableDictionary dictionary];
	fields[@"title"] = [name isKindOfClass:NSString.class] && name.length ? name : @"File";
	id fileId = file[@"id"];
	if (fileId)
		fields[@"fileId"] = fileId;
	fields[@"size"] = @(size);
	fields[@"detail"] = TGMediaFormatBytes(size);
	NSString *mimeType = document[@"mime_type"];
	if ([mimeType isKindOfClass:NSString.class])
		fields[@"mime"] = mimeType;
	return fields;
}

static NSMutableDictionary *TGMediaAudioFields(NSDictionary *content) {
	NSDictionary *audio = content[@"audio"];
	NSString *name = audio[@"title"];
	if (![name isKindOfClass:NSString.class] || name.length == 0)
		name = audio[@"file_name"];
	NSString *performer = audio[@"performer"];
	NSInteger duration = [audio[@"duration"] integerValue];
	NSDictionary *file = audio[@"audio"];
	long long size = [file[@"size"] longLongValue];
	if (size <= 0)
		size = [file[@"expected_size"] longLongValue];

	NSMutableDictionary *fields = [NSMutableDictionary dictionary];
	fields[@"title"] = [name isKindOfClass:NSString.class] && name.length ? name : @"Audio";
	id fileId = file[@"id"];
	if (fileId)
		fields[@"fileId"] = fileId;
	fields[@"fileType"] = TGFileTypeAudio;
	NSString *mimeType = audio[@"mime_type"];
	if ([mimeType isKindOfClass:NSString.class])
		fields[@"mime"] = mimeType;
	fields[@"size"] = @(size);
	fields[@"duration"] = @(duration);
	fields[@"detail"] = [performer isKindOfClass:NSString.class] && performer.length
			? [NSString stringWithFormat:@"%@ · %@", performer,
					TGMediaFormatDuration(duration)]
			: TGMediaFormatDuration(duration);
	return fields;
}

static NSMutableDictionary *TGMediaLinkFields(NSDictionary *content) {
	NSString *body = content[@"text"][@"text"];
	if (![body isKindOfClass:NSString.class])
		body = content[@"caption"][@"text"];
	NSString *found = TGMediaFirstUrlInText(body, content);
	if (!found.length)
		return nil;

	NSMutableDictionary *fields = [NSMutableDictionary dictionary];
	fields[@"url"] = found;
	NSString *pageTitle = content[@"web_page"][@"title"];
	fields[@"title"] = [pageTitle isKindOfClass:NSString.class] && pageTitle.length
			? pageTitle : found;
	fields[@"detail"] = found;
	return fields;
}

static NSDictionary *TGMediaListItemFromMessage(NSDictionary *message, NSInteger scope) {
	if (![message isKindOfClass:NSDictionary.class])
		return nil;

	NSDictionary *content = message[@"content"];
	NSString *kind = content[@"@type"];
	if (![kind isKindOfClass:NSString.class])
		return nil;

	NSMutableDictionary *fields = nil;
	if (scope == TGMediaScopeFiles){
		if (![kind isEqualToString:@"messageDocument"])
			return nil;
		fields = TGMediaDocumentFields(content);

	} else if (scope == TGMediaScopeMusic){
		if (![kind isEqualToString:@"messageAudio"])
			return nil;
		fields = TGMediaAudioFields(content);

	} else {
		fields = TGMediaLinkFields(content);
	}

	if (!fields)
		return nil;

	NSNumber *fileId = fields[@"fileId"];
	if (scope != TGMediaScopeLinks && ![fileId isKindOfClass:NSNumber.class])
		return nil;

	return @{
		@"messageId" : message[@"id"] ?: @(0),
		@"title"     : fields[@"title"] ?: @"",
		@"detail"    : fields[@"detail"] ?: @"",
		@"url"       : fields[@"url"] ?: @"",
		@"fileId"    : [fileId isKindOfClass:NSNumber.class] ? fileId : @(0),
		@"size"      : fields[@"size"] ?: @(0),
		@"duration"  : fields[@"duration"] ?: @(0),
		@"mime"      : fields[@"mime"] ?: @"",
		@"fileType"  : fields[@"fileType"] ?: TGFileTypeDocument,
		@"date"      : message[@"date"] ?: @(0),
		@"list"      : @(YES),
	};
}

#pragma mark - tile

@interface TGMediaTileView : TGRemoteImageView

@property (nonatomic, strong) UIView *badgeBar;
@property (nonatomic, strong) UILabel *badgeLabel;
@property (nonatomic, strong) UIImageView *playView;
@property (nonatomic, strong) UIImageView *shadowView;

- (void)showVideoBadge:(NSString *)text;
- (void)hideVideoBadge;

@end

@implementation TGMediaTileView

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self){
		self.reuseIdentifier = TGMediaTileIdentifier;
		self.clipsToBounds = YES;
		self.contentMode = UIViewContentModeScaleAspectFill;
		self.userInteractionEnabled = NO;
		self.fadeTransition = true;
		self.backgroundColor = TGMediaPlaceholderColour();

		UIImage *shadow = [UIImage imageNamed:@"MediaGridImageShadow.png"];
		if (shadow){
			_shadowView = [[UIImageView alloc] initWithImage:
					[shadow stretchableImageWithLeftCapWidth:(int)(shadow.size.width / 2)
												topCapHeight:(int)(shadow.size.height / 2)]];
			_shadowView.frame = CGRectMake(0, 0, TGMediaTileSide, TGMediaTileSide);
			_shadowView.userInteractionEnabled = NO;
			[self addSubview:_shadowView];
		}
	}
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	if (_shadowView)
		_shadowView.frame = self.bounds;
}

- (void)buildBadge {
	if (_badgeBar)
		return;

	_badgeBar = [[UIView alloc] initWithFrame:CGRectMake(0, TGMediaTileSide - 19,
														 TGMediaTileSide, 19)];
	_badgeBar.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.6f];
	_badgeBar.userInteractionEnabled = NO;

	UIImage *play = [UIImage imageNamed:@"MessageInlineVideoIcon.png"];
	if (play){
		_playView = [[UIImageView alloc] initWithImage:play];
		_playView.frame = CGRectOffset(_playView.frame, 4, 5);
	} else {
		play = [TGIcons play];
		_playView = [[UIImageView alloc] initWithImage:play];
		_playView.frame = CGRectMake(4, (int)((19 - MIN(11.0f, play.size.height)) / 2),
									 MIN(11.0f, play.size.width), MIN(11.0f, play.size.height));
		_playView.contentMode = UIViewContentModeScaleAspectFit;
	}
	[_badgeBar addSubview:_playView];

	_badgeLabel = [[UILabel alloc] initWithFrame:CGRectMake(TGMediaTileSide - 56 - 3, 0, 56, 19)];
	_badgeLabel.backgroundColor = [UIColor clearColor];
	_badgeLabel.textColor = [UIColor whiteColor];
	_badgeLabel.font = [UIFont boldSystemFontOfSize:10];
	_badgeLabel.textAlignment = NSTextAlignmentRight;
	[_badgeBar addSubview:_badgeLabel];

	[self addSubview:_badgeBar];
}

- (void)showVideoBadge:(NSString *)text {
	[self buildBadge];
	_badgeLabel.text = text;
	_badgeBar.hidden = NO;
	_badgeBar.frame = CGRectMake(0, self.bounds.size.height - 19, self.bounds.size.width, 19);
	_badgeLabel.frame = CGRectMake(self.bounds.size.width - 56 - 3, 0, 56, 19);
}

- (void)hideVideoBadge {
	_badgeBar.hidden = YES;
}

- (void)prepareForReuse {
	[super prepareForReuse];
	[self hideVideoBadge];
	self.image = TGMediaTilePlaceholder();
}

- (void)prepareForRecycle:(TGViewRecycler *)recycler {
	[super prepareForRecycle:recycler];
	[self hideVideoBadge];
	self.image = nil;
	self.fileId = nil;
}

@end

#pragma mark - grid row

@class TGMediaGridCell;

@protocol TGMediaGridCellDelegate <NSObject>
- (void)gridCell:(TGMediaGridCell *)cell tappedItemAtIndex:(NSInteger)index;
@end

@interface TGMediaGridCell : UITableViewCell

@property (nonatomic, weak) TGViewRecycler *recycler;
@property (nonatomic, weak) id<TGMediaGridCellDelegate> gridDelegate;
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, assign) NSInteger baseIndex;
@property (nonatomic, strong) NSMutableArray *tiles;

- (void)configureWithItems:(NSArray *)items baseIndex:(NSInteger)baseIndex;
- (void)releaseTiles;

@end

@implementation TGMediaGridCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self){
		self.selectionStyle = UITableViewCellSelectionStyleNone;
		self.backgroundColor = [UIColor clearColor];
		self.contentView.backgroundColor = [UIColor clearColor];
		_tiles = [[NSMutableArray alloc] init];

		UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
				initWithTarget:self action:@selector(handleTap:)];
		[self.contentView addGestureRecognizer:tap];
	}
	return self;
}

- (TGMediaTileView *)takeTile {
	TGMediaTileView *tile = nil;
	TGViewRecycler *recycler = self.recycler;
	if (recycler){
		UIView<TGReusableView> *view = [recycler dequeueReusableViewWithIdentifier:TGMediaTileIdentifier];
		if ([view isKindOfClass:[TGMediaTileView class]])
			tile = (TGMediaTileView *)view;
	}
	if (!tile){
		tile = [[TGMediaTileView alloc] initWithFrame:CGRectZero];
		tile.image = TGMediaTilePlaceholder();
	}
	return tile;
}

- (void)releaseTiles {
	TGViewRecycler *recycler = self.recycler;
	for (TGMediaTileView *tile in _tiles){
		if (recycler)
			[recycler recycleView:tile];
		else {
			[tile cancelLoading];
			[tile removeFromSuperview];
		}
	}
	[_tiles removeAllObjects];
	self.items = nil;
}

- (void)prepareForReuse {
	[super prepareForReuse];
	[self releaseTiles];
}

- (void)configureWithItems:(NSArray *)items baseIndex:(NSInteger)baseIndex {
	self.baseIndex = baseIndex;
	self.items = items;

	while (_tiles.count > items.count){
		TGMediaTileView *tile = [_tiles lastObject];
		[_tiles removeLastObject];
		TGViewRecycler *recycler = self.recycler;
		if (recycler)
			[recycler recycleView:tile];
		else {
			[tile cancelLoading];
			[tile removeFromSuperview];
		}
	}

	while (_tiles.count < items.count){
		TGMediaTileView *tile = [self takeTile];
		[self.contentView addSubview:tile];
		[_tiles addObject:tile];
	}

	for (NSInteger i = 0; i < (NSInteger)items.count; i++){
		TGMediaTileView *tile = _tiles[i];
		NSDictionary *item = items[i];

		if (tile.superview != self.contentView)
			[self.contentView addSubview:tile];

		NSNumber *thumbId = item[@"thumbId"];
		if (![thumbId isKindOfClass:NSNumber.class])
			thumbId = nil;

		UIImage *instant = TGMediaMinithumbImage(item);
		[tile loadWithFileId:thumbId
					  square:TGMediaTileSide
				 placeholder:instant ?: TGMediaTilePlaceholder()
				   forceFade:false];

		if ([item[@"isVideo"] boolValue])
			[tile showVideoBadge:TGMediaFormatDuration([item[@"duration"] integerValue])];
		else
			[tile hideVideoBadge];
	}

	[self setNeedsLayout];
}

- (void)layoutSubviews {
	[super layoutSubviews];

	NSInteger count = (NSInteger)_tiles.count;
	if (count == 0)
		return;

	CGFloat width = self.contentView.bounds.size.width;
	NSInteger perRow = (NSInteger)(width / (TGMediaTileSide + TGMediaTileSpacing));
	if (perRow < 1)
		perRow = 1;
	CGFloat used = perRow * TGMediaTileSide + (perRow - 1) * TGMediaTileSpacing;
	CGFloat x = (CGFloat)(int)((width - used) / 2.0f);

	for (NSInteger i = 0; i < count; i++){
		TGMediaTileView *tile = _tiles[i];
		tile.frame = CGRectMake(x, TGMediaTileSpacing, TGMediaTileSide, TGMediaTileSide);
		if (tile.badgeBar && !tile.badgeBar.hidden)
			tile.badgeBar.frame = CGRectMake(0, TGMediaTileSide - 19, TGMediaTileSide, 19);
		x += TGMediaTileSide + TGMediaTileSpacing;
	}
}

- (void)handleTap:(UITapGestureRecognizer *)recognizer {
	if (recognizer.state != UIGestureRecognizerStateRecognized)
		return;

	CGPoint point = [recognizer locationInView:self.contentView];
	for (NSInteger i = 0; i < (NSInteger)_tiles.count; i++){
		TGMediaTileView *tile = _tiles[i];
		if (CGRectContainsPoint(CGRectInset(tile.frame, -2, -2), point)){
			[self.gridDelegate gridCell:self tappedItemAtIndex:self.baseIndex + i];
			return;
		}
	}
}

@end

#pragma mark - fullscreen page

@interface TGMediaPageView : UIScrollView <UIScrollViewDelegate>

@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, assign) NSInteger pageIndex;
@property (nonatomic, strong) NSNumber *loadingFileId;
@property (nonatomic, assign) BOOL showingMinithumb;
@property (nonatomic, assign) CGSize imageSize;

- (void)setPageImage:(UIImage *)image;
- (void)setPageImage:(UIImage *)image crossfade:(BOOL)crossfade;
- (void)resetZoom;
- (void)layoutImage;
- (BOOL)isZoomed;
- (BOOL)canZoom;
- (void)centerContents;

@end

@implementation TGMediaPageView

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self){
		self.backgroundColor = [UIColor clearColor];
		self.showsHorizontalScrollIndicator = NO;
		self.showsVerticalScrollIndicator = NO;
		self.scrollsToTop = NO;
		self.bouncesZoom = YES;
		self.bounces = YES;
		self.alwaysBounceHorizontal = NO;
		self.alwaysBounceVertical = NO;
		self.decelerationRate = UIScrollViewDecelerationRateFast;
		self.minimumZoomScale = 1.0f;
		self.maximumZoomScale = 1.0f;
		self.delegate = self;
		self.pageIndex = -1;
		_imageSize = CGSizeZero;

		_imageView = [[UIImageView alloc] initWithFrame:self.bounds];
		_imageView.contentMode = UIViewContentModeScaleToFill;
		[self addSubview:_imageView];
	}
	return self;
}

- (void)setPageImage:(UIImage *)image {
	_imageView.image = image;
	_imageSize = image ? image.size : CGSizeZero;
	_showingMinithumb = NO;
	[self resetZoom];
}

- (void)setPageImage:(UIImage *)image crossfade:(BOOL)crossfade {
	if (!crossfade || !image || !_imageView.image){
		[self setPageImage:image];
		return;
	}

	UIImageView *view = _imageView;
	[UIView transitionWithView:view
					  duration:0.15
					   options:UIViewAnimationOptionTransitionCrossDissolve
					animations:^{ view.image = image; }
					completion:nil];
	_imageSize = image.size;
	_showingMinithumb = NO;
	[self resetZoom];
}

- (void)resetZoom {
	[self layoutImage];
}

- (void)updateZoomLimits {
	CGSize bounds = self.bounds.size;
	if (_imageSize.width < 1.0f || _imageSize.height < 1.0f ||
		bounds.width < 1.0f || bounds.height < 1.0f){
		self.minimumZoomScale = 1.0f;
		self.maximumZoomScale = 1.0f;
		return;
	}

	CGFloat scaleWidth = bounds.width / _imageSize.width;
	CGFloat scaleHeight = bounds.height / _imageSize.height;
	CGFloat minScale = MIN(scaleWidth, scaleHeight);
	CGFloat maxScale = MAX(MAX(scaleWidth, scaleHeight), minScale * 3.0f);
	if (fabs(maxScale - minScale) < 0.01f)
		maxScale = minScale;

	self.minimumZoomScale = minScale;
	self.maximumZoomScale = maxScale;
}

- (void)layoutImage {
	CGSize bounds = self.bounds.size;

	if (_imageSize.width < 1.0f || _imageSize.height < 1.0f){
		self.minimumZoomScale = 1.0f;
		self.maximumZoomScale = 1.0f;
		self.zoomScale = 1.0f;
		self.contentSize = bounds;
		self.scrollEnabled = NO;
		_imageView.frame = CGRectMake(0, 0, bounds.width, bounds.height);
		return;
	}

	self.minimumZoomScale = 1.0f;
	self.maximumZoomScale = 1.0f;
	self.zoomScale = 1.0f;
	_imageView.frame = CGRectMake(0, 0, _imageSize.width, _imageSize.height);
	self.contentSize = _imageSize;

	[self updateZoomLimits];
	self.zoomScale = self.minimumZoomScale;
	self.scrollEnabled = NO;

	[self centerContents];

	CGSize contentSize = self.contentSize;
	self.contentOffset = CGPointMake(
			MAX(0.0f, floorf((contentSize.width - bounds.width) / 2.0f)),
			MAX(0.0f, floorf((contentSize.height - bounds.height) / 2.0f)));
}

- (void)centerContents {
	CGSize bounds = self.bounds.size;
	CGRect frame = _imageView.frame;

	frame.origin.x = bounds.width > frame.size.width
			? floorf((bounds.width - frame.size.width) / 2.0f) : 0.0f;
	frame.origin.y = bounds.height > frame.size.height
			? floorf((bounds.height - frame.size.height) / 2.0f) : 0.0f;

	_imageView.frame = frame;
}

- (BOOL)isZoomed {
	return self.zoomScale > self.minimumZoomScale + 0.0001f;
}

- (BOOL)canZoom {
	return self.maximumZoomScale > self.minimumZoomScale + 0.0001f;
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
	return _imageView;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
	[self centerContents];
	self.scrollEnabled = [self isZoomed];
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView
					   withView:(UIView *)view
						atScale:(float)scale {
	[self centerContents];
	self.scrollEnabled = [self isZoomed];
}

@end

#pragma mark - radial download status

@interface TGMediaProgressRing : UIView
@property (nonatomic, assign) CGFloat progress;
@end

@implementation TGMediaProgressRing

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self){
		self.backgroundColor = [UIColor clearColor];
		self.opaque = NO;
		self.userInteractionEnabled = NO;
		_progress = 0.0f;
	}
	return self;
}

- (void)setProgress:(CGFloat)progress {
	CGFloat clamped = MAX(0.0f, MIN(1.0f, progress));
	if (fabs(clamped - _progress) < 0.005f)
		return;
	_progress = clamped;
	[self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGRect box = self.bounds;

	CGContextSetRGBFillColor(ctx, 0.0f, 0.0f, 0.0f, 0.5f);
	CGContextFillEllipseInRect(ctx, box);

	CGFloat lineWidth = 2.0f;
	CGRect ring = CGRectInset(box, 8.0f + lineWidth / 2.0f, 8.0f + lineWidth / 2.0f);
	CGPoint centre = CGPointMake(CGRectGetMidX(ring), CGRectGetMidY(ring));
	CGFloat radius = ring.size.width / 2.0f;

	CGContextSetLineWidth(ctx, lineWidth);
	CGContextSetLineCap(ctx, kCGLineCapRound);

	CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 0.25f);
	CGContextAddArc(ctx, centre.x, centre.y, radius, 0.0f, (CGFloat)(2.0 * M_PI), 0);
	CGContextStrokePath(ctx);

	if (_progress <= 0.001f)
		return;

	CGFloat start = (CGFloat)(-M_PI / 2.0);
	CGContextSetRGBStrokeColor(ctx, 1.0f, 1.0f, 1.0f, 1.0f);
	CGContextAddArc(ctx, centre.x, centre.y, radius, start,
					start + (CGFloat)(2.0 * M_PI) * _progress, 0);
	CGContextStrokePath(ctx);
}

@end

#pragma mark - fullscreen viewer

@interface TGMediaFullscreenController ()
		<UIScrollViewDelegate, UIGestureRecognizerDelegate, UIActionSheetDelegate>

@property (nonatomic, strong) NSMutableArray *items;
@property (nonatomic, assign) NSInteger startIndex;
@property (nonatomic, assign) NSInteger currentIndex;

@property (nonatomic, strong) UIScrollView *pagingView;
@property (nonatomic, strong) UIPanGestureRecognizer *dismissPan;
@property (nonatomic, assign) CGSize validSize;
@property (nonatomic, strong) NSMutableDictionary *visiblePages;
@property (nonatomic, strong) NSMutableArray *pagePool;
@property (nonatomic, strong) NSMutableDictionary *imageCache;

@property (nonatomic, strong) UIImageView *topBar;
@property (nonatomic, strong) UIImageView *topCorners;
@property (nonatomic, strong) UILabel *counterLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIImageView *bottomBar;
@property (nonatomic, strong) UIView *controlsContainer;
@property (nonatomic, strong) UIView *progressContainer;
@property (nonatomic, strong) UILabel *progressLabel;
@property (nonatomic, strong) UIActivityIndicatorView *progressSpinner;
@property (nonatomic, strong) UILabel *authorLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSMutableSet *failedPages;
@property (nonatomic, strong) NSMutableSet *prefetchedFiles;
@property (nonatomic, strong) NSArray *sheetActions;

@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UIView *captionPanel;
@property (nonatomic, strong) TGMediaProgressRing *progressRing;
@property (nonatomic, strong) NSNumber *ringFileId;
@property (nonatomic, copy) void (^savedProgressBlock)(NSInteger, float);
@property (nonatomic, assign) BOOL progressHooked;

@property (nonatomic, assign) BOOL chromeHidden;
@property (nonatomic, assign) BOOL dismissing;
@property (nonatomic, assign) BOOL statusBarWasHidden;

@end

@implementation TGMediaFullscreenController

- (instancetype)initWithItems:(NSArray *)items index:(NSInteger)index {
	self = [super init];
	if (self){
		_items = [NSMutableArray arrayWithArray:items ?: @[]];
		_startIndex = index;
		_currentIndex = index;
		_visiblePages = [[NSMutableDictionary alloc] init];
		_pagePool = [[NSMutableArray alloc] init];
		_imageCache = [[NSMutableDictionary alloc] init];
		_failedPages = [[NSMutableSet alloc] init];
		_prefetchedFiles = [[NSMutableSet alloc] init];
		self.modalPresentationStyle = UIModalPresentationFullScreen;
		self.wantsFullScreenLayout = YES;
	}
	return self;
}

- (void)loadView {
	[super loadView];
	self.view.backgroundColor = [UIColor blackColor];
	self.view.clipsToBounds = YES;

	[self buildPagingView];
	[self buildTopBar];
	[self buildBottomBar];
	[self buildCaptionPanel];
	[self buildOverlayAndGestures];
}

- (void)buildCaptionPanel {
	CGRect bounds = self.view.bounds;

	_captionPanel = [[UIView alloc] initWithFrame:
			CGRectMake(0, _bottomBar.frame.origin.y, bounds.size.width, 0)];
	_captionPanel.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.65f];
	_captionPanel.userInteractionEnabled = NO;
	_captionPanel.hidden = YES;
	_captionPanel.autoresizingMask = UIViewAutoresizingFlexibleWidth
			| UIViewAutoresizingFlexibleTopMargin;
	[self.view insertSubview:_captionPanel belowSubview:_bottomBar];

	_captionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_captionLabel.backgroundColor = [UIColor clearColor];
	_captionLabel.textColor = [UIColor whiteColor];
	_captionLabel.font = [UIFont systemFontOfSize:14];
	_captionLabel.numberOfLines = 3;
	_captionLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	_captionLabel.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.5f];
	_captionLabel.shadowOffset = CGSizeMake(0, -1);
	_captionLabel.textAlignment = NSTextAlignmentLeft;
	_captionLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[_captionPanel addSubview:_captionLabel];
}

- (void)layoutCaptionPanel {
	NSString *text = _captionLabel.text;
	if (text.length == 0){
		_captionPanel.hidden = YES;
		return;
	}

	CGFloat width = self.view.bounds.size.width;
	CGFloat inset = 10.0f;
	CGSize wanted = [text sizeWithFont:_captionLabel.font
					 constrainedToSize:CGSizeMake(width - inset * 2, 3 * 18.0f)
						 lineBreakMode:_captionLabel.lineBreakMode];
	CGFloat height = (CGFloat)(int)(wanted.height + 12.0f);

	_captionPanel.hidden = NO;
	_captionPanel.frame = CGRectMake(0, _bottomBar.frame.origin.y - height, width, height);
	_captionLabel.frame = CGRectMake(inset, 6.0f, width - inset * 2, height - 12.0f);
}

- (void)buildPagingView {
	CGRect bounds = self.view.bounds;

	_pagingView = [[UIScrollView alloc] initWithFrame:
			CGRectMake(-TGMediaPageGap / 2.0f, 0,
					   bounds.size.width + TGMediaPageGap, bounds.size.height)];
	_pagingView.pagingEnabled = YES;
	_pagingView.alwaysBounceHorizontal = YES;
	_pagingView.alwaysBounceVertical = NO;
	_pagingView.showsHorizontalScrollIndicator = NO;
	_pagingView.showsVerticalScrollIndicator = NO;
	_pagingView.scrollsToTop = NO;
	_pagingView.delaysContentTouches = NO;
	_pagingView.backgroundColor = [UIColor clearColor];
	_pagingView.delegate = self;
	[self.view addSubview:_pagingView];
}

- (void)buildTopBar {
	CGRect bounds = self.view.bounds;

	UIImage *topPanelImage = [UIImage imageNamed:@"GalleryTopPanel.png"];
	CGFloat inset = TGMediaStatusBarInset();
	_topBar = [[UIImageView alloc] initWithFrame:
			CGRectMake(0, inset, bounds.size.width, TGMediaTopBarHeight())];
	if (topPanelImage)
		_topBar.image = topPanelImage;
	else
		_topBar.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.6f];
	_topBar.userInteractionEnabled = YES;
	_topBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.view addSubview:_topBar];

	UIImage *cornersImage = [UIImage imageNamed:@"NavigationBar_Corners.png"];
	if (cornersImage){
		_topCorners = [[UIImageView alloc] initWithImage:
				[cornersImage stretchableImageWithLeftCapWidth:(int)(cornersImage.size.width / 2)
												  topCapHeight:0]];
		_topCorners.frame = CGRectMake(0, -inset, bounds.size.width, cornersImage.size.height);
		_topCorners.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[_topBar addSubview:_topCorners];
	}

	[self buildCloseButton];

	_counterLabel = [[UILabel alloc] initWithFrame:
			CGRectMake((CGFloat)(int)((bounds.size.width - 140) / 2), 11, 140, 20)];
	_counterLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin;
	_counterLabel.backgroundColor = [UIColor clearColor];
	_counterLabel.textColor = [UIColor whiteColor];
	_counterLabel.font = [UIFont boldSystemFontOfSize:20];
	_counterLabel.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.5f];
	_counterLabel.shadowOffset = CGSizeMake(0, -1);
	_counterLabel.textAlignment = NSTextAlignmentCenter;
	[_topBar addSubview:_counterLabel];
}

- (void)buildCloseButton {
	UIImage *closePlate = [UIImage imageNamed:@"GalleryDoneButton.png"];
	UIImage *closePlateHighlighted = [UIImage imageNamed:@"GalleryDoneButton_Highlighted.png"];
	UIButton *done = [UIButton buttonWithType:UIButtonTypeCustom];
	done.titleLabel.font = [UIFont boldSystemFontOfSize:12];
	[done setTitle:@"Close" forState:UIControlStateNormal];
	[done setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	[done setTitleShadowColor:[UIColor colorWithWhite:0.0f alpha:0.5f]
					 forState:UIControlStateNormal];
	done.titleLabel.shadowOffset = CGSizeMake(0, -1);
	if (closePlate){
		[done setBackgroundImage:[closePlate stretchableImageWithLeftCapWidth:11 topCapHeight:0]
						forState:UIControlStateNormal];
		if (closePlateHighlighted)
			[done setBackgroundImage:[closePlateHighlighted
					stretchableImageWithLeftCapWidth:11 topCapHeight:0]
							forState:UIControlStateHighlighted];
	}
	CGSize closeTitleSize = [@"Close" sizeWithFont:done.titleLabel.font];
	CGFloat closeWidth = closeTitleSize.width + 7.0f + 7.0f;
	if (closeWidth < 55.0f)
		closeWidth = 55.0f;
	done.frame = CGRectMake(5, 7, closeWidth, 30);
	[done addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
	[_topBar addSubview:done];
}

- (void)buildBottomBar {
	CGRect bounds = self.view.bounds;

	UIImage *bottomPanelImage = [UIImage imageNamed:@"GalleryBottomPanel.png"];
	CGFloat bottomPanelHeight = bottomPanelImage ? bottomPanelImage.size.height : 44.0f;
	_bottomBar = [[UIImageView alloc] initWithFrame:
			CGRectMake(0, bounds.size.height - bottomPanelHeight,
					   bounds.size.width, bottomPanelHeight)];
	if (bottomPanelImage)
		_bottomBar.image = [bottomPanelImage
				stretchableImageWithLeftCapWidth:(int)(bottomPanelImage.size.width / 2)
									topCapHeight:0];
	else
		_bottomBar.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.6f];
	_bottomBar.userInteractionEnabled = YES;
	_bottomBar.autoresizingMask = UIViewAutoresizingFlexibleWidth
			| UIViewAutoresizingFlexibleTopMargin;
	[self.view addSubview:_bottomBar];

	_controlsContainer = [[UIView alloc] initWithFrame:_bottomBar.bounds];
	_controlsContainer.backgroundColor = [UIColor clearColor];
	_controlsContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth
			| UIViewAutoresizingFlexibleHeight;
	[_bottomBar addSubview:_controlsContainer];

	_authorLabel = [[UILabel alloc] initWithFrame:
			CGRectMake((CGFloat)(int)((bounds.size.width - 220) / 2), 4, 220, 20)];
	_authorLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin;
	_authorLabel.backgroundColor = [UIColor clearColor];
	_authorLabel.textColor = [UIColor whiteColor];
	_authorLabel.font = [UIFont boldSystemFontOfSize:14];
	_authorLabel.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.5f];
	_authorLabel.shadowOffset = CGSizeMake(0, -1);
	_authorLabel.textAlignment = NSTextAlignmentCenter;
	[_controlsContainer addSubview:_authorLabel];

	_dateLabel = [[UILabel alloc] initWithFrame:
			CGRectMake((CGFloat)(int)((bounds.size.width - 140) / 2), 23, 140, 20)];
	_dateLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin;
	_dateLabel.backgroundColor = [UIColor clearColor];
	_dateLabel.textColor = [UIColor whiteColor];
	_dateLabel.font = [UIFont systemFontOfSize:13];
	_dateLabel.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.5f];
	_dateLabel.shadowOffset = CGSizeMake(0, -1);
	_dateLabel.textAlignment = NSTextAlignmentCenter;
	[_controlsContainer addSubview:_dateLabel];

	[self buildPlaybackControlsWithPanelHeight:bottomPanelHeight];
	[self buildBottomBarButtons];
}

- (void)buildPlaybackControlsWithPanelHeight:(CGFloat)bottomPanelHeight {
	CGRect bounds = self.view.bounds;

	UIImage *playImage = [UIImage imageNamed:@"VideoPanelPlay.png"];
	_playButton = [UIButton buttonWithType:UIButtonTypeCustom];
	if (playImage){
		_playButton.frame = CGRectMake(
				(CGFloat)(int)((bounds.size.width - playImage.size.width) / 2),
				(CGFloat)(int)((bottomPanelHeight - playImage.size.height) / 2),
				playImage.size.width, playImage.size.height);
		[_playButton setBackgroundImage:playImage forState:UIControlStateNormal];
	} else {
		_playButton.frame = CGRectMake((CGFloat)(int)((bounds.size.width - 60) / 2),
									   (CGFloat)(int)((bottomPanelHeight - 30) / 2), 60, 30);
		_playButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
		[_playButton setTitle:@"Play" forState:UIControlStateNormal];
		[_playButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	}
	_playButton.showsTouchWhenHighlighted = YES;
	_playButton.exclusiveTouch = YES;
	_playButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin;
	[_playButton addTarget:self action:@selector(playTapped)
		  forControlEvents:UIControlEventTouchUpInside];
	[_controlsContainer addSubview:_playButton];

	_progressContainer = [[UIView alloc] initWithFrame:_bottomBar.bounds];
	_progressContainer.backgroundColor = [UIColor clearColor];
	_progressContainer.userInteractionEnabled = NO;
	_progressContainer.alpha = 0.0f;
	_progressContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth
			| UIViewAutoresizingFlexibleHeight;
	[_bottomBar addSubview:_progressContainer];

	_progressLabel = [[UILabel alloc] initWithFrame:
			CGRectMake((CGFloat)(int)((bounds.size.width - 220) / 2), 14, 220, 20)];
	_progressLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin;
	_progressLabel.backgroundColor = [UIColor clearColor];
	_progressLabel.textColor = [UIColor whiteColor];
	_progressLabel.font = [UIFont systemFontOfSize:13];
	_progressLabel.shadowColor = [UIColor colorWithWhite:0.0f alpha:0.5f];
	_progressLabel.shadowOffset = CGSizeMake(0, -1);
	_progressLabel.textAlignment = NSTextAlignmentCenter;
	_progressLabel.clipsToBounds = NO;
	[_progressContainer addSubview:_progressLabel];

	_progressSpinner = [[UIActivityIndicatorView alloc]
			initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
	_progressSpinner.hidesWhenStopped = YES;
	[_progressContainer addSubview:_progressSpinner];
}

- (void)buildBottomBarButtons {
	CGRect bounds = self.view.bounds;

	UIImage *actionIcon = [UIImage imageNamed:@"GalleryActionIcon.png"];
	_actionButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_actionButton.frame = CGRectMake(6, 2, 40, 40);
	_actionButton.exclusiveTouch = YES;
	_actionButton.showsTouchWhenHighlighted = YES;
	if (actionIcon)
		[_actionButton setBackgroundImage:actionIcon forState:UIControlStateNormal];
	else {
		_actionButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
		[_actionButton setTitle:@"…" forState:UIControlStateNormal];
		[_actionButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	}
	_actionButton.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
	[_actionButton addTarget:self action:@selector(actionsTapped)
			forControlEvents:UIControlEventTouchUpInside];
	[_bottomBar addSubview:_actionButton];

	UIImage *trashIcon = [UIImage imageNamed:@"GalleryTrashIcon.png"];
	_deleteButton = [UIButton buttonWithType:UIButtonTypeCustom];
	_deleteButton.frame = CGRectMake(bounds.size.width - 40 - 6, 2, 40, 40);
	_deleteButton.exclusiveTouch = YES;
	_deleteButton.showsTouchWhenHighlighted = YES;
	if (trashIcon)
		[_deleteButton setBackgroundImage:trashIcon forState:UIControlStateNormal];
	else {
		_deleteButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
		[_deleteButton setTitle:@"Delete" forState:UIControlStateNormal];
		[_deleteButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	}
	_deleteButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[_deleteButton addTarget:self action:@selector(deleteTapped)
			forControlEvents:UIControlEventTouchUpInside];
	[_bottomBar addSubview:_deleteButton];
}

- (void)buildOverlayAndGestures {
	CGRect bounds = self.view.bounds;

	_spinner = [[UIActivityIndicatorView alloc]
			initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
	_spinner.center = CGPointMake(bounds.size.width / 2, bounds.size.height / 2);
	_spinner.hidesWhenStopped = YES;
	_spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin
			| UIViewAutoresizingFlexibleTopMargin
			| UIViewAutoresizingFlexibleBottomMargin;
	[self.view addSubview:_spinner];

	_progressRing = [[TGMediaProgressRing alloc] initWithFrame:CGRectMake(0, 0, 50, 50)];
	_progressRing.center = CGPointMake(bounds.size.width / 2, bounds.size.height / 2);
	_progressRing.hidden = YES;
	_progressRing.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin
			| UIViewAutoresizingFlexibleTopMargin
			| UIViewAutoresizingFlexibleBottomMargin;
	[self.view insertSubview:_progressRing belowSubview:_topBar];

	UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(handleDoubleTap:)];
	doubleTap.numberOfTapsRequired = 2;
	[self.view addGestureRecognizer:doubleTap];

	UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc]
			initWithTarget:self action:@selector(handleSingleTap:)];
	[singleTap requireGestureRecognizerToFail:doubleTap];
	[self.view addGestureRecognizer:singleTap];

	UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
			initWithTarget:self action:@selector(handlePan:)];
	pan.delegate = self;
	pan.maximumNumberOfTouches = 1;
	[self.view addGestureRecognizer:pan];
	_dismissPan = pan;
	[_pagingView.panGestureRecognizer requireGestureRecognizerToFail:pan];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[self layoutPagesPreservingIndex:_startIndex];
	[self updateChromeForCurrentItem];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	_statusBarWasHidden = [UIApplication sharedApplication].statusBarHidden;
	if (_statusBarWasHidden)
		[[UIApplication sharedApplication] setStatusBarHidden:NO
												withAnimation:UIStatusBarAnimationFade];
	[self installProgressHook];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[[UIApplication sharedApplication] setStatusBarHidden:_statusBarWasHidden
											withAnimation:UIStatusBarAnimationFade];
	[self removeProgressHook];
}

- (void)installProgressHook {
	if (_progressHooked)
		return;

	TGClient *client = [TGClient shared];
	void (^previous)(NSInteger, float) = client.onFileProgress;
	_savedProgressBlock = previous;
	_progressHooked = YES;

	__weak typeof(self) weakSelf = self;
	client.onFileProgress = ^(NSInteger fileId, float progress){
		if (previous)
			previous(fileId, progress);
		typeof(self) me = weakSelf;
		if (!me || ![me.ringFileId isEqual:@(fileId)])
			return;
		me.progressRing.progress = progress;
	};
}

- (void)removeProgressHook {
	if (!_progressHooked)
		return;
	[TGClient shared].onFileProgress = _savedProgressBlock;
	_savedProgressBlock = nil;
	_progressHooked = NO;
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self layoutTopBar];
	[self layoutPagesPreservingIndex:_currentIndex];
	[self layoutCaptionPanel];
}

- (void)layoutTopBar {
	CGRect bounds = self.view.bounds;
	if (bounds.size.width < 1)
		return;

	CGFloat inset = TGMediaStatusBarInset();
	_topBar.frame = CGRectMake(0, inset, bounds.size.width, TGMediaTopBarHeight());
	if (_topCorners)
		_topCorners.frame = CGRectMake(0, -inset, bounds.size.width,
									   _topCorners.image.size.height);
}

- (BOOL)shouldAutorotate {
	return YES;
}

- (NSUInteger)supportedInterfaceOrientations {
	return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
	return orientation != UIInterfaceOrientationPortraitUpsideDown;
}

#pragma mark - paging

- (CGFloat)pageWidth {
	return self.view.bounds.size.width + TGMediaPageGap;
}

- (void)layoutPagesPreservingIndex:(NSInteger)index {
	CGRect bounds = self.view.bounds;
	if (bounds.size.width < 1 || _dismissing)
		return;

	BOOL sizeChanged = !CGSizeEqualToSize(bounds.size, _validSize);
	_validSize = bounds.size;

	_pagingView.frame = CGRectMake(-TGMediaPageGap / 2.0f, 0,
								   bounds.size.width + TGMediaPageGap, bounds.size.height);
	_pagingView.contentSize = CGSizeMake([self pageWidth] * _items.count, bounds.size.height);

	if (sizeChanged){
		for (NSNumber *key in _visiblePages.allKeys){
			TGMediaPageView *page = _visiblePages[key];
			page.frame = [self frameForPageAtIndex:[key integerValue]];
			[page layoutImage];
		}

		CGFloat wanted = index * [self pageWidth];
		if (!_pagingView.isDragging && !_pagingView.isDecelerating &&
			fabs(_pagingView.contentOffset.x - wanted) > 0.5f)
			_pagingView.contentOffset = CGPointMake(wanted, 0);
	}

	[self updateVisiblePages];
}

- (CGRect)frameForPageAtIndex:(NSInteger)index {
	CGRect bounds = self.view.bounds;
	return CGRectMake(index * [self pageWidth] + TGMediaPageGap / 2.0f, 0,
					  bounds.size.width, bounds.size.height);
}

- (TGMediaPageView *)takePage {
	TGMediaPageView *page = [_pagePool lastObject];
	if (page){
		[_pagePool removeLastObject];
		return page;
	}
	page = [[TGMediaPageView alloc] initWithFrame:self.view.bounds];
	if (_dismissPan)
		[page.panGestureRecognizer requireGestureRecognizerToFail:_dismissPan];
	return page;
}

- (void)recyclePage:(TGMediaPageView *)page forKey:(NSNumber *)key {
	[page setPageImage:nil];
	page.loadingFileId = nil;
	page.pageIndex = -1;
	[page removeFromSuperview];
	[_visiblePages removeObjectForKey:key];
	if (_pagePool.count < 3)
		[_pagePool addObject:page];
}

- (void)trimImageCache {
	for (NSNumber *key in _imageCache.allKeys){
		if (labs((long)([key integerValue] - _currentIndex)) > 3)
			[_imageCache removeObjectForKey:key];
	}
}

- (void)updateVisiblePages {
	if (_items.count == 0)
		return;

	NSInteger first = _currentIndex - 1;
	NSInteger last = _currentIndex + 1;
	if (first < 0)
		first = 0;
	if (last > (NSInteger)_items.count - 1)
		last = (NSInteger)_items.count - 1;

	for (NSNumber *key in _visiblePages.allKeys){
		NSInteger index = [key integerValue];
		if (index < first || index > last){
			[self recyclePage:_visiblePages[key] forKey:key];
			[_failedPages removeObject:key];
		}
	}

	[self trimImageCache];
	[self cancelDownloadsOutsideWindow];

	for (NSInteger index = first; index <= last; index++){
		NSNumber *key = @(index);
		TGMediaPageView *page = _visiblePages[key];
		if (page){
			if (index != _currentIndex && [page isZoomed])
				[page resetZoom];
			continue;
		}

		page = [self takePage];
		page.pageIndex = index;
		page.frame = [self frameForPageAtIndex:index];
		[_pagingView addSubview:page];
		_visiblePages[key] = page;

		UIImage *cached = _imageCache[key];
		if (cached){
			[page setPageImage:cached];
			[self prefetchNeighboursOfIndex:index];
		} else {
			[page resetZoom];
			[self loadImageForPageAtIndex:index];
		}
	}
}

- (void)showMinithumbOnPage:(TGMediaPageView *)page forItem:(NSDictionary *)item {
	if (page.imageView.image)
		return;
	NSData *tiny = [[TGClient shared] minithumbnailData:item[@"minithumb"]];
	if (tiny.length == 0)
		return;
	UIImage *blurred = [UIImage imageWithData:tiny];
	if (!blurred)
		return;
	[page setPageImage:blurred];
	page.showingMinithumb = YES;
}

- (void)loadImageForPageAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)_items.count)
		return;

	NSDictionary *item = _items[index];
	NSNumber *fileId = [item[@"isVideo"] boolValue] ? item[@"thumbId"] : item[@"fullId"];
	if (![fileId isKindOfClass:NSNumber.class])
		fileId = item[@"thumbId"];
	if (![fileId isKindOfClass:NSNumber.class])
		return;

	NSNumber *key = @(index);
	TGMediaPageView *page = _visiblePages[key];
	if (!page)
		return;
	if ([page.loadingFileId isEqual:fileId])
		return;
	page.loadingFileId = fileId;
	[_failedPages removeObject:key];
	[self updateLoadingChrome];

	[self showMinithumbOnPage:page forItem:item];

	NSNumber *thumbId = item[@"thumbId"];
	if ([thumbId isKindOfClass:NSNumber.class] && ![thumbId isEqual:fileId] &&
		(!page.imageView.image || page.showingMinithumb))
		[self loadThumbnailForPageAtIndex:index fileId:thumbId];

	CGFloat maxSidePixels = [self fullImageMaxSidePixels];

	[_prefetchedFiles addObject:fileId];
	[[TGClient shared] startDownloadingFile:[fileId integerValue]
								   priority:(index == _currentIndex ? 32 : 8)
								 completion:nil];

	void (^handlePath)(NSString *) = [self pathHandlerForPageKey:key
														  fileId:fileId
												   maxSidePixels:maxSidePixels];

	NSArray *sizes = item[@"sizes"];
	if ([sizes isKindOfClass:NSArray.class] && sizes.count > 0 &&
		![item[@"isVideo"] boolValue]){
		CGFloat wanted = self.view.bounds.size.width;
		[[TGClient shared] downloadPhotoSizes:sizes
									 forWidth:wanted
										scale:[UIScreen mainScreen].scale
								   completion:^(NSString *path, NSDictionary *size){
			handlePath(path);
		}];
	} else {
		[[TGClient shared] downloadFile:[fileId integerValue] completion:handlePath];
	}

	[self prefetchNeighboursOfIndex:index];
}

- (CGFloat)fullImageMaxSidePixels {
	CGFloat maxSidePixels = MAX(self.view.bounds.size.width, self.view.bounds.size.height)
			* [UIScreen mainScreen].scale;
	if (maxSidePixels > 960.0f)
		maxSidePixels = 960.0f;
	return maxSidePixels;
}

- (void (^)(NSString *))pathHandlerForPageKey:(NSNumber *)key
									   fileId:(NSNumber *)fileId
								maxSidePixels:(CGFloat)maxSidePixels {
	__weak typeof(self) weakSelf = self;
	return ^(NSString *path){
		typeof(self) me = weakSelf;
		if (!me)
			return;
		if (path.length == 0){
			TGMediaPageView *failedPage = me.visiblePages[key];
			if (failedPage && [failedPage.loadingFileId isEqual:fileId]){
				failedPage.loadingFileId = nil;
				[me.failedPages addObject:key];
				[me updateLoadingChrome];
			}
			return;
		}
		dispatch_async(TGImageDecodeQueue(), ^{
			UIImage *image = TGDecodeThumbnail(path, maxSidePixels);
			dispatch_async(dispatch_get_main_queue(), ^{
				typeof(self) strongMe = weakSelf;
				if (!strongMe)
					return;
				TGMediaPageView *target = strongMe.visiblePages[key];
				if (!target || ![target.loadingFileId isEqual:fileId])
					return;
				if (!image){
					target.loadingFileId = nil;
					[strongMe.failedPages addObject:key];
					[strongMe updateLoadingChrome];
					return;
				}
				strongMe.imageCache[key] = image;
				[target setPageImage:image crossfade:(target.imageView.image != nil)];
				[strongMe updateLoadingChrome];
			});
		});
	};
}

- (void)loadThumbnailForPageAtIndex:(NSInteger)index fileId:(NSNumber *)thumbId {
	NSNumber *key = @(index);
	CGFloat sidePixels = TGMediaTileSide * 4.0f;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:[thumbId integerValue] completion:^(NSString *path){
		if (path.length == 0)
			return;
		dispatch_async(TGImageDecodeQueue(), ^{
			UIImage *image = TGDecodeThumbnail(path, sidePixels);
			if (!image)
				return;
			dispatch_async(dispatch_get_main_queue(), ^{
				typeof(self) me = weakSelf;
				if (!me)
					return;
				TGMediaPageView *target = me.visiblePages[key];
				if (!target || me.imageCache[key])
					return;
				if (index >= (NSInteger)me.items.count ||
					![me.items[index][@"thumbId"] isEqual:thumbId])
					return;
				if (target.imageView.image && !target.showingMinithumb)
					return;
				[target setPageImage:image crossfade:target.showingMinithumb];
			});
		});
	}];
}

- (void)cancelDownloadsOutsideWindow {
	if (_prefetchedFiles.count == 0 || _spinner.isAnimating)
		return;

	NSMutableSet *wanted = [NSMutableSet set];
	for (NSInteger index = _currentIndex - 1; index <= _currentIndex + 1; index++){
		if (index < 0 || index >= (NSInteger)_items.count)
			continue;
		NSDictionary *item = _items[index];
		NSNumber *fullId = item[@"fullId"];
		NSNumber *thumbId = item[@"thumbId"];
		if ([fullId isKindOfClass:NSNumber.class])
			[wanted addObject:fullId];
		if ([thumbId isKindOfClass:NSNumber.class])
			[wanted addObject:thumbId];
	}

	for (NSNumber *fileId in [_prefetchedFiles copy]){
		if ([wanted containsObject:fileId])
			continue;
		[[TGClient shared] cancelDownloadOfFile:[fileId integerValue] onlyIfPending:NO];
		[_prefetchedFiles removeObject:fileId];
	}
}

- (void)prefetchNeighboursOfIndex:(NSInteger)index {
	NSInteger neighbours[2] = {index - 1, index + 1};
	for (NSInteger i = 0; i < 2; i++){
		NSInteger at = neighbours[i];
		if (at < 0 || at >= (NSInteger)_items.count)
			continue;

		NSDictionary *item = _items[at];
		if ([item[@"isVideo"] boolValue])
			continue;

		NSNumber *fileId = item[@"fullId"];
		if (![fileId isKindOfClass:NSNumber.class] || [fileId integerValue] <= 0)
			continue;
		if ([_prefetchedFiles containsObject:fileId])
			continue;

		[_prefetchedFiles addObject:fileId];
		[[TGClient shared] startDownloadingFile:[fileId integerValue]
									   priority:1
									 completion:nil];
	}
}

- (void)updateLoadingChrome {
	if (!_playButton.enabled)
		return;

	NSNumber *key = @(_currentIndex);
	TGMediaPageView *page = _visiblePages[key];

	BOOL failed = page && !_imageCache[key] && [_failedPages containsObject:key];
	BOOL loading = page && !_imageCache[key] && page.loadingFileId && !failed;

	if (loading || failed){
		NSDictionary *item = [self currentItem];
		if (failed)
			_progressLabel.text = @"tap to try again";
		else
			_progressLabel.text = [item[@"isVideo"] boolValue]
					? @"loading video..." : @"loading full image...";
		[_progressLabel sizeToFit];

		CGFloat panelWidth = _bottomBar.frame.size.width;
		CGFloat labelWidth = _progressLabel.frame.size.width;
		CGFloat labelHeight = _progressLabel.frame.size.height;
		CGFloat labelLeft = (CGFloat)floorf((panelWidth - labelWidth) / 2.0f)
				+ (failed ? 0.0f : 10.0f);
		CGFloat labelTop = _authorLabel.text.length > 0 ? 23.0f : 14.0f;
		CGFloat retinaPixel = ([UIScreen mainScreen].scale > 1.0f) ? 0.5f : 0.0f;

		_progressLabel.frame = CGRectMake(labelLeft, labelTop, labelWidth, labelHeight);
		_progressSpinner.center = CGPointMake(labelLeft - 19.0f + 7.5f,
											  labelTop + 1.0f + retinaPixel + 7.5f);
		if (loading)
			[_progressSpinner startAnimating];
		else
			[_progressSpinner stopAnimating];
	} else {
		[_progressSpinner stopAnimating];
	}

	BOOL busy = loading || failed;
	[UIView animateWithDuration:0.2 animations:^{
		self.progressContainer.alpha = busy ? 1.0f : 0.0f;
		self.controlsContainer.alpha = busy ? 0.0f : 1.0f;
	}];

	[self updateProgressRingLoading:loading page:page];
}

- (void)updateProgressRingLoading:(BOOL)loading page:(TGMediaPageView *)page {
	if (!loading){
		_ringFileId = nil;
		if (!_progressRing.hidden){
			[UIView animateWithDuration:0.2 animations:^{
				self.progressRing.alpha = 0.0f;
			} completion:^(BOOL finished){
				self.progressRing.hidden = YES;
				self.progressRing.progress = 0.0f;
			}];
		}
		return;
	}

	_ringFileId = page.loadingFileId;

	NSDictionary *item = [self currentItem];
	NSArray *sizes = item[@"sizes"];
	if ([sizes isKindOfClass:NSArray.class] && sizes.count > 0 &&
		![item[@"isVideo"] boolValue]){
		NSDictionary *chosen = [[TGClient shared] bestPhotoSizeIn:sizes
														 forWidth:self.view.bounds.size.width
															scale:[UIScreen mainScreen].scale];
		if ([chosen[@"fileId"] isKindOfClass:NSNumber.class])
			_ringFileId = chosen[@"fileId"];
	}

	if (_progressRing.hidden){
		_progressRing.progress = 0.0f;
		_progressRing.alpha = 0.0f;
		_progressRing.hidden = NO;
		[UIView animateWithDuration:0.2 animations:^{
			self.progressRing.alpha = 1.0f;
		}];
	}
}

- (void)retryTapped {
	NSNumber *key = @(_currentIndex);
	[_failedPages removeObject:key];
	TGMediaPageView *page = _visiblePages[key];
	page.loadingFileId = nil;
	[self loadImageForPageAtIndex:_currentIndex];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (scrollView != _pagingView || _dismissing)
		return;

	CGFloat width = [self pageWidth];
	if (width < 1)
		return;

	NSInteger index = (NSInteger)((scrollView.contentOffset.x + width / 2.0f) / width);
	if (index < 0)
		index = 0;
	if (index > (NSInteger)_items.count - 1)
		index = (NSInteger)_items.count - 1;

	if (index != _currentIndex){
		_currentIndex = index;
		[self updateVisiblePages];
		[self updateChromeForCurrentItem];
	}
}

#pragma mark - chrome

- (void)updateChromeForCurrentItem {
	if (_items.count == 0)
		return;

	_counterLabel.text = [NSString stringWithFormat:@"%ld of %lu",
			(long)(_currentIndex + 1), (unsigned long)_items.count];

	NSDictionary *item = _items[_currentIndex];
	NSString *caption = item[@"caption"];
	NSString *author = item[@"author"];
	_captionLabel.text = [caption isKindOfClass:NSString.class] ? caption : @"";
	_authorLabel.text = [author isKindOfClass:NSString.class] ? author : @"";
	_dateLabel.text = TGMediaDayForDate([item[@"date"] integerValue]);
	_dateLabel.frame = CGRectMake(_dateLabel.frame.origin.x,
								  _authorLabel.text.length > 0 ? 23.0f : 14.0f,
								  _dateLabel.frame.size.width, _dateLabel.frame.size.height);
	[self layoutCaptionPanel];

	BOOL isVideo = [item[@"isVideo"] boolValue];
	_playButton.hidden = !isVideo;
	_authorLabel.alpha = isVideo ? 0.0f : 1.0f;
	_dateLabel.alpha = isVideo ? 0.0f : 1.0f;
	_captionPanel.alpha = (isVideo || _chromeHidden) ? 0.0f : 1.0f;
	_deleteButton.hidden = (self.chatId == 0 || [item[@"messageId"] longLongValue] == 0);

	[self updateLoadingChrome];
}

- (void)setChromeHidden:(BOOL)hidden animated:(BOOL)animated {
	_chromeHidden = hidden;
	CGFloat alpha = hidden ? 0.0f : 1.0f;
	[[UIApplication sharedApplication] setStatusBarHidden:hidden
											withAnimation:UIStatusBarAnimationFade];
	if (!hidden)
		[self layoutTopBar];
	CGFloat captionAlpha = [[self currentItem][@"isVideo"] boolValue] ? 0.0f : alpha;
	if (animated){
		[UIView animateWithDuration:(hidden ? 0.3 : 0.15) animations:^{
			self.topBar.alpha = alpha;
			self.bottomBar.alpha = alpha;
			self.captionPanel.alpha = captionAlpha;
		}];
	} else {
		_topBar.alpha = alpha;
		_bottomBar.alpha = alpha;
		_captionPanel.alpha = captionAlpha;
	}
}

- (void)handleSingleTap:(UITapGestureRecognizer *)recognizer {
	if (recognizer.state != UIGestureRecognizerStateRecognized)
		return;
	if ([_failedPages containsObject:@(_currentIndex)]){
		[self retryTapped];
		return;
	}
	[self setChromeHidden:!_chromeHidden animated:YES];
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)recognizer {
	if (recognizer.state != UIGestureRecognizerStateRecognized)
		return;

	TGMediaPageView *page = _visiblePages[@(_currentIndex)];
	if (!page || ![page canZoom])
		return;

	if ([page isZoomed]){
		[page setZoomScale:page.minimumZoomScale animated:YES];
		return;
	}

	CGPoint point = [recognizer locationInView:page.imageView];
	CGFloat scale = page.maximumZoomScale;
	CGSize size = page.bounds.size;
	CGFloat width = size.width / scale;
	CGFloat height = size.height / scale;
	CGRect target = CGRectMake(point.x - width / 2.0f, point.y - height / 2.0f, width, height);
	[page zoomToRect:target animated:YES];
}

#pragma mark - drag to dismiss

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
	if (![recognizer isKindOfClass:[UIPanGestureRecognizer class]])
		return YES;

	TGMediaPageView *page = _visiblePages[@(_currentIndex)];
	if (page && [page isZoomed])
		return NO;
	if (_pagingView.isDragging || _pagingView.isDecelerating)
		return NO;

	CGPoint translation = [(UIPanGestureRecognizer *)recognizer translationInView:self.view];
	if (fabs(translation.y) < 1.0f)
		return NO;
	return fabs(translation.y) > fabs(translation.x);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer
		shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
	return NO;
}

- (void)handlePan:(UIPanGestureRecognizer *)recognizer {
	CGPoint translation = [recognizer translationInView:self.view];

	if (recognizer.state == UIGestureRecognizerStateBegan){
		_dismissing = YES;
		[self setChromeHidden:YES animated:YES];
		return;
	}

	if (recognizer.state == UIGestureRecognizerStateChanged){
		CGFloat fade = MIN(1.0f, fabs(translation.y) / 80.0f);
		CGFloat shrink = 1.0f - MIN(0.2f, fabs(translation.y) / 1000.0f);
		_pagingView.transform = CGAffineTransformScale(
				CGAffineTransformMakeTranslation(0, translation.y), shrink, shrink);
		self.view.backgroundColor = [UIColor colorWithWhite:0.0f alpha:1.0f - fade];
		_progressRing.alpha = _progressRing.hidden ? 0.0f : 1.0f - fade;
		return;
	}

	if (recognizer.state == UIGestureRecognizerStateEnded ||
		recognizer.state == UIGestureRecognizerStateCancelled){
		CGPoint velocity = [recognizer velocityInView:self.view];
		BOOL shouldClose = fabs(translation.y) > 100.0f || fabs(velocity.y) > 700.0f;

		if (shouldClose){
			CGFloat target = translation.y < 0 ? -self.view.bounds.size.height
											   : self.view.bounds.size.height;
			[UIView animateWithDuration:0.2 animations:^{
				self.pagingView.transform = CGAffineTransformMakeTranslation(0, target);
				self.view.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.0f];
				self.progressRing.alpha = 0.0f;
			} completion:^(BOOL finished){
				[self dismissViewControllerAnimated:NO completion:nil];
			}];
			return;
		}

		[UIView animateWithDuration:0.25 animations:^{
			self.pagingView.transform = CGAffineTransformIdentity;
			self.view.backgroundColor = [UIColor blackColor];
			self.progressRing.alpha = self.progressRing.hidden ? 0.0f : 1.0f;
		} completion:^(BOOL finished){
			self.dismissing = NO;
			[self setChromeHidden:NO animated:YES];
		}];
	}
}

#pragma mark - actions

- (void)closeTapped {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showMessage:(NSString *)message {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@""
													message:message
												   delegate:nil
										  cancelButtonTitle:@"OK"
										  otherButtonTitles:nil];
	[alert show];
}

- (NSDictionary *)currentItem {
	if (_currentIndex < 0 || _currentIndex >= (NSInteger)_items.count)
		return nil;
	return _items[_currentIndex];
}

- (void)actionsTapped {
	NSDictionary *item = [self currentItem];
	if (!item)
		return;

	NSMutableArray *actions = [NSMutableArray array];
	if (self.chatId != 0 && [item[@"messageId"] longLongValue] != 0)
		[actions addObject:@"forward"];
	[actions addObject:@"save"];
	self.sheetActions = actions;

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	sheet.actionSheetStyle = UIActionSheetStyleBlackTranslucent;
	for (NSString *action in actions){
		if ([action isEqualToString:@"save"])
			[sheet addButtonWithTitle:@"Save to Camera Roll"];
		else
			[sheet addButtonWithTitle:@"Forward via Telegram"];
	}
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	[sheet showInView:self.view];
}

- (void)deleteTapped {
	NSDictionary *item = [self currentItem];
	if (!item)
		return;
	if (self.chatId == 0 || [item[@"messageId"] longLongValue] == 0)
		return;

	self.sheetActions = @[@"delete"];

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	sheet.actionSheetStyle = UIActionSheetStyleBlackTranslucent;
	sheet.destructiveButtonIndex = [sheet addButtonWithTitle:[item[@"isVideo"] boolValue]
			? @"Delete Video" : @"Delete Photo"];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	[sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)self.sheetActions.count)
		return;

	NSString *action = self.sheetActions[index];
	if ([action isEqualToString:@"save"])
		[self saveCurrentItem];
	else if ([action isEqualToString:@"forward"])
		[self forwardCurrentItem];
	else if ([action isEqualToString:@"delete"])
		[self deleteCurrentItem];
}

- (void)saveCurrentItem {
	NSDictionary *item = [self currentItem];
	NSNumber *fileId = item[@"fullId"];
	if (![fileId isKindOfClass:NSNumber.class] || [fileId integerValue] <= 0)
		return;

	BOOL isVideo = [item[@"isVideo"] boolValue];
	[_spinner startAnimating];
	_playButton.enabled = NO;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *path){
		typeof(self) me = weakSelf;
		if (!me)
			return;
		[me.spinner stopAnimating];
		me.playButton.enabled = YES;
		if (path.length == 0){
			[me showMessage:@"Could not save"];
			return;
		}
		if (isVideo){
			if (!UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(path)){
				[me showMessage:@"This video cannot be saved."];
				return;
			}
			UISaveVideoAtPathToSavedPhotosAlbum(path, me,
					@selector(media:didFinishSavingWithError:contextInfo:), NULL);
			return;
		}
		UIImage *image = [UIImage imageWithContentsOfFile:path];
		if (!image){
			[me showMessage:@"Could not save"];
			return;
		}
		UIImageWriteToSavedPhotosAlbum(image, me,
				@selector(media:didFinishSavingWithError:contextInfo:), NULL);
	}];
}

- (void)media:(id)item didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
	[self showMessage:error ? @"Could not save" : @"Saved to Camera Roll"];
}

- (void)forwardCurrentItem {
	NSDictionary *item = [self currentItem];
	NSNumber *messageId = item[@"messageId"];
	if (![messageId isKindOfClass:NSNumber.class] || [messageId longLongValue] == 0)
		return;

	int64_t fromChat = self.chatId;
	TGForwardPicker *picker = [[TGForwardPicker alloc] init];
	picker.onPicked = ^(int64_t targetChatId){
		[[TGClient shared] forwardMessages:@[messageId]
								  fromChat:fromChat
									toChat:targetChatId
									thread:0
									asCopy:NO
							removeCaptions:NO
									silent:NO
								completion:nil];
	};

	UINavigationController *wrapper = [[UINavigationController alloc]
			initWithRootViewController:picker];
	[self presentViewController:wrapper animated:YES completion:nil];
}

- (void)deleteCurrentItem {
	NSDictionary *item = [self currentItem];
	NSNumber *messageId = item[@"messageId"];
	if (![messageId isKindOfClass:NSNumber.class] || [messageId longLongValue] == 0)
		return;

	int64_t identifier = [messageId longLongValue];
	NSInteger index = _currentIndex;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] deleteMessages:@[messageId]
							   inChat:self.chatId
						  forEveryone:NO
						   completion:^(BOOL ok){
		typeof(self) me = weakSelf;
		if (!me)
			return;
		if (!ok){
			[me showMessage:@"Could not delete"];
			return;
		}
		if (me.onMessageDeleted)
			me.onMessageDeleted(identifier);
		[me removeItemAtIndex:index];
	}];
}

- (void)removeItemAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)_items.count)
		return;

	[_items removeObjectAtIndex:index];
	if (_items.count == 0){
		[self closeTapped];
		return;
	}

	for (NSNumber *key in _visiblePages.allKeys)
		[self recyclePage:_visiblePages[key] forKey:key];
	[_imageCache removeAllObjects];
	[_failedPages removeAllObjects];

	if (_currentIndex > (NSInteger)_items.count - 1)
		_currentIndex = (NSInteger)_items.count - 1;

	_validSize = CGSizeZero;
	[self layoutPagesPreservingIndex:_currentIndex];
	[self updateChromeForCurrentItem];
}

- (void)playTapped {
	if (_currentIndex < 0 || _currentIndex >= (NSInteger)_items.count)
		return;

	NSDictionary *item = _items[_currentIndex];
	NSNumber *fileId = item[@"fullId"];
	if (![fileId isKindOfClass:NSNumber.class])
		return;

	[_spinner startAnimating];
	_playButton.enabled = NO;
	[[TGClient shared] startDownloadingFile:[fileId integerValue]
								   priority:32
								 completion:nil];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:[fileId integerValue] completion:^(NSString *path){
		typeof(self) me = weakSelf;
		if (!me)
			return;
		[me.spinner stopAnimating];
		me.playButton.enabled = YES;
		if (path.length == 0){
			[me showMessage:@"Could not download"];
			return;
		}
		MPMoviePlayerViewController *player = [[TGMPClass(MPMoviePlayerViewController) alloc]
				initWithContentURL:[NSURL fileURLWithPath:path]];
		[me presentMoviePlayerViewControllerAnimated:player];
	}];
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	for (NSNumber *key in _imageCache.allKeys){
		if ([key integerValue] != _currentIndex)
			[_imageCache removeObjectForKey:key];
	}
	[_pagePool removeAllObjects];
}

- (void)dealloc {
	for (NSNumber *fileId in _prefetchedFiles)
		[[TGClient shared] cancelDownloadOfFile:[fileId integerValue] onlyIfPending:YES];
	_pagingView.delegate = nil;
	for (NSNumber *key in _visiblePages.allKeys)
		[(TGMediaPageView *)_visiblePages[key] setDelegate:nil];
	for (TGMediaPageView *page in _pagePool)
		page.delegate = nil;
}

@end

#pragma mark - file details

static const long long TGMediaExportChunk = 256 * 1024;
static const long long TGMediaExportLimit = 12 * 1024 * 1024;

@interface TGFileDetailsViewController : UITableViewController
		<UIActionSheetDelegate, UIDocumentInteractionControllerDelegate>

@property (nonatomic, assign) NSInteger fileId;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, copy) NSString *fileType;
@property (nonatomic, copy) NSString *mimeType;
@property (nonatomic, strong) NSDictionary *file;
@property (nonatomic, copy) NSString *extension;
@property (nonatomic, assign) long long prefixSize;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, strong) NSMutableArray *infoRows;
@property (nonatomic, strong) NSArray *sheetActions;
@property (nonatomic, strong) UIDocumentInteractionController *documentController;
@property (nonatomic, copy) NSString *exportPath;
@property (nonatomic, strong) NSFileHandle *exportHandle;
@property (nonatomic, assign) long long exportOffset;
@property (nonatomic, assign) long long exportTotal;

@end

@implementation TGFileDetailsViewController

- (id)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self){
		_infoRows = [[NSMutableArray alloc] init];
		_prefixSize = -1;
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = self.fileName.length ? self.fileName : @"File";
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	[self reloadFile];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
}

- (void)setBusy:(BOOL)busy {
	_busy = busy;
	if (busy){
		UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
				initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
		[spinner startAnimating];
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
				initWithCustomView:spinner];
	} else {
		self.navigationItem.rightBarButtonItem = nil;
	}
	self.tableView.userInteractionEnabled = !busy;
}

- (void)showAlert:(NSString *)message {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@""
													message:message
												   delegate:nil
										  cancelButtonTitle:@"OK"
										  otherButtonTitles:nil];
	[alert show];
}

- (void)reloadFile {
	if (self.fileId <= 0){
		[self rebuildInfoRows];
		return;
	}

	self.busy = YES;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] fileInfo:self.fileId completion:^(NSDictionary *file){
		typeof(self) me = weakSelf;
		if (!me || !me.isViewLoaded)
			return;
		me.busy = NO;
		if (!file){
			[me rebuildInfoRows];
			[me showAlert:@"This file is no longer available on this device."];
			return;
		}
		me.file = file;
		[me rebuildInfoRows];
		[me loadPrefixSize];
		[me loadExtension];
	}];
}

- (void)loadPrefixSize {
	if (self.fileId <= 0)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadedPrefixSizeForFile:self.fileId
											offset:0
										completion:^(long long size){
		typeof(self) me = weakSelf;
		if (!me || !me.isViewLoaded)
			return;
		me.prefixSize = size;
		[me rebuildInfoRows];
	}];
}

- (void)loadExtension {
	if (self.mimeType.length == 0)
		return;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] fileExtensionForMimeType:self.mimeType
									 completion:^(NSString *extension){
		typeof(self) me = weakSelf;
		if (!me || !me.isViewLoaded || extension.length == 0)
			return;
		me.extension = extension;
		[me rebuildInfoRows];
	}];
}

- (void)addInfoRow:(NSString *)title value:(NSString *)value {
	if (value.length == 0)
		return;
	[self.infoRows addObject:@{@"title" : title, @"value" : value}];
}

- (void)rebuildInfoRows {
	[self.infoRows removeAllObjects];

	NSDictionary *file = self.file;
	long long total = [file[@"size"] longLongValue];
	if (total <= 0)
		total = [file[@"expectedSize"] longLongValue];
	long long got = [file[@"downloadedSize"] longLongValue];

	NSString *status = @"Not downloaded";
	if ([file[@"isDownloaded"] boolValue])
		status = @"Downloaded";
	else if ([file[@"isDownloading"] boolValue])
		status = @"Downloading";
	else if (got > 0)
		status = @"Partly downloaded";

	[self addInfoRow:@"Status" value:file ? status : @"Unknown"];
	if (self.extension.length)
		[self addInfoRow:@"Kind" value:[self.extension uppercaseString]];
	else if (self.mimeType.length)
		[self addInfoRow:@"Kind" value:self.mimeType];
	if (total > 0)
		[self addInfoRow:@"Size" value:TGMediaFormatBytes(total)];
	if (got > 0)
		[self addInfoRow:@"On this device" value:TGMediaFormatBytes(got)];
	if (self.prefixSize >= 0)
		[self addInfoRow:@"Playable from start"
				   value:TGMediaFormatBytes(self.prefixSize)];

	[self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? (NSInteger)self.infoRows.count : 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return section == 0 ? @"File" : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *infoIdentifier = @"TGFileInfo";
	static NSString *actionIdentifier = @"TGFileAction";

	if (indexPath.section == 0){
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:infoIdentifier];
		if (!cell){
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
										  reuseIdentifier:infoIdentifier];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
		}
		[[TGTheme shared] styleCell:cell];
		NSDictionary *row = self.infoRows[indexPath.row];
		cell.textLabel.text = row[@"title"];
		cell.detailTextLabel.text = row[@"value"];
		cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
		cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
		return cell;
	}

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:actionIdentifier];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:actionIdentifier];
	}
	[[TGTheme shared] styleCell:cell];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.textLabel.textAlignment = NSTextAlignmentLeft;

	if (indexPath.row == 0){
		cell.textLabel.text = @"Open a Copy";
	} else if (indexPath.row == 1){
		cell.textLabel.text = @"Download Priority";
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	} else {
		cell.textLabel.text = @"Fetch Again";
	}
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != 1 || self.fileId <= 0)
		return;

	if (indexPath.row == 0){
		[self exportCopy];
	} else if (indexPath.row == 1){
		[self askPriority];
	} else {
		[self fetchAgain];
	}
}

#pragma mark - priority

- (void)askPriority {
	self.sheetActions = @[@(32), @(16), @(1)];
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Download Priority"
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	[sheet addButtonWithTitle:@"High"];
	[sheet addButtonWithTitle:@"Normal"];
	[sheet addButtonWithTitle:@"Low"];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	[sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)self.sheetActions.count)
		return;

	NSInteger priority = [self.sheetActions[index] integerValue];
	self.busy = YES;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] startDownloadingFile:self.fileId
								   priority:priority
								 completion:^(NSDictionary *file){
		typeof(self) me = weakSelf;
		if (!me || !me.isViewLoaded)
			return;
		me.busy = NO;
		if (!file){
			[me showAlert:@"Could not change the priority."];
			return;
		}
		me.file = file;
		[me rebuildInfoRows];
	}];
}

#pragma mark - fetch again

- (void)fetchAgain {
	self.busy = YES;
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] fileInfo:self.fileId completion:^(NSDictionary *file){
		typeof(self) me = weakSelf;
		if (!me || !me.isViewLoaded)
			return;

		if (file && [file[@"canBeDownloaded"] boolValue]){
			me.file = file;
			[me startDownloadOfFile:me.fileId];
			return;
		}

		NSString *remoteId = file[@"remoteId"];
		NSString *type = me.fileType.length ? me.fileType : TGFileTypeDocument;
		if (![remoteId isKindOfClass:NSString.class] || remoteId.length == 0){
			me.busy = NO;
			[me showAlert:@"This file cannot be downloaded again."];
			return;
		}

		[[TGClient shared] resolveRemoteFileId:remoteId type:type
									completion:^(NSDictionary *resolved){
			typeof(self) inner = weakSelf;
			if (!inner || !inner.isViewLoaded)
				return;
			if (!resolved){
				inner.busy = NO;
				[inner showAlert:@"This file cannot be downloaded again."];
				return;
			}
			inner.file = resolved;
			inner.fileId = [resolved[@"id"] integerValue];
			[inner startDownloadOfFile:inner.fileId];
		}];
	}];
}

- (void)startDownloadOfFile:(NSInteger)fileId {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] startDownloadingFile:fileId priority:16 completion:^(NSDictionary *file){
		typeof(self) me = weakSelf;
		if (!me || !me.isViewLoaded)
			return;
		me.busy = NO;
		if (!file){
			[me showAlert:@"Could not start the download."];
			return;
		}
		me.file = file;
		[me rebuildInfoRows];
		[me loadPrefixSize];
	}];
}

#pragma mark - export a copy

- (void)exportCopy {
	long long total = [self.file[@"size"] longLongValue];
	if (total <= 0)
		total = [self.file[@"expectedSize"] longLongValue];
	if (total <= 0){
		[self showAlert:@"The size of this file is not known yet."];
		return;
	}
	if (total > TGMediaExportLimit){
		[self showAlert:@"This file is too large to open here. Play or save it instead."];
		return;
	}

	NSString *name = self.fileName.length ? [self.fileName lastPathComponent] : @"file";
	if (self.extension.length && [[name pathExtension] length] == 0)
		name = [name stringByAppendingPathExtension:self.extension];

	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
	[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
	if (![[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil]){
		[self showAlert:@"Could not open a copy."];
		return;
	}

	self.exportPath = path;
	self.exportHandle = [NSFileHandle fileHandleForWritingAtPath:path];
	self.exportOffset = 0;
	self.exportTotal = total;
	if (!self.exportHandle){
		[self showAlert:@"Could not open a copy."];
		return;
	}

	self.busy = YES;
	[self pullNextChunk];
}

- (void)finishExportWithError:(NSString *)message {
	[self.exportHandle closeFile];
	self.exportHandle = nil;
	self.busy = NO;

	if (message.length){
		[[NSFileManager defaultManager] removeItemAtPath:self.exportPath error:NULL];
		self.exportPath = nil;
		[self showAlert:message];
		return;
	}

	self.documentController = [UIDocumentInteractionController
			interactionControllerWithURL:[NSURL fileURLWithPath:self.exportPath]];
	self.documentController.delegate = self;
	if ([self.documentController presentPreviewAnimated:YES])
		return;
	if (![self.documentController presentOpenInMenuFromRect:self.view.bounds
													 inView:self.view
												   animated:YES])
		[self showAlert:@"Nothing on this device can open that file."];
}

- (void)pullNextChunk {
	long long remaining = self.exportTotal - self.exportOffset;
	if (remaining <= 0){
		[self finishExportWithError:nil];
		return;
	}

	long long count = remaining < TGMediaExportChunk ? remaining : TGMediaExportChunk;
	long long offset = self.exportOffset;
	BOOL onDisk = [self.file[@"isDownloaded"] boolValue];

	__weak typeof(self) weakSelf = self;
	void (^handleData)(NSData *) = ^(NSData *data){
		typeof(self) me = weakSelf;
		if (!me || !me.isViewLoaded)
			return;
		if (data.length == 0){
			[me finishExportWithError:@"Could not read the whole file."];
			return;
		}
		@try {
			[me.exportHandle writeData:data];
		} @catch (NSException *exception){
			[me finishExportWithError:@"Could not write the copy."];
			return;
		}
		me.exportOffset += (long long)data.length;
		[me pullNextChunk];
	};

	if (onDisk)
		[[TGClient shared] readFile:self.fileId offset:offset count:count
						 completion:handleData];
	else
		[[TGClient shared] streamFile:self.fileId offset:offset count:count
						   completion:handleData];
}

- (UIViewController *)documentInteractionControllerViewControllerForPreview:
		(UIDocumentInteractionController *)controller {
	return self;
}

- (void)documentInteractionControllerDidEndPreview:(UIDocumentInteractionController *)controller {
	if (self.exportPath.length){
		[[NSFileManager defaultManager] removeItemAtPath:self.exportPath error:NULL];
		self.exportPath = nil;
	}
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
	return orientation != UIInterfaceOrientationPortraitUpsideDown;
}

- (void)dealloc {
	[_exportHandle closeFile];
	if (_exportPath.length)
		[[NSFileManager defaultManager] removeItemAtPath:_exportPath error:NULL];
}

@end

#pragma mark - shared media

@interface TGMediaViewController ()
		<TGMediaGridCellDelegate, UIDocumentInteractionControllerDelegate, UISearchBarDelegate>

@property (nonatomic, assign) NSInteger scope;
@property (nonatomic, assign) NSInteger loadToken;
@property (nonatomic, strong) UIView *scopeBar;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong) NSMutableArray *scopeButtons;
@property (nonatomic, strong) UILabel *dateIndicator;
@property (nonatomic, strong) UIDocumentInteractionController *documentController;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) TGViewRecycler *recycler;
@property (nonatomic, strong) NSMutableArray *items;
@property (nonatomic, assign) NSInteger itemsPerRow;
@property (nonatomic, assign) int64_t lastMessageId;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL canLoadMore;
@property (nonatomic, assign) BOOL loadedOnce;

@property (nonatomic, strong) UIControl *banner;
@property (nonatomic, strong) UILabel *bannerTitle;
@property (nonatomic, strong) UILabel *bannerDetail;
@property (nonatomic, assign) BOOL bannerVisible;

@property (nonatomic, strong) NSMutableDictionary *extensionCache;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIView *emptyView;
@property (nonatomic, strong) UIImageView *emptyImageView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, assign) BOOL emptyVisible;

@end

@implementation TGMediaViewController

- (instancetype)initWithChatId:(int64_t)chatId {
	self = [super init];
	if (self){
		_chatId = chatId;
	}
	return self;
}

- (UIColor *)backgroundColourForScope:(NSInteger)scope {
	return TGMediaScopeIsGrid(scope)
			? [UIColor whiteColor]
			: [[TGTheme shared] listBackgroundColour];
}

- (void)loadView {
	[super loadView];

	self.title = @"Media";
	self.view.backgroundColor = [self backgroundColourForScope:_scope];

	_items = [[NSMutableArray alloc] init];
	_recycler = [[TGViewRecycler alloc] init];
	_extensionCache = [[NSMutableDictionary alloc] init];
	_canLoadMore = YES;
	_itemsPerRow = [self itemsPerRowForWidth:self.view.bounds.size.width];

	[self buildMediaTableView];
	[self buildScopeBar];
	[self buildSearchBar];
	[self updateSearchBarVisibility];
	[self buildDownloadsBanner];
	[self buildSpinnerAndEmptyView];
	[self buildDateIndicator];
}

- (void)buildMediaTableView {
	_tableView = [[UITableView alloc] initWithFrame:self.view.bounds
											  style:UITableViewStylePlain];
	_tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
	_tableView.backgroundColor = [self backgroundColourForScope:_scope];
	_tableView.contentInset = UIEdgeInsetsMake(0, 0, 4, 0);
	_tableView.scrollIndicatorInsets = UIEdgeInsetsZero;
	_tableView.rowHeight = TGMediaRowHeight;
	_tableView.dataSource = self;
	_tableView.delegate = self;
	[self.view addSubview:_tableView];

	UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc]
			initWithTarget:self action:@selector(handleRowLongPress:)];
	longPress.minimumPressDuration = 0.5;
	[_tableView addGestureRecognizer:longPress];
}

- (void)buildScopeBar {
	CGRect scopeFrame = CGRectMake(0, 0, self.view.bounds.size.width, TGMediaScopeHeight);
	UIImage *scopeBackground = [UIImage imageNamed:@"SearchBarScopeBarBackground.png"];
	if (scopeBackground){
		UIImageView *barView = [[UIImageView alloc] initWithFrame:scopeFrame];
		barView.image = scopeBackground;
		barView.userInteractionEnabled = YES;
		_scopeBar = barView;
	} else {
		_scopeBar = [[UIView alloc] initWithFrame:scopeFrame];
		_scopeBar.backgroundColor = [TGTheme shared].isFlat
				? [[TGTheme shared] listBackgroundColour]
				: [UIColor colorWithRed:0xc3 / 255.0f green:0xcb / 255.0f
									blue:0xd4 / 255.0f alpha:1.0f];
		UIView *scopeLine = [[UIView alloc] initWithFrame:
				CGRectMake(0, TGMediaScopeHeight - 1, scopeFrame.size.width, 1)];
		scopeLine.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		scopeLine.backgroundColor = [[TGTheme shared] separatorColour];
		[_scopeBar addSubview:scopeLine];
	}
	_scopeBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_scopeBar.clipsToBounds = YES;
	[self.view addSubview:_scopeBar];

	_scopeButtons = [NSMutableArray array];
	NSArray *scopeTitles = TGMediaScopeTitles();
	for (NSUInteger i = 0; i < scopeTitles.count; i++){
		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.tag = (NSInteger)i;
		button.titleLabel.font = [UIFont boldSystemFontOfSize:12];
		button.titleLabel.shadowOffset = CGSizeMake(0, -1);
		[button setTitle:scopeTitles[i] forState:UIControlStateNormal];
		[self styleScopeButton:button selected:(i == 0)];
		[button addTarget:self action:@selector(scopeTapped:)
		 forControlEvents:UIControlEventTouchDown];
		[_scopeBar addSubview:button];
		[_scopeButtons addObject:button];
	}
}

- (void)buildSearchBar {
	_searchBar = [[UISearchBar alloc] initWithFrame:
			CGRectMake(0, 0, self.view.bounds.size.width, TGMediaSearchBarHeight)];
	_searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_searchBar.delegate = self;
	_searchBar.placeholder = @"Search";
	UIImage *searchBackground = [UIImage imageNamed:@"SearchBarBackground.png"];
	if (searchBackground && [_searchBar respondsToSelector:@selector(setBackgroundImage:)])
		[_searchBar setBackgroundImage:searchBackground];
}

- (void)buildDownloadsBanner {
	_banner = [[UIControl alloc] initWithFrame:
			CGRectMake(0, 0, self.view.bounds.size.width, TGMediaBannerHeight)];
	_banner.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_banner.backgroundColor = [[TGTheme shared] barColour];
	_banner.hidden = YES;
	[_banner addTarget:self action:@selector(bannerTapped)
	  forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:_banner];

	CGFloat retinaPixel = ([UIScreen mainScreen].scale > 1.0f) ? 0.5f : 0.0f;

	_bannerTitle = [[UILabel alloc] initWithFrame:
			CGRectMake(12 + retinaPixel, 2, self.view.bounds.size.width - 12 - 46, 18)];
	_bannerTitle.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_bannerTitle.backgroundColor = [UIColor clearColor];
	_bannerTitle.font = [UIFont boldSystemFontOfSize:14];
	_bannerTitle.lineBreakMode = NSLineBreakByTruncatingTail;
	_bannerTitle.textColor = [UIColor colorWithRed:0x36 / 255.0f green:0x3a / 255.0f
											  blue:0x40 / 255.0f alpha:1.0f];
	_bannerTitle.text = @"Downloads";
	[_banner addSubview:_bannerTitle];

	_bannerDetail = [[UILabel alloc] initWithFrame:
			CGRectMake(12 + retinaPixel, 21 + retinaPixel,
					   self.view.bounds.size.width - 12 - 46, 18)];
	_bannerDetail.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_bannerDetail.backgroundColor = [UIColor clearColor];
	_bannerDetail.font = [UIFont systemFontOfSize:14];
	_bannerDetail.lineBreakMode = NSLineBreakByTruncatingTail;
	_bannerDetail.textColor = [UIColor blackColor];
	[_banner addSubview:_bannerDetail];

	UIView *bannerLine = [[UIView alloc] initWithFrame:
			CGRectMake(0, TGMediaBannerHeight - 1, self.view.bounds.size.width, 1)];
	bannerLine.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	bannerLine.backgroundColor = [[TGTheme shared] separatorColour];
	[_banner addSubview:bannerLine];
}

- (void)buildSpinnerAndEmptyView {
	_spinner = [[UIActivityIndicatorView alloc]
			initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
	_spinner.center = CGPointMake(self.view.bounds.size.width / 2,
								  self.view.bounds.size.height / 2 - 40);
	_spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin
			| UIViewAutoresizingFlexibleBottomMargin;
	_spinner.hidesWhenStopped = YES;
	[self.view addSubview:_spinner];

	UIImage *blank = [UIImage imageNamed:@"PhotosBlankPlaceholder.png"];
	_emptyImageView = [[UIImageView alloc] initWithImage:blank];

	_emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_emptyLabel.backgroundColor = [UIColor clearColor];
	_emptyLabel.textAlignment = NSTextAlignmentCenter;
	_emptyLabel.font = [UIFont boldSystemFontOfSize:17];
	_emptyLabel.textColor = [UIColor colorWithRed:0x80 / 255.0f green:0x88 / 255.0f
											 blue:0x95 / 255.0f alpha:1.0f];
	_emptyLabel.text = TGMediaEmptyTextForScope(_scope);
	[_emptyLabel sizeToFit];

	_emptyView = [[UIView alloc] initWithFrame:CGRectZero];
	_emptyView.backgroundColor = [UIColor clearColor];
	_emptyView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
			| UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin
			| UIViewAutoresizingFlexibleBottomMargin;
	[_emptyView addSubview:_emptyImageView];
	[_emptyView addSubview:_emptyLabel];
	_emptyImageView.hidden = !TGMediaScopeIsGrid(_scope);
	_emptyView.alpha = 0.0f;
	_emptyView.userInteractionEnabled = NO;
	[self.view insertSubview:_emptyView aboveSubview:_tableView];
	[self layoutEmptyView];
}

- (void)buildDateIndicator {
	_dateIndicator = [[UILabel alloc] initWithFrame:
			CGRectMake(self.view.bounds.size.width - 140, TGMediaScopeHeight + 8, 128, 22)];
	_dateIndicator.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	_dateIndicator.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.6f];
	_dateIndicator.textColor = [UIColor whiteColor];
	_dateIndicator.font = [UIFont boldSystemFontOfSize:12];
	_dateIndicator.textAlignment = NSTextAlignmentCenter;
	_dateIndicator.layer.cornerRadius = 4.0f;
	_dateIndicator.clipsToBounds = YES;
	_dateIndicator.alpha = 0.0f;
	[self.view addSubview:_dateIndicator];
}

- (void)layoutEmptyView {
	CGRect bounds = self.view.bounds;
	UIImage *blank = _emptyImageView.hidden ? nil : _emptyImageView.image;
	CGFloat imageHeight = blank ? blank.size.height : 0.0f;
	CGFloat imageWidth = blank ? blank.size.width : 0.0f;
	CGFloat gap = imageHeight > 0.0f ? 12.0f : 0.0f;
	CGFloat width = MAX(imageWidth, _emptyLabel.frame.size.width);
	CGFloat height = imageHeight + gap + _emptyLabel.frame.size.height;

	_emptyView.frame = CGRectIntegral(CGRectMake((bounds.size.width - width) / 2.0f,
												 (bounds.size.height - height) / 2.0f - 18.0f,
												 width, height));
	_emptyImageView.frame = CGRectIntegral(CGRectMake((width - imageWidth) / 2.0f, 0,
													  imageWidth, imageHeight));
	_emptyLabel.frame = CGRectIntegral(CGRectMake(
			(width - _emptyLabel.frame.size.width) / 2.0f, imageHeight + gap,
			_emptyLabel.frame.size.width, _emptyLabel.frame.size.height));
}

- (void)setEmptyVisible:(BOOL)visible animated:(BOOL)animated {
	if (_emptyVisible == visible)
		return;
	_emptyVisible = visible;
	[self layoutEmptyView];

	BOOL keepTable = (self.query ?: @"").length > 0;
	void (^apply)(void) = ^{
		self.emptyView.alpha = visible ? 1.0f : 0.0f;
		self.tableView.alpha = (visible && !keepTable) ? 0.0f : 1.0f;
	};
	if (animated)
		[UIView animateWithDuration:0.2 animations:apply];
	else
		apply();
}

- (void)styleScopeButton:(UIButton *)button selected:(BOOL)selected {
	UIImage *plate = [UIImage imageNamed:selected
			? @"SearchBarScopeButton_Highlighted.png" : @"SearchBarScopeButton.png"];
	if (plate){
		plate = [plate stretchableImageWithLeftCapWidth:(int)(plate.size.width / 2)
										   topCapHeight:0];
		[button setBackgroundImage:plate forState:UIControlStateNormal];
		button.backgroundColor = [UIColor clearColor];
	} else {
		button.backgroundColor = selected
				? [[TGTheme shared] accentColour]
				: [UIColor clearColor];
	}

	if (selected){
		[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
		[button setTitleShadowColor:[UIColor colorWithRed:0x11 / 255.0f green:0x2e / 255.0f
													 blue:0x5c / 255.0f alpha:0.2f]
						   forState:UIControlStateNormal];
	} else {
		[button setTitleColor:[UIColor colorWithRed:0x5c / 255.0f green:0x70 / 255.0f
											   blue:0x8b / 255.0f alpha:1.0f]
					 forState:UIControlStateNormal];
		[button setTitleShadowColor:[UIColor colorWithWhite:1.0f alpha:0.25f]
						   forState:UIControlStateNormal];
	}
}

- (void)layoutScopeButtons {
	CGFloat width = self.view.bounds.size.width;
	NSUInteger count = _scopeButtons.count;
	if (width < 1 || count == 0)
		return;

	CGFloat available = width - 12;
	CGFloat each = (CGFloat)(int)(available / count);
	for (NSUInteger i = 0; i < count; i++){
		UIButton *button = _scopeButtons[i];
		CGFloat buttonWidth = (i == count - 1) ? (available - each * (count - 1)) : each;
		button.frame = CGRectMake(6 + each * i,
								  (CGFloat)(int)((TGMediaScopeHeight
										  - TGMediaScopeButtonHeight) / 2),
								  buttonWidth, TGMediaScopeButtonHeight);
	}
}

- (void)scopeTapped:(UIButton *)button {
	if (button.tag == _scope)
		return;

	_scope = button.tag;
	_loadToken++;
	for (UIButton *other in _scopeButtons)
		[self styleScopeButton:other selected:(other.tag == _scope)];

	self.query = @"";
	_searchBar.text = @"";
	[_searchBar resignFirstResponder];
	[self updateSearchBarVisibility];

	[_items removeAllObjects];
	_lastMessageId = 0;
	_canLoadMore = YES;
	_loadedOnce = NO;
	_loading = NO;
	[self setEmptyVisible:NO animated:NO];
	_emptyLabel.text = TGMediaEmptyTextForScope(_scope);
	[_emptyLabel sizeToFit];
	_emptyImageView.hidden = !TGMediaScopeIsGrid(_scope);
	[self layoutEmptyView];
	self.view.backgroundColor = [self backgroundColourForScope:_scope];
	_tableView.backgroundColor = [self backgroundColourForScope:_scope];
	_dateIndicator.alpha = 0.0f;
	[_recycler removeAllViews];
	_tableView.rowHeight = TGMediaScopeIsGrid(_scope)
			? TGMediaRowHeight : TGMediaListRowHeight;
	_tableView.separatorStyle = TGMediaScopeIsGrid(_scope)
			? UITableViewCellSeparatorStyleNone : UITableViewCellSeparatorStyleSingleLine;
	_tableView.separatorColor = [[TGTheme shared] separatorColour];
	[_tableView reloadData];
	[_tableView setContentOffset:CGPointZero animated:NO];
	[self loadNextPage];
}

- (void)updateSearchBarVisibility {
	_tableView.tableHeaderView = TGMediaScopeIsGrid(_scope) ? nil : _searchBar;
}

- (void)reloadFromStart {
	_loadToken++;
	[_items removeAllObjects];
	_lastMessageId = 0;
	_canLoadMore = YES;
	_loadedOnce = NO;
	_loading = NO;
	[self setEmptyVisible:NO animated:NO];
	[_recycler removeAllViews];
	[_tableView reloadData];
	[self loadNextPage];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
	[searchBar setShowsCancelButton:YES animated:YES];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
	[searchBar setShowsCancelButton:NO animated:YES];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
	NSString *text = searchBar.text ?: @"";
	if ([text isEqualToString:self.query ?: @""])
		return;
	self.query = text;
	[self reloadFromStart];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
	searchBar.text = @"";
	[searchBar resignFirstResponder];
	if ((self.query ?: @"").length == 0)
		return;
	self.query = @"";
	[self reloadFromStart];
}

- (void)viewDidLoad {
	[super viewDidLoad];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	[self loadNextPage];
	[self refreshDownloadsBanner];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	self.tableView.backgroundColor = [self backgroundColourForScope:_scope];
	[self refreshDownloadsBanner];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];

	CGFloat top = _bannerVisible ? TGMediaBannerHeight : 0.0f;
	CGRect bounds = self.view.bounds;
	_banner.frame = CGRectMake(0, 0, bounds.size.width, TGMediaBannerHeight);
	_scopeBar.frame = CGRectMake(0, top, bounds.size.width, TGMediaScopeHeight);
	[self layoutScopeButtons];
	top += TGMediaScopeHeight;
	_tableView.frame = CGRectMake(0, top, bounds.size.width, bounds.size.height - top);
	[self layoutEmptyView];
	_dateIndicator.frame = CGRectMake(bounds.size.width - 140, top + 8, 128, 22);

	NSInteger perRow = [self itemsPerRowForWidth:bounds.size.width];
	if (perRow != _itemsPerRow){
		_itemsPerRow = perRow;
		[_tableView reloadData];
	}
}

- (NSInteger)itemsPerRowForWidth:(CGFloat)width {
	NSInteger perRow = (NSInteger)(width / (TGMediaTileSide + TGMediaTileSpacing));
	return perRow < 1 ? 1 : perRow;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
	return orientation != UIInterfaceOrientationPortraitUpsideDown;
}

#pragma mark - loading

- (void)loadNextPage {
	if (_loading || !_canLoadMore || self.chatId == 0)
		return;

	_loading = YES;
	if (!_loadedOnce)
		[_spinner startAnimating];

	NSInteger token = _loadToken;
	NSInteger scope = _scope;

	__weak typeof(self) weakSelf = self;
	NSDictionary *request = @{
		@"@type"           : @"searchChatMessages",
		@"chat_id"         : @(self.chatId),
		@"query"           : self.query ?: @"",
		@"from_message_id" : @(_lastMessageId),
		@"offset"          : @(0),
		@"limit"           : @(TGMediaPageSize),
		@"filter"          : @{@"@type" : TGMediaFilterForScope(scope)},
	};

	[[TGClient shared] request:request completion:^(NSDictionary *result){
		typeof(self) me = weakSelf;
		if (!me || me.loadToken != token)
			return;
		[me applyPageResult:result scope:scope];
	}];
}

- (void)applyPageResult:(NSDictionary *)result scope:(NSInteger)scope {
	self.loading = NO;
	self.loadedOnce = YES;
	[self.spinner stopAnimating];

	NSArray *messages = result[@"messages"];
	if (![messages isKindOfClass:NSArray.class] || messages.count == 0){
		self.canLoadMore = NO;
		[self setEmptyVisible:(self.items.count == 0) animated:YES];
		[self.tableView reloadData];
		return;
	}

	NSInteger added = 0;
	for (NSDictionary *message in messages){
		if (![message isKindOfClass:NSDictionary.class])
			continue;
		NSDictionary *item = TGMediaScopeIsGrid(scope)
				? TGMediaItemFromMessage(message)
				: TGMediaListItemFromMessage(message, scope);
		if (item){
			[self.items addObject:item];
			added++;
		}
		int64_t identifier = [message[@"id"] longLongValue];
		if (identifier != 0)
			self.lastMessageId = identifier;
	}

	if (messages.count < (NSUInteger)TGMediaPageSize)
		self.canLoadMore = NO;

	[self setEmptyVisible:(self.items.count == 0 && !self.canLoadMore) animated:YES];
	[self.tableView reloadData];

	if (added == 0 && self.canLoadMore)
		[self loadNextPage];
}

#pragma mark - downloads banner

- (void)refreshDownloadsBanner {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchDownloadsWithQuery:@""
									 onlyActive:NO
								  onlyCompleted:NO
										 offset:nil
										  limit:1
									 completion:^(NSDictionary *page){
		typeof(self) me = weakSelf;
		if (!me || !me.isViewLoaded)
			return;

		NSInteger active = [page[@"activeCount"] integerValue];
		NSInteger paused = [page[@"pausedCount"] integerValue];
		NSInteger completed = [page[@"completedCount"] integerValue];
		NSInteger total = active + paused + completed;

		if (total == 0){
			me.bannerVisible = NO;
			me.banner.hidden = YES;
			[me.view setNeedsLayout];
			return;
		}

		NSMutableArray *parts = [NSMutableArray array];
		if (active > 0)
			[parts addObject:[NSString stringWithFormat:@"%ld downloading", (long)active]];
		if (paused > 0)
			[parts addObject:[NSString stringWithFormat:@"%ld paused", (long)paused]];
		if (completed > 0)
			[parts addObject:[NSString stringWithFormat:@"%ld ready", (long)completed]];

		me.bannerDetail.text = [parts componentsJoinedByString:@", "];
		me.bannerVisible = YES;
		me.banner.hidden = NO;
		[me.view setNeedsLayout];
	}];
}

- (void)bannerTapped {
	TGDownloadsViewController *downloads = [[TGDownloadsViewController alloc] init];
	if (self.navigationController)
		[self.navigationController pushViewController:downloads animated:YES];
}

#pragma mark - table

- (NSInteger)numberOfRowsForItems {
	if (!TGMediaScopeIsGrid(_scope))
		return (NSInteger)_items.count;
	NSInteger perRow = _itemsPerRow < 1 ? 1 : _itemsPerRow;
	return ((NSInteger)_items.count + perRow - 1) / perRow;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	NSInteger rows = [self numberOfRowsForItems];
	return _canLoadMore ? rows + 1 : rows;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.row >= [self numberOfRowsForItems])
		return 50.0f;
	return TGMediaScopeIsGrid(_scope) ? TGMediaRowHeight : TGMediaListRowHeight;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.row >= [self numberOfRowsForItems])
		return [self loadingCellForTableView:tableView];
	if (!TGMediaScopeIsGrid(_scope))
		return [self listCellForTableView:tableView atRow:indexPath.row];
	return [self gridCellForTableView:tableView atRow:indexPath.row];
}

- (UITableViewCell *)loadingCellForTableView:(UITableView *)tableView {
	static NSString *loadingIdentifier = @"TGMediaLoading";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:loadingIdentifier];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:loadingIdentifier];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.backgroundColor = [UIColor clearColor];
		UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
				initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
		spinner.tag = 401;
		spinner.frame = CGRectMake(
				(CGFloat)(int)((tableView.bounds.size.width
						- spinner.frame.size.width) / 2), 14,
				spinner.frame.size.width, spinner.frame.size.height);
		spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin
				| UIViewAutoresizingFlexibleRightMargin;
		[cell.contentView addSubview:spinner];
	}
	UIActivityIndicatorView *spinner = (UIActivityIndicatorView *)[cell.contentView viewWithTag:401];
	[spinner startAnimating];
	return cell;
}

- (UITableViewCell *)listCellForTableView:(UITableView *)tableView atRow:(NSInteger)row {
	static NSString *listIdentifier = @"TGMediaList";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:listIdentifier];
	if (!cell){
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:listIdentifier];
		cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
		cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
	}
	[[TGTheme shared] styleCell:cell];
	cell.textLabel.textColor = [[TGTheme shared] primaryTextColour];
	cell.detailTextLabel.textColor = [[TGTheme shared] secondaryTextColour];
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.accessoryType = UITableViewCellAccessoryNone;

	if (row < (NSInteger)_items.count){
		NSDictionary *item = _items[row];
		cell.textLabel.text = item[@"title"];
		NSString *detail = item[@"detail"];
		NSString *mime = item[@"mime"];
		if (_scope == TGMediaScopeFiles && [mime isKindOfClass:NSString.class]
				&& mime.length){
			NSString *known = _extensionCache[mime];
			if (known.length)
				detail = [NSString stringWithFormat:@"%@ · %@",
						[known uppercaseString], detail];
			else if (!known)
				[self loadExtensionForMime:mime];
		}
		cell.detailTextLabel.text = detail;
	}
	return cell;
}

- (UITableViewCell *)gridCellForTableView:(UITableView *)tableView atRow:(NSInteger)row {
	static NSString *gridIdentifier = @"TGMediaGrid";
	TGMediaGridCell *cell = (TGMediaGridCell *)[tableView dequeueReusableCellWithIdentifier:gridIdentifier];
	if (!cell){
		cell = [[TGMediaGridCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:gridIdentifier];
	}
	cell.recycler = _recycler;
	cell.gridDelegate = self;

	NSInteger perRow = _itemsPerRow < 1 ? 1 : _itemsPerRow;
	NSInteger base = row * perRow;
	NSInteger end = MIN(base + perRow, (NSInteger)_items.count);
	NSArray *slice = base < end
			? [_items subarrayWithRange:NSMakeRange(base, end - base)] : @[];

	[cell configureWithItems:slice baseIndex:base];
	return cell;
}

- (void)tableView:(UITableView *)tableView
	willDisplayCell:(UITableViewCell *)cell
  forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (!_canLoadMore || _loading)
		return;
	if (indexPath.row + 4 >= [self numberOfRowsForItems])
		[self loadNextPage];
}

- (void)tableView:(UITableView *)tableView
	didEndDisplayingCell:(UITableViewCell *)cell
	   forRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([cell isKindOfClass:[TGMediaGridCell class]])
		[(TGMediaGridCell *)cell releaseTiles];
}

- (void)gridCell:(TGMediaGridCell *)cell tappedItemAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)_items.count)
		return;

	TGMediaFullscreenController *viewer = [[TGMediaFullscreenController alloc]
			initWithItems:[_items copy] index:index];
	viewer.chatId = self.chatId;

	__weak typeof(self) weakSelf = self;
	viewer.onMessageDeleted = ^(int64_t messageId){
		[weakSelf removeItemWithMessageId:messageId];
	};

	[self presentViewController:viewer animated:YES completion:nil];
}

- (void)removeItemWithMessageId:(int64_t)messageId {
	for (NSInteger i = 0; i < (NSInteger)_items.count; i++){
		if ([_items[i][@"messageId"] longLongValue] != messageId)
			continue;
		[_items removeObjectAtIndex:i];
		[_tableView reloadData];
		[self setEmptyVisible:(_items.count == 0 && !_canLoadMore) animated:YES];
		return;
	}
}

#pragma mark - list rows

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (TGMediaScopeIsGrid(_scope) || indexPath.row >= (NSInteger)_items.count)
		return;

	NSDictionary *item = _items[indexPath.row];

	if (_scope == TGMediaScopeLinks){
		NSString *url = item[@"url"];
		if (![url isKindOfClass:NSString.class] || url.length == 0)
			return;
		NSURL *target = [NSURL URLWithString:url];
		if (!target.scheme.length)
			target = [NSURL URLWithString:[@"http://" stringByAppendingString:url]];
		if (target)
			[[UIApplication sharedApplication] openURL:target];
		return;
	}

	NSInteger fileId = [item[@"fileId"] integerValue];
	if (fileId <= 0)
		return;

	[_spinner startAnimating];
	[[TGClient shared] startDownloadingFile:fileId priority:32 completion:nil];

	BOOL isMusic = (_scope == TGMediaScopeMusic);
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] downloadFile:fileId completion:^(NSString *path){
		typeof(self) me = weakSelf;
		if (!me || !me.isViewLoaded)
			return;
		[me.spinner stopAnimating];
		if (path.length == 0){
			[me showAlertMessage:@"Could not download"];
			return;
		}
		if (isMusic){
			MPMoviePlayerViewController *player = [[TGMPClass(MPMoviePlayerViewController) alloc]
					initWithContentURL:[NSURL fileURLWithPath:path]];
			[me presentMoviePlayerViewControllerAnimated:player];
			return;
		}
		[me previewFileAtPath:path];
	}];
}

- (void)loadExtensionForMime:(NSString *)mime {
	if (mime.length == 0 || _extensionCache[mime])
		return;
	_extensionCache[mime] = @"";

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] fileExtensionForMimeType:mime completion:^(NSString *extension){
		typeof(self) me = weakSelf;
		if (!me || !me.isViewLoaded)
			return;
		if (extension.length == 0)
			return;
		me.extensionCache[mime] = extension;
		if (me.scope == TGMediaScopeFiles)
			[me.tableView reloadData];
	}];
}

- (void)handleRowLongPress:(UILongPressGestureRecognizer *)recognizer {
	if (recognizer.state != UIGestureRecognizerStateBegan)
		return;
	if (TGMediaScopeIsGrid(_scope) || _scope == TGMediaScopeLinks)
		return;

	CGPoint point = [recognizer locationInView:_tableView];
	NSIndexPath *path = [_tableView indexPathForRowAtPoint:point];
	if (!path || path.row >= (NSInteger)_items.count)
		return;

	NSDictionary *item = _items[path.row];
	NSInteger fileId = [item[@"fileId"] integerValue];
	if (fileId <= 0)
		return;

	TGFileDetailsViewController *details = [[TGFileDetailsViewController alloc] init];
	details.fileId = fileId;
	details.fileName = item[@"title"];
	details.mimeType = item[@"mime"];
	details.fileType = item[@"fileType"];
	if (self.navigationController)
		[self.navigationController pushViewController:details animated:YES];
}

- (void)showAlertMessage:(NSString *)message {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@""
													message:message
												   delegate:nil
										  cancelButtonTitle:@"OK"
										  otherButtonTitles:nil];
	[alert show];
}

- (void)previewFileAtPath:(NSString *)path {
	self.documentController = [UIDocumentInteractionController
			interactionControllerWithURL:[NSURL fileURLWithPath:path]];
	self.documentController.delegate = self;
	if ([self.documentController presentPreviewAnimated:YES])
		return;
	[self.documentController presentOpenInMenuFromRect:self.view.bounds
												inView:self.view
											  animated:YES];
}

- (UIViewController *)documentInteractionControllerViewControllerForPreview:
		(UIDocumentInteractionController *)controller {
	return self;
}

#pragma mark - fast scroll date

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	if (scrollView != _tableView || _items.count == 0)
		return;
	if (!scrollView.isDragging && !scrollView.isDecelerating)
		return;

	NSArray *visible = [_tableView indexPathsForVisibleRows];
	if (visible.count == 0)
		return;

	NSIndexPath *top = visible[0];
	NSInteger perRow = TGMediaScopeIsGrid(_scope)
			? (_itemsPerRow < 1 ? 1 : _itemsPerRow) : 1;
	NSInteger index = top.row * perRow;
	if (index >= (NSInteger)_items.count)
		index = (NSInteger)_items.count - 1;

	NSString *month = TGMediaMonthForDate([_items[index][@"date"] integerValue]);
	if (month.length == 0)
		return;

	_dateIndicator.text = month;
	if (_dateIndicator.alpha < 1.0f){
		[UIView animateWithDuration:0.15 animations:^{
			self.dateIndicator.alpha = 1.0f;
		}];
	}
}

- (void)hideDateIndicator {
	if (_dateIndicator.alpha == 0.0f)
		return;
	[UIView animateWithDuration:0.25 animations:^{
		self.dateIndicator.alpha = 0.0f;
	}];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
	[self hideDateIndicator];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
	if (!decelerate)
		[self hideDateIndicator];
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	[_recycler removeAllViews];
}

- (void)dealloc {
	_tableView.delegate = nil;
	_tableView.dataSource = nil;
	[_recycler removeAllViews];
}

@end

#pragma mark - downloads

@interface TGDownloadsRowCell : UITableViewCell

@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIProgressView *progressView;

@end

@implementation TGDownloadsRowCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self){
		_nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_nameLabel.backgroundColor = [UIColor clearColor];
		_nameLabel.font = [UIFont boldSystemFontOfSize:15];
		_nameLabel.textColor = [[TGTheme shared] primaryTextColour];
		[self.contentView addSubview:_nameLabel];

		_detailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
		_detailLabel.backgroundColor = [UIColor clearColor];
		_detailLabel.font = [UIFont systemFontOfSize:12];
		_detailLabel.textColor = [[TGTheme shared] secondaryTextColour];
		[self.contentView addSubview:_detailLabel];

		_progressView = [[UIProgressView alloc]
				initWithProgressViewStyle:UIProgressViewStyleDefault];
		_progressView.progressTintColor = [[TGTheme shared] accentColour];
		[self.contentView addSubview:_progressView];
	}
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat width = self.contentView.bounds.size.width;
	_nameLabel.frame = CGRectMake(12, 6, width - 24, 19);
	_progressView.frame = CGRectMake(12, 30, width - 24, 9);
	_detailLabel.frame = CGRectMake(12, 40, width - 24, 16);
}

@end

@interface TGDownloadsViewController () <UIActionSheetDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *storageLabel;
@property (nonatomic, assign) BOOL storageLoaded;
@property (nonatomic, strong) NSMutableArray *active;
@property (nonatomic, strong) NSMutableArray *completed;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) void (^savedProgressBlock)(NSInteger fileId, float progress);
@property (nonatomic, assign) BOOL progressHooked;
@property (nonatomic, strong) NSTimer *refreshTimer;

@end

@implementation TGDownloadsViewController

- (void)loadView {
	[super loadView];

	self.title = @"Downloads";
	self.view.backgroundColor = [[TGTheme shared] listBackgroundColour];

	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;

	_active = [[NSMutableArray alloc] init];
	_completed = [[NSMutableArray alloc] init];

	_tableView = [[UITableView alloc] initWithFrame:self.view.bounds
											  style:UITableViewStylePlain];
	_tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	_tableView.separatorColor = [[TGTheme shared] separatorColour];
	_tableView.rowHeight = 62.0f;
	_tableView.dataSource = self;
	_tableView.delegate = self;
	[self.view addSubview:_tableView];

	_emptyLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(0, self.view.bounds.size.height / 2 - 60,
					   self.view.bounds.size.width, 20)];
	_emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_emptyLabel.backgroundColor = [UIColor clearColor];
	_emptyLabel.textAlignment = NSTextAlignmentCenter;
	_emptyLabel.font = [UIFont systemFontOfSize:15];
	_emptyLabel.textColor = [[TGTheme shared] secondaryTextColour];
	_emptyLabel.text = @"Nothing downloading";
	_emptyLabel.hidden = YES;
	[self.view addSubview:_emptyLabel];

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
			initWithTitle:@"Clear"
					style:UIBarButtonItemStylePlain
				   target:self
				   action:@selector(clearTapped)];

	_storageLabel = [[UILabel alloc] initWithFrame:
			CGRectMake(0, 0, self.view.bounds.size.width, 44)];
	_storageLabel.backgroundColor = [UIColor clearColor];
	_storageLabel.textAlignment = NSTextAlignmentCenter;
	_storageLabel.font = [UIFont systemFontOfSize:13];
	_storageLabel.textColor = [[TGTheme shared] secondaryTextColour];
	_storageLabel.numberOfLines = 2;
	_storageLabel.text = @"Counting cached files…";
	_tableView.tableFooterView = _storageLabel;
}

- (void)loadStorageSummary {
	if (self.storageLoaded)
		return;
	self.storageLoaded = YES;

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] storageStatisticsWithChatLimit:20 completion:^(NSDictionary *stats){
		typeof(self) me = weakSelf;
		if (!me || !me.isViewLoaded)
			return;
		if (!stats){
			me.storageLabel.text = @"Cache size unavailable";
			return;
		}
		long long size = [stats[@"size"] longLongValue];
		NSInteger count = [stats[@"count"] integerValue];
		NSArray *chats = stats[@"chats"];
		NSString *top = @"";
		if ([chats isKindOfClass:NSArray.class] && chats.count > 0){
			NSDictionary *largest = chats[0];
			NSString *title = largest[@"title"];
			if ([title isKindOfClass:NSString.class] && title.length)
				top = [NSString stringWithFormat:@"\nLargest: %@, %@", title,
						TGMediaFormatBytes([largest[@"size"] longLongValue])];
		}
		me.storageLabel.text = [NSString stringWithFormat:@"%ld cached files, %@%@",
				(long)count, TGMediaFormatBytes(size), top];
	}];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
	[self reload];
	[self loadStorageSummary];
	[self installProgressHook];

	self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
														 target:self
													   selector:@selector(reload)
													   userInfo:nil
														repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.refreshTimer invalidate];
	self.refreshTimer = nil;
	[self removeProgressHook];
}

#pragma mark - progress

- (void)installProgressHook {
	if (self.progressHooked)
		return;

	TGClient *client = [TGClient shared];
	void (^previous)(NSInteger, float) = client.onFileProgress;
	self.savedProgressBlock = previous;
	self.progressHooked = YES;

	__weak typeof(self) weakSelf = self;
	client.onFileProgress = ^(NSInteger fileId, float progress){
		if (previous)
			previous(fileId, progress);
		[weakSelf applyProgress:progress toFile:fileId];
	};
}

- (void)removeProgressHook {
	if (!self.progressHooked)
		return;
	[TGClient shared].onFileProgress = self.savedProgressBlock;
	self.savedProgressBlock = nil;
	self.progressHooked = NO;
}

- (void)applyProgress:(float)progress toFile:(NSInteger)fileId {
	if (!self.isViewLoaded)
		return;

	for (NSInteger row = 0; row < (NSInteger)_active.count; row++){
		NSDictionary *entry = _active[row];
		if ([entry[@"fileId"] integerValue] != fileId)
			continue;

		NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:0];
		TGDownloadsRowCell *cell = (TGDownloadsRowCell *)[_tableView cellForRowAtIndexPath:path];
		if ([cell isKindOfClass:[TGDownloadsRowCell class]]){
			[cell.progressView setProgress:progress animated:YES];
			long long total = [entry[@"file"][@"size"] longLongValue];
			if (total <= 0)
				total = [entry[@"file"][@"expectedSize"] longLongValue];
			cell.detailLabel.text = total > 0
					? [NSString stringWithFormat:@"%@ of %@",
							TGMediaFormatBytes((long long)(total * progress)),
							TGMediaFormatBytes(total)]
					: [NSString stringWithFormat:@"%d%%", (int)(progress * 100)];
		}
		return;
	}
}

#pragma mark - data

- (void)reload {
	__weak typeof(self) weakSelf = self;
	[[TGClient shared] searchDownloadsWithQuery:@""
									 onlyActive:NO
								  onlyCompleted:NO
										 offset:nil
										  limit:100
									 completion:^(NSDictionary *page){
		typeof(self) me = weakSelf;
		if (!me || !me.isViewLoaded)
			return;

		NSArray *downloads = page[@"downloads"];
		if (![downloads isKindOfClass:NSArray.class])
			downloads = @[];

		[me.active removeAllObjects];
		[me.completed removeAllObjects];

		for (NSDictionary *entry in downloads){
			if ([entry[@"completeDate"] longLongValue] > 0 ||
				[entry[@"file"][@"isDownloaded"] boolValue])
				[me.completed addObject:entry];
			else
				[me.active addObject:entry];
		}

		me.emptyLabel.hidden = downloads.count != 0;
		[me.tableView reloadData];
	}];
}

- (void)clearTapped {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Clear Downloads"
													   delegate:self
											  cancelButtonTitle:nil
										 destructiveButtonTitle:nil
											  otherButtonTitles:nil];
	[sheet addButtonWithTitle:@"Clear Finished"];
	[sheet addButtonWithTitle:@"Clear List"];
	sheet.destructiveButtonIndex = [sheet addButtonWithTitle:@"Clear List and Delete Files"];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	[sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index < 0 || index > 2)
		return;

	if (index == 0){
		[[TGClient shared] removeAllDownloadsOnlyActive:NO
										  onlyCompleted:YES
										deleteFromCache:NO];
		[_completed removeAllObjects];
	} else {
		[[TGClient shared] removeAllDownloadsOnlyActive:NO
										  onlyCompleted:NO
										deleteFromCache:(index == 2)];
		[_active removeAllObjects];
		[_completed removeAllObjects];
	}

	_emptyLabel.hidden = (_active.count + _completed.count) != 0;
	[_tableView reloadData];

	self.storageLoaded = NO;
	_storageLabel.text = @"Counting cached files…";
	[self loadStorageSummary];
}

#pragma mark - table

- (NSArray *)entriesForSection:(NSInteger)section {
	return section == 0 ? _active : _completed;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)[self entriesForSection:section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if ([self entriesForSection:section].count == 0)
		return nil;
	return section == 0 ? @"Downloading" : @"Downloaded";
}

- (UITableViewCell *)tableView:(UITableView *)tableView
		 cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *identifier = @"TGDownloadRow";
	TGDownloadsRowCell *cell = (TGDownloadsRowCell *)
			[tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell){
		cell = [[TGDownloadsRowCell alloc] initWithStyle:UITableViewCellStyleDefault
										 reuseIdentifier:identifier];
	}
	[[TGTheme shared] styleCell:cell];

	NSArray *entries = [self entriesForSection:indexPath.section];
	if (indexPath.row >= (NSInteger)entries.count)
		return cell;

	NSDictionary *entry = entries[indexPath.row];
	NSDictionary *file = entry[@"file"];

	NSString *name = entry[@"fileName"];
	if (![name isKindOfClass:NSString.class] || name.length == 0)
		name = [NSString stringWithFormat:@"File %@", entry[@"fileId"] ?: @0];
	cell.nameLabel.text = name;

	long long total = [file[@"size"] longLongValue];
	if (total <= 0)
		total = [file[@"expectedSize"] longLongValue];
	long long got = [file[@"downloadedSize"] longLongValue];

	if (indexPath.section == 0){
		cell.progressView.hidden = NO;
		cell.progressView.progress = total > 0 ? (float)((double)got / (double)total) : 0.0f;
		BOOL paused = [entry[@"isPaused"] boolValue];
		cell.detailLabel.text = paused
				? [NSString stringWithFormat:@"Paused, %@ of %@",
						TGMediaFormatBytes(got), TGMediaFormatBytes(total)]
				: [NSString stringWithFormat:@"%@ of %@",
						TGMediaFormatBytes(got), TGMediaFormatBytes(total)];
	} else {
		cell.progressView.hidden = YES;
		cell.detailLabel.text = TGMediaFormatBytes(total > 0 ? total : got);
	}

	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	cell.accessoryType = indexPath.section == 0
			? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
	[cell setNeedsLayout];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	NSArray *entries = [self entriesForSection:indexPath.section];
	if (indexPath.row >= (NSInteger)entries.count)
		return;

	NSDictionary *entry = entries[indexPath.row];
	NSInteger fileId = [entry[@"fileId"] integerValue];

	if (indexPath.section != 0){
		if (fileId <= 0)
			return;
		TGFileDetailsViewController *details = [[TGFileDetailsViewController alloc] init];
		details.fileId = fileId;
		details.fileName = entry[@"fileName"];
		details.fileType = TGFileTypeDocument;
		if (self.navigationController)
			[self.navigationController pushViewController:details animated:YES];
		return;
	}

	BOOL paused = [entry[@"isPaused"] boolValue];
	[[TGClient shared] setDownloadOfFile:fileId paused:!paused];
	[self reload];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return YES;
}

- (void)tableView:(UITableView *)tableView
		commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
		 forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete)
		return;

	NSMutableArray *entries = indexPath.section == 0 ? _active : _completed;
	if (indexPath.row >= (NSInteger)entries.count)
		return;

	NSDictionary *entry = entries[indexPath.row];
	if (indexPath.section == 0)
		[[TGClient shared] cancelDownloadOfFile:[entry[@"fileId"] integerValue] onlyIfPending:NO];

	[entries removeObjectAtIndex:indexPath.row];
	[tableView deleteRowsAtIndexPaths:@[indexPath]
					 withRowAnimation:UITableViewRowAnimationFade];
	_emptyLabel.hidden = (_active.count + _completed.count) != 0;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
	return orientation != UIInterfaceOrientationPortraitUpsideDown;
}

- (void)dealloc {
	[_refreshTimer invalidate];
	_tableView.delegate = nil;
	_tableView.dataSource = nil;
}

@end
