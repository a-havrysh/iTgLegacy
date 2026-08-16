#import "TGEmoji.h"
#import "AppDelegate.h"

#import <CoreText/CoreText.h>

static NSString *const kTGEmojiKeyAttribute = @"TGEmojiKey";
static const unichar kTGEmojiPlaceholder = 0xFFFC;
static const CGFloat kTGEmojiUnboundedWidth = 100000.0f;

typedef struct {
	CGFloat ascent;
	CGFloat descent;
	CGFloat width;
} TGEmojiBox;

static void TGEmojiBoxRelease(void *ref) {
	free(ref);
}

static CGFloat TGEmojiBoxAscent(void *ref) {
	return ((TGEmojiBox *)ref)->ascent;
}

static CGFloat TGEmojiBoxDescent(void *ref) {
	return ((TGEmojiBox *)ref)->descent;
}

static CGFloat TGEmojiBoxWidth(void *ref) {
	return ((TGEmojiBox *)ref)->width;
}

static BOOL TGEmojiScalarIsCandidate(UTF32Char code) {
	if (code < 0x2000)
		return NO;
	if (code <= 0x3300)
		return YES;
	if (code >= 0xFE00 && code <= 0xFE0F)
		return YES;
	if (code >= 0x1F000 && code <= 0x1FBFF)
		return YES;
	return code >= 0xE0020 && code <= 0xE007F;
}

static BOOL TGEmojiScalarIsPictographic(UTF32Char code) {
	return code >= 0x1F000 && code <= 0x1FBFF;
}

static BOOL TGEmojiScalarIsInvisible(UTF32Char code) {
	if (code == 0x200D || code == 0xFE0E || code == 0xFE0F)
		return YES;
	if (code >= 0x1F3FB && code <= 0x1F3FF)
		return YES;
	return code >= 0xE0020 && code <= 0xE007F;
}

static NSUInteger TGEmojiAppendScalar(UTF32Char code, unichar *units) {
	if (code <= 0xFFFF){
		units[0] = (unichar)code;
		return 1;
	}
	UTF32Char shifted = code - 0x10000;
	units[0] = (unichar)(0xD800 + (shifted >> 10));
	units[1] = (unichar)(0xDC00 + (shifted & 0x3FF));
	return 2;
}

static CTFontRef TGEmojiSystemFont(void) {
	static CTFontRef font = NULL;
	static BOOL resolved = NO;
	if (resolved)
		return font;
	resolved = YES;

	CTFontRef candidate = CTFontCreateWithName(CFSTR("AppleColorEmoji"), 16.0f, NULL);
	if (!candidate)
		return NULL;

	NSString *family = CFBridgingRelease(CTFontCopyFamilyName(candidate));
	unichar probe[2];
	CGGlyph glyphs[2] = {0, 0};
	NSUInteger count = TGEmojiAppendScalar(0x1F604, probe);
	CTFontGetGlyphsForCharacters(candidate, probe, glyphs, (CFIndex)count);
	BOOL usable = [family rangeOfString:@"Emoji"].location != NSNotFound && glyphs[0] != 0;
	if (!usable){
		CFRelease(candidate);
		return NULL;
	}
	font = candidate;
	return font;
}

static BOOL TGEmojiSystemDrawsScalar(UTF32Char code) {
	CTFontRef font = TGEmojiSystemFont();
	if (!font)
		return YES;

	static NSMutableDictionary *cache = nil;
	if (!cache)
		cache = [[NSMutableDictionary alloc] init];
	NSNumber *slot = [NSNumber numberWithUnsignedInt:code];
	NSNumber *known = [cache objectForKey:slot];
	if (known)
		return [known boolValue];

	unichar units[2];
	CGGlyph glyphs[2] = {0, 0};
	NSUInteger count = TGEmojiAppendScalar(code, units);
	CTFontGetGlyphsForCharacters(font, units, glyphs, (CFIndex)count);
	BOOL drawn = glyphs[0] != 0;
	[cache setObject:[NSNumber numberWithBool:drawn] forKey:slot];
	return drawn;
}

static BOOL TGEmojiSystemDrawsPair(UTF32Char first, UTF32Char second) {
	CTFontRef font = TGEmojiSystemFont();
	if (!font)
		return YES;

	static NSMutableDictionary *cache = nil;
	if (!cache)
		cache = [[NSMutableDictionary alloc] init];
	NSNumber *slot = [NSNumber numberWithUnsignedLongLong:
			((unsigned long long)first << 32) | second];
	NSNumber *known = [cache objectForKey:slot];
	if (known)
		return [known boolValue];

	unichar units[4];
	NSUInteger count = TGEmojiAppendScalar(first, units);
	count += TGEmojiAppendScalar(second, units + count);
	NSString *text = [NSString stringWithCharacters:units length:count];
	NSDictionary *attributes = [NSDictionary dictionaryWithObject:(__bridge id)font
			forKey:(__bridge NSString *)kCTFontAttributeName];
	NSAttributedString *string = [[NSAttributedString alloc] initWithString:text
																 attributes:attributes];
	CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)string);
	CFIndex glyphs = line ? CTLineGetGlyphCount(line) : 2;
	if (line)
		CFRelease(line);

	BOOL drawn = glyphs == 1;
	[cache setObject:[NSNumber numberWithBool:drawn] forKey:slot];
	return drawn;
}

static NSString *TGEmojiKeyForScalars(const UTF32Char *scalars, NSUInteger count) {
	if (count == 1)
		return [NSString stringWithFormat:@"%x", (unsigned)scalars[0]];
	return [NSString stringWithFormat:@"%x-%x", (unsigned)scalars[0], (unsigned)scalars[1]];
}

static NSString *TGEmojiDirectory(void) {
	static NSString *path = nil;
	if (!path)
		path = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"emoji"];
	return path;
}

static BOOL TGEmojiHasImage(NSString *key) {
	static NSMutableDictionary *known = nil;
	if (!known)
		known = [[NSMutableDictionary alloc] init];

	NSNumber *cached = [known objectForKey:key];
	if (cached)
		return [cached boolValue];

	NSString *path = [[TGEmojiDirectory() stringByAppendingPathComponent:key]
			stringByAppendingPathExtension:@"png"];
	BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path];
	[known setObject:[NSNumber numberWithBool:exists] forKey:key];
	return exists;
}

static UIImage *TGEmojiImage(NSString *key) {
	static NSCache *cache = nil;
	if (!cache){
		cache = [[NSCache alloc] init];
		[cache setCountLimit:96];
	}
	UIImage *image = [cache objectForKey:key];
	if (image)
		return image;

	NSString *path = [[TGEmojiDirectory() stringByAppendingPathComponent:key]
			stringByAppendingPathExtension:@"png"];
	image = [UIImage imageWithContentsOfFile:path];
	if (image)
		[cache setObject:image forKey:key];
	return image;
}

static NSDictionary *TGEmojiPlainAttributes(UIFont *font, UIColor *colour) {
	id ctFont = CFBridgingRelease(CTFontCreateWithName(
			(__bridge CFStringRef)font.fontName, font.pointSize, NULL));
	UIColor *ink = colour ?: [UIColor blackColor];
	return [NSDictionary dictionaryWithObjectsAndKeys:
			ctFont, (__bridge NSString *)kCTFontAttributeName,
			(__bridge id)ink.CGColor, (__bridge NSString *)kCTForegroundColorAttributeName,
			nil];
}

static NSAttributedString *TGEmojiPlaceholder(NSString *key, UIFont *font,
											  NSDictionary *plain) {
	TGEmojiBox *box = malloc(sizeof(TGEmojiBox));
	if (!box)
		return nil;
	box->ascent = font.ascender;
	box->descent = -font.descender;
	box->width = ceilf(font.ascender - font.descender);

	CTRunDelegateCallbacks callbacks;
	memset(&callbacks, 0, sizeof(callbacks));
	callbacks.version = kCTRunDelegateVersion1;
	callbacks.dealloc = TGEmojiBoxRelease;
	callbacks.getAscent = TGEmojiBoxAscent;
	callbacks.getDescent = TGEmojiBoxDescent;
	callbacks.getWidth = TGEmojiBoxWidth;

	id delegate = CFBridgingRelease(CTRunDelegateCreate(&callbacks, box));
	if (!delegate){
		free(box);
		return nil;
	}

	NSMutableDictionary *attributes = [plain mutableCopy];
	[attributes setObject:(__bridge id)[UIColor clearColor].CGColor
				   forKey:(__bridge NSString *)kCTForegroundColorAttributeName];
	[attributes setObject:delegate
				   forKey:(__bridge NSString *)kCTRunDelegateAttributeName];
	[attributes setObject:key forKey:kTGEmojiKeyAttribute];

	return [[NSAttributedString alloc]
			initWithString:[NSString stringWithCharacters:&kTGEmojiPlaceholder length:1]
				attributes:attributes];
}

static void TGEmojiAppendPlain(NSMutableAttributedString *target, NSString *text,
							   NSUInteger from, NSUInteger to, NSDictionary *attributes) {
	if (to <= from)
		return;
	NSString *piece = [text substringWithRange:NSMakeRange(from, to - from)];
	[target appendAttributedString:[[NSAttributedString alloc] initWithString:piece
																   attributes:attributes]];
}

static BOOL TGEmojiWalk(NSString *text, UIFont *font, UIColor *colour,
						NSMutableArray *paragraphs) {
	NSUInteger length = text.length;
	if (!length)
		return NO;

	unichar stackUnits[256];
	unichar *units = length <= 256 ? stackUnits : malloc(length * sizeof(unichar));
	if (!units)
		return NO;
	[text getCharacters:units range:NSMakeRange(0, length)];

	NSDictionary *plain = paragraphs ? TGEmojiPlainAttributes(font, colour) : nil;
	NSMutableAttributedString *current = paragraphs
			? [[NSMutableAttributedString alloc] init] : nil;
	NSUInteger run = 0;
	BOOL changed = NO;

	NSUInteger i = 0;
	while (i < length){
		unichar high = units[i];
		UTF32Char code = high;
		NSUInteger size = 1;
		if (high >= 0xD800 && high <= 0xDBFF && i + 1 < length &&
			units[i + 1] >= 0xDC00 && units[i + 1] <= 0xDFFF){
			code = ((UTF32Char)(high - 0xD800) << 10) +
					(units[i + 1] - 0xDC00) + 0x10000;
			size = 2;
		}

		if (high == '\n'){
			if (paragraphs){
				TGEmojiAppendPlain(current, text, run, i, plain);
				[paragraphs addObject:current];
				current = [[NSMutableAttributedString alloc] init];
			}
			i += 1;
			run = i;
			continue;
		}

		if (!TGEmojiScalarIsCandidate(code)){
			i += size;
			continue;
		}

		UTF32Char scalars[2] = {code, 0};
		NSUInteger scalarCount = 1;
		NSUInteger end = i + size;
		if (code >= 0x1F1E6 && code <= 0x1F1FF && end + 1 < length &&
			units[end] >= 0xD800 && units[end] <= 0xDBFF){
			UTF32Char next = ((UTF32Char)(units[end] - 0xD800) << 10) +
					(units[end + 1] - 0xDC00) + 0x10000;
			if (next >= 0x1F1E6 && next <= 0x1F1FF){
				scalars[1] = next;
				scalarCount = 2;
				end += 2;
			}
		}

		NSUInteger consumed = end;
		while (consumed < length &&
			   (units[consumed] == 0xFE0F || units[consumed] == 0xFE0E))
			consumed++;

		BOOL drawable = scalarCount == 2
				? TGEmojiSystemDrawsPair(scalars[0], scalars[1])
				: TGEmojiSystemDrawsScalar(code);
		if (drawable){
			i = consumed;
			continue;
		}

		NSString *key = TGEmojiKeyForScalars(scalars, scalarCount);
		BOOL replaceable = TGEmojiHasImage(key);
		if (!replaceable && !TGEmojiScalarIsInvisible(code) &&
			!TGEmojiScalarIsPictographic(code)){
			i = consumed;
			continue;
		}

		changed = YES;
		if (!paragraphs)
			break;

		TGEmojiAppendPlain(current, text, run, i, plain);
		if (replaceable){
			NSAttributedString *slot = TGEmojiPlaceholder(key, font, plain);
			if (slot)
				[current appendAttributedString:slot];
		}
		i = consumed;
		run = i;
	}

	if (paragraphs){
		if (changed){
			TGEmojiAppendPlain(current, text, run, length, plain);
			[paragraphs addObject:current];
		} else {
			[paragraphs removeAllObjects];
		}
	}

	if (units != stackUnits)
		free(units);
	return changed;
}

static BOOL TGEmojiTextCarriesSymbols(NSString *text) {
	CFIndex length = (CFIndex)text.length;
	CFStringInlineBuffer buffer;
	CFStringInitInlineBuffer((__bridge CFStringRef)text, &buffer, CFRangeMake(0, length));
	for (CFIndex i = 0; i < length; i++){
		if (CFStringGetCharacterFromInlineBuffer(&buffer, i) >= 0x2000)
			return YES;
	}
	return NO;
}

BOOL TGEmojiTextNeedsSubstitution(NSString *text) {
	if (!text.length || !TGEmojiSystemFont())
		return NO;
	if (!TGEmojiTextCarriesSymbols(text))
		return NO;
	return TGEmojiWalk(text, nil, nil, nil);
}

static NSArray *TGEmojiBuildLines(NSArray *paragraphs, NSDictionary *plain, CGFloat limit,
								  NSInteger maxLines, CGFloat *widest) {
	NSMutableArray *lines = [NSMutableArray array];
	CGFloat maxWidth = 0;
	if (limit < 1 || limit > kTGEmojiUnboundedWidth)
		limit = kTGEmojiUnboundedWidth;

	NSAttributedString *dots = [[NSAttributedString alloc] initWithString:@"…"
															   attributes:plain];

	for (NSAttributedString *paragraph in paragraphs){
		if (maxLines > 0 && (NSInteger)lines.count >= maxLines)
			break;

		CFIndex length = (CFIndex)paragraph.length;
		if (length == 0){
			CTLineRef empty = CTLineCreateWithAttributedString(
					(__bridge CFAttributedStringRef)paragraph);
			if (empty)
				[lines addObject:CFBridgingRelease(empty)];
			continue;
		}

		CTTypesetterRef setter = CTTypesetterCreateWithAttributedString(
				(__bridge CFAttributedStringRef)paragraph);
		if (!setter)
			continue;

		CFIndex start = 0;
		while (start < length){
			BOOL lastAllowed = maxLines > 0 && (NSInteger)lines.count == maxLines - 1;
			CTLineRef line = NULL;

			if (lastAllowed){
				CTLineRef whole = CTTypesetterCreateLine(setter,
						CFRangeMake(start, length - start));
				CTLineRef token = CTLineCreateWithAttributedString(
						(__bridge CFAttributedStringRef)dots);
				if (whole)
					line = CTLineCreateTruncatedLine(whole, limit,
							kCTLineTruncationEnd, token);
				if (!line && whole)
					line = (CTLineRef)CFRetain(whole);
				if (whole)
					CFRelease(whole);
				if (token)
					CFRelease(token);
				start = length;
			} else {
				CFIndex count = CTTypesetterSuggestLineBreak(setter, start, limit);
				if (count < 1)
					break;
				line = CTTypesetterCreateLine(setter, CFRangeMake(start, count));
				start += count;
			}

			if (!line)
				break;
			CGFloat width = (CGFloat)CTLineGetTypographicBounds(line, NULL, NULL, NULL);
			if (width > maxWidth)
				maxWidth = width;
			[lines addObject:CFBridgingRelease(line)];

			if (maxLines > 0 && (NSInteger)lines.count >= maxLines)
				break;
		}
		CFRelease(setter);
	}

	if (widest)
		*widest = maxWidth;
	return lines;
}

static CGSize TGEmojiMeasure(NSString *text, UIFont *font, CGSize limit,
							 NSLineBreakMode mode, NSInteger maxLines) {
	TGWaitForTextWarm();
	if (!TGEmojiTextNeedsSubstitution(text))
		return [text sizeWithFont:font constrainedToSize:limit lineBreakMode:mode];

	NSMutableArray *paragraphs = [NSMutableArray array];
	if (!TGEmojiWalk(text, font, [UIColor blackColor], paragraphs) || !paragraphs.count)
		return [text sizeWithFont:font constrainedToSize:limit lineBreakMode:mode];

	CGFloat widest = 0;
	NSDictionary *plain = TGEmojiPlainAttributes(font, [UIColor blackColor]);
	NSArray *lines = TGEmojiBuildLines(paragraphs, plain, limit.width, maxLines, &widest);
	CGFloat height = lines.count * font.lineHeight;
	if (limit.width > 0 && widest > limit.width)
		widest = limit.width;
	if (limit.height > 0 && height > limit.height)
		height = limit.height;
	return CGSizeMake(ceilf(widest), ceilf(height));
}

CGSize TGEmojiTextSize(NSString *text, UIFont *font, CGSize limit,
					   NSLineBreakMode mode, NSInteger maxLines) {
	if (!text.length)
		return CGSizeZero;

	static NSCache *measured = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		measured = [[NSCache alloc] init];
		[measured setCountLimit:512];
	});

	NSString *key = [[NSString alloc] initWithFormat:@"%@\n%@|%.1f|%.1f|%.1f|%d|%ld",
			text, font.fontName, font.pointSize, limit.width, limit.height,
			(int)mode, (long)maxLines];
	NSValue *hit = [measured objectForKey:key];
	if (hit)
		return [hit CGSizeValue];

	CGSize size = TGEmojiMeasure(text, font, limit, mode, maxLines);
	[measured setObject:[NSValue valueWithCGSize:size] forKey:key];
	return size;
}

void TGEmojiTextDraw(NSString *text, UIFont *font, UIColor *colour, CGRect rect,
					 NSTextAlignment alignment, NSInteger maxLines) {
	CGContextRef context = UIGraphicsGetCurrentContext();
	if (!context || rect.size.width < 1 || rect.size.height < 1)
		return;

	NSMutableArray *paragraphs = [NSMutableArray array];
	if (!TGEmojiWalk(text, font, colour, paragraphs) || !paragraphs.count){
		[colour set];
		[text drawInRect:rect withFont:font lineBreakMode:NSLineBreakByWordWrapping];
		return;
	}

	CGFloat widest = 0;
	NSDictionary *plain = TGEmojiPlainAttributes(font, colour);
	NSArray *lines = TGEmojiBuildLines(paragraphs, plain, rect.size.width, maxLines, &widest);
	if (!lines.count)
		return;

	CGFloat lineHeight = font.lineHeight;
	CGFloat total = lines.count * lineHeight;
	CGFloat top = rect.origin.y + floorf((rect.size.height - total) / 2);
	if (top < rect.origin.y)
		top = rect.origin.y;

	CGContextSaveGState(context);
	CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
	CGContextTranslateCTM(context, 0, rect.origin.y + rect.size.height);
	CGContextScaleCTM(context, 1, -1);
	CGContextSetTextMatrix(context, CGAffineTransformIdentity);
	CGFloat base = rect.origin.y + rect.size.height;

	for (NSUInteger index = 0; index < lines.count; index++){
		CTLineRef line = (__bridge CTLineRef)[lines objectAtIndex:index];
		CGFloat width = (CGFloat)CTLineGetTypographicBounds(line, NULL, NULL, NULL);
		CGFloat x = rect.origin.x;
		if (alignment == NSTextAlignmentCenter)
			x += floorf((rect.size.width - width) / 2);
		else if (alignment == NSTextAlignmentRight)
			x += rect.size.width - width;
		if (x < rect.origin.x)
			x = rect.origin.x;

		CGFloat baseline = base - (top + index * lineHeight + font.ascender);
		CGContextSetTextPosition(context, x, baseline);
		CTLineDraw(line, context);

		CFArrayRef runs = CTLineGetGlyphRuns(line);
		CFIndex runCount = runs ? CFArrayGetCount(runs) : 0;
		for (CFIndex slot = 0; slot < runCount; slot++){
			CTRunRef glyphRun = (CTRunRef)CFArrayGetValueAtIndex(runs, slot);
			NSDictionary *attributes = (__bridge NSDictionary *)CTRunGetAttributes(glyphRun);
			NSString *key = [attributes objectForKey:kTGEmojiKeyAttribute];
			if (!key)
				continue;

			UIImage *image = TGEmojiImage(key);
			if (!image)
				continue;

			CGPoint position = CGPointZero;
			CTRunGetPositions(glyphRun, CFRangeMake(0, 1), &position);
			CGFloat ascent = 0, descent = 0;
			CGFloat advance = (CGFloat)CTRunGetTypographicBounds(glyphRun,
					CFRangeMake(0, 1), &ascent, &descent, NULL);
			CGRect box = CGRectMake(x + position.x, baseline - descent, advance,
									ascent + descent);
			CGContextDrawImage(context, box, image.CGImage);
		}
	}

	CGContextRestoreGState(context);
}

@implementation TGEmojiLabel

- (void)drawTextInRect:(CGRect)rect {
	NSString *text = self.text;
	if (!TGEmojiTextNeedsSubstitution(text)){
		[super drawTextInRect:rect];
		return;
	}

	UIColor *ink = self.highlighted && self.highlightedTextColor
			? self.highlightedTextColor : self.textColor;
	CGContextRef context = UIGraphicsGetCurrentContext();
	if (context)
		CGContextSaveGState(context);
	if (context && self.shadowColor)
		CGContextSetShadowWithColor(context, self.shadowOffset, 0, self.shadowColor.CGColor);

	TGEmojiTextDraw(text, self.font, ink ?: [UIColor blackColor], self.bounds,
					self.textAlignment, self.numberOfLines);

	if (context)
		CGContextRestoreGState(context);
}

- (CGSize)sizeThatFits:(CGSize)size {
	if (!TGEmojiTextNeedsSubstitution(self.text))
		return [super sizeThatFits:size];
	return TGEmojiTextSize(self.text, self.font, size, self.lineBreakMode,
						   self.numberOfLines);
}

@end
