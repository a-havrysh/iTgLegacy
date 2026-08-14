#import "TGAlertView.h"

static NSInteger TGAlertViewSystemVersionComponent(NSUInteger index)
{
    static NSArray *components = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        components = [[[UIDevice currentDevice] systemVersion] componentsSeparatedByString:@"."];
    });

    if (components == nil || index >= components.count)
        return 0;

    return [[components objectAtIndex:index] integerValue];
}

static NSString *TGAlertViewNormalizedMessage(NSString *title, NSString *message)
{
    if (message == nil)
        return nil;

    if (title == nil && TGAlertViewSystemVersionComponent(0) >= 8 && TGAlertViewSystemVersionComponent(1) < 1)
        return [@"\n" stringByAppendingString:message];

    return message;
}

@interface TGAlertView () <UIAlertViewDelegate>

@property (nonatomic, copy) void (^completionBlock)(bool okButtonPressed);

@end

@implementation TGAlertView

- (id)initWithTitle:(NSString *)title message:(NSString *)message cancelButtonTitle:(NSString *)cancelButtonTitle okButtonTitle:(NSString *)okButtonTitle completionBlock:(void (^)(bool okButtonPressed))completionBlock
{
    return [self initWithTitle:title message:message cancelButtonTitle:cancelButtonTitle otherButtonTitles:okButtonTitle == nil ? nil : [NSArray arrayWithObject:okButtonTitle] completionBlock:completionBlock];
}

- (id)initWithTitle:(NSString *)title message:(NSString *)message cancelButtonTitle:(NSString *)cancelButtonTitle otherButtonTitles:(NSArray *)otherButtonTitles completionBlock:(void (^)(bool okButtonPressed))completionBlock
{
    self = [super initWithTitle:title message:TGAlertViewNormalizedMessage(title, message) delegate:self cancelButtonTitle:cancelButtonTitle otherButtonTitles:nil];
    if (self != nil)
    {
        for (id otherButtonTitle in otherButtonTitles)
        {
            if ([otherButtonTitle isKindOfClass:[NSString class]] && ((NSString *)otherButtonTitle).length != 0)
                [self addButtonWithTitle:otherButtonTitle];
        }

        if (self.numberOfButtons == 0)
            [self addButtonWithTitle:@"OK"];

        _completionBlock = [completionBlock copy];
    }
    return self;
}

- (id)initWithTitle:(NSString *)title message:(NSString *)message delegate:(id)delegate cancelButtonTitle:(NSString *)cancelButtonTitle otherButtonTitles:(NSString *)otherButtonTitles, ...
{
    return [super initWithTitle:title message:TGAlertViewNormalizedMessage(title, message) delegate:delegate cancelButtonTitle:cancelButtonTitle otherButtonTitles:otherButtonTitles, nil];
}

- (void)show
{
    if ([NSThread isMainThread])
        [super show];
    else
    {
        dispatch_async(dispatch_get_main_queue(), ^
        {
            [super show];
        });
    }
}

- (void)invokeCompletionWithResult:(bool)okButtonPressed
{
    void (^block)(bool) = _completionBlock;
    _completionBlock = nil;

    if (block != nil)
        block(okButtonPressed);
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    [self invokeCompletionWithResult:(alertView.cancelButtonIndex < 0 || buttonIndex != alertView.cancelButtonIndex)];
}

- (void)alertViewCancel:(UIAlertView *)alertView
{
    (void)alertView;
    [self invokeCompletionWithResult:false];
}

@end
