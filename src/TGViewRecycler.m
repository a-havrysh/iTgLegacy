#import "TGViewRecycler.h"

static const NSUInteger TGViewRecyclerMaxPoolSize = 12;
static const NSUInteger TGViewRecyclerMaxTotalPoolSize = 32;

@interface TGViewRecycler ()

@property (nonatomic, strong) NSMutableDictionary *reusableViews;
@property (nonatomic, assign) NSUInteger pooledViewCount;

@end

@implementation TGViewRecycler

- (id)init {
	self = [super init];
	if (self != nil){
		dispatch_async(dispatch_get_main_queue(), ^{
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveMemoryWarning)
					name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveMemoryWarning)
					name:UIApplicationDidEnterBackgroundNotification object:nil];
		});
		self.reusableViews = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didReceiveMemoryWarning {
	[self removeAllViews];
}

- (UIView<TGReusableView> *)dequeueReusableViewWithIdentifier:(NSString *)reuseIdentifier {
	if (reuseIdentifier == nil)
		return nil;

	NSMutableArray *views = self.reusableViews[reuseIdentifier];
	if (views == nil)
		return nil;

	UIView<TGReusableView> *view = [views lastObject];
	if (view != nil){
		[views removeLastObject];
		if (self.pooledViewCount > 0)
			self.pooledViewCount--;
		if (views.count == 0)
			[self.reusableViews removeObjectForKey:reuseIdentifier];
		[view prepareForReuse];
	}
	return view;
}

- (void)recycleView:(UIView<TGReusableView> *)view {
	if (view == nil)
		return;

	NSString *reuseIdentifier = nil;
	if ([view respondsToSelector:@selector(reuseIdentifier)])
		reuseIdentifier = [view reuseIdentifier];
	if (reuseIdentifier == nil)
		reuseIdentifier = NSStringFromClass([view class]);

	if (view.superview != nil)
		[view removeFromSuperview];

	[view prepareForRecycle:self];

	NSMutableArray *views = self.reusableViews[reuseIdentifier];

	if ([views indexOfObjectIdenticalTo:view] != NSNotFound)
		return;

	if (views.count >= TGViewRecyclerMaxPoolSize)
		return;

	if (self.pooledViewCount >= TGViewRecyclerMaxTotalPoolSize)
		return;

	if (views == nil){
		views = [[NSMutableArray alloc] init];
		self.reusableViews[reuseIdentifier] = views;
	}

	[views addObject:view];
	self.pooledViewCount++;
}

- (int)recycledCount:(NSString *)identifier {
	if (identifier == nil)
		return 0;

	NSMutableArray *views = self.reusableViews[identifier];
	return (int)views.count;
}

- (void)removeAllViews {
	[self.reusableViews removeAllObjects];
	self.pooledViewCount = 0;
}

@end
