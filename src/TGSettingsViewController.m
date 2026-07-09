#import "TGSettingsViewController.h"
#import "TGClient.h"
#import "TGTheme.h"
#import "TGThemeFile.h"

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

	self.title = @"Settings";
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) return @"Account";
	if (section == 1) return @"Appearance";
	if (section == 2) return @"Telegram themes";
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
	if (section == 1) return 3;   // skeuomorphic / flat / wallpaper
	if (section == 2) return [TGTheme availableThemeFiles].count + 1;   // + "None"
	return 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGSettingsCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
									  reuseIdentifier:reuse];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.textLabel.textColor = [UIColor blackColor];

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

	if (indexPath.section == 1 && indexPath.row == 2){
		cell.textLabel.text = @"Chat wallpaper";
		cell.detailTextLabel.text = [TGTheme shared].wallpaper ? @"Set" : @"None";
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}

	if (indexPath.section == 1){
		BOOL flat = [TGTheme shared].isFlat;
		cell.textLabel.text = (indexPath.row == 0) ? @"Skeuomorphic" : @"Flat";
		cell.detailTextLabel.text = @"";
		cell.accessoryType = ((indexPath.row == 1) == flat)
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
		cell.textLabel.text = @"Clear local cache";
	} else {
		cell.textLabel.text = @"Log out";
		cell.textLabel.textColor = [UIColor colorWithRed:0.8f green:0.1f blue:0.1f alpha:1.0f];
	}
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == 1 && indexPath.row == 2){
		[self chooseWallpaper];
		return;
	}

	if (indexPath.section == 1){
		[TGTheme shared].style = (indexPath.row == 0)
			? TGThemeStyleSkeuomorphic : TGThemeStyleFlat;
		[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];
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

	if (indexPath.section != 3)
		return;

	if (indexPath.row == 0){
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
