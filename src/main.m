/**
 * main.m - entry point.
 *
 * LC_MAIN's entryoff must carry the Thumb bit or iOS 7.1.2 dyld enters this
 * function in ARM mode and executes the prologue as garbage. The linker does
 * not set it; tools/machofix.c does, after every link.
 */
#import <UIKit/UIKit.h>
#import "AppDelegate.h"

int main(int argc, char *argv[])
{
	@autoreleasepool {
		return UIApplicationMain(argc, argv, nil,
				NSStringFromClass([AppDelegate class]));
	}
}

// vim:ft=objc
