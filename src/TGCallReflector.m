#import "TGCallReflector.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>

@interface TGCallReflector ()
@property (nonatomic, strong) NSString *host;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, strong) NSData *peerTag;
@property (nonatomic, assign) int socketHandle;
@property (nonatomic, strong) NSThread *reader;
@property (nonatomic, strong) NSTimer *pinger;
@end

@implementation TGCallReflector {
	struct sockaddr_in _server;
}

- (instancetype)initWithHost:(NSString *)host port:(uint16_t)port peerTag:(NSData *)peerTag {
	if ((self = [super init])){
		_host = host;
		_port = port;
		_peerTag = peerTag;
		_socketHandle = -1;
		// Four random bytes name this side of the call. The reflector uses
		// them to decide which way a packet goes.
		arc4random_buf(&_localTag, sizeof(_localTag));
	}
	return self;
}

/// Twelve bytes from TDLib name the call; the last four name one side of it.
/// Each end announces its four bytes inside a candidate, as a hostname of the
/// form reflector-<server id>-<tag>.reflector, and addresses the other by the
/// four it read there.
- (NSData *)tagFor:(uint32_t)tag {
	if (self.peerTag.length < 16)
		return nil;
	NSMutableData *out = [NSMutableData dataWithBytes:self.peerTag.bytes length:12];
	[out appendBytes:&tag length:4];
	return out;
}

- (BOOL)start {
	if (self.peerTag.length < 16){
		NSLog(@"TGCallReflector: peer tag is %lu bytes", (unsigned long)self.peerTag.length);
		return NO;
	}

	memset(&_server, 0, sizeof(_server));
	_server.sin_family = AF_INET;
	_server.sin_port = htons(self.port);
	if (inet_pton(AF_INET, self.host.UTF8String, &_server.sin_addr) != 1){
		NSLog(@"TGCallReflector: cannot parse %@", self.host);
		return NO;
	}

	self.socketHandle = socket(AF_INET, SOCK_DGRAM, 0);
	if (self.socketHandle < 0){
		NSLog(@"TGCallReflector: no socket");
		return NO;
	}

	NSLog(@"TGCallReflector: %@:%u, our tag %08x", self.host, self.port, self.localTag);

	self.reader = [[NSThread alloc] initWithTarget:self selector:@selector(readLoop) object:nil];
	[self.reader start];

	// The reflector drops a route it has not heard from; the official client
	// pings on the same cadence.
	self.pinger = [NSTimer scheduledTimerWithTimeInterval:0.5
												   target:self
												 selector:@selector(ping)
												 userInfo:nil
												  repeats:YES];
	[self ping];
	return YES;
}

- (void)ping {
	NSData *tag = [self tagFor:self.localTag];
	if (!tag)
		return;

	NSMutableData *packet = [NSMutableData dataWithData:tag];
	uint8_t filler[16];
	memset(filler, 0xFF, sizeof(filler));
	filler[12] = 0xFE;
	[packet appendBytes:filler length:16];

	uint64_t marker = CFSwapInt64HostToBig(123);
	[packet appendBytes:&marker length:8];

	[self send:packet];
}

- (void)sendPayload:(NSData *)payload {
	if (!self.remoteTag){
		NSLog(@"TGCallReflector: the peer's tag is not known yet");
		return;
	}

	NSMutableData *packet = [NSMutableData dataWithData:[self tagFor:self.remoteTag]];
	[packet appendBytes:&_localTag length:4];

	uint32_t size = CFSwapInt32HostToBig((uint32_t)payload.length);
	[packet appendBytes:&size length:4];
	[packet appendData:payload];

	while (packet.length % 4)
		[packet appendBytes:"\0" length:1];

	[self send:packet];
}

- (void)send:(NSData *)packet {
	if (self.socketHandle < 0)
		return;
	sendto(self.socketHandle, packet.bytes, packet.length, 0,
		   (struct sockaddr *)&_server, sizeof(_server));
}

- (void)readLoop {
	uint8_t buffer[2048];
	while (self.socketHandle >= 0){
		ssize_t got = recv(self.socketHandle, buffer, sizeof(buffer), 0);
		if (got <= 0)
			break;

		NSData *packet = [NSData dataWithBytes:buffer length:got];
		dispatch_async(dispatch_get_main_queue(), ^{
			NSLog(@"TGCallReflector: %ld bytes in", (long)got);
			if (self.onPacket)
				self.onPacket(packet);
		});
	}
}

- (void)stop {
	[self.pinger invalidate];
	self.pinger = nil;
	int handle = self.socketHandle;
	self.socketHandle = -1;
	if (handle >= 0)
		close(handle);
}

@end

// vim:ft=objc
