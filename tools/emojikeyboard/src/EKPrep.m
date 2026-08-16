#import "EKPalette.h"

#import <stdio.h>

int main(int argc, char *argv[])
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	BOOL quiet = argc > 1 && strcmp(argv[1], "-q") == 0;
	int status = 0;

	@try {
		NSDate *started = [NSDate date];
		BOOL built = EKBuildSynchronously();
		double milliseconds = [[NSDate date] timeIntervalSinceDate:started] * 1000.0;

		if (!built){
			fprintf(stderr, "emojipaletteprep: %s\n",
					[EKDescribeState() UTF8String]);
			status = 1;
		} else {
			NSString *reason = nil;
			BOOL wrote = EKWriteGlyphCache(&reason);
			if (!quiet){
				printf("emojipaletteprep: %s\n", [EKDescribeState() UTF8String]);
				for (int type = EK_FIRST_TYPE; type <= EK_LAST_TYPE; type++)
					printf("  type %d  %lu drawable\n", type,
						   (unsigned long)[EKExtrasForType(type) count]);
				printf("  shaped in %.0f ms\n", milliseconds);
			}
			if (wrote){
				if (!quiet)
					printf("  wrote %s\n", [EK_GLYPHS_PATH UTF8String]);
			} else {
				fprintf(stderr, "emojipaletteprep: no glyph cache written (%s)\n",
						[(reason ?: @"unknown reason") UTF8String]);
				status = 2;
			}
		}
	}
	@catch (NSException *exception){
		fprintf(stderr, "emojipaletteprep: %s (%s)\n",
				[[exception name] UTF8String], [[exception reason] UTF8String]);
		status = 3;
	}

	[pool drain];
	return status;
}
