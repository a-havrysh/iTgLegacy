#import "TGViewRecycler.h"

static const NSUInteger TGViewRecyclerMaxPoolSize = 24;

@interface TGViewRecycler ()

@property (nonatomic, strong) NSMutableDictionary *reusableViews;

@end

@implementation TGViewRecycler

- (id)init {
	self = [super init];
	if (self != nil){
		dispatch_async(dispatch_get_main_queue(), ^{
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveMemoryWarning)
					name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
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

	NSMutableArray *views = self.reusableViews[reuseIdentifier];
	if (views == nil){
		views = [[NSMutableArray alloc] init];
		self.reusableViews[reuseIdentifier] = views;
	}

	[view prepareForRecycle:self];

	if (view.superview != nil)
		[view removeFromSuperview];

	if ([views indexOfObjectIdenticalTo:view] != NSNotFound)
		return;

	if (views.count >= TGViewRecyclerMaxPoolSize)
		return;

	[views addObject:view];
}

- (int)recycledCount:(NSString *)identifier {
	if (identifier == nil)
		return 0;

	NSMutableArray *views = self.reusableViews[identifier];
	return (int)views.count;
}

- (void)removeAllViews {
	[self.reusableViews removeAllObjects];
}

@end
