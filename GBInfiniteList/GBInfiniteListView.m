//
//  GBInfiniteListView.m
//  GBInfiniteList
//
//  Created by Luka Mirosevic on 30/04/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//

#import "GBInfiniteListView.h"

#import "UIView+GBInfiniteList.h"
#import "GBToolbox.h"

NSString * const GBTypeMismatchException =                                      @"GBTypeMismatchException";
NSString * const GBWidthMismatchException =                                     @"GBWidthMismatchException";
NSString * const GBSizeMismatchException =                                      @"GBSizeMismatchException";

static CGFloat const kDefaultVerticalItemMargin =                               0;
static CGFloat const kDefaultHorizontalColumnMargin =                           0;
static CGFloat const kDefaultLoadTriggerDistance =                              0;
static UIEdgeInsets const kDefaultOuterPadding =                                (UIEdgeInsets){0,0,0,0};

static BOOL const kDefaultForShouldPositionLoadingViewInsideOuterPadding =      YES;
static BOOL const kDefaultForShouldPositionHeaderViewInsideOuterPadding =       YES;
static CGFloat const kDefaultLoadingViewTopMargin =                             0;
static CGFloat const kDefaultHeaderViewBottomMargin =                           0;
static UIEdgeInsets const kPaddingForDefaultSpinner =                           (UIEdgeInsets){4, 0, 4, 0};

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
} GBInfiniteListGap;

typedef enum {
    GBLoadingViewTypeDefault,
    GBLoadingViewTypeCustom,
} GBLoadingViewType;

GBInfiniteListColumnBoundaries const GBInfiniteListColumnBoundariesZero = {0, 0};

@interface GBInfiniteListView () {
    UIView                                                          *_defaultLoadingView;
}

//Strong pointers to little subviews (so that the creator can safely drop their pointers and it won't get dealloced)
@property (strong, nonatomic) UIView                                *headerView;
@property (strong, nonatomic) UIView                                *noItemsView;
@property (strong, nonatomic) UIView                                *loadingView;

//Default loading view
@property (strong, nonatomic, readonly) UIView                      *defaultLoadingView;

//Geometry of the little subviews//foo these might not be necessary, at least not all of them
//@property (assign, nonatomic) CGFloat                               headerViewHeight;//foo init n co
//@property (assign, nonatomic) BOOL                                  isHeaderViewInsideOuterPadding;//foo init and clean and add default
//@property (assign, nonatomic) CGFloat                               headerViewBottomMargin;//foo init n co
//@property (assign, nonatomic) CGFloat                               loadingViewHeight;//foo init n co
//@property (assign, nonatomic) BOOL                                  isLoadingViewInsideOuterPadding;//foo init n co
//@property (assign, nonatomic) CGFloat                               loadingViewBottomMargin;//foo init n co

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
@property (assign, nonatomic) CGFloat                               actualListOrigin;//foo init n co


//Container for items that are about to be recycled
@property (strong, nonatomic) NSMutableArray                        *trashedViews;

//Container for items that can be recycled
@property (strong, nonatomic) NSMutableArray                        *recyclableViews;

//NSArray of GBFastArray's of GBInfiniteListItemMeta's. Fast data structure used for efficiently finding out who is visible, whether there are any gaps, calculating who just came back on screen when the infiniteList scrolls back up, and checking whether the size matches. It's fast because it's sorted in the order in which it will be queried (reverse order), and it can skip stuff it doesn't need to query because we have indexes.
@property (strong, nonatomic) NSArray                               *columnStacks;

//C-array of GBInfiniteListColumnBoundaries's. Used as an index to help making searching through columnStacks faster.
@property (assign, nonatomic) GBInfiniteListColumnBoundaries        *loadedItemsIndexBoundaries;

//A way to get to the actual view which is loaded once you have the itemIdentifier. NSDictionary where key is itemIdentifier, and value is the actual view
@property (strong, nonatomic) NSMutableDictionary                   *loadedViews;

//For keeping track of which item is the last one loaded
@property (assign, nonatomic) NSUInteger                            lastLoadedItemIdentifier;

@end

@implementation GBInfiniteListView

#pragma mark - Custom accessors: side effects

-(void)setDataSource:(id<GBInfiniteListDataSource>)dataSource {
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
    self.dataSource = nil;
    self.delegate = nil;
    
    self.headerView = nil;
    self.noItemsView = nil;
    self.loadingView = nil;
    
    self.scrollView = nil;
    
    self.trashedViews = nil;
    self.recyclableViews = nil;
    self.columnStacks = nil;
    self.loadedViews = nil;
    if (self.loadedItemsIndexBoundaries != NULL) {
        free(self.loadedItemsIndexBoundaries);
        self.loadedItemsIndexBoundaries = NULL;
    }
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

-(void)reloadVisibleItems {
    
}

-(void)reset {
    
}

-(void)didFinishLoadingMoreItems {
    
}

#pragma mark - Scrolling & Co.

-(void)scrollToTopAnimated:(BOOL)shouldAnimate {
    
}

-(void)scrollToPosition:(CGFloat)yPosition animated:(BOOL)shouldAnimate {
    
}

-(BOOL)isItemOnScreen:(NSUInteger)itemIdentifier {
    
}

-(NSArray *)itemsCurrentlyOnScreen {
    
}

#pragma mark - Private API: Memory

-(void)_initialisationRoutine {
    //Create the necessary data structures etc.
    [self _initialiseDataStructuresAndZeroState];
    
    //Set state
    self.isInitialised = YES;
}

-(void)_initialiseDataStructuresAndZeroState {
    //init data structures
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.scrollView.opaque = NO;
    self.scrollView.backgroundColor = [UIColor clearColor];
    self.scrollView.delegate = self;
    
    self.trashedViews = [NSMutableArray new];
    self.recyclableViews = [NSMutableArray new];
    self.loadedViews = [NSMutableDictionary new];
    
    self.lastLoadedItemIdentifier = 0;
    
    //these get initialised when the data dance starts. because they depend on the column count
    if (self.loadedItemsIndexBoundaries != NULL) {
        free(self.loadedItemsIndexBoundaries);
        self.loadedItemsIndexBoundaries = NULL;
    }
    self.columnStacks = nil;
    
    //reset the geometry stuff
    self.numberOfColumns = 0;
    self.requiredViewWidth = 0;
    self.outerPadding = UIEdgeInsetsZero;
    self.verticalItemMargin = 0;
    self.horizontalColumnMargin = 0;
    self.loadTriggerDistance = 0;
    
    //TODO: add any other ones in here, like the list of items and their sizes, list of visible items, the pool, etc.
}

#pragma mark - Private API: Data dance state management

-(void)_initialiseColumnCountDependentDataStructures {
    NSMutableArray *newColumnStacks = [[NSMutableArray alloc] initWithCapacity:self.numberOfColumns];
    self.loadedItemsIndexBoundaries = malloc(sizeof(GBInfiniteListColumnBoundariesZero) * self.numberOfColumns);
    
    for (int i=0; i<self.numberOfColumns; i++) {
        newColumnStacks[i] = [[GBFastArray alloc] initWithTypeSize:sizeof(GBInfiniteListItemMeta) initialCapacity:100 resizingFactor:1.5];
        
        self.loadedItemsIndexBoundaries[i] = GBInfiniteListColumnBoundariesZero;
    }
    
    self.columnStacks = [newColumnStacks copy];
}

-(void)_manageDataDanceState {
    BOOL newState = (self.isVisible && self.isDataSourceSet && self.isInitialised);
    
    //if it changes
    if (newState != self.isDataDanceActive) {
        //start it
        if (newState) {
            [self _startDataDance];
        }
        //stop it
        else {
            [self _stopDataDance];
        }
    }
}

-(void)_startDataDance {
//    //just remember it
//    self.isDataDanceActive = YES;
//    
//    //set the size of the scrollView to match the infiniteListView frame
//    self.scrollView.frame = self.frame;
//
//    //get all the geometry stuff
//    [self _requestAndPrepareGeometryStuff];
//    
//    //initialise column stacks n co.
//    [self _initialiseColumnCountDependentDataStructures];
//    
//    //ask for header... this shud be encapsualted so i just get a view that's ready for display and the frame configured ...... old sentence: padding/margins configured (however i may be doing that, modifying frame, or subviewing)
//    
//    //kick it all off
//    [self _iterate];//foo i think
}

-(void)_pauseDataDance {
    //if the dataSource is removed, stop everything
    //if the isVisible is changed, just pause it
}

-(void)_resumeDataDance {
    
}

-(void)_stopDataDance {
//    self.isDataDanceActive = NO;
//    
//    [self _initialiseDataStructuresAndZeroState];
//    
//    //note: asking for new items, etc. have their own checks and they stop autonomously as soon as they realise that self.isDataDanceActive is turned off
}

#pragma mark - Private API: Geometry stuff

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
    self.requiredViewWidth = (self.scrollView.frame.size.width - (self.outerPadding.left + self.outerPadding.right) - ((self.numberOfColumns - 1) * self.horizontalColumnMargin)) / self.numberOfColumns;
}

#pragma mark - Private API: Data dance

-(void)_iterate {
    [self _offScreenLoop];
    [self _recyclerLoop];
    [self _drawAndLoadLoop];
    [self _onScreenLoop];
    [self _emptyCheck];
}

-(void)_offScreenLoop {
    
}

-(void)_recyclerLoop {
    
}
//draw+load loop: a loop that tries to fill the screen by asking for more data, or if there isnt any more available: starting the dataload protocol in hopes of getting called again when more is available
-(void)_drawAndLoadLoop {
    //is dataDanceActive? YES
    if (self.isDataDanceActive) {
        //check if there is a gap (take into account loadingTriggerDistance)?
        GBInfiniteListGap nextGap = [self _findNextGap];
        
        //check if there is a gap? BOTTOM
        if (nextGap.type == GBInfiniteListTypeOfGapBottom) {
            //ask if there is another item currently available? YES
            if ([self.dataSource isViewForItem:nextGap.itemIdentifier currentlyAvailableInInfiniteListView:self]) {
                //ask for the item
                UIView *newItemView = [self.dataSource viewForItem:nextGap.itemIdentifier inInfiniteListView:self];
                //check that item is a UIView? YES
                if ([newItemView isKindOfClass:[UIView class]]) {
                    //check to make sure item width fits? YES
                    if (newItemView.frame.size.width == self.requiredViewWidth) {
                        //draw the item (add the subview, and stretch the scrollview content size) and record it in the internal logic (things like the size)
                        [self _drawNewItem:nextGap.itemIdentifier withView:newItemView inColumn:nextGap.columnIdentifier];
                        
                        //go back to checking if there is a gap, i.e. recurse
                        [self _drawAndLoadLoop];
                    }
                    //check to make sure item width fits? NO
                    else {
                        //raise width mismath exception
                        @throw [NSException exceptionWithName:GBWidthMismatchException reason:@"The view returned has the wrong width. Make sure the view frame width matches the column width." userInfo:@{@"object": newItemView, @"requiredViewWidth": @(self.requiredViewWidth)}];
                        return;
                    }
                }
                //check that item is a UIView? NO
                else {
                    //raise bad type exception
                    @throw [NSException exceptionWithName:GBTypeMismatchException reason:@"The object returned was not a UIView" userInfo:@{@"object":newItemView}];
                    return;
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
                        
                        //send datasource the startLoadingMoreItemsInInfiniteListView: message
                        [self.dataSource startLoadingMoreItemsInInfiniteListView:self];
                        
                        //send delegate the infiniteListViewDidStartLoadingMoreItems: message
                        if ([self.delegate respondsToSelector:@selector(infiniteListViewDidStartLoadingMoreItems:)]) {
                            [self.delegate infiniteListViewDidStartLoadingMoreItems:self];
                        }
                        
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
                            //check loadingview type? anything else
                            else {
                                //use default loading view
                                loadingViewType =GBLoadingViewTypeDefault;
                                
                                //use the default padding
                                isLoadingViewInsideOuterPadding = kDefaultForShouldPositionLoadingViewInsideOuterPadding;
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
                GBInfiniteListItemMeta oldItemMeta = *(GBInfiniteListItemMeta *)[self.columnStacks[nextGap.columnIdentifier] itemAtIndex:nextGap.itemIdentifier];
                
                //check to make sure item height matches the stored one and width the required width? YES
                if (oldItemView.frame.size.height == oldItemMeta.geometry.height && oldItemView.frame.size.width == self.requiredViewWidth) {
                    //draw the item in his old position
//                    [self _drawNewItem:nextGap.itemIdentifier withView:oldItemView inColumn:nextGap.columnIdentifier];
                    //foo complete
                    
                    //go back to checking if there is a gap, i.e. recurse
                    [self _drawAndLoadLoop];
                }
                //check to make sure item height matches the stored one and width the required width? NO
                else {
                    //raise size mismath exception
                    @throw [NSException exceptionWithName:GBSizeMismatchException reason:@"The view returned has the wrong size. Make sure the view frame matches the old one." userInfo:@{@"object": oldItemView, @"requiredViewWidth": @(self.requiredViewWidth), @"requiredViewHeight": @(oldItemMeta.geometry.height)}];
                    return;
                }
            }
            //check that item is a UIView? NO
            else {
                //raise bad type exception
                @throw [NSException exceptionWithName:GBTypeMismatchException reason:@"The object returned was not a UIView" userInfo:@{@"object":oldItemView}];
                return;
            }
        }
        //check if there is a gap? NO
        else if (nextGap.type == GBInfiniteListTypeOfGapNone) {
            //we're done
        }
    }
    //is dataDanceActive? NO
    else {
        //do nothing
    }
}

-(void)_onScreenLoop {
    
}

-(void)_emptyCheck {
    
}

-(void)_drawNewItem:(NSUInteger)itemIdentifier withView:(UIView *)itemView inColumn:(NSUInteger)columnIndex {
    //create meta struct which gets filled in along the way
    GBInfiniteListItemMeta itemMeta;
    itemMeta.itemIdentifier = itemIdentifier;
    
    //add the subview to the loadedViews
    self.loadedViews[@(itemIdentifier)] = itemView;

    //find out where to draw the item
    GBFastArray *columnStack = self.columnStacks[columnIndex];
    GBInfiniteListColumnBoundaries columnBoundaries = self.loadedItemsIndexBoundaries[columnIndex];
    GBInfiniteListItemGeometry itemGeometry;
    itemGeometry.height = itemView.frame.size.height;
    
    //if its the first item, stick it to the top, where the top is origin+outerpadding.top+header+headerMargin
    if (columnBoundaries.lastLoadedIndex == 0) {
        itemGeometry.origin = self.actualListOrigin;
    }
    //otherwise it's lastitem.origin + lastitem.height + verticalItemMargin
    else {
        GBInfiniteListItemMeta lastItem = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:columnBoundaries.lastLoadedIndex];
        itemGeometry.origin = lastItem.geometry.origin + lastItem.geometry.height + self.verticalItemMargin;
    }

    //add the meta to the columnstack
    [columnStack insertItem:&itemMeta atIndex:itemIdentifier];
    
    //set the lastLoadedItem
    self.lastLoadedItemIdentifier = itemIdentifier;
    
    //find the left origin of the column
    CGFloat columnOrigin = self.outerPadding.left + columnIndex * (self.requiredViewWidth + self.horizontalColumnMargin);
    
    //set the subview frame
    itemView.frame = CGRectMake(columnOrigin, itemGeometry.origin, self.requiredViewWidth, itemGeometry.height);
    
    //draw the actual subview
    [self.scrollView addSubview:itemView];
    
    //stretch the content size, but only if it makes it bigger, never smaller
    CGFloat newContentSizeHeight = itemGeometry.origin + itemGeometry.height + self.outerPadding.bottom;
    if (newContentSizeHeight > self.scrollView.contentSize.height) {
        self.scrollView.contentSize = CGSizeMake(self.scrollView.contentSize.width, newContentSizeHeight);
    }
}

-(void)_drawLoadingView:(UIView *)loadingView withType:(GBLoadingViewType)type paddingPreference:(BOOL)isLoadingViewInsideOuterPadding margin:(CGFloat)loadingViewBottomMargin {
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
    NSUInteger runningLongestColumnLength = 0;
    NSUInteger currentColumnHeight;
    GBInfiniteListItemMeta lastItemInColumn;
    for (int columnIndex=0; columnIndex<self.numberOfColumns; columnIndex++) {
        columnStack = self.columnStacks[columnIndex];
        columnBoundaries = self.loadedItemsIndexBoundaries[columnIndex];
        lastItemInColumn = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:columnBoundaries.lastLoadedIndex];
        
        currentColumnHeight = lastItemInColumn.geometry.origin + lastItemInColumn.geometry.height;
        
        if (currentColumnHeight > runningLongestColumnLength) {
            runningLongestColumnLength = currentColumnHeight;
        }
    }
    CGFloat furthestItemLastPoint = currentColumnHeight;
    
    //height stays the same
    newLoadingViewFrame.size.height = self.loadingView.frame.size.height;
    
    //origin and width depend on whether margin is ignored or not
    if (isLoadingViewInsideOuterPadding)  {
        newLoadingViewFrame.origin.x = self.outerPadding.left;
        newLoadingViewFrame.origin.y = furthestItemLastPoint + loadingViewBottomMargin;
        newLoadingViewFrame.size.width = self.scrollView.frame.size.width - self.outerPadding.left - self.outerPadding.right;
        spacingAfterLoadingView = self.outerPadding.bottom;
    }
    else {
        newLoadingViewFrame.origin.x = 0;
        newLoadingViewFrame.origin.y = furthestItemLastPoint + loadingViewBottomMargin + self.outerPadding.bottom;
        newLoadingViewFrame.size.width = self.scrollView.frame.size.width;
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

-(GBInfiniteListGap)_findNextGap {
    CGFloat loadedZoneTop = self.scrollView.contentOffset.y;
    CGFloat loadedZoneHeight = self.scrollView.frame.size.height + self.loadTriggerDistance;
    
    
    /* Search for gap at top */
    
    GBFastArray *columnStack;
    GBInfiniteListColumnBoundaries columnBoundaries;
    
    //try each column one by one
    for (int columnIndex=0; columnIndex<self.numberOfColumns; columnIndex++) {
        columnStack = self.columnStacks[columnIndex];
        columnBoundaries = self.loadedItemsIndexBoundaries[columnIndex];
        
        //prepare for checking the gap
        GBInfiniteListItemMeta nextItemUp;
        NSInteger index = columnBoundaries.firstLoadedIndex;
        
        //first check to see if the first item passes the top of the screen, and only if he doesnt should we start our search. If he does, we don't need to look further
        if (nextItemUp.geometry.origin <= loadedZoneTop) {
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
                if (!Lines1DOverlap(loadedZoneTop, loadedZoneHeight, nextItemUp.geometry.origin, nextItemUp.geometry.height)) {
                    GBInfiniteListGap newTopGap;
                    
                    newTopGap.type = GBInfiniteListTypeOfGapTop;
                    newTopGap.columnIdentifier = columnIndex;
                    newTopGap.itemIdentifier = nextItemUp.itemIdentifier;
                    
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
    
    //find the shortest column
    NSUInteger runningShortestColumnIndex = 0;
    NSUInteger runningShortestColumnLength = NSUIntegerMax;
    NSUInteger currentColumnHeight;
    GBInfiniteListItemMeta runningShortestItem;
    
    GBInfiniteListItemMeta lastItemInColumn;
    for (int columnIndex=0; columnIndex<self.numberOfColumns; columnIndex++) {
        columnStack = self.columnStacks[columnIndex];
        columnBoundaries = self.loadedItemsIndexBoundaries[columnIndex];
        lastItemInColumn = *(GBInfiniteListItemMeta *)[columnStack itemAtIndex:columnBoundaries.lastLoadedIndex];
        
        currentColumnHeight = lastItemInColumn.geometry.origin + lastItemInColumn.geometry.height;
        
        if (currentColumnHeight < runningShortestColumnLength) {
            runningShortestColumnIndex = columnIndex;
            runningShortestItem = lastItemInColumn;
            runningShortestColumnLength = currentColumnHeight;
        }
    }
    
    //check if the item leaves a gap
    if (runningShortestItem.geometry.origin + runningShortestItem.geometry.height < loadedZoneTop + loadedZoneHeight) {
        //if it does, return this gap
        GBInfiniteListGap newBottomGap;
        
        newBottomGap.type = GBInfiniteListTypeOfGapBottom;
        newBottomGap.columnIdentifier = runningShortestColumnIndex;
        newBottomGap.itemIdentifier = runningShortestItem.itemIdentifier;
        
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

//didScroll:
    //offscreen loop (detects who went off and informs delegate and saves them for recycling)
    //recycler loop (does actual recycling and tells delegate)
    //drawing loop (draws available items from datasource or kicks off load protocol)
    //onscreen loop (detects who came on and informs delegate)
    //empty check (if theres nothing there, then show the empty view, otherwise hide it)

//startDataDance:
    //offscreen loop (just in case, it's pretty cheap anyways)
    //recycler loop (just in case also, very cheap)
    //drawing loop
    //onscreen loop
    //empty check

//moreItemsAvailable:
    //offscreen loop (just in case, it's pretty cheap anyways)
    //recycler loop (just in case also, very cheap)
    //drawing loop
    //onscreen loop
    //empty check

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

//offscreen loop:
    //find and enumerate all items which have gone off screen
        //put them in trash list so they can be recycled
        //call offscreen handler with them

//onscreen loop:
    //find and enumerate all the items which have come on screen (can use a temporary place to store these instead of having to search for them)
        //call onscreen handler with the item

//offscreen handler:
    //update column loaded boundaries by taking item out
    //add item to the recyclebale stack
    //send the delegate an infiniteListView:view:correspondingToItemWentOffScreen: message

//onscreen handler:
    //send the delegate an infiniteListView:view:correspondingToItemCameOnScreen: message

//recycler loop:
    //iterate over all items that are in the trash
        //take them out of the loaded items list
        //tale them out of the trash list
        //put them in the recycleable stack
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