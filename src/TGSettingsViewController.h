//
// TGSettingsViewController - account and maintenance, on TDLib only.
//
// Replaces ConfigViewController, whose entries called into libtg's database
// helpers directly.
//
// One flat table held everything, which is not how Telegram arranges it: the
// root is a short list of doors, and the settings themselves live behind them.
// The same class draws each page, because they differ only in their rows.
//
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, TGSettingsPage) {
	TGSettingsPageRoot = 0,
	TGSettingsPageAppearance,
	TGSettingsPageData,
	TGSettingsPageNotifications,
	TGSettingsPagePrivacy,
	TGSettingsPageLanguage,
	TGSettingsPageBlocked
};

@interface TGSettingsViewController : UITableViewController

/// Root unless set before the view loads.
@property (nonatomic, assign) TGSettingsPage page;

@end
