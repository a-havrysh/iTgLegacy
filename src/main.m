/**
 * main.m - entry point.
 *
 * LC_MAIN's entryoff must carry the Thumb bit or iOS 7.1.2 dyld enters this
 * function in ARM mode and executes the prologue as garbage. The linker does
 * not set it; tools/machofix.c does, after every link.
 */
#import <UIKit/UIKit.h>
#import "AppDelegate.h"

/// Runs when dyld has finished with this image and before main, so the gap
/// between it and the kernel's fork time is everything the app cannot see:
/// exec, mapping a 7 MB Mach-O, signature validation, dyld itself.
static NSTimeInterval TGImageReadyAt = 0;

__attribute__((constructor)) static void tgNoteImageReady(void) {
	TGImageReadyAt = [NSDate timeIntervalSinceReferenceDate];
}

int main(int argc, char *argv[])
{
	@autoreleasepool {
		TGRedirectLogToFile();
		TGNoteImageReady(TGImageReadyAt);
		TGMarkLaunchStage(@"main");
		return UIApplicationMain(argc, argv, nil,
				NSStringFromClass([AppDelegate class]));
	}
}

// vim:ft=objc
