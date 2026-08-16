#import <CoreText/CoreText.h>
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <Foundation/Foundation.h>
#include <stdio.h>

static BOOL DrawnByEmojiFont(CTFontRef font, NSString *text) {
	NSUInteger length = text.length;
	if (length == 0)
		return NO;
	unichar *units = malloc(sizeof(unichar) * length);
	CGGlyph *glyphs = malloc(sizeof(CGGlyph) * length);
	if (!units || !glyphs){
		free(units);
		free(glyphs);
		return NO;
	}
	[text getCharacters:units range:NSMakeRange(0, length)];
	BOOL covered = CTFontGetGlyphsForCharacters(font, units, glyphs, (CFIndex)length);
	free(units);
	free(glyphs);
	return covered;
}

int main(int argc, char *argv[]) {
	@autoreleasepool {
		NSString *out = argc > 1 ? [NSString stringWithUTF8String:argv[1]]
								 : @"/tmp/emojiprobe.png";

		CGFloat probeSize = argc > 2 ? (CGFloat)atof(argv[2]) : 40.0;
		CTFontRef emoji = CTFontCreateWithName(CFSTR("AppleColorEmoji"), probeSize, NULL);
		if (!emoji){
			fprintf(stderr, "no AppleColorEmoji font\n");
			return 1;
		}
		CFStringRef family = CTFontCopyFamilyName(emoji);
		fprintf(stdout, "family: %s\n", [(__bridge NSString *)family UTF8String]);
		CFRelease(family);

		NSArray *samples = @[@"\U0001F604 U+1F604 grin, Unicode 6.0",
							 @"\U0001F602 U+1F602 tears, Unicode 6.0",
							 @"\U0001F923 U+1F923 rofl, Unicode 9.0",
							 @"\U0001F97A U+1F97A pleading, Unicode 11.0",
							 @"\U0001FAE0 U+1FAE0 melting, Unicode 14.0",
							 @"\U0001FAE8 U+1FAE8 shaking, Unicode 15.0",
							 @"\U0001FADB U+1FADB root veg, Unicode 16.0",
							 @"\U0001F1FA\U0001F1E6 flag UA, sequence",
							 @"\U0001F468‍\U0001F469‍\U0001F467 family, ZWJ",
							 @"\U0001F468‍\U0001F4BB technologist, ZWJ",
							 @"\U0001F44D\U0001F3FD thumb, skin tone",
							 @"\U0001F3F4‍\U0001F441 pirate-ish, ZWJ",
							 @"1\uFE0F\u20E3 keycap one"];

		CGFloat width = 640, lineHeight = probeSize + 16;
		CGFloat height = lineHeight * samples.count + 16;
		CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
		CGContextRef ctx = CGBitmapContextCreate(NULL, (size_t)width, (size_t)height, 8, 0,
												 space, kCGImageAlphaPremultipliedFirst);
		CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
		CGContextFillRect(ctx, CGRectMake(0, 0, width, height));

		CTFontRef label = CTFontCreateWithName(CFSTR("Helvetica"), 18.0, NULL);
		CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);

		for (NSUInteger i = 0; i < samples.count; i++){
			NSString *line = samples[i];
			NSString *glyph = [line substringToIndex:[line rangeOfString:@" "].location];
			fprintf(stdout, "%s covered=%s\n", [glyph UTF8String],
					DrawnByEmojiFont(emoji, glyph) ? "yes" : "NO");

			NSMutableAttributedString *rich =
					[[NSMutableAttributedString alloc] initWithString:line];
			[rich addAttribute:(id)kCTFontAttributeName value:(__bridge id)label
						 range:NSMakeRange(0, line.length)];
			NSRange head = [line rangeOfString:glyph];
			if (head.location != NSNotFound)
				[rich addAttribute:(id)kCTFontAttributeName value:(__bridge id)emoji range:head];

			CTLineRef ctLine = CTLineCreateWithAttributedString(
					(__bridge CFAttributedStringRef)rich);
			CGContextSetTextPosition(ctx, 12, height - lineHeight * (i + 1));
			CTLineDraw(ctLine, ctx);
			CFRelease(ctLine);
		}
		CFRelease(label);
		CFRelease(emoji);

		CGImageRef image = CGBitmapContextCreateImage(ctx);
		CFURLRef url = CFURLCreateWithFileSystemPath(NULL, (__bridge CFStringRef)out,
													 kCFURLPOSIXPathStyle, false);
		CGImageDestinationRef sink = CGImageDestinationCreateWithURL(url, kUTTypePNG, 1, NULL);
		CGImageDestinationAddImage(sink, image, NULL);
		BOOL ok = CGImageDestinationFinalize(sink);
		CFRelease(sink);
		CFRelease(url);
		CGImageRelease(image);
		CGContextRelease(ctx);
		CGColorSpaceRelease(space);

		fprintf(stdout, "wrote %s (%s)\n", [out UTF8String], ok ? "ok" : "failed");
		return ok ? 0 : 1;
	}
}
