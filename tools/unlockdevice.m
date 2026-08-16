#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>

typedef int (*MKBUnlockDeviceFn)(CFDataRef passcode, CFDictionaryRef options);
typedef int (*MKBGetDeviceLockStateFn)(CFDictionaryRef options);

int main(int argc, char *argv[]) {
	@autoreleasepool {
		if (argc < 2){
			fprintf(stderr, "usage: unlockdevice <passcode>\n");
			return 2;
		}

		void *keybag = dlopen("/System/Library/PrivateFrameworks/MobileKeyBag.framework/MobileKeyBag",
							  RTLD_LAZY);
		if (!keybag){
			fprintf(stderr, "MobileKeyBag not loadable: %s\n", dlerror());
			return 1;
		}

		MKBUnlockDeviceFn unlock = (MKBUnlockDeviceFn)dlsym(keybag, "MKBUnlockDevice");
		MKBGetDeviceLockStateFn state =
				(MKBGetDeviceLockStateFn)dlsym(keybag, "MKBGetDeviceLockState");
		if (!unlock){
			fprintf(stderr, "MKBUnlockDevice missing\n");
			return 1;
		}

		if (state)
			fprintf(stdout, "lock state before: %d\n", state(NULL));

		NSData *passcode = [[NSString stringWithUTF8String:argv[1]]
				dataUsingEncoding:NSUTF8StringEncoding];
		int result = unlock((__bridge CFDataRef)passcode, NULL);
		fprintf(stdout, "MKBUnlockDevice returned %d\n", result);

		if (state)
			fprintf(stdout, "lock state after: %d\n", state(NULL));
		return result == 0 ? 0 : 1;
	}
}
