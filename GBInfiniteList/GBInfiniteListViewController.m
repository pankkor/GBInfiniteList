//
//  GBInfiniteListViewController.m
//  GBInfiniteList
//
//  Created by Luka Mirosevic on 30/04/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//

#import "GBInfiniteListViewController.h"

@interface GBInfiniteListViewController ()

@property (strong, nonatomic, readwrite) GBInfiniteListView *infiniteListView;

@end

@implementation GBInfiniteListViewController

//creates an infiniteListView for you and sets the frame to match and adds it as a subview to this viewController's view, also sets delegate and dataSource methods.

#pragma mark - Memory


#pragma mark - Lifecycle

-(void)viewDidLoad {
    [super viewDidLoad];
    
    self.infiniteListView = [[GBInfiniteListView alloc] initWithFrame:self.view.frame];
    self.infiniteListView.delegate = self;
    self.infiniteListView.dataSource = self;
}

#pragma mark - GBInfiniteListViewDataSource

-(NSUInteger)numberOfColumnsInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return 2;
}

-(CGFloat)loadTriggerDistanceInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return 100;
}

-(UIEdgeInsets)outerPaddingInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return UIEdgeInsetsMake(10, 10, 10, 10);//foo test other sizes
}

-(CGFloat)verticalItemMarginInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return 6;
}

-(CGFloat)horizontalColumnMarginInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return 10;
}

-(BOOL)isViewForItem:(NSUInteger)itemIdentifier currentlyAvailableInInfiniteListView:(GBInfiniteListView *)infiniteListView;

-(UIView *)viewForItem:(NSUInteger)itemIdentifier inInfiniteListView:(GBInfiniteListView *)infiniteListView;

-(BOOL)canLoadMoreItemsInInfiniteListView:(GBInfiniteListView *)infiniteListView;

-(void)startLoadingMoreItemsInInfiniteListView:(GBInfiniteListView *)infiniteListView;

-(void)infiniteListView:(GBInfiniteListView *)infiniteListView didRecycleView:(UIView *)view lastUsedByItem:(NSUInteger)itemIdentifier {
    NSLog(@"Recycled view with identifier: %d", itemIdentifier);
}

-(UIView *)headerViewInInfiniteListView:(GBInfiniteListView *)infiniteListView;
-(BOOL)shouldPositionHeaderViewInsideOuterPaddingInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return YES;//foo try NO
}
-(CGFloat)marginForHeaderViewInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return 30;
}

-(UIView *)noItemsViewInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    //foo try another view
    return nil;
}

-(BOOL)shouldShowLoadingIndicatorInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return YES;
}
-(UIView *)loadingViewInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return nil;//foo try another
}
-(BOOL)shouldPositionLoadingViewInsideOuterPaddingInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return YES;//foo try another
}

-(CGFloat)marginForLoadingViewInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return 12;
}

//#pragma mark - GBInfiniteListViewDelegate

#pragma mark - Testing

@end
