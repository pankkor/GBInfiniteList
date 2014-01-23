//
//  GBInfiniteListDemoViewController.m
//  GBInfiniteList
//
//  Created by Luka Mirosevic on 30/04/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//

#import "GBInfiniteListDemoViewController.h"

#import "GBToolbox.h"
#import "MyView.h"

typedef struct {
    NSUInteger identifier;
    CGFloat hue;
    CGFloat width;
    CGFloat height;
} MyItemProperties;

@interface GBInfiniteListDemoViewController ()

@property (strong, nonatomic, readwrite) GBInfiniteListView *infiniteListView;

@property (strong, nonatomic) NSMutableArray *loadedItems;

@end

@implementation GBInfiniteListDemoViewController

//creates an infiniteListView for you and sets the frame to match and adds it as a subview to this viewController's view, also sets delegate and dataSource methods.

-(void)reset {
    [self.infiniteListView reset];
}

-(void)scrollUp {
    [self.infiniteListView scrollToPosition:0 animated:NO];
}
-(void)scrollDown {
    [self.infiniteListView scrollToPosition:10000 animated:NO];
}

#pragma mark - Lifecycle

-(void)viewDidLoad {
    [super viewDidLoad];
    
    self.loadedItems = [[NSMutableArray alloc] init];
    
    self.infiniteListView = [[GBInfiniteListView alloc] initWithFrame:self.view.bounds];
    self.infiniteListView.delegate = self;
    self.infiniteListView.dataSource = self;
    
    [self.view addSubview:self.infiniteListView];
}

#pragma mark - GBInfiniteListViewDataSource

-(NSUInteger)numberOfColumnsInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return 3;
}

-(CGFloat)loadTriggerDistanceInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return 100;
}

-(UIEdgeInsets)outerPaddingInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return UIEdgeInsetsMake(10, 10, 10, 10);
}

-(CGFloat)verticalItemMarginInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return 6;
}

-(CGFloat)horizontalColumnMarginInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return 10;
}

-(BOOL)isViewForItem:(NSUInteger)itemIdentifier currentlyAvailableInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return itemIdentifier < self.loadedItems.count;
}

-(UIView *)viewForItem:(NSUInteger)itemIdentifier inInfiniteListView:(GBInfiniteListView *)infiniteListView {
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
    return YES;
}

-(void)startLoadingMoreItemsInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    //pretend to download some stuff off a server and store it locally
    for (int i=0; i<50; i++) {
        NSUInteger newIdentifier = self.loadedItems.count;
        
        MyItemProperties newItem;
        newItem.identifier = newIdentifier;
        newItem.width = self.infiniteListView.requiredViewWidth;
        newItem.height = RandomIntegerBetween(60, 260);
        newItem.hue = Random();
        
        [self.loadedItems addObject:[NSValue valueWithBytes:&newItem objCType:@encode(MyItemProperties)]];
    }
    
    [self.infiniteListView didFinishLoadingMoreItems];
}

-(void)infiniteListView:(GBInfiniteListView *)infiniteListView didRecycleView:(UIView *)view lastUsedByItem:(NSUInteger)itemIdentifier {
    NSLog(@"Recycled view with identifier: %d", itemIdentifier);
}

-(UIView *)headerViewInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return nil;
}

-(BOOL)shouldPositionHeaderViewInsideOuterPaddingInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return YES;
}
-(CGFloat)marginForHeaderViewInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return 30;
}

-(UIView *)noItemsViewInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return nil;
}

-(BOOL)shouldShowLoadingIndicatorInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return YES;
}
-(UIView *)loadingViewInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return nil;
}
-(BOOL)shouldPositionLoadingViewInsideOuterPaddingInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return YES;
}

-(CGFloat)marginForLoadingViewInInfiniteListView:(GBInfiniteListView *)infiniteListView {
    return 12;
}

@end
