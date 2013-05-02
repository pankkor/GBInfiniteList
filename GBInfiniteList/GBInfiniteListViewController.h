//
//  GBInfiniteListViewController.h
//  GBInfiniteList
//
//  Created by Luka Mirosevic on 30/04/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//

#import <UIKit/UIKit.h>

//foo might need a start method which you call once your view has been sized properly

#import "GBInfiniteListView.h"

@interface GBInfiniteListViewController : UIViewController <GBInfiniteListViewDataSource, GBInfiniteListViewDelegate>

//this one is created and fills the view upon init
@property (strong, nonatomic, readonly) GBInfiniteListView *infiniteListView;

-(void)reset;//foo test

@end
