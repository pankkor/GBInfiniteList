//
//  GBInfiniteListDemoViewController.h
//  GBInfiniteList
//
//  Created by Luka Mirosevic on 30/04/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "GBInfiniteListView.h"

@interface GBInfiniteListDemoViewController : UIViewController <GBInfiniteListViewDataSource, GBInfiniteListViewDelegate>

//this one is created and fills the view upon init
@property (strong, nonatomic, readonly) GBInfiniteListView *infiniteListView;

-(void)reset;

-(void)scrollUp;
-(void)scrollDown;

@end
