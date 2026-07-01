#import "TGForwardPicker.h"
#import "TGClient.h"

@interface TGForwardPicker ()
@property (nonatomic, strong) NSArray *chats;
@end

@implementation TGForwardPicker

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Forward to";
	self.chats = [TGClient shared].chats;
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
			initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
								 target:self action:@selector(cancel)];
}

- (void)cancel {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.chats.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGForwardCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
									  reuseIdentifier:reuse];
	cell.textLabel.text = self.chats[indexPath.row][@"title"];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.onPicked)
		self.onPicked([self.chats[indexPath.row][@"id"] longLongValue]);
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end

// vim:ft=objc
