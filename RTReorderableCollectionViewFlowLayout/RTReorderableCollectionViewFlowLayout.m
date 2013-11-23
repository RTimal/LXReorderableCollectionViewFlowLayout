
#import "RTReorderableCollectionViewFlowLayout.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#pragma mark Inline Function

CG_INLINE CGPoint
RTS_CGPointAdd(CGPoint point1, CGPoint point2) {
    return CGPointMake(point1.x + point2.x, point1.y + point2.y);
}

#pragma  mark - Enums

typedef NS_ENUM(NSInteger, RTScrollingDirection) {
    RTScrollingDirectionUnknown = 0,
    RTScrollingDirectionUp,
    RTScrollingDirectionDown,
    RTScrollingDirectionLeft,
    RTScrollingDirectionRight
};

#pragma mark Constants

static NSString * const kRTScrollingDirectionKey = @"RTScrollingDirection";
static NSString * const kRTCollectionViewKeyPath = @"collectionView";
static NSInteger kRTFramesPerSecond = 60.f;

#pragma mark -  CADisplayLink (RT_userInfo)

@interface CADisplayLink (RT_userInfo)
@property (nonatomic, copy) NSDictionary *RT_userInfo;
@end

@implementation CADisplayLink (RT_userInfo)

- (void)setRT_userInfo:(NSDictionary *) RT_userInfo {
    objc_setAssociatedObject(self, "RT_userInfo", RT_userInfo, OBJC_ASSOCIATION_COPY);
}

- (NSDictionary *)RT_userInfo {
    return objc_getAssociatedObject(self, "RT_userInfo");
}
@end

#pragma mark - UICollectionViewCell UICollectionViewCell (RTReorderableCollectionViewFlowLayout)

@interface UICollectionViewCell (RTReorderableCollectionViewFlowLayout)

- (UIImage *)RT_rasterizedImage;

@end

@implementation UICollectionViewCell (RTReorderableCollectionViewFlowLayout)

- (UIImage *)RT_rasterizedImage
{
    UIGraphicsBeginImageContextWithOptions(self.bounds.size, self.isOpaque, 0.0f);
    [self.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

@end

#pragma mark - RTReorderableCollectionViewFlowLayout

@interface RTReorderableCollectionViewFlowLayout ()

@property (strong, nonatomic) NSIndexPath *indexPathForSelectedItem;
@property (strong, nonatomic) UIView *currentCellCopy;
@property (assign, nonatomic) CGPoint currentViewCenter;
@property (assign, nonatomic) CGPoint panTranslationInCollectionView;
@property (strong, nonatomic) CADisplayLink *displayLink;

@property (assign, nonatomic, readonly) id<RTReorderableCollectionViewDataSource> dataSource;
@property (assign, nonatomic, readonly) id<RTReorderableCollectionViewDelegateFlowLayout> delegate;

@end

@implementation RTReorderableCollectionViewFlowLayout

#pragma mark Designated Initializer

- (id)init
{
    self = [super init];
    if (self) {
		[self setup];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
		[self setup];
       }
    return self;
}

#pragma mark setup

- (void)setup
{
	_scrollingSpeed = 300.0f;
    _scrollingTriggerEdgeInsets = UIEdgeInsetsMake(50.0f, 50.0f, 50.0f, 50.0f);
	[self addObserver:self forKeyPath:kRTCollectionViewKeyPath options:NSKeyValueObservingOptionNew context:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ([keyPath isEqualToString:kRTCollectionViewKeyPath])
	{
        if (self.collectionView != nil) {
            [self setupCollectionView];
        } else {
            [self invalidatesScrollTimer];
        }
    }
}

- (void)setupCollectionView
{
    _longPressGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                                action:@selector(handleLongPressGesture:)];
    _longPressGestureRecognizer.delegate = self;
    for (UIGestureRecognizer *gestureRecognizer in self.collectionView.gestureRecognizers) {
        if ([gestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
            [gestureRecognizer requireGestureRecognizerToFail:_longPressGestureRecognizer];
        }
    }
	
    [self.collectionView addGestureRecognizer:_longPressGestureRecognizer];
    
    _panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                    action:@selector(handlePanGesture:)];
    _panGestureRecognizer.delegate = self;
	
    [self.collectionView addGestureRecognizer:_panGestureRecognizer];

    // Useful in multiple scenarios: one common scenario being when the Notification Center drawer is pulled down
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleApplicationWillResignActive:) name: UIApplicationWillResignActiveNotification object:nil];
}

#pragma mark - Get Data Source and Delegate

- (id<RTReorderableCollectionViewDataSource>)dataSource
{
    return (id<RTReorderableCollectionViewDataSource>)self.collectionView.dataSource;
}

- (id<RTReorderableCollectionViewDelegateFlowLayout>)delegate
{
    return (id<RTReorderableCollectionViewDelegateFlowLayout>)self.collectionView.delegate;
}
#pragma mark - Long Press

- (void)handleLongPressGesture:(UILongPressGestureRecognizer *)gestureRecognizer
{
    switch(gestureRecognizer.state)
	{
        case UIGestureRecognizerStateBegan:
		{
            NSIndexPath *currentIndexPath = [self.collectionView indexPathForItemAtPoint:[gestureRecognizer locationInView:self.collectionView]];

            if (![self.dataSource collectionView:self.collectionView canMoveItemAtIndexPath:currentIndexPath])
			{
                return;
            }
			
			_indexPathForSelectedItem = currentIndexPath;

            if ([[self delegate] respondsToSelector:@selector(collectionView:layout:willBeginDraggingItemAtIndexPath:)])
			{
				[[self delegate]collectionView:self.collectionView layout:self willBeginDraggingItemAtIndexPath:_indexPathForSelectedItem];
            }
			
            UICollectionViewCell *collectionViewCell = [self.collectionView cellForItemAtIndexPath:_indexPathForSelectedItem];

            self.currentCellCopy = [[UIView alloc] initWithFrame:collectionViewCell.frame];
			
			collectionViewCell.highlighted = YES;
            UIImageView *highlightedImageView = [[UIImageView alloc] initWithImage:[collectionViewCell RT_rasterizedImage]];
            highlightedImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            highlightedImageView.alpha = 1.0f;
			
            collectionViewCell.highlighted = NO;
            UIImageView *imageView = [[UIImageView alloc] initWithImage:[collectionViewCell RT_rasterizedImage]];
            imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            imageView.alpha = 0.0f;
			
            [self.currentCellCopy addSubview:imageView];
            [self.currentCellCopy addSubview:highlightedImageView];
            [self.collectionView addSubview:self.currentCellCopy];
            self.currentViewCenter = self.currentCellCopy.center;
			
            __weak typeof(self) weakSelf = self;
			
            [UIView
             animateWithDuration:0.3
             delay:0.0
             options:UIViewAnimationOptionBeginFromCurrentState
             animations:^{
                 __strong typeof(self) strongSelf = weakSelf;
                 if (strongSelf) {
                     strongSelf.currentCellCopy.transform = CGAffineTransformMakeScale(1.1f, 1.1f);
                     highlightedImageView.alpha = 0.0f;
                     imageView.alpha = 1.0f;
                 }
             }
             completion:^(BOOL finished) {
                 __strong typeof(self) strongSelf = weakSelf;
                 if (strongSelf) {
                     [highlightedImageView removeFromSuperview];
                     
                     if ([strongSelf.delegate respondsToSelector:@selector(collectionView:layout:didBeginDraggingItemAtIndexPath:)]) {
						 [strongSelf.delegate collectionView:strongSelf.collectionView layout:strongSelf didBeginDraggingItemAtIndexPath:strongSelf.indexPathForSelectedItem];
                     }
                 }
             }];
            [self invalidateLayout];
        } break;
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateEnded: {
            NSIndexPath *currentIndexPath = self.indexPathForSelectedItem;
            
            if (currentIndexPath) {
                if ([self.delegate respondsToSelector:@selector(collectionView:layout:willEndDraggingItemAtIndexPath:)]) {
                    [self.delegate collectionView:self.collectionView layout:self willEndDraggingItemAtIndexPath:currentIndexPath];
                }
                
                self.indexPathForSelectedItem = nil;
                self.currentViewCenter = CGPointZero;
                
                UICollectionViewLayoutAttributes *layoutAttributes = [self layoutAttributesForItemAtIndexPath:currentIndexPath];
                __weak typeof(self) weakSelf = self;
                [UIView
                 animateWithDuration:0.3
                 delay:0.0
                 options:UIViewAnimationOptionBeginFromCurrentState
                 animations:^{
                     __strong typeof(self) strongSelf = weakSelf;
                     if (strongSelf) {
                         strongSelf.currentCellCopy.transform = CGAffineTransformMakeScale(1.0f, 1.0f);
                         strongSelf.currentCellCopy.center = layoutAttributes.center;
                     }
                 }
                 completion:^(BOOL finished) {
                     __strong typeof(self) strongSelf = weakSelf;
                     if (strongSelf) {
                         [strongSelf.currentCellCopy removeFromSuperview];
                         strongSelf.currentCellCopy = nil;
                         [strongSelf invalidateLayout];
                         
                         if ([strongSelf.delegate respondsToSelector:@selector(collectionView:layout:didEndDraggingItemAtIndexPath:)]) {
                             [strongSelf.delegate collectionView:strongSelf.collectionView layout:strongSelf didEndDraggingItemAtIndexPath:currentIndexPath];
                         }
                     }
                 }];
            }
        } break;
        default: break;
    }
}

#pragma mark Panning

- (void)handlePanGesture:(UIPanGestureRecognizer *)gestureRecognizer
{
    switch (gestureRecognizer.state)
	{
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
		{
            _panTranslationInCollectionView = [gestureRecognizer translationInView:self.collectionView];
            CGPoint viewCenter = _currentCellCopy.center = RTS_CGPointAdd(_currentViewCenter, self.panTranslationInCollectionView);

            [self invalidateLayoutIfNecessary];
            
            switch (self.scrollDirection)
			{
                case UICollectionViewScrollDirectionVertical:
				{
                    if (viewCenter.y < (CGRectGetMinY(self.collectionView.bounds) + self.scrollingTriggerEdgeInsets.top)) {
                        [self setupScrollTimerInDirection:RTScrollingDirectionUp];
                    } else {
                        if (viewCenter.y > (CGRectGetMaxY(self.collectionView.bounds) - self.scrollingTriggerEdgeInsets.bottom)) {
                            [self setupScrollTimerInDirection:RTScrollingDirectionDown];
                        } else {
                            [self invalidatesScrollTimer];
                        }
                    }
                } break;
                case UICollectionViewScrollDirectionHorizontal: {
                    if (viewCenter.x < (CGRectGetMinX(self.collectionView.bounds) + self.scrollingTriggerEdgeInsets.left)) {
                        [self setupScrollTimerInDirection:RTScrollingDirectionLeft];
                    } else {
                        if (viewCenter.x > (CGRectGetMaxX(self.collectionView.bounds) - self.scrollingTriggerEdgeInsets.right)) {
                            [self setupScrollTimerInDirection:RTScrollingDirectionRight];
                        } else {
                            [self invalidatesScrollTimer];
                        }
                    }
                } break;
            }
        } break;
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateEnded: {
            [self invalidatesScrollTimer];
        } break;
        default: {
            // Do nothing...
        } break;
    }
}


- (void)invalidateLayoutIfNecessary
{
    NSIndexPath *newIndexPath = [self.collectionView indexPathForItemAtPoint:_currentCellCopy.center];
    NSIndexPath *previousIndexPath = _indexPathForSelectedItem;
	
    if ((newIndexPath == nil) || [newIndexPath isEqual:previousIndexPath])
	{
        return;
    }
	
    if ([[self dataSource] respondsToSelector:@selector(collectionView:itemAtIndexPath:canMoveToIndexPath:)] &&
        ![[self dataSource] collectionView:self.collectionView itemAtIndexPath:previousIndexPath canMoveToIndexPath:newIndexPath])
	{
        return;
    }
	
	_indexPathForSelectedItem = newIndexPath;
    
    if ([[self dataSource] respondsToSelector:@selector(collectionView:itemAtIndexPath:willMoveToIndexPath:)])
	{
        [[self dataSource] collectionView:self.collectionView itemAtIndexPath:previousIndexPath willMoveToIndexPath:newIndexPath];
    }
	
    __weak typeof(self) weakSelf = self;
    [self.collectionView performBatchUpdates:^{
        __strong typeof(self) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf.collectionView deleteItemsAtIndexPaths:@[ previousIndexPath ]];
            [strongSelf.collectionView insertItemsAtIndexPaths:@[ newIndexPath ]];
        }
    } completion:^(BOOL finished) {
        __strong typeof(self) strongSelf = weakSelf;
        if ([strongSelf.dataSource respondsToSelector:@selector(collectionView:itemAtIndexPath:didMoveToIndexPath:)]) {
            [strongSelf.dataSource collectionView:strongSelf.collectionView itemAtIndexPath:previousIndexPath didMoveToIndexPath:newIndexPath];
        }
    }];
	
}

- (void)setupScrollTimerInDirection:(RTScrollingDirection)direction
{
    if (!self.displayLink.paused)
	{
        RTScrollingDirection oldDirection = [self.displayLink.RT_userInfo[kRTScrollingDirectionKey] integerValue];
		
        if (direction == oldDirection)
		{
            return;
        }
    }
    
    [self invalidatesScrollTimer];
	
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(handleScroll:)];
    self.displayLink.RT_userInfo = @{ kRTScrollingDirectionKey : @(direction) };
	
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)invalidatesScrollTimer
{
    if (!self.displayLink.paused)
	{
        [self.displayLink invalidate];
    }
    self.displayLink = nil;
}


- (void)handleScroll:(CADisplayLink *)displayLink {
    RTScrollingDirection direction = (RTScrollingDirection)[displayLink.RT_userInfo[kRTScrollingDirectionKey] integerValue];
    if (direction == RTScrollingDirectionUnknown) {
        return;
    }
    CGSize frameSize = self.collectionView.bounds.size;
    CGSize contentSize = self.collectionView.contentSize;
    CGPoint contentOffset = self.collectionView.contentOffset;
    CGFloat distance = rint(self.scrollingSpeed / kRTFramesPerSecond);
    CGPoint translation = CGPointZero;
	
	switch(direction)
	{
        case RTScrollingDirectionUp:
		{
            distance = -distance;
            CGFloat minY = 0.0f;
            
            if ((contentOffset.y + distance) <= minY)
			{
                distance = -contentOffset.y;
            }
            translation = CGPointMake(0.0f, distance);
        } break;
        case RTScrollingDirectionDown:
		{
            CGFloat maxY = MAX(contentSize.height, frameSize.height) - frameSize.height;
            
            if ((contentOffset.y + distance) >= maxY)
			{
                distance = maxY - contentOffset.y;
            }
            
            translation = CGPointMake(0.0f, distance);
        } break;
        case RTScrollingDirectionLeft:
		{
            distance = -distance;
            CGFloat minX = 0.0f;
            
            if ((contentOffset.x + distance) <= minX)
			{
                distance = -contentOffset.x;
            }
            
            translation = CGPointMake(distance, 0.0f);
        } break;
        case RTScrollingDirectionRight:
		{
            CGFloat maxX = MAX(contentSize.width, frameSize.width) - frameSize.width;
            
            if ((contentOffset.x + distance) >= maxX)
			{
                distance = maxX - contentOffset.x;
            }
            translation = CGPointMake(distance, 0.0f);
        } break;
        default:
		{
            // Do nothing...
        } break;
    }
    
    self.currentViewCenter = RTS_CGPointAdd(self.currentViewCenter, translation);
    self.currentCellCopy.center = RTS_CGPointAdd(self.currentViewCenter, self.panTranslationInCollectionView);
    self.collectionView.contentOffset = RTS_CGPointAdd(contentOffset, translation);
}

#pragma mark - UICollectionViewLayout overridden methods

- (NSArray *)layoutAttributesForElementsInRect:(CGRect)rect {
    NSArray *layoutAttributesForElementsInRect = [super layoutAttributesForElementsInRect:rect];
    
    for (UICollectionViewLayoutAttributes *layoutAttributes in layoutAttributesForElementsInRect)
	{
        switch (layoutAttributes.representedElementCategory) {
            case UICollectionElementCategoryCell: {
                [self changeLayoutAttributes:layoutAttributes];
            } break;
            default: {
                // Do nothing...
            } break;
        }
    }
    
    return layoutAttributesForElementsInRect;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath
{
    UICollectionViewLayoutAttributes *layoutAttributes = [super layoutAttributesForItemAtIndexPath:indexPath];
    switch (layoutAttributes.representedElementCategory)
	{
        case UICollectionElementCategoryCell: {
            [self changeLayoutAttributes:layoutAttributes];
        } break;
        default: {
        } break;
    }
    
    return layoutAttributes;
}

- (void)changeLayoutAttributes:(UICollectionViewLayoutAttributes *)layoutAttributes
{
    if ([layoutAttributes.indexPath isEqual:self.indexPathForSelectedItem])
	{
        layoutAttributes.hidden = YES;
    }
}

#pragma mark - UIGestureRecognizerDelegate methods

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == _panGestureRecognizer) {
        return (_indexPathForSelectedItem != nil);
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    if (gestureRecognizer == _longPressGestureRecognizer)
	{
        return (otherGestureRecognizer == _panGestureRecognizer);
    }

    if (gestureRecognizer == _panGestureRecognizer)
	{
        return _longPressGestureRecognizer == otherGestureRecognizer;
    }

    return NO;
}

#pragma mark - Notifications

- (void)handleApplicationWillResignActive:(NSNotification *)notification {
	[_panGestureRecognizer setEnabled:NO];
	[_panGestureRecognizer setEnabled:YES];
}

#pragma mark Dealloc

- (void)dealloc
{
    [self invalidatesScrollTimer];
    [self removeObserver:self forKeyPath:kRTCollectionViewKeyPath];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
}

@end
