//
//  UIView+GBInfiniteList.h
//  GBInfiniteList
//
//  Created by Luka Mirosevic on 01/05/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//

#import <UIKit/UIKit.h>

extern NSString * const GBImmutabilityException;

@interface UIView (GBInfiniteList)

@property (copy, nonatomic) NSString *reuseIdentifier;

-(id)initWithReuseIdentifier:(NSString *)reuseIdentifier;
-(id)initWithFrame:(CGRect)frame reuseIdentifier:(NSString *)reuseIdentifier;

@end
