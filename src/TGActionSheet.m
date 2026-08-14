#import "TGActionSheet.h"

#import <objc/runtime.h>

@implementation TGActionSheetAction

- (instancetype)initWithTitle:(NSString *)title action:(NSString *)action
{
    return [self initWithTitle:title action:action type:TGActionSheetActionTypeGeneric];
}

- (instancetype)initWithTitle:(NSString *)title action:(NSString *)action type:(TGActionSheetActionType)type
{
    self = [super init];
    if (self != nil)
    {
        _title = title;
        _action = action;
        _type = type;
    }
    return self;
}

@end

@interface TGActionSheet () <UIActionSheetDelegate>
{
    int _replacedIndex;
}

@property (nonatomic, weak) id target;
@property (nonatomic, copy) void (^actionBlock)(id target, NSString *action);
@property (nonatomic, strong) NSArray *actions;

@end

@implementation TGActionSheet

- (instancetype)initWithTitle:(NSString *)title actions:(NSArray *)actions actionBlock:(void (^)(id target, NSString *action))actionBlock target:(id)target
{
    self = [super initWithTitle:title delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    if (self != nil)
    {
        self.delegate = self;
        self.actionSheetStyle = UIActionSheetStyleDefault;

        NSMutableArray *validActions = [[NSMutableArray alloc] init];
        bool hasCancel = false;
        for (id item in actions)
        {
            if (![item isKindOfClass:[TGActionSheetAction class]])
                continue;
            TGActionSheetAction *action = (TGActionSheetAction *)item;
            if (action.title == nil || action.title.length == 0)
                continue;
            if (action.type == TGActionSheetActionTypeCancel)
            {
                if (hasCancel)
                    continue;
                hasCancel = true;
            }
            [validActions addObject:action];
        }

        if (!hasCancel)
        {
            TGActionSheetAction *cancelAction = [[TGActionSheetAction alloc] initWithTitle:NSLocalizedString(@"Common.Cancel", @"Cancel") action:@"cancel" type:TGActionSheetActionTypeCancel];
            if (cancelAction.title == nil || cancelAction.title.length == 0 || [cancelAction.title isEqualToString:@"Common.Cancel"])
                cancelAction.title = @"Cancel";
            [validActions addObject:cancelAction];
        }

        _actions = validActions;

        for (TGActionSheetAction *action in _actions)
        {
            NSInteger buttonIndex = [self addButtonWithTitle:action.title];
            if (action.type == TGActionSheetActionTypeCancel)
                self.cancelButtonIndex = buttonIndex;
            else if (action.type == TGActionSheetActionTypeDestructive)
                self.destructiveButtonIndex = buttonIndex;
        }

        self.actionBlock = actionBlock;
        self.target = target;
        
        _replacedIndex = -1;
    }
    return self;
}

- (void)actionSheet:(UIActionSheet *)__unused actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (_replacedIndex != -1)
        buttonIndex = _replacedIndex;

    if (buttonIndex < 0 || buttonIndex >= (NSInteger)_actions.count)
        return;

    NSString *action = ((TGActionSheetAction *)_actions[buttonIndex]).action;
    if (action == nil)
        return;

    id target = _target;
    if (target == nil)
        return;

    if (_dismissBlock != nil && !_dismissBlock(target, action))
        return;

    if (_actionBlock != nil)
        _actionBlock(target, action);
}

- (void)actionSheetCancel:(UIActionSheet *)__unused actionSheet
{
    if (self.cancelButtonIndex >= 0 && self.cancelButtonIndex < (NSInteger)_actions.count)
        [self actionSheet:self clickedButtonAtIndex:self.cancelButtonIndex];
}

- (void)actionSheet:(UIActionSheet *)__unused actionSheet didDismissWithButtonIndex:(NSInteger)__unused buttonIndex
{
    self.delegate = nil;
    self.actionBlock = nil;
    self.dismissBlock = nil;
    self.target = nil;
}

- (BOOL)canBecomeFirstResponder
{
    return false;
}

- (BOOL)resignFirstResponder
{
    return false;
}

@end
