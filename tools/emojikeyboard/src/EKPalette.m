#import "EKPalette.h"

#import <pthread.h>
#import <sys/stat.h>
#import <unistd.h>

#define EK_DATA_FORMAT 1

@implementation EKEntry

@synthesize string = _string;
@synthesize glyph = _glyph;

- (id)initWithString:(NSString *)string glyph:(unsigned short)glyph
{
	self = [super init];
	if (self){
		_string = [string copy];
		_glyph = glyph;
	}
	return self;
}

- (void)dealloc
{
	[_string release];
	[super dealloc];
}

@end

static pthread_mutex_t gLock = PTHREAD_MUTEX_INITIALIZER;

enum {
	EKStateIdle = 0,
	EKStateBuilding,
	EKStateReady,
	EKStateFailed
};

static int gState = EKStateIdle;
static NSMutableDictionary *gExtras;
static NSMutableDictionary *gGlyphByString;
static NSString *gDiagnostic;
static void (^gReadyHandler)(void);

#pragma mark - preferences

static NSDictionary *EKPrefs(void)
{
	static NSDictionary *prefs;
	static BOOL loaded;
	if (loaded)
		return prefs;
	loaded = YES;
	NSDictionary *raw = [NSDictionary dictionaryWithContentsOfFile:@EK_PREFS];
	if ([raw isKindOfClass:[NSDictionary class]])
		prefs = [raw retain];
	return prefs;
}

static BOOL EKFlag(NSString *key, BOOL fallback)
{
	id value = [EKPrefs() objectForKey:key];
	if (![value isKindOfClass:[NSNumber class]])
		return fallback;
	return [value boolValue];
}

static NSInteger EKNumber(NSString *key, NSInteger fallback)
{
	id value = [EKPrefs() objectForKey:key];
	if (![value isKindOfClass:[NSNumber class]])
		return fallback;
	return [value integerValue];
}

BOOL EKEnabled(void)
{
	static BOOL resolved;
	static BOOL enabled;
	if (resolved)
		return enabled;
	resolved = YES;
	if (getenv("EMOJIKEYBOARD_DISABLE")){
		enabled = NO;
		return enabled;
	}
	struct stat st;
	if (stat(EK_ROOT "/disabled", &st) == 0){
		enabled = NO;
		return enabled;
	}
	enabled = EKFlag(@"Enabled", YES);
	return enabled;
}

BOOL EKVerbose(void)      { return EKFlag(@"Verbose", NO); }
BOOL EKHookRecents(void)  { return EKFlag(@"HookRecents", YES); }
BOOL EKHookPageDots(void) { return EKFlag(@"HookPageDots", YES); }
BOOL EKSkinTones(void)    { return EKFlag(@"SkinTones", YES); }

BOOL EKPrepareOnMainThread(void)
{
	return EKFlag(@"PrepareOnMainThread", NO);
}

NSInteger EKPageDotLimit(void)
{
	NSInteger limit = EKNumber(@"PageDotLimit", 14);
	return limit < 0 ? 0 : limit;
}

void EKLog(NSString *format, ...)
{
	if (!EKVerbose())
		return;
	va_list args;
	va_start(args, format);
	NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	NSLog(@"emojikeyboard: %@", line);
	[line release];
}

void EKComplain(NSString *format, ...)
{
	va_list args;
	va_start(args, format);
	NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	NSLog(@"emojikeyboard: %@", line);
	[line release];
}

#pragma mark - font

static CTFontRef EKEmojiFont(void)
{
	static CTFontRef font;
	static BOOL resolved;
	if (resolved)
		return font;
	resolved = YES;

	CTFontRef candidate = CTFontCreateWithName(CFSTR("AppleColorEmoji"), 12.0f, NULL);
	if (!candidate)
		return NULL;

	NSString *family = (NSString *)CTFontCopyFamilyName(candidate);
	BOOL usable = [family isKindOfClass:[NSString class]] &&
			[family rangeOfString:@"Emoji"].location != NSNotFound;
	[family release];

	if (!usable){
		CFRelease(candidate);
		return NULL;
	}
	font = candidate;
	return font;
}

static NSString *EKFontName(CTFontRef font)
{
	if (!font)
		return nil;
	NSString *name = (NSString *)CTFontCopyPostScriptName(font);
	if (![name isKindOfClass:[NSString class]]){
		[name release];
		return nil;
	}
	return [name autorelease];
}

static NSUInteger EKAppendScalar(UTF32Char code, unichar *units)
{
	if (code <= 0xFFFF){
		units[0] = (unichar)code;
		return 1;
	}
	UTF32Char shifted = code - 0x10000;
	units[0] = (unichar)(0xD800 + (shifted >> 10));
	units[1] = (unichar)(0xDC00 + (shifted & 0x3FF));
	return 2;
}

static NSString *EKFontFingerprint(CTFontRef font)
{
	static const UTF32Char probes[] = {
		0x0023, 0x263A, 0x2764, 0x1F600, 0x1F469, 0x1F1FA, 0x1F9D1, 0x1FAE0
	};
	if (!font)
		return @"none";

	NSMutableString *out = [NSMutableString stringWithFormat:@"%@|%ld",
			EKFontName(font) ?: @"?", (long)CTFontGetGlyphCount(font)];
	for (size_t i = 0; i < sizeof(probes) / sizeof(probes[0]); i++){
		unichar units[2] = {0, 0};
		CGGlyph glyphs[2] = {0, 0};
		NSUInteger count = EKAppendScalar(probes[i], units);
		CTFontGetGlyphsForCharacters(font, units, glyphs, (CFIndex)count);
		[out appendFormat:@"|%u", (unsigned)glyphs[0]];
	}
	return out;
}

#pragma mark - glyph resolution

static BOOL EKIsSingleScalar(NSString *string, UTF32Char *scalar)
{
	NSUInteger length = [string length];
	if (length < 1 || length > 2)
		return NO;

	unichar units[2] = {0, 0};
	[string getCharacters:units range:NSMakeRange(0, length)];

	if (length == 1){
		if (units[0] >= 0xD800 && units[0] <= 0xDFFF)
			return NO;
		*scalar = units[0];
		return YES;
	}
	if (units[0] >= 0xD800 && units[0] <= 0xDBFF &&
		units[1] >= 0xDC00 && units[1] <= 0xDFFF){
		*scalar = ((UTF32Char)(units[0] - 0xD800) << 10) +
				(units[1] - 0xDC00) + 0x10000;
		return YES;
	}
	return NO;
}

static BOOL EKHasSkinTone(NSString *string)
{
	NSUInteger length = [string length];
	if (length < 2)
		return NO;
	for (NSUInteger i = 0; i + 1 < length; i++){
		if ([string characterAtIndex:i] != 0xD83C)
			continue;
		unichar low = [string characterAtIndex:i + 1];
		if (low >= 0xDFFB && low <= 0xDFFF)
			return YES;
	}
	return NO;
}

static unsigned short EKShapeSingleGlyph(CTFontRef font, NSString *string)
{
	if (!font || ![string length])
		return 0;

	NSDictionary *attributes = [NSDictionary dictionaryWithObject:(id)font
			forKey:(NSString *)kCTFontAttributeName];
	NSAttributedString *styled = [[NSAttributedString alloc]
			initWithString:string attributes:attributes];
	CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)styled);
	[styled release];
	if (!line)
		return 0;

	unsigned short result = 0;
	if (CTLineGetGlyphCount(line) == 1){
		CFArrayRef runs = CTLineGetGlyphRuns(line);
		if (runs && CFArrayGetCount(runs) == 1){
			CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, 0);
			CFDictionaryRef runAttributes = CTRunGetAttributes(run);
			CTFontRef runFont = runAttributes
					? (CTFontRef)CFDictionaryGetValue(runAttributes, kCTFontAttributeName)
					: NULL;
			NSString *wanted = EKFontName(font);
			NSString *got = EKFontName(runFont);
			if (wanted && got && [wanted isEqualToString:got]){
				CGGlyph glyph = 0;
				const CGGlyph *direct = CTRunGetGlyphsPtr(run);
				if (direct)
					glyph = direct[0];
				else
					CTRunGetGlyphs(run, CFRangeMake(0, 1), &glyph);
				result = (unsigned short)glyph;
			}
		}
	}
	CFRelease(line);
	return result;
}

static unsigned short EKResolveGlyph(CTFontRef font, NSString *string)
{
	if (!font || ![string length])
		return 0;

	UTF32Char scalar = 0;
	if (EKIsSingleScalar(string, &scalar)){
		unichar units[2] = {0, 0};
		CGGlyph glyphs[2] = {0, 0};
		NSUInteger count = EKAppendScalar(scalar, units);
		CTFontGetGlyphsForCharacters(font, units, glyphs, (CFIndex)count);
		return (unsigned short)glyphs[0];
	}
	return EKShapeSingleGlyph(font, string);
}

#pragma mark - stored data

static NSDictionary *EKLoadPlist(NSString *path)
{
	NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:path];
	if (![root isKindOfClass:[NSDictionary class]])
		return nil;
	id format = [root objectForKey:@"format"];
	if (![format isKindOfClass:[NSNumber class]] ||
		[format intValue] != EK_DATA_FORMAT)
		return nil;
	return root;
}

static NSString *EKPaletteStamp(void)
{
	struct stat st;
	if (stat(EK_ROOT "/palette.plist", &st) != 0)
		return nil;
	return [NSString stringWithFormat:@"%lld:%ld", (long long)st.st_size,
			(long)st.st_mtime];
}

static NSArray *EKStringsForType(NSDictionary *root, int type)
{
	id categories = [root objectForKey:@"categories"];
	if (![categories isKindOfClass:[NSDictionary class]])
		return nil;
	id list = [categories objectForKey:[NSString stringWithFormat:@"%d", type]];
	if (![list isKindOfClass:[NSArray class]])
		return nil;
	return list;
}

#pragma mark - publishing

static void EKPublish(int type, NSArray *entries)
{
	pthread_mutex_lock(&gLock);
	if (!gExtras)
		gExtras = [[NSMutableDictionary alloc] initWithCapacity:EK_LAST_TYPE];
	[gExtras setObject:entries forKey:[NSNumber numberWithInt:type]];
	pthread_mutex_unlock(&gLock);
}

static void EKFinish(int state, NSString *diagnostic)
{
	void (^handler)(void) = nil;
	pthread_mutex_lock(&gLock);
	gState = state;
	[gDiagnostic release];
	gDiagnostic = [diagnostic copy];
	handler = [gReadyHandler retain];
	pthread_mutex_unlock(&gLock);

	if (handler && state == EKStateReady)
		handler();
	[handler release];
}

BOOL EKExtrasReady(void)
{
	pthread_mutex_lock(&gLock);
	BOOL ready = gState == EKStateReady;
	pthread_mutex_unlock(&gLock);
	return ready;
}

NSString *EKDescribeState(void)
{
	pthread_mutex_lock(&gLock);
	NSString *diagnostic = [[gDiagnostic retain] autorelease];
	int state = gState;
	NSUInteger count = 0;
	for (id key in gExtras)
		count += [[gExtras objectForKey:key] count];
	pthread_mutex_unlock(&gLock);

	static const char *names[] = {"idle", "building", "ready", "failed"};
	return [NSString stringWithFormat:@"%s, %lu entries%@%@",
			names[state], (unsigned long)count,
			diagnostic ? @", " : @"", diagnostic ?: @""];
}

void EKSetReadyHandler(void (^handler)(void))
{
	void (^copied)(void) = handler ? [handler copy] : nil;
	pthread_mutex_lock(&gLock);
	[gReadyHandler release];
	gReadyHandler = copied;
	pthread_mutex_unlock(&gLock);
}

#pragma mark - cache

static NSArray *EKEntriesFromCache(NSDictionary *bucket, NSMutableSet *usedGlyphs)
{
	id strings = [bucket objectForKey:@"strings"];
	id blob = [bucket objectForKey:@"glyphs"];
	if (![strings isKindOfClass:[NSArray class]] ||
		![blob isKindOfClass:[NSData class]])
		return nil;
	if ([blob length] != [strings count] * sizeof(unsigned short))
		return nil;

	const unsigned short *glyphs = (const unsigned short *)[blob bytes];
	NSMutableArray *entries = [NSMutableArray arrayWithCapacity:[strings count]];
	NSUInteger index = 0;
	for (id string in strings){
		unsigned short glyph = glyphs[index++];
		if (![string isKindOfClass:[NSString class]] || ![string length] || !glyph)
			continue;
		NSNumber *key = [NSNumber numberWithUnsignedShort:glyph];
		if ([usedGlyphs containsObject:key])
			continue;
		[usedGlyphs addObject:key];
		EKEntry *entry = [[EKEntry alloc] initWithString:string glyph:glyph];
		[entries addObject:entry];
		[entry release];
	}
	return entries;
}

static BOOL EKLoadFromCache(CTFontRef font, NSString *paletteStamp)
{
	NSDictionary *root = EKLoadPlist(EK_GLYPHS_PATH);
	if (!root)
		return NO;

	id stamp = [root objectForKey:@"palette"];
	id fingerprint = [root objectForKey:@"font"];
	id tones = [root objectForKey:@"skinTones"];
	if (![stamp isKindOfClass:[NSString class]] ||
		![fingerprint isKindOfClass:[NSString class]] ||
		![tones isKindOfClass:[NSNumber class]])
		return NO;
	if (!paletteStamp || ![stamp isEqualToString:paletteStamp])
		return NO;
	if (![fingerprint isEqualToString:EKFontFingerprint(font)])
		return NO;
	if ([tones boolValue] != EKSkinTones())
		return NO;

	id categories = [root objectForKey:@"categories"];
	if (![categories isKindOfClass:[NSDictionary class]])
		return NO;

	NSMutableSet *usedGlyphs = [NSMutableSet set];
	NSMutableDictionary *staged = [NSMutableDictionary dictionary];
	for (int type = EK_FIRST_TYPE; type <= EK_LAST_TYPE; type++){
		id bucket = [categories objectForKey:[NSString stringWithFormat:@"%d", type]];
		if (![bucket isKindOfClass:[NSDictionary class]])
			return NO;
		NSArray *entries = EKEntriesFromCache(bucket, usedGlyphs);
		if (!entries)
			return NO;
		[staged setObject:entries forKey:[NSNumber numberWithInt:type]];
	}

	for (int type = EK_FIRST_TYPE; type <= EK_LAST_TYPE; type++)
		EKPublish(type, [staged objectForKey:[NSNumber numberWithInt:type]]);
	return YES;
}

BOOL EKWriteGlyphCache(NSString **reason)
{
	NSString *paletteStamp = EKPaletteStamp();
	if (!paletteStamp){
		if (reason) *reason = @"no palette data to stamp";
		return NO;
	}
	if (!EKExtrasReady()){
		if (reason) *reason = @"palette not built";
		return NO;
	}
	if (access(EK_ROOT, W_OK) != 0){
		if (reason) *reason = @"" EK_ROOT " is not writable";
		return NO;
	}

	NSMutableDictionary *categories = [NSMutableDictionary dictionary];
	for (int type = EK_FIRST_TYPE; type <= EK_LAST_TYPE; type++){
		NSArray *entries = EKExtrasForType(type);
		NSMutableArray *strings = [NSMutableArray arrayWithCapacity:[entries count]];
		NSMutableData *blob = [NSMutableData dataWithCapacity:
				[entries count] * sizeof(unsigned short)];
		for (EKEntry *entry in entries){
			[strings addObject:entry.string];
			unsigned short glyph = entry.glyph;
			[blob appendBytes:&glyph length:sizeof(glyph)];
		}
		[categories setObject:[NSDictionary dictionaryWithObjectsAndKeys:
				strings, @"strings", blob, @"glyphs", nil]
					   forKey:[NSString stringWithFormat:@"%d", type]];
	}

	NSDictionary *root = [NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithInt:EK_DATA_FORMAT], @"format",
			paletteStamp, @"palette",
			EKFontFingerprint(EKEmojiFont()), @"font",
			[NSNumber numberWithBool:EKSkinTones()], @"skinTones",
			categories, @"categories",
			nil];

	NSString *temporary = [EK_GLYPHS_PATH stringByAppendingPathExtension:@"part"];
	NSData *encoded = [NSPropertyListSerialization dataFromPropertyList:root
			format:NSPropertyListBinaryFormat_v1_0 errorDescription:NULL];
	if (!encoded){
		if (reason) *reason = @"could not encode the glyph cache";
		return NO;
	}
	if (![encoded writeToFile:temporary atomically:YES]){
		if (reason) *reason = [@"could not write " stringByAppendingString:temporary];
		return NO;
	}
	[[NSFileManager defaultManager] removeItemAtPath:EK_GLYPHS_PATH error:NULL];
	if (![[NSFileManager defaultManager] moveItemAtPath:temporary
												 toPath:EK_GLYPHS_PATH error:NULL]){
		[[NSFileManager defaultManager] removeItemAtPath:temporary error:NULL];
		if (reason) *reason = @"could not install the glyph cache";
		return NO;
	}
	chmod(EK_ROOT "/glyphs.plist", 0644);
	return YES;
}

#pragma mark - building

static NSArray *EKFilterStrings(CTFontRef font, NSArray *strings,
								NSMutableSet *usedGlyphs, BOOL skinTones)
{
	NSMutableArray *entries = [NSMutableArray arrayWithCapacity:[strings count]];
	for (id string in strings){
		if (![string isKindOfClass:[NSString class]] || ![string length])
			continue;
		if (!skinTones && EKHasSkinTone(string))
			continue;
		unsigned short glyph = EKResolveGlyph(font, string);
		if (!glyph)
			continue;
		NSNumber *key = [NSNumber numberWithUnsignedShort:glyph];
		if ([usedGlyphs containsObject:key])
			continue;
		[usedGlyphs addObject:key];
		EKEntry *entry = [[EKEntry alloc] initWithString:string glyph:glyph];
		[entries addObject:entry];
		[entry release];
	}
	return entries;
}

static BOOL EKBuild(void)
{
	CTFontRef font = EKEmojiFont();
	if (!font){
		EKFinish(EKStateFailed, @"no AppleColorEmoji font");
		return NO;
	}

	NSString *paletteStamp = EKPaletteStamp();
	NSDate *started = [NSDate date];

	if (EKLoadFromCache(font, paletteStamp)){
		EKFinish(EKStateReady, [NSString stringWithFormat:@"from cache in %.0f ms",
				[[NSDate date] timeIntervalSinceDate:started] * 1000.0]);
		EKLog(@"palette %@", EKDescribeState());
		return YES;
	}

	NSDictionary *root = EKLoadPlist(EK_PALETTE_PATH);
	if (!root){
		EKFinish(EKStateFailed, @"no usable " EK_ROOT "/palette.plist");
		return NO;
	}

	BOOL skinTones = EKSkinTones();
	NSMutableSet *usedGlyphs = [NSMutableSet setWithCapacity:4096];
	NSUInteger offered = 0;
	NSUInteger kept = 0;

	for (int type = EK_FIRST_TYPE; type <= EK_LAST_TYPE; type++){
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		NSArray *strings = EKStringsForType(root, type);
		NSArray *entries = strings
				? EKFilterStrings(font, strings, usedGlyphs, skinTones)
				: [NSArray array];
		offered += [strings count];
		kept += [entries count];
		EKPublish(type, entries);
		[pool drain];
	}

	double milliseconds = [[NSDate date] timeIntervalSinceDate:started] * 1000.0;
	EKFinish(kept ? EKStateReady : EKStateFailed,
			 [NSString stringWithFormat:@"%lu of %lu drawable, shaped in %.0f ms",
					 (unsigned long)kept, (unsigned long)offered, milliseconds]);
	EKLog(@"palette %@", EKDescribeState());
	return kept > 0;
}

void EKEnsureBuild(void)
{
	pthread_mutex_lock(&gLock);
	BOOL go = gState == EKStateIdle;
	if (go)
		gState = EKStateBuilding;
	pthread_mutex_unlock(&gLock);
	if (!go)
		return;

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		@try {
			EKBuild();
		}
		@catch (NSException *exception){
			EKComplain(@"palette build raised %@: %@ -- staying out of the way",
					   [exception name], [exception reason]);
			EKFinish(EKStateFailed, @"build raised an exception");
		}
		[pool drain];
	});
}

BOOL EKBuildSynchronously(void)
{
	pthread_mutex_lock(&gLock);
	while (gState == EKStateBuilding){
		pthread_mutex_unlock(&gLock);
		usleep(20000);
		pthread_mutex_lock(&gLock);
	}
	BOOL done = gState == EKStateReady;
	if (!done)
		gState = EKStateBuilding;
	pthread_mutex_unlock(&gLock);
	if (done)
		return YES;
	return EKBuild();
}

NSArray *EKExtrasForType(int type)
{
	if (type < EK_FIRST_TYPE || type > EK_LAST_TYPE)
		return nil;

	pthread_mutex_lock(&gLock);
	NSArray *entries = [[[gExtras objectForKey:[NSNumber numberWithInt:type]]
			retain] autorelease];
	BOOL idle = gState == EKStateIdle;
	pthread_mutex_unlock(&gLock);

	if (!entries && idle)
		EKEnsureBuild();
	return entries;
}

unsigned short EKGlyphForString(NSString *string)
{
	if (![string isKindOfClass:[NSString class]] || ![string length])
		return 0;

	pthread_mutex_lock(&gLock);
	NSNumber *known = [[[gGlyphByString objectForKey:string] retain] autorelease];
	pthread_mutex_unlock(&gLock);
	if (known)
		return [known unsignedShortValue];

	unsigned short glyph = EKResolveGlyph(EKEmojiFont(), string);

	pthread_mutex_lock(&gLock);
	if (!gGlyphByString)
		gGlyphByString = [[NSMutableDictionary alloc] initWithCapacity:64];
	if ([gGlyphByString count] < 256)
		[gGlyphByString setObject:[NSNumber numberWithUnsignedShort:glyph]
						   forKey:string];
	pthread_mutex_unlock(&gLock);
	return glyph;
}

void EKCompact(void)
{
	pthread_mutex_lock(&gLock);
	if (gState == EKStateReady){
		[gExtras release];
		gExtras = nil;
	}
	pthread_mutex_unlock(&gLock);
}
