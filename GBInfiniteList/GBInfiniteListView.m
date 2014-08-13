//
//  GBInfiniteListView.m
//  GBInfiniteList
//
//  Created by Luka Mirosevic on 30/04/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//

#import "GBInfiniteListView.h"

#import "UIView+GBInfiniteList.h"

NSString * const GBWidthMismatchException =                                             @"GBWidthMismatchException";
NSString * const GBSizeMismatchException =                                              @"GBSizeMismatchException";

typedef struct {
    CGFloat origin;
    CGFloat height;
} GBInfiniteListItemGeometry;

typedef struct {
    NSUInteger                      itemIdentifier;
    GBInfiniteListItemGeometry      geometry;
} GBInfiniteListItemMeta;

typedef struct {
    NSUInteger firstLoadedIndex;
    NSUInteger lastLoadedIndex;
} GBInfiniteListColumnBoundaries;

typedef enum {
    GBInfiniteListTypeOfGapNone,
    GBInfiniteListTypeOfGapExisting,
    GBInfiniteListTypeOfGapEndOfList,
} GBInfiniteListTypeOfGap;

typedef struct {
    GBInfiniteListTypeOfGap     type;
    NSUInteger                  columnIdentifier;
    NSUInteger                  itemIdentifier;
    NSUInteger                  indexInColumnStack;
} GBInfiniteListGap;

typedef enum {
    GBInfiniteListLoadingViewTypeDefault,
    GBInfiniteListLoadingViewTypeCustom,
} GBInfiniteListLoadingViewType;

typedef enum {
    GBInfiniteListDirectionMovedHintNone,
    GBInfiniteListDirectionMovedHintUp,
    GBInfiniteListDirectionMovedHintDown,
} GBInfiniteListDirectionMovedHint;

static BOOL const kDefaultShouldAutoStart =                                             YES;

static CGFloat const kDefaultVerticalItemMargin =                                       0;
static CGFloat const kDefaultHorizontalColumnMargin =                                   0;
static CGFloat const kDefaultLoadTriggerDistance =                                      0;
static UIEdgeInsets const kDefaultOuterPadding =                                        (UIEdgeInsets){0,0,0,0};

static BOOL const kDefaultForShouldPositionLoadingViewInsideOuterPadding =              YES;
static BOOL const kDefaultForShouldPositionHeaderViewInsideOuterPadding =               YES;
static CGFloat const kDefaultLoadingViewTopMargin =                                     0;
static CGFloat const kDefaultHeaderViewBottomMargin =                                   0;
static UIEdgeInsets const kPaddingForDefaultSpinner =                                   (UIEdgeInsets){4, 0, 4, 0};

static NSUInteger const kDefaultRecyclableViewsPoolSize =                               28;

static BOOL const kDefaultForShouldAlwaysScroll =                                       YES;
static BOOL const kDefaultForStaticMode =                                               NO;

static NSUInteger const GBColumnIndexUndefined =                                        NSUIntegerMax;
static GBInfiniteListColumnBoundaries const GBInfiniteListColumnBoundariesUndefined =   {GBColumnIndexUndefined, GBColumnIndexUndefined};
static inline BOOL IsGBInfiniteListColumnBoundariesUndefined(GBInfiniteListColumnBoundaries columnBoundaries) {
    if (columnBoundaries.firstLoadedIndex == GBColumnIndexUndefined && columnBoundaries.lastLoadedIndex == GBColumnIndexUndefined) {
        return YES;
    }
    else {
        return NO;
    }
}


@interface GBInfiniteListView () <UIGestureRecognizerDelegate> {
    UIView                                                          *_defaultLoadingView;
}

//Strong pointers to little subviews (so that the creator can safely drop their pointers and it won't get dealloced)
@property (strong, nonatomic) UIView                                *headerView;
@property (strong, nonatomic) UIView                                *noItemsView;
@property (strong, nonatomic) UIView                                *loadingView;

//Default loading view
@property (strong, nonatomic, readonly) UIView                      *defaultLoadingView;

//Scrollview where to put all the stuff on
@property (strong, nonatomic, readwrite) UIScrollView               *scrollView;

//To know when to kick off the data dance. Data dance is kicked off as soon as view is visible, init has been called, and datasource has been set. if any of these changes, the data dance stops
@property (assign, nonatomic) BOOL                                  isInitialised;
@property (assign, nonatomic) BOOL                                  isVisible;
@property (assign, nonatomic) BOOL                                  isDataSourceSet;

//Used so the starting machinery can know when the start method was called
@property (assign, nonatomic) BOOL                                  didRequestStart;

//This says whether the data dance is on or not
@property (assign, nonatomic) BOOL                                  isDataDanceActive;

//So it knows if it should ask for more items or wait patiently for a callback
@property (assign, nonatomic) BOOL                                  hasRequestedMoreItems;

//Redefined as readwrite
@property (assign, nonatomic, readwrite) CGFloat                    requiredViewWidth;

//Geometry stuff
@property (assign, nonatomic) NSUInteger                            numberOfColumns;
@property (assign, nonatomic) UIEdgeInsets                          outerPadding;
@property (assign, nonatomic) CGFloat                               verticalItemMargin;
@property (assign, nonatomic) CGFloat                               horizontalColumnMargin;
@property (assign, nonatomic) CGFloat                               loadTriggerDistance;
@property (assign, nonatomic) CGFloat                               actualListOrigin;

//Container for views that can be recycled
@property (strong, nonatomic) NSMutableDictionary                   *recycledViewsPool;

//NSArray of GBFastArray's of GBInfiniteListItemMeta's. Fast data structure used for efficiently finding out who is visible, whether there are any gaps, calculating who just came back on screen when the infiniteList scrolls back up, and checking whether the size matches. It's fast because it's sorted in the order in which it will be queried (reverse order), and it can skip stuff it doesn't need to query because we have indexes.
@property (strong, nonatomic) NSArray                               *columnStacks;

//C-array of GBInfiniteListColumnBoundaries's. Used as an index to help making searching through columnStacks faster.
@property (assign, nonatomic) GBInfiniteListColumnBoundaries        *columnStacksLoadedItemBoundaryIndices;

//A way to get to the actual view which is loaded once you have the itemIdentifier. NSDictionary where key is itemIdentifier, and value is the actual view
@property (strong, nonatomic) NSMutableDictionary                   *loadedViews;

//For keeping track of which item is the last one loaded
@property (assign, nonatomic) NSInteger                             lastLoadedItemIdentifier;

//C-array for keeping track of which item was the last one to be recycled, used as a hint for array searches. one for each column
@property (assign, nonatomic) NSInteger                             *lastRecycledItemsIdentifiers;

//For keeping track of the last scrolled position
@property (assign, nonatomic) CGFloat                               lastScrollViewPosition;

//For keeping track of the last dragged position
@property (assign, nonatomic) CGPoint                               lastIncrementalDraggingPosition;
@property (assign, nonatomic) CGPoint                               lastInitialDraggingPosition;

//For keeping track of when the user is dragging (because the UIScrollView isDragging property doesn't seem to work)
@property (assign, nonatomic) BOOL                                  isUserDragging;

//For detecting taps
@property (strong, nonatomic) UITapGestureRecognizer                *tapGestureRecognizer;

@end


@implementation GBInfiniteListView

#pragma mark - Custom accessors: side effects

-(void)setDidRequestStart:(BOOL)didRequestStart {
    _didRequestStart = didRequestStart;
    
    [self _manageDataDanceState];
}

-(void)setStaticMode:(BOOL)staticMode {
    _staticMode = staticMode;
    
    [self _syncHeight];
}

-(CGFloat)totalHeight {
    //it's safe to just return the contentSize, and ignore the insets etc. because we handle the header internally and all content is always just drawn straight into the scrollview
    return self.scrollView.contentSize.height;
}

-(void)setDataSource:(id<GBInfiniteListViewDataSource>)dataSource {
    _dataSource = dataSource;
    
    if (dataSource) {
        self.isDataSourceSet = YES;
    }
    else {
        self.isDataSourceSet = NO;
    }
}

-(void)setMaxReusableViewsPoolSize:(NSUInteger)maxReusableViewsPoolSize {
    //if its bigger or equal
    if (maxReusableViewsPoolSize >= _maxReusableViewsPoolSize) {
        //do nothing special
    }
    //if its smaller
    else {
        //prune all the pools
        for (id key in self.recycledViewsPool) {
            NSMutableArray *pool = self.recycledViewsPool[key];
            
            //check if this pool is too long
            if (pool.count > maxReusableViewsPoolSize) {
                [pool removeObjectsInRange:NSMakeRange(maxReusableViewsPoolSize, (pool.count - 1) - maxReusableViewsPoolSize)];
            }
        }
    }
    
    _maxReusableViewsPoolSize = maxReusableViewsPoolSize;
}

-(void)setShouldAlwaysScroll:(BOOL)shouldAlwaysScroll {
    _shouldAlwaysScroll = shouldAlwaysScroll;
    
    self.scrollView.alwaysBounceVertical = shouldAlwaysScroll;
}

#pragma mark - Custom accessors: Lazy

-(UIView *)defaultLoadingView {
    if (!_defaultLoadingView) {
        //create spinner
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        
        //create & configure the containing view
        _defaultLoadingView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, spinner.frame.size.width + kPaddingForDefaultSpinner.left + kPaddingForDefaultSpinner.right, spinner.frame.size.height + kPaddingForDefaultSpinner.top + kPaddingForDefaultSpinner.bottom)];
        _defaultLoadingView.backgroundColor = [UIColor clearColor];
        
        //configure the spinner
        spinner.frame = CGRectMake(kPaddingForDefaultSpinner.left, kPaddingForDefaultSpinner.top, spinner.frame.size.width, spinner.frame.size.height);
        spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        [spinner startAnimating];
        
        //add the spinner to the container view
        [_defaultLoadingView addSubview:spinner];
    }
    
    return _defaultLoadingView;
}

#pragma mark - Custom accessors: Data dance state management

-(void)setIsInitialised:(BOOL)isInitialised {
    _isInitialised = isInitialised;
    
    [self _manageDataDanceState];
}

-(void)setIsVisible:(BOOL)isVisible {
    _isVisible = isVisible;
    
    [self _manageDataDanceState];
}

-(void)setIsDataSourceSet:(BOOL)isDataSourceSet {
    _isDataSourceSet = isDataSourceSet;
    
    [self _manageDataDanceState];
}

#pragma mark - Memory

-(id)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self _initialisationRoutine];
    }
    
    return self;
}

-(id)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super initWithCoder:aDecoder]) {
        [self _initialisationRoutine];
    }
    
    return self;
}

-(void)dealloc {
    _defaultLoadingView = nil;
    
    self.dataSource = nil;
    self.delegate = nil;
    
    [self _cleanup];
}

#pragma mark - View lifecycle

-(void)willMoveToSuperview:(UIView *)newSuperview {
    if (newSuperview) {
        self.isVisible = YES;
    }
    else {
        self.isVisible = NO;
    }
}

#pragma mark - Public API: Data dance

-(void)reset {
    //make sure we don't do a double reset
    if (self.isDataDanceActive) {
        //make sure they don't sent a draggin message
        self.isUserDragging = NO;
        
        //recycle all loaded items. just so the old delegate gets his messages
        [self _recyclerLoopWithHint:GBInfiniteListDirectionMovedHintNone forcedRecyclingOfEverything:YES];
        
        //stop data dance
        [self _stopDataDance];
        
        //scroll to top without animating
        [self scrollToTopAnimated:NO];
        
        //start data dance
        [self _manageDataDanceState];
    }
}

-(void)start {
    if (!self.isDataDanceActive) {
        self.didRequestStart = YES;
    }
}

-(UIView *)dequeueReusableViewWithIdentifier:(NSString *)reuseIdentifier {
    NSMutableArray *pool;
    //check if we have a pool for that? YES
    if ((pool = self.recycledViewsPool[reuseIdentifier])) {
        //make sure we have a view in there
        if (pool.count > 0) {
            //get a pointer to the view
            UIView *viewToBeRecycled = [pool lastObject];
            
            //remove it from the array
            [pool removeLastObject];
            
            //return it
            return viewToBeRecycled;
        }
    }

    //in all other cases return nil
    return nil;
}

-(UIView *)dequeueReusableViewWithIdentifier:(NSString *)reuseIdentifier elseCreateWithBlock:(UIView *(^)(void))block {
    //if the block is nil, raise an exception
    if (!block) @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"block was nil" userInfo:nil];
    
    UIView *dequeuedView = [self dequeueReusableViewWithIdentifier:reuseIdentifier];
    
    //if its non-nil return it
    if (dequeuedView) {
        return dequeuedView;
    }
    //otherwise return a new one
    else {
        //create it by inverting control
        UIView *newView = block();

        //set its reuseIdentfier
        newView.reuseIdentifier = reuseIdentifier;
        
        //return it
        return newView;
    }
}

-(void)didFinishLoadingMoreItems {
    if (self.isDataDanceActive) {
        [self _didCompleteLoadingWithCustomLogic:^{
            //send delegate the infiniteListViewDidFinishLoadingMoreItems: message
            if ([self.delegate respondsToSelector:@selector(infiniteListViewDidFinishLoadingMoreItems:)]) {
                [self.delegate infiniteListViewDidFinishLoadingMoreItems:self];
            }
            
            //restart our loop
            [self _iterateWithHint:GBInfiniteListDirectionMovedHintDown recyclerEnabled:NO];
        }];
    }
}

-(void)didFailLoadingMoreItems {
    if (self.isDataDanceActive) {
        [self _didCompleteLoadingWithCustomLogic:nil];
    }
}

#pragma mark - Private API: Data dance

-(void)_didCompleteLoadingWithCustomLogic:(VoidBlock)code {
    //check that it was expecting this message? YES
    if (self.hasRequestedMoreItems) {
        //remember that you're no longer expecting to receive the moreItemsAvailable: message
        self.hasRequestedMoreItems = NO;
        
        //hide loading view if there was one
        [self.loadingView removeFromSuperview];
        self.loadingView = nil;
        
        //call the code
        if (code) code();
        
        [self _handleNoItemsView];
    }
    //check that it was expecting this message? NO
    else {
        //raise GBUnexpectedMessageException and remind to only call this once and only in response to startLoadingMoreItemsInInfiniteListView: message
        @throw [NSException exceptionWithName:GBUnexpectedMessageException reason:@"The infiniteListView was not expecting more data. Only send this message after the list asks you for more data, and only once!" userInfo:nil];
    }
}

#pragma mark - Public API: Scrolling & Co.

-(void)scrollToTopAnimated:(BOOL)shouldAnimate {
    [self scrollToPosition:0 animated:shouldAnimate];
}

-(void)scrollToPosition:(CGFloat)yPosition animated:(BOOL)shouldAnimate {
    CGFloat verticalContentOffset = ThresholdCGFloat(yPosition, 0, self.scrollView.contentSize.height - self.scrollView.bounds.size.height);
    
    [self.scrollView setContentOffset:CGPointMake(0, verticalContentOffset) animated:shouldAnimate];
}

-(BOOL)isItemVisible:(NSUInteger)itemIdentifier {
    NSNumber *itemNumber = @(itemIdentifier);
    for (NSNumber *key in self.visibleItems) {
        //found one!
        if ([key isEqualToNumber:itemNumber]) {
            return YES;
        }
    }
    
    //if we got here it means he's not there
    return NO;
}

-(NSDictionary *)visibleItems {
    return [self.loadedViews copy];
}

#pragma mark - Caching

-(void)flushReusableViewsPool {    
    //simply replaces the pool with a new one, which causes the old one to trickle down releases and release everything held in it
    self.recycledViewsPool = [NSMutableDictionary new];
}

#pragma mark - UIScrollViewDelegate

-(void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    self.isUserDragging = YES;
    self.lastIncrementalDraggingPosition = self.scrollView.contentOffset;
    self.lastInitialDraggingPosition = self.scrollView.contentOffset;
}

-(void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset {
    self.isUserDragging = NO;
    
    CGPoint oldOffset = self.lastInitialDraggingPosition;
    CGPoint newOffset = *targetContentOffset;
    
    [self _notifyDelegateAboutEndedDraggingFrom:oldOffset to:newOffset velocity:velocity];
}

-(void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self _didMoveViewport];
}

-(void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [self _didMoveViewport];
}

-(void)_didMoveViewport {
    //find out direction of scroll
    GBInfiniteListDirectionMovedHint directionHint;
    if (self.scrollView.contentOffset.y > self.lastScrollViewPosition) {
        directionHint = GBInfiniteListDirectionMovedHintDown;
    }
    else {
        directionHint = GBInfiniteListDirectionMovedHintUp;
    }
    
    //iterate
    [self _iterateWithHint:directionHint recyclerEnabled:YES];
    
    //offsets
    CGFloat oldOffset = self.lastScrollViewPosition;
    CGFloat newOffset = self.scrollView.contentOffset.y;
    
    //remember the current position
    self.lastScrollViewPosition = newOffset;
    
    if (self.isUserDragging) {
        //dragging
        CGPoint oldDraggingOffset = self.lastIncrementalDraggingPosition;
        CGPoint newDraggingOffset = self.scrollView.contentOffset;
        
        //remember the drag position
        self.lastIncrementalDraggingPosition = newDraggingOffset;
        
        //tell delegate about incremental dragging
        [self _notifyDelegateAboutContinuousDraggingFrom:oldDraggingOffset to:newDraggingOffset];
    }
    
    //tell delegate about scrolling
    [self _notifyDelegateAboutScrollingFrom:oldOffset to:newOffset];
}

-(void)_notifyDelegateAboutEndedDraggingFrom:(CGPoint)oldOffset to:(CGPoint)newOffset velocity:(CGPoint)velocity {
    if ([self.delegate respondsToSelector:@selector(infiniteListView:didEndDraggingFromPosition:toPosition:withVelocity:)]) {
        [self.delegate infiniteListView:self didEndDraggingFromPosition:oldOffset toPosition:newOffset withVelocity:velocity];
    }
}

-(void)_notifyDelegateAboutContinuousDraggingFrom:(CGPoint)oldOffset to:(CGPoint)newOffset {
    if ([self.delegate respondsToSelector:@selector(infiniteListView:didDragFromPosition:toPosition:)]) {
        [self.delegate infiniteListView:self didDragFromPosition:oldOffset toPosition:newOffset];
    }
}

-(void)_notifyDelegateAboutScrollingFrom:(CGFloat)oldOffset to:(CGFloat)newOffset {
    //tell delegate about scrolling
    if ([self.delegate respondsToSelector:@selector(infiniteListView:didScrollFromPosition:toPosition:)]) {
        [self.delegate infiniteListView:self didScrollFromPosition:oldOffset toPosition:newOffset];
    }
}

#pragma mark - UITapGestureRecognizerDelegate

//we want to pass touches through to these other views in case they have controls on them
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if ((self.headerView.superview && [touch.view isDescendantOfView:self.headerView]) ||
        (self.noItemsView.superview && [touch.view isDescendantOfView:self.noItemsView]) ||
        (self.loadingView.superview && [touch.view isDescendantOfView:self.loadingView])) {
        return NO;
    }
    else {
        return YES;
    }
}

#pragma mark - Private API: Memory

-(void)_initialisationRoutine {
    //default properties (which should persist between resets)
    self.shouldAutoStart = kDefaultShouldAutoStart;
    self.shouldAlwaysScroll = kDefaultForShouldAlwaysScroll;
    self.staticMode = kDefaultForStaticMode;
    
    //Set state
    self.isInitialised = YES;
}

-(void)_initialiseDataStructures {
    //init data structures n co.
    self.tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didTap:)];
    self.tapGestureRecognizer.delegate = self;
    self.gestureRecognizers = @[self.tapGestureRecognizer];
    
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.scrollView.opaque = NO;
    self.scrollView.backgroundColor = [UIColor clearColor];
    self.scrollView.delegate = self;
    self.scrollView.scrollEnabled = YES;
    self.scrollView.showsVerticalScrollIndicator = NO;
    self.scrollView.alwaysBounceVertical = self.shouldAlwaysScroll;
    self.recycledViewsPool = [NSMutableDictionary new];
    self.loadedViews = [NSMutableDictionary new];
    self.hasRequestedMoreItems = NO;
    self.lastScrollViewPosition = 0;
    self.maxReusableViewsPoolSize = kDefaultRecyclableViewsPoolSize;
    
    //add the actual scrollview to the screen
    [self addSubview:self.scrollView];
    
    //reset the geometry stuff
    self.actualListOrigin = 0;
    self.lastLoadedItemIdentifier = -1;
    self.numberOfColumns = 0;
    self.requiredViewWidth = 0;
    self.outerPadding = UIEdgeInsetsZero;
    self.verticalItemMargin = 0;
    self.horizontalColumnMargin = 0;
    self.loadTriggerDistance = 0;
}

-(void)_finaliseScrollViewSize {
    self.scrollView.frame = self.bounds;
}

-(void)_initialiseColumnCountDependentDataStructures {
    //last recycled items identifiers
    self.lastRecycledItemsIdentifiers = malloc(sizeof(NSInteger) * self.numberOfColumns);
    
    //column stacks + column stack loaded indices
    NSMutableArray *newColumnStacks = [[NSMutableArray alloc] initWithCapacity:self.numberOfColumns];
    self.columnStacksLoadedItemBoundaryIndices = malloc(sizeof(GBInfiniteListColumnBoundaries) * self.numberOfColumns);
    
    for (int i=0; i<self.numberOfColumns; i++) {
        newColumnStacks[i] = [[GBFastArray alloc] initWithTypeSize:sizeof(GBInfiniteListItemMeta) initialCapacity:100 resizingFactor:1.5];
        
        self.columnStacksLoadedItemBoundaryIndices[i] = GBInfiniteListColumnBoundariesUndefined;
    }
    
    self.columnStacks = [newColumnStacks copy];
}

-(void)_cleanup {
    //my data structures
    self.columnStacks = nil;
    if (self.columnStacksLoadedItemBoundaryIndices != NULL) {
        free(self.columnStacksLoadedItemBoundaryIndices);
        self.columnStacksLoadedItemBoundaryIndices = NULL;
    }
    if (self.lastRecycledItemsIdentifiers != NULL) {
        free(self.lastRecycledItemsIdentifiers);
        self.lastRecycledItemsIdentifiers = NULL;
    }
    
    self.recycledViewsPool = nil;
    self.loadedViews = nil;
    
    //scroll view
    [self.scrollView removeFromSuperview];
    self.scrollView = nil;
    
    //little views
    [self.headerView removeFromSuperview];
    self.headerView = nil;
    [self.noItemsView removeFromSuperview];
    self.noItemsView = nil;
    [self.loadingView removeFromSuperview];
    self.loadingView = nil;
}

#pragma mark - Private API: Tapping {

-(void)didTap:(UITapGestureRecognizer *)tapGestureRecognizer {
    if (self.isDataDanceActive) {
        if (tapGestureRecognizer.state == UIGestureRecognizerStateEnded) {
            CGPoint tapLocation = [tapGestureRecognizer locationInView:self.scrollView];
            CGFloat x = tapLocation.x;
            CGFloat y = tapLocation.y;
            
            //find column in which the tap occurred
            NSUInteger columnIndex;
            BOOL insideColumn = false;
            for (NSUInteger i=0; i<self.numberOfColumns; i++) {
                
                CGFloat columnLeftEdge = self.outerPadding.left + i * (self.requiredViewWidth + self.horizontalColumnMargin);
                CGFloat columnRightEdge = columnLeftEdge + self.requiredViewWidth;
                
                
                if (x >= columnLeftEdge && x <= columnRightEdge) {
                    columnIndex = i;
                    insideColumn = YES;
                    break;
                }
            }
            
            //bail if it's in no column
            if (!insideColumn) return;
            
            GBFastArray *columnStack = self.columnStacks[columnIndex];
            NSUInteger firstLoadedIndex = self.columnStacksLoadedItemBoundaryIndices[columnIndex].firstLoadedIndex;
            NSUInteger lastLoadedIndex = self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex;
            
            //bail if undefined
            if (IsGBInfiniteListColumnBoundariesUndefined(self.columnStacksLoadedItemBoundaryIndices[columnIndex])) return;
            
            //do binary search for the item that matches, top/low: lastUnloaded, bottom/high: count-1
            __block GBInfiniteListItemMeta nativeCandidateItem;
            NSUInteger itemIndex = [columnStack binarySearchForIndexWithLow:firstLoadedIndex high:lastLoadedIndex searchLambda:^GBSearchResult(void *candidateItem) {
                nativeCandidateItem = *(GBInfiniteListItemMeta *)candidateItem;
                GBInfiniteListItemGeometry geometry = nativeCandidateItem.geometry;
                
                //if visible: bingo
                if (y >= geometry.origin && y<= (geometry.origin + geometry.height)) {
                    return GBSearchResultMatch;
                }
                //if the item is somewhere before, then we've gone too far
                else if (y < geometry.origin) {
                    return GBSearchResultHigh;
                }
                //otherwise we're too low
                else {
                    return GBSearchResultLow;
                }
            }];
            
            //bail if we haven't found one
            if (itemIndex == kGBSearchResultNotFound) return;
            
            //we found one, tell delegate
            UIView *view = self.loadedViews[@(nativeCandidateItem.itemIdentifier)];
            if ([self.delegate respondsToSelector:@selector(infiniteListView:didTapOnView:correspondingToItem:)]) {
                [self.delegate infiniteListView:self didTapOnView:view correspondingToItem:nativeCandidateItem.itemIdentifier];
            }
        }
    }
}

#pragma mark - Private API: Data dance state management

-(void)_manageDataDanceState {
    BOOL allRequiredToStart = (self.isVisible && self.isDataSourceSet && self.isInitialised && (self.shouldAutoStart || self.didRequestStart));
    BOOL anyRequireToStop = (!self.isDataSourceSet || !self.isInitialised);
    
    //if we have conditions to start & we're not started yet
    if (allRequiredToStart && !self.isDataDanceActive) {
        _didRequestStart = NO;
        [self _startDataDance];
    }
    
    //if we have conditions to stop & we're started atm
    if (anyRequireToStop && self.isDataDanceActive) {
        [self _stopDataDance];
    }
}

-(void)_startDataDance {
    //just remember it
    self.isDataDanceActive = YES;

    //initialise data structures
    [self _initialiseDataStructures];
    
    //set the size of the scrollView to match the infiniteListView frame
    [self _finaliseScrollViewSize];

    //get all the geometry stuff
    [self _requestAndPrepareGeometryStuff];
    
    //initialise column stacks n co.
    [self _initialiseColumnCountDependentDataStructures];

    //draw header view if necessary, this also configures the actualListOrigin.
    [self _handleHeaderViewAndConfigureListOrigin];
    
    //kick it all off
    [self _iterateWithHint:GBInfiniteListDirectionMovedHintNone recyclerEnabled:YES];
}

-(void)_stopDataDance {
    //remember state
    self.isDataDanceActive = NO;

    //clean up as if nothing ever happened (except for maybe the lazy loading spinner)
    [self _cleanup];
}

#pragma mark - Private API: Little views (header, no items, loading)

-(void)_handleHeaderViewAndConfigureListOrigin {
    UIView *headerView;
    BOOL isHeaderViewInsidePadding;
    CGFloat marginForHeader;

    //fetch the header first
    if ([self.dataSource respondsToSelector:@selector(headerViewInInfiniteListView:)]) {
        headerView = [self.dataSource headerViewInInfiniteListView:self];
    }
    //if they don't wanna give one, just set it to nil so we can do the rest
    else {
        headerView = nil;
    }
    
    //check header type? UIView *
    if ([headerView isKindOfClass:[UIView class]]) {
        //check whethere to ignore padding
        if ([self.dataSource respondsToSelector:@selector(shouldPositionHeaderViewInsideOuterPaddingInInfiniteListView:)]) {
            isHeaderViewInsidePadding = [self.dataSource shouldPositionHeaderViewInsideOuterPaddingInInfiniteListView:self];
        }
        else {
            isHeaderViewInsidePadding = kDefaultForShouldPositionHeaderViewInsideOuterPadding;
        }
        
        //check for margin
        if ([self.dataSource respondsToSelector:@selector(marginForHeaderViewInInfiniteListView:)]) {
            marginForHeader = [self.dataSource marginForHeaderViewInInfiniteListView:self];
        }
        //just use default
        else {
            marginForHeader = kDefaultHeaderViewBottomMargin;
        }
        
        //set autosizing and all that so it stays put
        headerView.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin;
        
        //resize width
        CGRect newFrame;
        if (isHeaderViewInsidePadding) {
            newFrame.origin.x = self.outerPadding.left;
            newFrame.origin.y = self.outerPadding.top;
            newFrame.size.width = self.scrollView.frame.size.width - self.outerPadding.left - self.outerPadding.right;
        }
        else {
            newFrame.origin.x = 0;
            newFrame.origin.y = 0;
            newFrame.size.width = self.scrollView.frame.size.width;
        }
        //keep height
        newFrame.size.height = headerView.frame.size.height;

        //apply frame
        headerView.frame = newFrame;
        
        //keep a pointer
        self.headerView = headerView;
        
        //draw it
        [self.scrollView addSubview:headerView];
        
        //update self.actualListOrigin
        self.actualListOrigin = newFrame.size.height + marginForHeader + self.outerPadding.top;
    }
    //check header type? nil
    else if (headerView == nil) {
        //list origin is 0
        self.actualListOrigin = self.outerPadding.top;
        
        //that's it
        return;
    }
    //check header type? something else
    else {
        //raise bad type exception
        @throw [NSException exceptionWithName:GBTypeMismatchException reason:@"The object returned was not a UIView" userInfo:@{@"object":headerView}];
    }
}

-(void)_handleNoItemsView {
    //check if all columns have undefined indices
    BOOL isEmpty = YES;
    for (int columnIndex=0; columnIndex<self.numberOfColumns; columnIndex++) {
        if (!IsGBInfiniteListColumnBoundariesUndefined(self.columnStacksLoadedItemBoundaryIndices[columnIndex])) {
            isEmpty = NO;
            break;
        }
    }
    
    //first remove the old empty view if there was one
    [self.noItemsView removeFromSuperview];
    self.noItemsView = nil;
    
    //isEmpty? YES
    if (isEmpty) {
        //should we show empty view?
        UIView *noItemsView;
        if ([self.dataSource respondsToSelector:@selector(noItemsViewInInfiniteListView:)]) {
            noItemsView = [self.dataSource noItemsViewInInfiniteListView:self];
        }
        
        //is the view a view?
        if ([noItemsView isKindOfClass:[UIView class]]) {
            
            //get margin for header
            CGFloat marginForHeader;
            if ([self.dataSource respondsToSelector:@selector(marginForHeaderViewInInfiniteListView:)]) {
                marginForHeader = [self.dataSource marginForHeaderViewInInfiniteListView:self];
            }
            //just use default
            else {
                marginForHeader = kDefaultHeaderViewBottomMargin;
            }
            //calculate new size to match the width, but keep the height
            CGRect newFrame = CGRectMake(self.outerPadding.left, self.headerView.frame.origin.y + self.headerView.bounds.size.height + marginForHeader, self.scrollView.bounds.size.width - self.outerPadding.left - self.outerPadding.right, noItemsView.frame.size.height);
            
            //apply the new size
            noItemsView.frame = newFrame;
            
            //configure it to stay there
            noItemsView.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin;
            
            //draw the view
            [self.scrollView addSubview:noItemsView];
            
            //keep a pointer to the empty view
            self.noItemsView = noItemsView;
            
            //calculate the new minimum content height
            CGFloat newContentSizeHeight = self.noItemsView.frame.origin.y + self.noItemsView.frame.size.height + //empty list
            self.outerPadding.bottom; //bottom padding
            
            
            //stretch the content size, but only if it makes it bigger, never smaller
            [self _handleContentAndViewHeightForRequiredMinimumContentHeight:newContentSizeHeight];
        }
        //is the view a view? nil
        else if (noItemsView == nil) {
            //do nothing, it's already been removed
        }
        //its some other object
        else {
            //raise bad type exception
            @throw [NSException exceptionWithName:GBTypeMismatchException reason:@"The object returned was not a UIView" userInfo:@{@"object":noItemsView}];
        }
    }
    //isEmpty? NO
    else {
        //do nothing, it's already been removed
    }
}

-(void)_drawLoadingView {
    //ask if it should show a loading view? YES
    if ([self.dataSource respondsToSelector:@selector(shouldShowLoadingIndicatorInInfiniteListView:)] &&
        [self.dataSource shouldShowLoadingIndicatorInInfiniteListView:self]) {
        UIView *loadingView;
        BOOL isLoadingViewInsideOuterPadding;
        GBInfiniteListLoadingViewType loadingViewType;
        CGFloat margin;
        
        //fetch the loading view
        if ([self.dataSource respondsToSelector:@selector(loadingViewInInfiniteListView:)]) {
            loadingView = [self.dataSource loadingViewInInfiniteListView:self];
        }
        
        //check loadingview type? UIView*
        if ([loadingView isKindOfClass:[UIView class]]) {
            //ask for loading view margin stuff...
            if ([self.dataSource respondsToSelector:@selector(shouldPositionLoadingViewInsideOuterPaddingInInfiniteListView:)]) {
                isLoadingViewInsideOuterPadding = [self.dataSource shouldPositionLoadingViewInsideOuterPaddingInInfiniteListView:self];
            }
            //just use the default
            else {
                isLoadingViewInsideOuterPadding = kDefaultForShouldPositionLoadingViewInsideOuterPadding;
            }
            
            loadingViewType = GBInfiniteListLoadingViewTypeCustom;
        }
        //check loadingview type? nil
        else if (loadingView == nil) {
            //use default loading view
            loadingViewType =GBInfiniteListLoadingViewTypeDefault;
            
            //use the default padding
            isLoadingViewInsideOuterPadding = kDefaultForShouldPositionLoadingViewInsideOuterPadding;
        }
        //check loadingview type? anything else
        else {
            //raise bad type exception
            @throw [NSException exceptionWithName:GBTypeMismatchException reason:@"The object returned was not a UIView" userInfo:@{@"object":loadingView}];
        }
        
        //ask for loadingView margin...
        if ([self.dataSource respondsToSelector:@selector(marginForLoadingViewInInfiniteListView:)]) {
            margin = [self.dataSource marginForLoadingViewInInfiniteListView:self];
        }
        //just use default
        else {
            margin = kDefaultLoadingViewTopMargin;
        }
        
        //draw the loadingView
        [self _drawLoadingView:loadingView withType:loadingViewType paddingPreference:isLoadingViewInsideOuterPadding margin:margin];
    }
}

-(void)_drawLoadingView:(UIView *)loadingView withType:(GBInfiniteListLoadingViewType)type paddingPreference:(BOOL)isLoadingViewInsideOuterPadding margin:(CGFloat)loadingViewBottomMargin {
    //remove and release any potential previous loading views
    if (self.loadingView) {
        [self.loadingView removeFromSuperview];
        self.loadingView = nil;
    }
    
    //set the view
    if (type == GBInfiniteListLoadingViewTypeDefault) {
        self.loadingView = self.defaultLoadingView;
    }
    else if (type == GBInfiniteListLoadingViewTypeCustom) {
        self.loadingView = loadingView;
    }
    
    //calculate the new view frame
    CGRect newLoadingViewFrame;
    CGFloat spacingAfterLoadingView;
    
    //find the longest column
    GBFastArray *columnStack;
    GBInfiniteListColumnBoundaries columnBoundaries;
    CGFloat runningLongestColumnLength = self.actualListOrigin;
    CGFloat currentColumnHeight;
    GBInfiniteListItemMeta lastItemInColumn;
    for (int columnIndex=0; columnIndex<self.numberOfColumns; columnIndex++) {
        columnStack = self.columnStacks[columnIndex];
        columnBoundaries = self.columnStacksLoadedItemBoundaryIndices[columnIndex];
        
        //if the index is undefined, continue
        if (columnBoundaries.lastLoadedIndex == GBColumnIndexUndefined) {
            continue;
        }
        
        lastItemInColumn = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:columnBoundaries.lastLoadedIndex];
        
        currentColumnHeight = lastItemInColumn.geometry.origin + lastItemInColumn.geometry.height;
        
        if (currentColumnHeight > runningLongestColumnLength) {
            runningLongestColumnLength = currentColumnHeight;
        }
    }
    CGFloat furthestItemLastPoint = runningLongestColumnLength;
    
    //height stays the same
    newLoadingViewFrame.size.height = self.loadingView.frame.size.height;
    
    //origin and width depend on whether margin is ignored or not
    if (isLoadingViewInsideOuterPadding)  {
        newLoadingViewFrame.origin.x = self.outerPadding.left;
        newLoadingViewFrame.origin.y = furthestItemLastPoint + loadingViewBottomMargin;
        newLoadingViewFrame.size.width = self.scrollView.bounds.size.width - self.outerPadding.left - self.outerPadding.right;
        spacingAfterLoadingView = self.outerPadding.bottom;
    }
    else {
        newLoadingViewFrame.origin.x = 0;
        newLoadingViewFrame.origin.y = furthestItemLastPoint + loadingViewBottomMargin + self.outerPadding.bottom;
        newLoadingViewFrame.size.width = self.scrollView.bounds.size.width;
        spacingAfterLoadingView = 0;
    }
    
    //set the view frame
    self.loadingView.frame = newLoadingViewFrame;
    
    //draw the actual view
    [self.scrollView addSubview:self.loadingView];
    
    //resize the scrollview, but only to increase size
    CGFloat newContentSizeHeight = newLoadingViewFrame.origin.y + newLoadingViewFrame.size.height + spacingAfterLoadingView;
    [self _handleContentAndViewHeightForRequiredMinimumContentHeight:newContentSizeHeight];
}

#pragma mark - Private API: Geometry stuff

-(void)_syncHeight {
    CGFloat minimumContentHeight = self.scrollView.contentSize.height;
    [self _handleContentAndViewHeightForRequiredMinimumContentHeight:minimumContentHeight];
}

-(void)_handleContentAndViewHeightForRequiredMinimumContentHeight:(CGFloat)minContentHeight {
    //always resize the contentSize
    if (minContentHeight > self.scrollView.contentSize.height) {
        self.scrollView.contentSize = CGSizeMake(self.scrollView.contentSize.width, minContentHeight);
    }
    
    //if the table is static, resize own frame and scrollView frame as well
    if (self.staticMode) {
        CGFloat currentContentHeight = self.scrollView.contentSize.height;
        
        //change scrollview contentSize
        //noop, already done above
        
        //change the scrollview height
        self.scrollView.frame = CGRectMake(self.scrollView.frame.origin.x,
                                           self.scrollView.frame.origin.y,
                                           self.scrollView.frame.size.width,
                                           currentContentHeight);
        
        //change own height
        self.frame = CGRectMake(self.frame.origin.x,
                                self.frame.origin.y,
                                self.frame.size.width,
                                currentContentHeight);
    }
}

-(void)_requestAndPrepareGeometryStuff {
    //required
    self.numberOfColumns = [self.dataSource numberOfColumnsInInfiniteListView:self];
    
    //optional
    if ([self.dataSource respondsToSelector:@selector(loadTriggerDistanceInInfiniteListView:)]) {
        self.loadTriggerDistance = [self.dataSource loadTriggerDistanceInInfiniteListView:self];
    }
    else {
        self.loadTriggerDistance = kDefaultLoadTriggerDistance;
    }
    
    //optional
    if ([self.dataSource respondsToSelector:@selector(outerPaddingInInfiniteListView:)]) {
        self.outerPadding = [self.dataSource outerPaddingInInfiniteListView:self];
    }
    else {
        self.outerPadding = kDefaultOuterPadding;
    }
    
    //optional
    if ([self.dataSource respondsToSelector:@selector(horizontalColumnMarginInInfiniteListView:)]) {
        self.horizontalColumnMargin = [self.dataSource horizontalColumnMarginInInfiniteListView:self];
    }
    else {
        self.horizontalColumnMargin = kDefaultHorizontalColumnMargin;
    }
    
    //optional
    if ([self.dataSource respondsToSelector:@selector(verticalItemMarginInInfiniteListView:)]) {
        self.verticalItemMargin = [self.dataSource verticalItemMarginInInfiniteListView:self];
    }
    else {
        self.verticalItemMargin = kDefaultVerticalItemMargin;
    }
    
    //calculate the requiredViewWidth
    self.requiredViewWidth = (self.scrollView.bounds.size.width - (self.outerPadding.left + self.outerPadding.right) - ((self.numberOfColumns - 1) * self.horizontalColumnMargin)) / self.numberOfColumns;
}

#pragma mark - Private API: Data dance

-(void)_iterateWithHint:(GBInfiniteListDirectionMovedHint)directionMovedHint recyclerEnabled:(BOOL)shouldRecycle {
    if (self.isDataDanceActive) {
        if (shouldRecycle) [self _recyclerLoopWithHint:directionMovedHint forcedRecyclingOfEverything:NO];
        [self _drawAndLoadLoopWithHint:directionMovedHint];
    }
}

-(void)_recyclerLoopWithHint:(GBInfiniteListDirectionMovedHint)directionMovedHint forcedRecyclingOfEverything:(BOOL)forceRecycleAll {
    //prepare
    CGFloat loadedZoneTop = self.scrollView.contentOffset.y;
    CGFloat loadedZoneHeight = self.scrollView.bounds.size.height + self.loadTriggerDistance;
    GBFastArray *columnStack;
    NSInteger firstLoadedIndex;
    NSInteger lastLoadedIndex;
    NSInteger index;
    NSInteger columnIndex;
    GBInfiniteListItemMeta nextItemUp;
    
    int loopNumber;
    
    //each column
    for (columnIndex=0; columnIndex<self.numberOfColumns; columnIndex++) {
        //if there's nothing loaded in this column, skip to next one
        if (IsGBInfiniteListColumnBoundariesUndefined(self.columnStacksLoadedItemBoundaryIndices[columnIndex])) {
            continue;
        }

        //remember the column stack for this column iteration
        columnStack = self.columnStacks[columnIndex];
        
        //remember the indices
        firstLoadedIndex = self.columnStacksLoadedItemBoundaryIndices[columnIndex].firstLoadedIndex;
        lastLoadedIndex = self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex;
        
        //not forced
        if (!forceRecycleAll) {
            //direction moved: down || none
            if (directionMovedHint == GBInfiniteListDirectionMovedHintDown || directionMovedHint == GBInfiniteListDirectionMovedHintNone) {
                //enumerate downwards, starting from top
                loopNumber = 1;
                for (index = firstLoadedIndex; index <= lastLoadedIndex; index++) {
                    goto innerLoop;
                    loop1: continue;
                    exit1: break;
                }
            }
            
            //direction moved: up || none
            if (directionMovedHint == GBInfiniteListDirectionMovedHintUp || directionMovedHint == GBInfiniteListDirectionMovedHintNone) {
                //enumerate upwards, starting from bottom
                loopNumber = 2;
                for (index = lastLoadedIndex; index >= firstLoadedIndex; index--) {
                    goto innerLoop;                    
                    loop2: continue;
                    exit2: break;
                }
            }

        }
        //forced
        else {
            //enumerate downwards, starting from top
            for (index = firstLoadedIndex; index <= lastLoadedIndex; index++) {
                //get item
                nextItemUp = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:index];
                
                //recycle
                [self _recycleItemWithMeta:nextItemUp indexInColumn:index inColumnWithIndex:columnIndex inColumnBoundaryWithAddress:self.columnStacksLoadedItemBoundaryIndices[columnIndex]];
            }
        }
    }
    
    return;
    
innerLoop:
    //get item
    nextItemUp = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:index];
    
    //if view is visible
    if (Lines1DOverlap(loadedZoneTop, loadedZoneHeight + self.verticalItemMargin, nextItemUp.geometry.origin, nextItemUp.geometry.height)) {//need to add the verticalItemMargin because items are loaded as soon edge of the previous item is exceeded, so they can be placed offscreen if the scroll distance is less than the margin
        //done with this column, exit this loop
        if (loopNumber == 1) { goto exit1; } else { goto exit2; }
    }
    //if invisible
    else {
        //recycle
        [self _recycleItemWithMeta:nextItemUp indexInColumn:index inColumnWithIndex:columnIndex inColumnBoundaryWithAddress:self.columnStacksLoadedItemBoundaryIndices[columnIndex]];
    }
    
    //go back into loop
    if (loopNumber == 1) { goto loop1; } else { goto loop2; }


    //each column
        //make sure that there is something to recycle
            //if there isnt, skip to next column
    
        //not forced
            //direction moved: down || none
                //enumerate downwards, starting from top
                    //if view is visible
                        //done with this column
                    //if invisible
                        //recycle
            
            //direction moved: up || none
                //enumerate upwards, starting from bottom
                    //if view is visible
                        //done with this column
                    //if invisible
                        //recycle
        //forced
            //enumerate downwards, starting from top
                //recycle    
}

-(void)_recycleItemWithMeta:(GBInfiniteListItemMeta)itemMeta indexInColumn:(NSUInteger)index inColumnWithIndex:(NSUInteger)columnIndex inColumnBoundaryWithAddress:(GBInfiniteListColumnBoundaries)columnBoundaries {
    NSNumber *key = @(itemMeta.itemIdentifier);
    UIView *oldView = self.loadedViews[key];
    
    //check to make sure the view is actually loaded before we try to re-unload it and confuse our delegate
    if ([self.loadedViews objectForKey:key]) {
        //tell our delegate that we are about to recycled the view
        if ([self.dataSource respondsToSelector:@selector(infiniteListView:willRecycleView:usedByItem:)]) {
            [self.dataSource infiniteListView:self willRecycleView:oldView usedByItem:itemMeta.itemIdentifier];
        }
    }
    
    //if there are at least 2 items loaded: i.e. last-first>=1
    if (columnBoundaries.lastLoadedIndex - columnBoundaries.firstLoadedIndex >= 1) {
        //if the view was on the front
        if (columnBoundaries.firstLoadedIndex == index) {
            //update column boundaries by moving front index up 1
            self.columnStacksLoadedItemBoundaryIndices[columnIndex].firstLoadedIndex += 1;
        }
        //must be off the end in this case
        else if (columnBoundaries.lastLoadedIndex == index) {
            //update column boundaries by moving last index down by 1
            self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex -= 1;
        }
        else {
            l(@"!!!!!!!!!!!!!!!! how the fuck did this happen? the recycler should only ask to recycle views on edges of the loaded views");
        }
    }
    //if the indices are undefined
    else if (IsGBInfiniteListColumnBoundariesUndefined(columnBoundaries)) {
        //do nothing, i shouldnt be recycling!
        l(@"!!!!!!!!!!!!! why am i recycling when there is nothing loaded?... its no big deal but worth checking out. its prolly safe to do nothing if this doesnt happen regularly");
    }
    //if there is just 1 loaded
    else if (columnBoundaries.lastLoadedIndex == columnBoundaries.firstLoadedIndex) {
        //change the indices to indicate nothing is loaded
        self.columnStacksLoadedItemBoundaryIndices[columnIndex] = GBInfiniteListColumnBoundariesUndefined;
    }
    else {
        l(@"!!!!!!!!! this also shudnt happen, wtf? how did we get here?");
    }
    
    //set the last unloaded pointer
    self.lastRecycledItemsIdentifiers[columnIndex] = index;
    
    //check to make sure the view is actually loaded before we try to re-unload it and confuse our delegate
    if ([self.loadedViews objectForKey:key]) {
        //put him in the recycleable pool, the oldView pointer above has a strong ref so don't worry, we won't loose him
        if ([oldView.reuseIdentifier isKindOfClass:[NSString class]]) {
            //make sure we have a pool for that reuseIdentifier
            if (!self.recycledViewsPool[oldView.reuseIdentifier]) {
                self.recycledViewsPool[oldView.reuseIdentifier] = [NSMutableArray new];
            }
            
            //capacity check for pool, see if there is still space left
            if (((NSArray *)self.recycledViewsPool[oldView.reuseIdentifier]).count < self.maxReusableViewsPoolSize) {
                //add it to the pool
                [self.recycledViewsPool[oldView.reuseIdentifier] addObject:oldView];
            }
        }
        
        //take him offscreen
        [oldView removeFromSuperview];
        
        //take him out of the loaded items list
        [self.loadedViews removeObjectForKey:key];
        
        //send the delegate an infiniteListView:view:correspondingToItemDidGoOffScreen: message
        if ([self.delegate respondsToSelector:@selector(infiniteListView:view:correspondingToItemDidGoOffScreen:)]) {
            [self.delegate infiniteListView:self view:oldView correspondingToItemDidGoOffScreen:itemMeta.itemIdentifier];
        }
        
        //send the delegate a message that the list of visible items changed
        if ([self.delegate respondsToSelector:@selector(infiniteListView:listOfVisibleItemsChanged:)]) {
            [self.delegate infiniteListView:self listOfVisibleItemsChanged:[self.loadedViews allKeys]];
        }
        
        //send the dataSource an infiniteListView:didRecycleView:lastUsedByItem: message
        if ([self.dataSource respondsToSelector:@selector(infiniteListView:didRecycleView:lastUsedByItem:)]) {
            [self.dataSource infiniteListView:self didRecycleView:oldView lastUsedByItem:itemMeta.itemIdentifier];
        }
        
    }
}

//draw+load loop: a loop that tries to fill the screen by asking for more data, or if there isnt any more available: starting the dataload procedure in hopes of getting called again when more is available
-(void)_drawAndLoadLoopWithHint:(GBInfiniteListDirectionMovedHint)directionMovedHint {
    //check if there is a gap?
    GBInfiniteListGap nextGap = [self _findNextGapWithHint:directionMovedHint];
    
    //check if there is a gap? end of list
    if (nextGap.type == GBInfiniteListTypeOfGapEndOfList) {
        //calculate the next item identifier
        NSUInteger newItemIdentifier = self.lastLoadedItemIdentifier + 1;
        
        //ask if there is another item currently available? YES
        if ([self.dataSource isViewForItem:newItemIdentifier currentlyAvailableInInfiniteListView:self]) {
            //ask for the item
            UIView *newItemView = [self.dataSource viewForItem:newItemIdentifier inInfiniteListView:self];
            //check that item is a UIView? YES
            if ([newItemView isKindOfClass:[UIView class]]) {
                //check to make sure item width fits? YES
                if (newItemView.frame.size.width == self.requiredViewWidth) {
                    //draw the item (add the subview, and stretch the scrollview content size) and record it in the internal logic (things like the size)
                    [self _drawAndStoreNewItem:newItemIdentifier withView:newItemView inColumn:nextGap.columnIdentifier];
                    
                    //go back to checking if there is a gap, i.e. recurse
                    [self _drawAndLoadLoopWithHint:directionMovedHint];
                }
                //check to make sure item width fits? NO
                else {
                    //raise width mismath exception
                    @throw [NSException exceptionWithName:GBWidthMismatchException reason:@"The view returned has the wrong width. Make sure the view frame width matches the column width." userInfo:@{@"object": newItemView, @"requiredViewWidth": @(self.requiredViewWidth)}];
                }
            }
            //check that item is a UIView? NO
            else {
                //raise bad type exception
                @throw [NSException exceptionWithName:GBTypeMismatchException reason:@"The object returned was not a UIView" userInfo:@{@"object":newItemView}];
            }
        }
        //ask if there is another item currently available? NO
        else {
            //check to see if it has already requested more items? NO
            if (!self.hasRequestedMoreItems) {
                //ask if it can load more items? YES
                if ([self.dataSource canLoadMoreItemsInInfiniteListView:self]) {
                    //send delegate the infiniteListViewWillStartLoadingMoreItems: message
                    if ([self.delegate respondsToSelector:@selector(infiniteListViewWillStartLoadingMoreItems:)]) {
                        [self.delegate infiniteListViewWillStartLoadingMoreItems:self];
                    }
                    
                    //remember that you're expecting to receive the moreItemsAvailable: message
                    self.hasRequestedMoreItems = YES;
                    
                    //draw loading view
                    [self _drawLoadingView];
                    
                    //send datasource the startLoadingMoreItemsInInfiniteListView: message
                    [self.dataSource startLoadingMoreItemsInInfiniteListView:self];
                }
                //ask if it can load more items? NO
                else {
                    //send infiniteListViewNoMoreItemsAvailable: to delegate
                    if ([self.delegate respondsToSelector:@selector(infiniteListViewNoMoreItemsAvailable:)]) {
                        [self.delegate infiniteListViewNoMoreItemsAvailable:self];
                    }
                    
                    //handle the empty view
                    [self _handleNoItemsView];
                    
                    //we're done
                }
            }
            //check to see if it has already requested more items? NO
            else {
                //we're done
            }
        }
    }
    //check if there is a gap? old one (doesn't matter which side)
    else if (nextGap.type == GBInfiniteListTypeOfGapExisting) {
        //ask for the item
        UIView *oldItemView = [self.dataSource viewForItem:nextGap.itemIdentifier inInfiniteListView:self];
        
        //check that item is UIView? YES
        if ([oldItemView isKindOfClass:[UIView class]]) {
            //fetch the old meta
            GBInfiniteListItemMeta oldItemMeta = *(GBInfiniteListItemMeta *)[self.columnStacks[nextGap.columnIdentifier] itemAtIndex:nextGap.indexInColumnStack];
            
            //check to make sure item height matches the stored one and width the required width? YES
            if (oldItemView.frame.size.height == oldItemMeta.geometry.height && oldItemView.frame.size.width == self.requiredViewWidth) {
                //draw the item in his old position
                [self _drawOldItemWithMeta:oldItemMeta view:oldItemView indexInColumnStack:nextGap.indexInColumnStack inColumn:nextGap.columnIdentifier];
                
                //go back to checking if there is a gap, i.e. recurse
                [self _drawAndLoadLoopWithHint:directionMovedHint];
            }
            //check to make sure item height matches the stored one and width the required width? NO
            else {
                //raise size mismath exception
                @throw [NSException exceptionWithName:GBSizeMismatchException reason:@"The view returned has the wrong size. Make sure the view frame matches the old one." userInfo:@{@"object": oldItemView, @"requiredViewWidth": @(self.requiredViewWidth), @"requiredViewHeight": @(oldItemMeta.geometry.height)}];
            }
        }
        //check that item is a UIView? NO
        else {
            //raise bad type exception
            @throw [NSException exceptionWithName:GBTypeMismatchException reason:@"The object returned was not a UIView" userInfo:@{@"object":oldItemView}];
        }
    }
    //check if there is a gap? NO
    else if (nextGap.type == GBInfiniteListTypeOfGapNone) {
        //we're done
    }
}

-(void)_drawOldItemWithMeta:(GBInfiniteListItemMeta)itemMeta view:(UIView *)itemView indexInColumnStack:(NSUInteger)indexInColumnStack inColumn:(NSUInteger)columnIndex {
    //update column boundary
    //boundary: undefined
    if (IsGBInfiniteListColumnBoundariesUndefined(self.columnStacksLoadedItemBoundaryIndices[columnIndex])) {
        //set first and last to the new index
        self.columnStacksLoadedItemBoundaryIndices[columnIndex].firstLoadedIndex = indexInColumnStack;
        self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex = indexInColumnStack;
    }
    //boundary: defined
    else {
        //are we extending first? (first - 1 == index)
        if (self.columnStacksLoadedItemBoundaryIndices[columnIndex].firstLoadedIndex - 1 == indexInColumnStack) {
            //first = item
            self.columnStacksLoadedItemBoundaryIndices[columnIndex].firstLoadedIndex = indexInColumnStack;
        }
        //are we extending last? (last + 1 == index)
        else if (self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex + 1 == indexInColumnStack) {
            //last = item
            self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex = indexInColumnStack;
        }
        //otherwise
        else {
            l(@"!!!!!!!!!!!!wtf how did we end up here. i though gaps were only every found immediately before the first loaded item, or immediately after the last loaded item");
        }
    }
    
    //don't need to add it to columnStack because it's alread in there
    
    //find the left origin of the column
    CGFloat columnOrigin = self.outerPadding.left + columnIndex * (self.requiredViewWidth + self.horizontalColumnMargin);
    
    //make sure the autoresizingmask is set appropriately
    itemView.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleRightMargin;
    
    //set the subview frame
    itemView.frame = CGRectMake(columnOrigin, itemMeta.geometry.origin, self.requiredViewWidth, itemMeta.geometry.height);
    
    //add the subview to the loadedViews
    self.loadedViews[@(itemMeta.itemIdentifier)] = itemView;
    
    //draw the actual subview
    [self.scrollView addSubview:itemView];
    
    //send the delegate an infiniteListView:view:correspondingToItemDidComeOnScreen: message
    if ([self.delegate respondsToSelector:@selector(infiniteListView:view:correspondingToItemDidComeOnScreen:)]) {
        [self.delegate infiniteListView:self view:itemView correspondingToItemDidComeOnScreen:itemMeta.itemIdentifier];
    }
    
    //send the delegate a message that the list of visible items changed
    if ([self.delegate respondsToSelector:@selector(infiniteListView:listOfVisibleItemsChanged:)]) {
        [self.delegate infiniteListView:self listOfVisibleItemsChanged:[self.loadedViews allKeys]];
    }
}

-(void)_drawAndStoreNewItem:(NSUInteger)newItemIdentifier withView:(UIView *)itemView inColumn:(NSUInteger)columnIndex {
    //create meta struct which gets filled in along the way
    GBInfiniteListItemMeta newItemMeta;
    newItemMeta.itemIdentifier = newItemIdentifier;
    
    //find out where to draw the item
    GBFastArray *columnStack = self.columnStacks[columnIndex];
    GBInfiniteListItemGeometry itemGeometry;
    itemGeometry.height = itemView.frame.size.height;
    
    NSUInteger newStackIndex;
    
    //if its the first item, stick it to the top, where the top is origin+outerPadding.top+header+headerMargin
    if (columnStack.isEmpty) {
        itemGeometry.origin = self.actualListOrigin;
        
        //set the indices to both be 0
        self.columnStacksLoadedItemBoundaryIndices[columnIndex] = (GBInfiniteListColumnBoundaries){0,0};
        newStackIndex = self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex;
    }
    //otherwise it's lastitem.origin + lastitem.height + verticalItemMargin
    else {
        NSUInteger lastLoadedIndex;
        //if buindaries are undefined all were unloaded due to not being visible, set indicies to be the latest one in a column stack
        if (IsGBInfiniteListColumnBoundariesUndefined(self.columnStacksLoadedItemBoundaryIndices[columnIndex])) {
            newStackIndex = columnStack.count;
            self.columnStacksLoadedItemBoundaryIndices[columnIndex].firstLoadedIndex = newStackIndex;
            self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex = newStackIndex;
            
            lastLoadedIndex = columnStack.count - 1;
        } else {
            lastLoadedIndex = self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex;
            // expand the last column boundary by 1
            self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex += 1;
            newStackIndex = self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex;
        }
        
        GBInfiniteListItemMeta lastItem = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:lastLoadedIndex];
        itemGeometry.origin = lastItem.geometry.origin + lastItem.geometry.height + self.verticalItemMargin;
    }
    
    //fill in the geometry
    newItemMeta.geometry = itemGeometry;
    
    //and add the meta struct to the columnStack at the correct index
    [columnStack insertItem:&newItemMeta atIndex:newStackIndex];
    
    //find the left origin of the column
    CGFloat columnOrigin = self.outerPadding.left + columnIndex * (self.requiredViewWidth + self.horizontalColumnMargin);
    
    //make sure the autoresizingmask is set appropriately
    itemView.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleRightMargin;
    
    //set the subview frame
    itemView.frame = CGRectMake(columnOrigin, itemGeometry.origin, self.requiredViewWidth, itemGeometry.height);
    
    //add the subview to the loadedViews
    self.loadedViews[@(newItemIdentifier)] = itemView;
    
    //set the lastLoadedItem
    self.lastLoadedItemIdentifier = newItemIdentifier;
    
    //draw the actual subview
    [self.scrollView addSubview:itemView];
    
    //stretch the content size, but only if it makes it bigger, never smaller
    CGFloat newContentSizeHeight = itemGeometry.origin + itemGeometry.height + self.outerPadding.bottom;
    [self _handleContentAndViewHeightForRequiredMinimumContentHeight:newContentSizeHeight];
    
    //send the delegate an infiniteListView:view:correspondingToItemDidComeOnScreen: message
    if ([self.delegate respondsToSelector:@selector(infiniteListView:view:correspondingToItemDidComeOnScreen:)]) {
        [self.delegate infiniteListView:self view:itemView correspondingToItemDidComeOnScreen:newItemMeta.itemIdentifier];
    }
    
    //send the delegate a message that the list of visible items changed
    if ([self.delegate respondsToSelector:@selector(infiniteListView:listOfVisibleItemsChanged:)]) {
        [self.delegate infiniteListView:self listOfVisibleItemsChanged:[self.loadedViews allKeys]];
    }
}

-(GBInfiniteListGap)_findNextGapWithHint:(GBInfiniteListDirectionMovedHint)directionMovedHint {
    //prepare
    CGFloat loadedZoneTop = self.scrollView.contentOffset.y;
    CGFloat loadedZoneHeight = self.scrollView.bounds.size.height + self.loadTriggerDistance;
    CGFloat loadedZoneBottom = loadedZoneTop + loadedZoneHeight;
    GBFastArray *columnStack;
    GBInfiniteListColumnBoundaries columnBoundaries;
    NSUInteger numberOfColumns = self.numberOfColumns;
    NSUInteger columnIndex;
    GBInfiniteListItemMeta nextItemUp;
    NSInteger index;
    NSUInteger firstLoadedIndex;
    NSUInteger lastLoadedIndex;
    NSUInteger runningShortestColumnIndex = NSUIntegerMax;
    CGFloat runningShortestColumnLength = CGFLOAT_MAX;
    CGFloat currentColumnLength;
    
    //move direction: down || none
    if (directionMovedHint == GBInfiniteListDirectionMovedHintDown || directionMovedHint == GBInfiniteListDirectionMovedHintNone) {
        //each column
        for (columnIndex=0; columnIndex<numberOfColumns; columnIndex++) {
            //prepare
            columnStack = self.columnStacks[columnIndex];
            columnBoundaries = self.columnStacksLoadedItemBoundaryIndices[columnIndex];
//            firstLoadedIndex = self.columnStacksLoadedItemBoundaryIndices[columnIndex].firstLoadedIndex;//removed at behest of Clang analyzer
            lastLoadedIndex = self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex;
            
            //is column empty?
            if (columnStack.isEmpty) {
                //return that as new gap
                GBInfiniteListGap newBottomGap;
                newBottomGap.type = GBInfiniteListTypeOfGapEndOfList;
                newBottomGap.columnIdentifier = columnIndex;
                return newBottomGap;
            }
            //else is something still loaded? (! indicesUndefined)
            else if (!IsGBInfiniteListColumnBoundariesUndefined(columnBoundaries)) {
                //start at bottom, enumerate downwards sequentially
                for (index = lastLoadedIndex; YES; index++) {
                    //find the item first
                    nextItemUp = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:index];
                    
                    //item surpasses screen? o + h > loadedZoneBottom // foo maybe add margin
                    if (nextItemUp.geometry.origin + nextItemUp.geometry.height > loadedZoneBottom)
                        //break to continue to next column
                        break;
                    //item surpasses screen? NO
                    else {
                        //is item last one? index == count-1
                        if (index == columnStack.count-1) {
                            //we need to calculate the length of the column first
                            GBInfiniteListItemMeta lastItemInColumn = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:index];
                            currentColumnLength = lastItemInColumn.geometry.origin + lastItemInColumn.geometry.height;
                            
                            //then check if its shorter or not than what we currently think is the shortest
                            if (currentColumnLength < runningShortestColumnLength) {
                                runningShortestColumnIndex = columnIndex;
                                runningShortestColumnLength = currentColumnLength;
                            }
                            
                            //break out of this search to continue to next column
                            break;
                        }
                        //is item last one? NO
                        else {
                            //found it! get the next old guy
                            GBInfiniteListItemMeta nextOldItem = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:index+1];
                            
                            //return the next guy as the old gap!
                            GBInfiniteListGap oldGap;
                            oldGap.type = GBInfiniteListTypeOfGapExisting;
                            oldGap.columnIdentifier = columnIndex;
                            oldGap.itemIdentifier = nextOldItem.itemIdentifier;
                            oldGap.indexInColumnStack = index+1;
                            return oldGap;
                        }
                    }
                }
            }
            //else (so column isn't empty, but everything is unloaded)
            else {
                //do binary search for a visible item, top/low: lastUnloaded, bottom/high: count-1
                index = [columnStack binarySearchForIndexWithLow:self.lastRecycledItemsIdentifiers[columnIndex] high:columnStack.count-1 searchLambda:^GBSearchResult(void *candidateItem) {
                    GBInfiniteListItemMeta nativeCandidateItem = *(GBInfiniteListItemMeta *)candidateItem;
                    
                    //if visible: bingo
                    if (Lines1DOverlap(loadedZoneTop, loadedZoneHeight, nativeCandidateItem.geometry.origin, nativeCandidateItem.geometry.height)) {
                        return GBSearchResultMatch;
                    }
                    //if the item is somewhere before, then we've gone too far
                    else if (nativeCandidateItem.geometry.origin > loadedZoneTop) {
                        return GBSearchResultHigh;
                    }
                    //only other option is that the item is after
                    else {
                        return GBSearchResultLow;
                    }
                }];
                
                // scrolled too far, there are no visible items in the column
                if (index == kGBSearchResultNotFound) {
                    //we return GBInfiniteListTypeOfGapEndOfList gap with index of the smallest columnLenght
                    //we need to calculate the length of the column first
                    GBInfiniteListItemMeta lastItemInColumn = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:columnStack.count-1];
                    currentColumnLength = lastItemInColumn.geometry.origin + lastItemInColumn.geometry.height;
                    
                    //then check if its shorter or not than what we currently think is the shortest
                    if (currentColumnLength < runningShortestColumnLength) {
                        runningShortestColumnIndex = columnIndex;
                        runningShortestColumnLength = currentColumnLength;
                    }
                    
                    //break out of this search to continue to next column
                    break;
                }
                
                //as soon as we find one, do a sequential search upwards to find the first visible one and return that one as the gap (this way when we recurse back he will continue searching properly as if we didn't have to do this tricky binary search)
                while (index > 0) {
                    //get the next item up
                    nextItemUp = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:index-1];
                    
                    //if the next one is invisible? YES
                    if (!Lines1DOverlap(loadedZoneTop, loadedZoneHeight, nextItemUp.geometry.origin, nextItemUp.geometry.height)) {
                        //then that means the current one is the last visible one... so return that as the gap
                        
                        //return him as the old gap!
                        GBInfiniteListGap oldGap;
                        oldGap.type = GBInfiniteListTypeOfGapExisting;
                        oldGap.columnIdentifier = columnIndex;
                        oldGap.itemIdentifier = nextItemUp.itemIdentifier;
                        oldGap.indexInColumnStack = index-1;
                        return oldGap;
                    }
                    
                    //otherwise go up one more
                    index -= 1;
                }
            }
        }
            
        //if we got here it means no colums had any old candidates, we should see if that search rustled up some new potential new candidates
        //if there are shortest column candidates? YES
        if (runningShortestColumnIndex != NSUIntegerMax) {
            //return the shortest column gap as a new gap
            GBInfiniteListGap newGap;
            newGap.type = GBInfiniteListTypeOfGapEndOfList;
            newGap.columnIdentifier = runningShortestColumnIndex;
            return newGap;
        }
    }
    
    //move direction: up
    if (directionMovedHint == GBInfiniteListDirectionMovedHintUp) {
        //each column
        for (columnIndex=0; columnIndex<numberOfColumns; columnIndex++) {
            //prepare
            columnStack = self.columnStacks[columnIndex];
            columnBoundaries = self.columnStacksLoadedItemBoundaryIndices[columnIndex];
            firstLoadedIndex = self.columnStacksLoadedItemBoundaryIndices[columnIndex].firstLoadedIndex;
//            lastLoadedIndex = self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex;//removed at behest of Clang analyzer
            
            //is column empty?
            if (columnStack.isEmpty) {
                //continue to next column, can't be any gaps above in that case
                continue;
            }
            //else if first loaded item is 0? YES
            else if (firstLoadedIndex == 0) {
                //continue to next column, can't be any gaps above either in this case
                continue;
            }
            //else if something is still loaded? (! indicesUndefined)
            else if (!IsGBInfiniteListColumnBoundariesUndefined(columnBoundaries)) {
                //start at top, enumerate upwards sequentially
                for (index = firstLoadedIndex; index>=0; index--) {
                    //find the item first
                    nextItemUp = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:index];
                    
                    //item surpasses screen? o < loadedZoneTop
                    if (nextItemUp.geometry.origin < loadedZoneTop)
                        //break to continue to next column
                        break;
                    //item surpasses screen? NO
                    else {
                        //is it the first item? NO
                        if (index > 0) {
                            //found it! get the previous old guy
                            GBInfiniteListItemMeta nextOldItem = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:index-1];

                            //return the previous guy as the old gap!
                            GBInfiniteListGap oldGap;
                            oldGap.type = GBInfiniteListTypeOfGapExisting;
                            oldGap.columnIdentifier = columnIndex;
                            oldGap.itemIdentifier = nextOldItem.itemIdentifier;
                            oldGap.indexInColumnStack = index-1;
                            return oldGap;
                        }
                    }
                }
            }
            //else (column isnt empty, not first item, nothing is still loaded)
            else {
                //do binary search for a visible item, top/low:0, bottom/high: lastUnloaded
                index = [columnStack binarySearchForIndexWithLow:0 high:self.lastRecycledItemsIdentifiers[columnIndex] searchLambda:^GBSearchResult(void *candidateItem) {
                    GBInfiniteListItemMeta nativeCandidateItem = *(GBInfiniteListItemMeta *)candidateItem;
                    
                    //if visible: bingo
                    if (Lines1DOverlap(loadedZoneTop, loadedZoneHeight, nativeCandidateItem.geometry.origin, nativeCandidateItem.geometry.height)) {
                        return GBSearchResultMatch;
                    }
                    //if the item is somewhere before, then we've gone too far
                    else if (nativeCandidateItem.geometry.origin > loadedZoneTop) {
                        return GBSearchResultHigh;
                    }
                    //only other option is that the item is after
                    else {
                        return GBSearchResultLow;
                    }
                }];
                
                // scrolled too far, the column is empty and there is no visible items in the column
                if (index == kGBSearchResultNotFound) {
                    break;
                }
                
                //as soon as we find one, do a sequential search downwards to find the last visibleone, and return that one as gap (this way when we recurse back he will continue searching properly as if we didn't have to do this tricky binary search)
                NSUInteger lastIndex = columnStack.count-1;
                while (index < lastIndex) {
                    //get the next item down
                    nextItemUp = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:index+1];
                    
                    //if the next one is invisible? YES
                    if (!Lines1DOverlap(loadedZoneTop, loadedZoneHeight, nextItemUp.geometry.origin, nextItemUp.geometry.height)) {
                        //then that means the current one is the last visible one... so return that as the gap
                        
                        //return him as the old gap!
                        GBInfiniteListGap oldGap;
                        oldGap.type = GBInfiniteListTypeOfGapExisting;
                        oldGap.columnIdentifier = columnIndex;
                        oldGap.itemIdentifier = nextItemUp.itemIdentifier;
                        oldGap.indexInColumnStack = index+1;
                        return oldGap;
                    }
                    
                    //otherwise go down one more
                    index += 1;
                }
                
                //is item is the last one and is visible
                nextItemUp = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:index];
                GBInfiniteListGap oldGap;
                oldGap.type = GBInfiniteListTypeOfGapExisting;
                oldGap.columnIdentifier = columnIndex;
                oldGap.itemIdentifier = nextItemUp.itemIdentifier;
                oldGap.indexInColumnStack = index;
                return oldGap;
            }
        }
    }

    //if we got here, then theres no gap
    GBInfiniteListGap noGap;
    noGap.type = GBInfiniteListTypeOfGapNone;
    return noGap;
}

@end


//kickoffs by: 1)_startDataDance and 2)scrolling of scrollView, 3)moreItemsAvailable message

//gap search strategy:
    //move direction: down || none
        //each column
            //is column empty? (columnstack.count == 0)
                //return that as new gap
            //else is something still loaded? (! indicesUndefined)
                //start at bottom, enumerate downwards sequentially
                    //item surpasses screen? YES
                        //continue to next column
                    //item surpasses screen? NO
                        //is item last one? index == count-1
                            //remember as candidate: this is the last item in the column
                        //is item last one? NO
                            //found it! return the old gap!
            //else (so column isn't empty, but everything is unloaded)
                //do binary search for a visible item, top: lastUnloaded, bottom: count-1
                //as soon as we find one, do a sequential search to find the first visible one and return that one as the gap (this way when we recurse back he will continue searching properly as if we didn't have to do this tricky binary search)
        
        //if we got here it means all columns are depleted
        //if there are shortest column candidates? YES
            //find the shortest column
            //return the shortest column gap as a new gap


    //move direction: up
        //each column
            //is column empty? (columnstack.count == 0)
                //continue, can't be any gaps above in that case
            //else if first loaded item is 0? YES
                //continue, can't be any gaps above either in this case
            //else if something is still loaded? (! indicesUndefined)
                //start at top, enumerate upwards sequentially
                    //item surpasses screen? YES
                        //continue to next column
                    //item supasses screen? NO
                        //is it the first item? NO
                            //found it, return gap!
            //else (column isnt empty, not first item, nothing is still loaded)
                //do binary search for a visible item, top:0, bottom: lastUnloaded
                //as soon as we find one, do a sequential search to find the last visibleone, and return that one as gap


    //if we got here, then theres no gap
    //return no gap


//iterate:
    //recycler loop (detects who went off and informs delegate and, does actual recycling and tells delegate)
    //drawing loop (draws available items from datasource or kicks off load protocol)
    //NOT THIS ONE ANY MORE: onscreen loop (detects who came on and informs delegate)
    //empty check (if theres nothing there, then show the empty view, otherwise hide it)


//didScrollButIsStillScrolling:
    //iterate without recycler

//didScrollToStop:
    //iterate

//startDataDance:
    //iterate

//moreItemsAvailable:
    //iterate

//reset:
    //take all loaded items
        //put them in the trash
        //send the delegate an infiniteListView:view:correspondingToItemWentOffScreen: message
    //recycler loop
    //scroll to top without animating
    //init data structures and zero state

//moreItemsAvailable:
    //check that it was expecting this message? YES
        //hide loading view if there was one
        //send delegate the infiniteListViewDidFinishLoadingMoreItems: message
        //start drawing loop
        //remember that you're no longer expecting to receive the moreItemsAvailable: message
    //check that it was expecting this message? NO
        //raise GBUnavailableMessageException and remind to only call this once and only in response to startLoadingMoreItemsInInfiniteListView: message

//recycler loop:
    //find and enumerate all items which have gone off screen
        //take them out of the loaded items list
        //update column boundaries by moving index
        //put them in the trash so they can be recycled
        //send the delegate an infiniteListView:view:correspondingToItemWentOffScreen: message
        //take them out of the trash
        //put them in the recycleable pool
        //send the delegate an infiniteListView:didRecycleView:lastUsedByItem: message

//empty handler:
    //is anything shown? YES
        //hide empty view...
    //is anything shown? NO
        //show empty view...

//draw+load loop: a loop that tries to fill the screen by asking for more data, or if there isnt any more available: starting the dataload protocol in hopes of getting called again when more is available
    //is dataDanceActive? YES
        //check if there is a gap (take into account loadingTriggerDistance)? new
            //ask if there is another item currently available? YES
                //ask for the item
                    //check that item is a UIView? YES
                        //check to make sure item width fits? YES
                            //draw the item (add the subview, and stretch the scrollview content size) and record it in the internal logic (things like the size)
                            //go back to checking if there is a gap, i.e. recurse
                        //check to make sure item width fits? NO
                            //raise width mismath exception
                    //check that item is a UIView? NO
                        //raise bad type exception

            //ask if there is another item currently available? NO
                //check to see if it has already requested mroe items? NO
                    //ask if it can load more items? YES
                        //remember that you're expecting to receive the moreItemsAvailable: message
                        //send datasource the startLoadingMoreItemsInInfiniteListView: message
                        //send delegate the infiniteListViewDidStartLoadingMoreItems: message
                        //ask if it should show a loading view? YES
                            //ask for the loading view? UIView*
                                //ask for loading view margin stuff...
                                //assign that UIView* as the loadingView
                            //ask for the loading view? nil
                                //assign a default simple spinner as the loadingView
                            //show loading view
                    //ask if it can load more items? NO
                        //send infiniteListViewNoMoreItemsAvailable: to delegate
                        //we're done
                //check to see if it has already requested more items? NO
                    //we're done
        //check if there is a gap? old
            //ask for the item
                //check that item is UIView? YES
                    //check to make sure item size matches the stored one? YES
                        //draw the item in his old position
                        //go back to checking if there is a gap, i.e. recurse
                    //check to make sure item size matches the stored one? NO
                        //raise inconsistency exception and quote the old required size, and the one the client tried to pass in
                //check that item is UIView? NO
                    //raise bad type exception
        //check if there is a gap? NO
            //we're done

        //handle empty list... (maybe not the best place for it)
    //is dataDanceActive? NO
        //do nothing