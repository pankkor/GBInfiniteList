//
//  GBInfiniteListView.m
//  GBInfiniteList
//
//  Created by Luka Mirosevic on 30/04/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//

#import "GBInfiniteListView.h"

//foo add a way to detect when views are tapped, need to handle the touches myself assuming they come through to my layer

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
    GBInfiniteListTypeOfGapTop,
    GBInfiniteListTypeOfGapBottom,
} GBInfiniteListTypeOfGap;

typedef struct {
    GBInfiniteListTypeOfGap     type;
    NSUInteger                  columnIdentifier;
    NSUInteger                  itemIdentifier;
    NSUInteger                  indexInColumnStack;
} GBInfiniteListGap;

typedef enum {
    GBLoadingViewTypeDefault,
    GBLoadingViewTypeCustom,
} GBLoadingViewType;


static CGFloat const kDefaultVerticalItemMargin =                                       0;
static CGFloat const kDefaultHorizontalColumnMargin =                                   0;
static CGFloat const kDefaultLoadTriggerDistance =                                      0;
static UIEdgeInsets const kDefaultOuterPadding =                                        (UIEdgeInsets){0,0,0,0};

static BOOL const kDefaultForShouldPositionLoadingViewInsideOuterPadding =              YES;
static BOOL const kDefaultForShouldPositionHeaderViewInsideOuterPadding =               YES;
static CGFloat const kDefaultLoadingViewTopMargin =                                     0;
static CGFloat const kDefaultHeaderViewBottomMargin =                                   0;
static UIEdgeInsets const kPaddingForDefaultSpinner =                                   (UIEdgeInsets){4, 0, 4, 0};

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

static NSUInteger const kNumberOfTicksAfterWhichToRecycle =                             4;


@interface GBInfiniteListView () {
    UIView                                                          *_defaultLoadingView;
    NSUInteger                                                      _tickCounter;
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

#pragma mark - Data dance

//-(void)reloadVisibleItems {
//    //go through all visible items by going through each of the columnStacks according to the indices and redraw the items
//}

-(void)reset {
//    l(@"_reset");
//    //recycle all loaded items
//    [self _recyclerLoopWithForcedRecyclingOfEverything:YES];//foo
    
    //scroll to top without animating
    [self scrollToTopAnimated:NO];
    
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
        [self _iterateWithRecyclerEnabled:NO];//foo was yes before
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

#pragma mark - Scrolling & Co.

-(void)scrollToTopAnimated:(BOOL)shouldAnimate {
//    l(@"scrolltotop");
    [self scrollToPosition:0 animated:shouldAnimate];
}

-(void)scrollToPosition:(CGFloat)yPosition animated:(BOOL)shouldAnimate {
//    l(@"scrolltoposition");
    [self.scrollView setContentOffset:CGPointMake(0, yPosition) animated:shouldAnimate];
    
//    //recycle
//    [self _recyclerLoopWithForcedRecyclingOfEverything:NO];//foo
    
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

#pragma mark - UIScrollViewDelegate

-(void)scrollViewDidScroll:(UIScrollView *)scrollView {
//    l(@"scrollview did scroll");
    if (_tickCounter % kNumberOfTicksAfterWhichToRecycle == 0) {
        [self _iterateWithRecyclerEnabled:YES];
        _tickCounter = 0;
    }
    else {
        [self _iterateWithRecyclerEnabled:NO];
    }
    
    [self _notifyDelegateAboutScrolling];
}

-(void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
//    l(@"scrollview did end deceleratin");
    [self _iterateWithRecyclerEnabled:YES];
    
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
//    self.viewsDeferredForRecycling = [NSMutableDictionary new];//foo
    self.loadedViews = [NSMutableDictionary new];
    self.hasRequestedMoreItems = NO;
//    self.scrollView.backgroundColor = [UIColor redColor];//foo test
    
    //add the actual scrollview to the screen
    [self addSubview:self.scrollView];
    
    //ticks to 0
    _tickCounter = 0;
    
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
    _lRect(self.scrollView.frame);
}

-(void)_initialiseColumnCountDependentDataStructures {
//    l(@"_initialiseColumnCountDependentDataStructures");
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
        self.columnStacksLoadedItemBoundaryIndices = NULL;
    }
    self.recycledViewsPool = nil;
//    self.viewsDeferredForRecycling = nil;//foo
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
    [self _iterateWithRecyclerEnabled:NO];
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
        GBLoadingViewType loadingViewType;
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
            
            loadingViewType = GBLoadingViewTypeCustom;
        }
        //check loadingview type? nil
        else if (loadingView == nil) {
            //use default loading view
            loadingViewType =GBLoadingViewTypeDefault;
            
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

-(void)_drawLoadingView:(UIView *)loadingView withType:(GBLoadingViewType)type paddingPreference:(BOOL)isLoadingViewInsideOuterPadding margin:(CGFloat)loadingViewBottomMargin {
//    l(@"_drawLoadingView... the one that does the drawing");
    //remove and release any potential previous loading views
    if (self.loadingView) {
        [self.loadingView removeFromSuperview];
        self.loadingView = nil;
    }
    
    //set the view
    if (type == GBLoadingViewTypeDefault) {
        self.loadingView = self.defaultLoadingView;
    }
    else if (type == GBLoadingViewTypeCustom) {
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

-(void)_iterateWithRecyclerEnabled:(BOOL)shouldRecycle {
//    l(@"\n\n");
//    l(@"_iterateWithRecyclerEnabled: %@", _b(shouldRecycle));
    if (self.isDataDanceActive) {
//        if (shouldRecycle) [self _recyclerLoopWithForcedRecyclingOfEverything:NO];//foo
        [self _drawAndLoadLoop];
        [self _handleNoItemsView];
    }
//    l(@"\n\n");
}

-(void)_recyclerLoopWithForcedRecyclingOfEverything:(BOOL)forceRecycleAll {
//    l(@"_recyclerLoopWithForcedRecyclingOfEverything: %@", _b(forceRecycleAll));
    
    //loop over every column
    CGFloat loadedZoneTop = self.scrollView.contentOffset.y;
    CGFloat loadedZoneHeight = self.scrollView.bounds.size.height + self.loadTriggerDistance;
    GBFastArray *columnStack;
    for (int columnIndex=0; columnIndex<self.numberOfColumns; columnIndex++) {
        //if there's nothing in this column, skip to next one
        if (IsGBInfiniteListColumnBoundariesUndefined(self.columnStacksLoadedItemBoundaryIndices[columnIndex])) {
            continue;
        }
        
        //remember the column stack for this column iteration
        columnStack = self.columnStacks[columnIndex];
        
        //we're gonna need an index
        NSInteger index;
        
        //forced
        if (forceRecycleAll) {//foo untested. call reset and make sure it works
            index = self.columnStacksLoadedItemBoundaryIndices[columnIndex].firstLoadedIndex;
            while (index <= self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex) {
                //get the item
                GBInfiniteListItemMeta nextItemUp = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:index];
                
                //recycle it
                [self _recycleItemWithMeta:nextItemUp indexInColumn:index column:columnIndex inColumnBoundaryWithAddress:self.columnStacksLoadedItemBoundaryIndices[columnIndex] moveLastLoadedPointer:YES];//foo test
                
                index++;
            }
        }
        //if not forced
        else {
            //try bottom up search for invisibles
            index = self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex;
            while (index > self.columnStacksLoadedItemBoundaryIndices[columnIndex].firstLoadedIndex) {
                if ([self _recycleIfInvisibleItemWithIndex:index inColumnStack:columnStack columnIndex:columnIndex loadedZoneTop:loadedZoneTop loadedZoneHeight:loadedZoneHeight moveLastLoadedPointer:YES]) {
                    //he got recycled, see if there is any more
//                    l(@"recycled bottom: %d", index);
                    index--;
                }
                else {
                    //if it returns false it means he didn't get recycled so we must have found a visibl item and be done
                    break;
                }
            }
            
//            l(@"column %d indices after bottom up search is: %d-%d", columnIndex, self.columnStacksLoadedItemBoundaryIndices[columnIndex].firstLoadedIndex, self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex);
            
            //try top down search for invisibles, but only if the last loaded index is greater than the first
            index = self.columnStacksLoadedItemBoundaryIndices[columnIndex].firstLoadedIndex;
            while (index <= self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex) {
                if ([self _recycleIfInvisibleItemWithIndex:index inColumnStack:columnStack columnIndex:columnIndex loadedZoneTop:loadedZoneTop loadedZoneHeight:loadedZoneHeight moveLastLoadedPointer:NO]) {
                    //he got recycled, see if there is any more
//                    l(@"recycled top: %d", index);
                    index++;
                }
                else {
                    //if it returns false it means he didn't get recycled so we must have found a visibl item and be done
                    break;
                }
            }
            
//            l(@"column %d indices after top down search is: %d-%d", columnIndex, self.columnStacksLoadedItemBoundaryIndices[columnIndex].firstLoadedIndex, self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex);
//            l(@"\n\n");
        }
    }
}

-(BOOL)_recycleIfInvisibleItemWithIndex:(NSUInteger)index inColumnStack:(GBFastArray *)columnStack columnIndex:(NSUInteger)columnIndex loadedZoneTop:(CGFloat)loadedZoneTop loadedZoneHeight:(CGFloat)loadedZoneHeight moveLastLoadedPointer:(BOOL)moveLastLoadedPointer {
    GBInfiniteListItemMeta nextItemUp = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:index];
    
    //check if item is visible? NO
    if (!Lines1DOverlap(loadedZoneTop, loadedZoneHeight + self.verticalItemMargin, nextItemUp.geometry.origin, nextItemUp.geometry.height)) {//need to add the verticalItemMargin because items are loaded as soon edge of the prebious item is exceeded, so they can be placed offscreen if the scroll distance is less than the margin
        //recycle the item
        [self _recycleItemWithMeta:nextItemUp indexInColumn:index column:columnIndex inColumnBoundaryWithAddress:self.columnStacksLoadedItemBoundaryIndices[columnIndex] moveLastLoadedPointer:moveLastLoadedPointer];
        
        //report back that he got recycled
        return YES;
    }
    //otherwise...
    else {
        //...report that he didn't get recycled
        return NO;
    }
}

//draw+load loop: a loop that tries to fill the screen by asking for more data, or if there isnt any more available: starting the dataload protocol in hopes of getting called again when more is available
-(void)_drawAndLoadLoop {
//    l(@"_drawAndLoadLoop");
    //check if there is a gap (take into account loadingTriggerDistance)?
    GBInfiniteListGap nextGap = [self _findNextGap];
    
    //check if there is a gap? BOTTOM
    if (nextGap.type == GBInfiniteListTypeOfGapBottom) {
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
                    [self _drawAndLoadLoop];
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
                    //remember that you're expecting to receive the moreItemsAvailable: message
                    self.hasRequestedMoreItems = YES;
                    
                    //draw loading view
                    [self _drawLoadingView];
                    
                    //send datasource the startLoadingMoreItemsInInfiniteListView: message
                    [self.dataSource startLoadingMoreItemsInInfiniteListView:self];
                    
                    //send delegate the infiniteListViewDidStartLoadingMoreItems: message
                    if ([self.delegate respondsToSelector:@selector(infiniteListViewDidStartLoadingMoreItems:)]) {
                        [self.delegate infiniteListViewDidStartLoadingMoreItems:self];
                    }
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
    //check if there is a gap? TOP
    else if (nextGap.type == GBInfiniteListTypeOfGapTop) {
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
                [self _drawAndLoadLoop];
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

-(void)_recycleItemWithMeta:(GBInfiniteListItemMeta)itemMeta indexInColumn:(NSUInteger)index column:(NSUInteger)columnIndex inColumnBoundaryWithAddress:(GBInfiniteListColumnBoundaries)columnBoundaries moveLastLoadedPointer:(BOOL)moveLastLoadedPointer {
    //find the old view
    NSNumber *key = @(itemMeta.itemIdentifier);
    UIView *oldView = self.loadedViews[key];
    
    //only if we're told to move the pointer (as a result of scrolling back up)
    if (moveLastLoadedPointer) {
        //decrement the last loaded index... this might cause a temporarily inconsistent state because the items are not removed in the order they were added globally, but sorted by column. but it works out in the end.
        self.lastLoadedItemIdentifier -= 1;//foo
    }
    
    //if the view was the only view in the column
    if (columnBoundaries.firstLoadedIndex == 0 && columnBoundaries.lastLoadedIndex == 0) {
        //change the indices to indicate the column is now empty
        self.columnStacksLoadedItemBoundaryIndices[columnIndex] = GBInfiniteListColumnBoundariesUndefined;
    }
    //if the view disappeared off the front? YES
    else if (columnBoundaries.firstLoadedIndex == index) {
        //update column boundaries by moving front index up 1
        self.columnStacksLoadedItemBoundaryIndices[columnIndex].firstLoadedIndex += 1;
    }
    //must be off the end in this case
    else if (columnBoundaries.lastLoadedIndex == index) {
        //update column boundaries by moving last index down by 1
        self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex -= 1;
    }
    else {
        l(@"----------------warning, i shudnt be here");//foo when you jump up and down it crashes
        //        NSAssert(false, @"Time to rethink your logic...");//foo donno why this happens
    }
    
    //check to make sure the view is actually loaded before we try to re-unload it and confuse our delegate
    if ([self.loadedViews objectForKey:key]) {
        //put them in the recycleable pool, the oldView pointer above has a strong ref so don't worry, we won't loose him
        if ([oldView.reuseIdentifier isKindOfClass:[NSString class]]) {
            //make sure we have a pool for that reuseIdentifier
            if (!self.recycledViewsPool[oldView.reuseIdentifier]) {
                self.recycledViewsPool[oldView.reuseIdentifier] = [[NSMutableArray alloc] init];
            }
            
            //add it to the pool
            self.recycledViewsPool[oldView.reuseIdentifier] = oldView;
        }
        
        //take them offscreen
        [oldView removeFromSuperview];
        
        //take them out of the loaded items list
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
    
    
    l(@"recycled: %d. loadedStack: %d-%d. lastloaded: %d", itemMeta.itemIdentifier, self.columnStacksLoadedItemBoundaryIndices[columnIndex].firstLoadedIndex, self.columnStacksLoadedItemBoundaryIndices[columnIndex].lastLoadedIndex, self.lastLoadedItemIdentifier);//foo
}

-(void)_drawOldItemWithMeta:(GBInfiniteListItemMeta)itemMeta view:(UIView *)itemView indexInColumnStack:(NSUInteger)indexInColumnStack inColumn:(NSUInteger)columnIndex {
//    l(@"_drawOldItemWithMeta");
    //update column boundary
    self.columnStacksLoadedItemBoundaryIndices[columnIndex].firstLoadedIndex = indexInColumnStack;//foo

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
    if (columnBoundaries.lastLoadedIndex == GBColumnIndexUndefined) {
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
    if (columnBoundaries.lastLoadedIndex == GBColumnIndexUndefined) {
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

-(GBInfiniteListGap)_findNextGap {
//    l(@"_findNextGap");
    CGFloat loadedZoneTop = self.scrollView.contentOffset.y;
    CGFloat loadedZoneHeight = self.scrollView.bounds.size.height + self.loadTriggerDistance;
    
    
    /* Search for gap at top */
    
    GBFastArray *columnStack;
    GBInfiniteListColumnBoundaries columnBoundaries;
    //try each column one by one
    for (int columnIndex=0; columnIndex<self.numberOfColumns; columnIndex++) {
        columnStack = self.columnStacks[columnIndex];
        columnBoundaries = self.columnStacksLoadedItemBoundaryIndices[columnIndex];
        
        //prepare for checking the gap
        GBInfiniteListItemMeta nextItemUp;
        NSInteger index = columnBoundaries.firstLoadedIndex;
        
        //check if column is empty
        if (index == GBColumnIndexUndefined) {
            //column is empty so there can't be any gap above it
            continue;
        }
        //check to see if its the first item, if so there can't be any gap above it
        else if (index == 0) {
            //don't need to search up this column any more
            continue;
        }
        //check to see if the first item covers the top edge of the screen, and only if he doesnt should we start our search. If he does, we don't need to look further
        else if ((*(GBInfiniteListItemMeta *)[columnStack itemAtIndex:index]).geometry.origin <= loadedZoneTop) {
            //don't need to search up this column any more
            continue;
        }
        else {
            //move past the first current element and see if the next one is our target, in most cases it will be, but if the user scrolled really fast and skipped some, then we might have to continue looking, that's why there's a loop
            index--;
            
            //go up until you find the first item that's visible
            while (index >= 0) {
                nextItemUp = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:index];
                
                //check if item is visible
                if (Lines1DOverlap(loadedZoneTop, loadedZoneHeight, nextItemUp.geometry.origin, nextItemUp.geometry.height)) {//foo was negated
                    GBInfiniteListGap newTopGap;
                    
                    newTopGap.type = GBInfiniteListTypeOfGapTop;
                    newTopGap.columnIdentifier = columnIndex;
                    newTopGap.itemIdentifier = nextItemUp.itemIdentifier;
                    newTopGap.indexInColumnStack = index;
                    
                    return newTopGap;
                }
                
                //if we didnt find one and got here... try again
                index--;
            }
        }
    }
    
    
    /* Search for gap at bottom */
    
    
    //find shortest column -> check if it's onscreen -> if not return a newGap with itemID as last+1
    //this code is different because we can't skip items, and we must pick the shortest one first
    
    //calculate the shortest column and that column's length
    NSUInteger runningShortestColumnIndex = 0;
    CGFloat runningShortestColumnLength = CGFLOAT_MAX;
    CGFloat currentColumnLength;
//    GBInfiniteListItemMeta runningShortestItem;
    
    GBInfiniteListItemMeta lastItemInColumn;
    for (int columnIndex=0; columnIndex<self.numberOfColumns; columnIndex++) {
        columnStack = self.columnStacks[columnIndex];
        columnBoundaries = self.columnStacksLoadedItemBoundaryIndices[columnIndex];
        
        //if the index is undefined, then this is a column that is as short as it gets. and since we search left to right, if it has multiple empty columns, it will return the leftmost one first. if this is the case, skip all the rest because it cant get shorter.
        if (columnBoundaries.lastLoadedIndex == GBColumnIndexUndefined) {
            runningShortestColumnIndex = columnIndex;
            runningShortestColumnLength = 0;

            //don't search any more
            break;
        }
        //otherwise continue looking for the shortest one
        else {
            //we need to calculate the length of the column first
            lastItemInColumn = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:columnBoundaries.lastLoadedIndex];
            currentColumnLength = lastItemInColumn.geometry.origin + lastItemInColumn.geometry.height;
            
            //then check if its shorter or not than what we currently think is the shortest
            if (currentColumnLength < runningShortestColumnLength) {
                runningShortestColumnIndex = columnIndex;
                runningShortestColumnLength = currentColumnLength;
            }
        }
    }
    
    //check if the item leaves a gap
    if (runningShortestColumnLength < loadedZoneTop + loadedZoneHeight) {
        //if it does, return this gap
        GBInfiniteListGap newBottomGap;
        
        newBottomGap.type = GBInfiniteListTypeOfGapBottom;
        newBottomGap.columnIdentifier = runningShortestColumnIndex;
        
        return newBottomGap;
    }
    
    
    /* No gap */
    
    //if we're here then theres no gap
    GBInfiniteListGap noGap;
    noGap.type = GBInfiniteListTypeOfGapNone;
    return noGap;
}

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

//onscreen loop: (might replace this by just sending the delegate message from the drawAndLoad loop)
    //find and enumerate all the items which have come on screen (can use a temporary place to store these instead of having to search for them)
        //send the delegate an infiniteListView:view:correspondingToItemCameOnScreen: message

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