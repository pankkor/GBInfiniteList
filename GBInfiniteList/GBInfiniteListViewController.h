//
//  GBInfiniteListViewController.h
//  GBInfiniteList
//
//  Created by Luka Mirosevic on 30/04/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "GBInfiniteListView.h"

@interface GBInfiniteListViewController : UIViewController <GBInfiniteListDataSource, GBInfiniteListDelegate>

//this one is created and fills the view upon init
@property (strong, nonatomic, readonly) GBInfiniteListView *infiniteListView;

//creates an infiniteListView for you and sets the frame to match and adds it as a subview to this viewController's view, also sets delegate and dataSource methods.
-(id)initWithFrame:(CGRect)frame;

@end
