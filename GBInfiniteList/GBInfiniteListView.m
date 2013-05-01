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

//internals
    //has pools of reusable views which can be changed completely except for width
    //has an array of view sizes so it knows which view to draw when, especially when scrolling up

typedef struct {
    NSUInteger  itemIdentifier;
    CGRect      frame;
} GBInfiniteListItemMeta;

typedef struct {
    NSUInteger  firstVisibleIndex;
    NSUInteger  lastVisibleIndex;
} GBInfiniteListColumnBoundaries;

GBInfiniteListColumnBoundaries const GBInfiniteListColumnBoundariesZero = {0, 0};

@interface GBInfiniteListView ()

//Strong pointers to little subviews (so that the creator can safely drop their pointers and it won't get dealloced)
@property (strong, nonatomic) UIView                                *headerView;
@property (strong, nonatomic) UIView                                *noItemsView;
@property (strong, nonatomic) UIView                                *loadingView;

//Scrollview where to put all the stuff on
@property (strong, nonatomic) UIScrollView                          *scrollView;

//To know when to kick off the data dance. Data dance is kicked off as soon as view is visible, init has been called, and datasource has been set. if any of these changes, the data dance stops
@property (assign, nonatomic) BOOL                                  isInitialised;
@property (assign, nonatomic) BOOL                                  isVisible;
@property (assign, nonatomic) BOOL                                  isDataSourceSet;

//This says whether the data dance is on or not
@property (assign, nonatomic) BOOL                                  isDataDanceActive;

//Redefined as readwrite
@property (assign, nonatomic, readwrite) CGFloat                    requiredViewWidth;

//Geometry stuff
@property (assign, nonatomic) NSUInteger                            numberOfColumns;
@property (assign, nonatomic) UIEdgeInsets                          outerPadding;
@property (assign, nonatomic) CGFloat                               verticalItemMargin;
@property (assign, nonatomic) CGFloat                               horizontalColumnMargin;

//Container for items that are about to be recycled
@property (strong, nonatomic) NSMutableArray                        *unrecycledViews;

//Container for items that can be recycled
@property (strong, nonatomic) NSMutableArray                        *recyclableViews;

//NSArray of GBFastArray's of GBInfiniteListItemMeta's. Fast data structure used for efficiently finding out who is visible, whether there are any gaps, calculating who just came back on screen when the infiniteList scrolls back up, and checking whether the size matches. It's fast because it's sorted in the order in which it will be queried (reverse order), and it can skip stuff it doesn't need to query because we have indexes.
@property (strong, nonatomic) NSArray                               *columnStacks;

//C-array of GBInfiniteListColumnBoundaries's. Used as an index to help making searching through columnStacks faster.
@property (assign, nonatomic) GBInfiniteListColumnBoundaries        *loadedItemsIndexBoundaries;

//A way to get to the actual view which is loaded once you have the itemIdentifier. NSDictionary where key is itemIdentifier, and value is the actual view
@property (strong, nonatomic) NSMutableDictionary                   *loadedViews;

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
    
    self.unrecycledViews = nil;
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
    
    self.unrecycledViews = [NSMutableArray new];
    self.recyclableViews = [NSMutableArray new];
    self.loadedViews = [NSMutableDictionary new];
    
    //these get initialised when the data dance starts. because they need to know the column count
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
    
    //TODO: add the other ones in here, like the list of items and their sizes, list of visible items, the pool, etc.
}

#pragma mark - Private API: Data dance state management

-(void)_initialiseColumnCountDependentDataStructures {
    NSMutableArray *newColumnStacks = [[NSMutableArray alloc] initWithCapacity:self.numberOfColumns];
    self.loadedItemsIndexBoundaries = malloc(sizeof(GBInfiniteListColumnBoundariesZero) * self.numberOfColumns);
    
    for (int i=0; i<self.numberOfColumns; i++) {
        newColumnStacks[i] = [[GBFastArray alloc] initWithTypeSize:sizeof(CGRect) initialCapacity:100 resizingFactor:1.5];
        
        self.loadedItemsIndexBoundaries[i] = GBInfiniteListColumnBoundariesZero;
    }
    
    self.columnStacks = [newColumnStacks copy];
}

-(void)_manageDataDanceState {
    BOOL newState = (self.isVisible && self.isDataSourceSet && self.isInitialised);
    
    //if it changes
    if (newState != self.isDataDanceActive) {
        //just remember it
        self.isDataDanceActive = newState;
        
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
    //set the size of the scrollView to match the infiniteListView frame
    self.scrollView.frame = self.frame;
    
    //get all the geometry stuff
    self.numberOfColumns = [self.dataSource numberOfColumnsInInfiniteListView:self];
    
    if ([self.dataSource respondsToSelector:@selector(outerPaddingInInfiniteListView:)]) {
        self.outerPadding = [self.dataSource outerPaddingInInfiniteListView:self];
    }
    
    if ([self.dataSource respondsToSelector:@selector(horizontalColumnMarginInInfiniteListView:)]) {
        self.horizontalColumnMargin = [self.dataSource horizontalColumnMarginInInfiniteListView:self];
    }
    
    if ([self.dataSource respondsToSelector:@selector(verticalItemMarginInInfiniteListView:)]) {
        self.verticalItemMargin = [self.dataSource verticalItemMarginInInfiniteListView:self];
    }
    
    //calculate the requiredViewWidth
    self.requiredViewWidth = (self.scrollView.frame.size.width - (self.outerPadding.left + self.outerPadding.right) - ((self.numberOfColumns - 1) * self.horizontalColumnMargin)) / self.numberOfColumns;
    
    //initialise column stacks n co.
    [self _initialiseColumnCountDependentDataStructures];
    
    //ask for header... this shud be encapsualted so i just get a view that's ready for display and the frame configured ...... old sentence: padding/margins configured (however i may be doing that, modifying frame, or subviewing)
    
    
    
    //kick it all off
    //TODO: do
}

-(void)_stopDataDance {
    [self _initialiseDataStructuresAndZeroState];
    
    //note: asking for new items, etc. have their own checks and they stop autonomously as soon as they realise that self.isDataDanceActive is turned off
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
    //call offscreen handler on all visible items
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
        //put them in unrecycled list so they can be recycled
        //call offscreen handler with them
    //update column boundaries or visibles... not sure

//onscreen loop:
    //find and enumerate all the items which have come on screen (can use a temporary place to store these instead of having to search for them)
        //call onscreen handler with the item
    //update column boundaries or visibles... not sure

//offscreen handler:
    //add them to the recyclebale stack
    //send the delegate an infiniteListView:view:correspondingToItemWentOffScreen: message

//onscreen handler:
    //send the delegate an infiniteListView:view:correspondingToItemCameOnScreen: message

//recycler loop:
    //iterate over all items that are in the unrecycled stack
        //take them out of the loaded items list
        //tale them out of the unrecycled list
        //put them in the recycleable stack
        //send the delegate an infiniteListView:didRecycleView:lastUsedByItem: message

//empty handler:
    //is anything shown? YES
        //hide empty view...
    //is anything shown? NO
        //show empty view...

//drawing loop: a loop that tries to fill the screen by asking for more data, or if there isnt any more available: starting the dataload protocol in hopes of getting called again when more is available
    //is dataDanceActive? YES
        //check if there is a gap? Bottom
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