#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>

static NSArray *ParseSequences(NSString *path, BOOL includeBaseline) {
	NSString *raw = [NSString stringWithContentsOfFile:path
											  encoding:NSUTF8StringEncoding error:NULL];
	if (!raw){
		fprintf(stderr, "cannot read %s\n", [path UTF8String]);
		return nil;
	}

	NSMutableArray *out = [NSMutableArray array];
	NSMutableSet *seen = [NSMutableSet set];

	for (NSString *line in [raw componentsSeparatedByString:@"\n"]){
		if (![line length] || [line hasPrefix:@"#"])
			continue;
		NSRange semi = [line rangeOfString:@";"];
		if (semi.location == NSNotFound)
			continue;

		NSString *codes = [line substringToIndex:semi.location];
		NSString *rest = [line substringFromIndex:semi.location + 1];
		NSRange hash = [rest rangeOfString:@"#"];
		if (hash.location == NSNotFound)
			continue;
		NSString *status = [[rest substringToIndex:hash.location]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (![status isEqualToString:@"fully-qualified"] &&
			![status isEqualToString:@"minimally-qualified"])
			continue;

		NSString *comment = [rest substringFromIndex:hash.location];
		BOOL unicode60 = [comment rangeOfString:@" E0.6 "].location != NSNotFound;
		if (unicode60 && !includeBaseline)
			continue;

		NSMutableArray *scalars = [NSMutableArray array];
		for (NSString *token in [codes componentsSeparatedByCharactersInSet:
				[NSCharacterSet whitespaceCharacterSet]]){
			if (![token length])
				continue;
			unsigned value = 0;
			[[NSScanner scannerWithString:token] scanHexInt:&value];
			if (value != 0xFE0F)
				[scalars addObject:[NSNumber numberWithUnsignedInt:value]];
		}
		if (![scalars count])
			continue;

		BOOL single = [scalars count] == 1;
		BOOL flag = NO;
		if ([scalars count] == 2){
			unsigned a = [[scalars objectAtIndex:0] unsignedIntValue];
			unsigned b = [[scalars objectAtIndex:1] unsignedIntValue];
			flag = a >= 0x1F1E6 && a <= 0x1F1FF && b >= 0x1F1E6 && b <= 0x1F1FF;
		}
		if (!single && !flag)
			continue;

		NSMutableString *key = [NSMutableString string];
		for (NSNumber *scalar in scalars){
			if ([key length])
				[key appendString:@"-"];
			[key appendFormat:@"%x", [scalar unsignedIntValue]];
		}
		if ([seen containsObject:key])
			continue;
		[seen addObject:key];
		[out addObject:[NSArray arrayWithObjects:key, scalars, nil]];
	}
	return out;
}

static NSString *StringForScalars(NSArray *scalars) {
	NSMutableString *text = [NSMutableString string];
	for (NSNumber *scalar in scalars){
		UTF32Char value = [scalar unsignedIntValue];
		unichar units[2];
		NSUInteger count = 1;
		if (value > 0xFFFF){
			value -= 0x10000;
			units[0] = (unichar)(0xD800 + (value >> 10));
			units[1] = (unichar)(0xDC00 + (value & 0x3FF));
			count = 2;
		} else {
			units[0] = (unichar)value;
		}
		[text appendString:[NSString stringWithCharacters:units length:count]];
	}
	return text;
}

static CTLineRef CreateLine(NSString *text, CTFontRef font) {
	CFStringRef keys[1] = {kCTFontAttributeName};
	CFTypeRef values[1] = {font};
	CFDictionaryRef attrs = CFDictionaryCreate(NULL, (const void **)keys,
			(const void **)values, 1, &kCFTypeDictionaryKeyCallBacks,
			&kCFTypeDictionaryValueCallBacks);
	CFAttributedStringRef string = CFAttributedStringCreate(NULL,
			(__bridge CFStringRef)text, attrs);
	CTLineRef line = CTLineCreateWithAttributedString(string);
	CFRelease(string);
	CFRelease(attrs);
	return line;
}

static BOOL FontCoversString(CTFontRef font, NSString *text) {
	NSUInteger length = [text length];
	if (length > 8)
		return NO;
	unichar units[8];
	CGGlyph glyphs[8];
	[text getCharacters:units range:NSMakeRange(0, length)];
	return CTFontGetGlyphsForCharacters(font, units, glyphs, (CFIndex)length);
}

static BOOL WritePNG(CGImageRef image, NSString *path) {
	CGImageDestinationRef sink = CGImageDestinationCreateWithURL(
			(__bridge CFURLRef)[NSURL fileURLWithPath:path], CFSTR("public.png"), 1, NULL);
	if (!sink)
		return NO;
	CGImageDestinationAddImage(sink, image, NULL);
	BOOL ok = CGImageDestinationFinalize(sink);
	CFRelease(sink);
	return ok;
}

static CGImageRef CreateEmojiImage(NSString *text, CGFloat side, NSString *fontName) {
	CGFloat pointSize = side / 1.2f;
	CTFontRef font = CTFontCreateWithName((__bridge CFStringRef)fontName, pointSize, NULL);
	if (!font)
		return NULL;

	CTLineRef probe = CreateLine(text, font);
	CGRect ink = CTLineGetImageBounds(probe, NULL);
	CFRelease(probe);
	if (CGRectIsEmpty(ink)){
		CFRelease(font);
		return NULL;
	}

	CGFloat span = MAX(CGRectGetWidth(ink), CGRectGetHeight(ink));
	if (span > 0.5f){
		CGFloat corrected = pointSize * (side / span) * 0.97f;
		CFRelease(font);
		font = CTFontCreateWithName((__bridge CFStringRef)fontName, corrected, NULL);
	}

	CTLineRef line = CreateLine(text, font);
	ink = CTLineGetImageBounds(line, NULL);

	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	CGContextRef ctx = CGBitmapContextCreate(NULL, (size_t)side, (size_t)side, 8,
			(size_t)side * 4, space, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
	CGColorSpaceRelease(space);
	if (!ctx){
		CFRelease(line);
		CFRelease(font);
		return NULL;
	}

	CGContextSetTextPosition(ctx,
			(side - CGRectGetWidth(ink)) / 2 - CGRectGetMinX(ink),
			(side - CGRectGetHeight(ink)) / 2 - CGRectGetMinY(ink));
	CTLineDraw(line, ctx);

	CGImageRef image = CGBitmapContextCreateImage(ctx);
	CGContextRelease(ctx);
	CFRelease(line);
	CFRelease(font);
	return image;
}

int main(int argc, const char *argv[]) {
	@autoreleasepool {
		if (argc < 4){
			fprintf(stderr, "usage: emojigen <emoji-test.txt> <outdir> <pixels> "
							"[fontName] [--all]\n");
			return 1;
		}

		NSString *source = [NSString stringWithUTF8String:argv[1]];
		NSString *outDir = [NSString stringWithUTF8String:argv[2]];
		CGFloat side = atoi(argv[3]);
		NSString *fontName = argc > 4 && strncmp(argv[4], "--", 2) != 0
				? [NSString stringWithUTF8String:argv[4]] : @"AppleColorEmoji";
		BOOL includeBaseline = NO;
		for (int i = 4; i < argc; i++)
			if (strcmp(argv[i], "--all") == 0)
				includeBaseline = YES;

		NSArray *sequences = ParseSequences(source, includeBaseline);
		if (!sequences)
			return 1;

		[[NSFileManager defaultManager] createDirectoryAtPath:outDir
								  withIntermediateDirectories:YES
												   attributes:nil error:NULL];

		CTFontRef probeFont = CTFontCreateWithName((__bridge CFStringRef)fontName, 32, NULL);
		NSUInteger written = 0, skipped = 0;
		for (NSArray *entry in sequences){
			@autoreleasepool {
				NSString *key = [entry objectAtIndex:0];
				NSString *text = StringForScalars([entry objectAtIndex:1]);
				if (!FontCoversString(probeFont, text)){
					skipped++;
					continue;
				}
				CGImageRef image = CreateEmojiImage(text, side, fontName);
				if (!image){
					skipped++;
					continue;
				}
				NSString *path = [outDir stringByAppendingPathComponent:
						[key stringByAppendingString:@".png"]];
				if (WritePNG(image, path))
					written++;
				else
					skipped++;
				CGImageRelease(image);
			}
		}
		CFRelease(probeFont);
		fprintf(stdout, "wrote %lu, skipped %lu\n", (unsigned long)written,
				(unsigned long)skipped);
	}
	return 0;
}
