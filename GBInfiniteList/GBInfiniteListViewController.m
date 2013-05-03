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
    return 0;//foo test different one
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
    //foo update recycling API so you can give it a closure which it can use to create a new view so u always have a view, dequeueViewWithReuseIdentifier:orElseCreateWithBlock:
    
    //try to recycle one
    UIView *myView;
    if (NO) {
        
    }
    else {
        myView = [self _createNewView];
    }
    
    [self _configureViewRandomly:myView];
    
    return myView;
}

-(BOOL)canLoadMoreItemsInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    NSLog(@"can laoding more?");
    return YES;//foo try no also
}

-(void)startLoadingMoreItemsInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    NSLog(@"start laoding");
    
    NSLog(@"loaded more");
    self.numberOfCurrentlyLoadedViews += 10;//foo try different number of loaded items
    [self.infiniteListView didFinishLoadingMoreItems];
    
    
//    ExecuteAfter(0, ^{//foo try different delay
//        NSLog(@"loaded more");
//        self.numberOfCurrentlyLoadedViews += 10;//foo try different number of loaded items
//        [self.infiniteListView didFinishLoadingMoreItems];
//    });
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

-(UIView *)_createNewView {
    return [[UIView alloc] init];
}

-(UIView *)_configureViewRandomly:(UIView *)view {
    view.frame = CGRectMake(0, 0, self.infiniteListView.requiredViewWidth, [self _randomIntegerFrom:60 to:160]);
    view.backgroundColor = [self _randomColor];
    
    return view;
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
