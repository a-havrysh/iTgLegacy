#import "EKPalette.h"
#import "EKStockTable.h"

#import <objc/runtime.h>
#import <stdarg.h>
#import <stdio.h>

static int gFailures;
static int gChecks;

static void ok(BOOL condition, const char *format, ...)
{
	gChecks++;
	if (!condition)
		gFailures++;
	printf("  %s  ", condition ? "ok  " : "FAIL");
	va_list args;
	va_start(args, format);
	vprintf(format, args);
	va_end(args);
	printf("\n");
}

#pragma mark - stand-ins with the iOS 6.1.3 method shapes

@interface UIKeyboardEmoji : NSObject
{
	NSString *emojiString;
	unsigned short _glyph;
}
+ (id)emojiWithString:(id)string;
@property unsigned short glyph;
@property (retain) NSString *emojiString;
@property (readonly) NSString *key;
@end

@implementation UIKeyboardEmoji

@synthesize glyph = _glyph;
@synthesize emojiString;

+ (id)emojiWithString:(id)string
{
	UIKeyboardEmoji *one = [[[UIKeyboardEmoji alloc] init] autorelease];
	one.emojiString = string;
	return one;
}

- (NSString *)key { return emojiString; }

- (void)dealloc
{
	[emojiString release];
	[super dealloc];
}

@end

static NSMutableArray *gCategories;
static int gBuildCount;

@interface UIKeyboardEmojiCategory : NSObject
{
	int _type;
	NSArray *_emoji;
}
+ (id)categoryForType:(int)type;
+ (id)categories;
+ (id)getGlyphForRecents:(id)recents;
+ (int)numberOfCategories;
@property (retain) NSArray *emoji;
@property int categoryType;
@end

@implementation UIKeyboardEmojiCategory

@synthesize emoji = _emoji;
@synthesize categoryType = _type;

+ (int)numberOfCategories { return 6; }

+ (id)categories
{
	if (!gCategories){
		gCategories = [[NSMutableArray alloc] initWithCapacity:6];
		for (int i = 0; i < 6; i++){
			UIKeyboardEmojiCategory *one =
					[[[UIKeyboardEmojiCategory alloc] init] autorelease];
			one.categoryType = i;
			[gCategories addObject:one];
		}
	}
	return gCategories;
}

+ (id)categoryForType:(int)type
{
	id category = [[self categories] objectAtIndex:type];
	if ([[category emoji] count])
		return category;
	if (type > 5)
		return nil;

	gBuildCount++;
	static unsigned short unmapped = 60000;
	NSMutableArray *built = [NSMutableArray array];
	const char **slot = kEKStock[type];
	for (int i = 0; slot && slot[i]; i++){
		NSString *text = [NSString stringWithUTF8String:slot[i]];
		UIKeyboardEmoji *one = [UIKeyboardEmoji emojiWithString:text];
		unsigned short glyph = EKGlyphForString(text);
		one.glyph = glyph ? glyph : unmapped++;
		[built addObject:one];
	}
	[category setEmoji:built];
	return category;
}

+ (id)getGlyphForRecents:(id)recents
{
	NSMutableArray *built = [NSMutableArray array];
	for (NSString *text in recents){
		UIKeyboardEmoji *one = [UIKeyboardEmoji emojiWithString:text];
		one.glyph = 1;
		[built addObject:one];
	}
	return built;
}

- (void)dealloc
{
	[_emoji release];
	[super dealloc];
}

@end

#pragma mark - checks

static NSUInteger stockCount(int type)
{
	const char **slot = kEKStock[type];
	NSUInteger n = 0;
	while (slot && slot[n])
		n++;
	return n;
}

static void spin(NSTimeInterval seconds)
{
	[[NSRunLoop currentRunLoop] runUntilDate:
			[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static BOOL waitForGrowth(int type, NSUInteger stock)
{
	for (int i = 0; i < 200; i++){
		spin(0.05);
		if ([[[UIKeyboardEmojiCategory categoryForType:type] emoji] count] > stock)
			return YES;
	}
	return NO;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	printf("hook install\n");
	Method hooked = class_getClassMethod([UIKeyboardEmojiCategory class],
										 @selector(categoryForType:));
	ok(hooked != NULL, "+categoryForType: still exists after the constructor ran");

	printf("first call, before the palette is shaped\n");
	NSUInteger stock1 = stockCount(1);
	id people = [UIKeyboardEmojiCategory categoryForType:1];
	ok([[people emoji] count] == stock1,
	   "returns the stock list untouched while the background pass is running");
	ok(gBuildCount == 1, "UIKit's own builder ran exactly once");

	printf("after the background pass finishes\n");
	ok(waitForGrowth(1, stock1), "People grows once the palette is ready");
	NSUInteger grown = [[people emoji] count];
	ok(grown > stock1, "People is %lu entries, was %lu",
	   (unsigned long)grown, (unsigned long)stock1);
	printf("       People %lu -> %lu\n", (unsigned long)stock1,
		   (unsigned long)grown);

	printf("idempotence\n");
	int builds = gBuildCount;
	for (int i = 0; i < 5; i++)
		[UIKeyboardEmojiCategory categoryForType:1];
	ok([[people emoji] count] == grown,
	   "repeated calls do not append a second time");
	ok(gBuildCount == builds && builds <= 5,
	   "UIKit's own builder ran %d times in total, never again after that",
	   builds);

	printf("every category\n");
	for (int type = 1; type <= 5; type++){
		NSUInteger stock = stockCount(type);
		id category = [UIKeyboardEmojiCategory categoryForType:type];
		NSUInteger count = [[category emoji] count];
		printf("       type %d  %lu -> %lu\n", type, (unsigned long)stock,
			   (unsigned long)count);
		ok(count >= stock, "type %d never loses a stock emoji", type);
	}
	id recents = [UIKeyboardEmojiCategory categoryForType:0];
	ok([[recents emoji] count] == 0, "Recents is left alone");

	printf("contents\n");
	NSMutableSet *glyphs = [NSMutableSet set];
	NSMutableSet *strings = [NSMutableSet set];
	NSUInteger zeroGlyphs = 0;
	NSUInteger repeatedGlyphs = 0;
	NSUInteger repeatedStrings = 0;
	for (int type = 1; type <= 5; type++){
		for (UIKeyboardEmoji *one in [[UIKeyboardEmojiCategory categoryForType:type] emoji]){
			NSNumber *glyph = [NSNumber numberWithUnsignedShort:one.glyph];
			if (!one.glyph)
				zeroGlyphs++;
			if ([glyphs containsObject:glyph])
				repeatedGlyphs++;
			if ([strings containsObject:one.emojiString])
				repeatedStrings++;
			[glyphs addObject:glyph];
			[strings addObject:one.emojiString];
		}
	}
	ok(zeroGlyphs == 0, "no cell would draw .notdef");
	ok(repeatedGlyphs == 0, "no glyph appears in two cells");
	ok(repeatedStrings == 0, "no emoji appears in two cells");

	printf("first stock entries keep their position\n");
	NSArray *first = [[UIKeyboardEmojiCategory categoryForType:1] emoji];
	BOOL ordered = YES;
	for (NSUInteger i = 0; i < stock1 && ordered; i++)
		ordered = [[[first objectAtIndex:i] emojiString]
				isEqualToString:[NSString stringWithUTF8String:kEKStock[1][i]]];
	ok(ordered, "the stock emoji are still slots 0..%lu in the original order",
	   (unsigned long)(stock1 - 1));

	printf("recents\n");
	NSArray *rebuilt = [UIKeyboardEmojiCategory getGlyphForRecents:
			[NSArray arrayWithObjects:
					[NSString stringWithUTF8String:kEKStock[1][0]],
					@"\U0001F937\U0001F3FD‍♂️",
					@"\U0001FAF6",
					nil]];
	ok([rebuilt isKindOfClass:[NSArray class]], "returns an array");
	NSUInteger recentZeros = 0;
	for (UIKeyboardEmoji *one in rebuilt){
		if (!one.glyph)
			recentZeros++;
		if (![one.emojiString length])
			recentZeros++;
	}
	ok(recentZeros == 0,
	   "every surviving recent has a real glyph and its full original string");
	printf("       %lu of 3 recents kept\n", (unsigned long)[rebuilt count]);

	NSArray *junk = [UIKeyboardEmojiCategory getGlyphForRecents:
			[NSArray arrayWithObjects:@"￾￿", nil]];
	ok(junk != nil, "undrawable recents fall back to the original implementation");

	NSArray *empty = [UIKeyboardEmojiCategory getGlyphForRecents:[NSArray array]];
	ok([empty isKindOfClass:[NSArray class]] && [empty count] == 0,
	   "an empty recents list stays empty");

	printf("\n%d checks, %d failed\n", gChecks, gFailures);
	[pool drain];
	return gFailures ? 1 : 0;
}
