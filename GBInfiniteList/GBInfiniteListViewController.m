//
//  GBInfiniteListViewController.m
//  GBInfiniteList
//
//  Created by Luka Mirosevic on 30/04/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//

#import "GBInfiniteListViewController.h"

#import "GBToolbox.h"//foo test
#import "MyView.h"//foo test

typedef struct {
    NSUInteger identifier;
    CGFloat hue;
    CGFloat width;
    CGFloat height;
} MyItemProperties;//foo test

@interface GBInfiniteListViewController ()

@property (strong, nonatomic, readwrite) GBInfiniteListView *infiniteListView;

@property (strong, nonatomic) NSMutableArray *loadedItems;//foo test

@end

@implementation GBInfiniteListViewController

//creates an infiniteListView for you and sets the frame to match and adds it as a subview to this viewController's view, also sets delegate and dataSource methods.

-(void)reset {
    l(@"reset in here");
    [self.infiniteListView reset];
}

//foo testing
-(void)scrollUp {
    [self.infiniteListView scrollToPosition:0 animated:NO];
}
-(void)scrollDown {
    [self.infiniteListView scrollToPosition:10000 animated:NO];
}

#pragma mark - Memory


#pragma mark - Lifecycle

-(void)viewDidLoad {
    [super viewDidLoad];
    
    self.loadedItems = [[NSMutableArray alloc] init];
    
    self.infiniteListView = [[GBInfiniteListView alloc] initWithFrame:self.view.bounds];
    self.infiniteListView.delegate = self;
    self.infiniteListView.dataSource = self;
    
    [self.view addSubview:self.infiniteListView];
    
    ExecuteAfter(3, ^{
//        l(@"go");
//        [self.infiniteListView reset];//foo this doesnt work
    });
}

#pragma mark - GBInfiniteListViewDataSource

-(NSUInteger)numberOfColumnsInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return 3;//foo test different one
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
//    l(@"avail?: %d", itemIdentifier);
    
    return itemIdentifier < self.loadedItems.count;
}

-(UIView *)viewForItem:(NSUInteger)itemIdentifier inInfiniteListView:(GBInfiniteListView *)infiniteListView {
//    l(@"load item: %d", itemIdentifier);
    
    //get a view object...
    MyView *myView = (MyView *)[infiniteListView dequeueReusableViewWithIdentifier:@"SimpleColorBox" elseCreateWithBlock:^UIView *{
        return [[MyView alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
    }];
    
    //configure the view
    MyItemProperties myItem;
    [[self.loadedItems objectAtIndex:itemIdentifier] getValue:&myItem];
    myView.frame = CGRectMake(0, 0, myItem.width, myItem.height);
    [myView setHue:myItem.hue];
    [myView setText:[NSString stringWithFormat:@"#%d", myItem.identifier]];
    
    return myView;
}

-(BOOL)canLoadMoreItemsInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return YES;//foo try no also
}

-(void)startLoadingMoreItemsInInfiniteListView:(GBInfiniteListView *)infiniteListView {
//    NSLog(@"start loading more from server");
    
    //pretend to download some stuff off a server and store it locally
    for (int i=0; i<50; i++) {
        NSUInteger newIdentifier = self.loadedItems.count;
        
        MyItemProperties newItem;
        newItem.identifier = newIdentifier;
        newItem.width = self.infiniteListView.requiredViewWidth;
        newItem.height = [self randomIntegerFrom:60 to:160];
        newItem.hue = [self randomHue];
        
        [self.loadedItems addObject:[NSValue valueWithBytes:&newItem objCType:@encode(MyItemProperties)]];
    }
    
    [self.infiniteListView didFinishLoadingMoreItems];
    
//    ExecuteAfter(0, ^{//foo try different delay
//        NSLog(@"loaded more");
//        self.numberOfCurrentlyLoadedViews += 10;//foo try different number of loaded items
//        [self.infiniteListView didFinishLoadingMoreItems];
//    });
}

-(void)infiniteListView:(GBInfiniteListView *)infiniteListView didRecycleView:(UIView *)view lastUsedByItem:(NSUInteger)itemIdentifier {
//    NSLog(@"Recycled view with identifier: %d", itemIdentifier);
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

//foo add to GBToolbox
-(NSInteger)randomIntegerFrom:(NSInteger)min to:(NSInteger)max {
    return arc4random() % (max-min) + min;
}

//foo add to GBToolbox
-(UIColor *)randomColor {
    CGFloat hue = ( arc4random() % 256 / 256.0 );  //  0.0 to 1.0
    CGFloat saturation = ( arc4random() % 128 / 256.0 ) + 0.5;  //  0.5 to 1.0, away from white
    CGFloat brightness = ( arc4random() % 128 / 256.0 ) + 0.5;  //  0.5 to 1.0, away from black
    return [UIColor colorWithHue:hue saturation:saturation brightness:brightness alpha:1];
}

//foo add to GBToolbox
-(CGFloat)randomHue {
    return arc4random() % 256 / 256.0;
}

@end
