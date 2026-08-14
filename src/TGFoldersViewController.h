//
// TGFoldersViewController - chat folder management.
//
// One class, four pages, the way TGSettingsViewController carries its own
// sub-pages: the folder list, the folder editor, the chat picker the editor
// pushes, and the icon picker. Only the first two are meant to be created from
// outside.
//
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, TGFoldersPage) {
	/// The list of folders: create, rename, delete, reorder.
	TGFoldersPageList = 0,
	/// One folder's definition. Set `folderId` first, or leave it 0 to create.
	TGFoldersPageEditor = 1,
	/// Chat multi-selection, pushed by the editor. Internal.
	TGFoldersPageChatPicker = 2,
	/// Folder icon names, pushed by the editor. Internal.
	TGFoldersPageIconPicker = 3
};

@interface TGFoldersViewController : UITableViewController

/// Which page this instance shows. Defaults to TGFoldersPageList, so a plain
/// -init pushed onto a navigation controller gives the folder list.
@property (nonatomic, assign) TGFoldersPage page;

/// Editor only: the folder to edit. 0 (the default) creates a new folder.
/// Set it before the view loads.
@property (nonatomic, assign) NSInteger folderId;

@end
