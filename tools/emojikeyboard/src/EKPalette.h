#ifndef EK_PALETTE_H
#define EK_PALETTE_H

#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>

#ifndef EK_ROOT
#define EK_ROOT "/var/lib/emojikeyboard"
#endif

#ifndef EK_PREFS
#define EK_PREFS "/var/mobile/Library/Preferences/com.havrysh.emojikeyboard.plist"
#endif

#define EK_PALETTE_PATH  @EK_ROOT "/palette.plist"
#define EK_GLYPHS_PATH   @EK_ROOT "/glyphs.plist"
#define EK_DISABLE_PATH  @EK_ROOT "/disabled"

#define EK_FIRST_TYPE 1
#define EK_LAST_TYPE  5

@interface EKEntry : NSObject
{
	NSString *_string;
	unsigned short _glyph;
}
@property (nonatomic, readonly) NSString *string;
@property (nonatomic, readonly) unsigned short glyph;
@end

BOOL EKEnabled(void);
BOOL EKVerbose(void);
BOOL EKHookRecents(void);
BOOL EKHookPageDots(void);
BOOL EKSkinTones(void);
BOOL EKPrepareOnMainThread(void);
NSInteger EKPageDotLimit(void);

void EKLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
void EKComplain(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

NSArray *EKExtrasForType(int type);
BOOL EKExtrasReady(void);
void EKEnsureBuild(void);
void EKCompact(void);
unsigned short EKGlyphForString(NSString *string);
void EKSetReadyHandler(void (^handler)(void));

BOOL EKBuildSynchronously(void);
BOOL EKWriteGlyphCache(NSString **reason);
NSString *EKDescribeState(void);

#endif
