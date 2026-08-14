#import "TGActionTableView.h"
#include "UIKit/UIKit.h"
#include "Foundation/Foundation.h"

//#import "TGViewController.h"

//#import "TGHacks.h"

@interface TGActionTableView () <UIGestureRecognizerDelegate>
{
    bool _shouldHackHeaderSize;
    bool _swipeActionsEnabled;
}

@property (nonatomic) bool ignoreTouches;

@end

@implementation TGActionTableView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
    {
    }
    return self;
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    if (!editing)
    {
        if (_actionCell != nil)
        {
            if ([_actionCell conformsToProtocol:@protocol(TGActionTableViewCell)])
                [(id<TGActionTableViewCell>)_actionCell dismissEditingControls:true];
            self.actionCell = nil;

            _ignoreTouches = false;

            id delegate = self.delegate;
            if ([delegate conformsToProtocol:@protocol(TGActionTableViewDelegate)])
                [(id<TGActionTableViewDelegate>)delegate dismissEditingControls];
        }
    }
    
    [super setEditing:editing animated:animated];
}

- (BOOL)touchesShouldCancelInContentView:(UIView *)__unused view
{
    return true;
}

- (void)setActionCell:(UITableViewCell *)actionCell
{
    _actionCell = actionCell;
    
    if (actionCell != nil)
        self.scrollEnabled = false;
    else
        self.scrollEnabled = true;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    if (self.hidden || self.alpha < 0.01f || !self.userInteractionEnabled)
        return nil;

    if (!([self pointInside:point withEvent:event]))
        return nil;

    bool isTouchEvent = (event == nil || event.type == UIEventTypeTouches);

    if (_actionCell != nil && _actionCell.superview == nil)
    {
        _actionCell = nil;
        self.scrollEnabled = true;
    }

    if (_actionCell != nil && isTouchEvent)
    {
        UIView *buttonHitTest = [_actionCell hitTest:CGPointMake(point.x - _actionCell.frame.origin.x, point.y - _actionCell.frame.origin.y) withEvent:event];
        if ([buttonHitTest isKindOfClass:[UIButton class]])
            return buttonHitTest;
        else
        {
            if ([_actionCell conformsToProtocol:@protocol(TGActionTableViewCell)])
                [(id<TGActionTableViewCell>)_actionCell dismissEditingControls:true];
            self.actionCell = nil;
            _ignoreTouches = true;
            
            id delegate = self.delegate;
            if ([delegate conformsToProtocol:@protocol(TGActionTableViewDelegate)])
            {
                [(id<TGActionTableViewDelegate>)delegate dismissEditingControls];
            }
        }
        
        return self;
    }
    else if (_ignoreTouches && event != nil && event.type == UIEventTypeTouches)
        return self;
    
    UIView *result = [super hitTest:point withEvent:event];
    
    if ([result isKindOfClass:[UIButton class]])
    {
        self.delaysContentTouches = false;
    }
    else
    {
        self.delaysContentTouches = true;
    }
    
    return result;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    if (!_ignoreTouches)
        [super touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    if (!_ignoreTouches)
        [super touchesMoved:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    if (_ignoreTouches)
        _ignoreTouches = false;
    else
        [super touchesCancelled:touches withEvent:event];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    if (_ignoreTouches)
        _ignoreTouches = false;
    else
    {
        [super touchesEnded:touches withEvent:event];
        
        if (self.delegate != nil && [self.delegate respondsToSelector:@selector(touchedTableBackground)])
            [self.delegate performSelector:@selector(touchedTableBackground)];
    }
}

- (void)enableSwipeToLeftAction
{
    if (_swipeActionsEnabled)
        return;
    _swipeActionsEnabled = true;

    UISwipeGestureRecognizer *rightSwipeRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(tableViewSwipedRight:)];
    rightSwipeRecognizer.direction = UISwipeGestureRecognizerDirectionRight;
    [self addGestureRecognizer:rightSwipeRecognizer];
    rightSwipeRecognizer.delegate = self;

    UISwipeGestureRecognizer *leftSwipeRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(tableViewSwipedLeft:)];
    leftSwipeRecognizer.direction = UISwipeGestureRecognizerDirectionLeft;
    [self addGestureRecognizer:leftSwipeRecognizer];
    leftSwipeRecognizer.delegate = self;
}

- (void)tableViewSwipedRight:(UISwipeGestureRecognizer *)recognizer
{
    if (recognizer.state == UIGestureRecognizerStateRecognized)
    {
        id delegate = self.delegate;
        if ([delegate respondsToSelector:@selector(performSwipeToRightAction)])
            [delegate performSwipeToRightAction];
    }
}

- (void)tableViewSwipedLeft:(UISwipeGestureRecognizer *)recognizer
{
    if (recognizer.state == UIGestureRecognizerStateRecognized)
    {
        id delegate = self.delegate;
        if ([delegate respondsToSelector:@selector(performSwipeToLeftAction)])
            [delegate performSwipeToLeftAction];
    }
}


- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    if (![gestureRecognizer isKindOfClass:[UISwipeGestureRecognizer class]])
    {
        if ([[UITableView class] instancesRespondToSelector:@selector(gestureRecognizerShouldBegin:)])
            return [super gestureRecognizerShouldBegin:gestureRecognizer];
        return true;
    }

    if ([self isEditing] || [self isDecelerating] || [self isDragging])
        return false;

    if (_actionCell != nil)
        return false;

    return true;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)__unused gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)__unused otherGestureRecognizer
{
    return false;
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];

    if (self.window == nil)
    {
        _ignoreTouches = false;

        if (_actionCell != nil)
        {
            if ([_actionCell conformsToProtocol:@protocol(TGActionTableViewCell)])
                [(id<TGActionTableViewCell>)_actionCell dismissEditingControls:false];
            self.actionCell = nil;
        }
    }
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    if (_shouldHackHeaderSize)
    {
        UIView *tableHeaderView = self.tableHeaderView;
        if (tableHeaderView != nil)
        {
            CGSize size = self.frame.size;
            
            CGRect frame = tableHeaderView.frame;
            if (frame.size.width < size.width)
            {
                frame.size.width = size.width;
                tableHeaderView.frame = frame;
            }
        }
    }
}

- (void)hackHeaderSize
{
    _shouldHackHeaderSize = true;
}

@end
