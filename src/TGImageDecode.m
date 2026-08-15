#import "TGImageDecode.h"
#import <ImageIO/ImageIO.h>

UIImage *TGDecodeThumbnail(NSString *path, CGFloat maxPixelSize) {
	NSURL *url = [NSURL fileURLWithPath:path];
	CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
	if (!src) return nil;
	NSDictionary *opts = @{
		(id)kCGImageSourceCreateThumbnailFromImageAlways : @YES,
		(id)kCGImageSourceThumbnailMaxPixelSize : @(maxPixelSize),
		(id)kCGImageSourceCreateThumbnailWithTransform : @YES,
	};
	CGImageRef cgImage = CGImageSourceCreateThumbnailAtIndex(src, 0, (CFDictionaryRef)opts);
	CFRelease(src);
	if (!cgImage) return nil;
	UIImage *image = [UIImage imageWithCGImage:cgImage];
	CGImageRelease(cgImage);
	return image;
}

UIImage *TGDecodeSquareThumbnail(NSString *path, CGFloat side) {
	UIImage *source = TGDecodeThumbnail(path, side * 2);
	if (!source) return nil;

	CGSize size = source.size;
	CGFloat scale = MAX(side / size.width, side / size.height);
	CGSize scaled = CGSizeMake(size.width * scale, size.height * scale);

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 0.0f);
	[source drawInRect:CGRectMake((side - scaled.width) / 2,
								   (side - scaled.height) / 2,
								   scaled.width, scaled.height)];
	UIImage *square = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return square;
}
