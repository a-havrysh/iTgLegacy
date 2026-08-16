#import <CoreText/CoreText.h>
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <Foundation/Foundation.h>
#include <stdio.h>

static NSArray *ReadLines(NSString *path) {
	NSString *blob = [NSString stringWithContentsOfFile:path
											   encoding:NSUTF8StringEncoding
												  error:NULL];
	if (!blob)
		return nil;
	NSMutableArray *out = [NSMutableArray array];
	for (NSString *line in [blob componentsSeparatedByString:@"\n"]) {
		if (line.length > 0)
			[out addObject:line];
	}
	return out;
}

static void DescribeLine(CTFontRef emoji, NSString *text, NSUInteger index) {
	NSMutableAttributedString *rich =
			[[NSMutableAttributedString alloc] initWithString:text];
	[rich addAttribute:(id)kCTFontAttributeName value:(__bridge id)emoji
				 range:NSMakeRange(0, text.length)];
	CTLineRef line = CTLineCreateWithAttributedString(
			(__bridge CFAttributedStringRef)rich);
	CFArrayRef runs = CTLineGetGlyphRuns(line);
	CFIndex nruns = CFArrayGetCount(runs);

	NSMutableString *glyphList = [NSMutableString string];
	CFIndex total = 0;
	BOOL foreign = NO;
	for (CFIndex r = 0; r < nruns; r++) {
		CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, r);
		CFDictionaryRef attrs = CTRunGetAttributes(run);
		CTFontRef used = (CTFontRef)CFDictionaryGetValue(attrs, kCTFontAttributeName);
		CFStringRef psname = used ? CTFontCopyPostScriptName(used) : NULL;
		BOOL isEmoji = psname && CFStringCompare(psname, CFSTR("AppleColorEmoji"), 0)
					   == kCFCompareEqualTo;
		if (psname)
			CFRelease(psname);
		if (!isEmoji)
			foreign = YES;
		CFIndex n = CTRunGetGlyphCount(run);
		CGGlyph *glyphs = malloc(sizeof(CGGlyph) * (size_t)n);
		CTRunGetGlyphs(run, CFRangeMake(0, n), glyphs);
		for (CFIndex i = 0; i < n; i++) {
			[glyphList appendFormat:@"%s%u", total == 0 ? "" : ",",
									(unsigned)glyphs[i]];
			total++;
		}
		free(glyphs);
	}
	fprintf(stdout, "%lu\t%ld\t%s\t%s\n", (unsigned long)index, (long)total,
			foreign ? "mixed" : "emoji", [glyphList UTF8String]);
	CFRelease(line);
	[rich release];
}

static void RenderGrid(CTFontRef emoji, NSArray *samples, NSString *out,
					   CGFloat cell, NSUInteger columns) {
	NSUInteger count = samples.count;
	NSUInteger rows = (count + columns - 1) / columns;
	CGFloat width = cell * columns;
	CGFloat height = cell * rows;
	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	CGContextRef ctx = CGBitmapContextCreate(NULL, (size_t)width, (size_t)height, 8, 0,
											 space, kCGImageAlphaPremultipliedFirst);
	CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
	CGContextFillRect(ctx, CGRectMake(0, 0, width, height));
	CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);

	for (NSUInteger i = 0; i < count; i++) {
		NSString *text = samples[i];
		NSMutableAttributedString *rich =
				[[NSMutableAttributedString alloc] initWithString:text];
		[rich addAttribute:(id)kCTFontAttributeName value:(__bridge id)emoji
					 range:NSMakeRange(0, text.length)];
		CTLineRef line = CTLineCreateWithAttributedString(
				(__bridge CFAttributedStringRef)rich);
		NSUInteger col = i % columns, row = i / columns;
		CGContextSetTextPosition(ctx, col * cell + cell * 0.1,
								 height - (row + 1) * cell + cell * 0.25);
		CTLineDraw(line, ctx);
		CFRelease(line);
		[rich release];
	}

	CGImageRef image = CGBitmapContextCreateImage(ctx);
	CFURLRef url = CFURLCreateWithFileSystemPath(NULL, (__bridge CFStringRef)out,
												 kCFURLPOSIXPathStyle, false);
	CGImageDestinationRef sink = CGImageDestinationCreateWithURL(url, kUTTypePNG, 1,
																 NULL);
	CGImageDestinationAddImage(sink, image, NULL);
	CGImageDestinationFinalize(sink);
	CFRelease(sink);
	CFRelease(url);
	CGImageRelease(image);
	CGContextRelease(ctx);
	CGColorSpaceRelease(space);
}

int main(int argc, char *argv[]) {
	@autoreleasepool {
		if (argc < 2) {
			fprintf(stderr, "usage: %s <samples.txt> [out.png] [size] [columns]\n",
					argv[0]);
			return 2;
		}
		NSString *input = [NSString stringWithUTF8String:argv[1]];
		NSString *out = argc > 2 ? [NSString stringWithUTF8String:argv[2]] : nil;
		CGFloat size = argc > 3 ? (CGFloat)atof(argv[3]) : 40.0;
		NSUInteger columns = argc > 4 ? (NSUInteger)atoi(argv[4]) : 16;

		NSArray *samples = ReadLines(input);
		if (!samples) {
			fprintf(stderr, "cannot read %s\n", argv[1]);
			return 1;
		}

		CTFontRef emoji = CTFontCreateWithName(CFSTR("AppleColorEmoji"), size, NULL);
		if (!emoji) {
			fprintf(stderr, "no AppleColorEmoji font\n");
			return 1;
		}
		CFStringRef family = CTFontCopyFamilyName(emoji);
		CFStringRef ps = CTFontCopyPostScriptName(emoji);
		fprintf(stdout, "# family=%s postscript=%s size=%.0f units=%u ascent=%.1f "
						"descent=%.1f leading=%.1f glyphs=%u\n",
				[(__bridge NSString *)family UTF8String],
				[(__bridge NSString *)ps UTF8String], (double)size,
				(unsigned)CTFontGetUnitsPerEm(emoji), CTFontGetAscent(emoji),
				CTFontGetDescent(emoji), CTFontGetLeading(emoji),
				(unsigned)CTFontGetGlyphCount(emoji));
		CFRelease(family);
		CFRelease(ps);

		for (NSUInteger i = 0; i < samples.count; i++)
			DescribeLine(emoji, samples[i], i);

		if (out)
			RenderGrid(emoji, samples, out, size * 1.5, columns);

		CFRelease(emoji);
		return 0;
	}
}
