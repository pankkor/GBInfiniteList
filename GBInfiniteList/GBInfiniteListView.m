//
//  GBInfiniteListView.m
//  GBInfiniteList
//
//  Created by Luka Mirosevic on 30/04/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//

#import "GBInfiniteListView.h"

//foo add a way to detect when views are tapped, need to handle the touches myself assuming they come through to my layer
//foo also need to set the cache pool size

#import "UIView+GBInfiniteList.h"
#import "GBToolbox.h"


NSString * const GBTypeMismatchException =                                              @"GBTypeMismatchException";
NSString * const GBWidthMismatchException =                                             @"GBWidthMismatchException";
NSString * const GBSizeMismatchException =                                              @"GBSizeMismatchException";
NSString * const GBUnexpectedMessageException =                                         @"GBUnexpectedMessageException";


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

static CGFloat const kDefaultVerticalItemMargin =                                       0;
static CGFloat const kDefaultHorizontalColumnMargin =                                   0;
static CGFloat const kDefaultLoadTriggerDistance =                                      0;
static UIEdgeInsets const kDefaultOuterPadding =                                        (UIEdgeInsets){0,0,0,0};

static BOOL const kDefaultForShouldPositionLoadingViewInsideOuterPadding =              YES;
static BOOL const kDefaultForShouldPositionHeaderViewInsideOuterPadding =               YES;
static CGFloat const kDefaultLoadingViewTopMargin =                                     0;
static CGFloat const kDefaultHeaderViewBottomMargin =                                   0;
static UIEdgeInsets const kPaddingForDefaultSpinner =                                   (UIEdgeInsets){4, 0, 4, 0};

static NSUInteger const kDefaultRecyclableViewsPoolSize =                               10;

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


@interface GBInfiniteListView () {
    UIView                                                          *_defaultLoadingView;
}

//Strong pointers to little subviews (so that the creator can safely drop their pointers and it won't get dealloced)
@property (strong, nonatomic) UIView                                *headerView;
@property (strong, nonatomic) UIView                                *noItemsView;
@property (strong, nonatomic) UIView                                *loadingView;

//Default loading view
@property (strong, nonatomic, readonly) UIView                      *defaultLoadingView;

//Scrollview where to put all the stuff on
@property (strong, nonatomic) UIScrollView                          *scrollView;

//To know when to kick off the data dance. Data dance is kicked off as soon as view is visible, init has been called, and datasource has been set. if any of these changes, the data dance stops
@property (assign, nonatomic) BOOL                                  isInitialised;
@property (assign, nonatomic) BOOL                                  isVisible;
@property (assign, nonatomic) BOOL                                  isDataSourceSet;

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

@end


@implementation GBInfiniteListView

#pragma mark - Custom accessors: side effects

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
                [pool removeObjectsInRange:NSMakeRange(maxReusableViewsPoolSize, (pool.count - 1) - maxReusableViewsPoolSize)];//foo test that this does what it should
            }
        }
    }
    
    _maxReusableViewsPoolSize = maxReusableViewsPoolSize;
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

//-(void)reloadVisibleItems {
//    //go through all visible items by going through each of the columnStacks according to the indices and redraw the items
//}

-(void)reset {
//    l(@"_reset");
    
    //scroll to top without animating
    [self scrollToTopAnimated:NO];
    
    //recycle all loaded items. just so the old delegate gets his messages
    [self _recyclerLoopWithHint:GBInfiniteListDirectionMovedHintNone forcedRecyclingOfEverything:YES];//foo do we need/want this?
    
    //restart data dance
    [self _stopDataDance];
    [self _startDataDance];
}

-(void)didFinishLoadingMoreItems {
    //check that it was expecting this message? YES
    if (self.hasRequestedMoreItems) {
        //remember that you're no longer expecting to receive the moreItemsAvailable: message
        self.hasRequestedMoreItems = NO;
        
        //hide loading view if there was one
        [self.loadingView removeFromSuperview];
        self.loadingView = nil;
        
        //send delegate the infiniteListViewDidFinishLoadingMoreItems: message
        if ([self.delegate respondsToSelector:@selector(infiniteListViewDidFinishLoadingMoreItems:)]) {
            [self.delegate infiniteListViewDidFinishLoadingMoreItems:self];
        }
        
        //restart our loop
        [self _iterateWithHint:GBInfiniteListDirectionMovedHintDown recyclerEnabled:NO];//foo was yes before
    }
    //check that it was expecting this message? NO
    else {
        //raise GBUnexpectedMessageException and remind to only call this once and only in response to startLoadingMoreItemsInInfiniteListView: message
        @throw [NSException exceptionWithName:GBUnexpectedMessageException reason:@"The infiniteListView was not expecting more data. Only send this message after the list asks you for more data, and only once!" userInfo:nil];
    }
}

-(UIView *)dequeueReusableViewWithIdentifier:(NSString *)viewIdentifier {
    NSMutableArray *pool;
    //check if we have a pool for that? YES
    if ((pool = self.recycledViewsPool[viewIdentifier])) {
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

#pragma mark - Public API: Scrolling & Co.

-(void)scrollToTopAnimated:(BOOL)shouldAnimate {
//    l(@"scrolltotop");
    [self scrollToPosition:0 animated:shouldAnimate];
}

-(void)scrollToPosition:(CGFloat)yPosition animated:(BOOL)shouldAnimate {
    [self.scrollView setContentOffset:CGPointMake(0, yPosition) animated:shouldAnimate];
    
    [self _notifyDelegateAboutScrolling];    //foo dont call this if the UIScrolLView delegate gets sent a messag when this is done... dont wanna double call
}

-(BOOL)isItemOnScreen:(NSUInteger)itemIdentifier {
    NSNumber *itemNumber = @(itemIdentifier);
    for (NSNumber *key in self.itemsCurrentlyOnScreen) {
        //found one!
        if ([key isEqualToNumber:itemNumber]) {
            return YES;
        }
    }
    
    //if we got here it means he's not there
    return NO;
}

-(NSDictionary *)itemsCurrentlyOnScreen {
    return [self.loadedViews copy];
}

#pragma mark - Caching

-(void)flushReusableViewPool {
    //simply replaces the pool with a new one, which causes the old one to trickle down releases and release everything held in it
    self.recycledViewsPool = [NSMutableDictionary new];
}

#pragma mark - UIScrollViewDelegate

-(void)scrollViewDidScroll:(UIScrollView *)scrollView {
//    l(@"scrollview did scroll");
    [self _didMoveViewport];
}

-(void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
//    l(@"scrollview did end deceleratin");
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
    
    //remember the current position
    self.lastScrollViewPosition = self.scrollView.contentOffset.y;
    
    //tell delegate
    [self _notifyDelegateAboutScrolling];
}

-(void)_notifyDelegateAboutScrolling {
//    l(@"notify delegate about scrolling");
    //tell delegate about scrolling
    if ([self.delegate respondsToSelector:@selector(infiniteListView:didScrollToPosition:)]) {
        [self.delegate infiniteListView:self didScrollToPosition:self.scrollView.contentOffset.y];
    }
}

#pragma mark - Private API: Memory

-(void)_initialisationRoutine {
//    l(@"initroutine");
    self.backgroundColor = [UIColor grayColor];//foo test
    
    //Create the necessary data structures etc.
    [self _initialiseDataStructures];
    
    //Set state
    self.isInitialised = YES;
}

-(void)_initialiseDataStructures {
//    l(@"_initialiseDataStructures");
    //init data structures n co.
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.scrollView.opaque = NO;
    self.scrollView.backgroundColor = [UIColor clearColor];
    self.scrollView.delegate = self;
    self.scrollView.scrollEnabled = YES;
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
//    l(@"_finaliseScrollViewSize to size:");
    self.scrollView.frame = self.bounds;
}

-(void)_initialiseColumnCountDependentDataStructures {
//    l(@"_initialiseColumnCountDependentDataStructures");
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
//    l(@"_cleanup");
    //my data structures
    self.columnStacks = nil;
    if (self.columnStacksLoadedItemBoundaryIndices != NULL) {
        free(self.columnStacksLoadedItemBoundaryIndices);
        self.columnStacksLoadedItemBoundaryIndices = NULL;//foo do we need this? or is it automatically nulled after the free
    }
    if (self.lastRecycledItemsIdentifiers != NULL) {
        free(self.lastRecycledItemsIdentifiers);
        self.lastRecycledItemsIdentifiers = NULL;//foo do we need this? or is it automatically nulled after the free
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

#pragma mark - Private API: Data dance state management

-(void)_manageDataDanceState {
//    l(@"_manageDataDanceState");
    BOOL allRequiredToStart = (self.isVisible && self.isDataSourceSet && self.isInitialised);
    BOOL anyRequireToStop = (!self.isDataSourceSet || !self.isInitialised);
    
    //if we have conditions to start & we're not started yet
    if (allRequiredToStart && !self.isDataDanceActive) {
        [self _startDataDance];
    }
    
    //if we have conditions to stop & we're started atm
    if (anyRequireToStop && self.isDataDanceActive) {
        [self _stopDataDance];
    }
}

-(void)_startDataDance {
//    l(@"_startDataDance");
    //just remember it
    self.isDataDanceActive = YES;

    //set the size of the scrollView to match the infiniteListView frame
    [self _finaliseScrollViewSize];

    //get all the geometry stuff
    [self _requestAndPrepareGeometryStuff];
    
    //initialise column stacks n co.
    [self _initialiseColumnCountDependentDataStructures];

    //draw header view if necessary, this also configures the actualListOrigin.
    [self _handleHeaderViewAndConfigureListOrigin];
    
    //kick it all off
    [self _iterateWithHint:GBInfiniteListDirectionMovedHintNone recyclerEnabled:YES];//foo might be able to change this to down, but this is safer for now. //foo can change to NO but wanna make sure i test all cases during dev
}

-(void)_stopDataDance {
//    l(@"_stopDataDance");
    //remember state
    self.isDataDanceActive = NO;

    //clean up as if nothing ever happened (except for maybe the lazy loading spinner)
    [self _cleanup];
}

#pragma mark - Private API: Little views (header, no items, loading)

-(void)_handleHeaderViewAndConfigureListOrigin {
//    l(@"_handleHeaderViewAndConfigureListOrigin");
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
//    l(@"_handleNoItemsView");
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
            //calculate new size to match the width, but keep the height
            CGRect newFrame = CGRectMake(self.outerPadding.left, self.actualListOrigin, self.scrollView.bounds.size.width, noItemsView.frame.size.height);
            
            //apply the new size
            noItemsView.frame = newFrame;
            
            //draw the view
            [self.scrollView addSubview:noItemsView];
            
            //keep a pointer to the empty view
            self.noItemsView = noItemsView;
            
            //stretch the content size, but only if it makes it bigger, never smaller
            CGFloat newContentSizeHeight = noItemsView.frame.origin.y + noItemsView.frame.size.height + self.outerPadding.bottom;
            if (newContentSizeHeight > self.scrollView.contentSize.height) {
                self.scrollView.contentSize = CGSizeMake(self.scrollView.contentSize.width, newContentSizeHeight);
            }
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
//    l(@"_drawLoadingView");
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
//    l(@"_drawLoadingView... the one that does the drawing");
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
    CGFloat runningLongestColumnLength = 0;
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
    if (newContentSizeHeight > self.scrollView.contentSize.height) {
        self.scrollView.contentSize = CGSizeMake(self.scrollView.contentSize.width, newContentSizeHeight);
    }
}

#pragma mark - Private API: Geometry stuff

-(void)_requestAndPrepareGeometryStuff {
//    l(@"_requestAndPrepareGeometryStuff");
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
//    l(@"\n\n");
//    l(@"_iterateWithRecyclerEnabled: %@", _b(shouldRecycle));
    if (self.isDataDanceActive) {
        if (shouldRecycle) [self _recyclerLoopWithHint:directionMovedHint forcedRecyclingOfEverything:NO];
        [self _drawAndLoadLoopWithHint:directionMovedHint];
        [self _handleNoItemsView];
    }
//    l(@"\n\n");
}

-(void)_recyclerLoopWithHint:(GBInfiniteListDirectionMovedHint)directionMovedHint forcedRecyclingOfEverything:(BOOL)forceRecycleAll {
    //prepare
    CGFloat loadedZoneTop = self.scrollView.contentOffset.y;
    CGFloat loadedZoneHeight = self.scrollView.bounds.size.height + self.loadTriggerDistance;
    GBFastArray *columnStack;
    NSUInteger firstLoadedIndex;
    NSUInteger lastLoadedIndex;
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
    if (Lines1DOverlap(loadedZoneTop, loadedZoneHeight + self.verticalItemMargin, nextItemUp.geometry.origin, nextItemUp.geometry.height)) {//need to add the verticalItemMargin because items are loaded as soon edge of the prebious item is exceeded, so they can be placed offscreen if the scroll distance is less than the margin
        //done with this column, exit this loop
        if (loopNumber == 1) { goto exit1; } else  { goto exit2; }
    }
    //if invisible
    else {
        //recycle
        [self _recycleItemWithMeta:nextItemUp indexInColumn:index inColumnWithIndex:columnIndex inColumnBoundaryWithAddress:self.columnStacksLoadedItemBoundaryIndices[columnIndex]];
    }
    
    //go back into loop
    if (loopNumber == 1) { goto loop1; } else  { goto loop2; }


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
                self.recycledViewsPool[oldView.reuseIdentifier] = [[NSMutableArray alloc] init];
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
//    l(@"_drawAndLoadLoop");
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
            //check to see if it has already requested mroe items? NO
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
//    l(@"_drawOldItemWithMeta");
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
//    l(@"_drawAndStoreNewItem");
//    l(@".");
    //create meta struct which gets filled in along the way
    GBInfiniteListItemMeta newItemMeta;
    newItemMeta.itemIdentifier = newItemIdentifier;

    //find out where to draw the item
    GBFastArray *columnStack = self.columnStacks[columnIndex];
    GBInfiniteListColumnBoundaries columnBoundaries = self.columnStacksLoadedItemBoundaryIndices[columnIndex];
    GBInfiniteListItemGeometry itemGeometry;
    itemGeometry.height = itemView.frame.size.height;
    
    //if its the first item, stick it to the top, where the top is origin+outerPadding.top+header+headerMargin
    if (columnBoundaries.lastLoadedIndex == GBColumnIndexUndefined) {//foo change this to something a little more elegant, i.e. self.columnStacks[columnStack].isEmpty?
        itemGeometry.origin = self.actualListOrigin;
    }
    //otherwise it's lastitem.origin + lastitem.height + verticalItemMargin
    else {
        GBInfiniteListItemMeta lastItem = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:columnBoundaries.lastLoadedIndex];
        itemGeometry.origin = lastItem.geometry.origin + lastItem.geometry.height + self.verticalItemMargin;
    }
    
    //fill in the geometry
    newItemMeta.geometry = itemGeometry;
    
    //if its the first item, set the indices to both be 0
    if (columnBoundaries.lastLoadedIndex == GBColumnIndexUndefined) {//foo change this to something a little more elegant, i.e. self.columnStacks[columnStack].isEmpty?
        self.columnStacksLoadedItemBoundaryIndices[columnIndex] = (GBInfiniteListColumnBoundaries){0,0};
    }
    //else expand the last column boundary by 1
    else {
        self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex += 1;
    }
    
    //and add the meta struct to the columnStack at the correct index
    [columnStack insertItem:&newItemMeta atIndex:self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex];
    
    //find the left origin of the column
    CGFloat columnOrigin = self.outerPadding.left + columnIndex * (self.requiredViewWidth + self.horizontalColumnMargin);
    
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
    if (newContentSizeHeight > self.scrollView.contentSize.height) {
        self.scrollView.contentSize = CGSizeMake(self.scrollView.contentSize.width, newContentSizeHeight);
    }
    
    //send the delegate an infiniteListView:view:correspondingToItemDidComeOnScreen: message
    if ([self.delegate respondsToSelector:@selector(infiniteListView:view:correspondingToItemDidComeOnScreen:)]) {
        [self.delegate infiniteListView:self view:itemView correspondingToItemDidComeOnScreen:newItemMeta.itemIdentifier];
    }
}

-(GBInfiniteListGap)_findNextGapWithHint:(GBInfiniteListDirectionMovedHint)directionMovedHint {
//    l(@"_findNextGap");
    
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
            firstLoadedIndex = self.columnStacksLoadedItemBoundaryIndices[columnIndex].firstLoadedIndex;
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
                for (index = lastLoadedIndex; YES; index++) {//foo maybe not a good idea to have an unbounded loop
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
                            //foo im not all too sure about this business here
                            
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
                    GBInfiniteListItemMeta *nativeCandidateItem = (GBInfiniteListItemMeta *)candidateItem;
                    
                    //if visible: bingo
                    if (Lines1DOverlap(loadedZoneTop, loadedZoneHeight, nativeCandidateItem->geometry.origin, nativeCandidateItem->geometry.height)) {
                        return GBSearchResultMatch;
                    }
                    //if the item is somewhere before, then we've gone too far
                    else if (nativeCandidateItem->geometry.origin > loadedZoneTop) {
                        return GBSearchResultLow;
                    }
                    //only other option is that the item is after
                    else {
                        return GBSearchResultHigh;
                    }
                }];

                //foo if it doesnt find one then we need to swap the answer//foo delete all this its just a quick test
                if (index == kGBSearchResultNotFound) {
                    l(@"not found!");
                }
                else {
                    l(@"found");//if we got here, then swap the search hints and make sure we dont find him any more
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
            lastLoadedIndex = self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex;
            
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
                for (index = firstLoadedIndex; index>=0; index--) {//foo maybe can have an unbounded loop here and save some time on the checks
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
                //do binary search for a visible item, top:0, bottom: lastUnloaded
                //as soon as we find one, do a sequential search downwards to find the last visibleone, and return that one as gap                
            }
        }
    }
    
    //if we got here, then theres no gap
    GBInfiniteListGap noGap;
    noGap.type = GBInfiniteListTypeOfGapNone;
    return noGap;
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    
    
    
//    /* Search for gap at top */
//    
//    GBFastArray *columnStack;
//    GBInfiniteListColumnBoundaries columnBoundaries;
//    //try each column one by one
//    for (int columnIndex=0; columnIndex<self.numberOfColumns; columnIndex++) {
//        columnStack = self.columnStacks[columnIndex];
//        columnBoundaries = self.columnStacksLoadedItemBoundaryIndices[columnIndex];
//        
//        //prepare for checking the gap
//        GBInfiniteListItemMeta nextItemUp;
//        NSInteger index = columnBoundaries.firstLoadedIndex;
//        
//        //check if column is empty
//        if (index == GBColumnIndexUndefined) {
//            //column is empty so there can't be any gap above it
//            continue;
//        }
//        //check to see if its the first item, if so there can't be any gap above it
//        else if (index == 0) {
//            //don't need to search up this column any more
//            continue;
//        }
//        //check to see if the first item covers the top edge of the screen, and only if he doesnt should we start our search. If he does, we don't need to look further
//        else if ((*(GBInfiniteListItemMeta *)[columnStack itemAtIndex:index]).geometry.origin <= loadedZoneTop) {
//            //don't need to search up this column any more
//            continue;
//        }
//        else {
//            //move past the first current element and see if the next one is our target, in most cases it will be, but if the user scrolled really fast and skipped some, then we might have to continue looking, that's why there's a loop
//            index--;
//            
//            //go up until you find the first item that's visible
//            while (index >= 0) {
//                nextItemUp = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:index];
//                
//                //check if item is visible
//                if (Lines1DOverlap(loadedZoneTop, loadedZoneHeight, nextItemUp.geometry.origin, nextItemUp.geometry.height)) {//foo was negated
//                    GBInfiniteListGap newTopGap;
//                    
//                    newTopGap.type = GBInfiniteListTypeOfGapTop;
//                    newTopGap.columnIdentifier = columnIndex;
//                    newTopGap.itemIdentifier = nextItemUp.itemIdentifier;
//                    newTopGap.indexInColumnStack = index;
//                    
//                    return newTopGap;
//                }
//                
//                //if we didnt find one and got here... try again
//                index--;
//            }
//        }
//    }
//    
//    
//    /* Search for gap at bottom */
//    
//    
//    //find shortest column -> check if it's onscreen -> if not return a newGap with itemID as last+1
//    //this code is different because we can't skip items, and we must pick the shortest one first
//    
//    //calculate the shortest column and that column's length
//    NSUInteger runningShortestColumnIndex = 0;
//    CGFloat runningShortestColumnLength = CGFLOAT_MAX;
//    CGFloat currentColumnLength;
////    GBInfiniteListItemMeta runningShortestItem;
//    
//    GBInfiniteListItemMeta lastItemInColumn;
//    for (int columnIndex=0; columnIndex<self.numberOfColumns; columnIndex++) {
//        columnStack = self.columnStacks[columnIndex];
//        columnBoundaries = self.columnStacksLoadedItemBoundaryIndices[columnIndex];
//        
//        //if the index is undefined, then this is a column that is as short as it gets. and since we search left to right, if it has multiple empty columns, it will return the leftmost one first. if this is the case, skip all the rest because it cant get shorter.
//        if (columnBoundaries.lastLoadedIndex == GBColumnIndexUndefined) {
//            runningShortestColumnIndex = columnIndex;
//            runningShortestColumnLength = 0;
//
//            //don't search any more
//            break;
//        }
//        //otherwise continue looking for the shortest one
//        else {
//            //we need to calculate the length of the column first
//            lastItemInColumn = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:columnBoundaries.lastLoadedIndex];
//            currentColumnLength = lastItemInColumn.geometry.origin + lastItemInColumn.geometry.height;
//            
//            //then check if its shorter or not than what we currently think is the shortest
//            if (currentColumnLength < runningShortestColumnLength) {
//                runningShortestColumnIndex = columnIndex;
//                runningShortestColumnLength = currentColumnLength;
//            }
//        }
//    }
//    
//    //check if the item leaves a gap
//    if (runningShortestColumnLength < loadedZoneTop + loadedZoneHeight) {
//        //if it does, return this gap
//        GBInfiniteListGap newBottomGap;
//        
//        newBottomGap.type = GBInfiniteListTypeOfGapBottom;
//        newBottomGap.columnIdentifier = runningShortestColumnIndex;
//        
//        return newBottomGap;
//    }
//    
//    
//    /* No gap */
//    
//    //if we're here then theres no gap
//    GBInfiniteListGap noGap;
//    noGap.type = GBInfiniteListTypeOfGapNone;
//    return noGap;

@end


//kickoffs by: 1)_startDataDance and 2)scrolling of scrollView, 3)moreItemsAvailable message

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
        //check if there is a gap (take into account loadingTriggerDistance)? Bottom
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
        //check if there is a gap? TOP
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