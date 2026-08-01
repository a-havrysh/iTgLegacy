#import "TGSettingsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGThemeFile.h"
#import "TGStorageViewController.h"
#import "TGSessionsViewController.h"
#import "TGDeviceViewController.h"
#import "TGDevice.h"
#import "TGEditProfileViewController.h"

@implementation TGSettingsViewController

- (id)init {
	return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	// iOS 7 lays content out under the bars; these screens position their own
	// frames and expect the old behaviour.
	if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)])
		self.edgesForExtendedLayout = UIRectEdgeNone;
	self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
	self.tableView.separatorColor = [[TGTheme shared] separatorColour];

	self.title = @"Settings";
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 5;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) return @"Account";
	if (section == 1) return @"Appearance";
	if (section == 2) return @"Telegram themes";
	if (section == 3) return @"Account";
	return @"Storage";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 2)
		return @"Theme files made for the official clients - .tgios-theme and "
			   @".attheme - are read from the app's Documents folder, or from "
			   @"one received in a chat.";
	if (section != 1)
		return nil;
	return (NSFoundationVersionNumber > 993.00)
		? @"This system shipped flat, so that is the default here."
		: @"This system shipped skeuomorphic, so that is the default here.";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return 1;
	if (section == 1) return 5;   // skeuomorphic / flat / dark / wallpaper / text size
	if (section == 2) return [TGTheme availableThemeFiles].count + 1;   // + "None"
	if (section == 3) return 3;   // edit profile, devices, this device
	return 3;   // storage, clear database, log out
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGSettingsCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:reuse];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.textLabel.textColor = [UIColor blackColor];
	[[TGTheme shared] styleCell:cell];

	if (indexPath.section == 0){
		NSDictionary *me = [TGClient shared].me;
		if (me){
			cell.textLabel.text = [me[@"username"] length]
				? [NSString stringWithFormat:@"@%@", me[@"username"]]
				: me[@"first_name"];
			cell.detailTextLabel.text = [NSString stringWithFormat:@"+%@", me[@"phone"]];
			cell.accessoryType = UITableViewCellAccessoryCheckmark;
		} else {
			cell.textLabel.text = @"Not signed in";
			cell.detailTextLabel.text = @"";
		}
		return cell;
	}

	if (indexPath.section == 1 && indexPath.row == 4){
		cell.textLabel.text = @"Message text size";
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f pt",
				[TGTheme shared].messageFontSize];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}

	if (indexPath.section == 3){
		static NSArray *labels = nil;
		if (!labels) labels = @[@"Edit profile", @"Devices", @"This device"];
		cell.textLabel.text = labels[indexPath.row];
		cell.detailTextLabel.text = indexPath.row == 2 ? [TGDevice tierName] : @"";
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}

	if (indexPath.section == 1 && indexPath.row == 3){
		cell.textLabel.text = @"Chat wallpaper";
		cell.detailTextLabel.text = [TGTheme shared].wallpaper ? @"Set" : @"None";
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}

	if (indexPath.section == 1){
		static NSArray *styles = nil;
		if (!styles) styles = @[@"Skeuomorphic", @"Flat", @"Dark"];
		cell.textLabel.text = styles[indexPath.row];
		cell.detailTextLabel.text = @"";
		cell.accessoryType = (indexPath.row == [TGTheme shared].style)
			? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
		return cell;
	}

	if (indexPath.section == 2){
		NSArray *files = [TGTheme availableThemeFiles];
		NSString *current = [TGTheme shared].importedName;
		if (indexPath.row == 0){
			cell.textLabel.text = @"None";
			cell.detailTextLabel.text = @"";
			cell.accessoryType = current ? UITableViewCellAccessoryNone
										 : UITableViewCellAccessoryCheckmark;
			return cell;
		}
		NSString *path = files[indexPath.row - 1];
		NSString *label = [path.lastPathComponent stringByDeletingPathExtension];
		cell.textLabel.text = label;
		cell.detailTextLabel.text = path.pathExtension;
		cell.accessoryType = [current isEqualToString:label]
				? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
		return cell;
	}

	cell.detailTextLabel.text = @"";
	if (indexPath.row == 0){
		cell.textLabel.text = @"Storage and cache";
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	} else if (indexPath.row == 1){
		cell.textLabel.text = @"Clear local database";
	} else {
		cell.textLabel.text = @"Log out";
		cell.textLabel.textColor = [UIColor colorWithRed:0.8f green:0.1f blue:0.1f alpha:1.0f];
	}
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == 1 && indexPath.row == 3){
		[self chooseWallpaper];
		return;
	}

	if (indexPath.section == 1 && indexPath.row == 4){
		[self chooseTextSize];
		return;
	}

	if (indexPath.section == 3){
		UIViewController *next = nil;
		if (indexPath.row == 0)      next = [[TGEditProfileViewController alloc] init];
		else if (indexPath.row == 1) next = [[TGSessionsViewController alloc] init];
		else                         next = [[TGDeviceViewController alloc] init];
		next.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:next animated:YES];
		return;
	}

	if (indexPath.section == 1){
		[TGTheme shared].style = (TGThemeStyle)indexPath.row;
		[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
		self.tableView.backgroundColor = [[TGTheme shared] listBackgroundColour];
		self.tableView.separatorColor = [[TGTheme shared] separatorColour];
		[tableView reloadData];
		return;
	}

	if (indexPath.section == 2){
		NSArray *files = [TGTheme availableThemeFiles];
		if (indexPath.row == 0){
			[[TGTheme shared] clearImportedTheme];
		} else if (![[TGTheme shared] importThemeAtPath:files[indexPath.row - 1]]){
			UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Theme"
					message:@"This file could not be read as a Telegram theme."
				   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
			[alert show];
		}
		[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
		[tableView reloadData];
		return;
	}

	if (indexPath.section != 4)
		return;

	if (indexPath.row == 0){
		TGStorageViewController *storage = [[TGStorageViewController alloc] init];
		storage.hidesBottomBarWhenPushed = YES;
		[self.navigationController pushViewController:storage animated:YES];
		return;
	}

	if (indexPath.row == 1){
		[[TGClient shared] clearLocalDatabase];
		return;
	}

	// Logging out drops the session, so make it deliberate.
	UIAlertView *confirm = [[UIAlertView alloc]
			initWithTitle:@"Log out"
				  message:@"Sign out of this account on this device?"
				 delegate:self
		cancelButtonTitle:@"Cancel"
		otherButtonTitles:@"Log out", nil];
	[confirm show];
}

/// Four sizes is enough on a 3.5-inch screen; a slider would be finer than
/// the difference it makes.
- (void)chooseTextSize {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Message text size"
													  delegate:self
											 cancelButtonTitle:nil
										destructiveButtonTitle:nil
											 otherButtonTitles:@"13 pt", @"15 pt",
														   @"17 pt", @"19 pt", nil];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
	sheet.tag = 88;
	[sheet showInView:self.view];
}

#pragma mark - wallpaper

- (void)chooseWallpaper {
	if ([TGTheme shared].wallpaper){
		UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Chat wallpaper"
														  delegate:self
												 cancelButtonTitle:nil
											destructiveButtonTitle:@"Remove"
												 otherButtonTitles:@"Choose another", nil];
		sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
		[sheet showInView:self.view];
		return;
	}
	[self presentWallpaperPicker];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index {
	if (index == sheet.cancelButtonIndex)
		return;

	if (sheet.tag == 88){
		[TGTheme shared].messageFontSize = 13.0f + index * 2.0f;
		[self.tableView reloadData];
		return;
	}

	if (index == sheet.destructiveButtonIndex){
		[[TGTheme shared] setWallpaperImage:nil];
		[self.tableView reloadData];
		return;
	}
	[self presentWallpaperPicker];
}

- (void)presentWallpaperPicker {
	if (![UIImagePickerController isSourceTypeAvailable:
			UIImagePickerControllerSourceTypePhotoLibrary])
		return;
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
		didFinishPickingMediaWithInfo:(NSDictionary *)info {
	[picker dismissViewControllerAnimated:YES completion:nil];
	UIImage *image = info[UIImagePickerControllerOriginalImage];
	if (image)
		[[TGTheme shared] setWallpaperImage:image];
	[self.tableView reloadData];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	[picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (buttonIndex == 1)
		[[TGClient shared] logOut];
}

@end

// vim:ft=objc
