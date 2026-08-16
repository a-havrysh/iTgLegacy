#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <stdio.h>

static double gScale = 0.0;

static double Now(void) {
	if (gScale == 0.0) {
		mach_timebase_info_data_t tb;
		mach_timebase_info(&tb);
		gScale = (double)tb.numer / (double)tb.denom / 1.0e6;
	}
	return (double)mach_absolute_time() * gScale;
}

static double ResidentMB(void) {
	struct task_basic_info info;
	mach_msg_type_number_t count = TASK_BASIC_INFO_COUNT;
	if (task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &count)
		!= KERN_SUCCESS)
		return -1.0;
	return (double)info.resident_size / 1048576.0;
}

static NSString *ModernText(void) {
	unichar buf[] = {
		0x0048, 0x0069, 0x0020, 0xD83D, 0xDC4B, 0xD83C, 0xDFFD, 0x0020,
		0xD83D, 0xDC68, 0x200D, 0xD83D, 0xDC69, 0x200D, 0xD83D, 0xDC67, 0x0020,
		0xD83C, 0xDDFA, 0xD83C, 0xDDE6, 0x0020, 0x0031, 0xFE0F, 0x20E3, 0x0020,
		0xD83D, 0xDE00, 0xD83D, 0xDE02, 0xD83D, 0xDE0D, 0xD83D, 0xDC4D
	};
	return [NSString stringWithCharacters:buf length:sizeof(buf) / sizeof(buf[0])];
}

static NSString *LegacyText(void) {
	unichar buf[] = {
		0x0048, 0x0069, 0x0020, 0xD83D, 0xDE00, 0xD83D, 0xDE02, 0xD83D, 0xDE0D,
		0xD83D, 0xDC4D, 0x0020, 0xD83D, 0xDE0A, 0xD83D, 0xDE1B, 0xD83D, 0xDC4C
	};
	return [NSString stringWithCharacters:buf length:sizeof(buf) / sizeof(buf[0])];
}

static NSString *SampleText(int which) {
	return which == 1 ? LegacyText() : ModernText();
}

int main(int argc, char *argv[]) {
	@autoreleasepool {
		double entry = Now();
		CGFloat size = argc > 1 ? (CGFloat)atof(argv[1]) : 20.0;
		int which = argc > 2 ? atoi(argv[2]) : 0;

		double t0 = Now();
		CTFontRef emoji = CTFontCreateWithName(CFSTR("AppleColorEmoji"), size, NULL);
		if (!emoji) {
			fprintf(stderr, "no AppleColorEmoji font\n");
			return 1;
		}
		unsigned glyphs = (unsigned)CTFontGetGlyphCount(emoji);
		double t1 = Now();

		NSString *text = SampleText(which);
		NSMutableAttributedString *rich =
				[[NSMutableAttributedString alloc] initWithString:text];
		[rich addAttribute:(id)kCTFontAttributeName value:(__bridge id)emoji
					 range:NSMakeRange(0, text.length)];
		CTLineRef line = CTLineCreateWithAttributedString(
				(__bridge CFAttributedStringRef)rich);
		double t2 = Now();

		CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
		CGContextRef ctx = CGBitmapContextCreate(NULL, 512, 64, 8, 0, space,
												 kCGImageAlphaPremultipliedFirst);
		CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
		CGContextSetTextPosition(ctx, 4, 16);
		CTLineDraw(line, ctx);
		double t3 = Now();

		fprintf(stdout, "set=%d glyphs=%u open=%.1f shape=%.1f draw=%.1f "
						"firstdraw=%.1f total=%.1f rss=%.1f\n",
				which, glyphs, t1 - t0, t2 - t1, t3 - t2, t3 - t0, t3 - entry,
				ResidentMB());

		CGContextRelease(ctx);
		CGColorSpaceRelease(space);
		CFRelease(line);
		[rich release];
		CFRelease(emoji);
		return 0;
	}
}
