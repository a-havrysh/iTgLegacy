#import "TGImageDecode.h"
#import <ImageIO/ImageIO.h>
#import "AppDelegate.h"

UIImage *TGDecodeThumbnail(NSString *path, CGFloat maxPixelSize) {
	NSURL *url = [NSURL fileURLWithPath:path];
	NSDictionary *sourceOpts = @{ (id)kCGImageSourceShouldCache : @NO };
	CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, (CFDictionaryRef)sourceOpts);
	if (!src) return nil;
	NSDictionary *opts = @{
		(id)kCGImageSourceCreateThumbnailFromImageAlways : @YES,
		(id)kCGImageSourceThumbnailMaxPixelSize : @(maxPixelSize),
		(id)kCGImageSourceCreateThumbnailWithTransform : @YES,
		(id)kCGImageSourceShouldCache : @NO,
	};
	CGImageRef cgImage = CGImageSourceCreateThumbnailAtIndex(src, 0, (CFDictionaryRef)opts);
	CFRelease(src);
	if (!cgImage) return nil;
	UIImage *image = [UIImage imageWithCGImage:cgImage];
	if (TGPerfLogging())
		NSLog(@"PERF decode %@ max=%d -> %dx%d %.0f KB %@",
				[path lastPathComponent], (int)maxPixelSize,
				(int)CGImageGetWidth(cgImage), (int)CGImageGetHeight(cgImage),
				CGImageGetHeight(cgImage) * CGImageGetBytesPerRow(cgImage) / 1024.0,
				[NSThread isMainThread] ? @"MAINTHREAD" : @"bg");
	CGImageRelease(cgImage);
	return image;
}

dispatch_queue_t TGImageDecodeQueue(void) {
	static dispatch_queue_t queue = NULL;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		queue = dispatch_queue_create("tg.image.decode", DISPATCH_QUEUE_SERIAL);
	});
	return queue;
}

NSUInteger TGImageBitmapBytes(UIImage *image) {
	CGImageRef cg = image.CGImage;
	if (!cg)
		return 0;
	return (NSUInteger)(CGImageGetHeight(cg) * CGImageGetBytesPerRow(cg));
}

UIImage *TGImageWithinPixelLimit(UIImage *image, CGFloat maxPixelSize) {
	if (!image || maxPixelSize < 1)
		return image;
	CGFloat scale = image.scale > 0 ? image.scale : 1.0f;
	CGFloat w = image.size.width * scale;
	CGFloat h = image.size.height * scale;
	if (w < 1 || h < 1)
		return image;
	CGFloat shrink = MIN(maxPixelSize / w, maxPixelSize / h);
	if (shrink >= 1.0f)
		return image;

	CGSize points = CGSizeMake(MAX(1.0f, floorf(w * shrink)),
							   MAX(1.0f, floorf(h * shrink)));
	UIGraphicsBeginImageContextWithOptions(points, NO, 1.0f);
	[image drawInRect:CGRectMake(0, 0, points.width, points.height)];
	UIImage *smaller = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return smaller ?: image;
}

UIImage *TGDecodeSquareThumbnail(NSString *path, CGFloat side) {
	UIImage *square = nil;
	@autoreleasepool {
		UIImage *source = TGDecodeThumbnail(path, side * 2);
		if (!source) return nil;

		CGSize size = source.size;
		CGFloat scale = MAX(side / size.width, side / size.height);
		CGSize scaled = CGSizeMake(size.width * scale, size.height * scale);

		UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0.0f);
		[source drawInRect:CGRectMake((side - scaled.width) / 2,
									   (side - scaled.height) / 2,
									   scaled.width, scaled.height)];
		square = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
	}
	return square;
}
