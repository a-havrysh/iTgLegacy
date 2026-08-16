#import "EKPalette.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <pthread.h>

@protocol EKEmojiObject <NSObject>
- (NSString *)emojiString;
- (unsigned short)glyph;
- (void)setGlyph:(unsigned short)glyph;
@end

@protocol EKEmojiCategory <NSObject>
- (NSArray *)emoji;
- (void)setEmoji:(NSArray *)emoji;
@end

@protocol EKPageControl <NSObject>
- (NSInteger)numberOfPages;
- (BOOL)isHidden;
- (void)setHidden:(BOOL)hidden;
@end

@protocol EKEmojiFactory <NSObject>
+ (id)emojiWithString:(NSString *)string;
+ (id)categories;
@end

@interface EKPrepared : NSObject
{
	id _emoji;
	NSString *_key;
	unsigned short _glyph;
}
@property (nonatomic, readonly) id emoji;
@property (nonatomic, readonly) NSString *key;
@property (nonatomic, readonly) unsigned short glyph;
@end

@implementation EKPrepared

@synthesize emoji = _emoji;
@synthesize key = _key;
@synthesize glyph = _glyph;

- (id)initWithEmoji:(id)emoji key:(NSString *)key glyph:(unsigned short)glyph
{
	self = [super init];
	if (self){
		_emoji = [emoji retain];
		_key = [key copy];
		_glyph = glyph;
	}
	return self;
}

- (void)dealloc
{
	[_emoji release];
	[_key release];
	[super dealloc];
}

@end

static Class gCategoryClass;
static Class gEmojiClass;
static BOOL gStop;
static void *EKMarkerKey = &EKMarkerKey;

static pthread_mutex_t gPreparedLock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableDictionary *gPrepared;

static id (*gOriginalCategoryForType)(id, SEL, int);
static id (*gOriginalGlyphForRecents)(id, SEL, id);
static void (*gOriginalLayoutPages)(id, SEL);

#pragma mark - substrate

static void (*gHookMessage)(Class, SEL, IMP, IMP *);

static void EKResolveSubstrate(void)
{
	static const char *candidates[] = {
		"/usr/lib/libsubstrate.dylib",
		"/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
		"/usr/lib/libsubstrate.0.dylib",
		"/usr/lib/libhooker.dylib",
		NULL
	};

	gHookMessage = dlsym(RTLD_DEFAULT, "MSHookMessageEx");
	for (int i = 0; !gHookMessage && candidates[i]; i++){
		void *image = dlopen(candidates[i], RTLD_LAZY | RTLD_GLOBAL);
		if (image)
			gHookMessage = dlsym(image, "MSHookMessageEx");
	}
}

static BOOL EKMethodBelongsTo(Class target, SEL selector)
{
	unsigned int count = 0;
	Method *methods = class_copyMethodList(target, &count);
	if (!methods)
		return NO;
	BOOL found = NO;
	for (unsigned int i = 0; i < count && !found; i++)
		found = method_getName(methods[i]) == selector;
	free(methods);
	return found;
}

static BOOL EKHook(Class target, SEL selector, IMP replacement, void *original)
{
	if (!target || !selector || !replacement || !original)
		return NO;
	if (!class_getInstanceMethod(target, selector))
		return NO;

	IMP *slot = (IMP *)original;
	if (gHookMessage){
		*slot = NULL;
		gHookMessage(target, selector, replacement, slot);
		return *slot != NULL;
	}

	if (!EKMethodBelongsTo(target, selector))
		return NO;
	*slot = method_setImplementation(class_getInstanceMethod(target, selector),
									 replacement);
	return *slot != NULL;
}

#pragma mark - signature guards

static BOOL EKSignatureIs(NSMethodSignature *signature, const char *returnType,
						  const char *argumentTypes)
{
	if (!signature)
		return NO;
	size_t wanted = strlen(argumentTypes);
	if ([signature numberOfArguments] != wanted + 2)
		return NO;
	if (strcmp([signature methodReturnType], returnType) != 0)
		return NO;
	for (size_t i = 0; i < wanted; i++){
		char one[2] = {argumentTypes[i], 0};
		if (strcmp([signature getArgumentTypeAtIndex:i + 2], one) != 0)
			return NO;
	}
	return YES;
}

static BOOL EKClassMethodIs(Class target, SEL selector, const char *returnType,
							const char *argumentTypes)
{
	if (![target respondsToSelector:selector])
		return NO;
	return EKSignatureIs([target methodSignatureForSelector:selector],
						 returnType, argumentTypes);
}

static BOOL EKInstanceMethodIs(Class target, SEL selector, const char *returnType,
							   const char *argumentTypes)
{
	if (!class_getInstanceMethod(target, selector))
		return NO;
	return EKSignatureIs([target instanceMethodSignatureForSelector:selector],
						 returnType, argumentTypes);
}

#pragma mark - normalisation

static NSString *EKNormalise(NSString *string)
{
	NSUInteger length = [string length];
	BOOL selectors = NO;
	for (NSUInteger i = 0; i < length && !selectors; i++){
		unichar unit = [string characterAtIndex:i];
		selectors = unit == 0xFE0F || unit == 0xFE0E;
	}
	if (!selectors)
		return string;

	NSMutableString *plain = [NSMutableString stringWithCapacity:length];
	for (NSUInteger i = 0; i < length; i++){
		unichar unit = [string characterAtIndex:i];
		if (unit == 0xFE0F || unit == 0xFE0E)
			continue;
		[plain appendFormat:@"%C", unit];
	}
	return [plain length] ? plain : string;
}

#pragma mark - preparation

static NSArray *EKPreparedForType(int type)
{
	pthread_mutex_lock(&gPreparedLock);
	NSArray *ready = [[[gPrepared objectForKey:[NSNumber numberWithInt:type]]
			retain] autorelease];
	pthread_mutex_unlock(&gPreparedLock);
	return ready;
}

static void EKPrepareAll(void)
{
	if (gStop || !gEmojiClass)
		return;

	NSMutableDictionary *staged = [NSMutableDictionary dictionary];
	for (int type = EK_FIRST_TYPE; type <= EK_LAST_TYPE; type++){
		NSArray *extras = EKExtrasForType(type);
		NSMutableArray *prepared = [NSMutableArray arrayWithCapacity:[extras count]];
		for (EKEntry *entry in extras){
			id emoji = [(Class <EKEmojiFactory>)gEmojiClass emojiWithString:entry.string];
			if (![emoji isKindOfClass:gEmojiClass])
				continue;
			if (![emoji respondsToSelector:@selector(setGlyph:)])
				continue;
			[(id <EKEmojiObject>)emoji setGlyph:entry.glyph];
			EKPrepared *slot = [[EKPrepared alloc]
					initWithEmoji:emoji
							  key:EKNormalise(entry.string)
							glyph:entry.glyph];
			[prepared addObject:slot];
			[slot release];
		}
		[staged setObject:prepared forKey:[NSNumber numberWithInt:type]];
	}

	pthread_mutex_lock(&gPreparedLock);
	[gPrepared release];
	gPrepared = [staged retain];
	pthread_mutex_unlock(&gPreparedLock);

	EKCompact();
}

#pragma mark - appending

static NSMutableSet *gStockGlyphs;

static void EKCollectGlyphs(id category, NSMutableSet *into)
{
	if (![category isKindOfClass:gCategoryClass])
		return;
	NSArray *list = [(id <EKEmojiCategory>)category emoji];
	if (![list isKindOfClass:[NSArray class]])
		return;
	for (id one in list){
		if (![one respondsToSelector:@selector(glyph)])
			continue;
		unsigned short glyph = [(id <EKEmojiObject>)one glyph];
		if (glyph)
			[into addObject:[NSNumber numberWithUnsignedShort:glyph]];
	}
}

static NSSet *EKStockGlyphs(void)
{
	if (gStockGlyphs)
		return gStockGlyphs;

	gStockGlyphs = [[NSMutableSet alloc] initWithCapacity:1024];
	for (int type = EK_FIRST_TYPE; type <= EK_LAST_TYPE; type++){
		id category = gOriginalCategoryForType(gCategoryClass,
											   @selector(categoryForType:), type);
		EKCollectGlyphs(category, gStockGlyphs);
	}
	EKLog(@"stock palette draws %lu distinct glyphs",
		  (unsigned long)[gStockGlyphs count]);
	return gStockGlyphs;
}

static void EKAppendToCategory(id category, int type)
{
	if (gStop || type < EK_FIRST_TYPE || type > EK_LAST_TYPE)
		return;
	if (!category || ![category isKindOfClass:gCategoryClass])
		return;
	if (objc_getAssociatedObject(category, EKMarkerKey))
		return;

	NSArray *current = [(id <EKEmojiCategory>)category emoji];
	if (![current isKindOfClass:[NSArray class]] || ![current count])
		return;

	NSArray *prepared = EKPreparedForType(type);
	if (!prepared){
		EKEnsureBuild();
		return;
	}

	NSMutableSet *taken = [NSMutableSet setWithSet:EKStockGlyphs()];
	for (id existing in current){
		if ([existing respondsToSelector:@selector(emojiString)]){
			NSString *text = [(id <EKEmojiObject>)existing emojiString];
			if ([text isKindOfClass:[NSString class]] && [text length])
				[taken addObject:EKNormalise(text)];
		}
	}

	NSMutableArray *added = [NSMutableArray arrayWithCapacity:[prepared count]];
	for (EKPrepared *slot in prepared){
		NSNumber *glyph = [NSNumber numberWithUnsignedShort:slot.glyph];
		if ([taken containsObject:glyph] || [taken containsObject:slot.key])
			continue;
		[taken addObject:glyph];
		[taken addObject:slot.key];
		[added addObject:slot.emoji];
	}

	if ([added count])
		[(id <EKEmojiCategory>)category setEmoji:
				[current arrayByAddingObjectsFromArray:added]];
	objc_setAssociatedObject(category, EKMarkerKey, (id)kCFBooleanTrue,
							 OBJC_ASSOCIATION_ASSIGN);
	EKLog(@"category %d: %lu stock + %lu added", type,
		  (unsigned long)[current count], (unsigned long)[added count]);
}

static void EKAppendToExistingCategories(void)
{
	if (gStop || !gCategoryClass)
		return;
	if (!EKClassMethodIs(gCategoryClass, @selector(categories), "@", ""))
		return;

	id list = [(Class <EKEmojiFactory>)gCategoryClass categories];
	if (![list isKindOfClass:[NSArray class]])
		return;

	int type = 0;
	for (id category in list){
		if (type >= EK_FIRST_TYPE && type <= EK_LAST_TYPE)
			EKAppendToCategory(category, type);
		type++;
	}
}

#pragma mark - hooks

static void EKPanic(NSException *exception, NSString *where)
{
	gStop = YES;
	EKComplain(@"%@ raised %@ (%@); every hook is now a straight pass-through",
			   where, [exception name], [exception reason]);
}

static id EKCategoryForType(id self, SEL _cmd, int type)
{
	id category = gOriginalCategoryForType(self, _cmd, type);
	if (gStop)
		return category;
	@try {
		if (!EKExtrasReady())
			EKEnsureBuild();
		EKAppendToCategory(category, type);
	}
	@catch (NSException *exception){
		EKPanic(exception, @"categoryForType:");
	}
	return category;
}

static id EKGlyphForRecents(id self, SEL _cmd, id recents)
{
	if (gStop || !gEmojiClass || ![recents isKindOfClass:[NSArray class]])
		return gOriginalGlyphForRecents(self, _cmd, recents);

	NSMutableArray *rebuilt = nil;
	@try {
		rebuilt = [NSMutableArray arrayWithCapacity:[recents count]];
		for (id text in recents){
			if (![text isKindOfClass:[NSString class]] || ![text length])
				continue;
			unsigned short glyph = EKGlyphForString(text);
			if (!glyph)
				continue;
			id emoji = [(Class <EKEmojiFactory>)gEmojiClass emojiWithString:text];
			if (![emoji isKindOfClass:gEmojiClass])
				continue;
			[(id <EKEmojiObject>)emoji setGlyph:glyph];
			[rebuilt addObject:emoji];
		}
	}
	@catch (NSException *exception){
		EKPanic(exception, @"getGlyphForRecents:");
		return gOriginalGlyphForRecents(self, _cmd, recents);
	}

	if (![rebuilt count] && [recents count])
		return gOriginalGlyphForRecents(self, _cmd, recents);
	return rebuilt;
}

static void EKClampPageDots(id scrollView)
{
	NSInteger limit = EKPageDotLimit();
	if (limit <= 0)
		return;

	Ivar slot = class_getInstanceVariable([scrollView class], "_pageControl");
	if (!slot)
		return;
	id control = object_getIvar(scrollView, slot);

	Class pageControl = objc_getClass("UIPageControl");
	if (!pageControl || ![control isKindOfClass:pageControl])
		return;
	if (![control respondsToSelector:@selector(numberOfPages)] ||
		![control respondsToSelector:@selector(setHidden:)])
		return;

	BOOL overflowing = [(id <EKPageControl>)control numberOfPages] > limit;
	[(id <EKPageControl>)control setHidden:overflowing];
}

static void EKLayoutPages(id self, SEL _cmd)
{
	gOriginalLayoutPages(self, _cmd);
	if (gStop)
		return;
	@try {
		EKClampPageDots(self);
	}
	@catch (NSException *exception){
		EKPanic(exception, @"layoutPages");
	}
}

#pragma mark - installation

static BOOL EKInstallCategoryHook(void)
{
	gCategoryClass = objc_getClass("UIKeyboardEmojiCategory");
	gEmojiClass = objc_getClass("UIKeyboardEmoji");
	if (!gCategoryClass || !gEmojiClass){
		EKLog(@"UIKeyboardEmojiCategory/UIKeyboardEmoji missing; doing nothing");
		return NO;
	}

	if (!EKClassMethodIs(gCategoryClass, @selector(categoryForType:), "@", "i")){
		EKLog(@"+categoryForType: has an unexpected signature; doing nothing");
		return NO;
	}
	if (!EKClassMethodIs(gEmojiClass, @selector(emojiWithString:), "@", "@")){
		EKLog(@"+emojiWithString: has an unexpected signature; doing nothing");
		return NO;
	}
	if (!EKInstanceMethodIs(gEmojiClass, @selector(setGlyph:), "v", "S") ||
		!EKInstanceMethodIs(gEmojiClass, @selector(glyph), "S", "") ||
		!EKInstanceMethodIs(gEmojiClass, @selector(emojiString), "@", "")){
		EKLog(@"UIKeyboardEmoji has an unexpected shape; doing nothing");
		return NO;
	}
	if (!EKInstanceMethodIs(gCategoryClass, @selector(emoji), "@", "") ||
		!EKInstanceMethodIs(gCategoryClass, @selector(setEmoji:), "v", "@")){
		EKLog(@"UIKeyboardEmojiCategory has an unexpected shape; doing nothing");
		return NO;
	}

	if (!EKHook(object_getClass(gCategoryClass), @selector(categoryForType:),
				(IMP)EKCategoryForType, &gOriginalCategoryForType)){
		EKLog(@"could not hook +categoryForType:; doing nothing");
		return NO;
	}
	return YES;
}

static void EKInstallRecentsHook(void)
{
	if (!EKHookRecents())
		return;
	if (!EKClassMethodIs(gCategoryClass, @selector(getGlyphForRecents:), "@", "@")){
		EKLog(@"+getGlyphForRecents: has an unexpected signature; leaving it alone");
		return;
	}
	if (!EKHook(object_getClass(gCategoryClass), @selector(getGlyphForRecents:),
				(IMP)EKGlyphForRecents, &gOriginalGlyphForRecents))
		EKLog(@"could not hook +getGlyphForRecents:; leaving it alone");
}

static void EKInstallPageDotsHook(void)
{
	if (!EKHookPageDots() || EKPageDotLimit() <= 0)
		return;

	Class scrollView = objc_getClass("UIKeyboardEmojiScrollView");
	if (!scrollView || !class_getInstanceVariable(scrollView, "_pageControl")){
		EKLog(@"UIKeyboardEmojiScrollView has no _pageControl; leaving it alone");
		return;
	}
	if (!EKInstanceMethodIs(scrollView, @selector(layoutPages), "v", "")){
		EKLog(@"-layoutPages has an unexpected signature; leaving it alone");
		return;
	}
	if (!EKHook(scrollView, @selector(layoutPages), (IMP)(void *)EKLayoutPages,
				&gOriginalLayoutPages))
		EKLog(@"could not hook -layoutPages; leaving it alone");
}

__attribute__((constructor))
static void EKInitialise(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	@try {
		if (!EKEnabled()){
			EKLog(@"switched off");
			[pool drain];
			return;
		}

		EKSetReadyHandler(^{
			BOOL onMain = EKPrepareOnMainThread();
			dispatch_block_t work = ^{
				@try {
					EKPrepareAll();
					EKAppendToExistingCategories();
				}
				@catch (NSException *exception){
					EKPanic(exception, @"palette preparation");
				}
			};
			if (onMain){
				dispatch_async(dispatch_get_main_queue(), work);
				return;
			}
			@try {
				EKPrepareAll();
			}
			@catch (NSException *exception){
				EKPanic(exception, @"palette preparation");
				return;
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				@try {
					EKAppendToExistingCategories();
				}
				@catch (NSException *exception){
					EKPanic(exception, @"deferred append");
				}
			});
		});

		EKResolveSubstrate();
		if (!EKInstallCategoryHook()){
			[pool drain];
			return;
		}

		EKInstallRecentsHook();
		EKInstallPageDotsHook();
		EKLog(@"installed in %@", [[NSProcessInfo processInfo] processName]);
	}
	@catch (NSException *exception){
		gStop = YES;
		EKComplain(@"install raised %@ (%@); no hooks are active",
				   [exception name], [exception reason]);
	}
	[pool drain];
}
