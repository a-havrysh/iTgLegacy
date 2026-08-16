#import "EKPalette.h"

#import <objc/runtime.h>
#import <stdio.h>

#ifndef EK_FAILSAFE_CASE
#define EK_FAILSAFE_CASE 0
#endif

static int gFailures;

static void ok(BOOL condition, const char *what)
{
	if (!condition)
		gFailures++;
	printf("  %s  %s\n", condition ? "ok  " : "FAIL", what);
}

#if EK_FAILSAFE_CASE == 1 || EK_FAILSAFE_CASE == 2

@interface UIKeyboardEmoji : NSObject
+ (id)emojiWithString:(id)string;
@property (retain) NSString *emojiString;
#if EK_FAILSAFE_CASE == 2
@property unsigned int glyph;
#else
@property unsigned short glyph;
#endif
@end

@implementation UIKeyboardEmoji
@synthesize glyph;
@synthesize emojiString;
+ (id)emojiWithString:(id)string
{
	UIKeyboardEmoji *one = [[[UIKeyboardEmoji alloc] init] autorelease];
	one.emojiString = string;
	return one;
}
@end

static NSMutableArray *gCategories;

@interface UIKeyboardEmojiCategory : NSObject
#if EK_FAILSAFE_CASE == 1
+ (id)categoryForType:(long long)type;
#else
+ (id)categoryForType:(int)type;
#endif
+ (id)categories;
@property (retain) NSArray *emoji;
@end

@implementation UIKeyboardEmojiCategory
@synthesize emoji;

+ (id)categories
{
	if (!gCategories){
		gCategories = [[NSMutableArray alloc] init];
		for (int i = 0; i < 6; i++)
			[gCategories addObject:[[[UIKeyboardEmojiCategory alloc] init] autorelease]];
	}
	return gCategories;
}

#if EK_FAILSAFE_CASE == 1
+ (id)categoryForType:(long long)type
#else
+ (id)categoryForType:(int)type
#endif
{
	id category = [[self categories] objectAtIndex:(NSUInteger)type];
	if ([[category emoji] count])
		return category;
	[category setEmoji:[NSArray arrayWithObjects:@"\U0001F604", @"\U0001F603",
			@"\U0001F600", nil]];
	return category;
}
@end

#endif

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

#if EK_FAILSAFE_CASE == 1
	printf("case 1: +categoryForType: takes a long long, not an int\n");
#elif EK_FAILSAFE_CASE == 2
	printf("case 2: UIKeyboardEmoji.glyph is 32 bits, not 16\n");
#else
	printf("case 3: no UIKeyboardEmojiCategory in this process at all\n");
#endif

#if EK_FAILSAFE_CASE == 1 || EK_FAILSAFE_CASE == 2
	id category = [UIKeyboardEmojiCategory categoryForType:1];
	for (int i = 0; i < 40; i++)
		[[NSRunLoop currentRunLoop] runUntilDate:
				[NSDate dateWithTimeIntervalSinceNow:0.05]];
	[UIKeyboardEmojiCategory categoryForType:1];
	ok([[category emoji] count] == 3,
	   "the palette is exactly what UIKit built, nothing was appended");
	ok([[[category emoji] objectAtIndex:0] isKindOfClass:[NSString class]],
	   "the array UIKit returned was not reshaped");
#else
	ok(objc_getClass("UIKeyboardEmojiCategory") == NULL,
	   "the class really is absent");
	ok(EKEnabled(), "the tweak still loaded and read its preferences");
#endif

	printf("  reached the end of main without crashing\n");
	[pool drain];
	return gFailures ? 1 : 0;
}
