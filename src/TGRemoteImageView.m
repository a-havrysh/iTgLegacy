#import "TGRemoteImageView.h"
#import "TGClient.h"
#import "TGImageDecode.h"

@interface TGRemoteImageView ()
@property (nonatomic, strong) UIImage *placeholderImage;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, strong) NSString *currentCacheKey;
@end

static NSCache *TGRemoteImageMemoryCache(void) {
	static NSCache *cache = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		cache = [[NSCache alloc] init];
		cache.totalCostLimit = 6 * 1024 * 1024;
		[[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
														  object:nil
														   queue:[NSOperationQueue mainQueue]
													  usingBlock:^(NSNotification *__unused note){
			[cache removeAllObjects];
		}];
	});
	return cache;
}

static NSUInteger TGRemoteImageCost(UIImage *image) {
	CGImageRef cg = image.CGImage;
	if (!cg)
		return 1;
	NSUInteger cost = CGImageGetHeight(cg) * CGImageGetBytesPerRow(cg);
	return cost > 0 ? cost : 1;
}

@implementation TGRemoteImageView

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.fadeTransitionDuration = 0.14;
	}
	return self;
}

- (void)prepareForReuse {
	[self cancelLoading];
	self.fileId = nil;
	self.currentCacheKey = nil;
	self.image = self.placeholderImage;
}

- (void)prepareForRecycle:(TGViewRecycler *)__unused recycler {
	[self cancelLoading];
}

- (UIImage *)currentImage {
	return self.image;
}

- (NSString *)cachePathForKey:(NSString *)key {
	static NSString *dir = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		dir = [NSSearchPathForDirectoriesInDomains(
				NSCachesDirectory, NSUserDomainMask, YES).firstObject
						stringByAppendingPathComponent:@"RemoteImageCache"];
		[[NSFileManager defaultManager] createDirectoryAtPath:dir
								 withIntermediateDirectories:YES attributes:nil error:nil];
	});
	return [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.png", key]];
}

- (void)applyImage:(UIImage *)image fade:(bool)fade {
	if (!image)
		return;
	if (fade){
		NSTimeInterval duration = self.fadeTransitionDuration > FLT_EPSILON ? self.fadeTransitionDuration : 0.14;
		[UIView transitionWithView:self duration:duration
						   options:UIViewAnimationOptionTransitionCrossDissolve
						animations:^{ self.image = image; } completion:nil];
	} else {
		self.image = image;
	}
}

- (void)loadWithFileId:(NSNumber *)fileId square:(CGFloat)side placeholder:(UIImage *)placeholder forceFade:(bool)forceFade {
	self.placeholderImage = placeholder;
	self.fileId = fileId;
	self.cancelled = false;

	if (![fileId isKindOfClass:NSNumber.class] || side < 1.0f){
		self.currentCacheKey = nil;
		self.image = placeholder;
		return;
	}

	NSString *cacheKey = [NSString stringWithFormat:@"%@_%d", fileId.stringValue, (int)(side + 0.5f)];
	self.currentCacheKey = cacheKey;

	UIImage *memoryCached = [TGRemoteImageMemoryCache() objectForKey:cacheKey];
	if (memoryCached){
		self.image = memoryCached;
		return;
	}

	self.image = placeholder;

	NSString *cachePath = [self cachePathForKey:cacheKey];
	bool fade = self.fadeTransition || forceFade;
	CGFloat screenScale = [UIScreen mainScreen].scale;
	if (screenScale < 1.0f)
		screenScale = 1.0f;
	__weak typeof(self) weakSelf = self;

	void (^deliver)(UIImage *) = ^(UIImage *image){
		TGRemoteImageView *me = weakSelf;
		if (!me || !image || me.cancelled || ![me.fileId isEqual:fileId] || ![me.currentCacheKey isEqualToString:cacheKey])
			return;
		[me applyImage:image fade:fade];
	};

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		UIImage *cached = nil;
		NSData *cachedData = [NSData dataWithContentsOfFile:cachePath];
		if (cachedData.length){
			cached = [UIImage imageWithData:cachedData scale:screenScale];
			CGFloat expected = side * screenScale;
			if (cached && (fabs(cached.size.width * cached.scale - expected) > 0.5f ||
						   fabs(cached.size.height * cached.scale - expected) > 0.5f))
				cached = nil;
		}
		if (cached){
			[TGRemoteImageMemoryCache() setObject:cached forKey:cacheKey cost:TGRemoteImageCost(cached)];
			dispatch_async(dispatch_get_main_queue(), ^{ deliver(cached); });
			return;
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			TGRemoteImageView *me = weakSelf;
			if (!me || me.cancelled || ![me.fileId isEqual:fileId])
				return;
			[[TGClient shared] downloadFile:fileId.integerValue completion:^(NSString *path){
				if (path.length == 0)
					return;
				dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
					UIImage *thumb = TGDecodeSquareThumbnail(path, side);
					if (!thumb)
						return;
					NSData *data = UIImagePNGRepresentation(thumb);
					if (data.length != 0)
						[data writeToFile:cachePath atomically:YES];
					[TGRemoteImageMemoryCache() setObject:thumb forKey:cacheKey cost:TGRemoteImageCost(thumb)];
					dispatch_async(dispatch_get_main_queue(), ^{ deliver(thumb); });
				});
			}];
		});
	});
}

- (void)loadPlaceholder:(UIImage *)placeholder {
	[self cancelLoading];
	self.fileId = nil;
	self.currentCacheKey = nil;
	self.placeholderImage = placeholder;
	self.image = placeholder;
}

- (void)cancelLoading {
	self.cancelled = true;
}

@end
