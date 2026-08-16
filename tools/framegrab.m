#import <UIKit/UIKit.h>
#import <mach/mach_time.h>
#include <sys/time.h>

CGImageRef UIGetScreenImage(void);

static double TGNow(void) {
	static double scale = 0;
	if (scale == 0){
		mach_timebase_info_data_t info;
		mach_timebase_info(&info);
		scale = (double)info.numer / (double)info.denom / 1e6;
	}
	return mach_absolute_time() * scale;
}

int main(int argc, char *argv[]) {
	@autoreleasepool {
		const char *prefix = argc > 1 ? argv[1] : "/tmp/fg";
		int count = argc > 2 ? atoi(argv[2]) : 16;
		int delayMs = argc > 3 ? atoi(argv[3]) : 0;
		double startDelay = argc > 4 ? atof(argv[4]) : 0;
		int divisor = argc > 5 ? atoi(argv[5]) : 1;
		const char *trigger = argc > 6 ? argv[6] : NULL;
		if (count < 1) count = 1;
		if (count > 96) count = 96;
		if (divisor < 1) divisor = 1;

		CGImageRef warm = UIGetScreenImage();
		if (warm)
			CGImageRelease(warm);
		printf("warm frame done\n");
		fflush(stdout);

		if (startDelay > 0)
			usleep((useconds_t)(startDelay * 1000000));

		if (trigger){
			pid_t child = fork();
			if (child == 0){
				execl("/bin/sh", "sh", "-c", trigger, (char *)NULL);
				_exit(127);
			}
		}

		CGImageRef *frames = calloc(count, sizeof(CGImageRef));
		double *stamps = calloc(count, sizeof(double));
		double *walls = calloc(count, sizeof(double));
		double base = TGNow();
		int got = 0;
		for (int i = 0; i < count; i++){
			double at = TGNow();
			struct timeval wall;
			gettimeofday(&wall, NULL);
			CGImageRef image = UIGetScreenImage();
			if (!image)
				continue;
			if (divisor > 1){
				size_t w = CGImageGetWidth(image) / divisor;
				size_t h = CGImageGetHeight(image) / divisor;
				CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
				CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w * 4, space,
						kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
				CGColorSpaceRelease(space);
				if (ctx){
					CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
					CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), image);
					CGImageRef small = CGBitmapContextCreateImage(ctx);
					CGContextRelease(ctx);
					CGImageRelease(image);
					image = small;
				}
			}
			frames[got] = image;
			stamps[got] = at - base;
			walls[got] = wall.tv_sec + wall.tv_usec / 1e6;
			got++;
			if (delayMs > 0)
				usleep(delayMs * 1000);
		}

		printf("captured %d frames over %.0f ms\n", got, TGNow() - base);
		for (int i = 0; i < got; i++){
			@autoreleasepool {
				NSString *path = [NSString stringWithFormat:@"%s_%02d.png", prefix, i];
				UIImage *shot = [UIImage imageWithCGImage:frames[i]];
				NSData *png = UIImagePNGRepresentation(shot);
				[png writeToFile:path atomically:NO];
				CGImageRelease(frames[i]);
				time_t seconds = (time_t)walls[i];
				struct tm parts;
				localtime_r(&seconds, &parts);
				printf("frame %02d at +%.0f ms wall %02d:%02d:%02d.%03d -> %s\n",
						i, stamps[i], parts.tm_hour, parts.tm_min, parts.tm_sec,
						(int)((walls[i] - seconds) * 1000), path.UTF8String);
			}
		}
		free(frames);
		free(stamps);
		return 0;
	}
}
