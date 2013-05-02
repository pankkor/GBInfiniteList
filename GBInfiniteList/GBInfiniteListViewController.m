//
//  GBInfiniteListViewController.m
//  GBInfiniteList
//
//  Created by Luka Mirosevic on 30/04/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//

#import "GBInfiniteListViewController.h"

#import "GBToolbox.h"//foo test

@interface GBInfiniteListViewController ()

@property (strong, nonatomic, readwrite) GBInfiniteListView *infiniteListView;

@property (assign, nonatomic) NSUInteger numberOfCurrentlyLoadedViews;//foo test

@end

@implementation GBInfiniteListViewController

//creates an infiniteListView for you and sets the frame to match and adds it as a subview to this viewController's view, also sets delegate and dataSource methods.

-(void)reset {
    l(@"reset in here");
    [self.infiniteListView reset];
}

#pragma mark - Memory


#pragma mark - Lifecycle

-(void)viewDidLoad {
    [super viewDidLoad];
    
    l(@"viewdidload with following frame:");
    _lRect(self.view.frame);
    
    self.numberOfCurrentlyLoadedViews = 10;//foo try with 0
    
//    self.view.backgroundColor = [UIColor blueColor];//foo test
    
    self.infiniteListView = [[GBInfiniteListView alloc] initWithFrame:self.view.bounds];
    self.infiniteListView.delegate = self;
    self.infiniteListView.dataSource = self;
    
    [self.view addSubview:self.infiniteListView];
}

#pragma mark - GBInfiniteListViewDataSource

-(NSUInteger)numberOfColumnsInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return 2;//foo test different one
}

-(CGFloat)loadTriggerDistanceInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return 100;//foo test different one
}

-(UIEdgeInsets)outerPaddingInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return UIEdgeInsetsMake(10, 10, 10, 10);//foo test other sizes
}

-(CGFloat)verticalItemMarginInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return 6;//foo test more
}

-(CGFloat)horizontalColumnMarginInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return 10;//foo test more
}

-(BOOL)isViewForItem:(NSUInteger)itemIdentifier currentlyAvailableInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return itemIdentifier < self.numberOfCurrentlyLoadedViews;
}

-(UIView *)viewForItem:(NSUInteger)itemIdentifier inInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return [self _randomView];
}

-(BOOL)canLoadMoreItemsInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return NO;
    return YES;//foo try no also
}

-(void)startLoadingMoreItemsInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    ExecuteAfter(3, ^{//foo try different delay
        self.numberOfCurrentlyLoadedViews += 10;//foo try different number of loaded items
        [self.infiniteListView didFinishLoadingMoreItems];
    });
}

-(void)infiniteListView:(GBInfiniteListView *)infiniteListView didRecycleView:(UIView *)view lastUsedByItem:(NSUInteger)itemIdentifier {
    NSLog(@"Recycled view with identifier: %d", itemIdentifier);
}

-(UIView *)headerViewInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return nil;//foo try sth else too
}

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

-(UIView *)_randomView {
    UIView *newView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.infiniteListView.requiredViewWidth, [self _randomIntegerFrom:20 to:60])];
    newView.backgroundColor = [self _randomColor];
    
    return newView;
}

//foo add to GBToolbox
-(NSInteger)_randomIntegerFrom:(NSInteger)min to:(NSInteger)max {
    return arc4random() % (max-min) + min;
}

//foo add to GBToolbox
-(UIColor *)_randomColor {
    CGFloat hue = ( arc4random() % 256 / 256.0 );  //  0.0 to 1.0
    CGFloat saturation = ( arc4random() % 128 / 256.0 ) + 0.5;  //  0.5 to 1.0, away from white
    CGFloat brightness = ( arc4random() % 128 / 256.0 ) + 0.5;  //  0.5 to 1.0, away from black
    return [UIColor colorWithHue:hue saturation:saturation brightness:brightness alpha:1];
}

@end
