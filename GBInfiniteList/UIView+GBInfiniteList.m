//
//  UIView+GBInfiniteList.m
//  GBInfiniteList
//
//  Created by Luka Mirosevic on 01/05/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//

#import "UIView+GBInfiniteList.h"

#import <objc/runtime.h>

NSString * const GBImmutabilityException = @"GBImmutabilityException";

@implementation UIView (GBInfiniteList)

#pragma mark - Storage

static char gb_reuseIdentifier_key;
-(void)setReuseIdentifier:(NSString *)reuseIdentifier {
    if (self.reuseIdentifier == nil) {
        objc_setAssociatedObject(self, &gb_reuseIdentifier_key, reuseIdentifier, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    else {
        @throw [NSException exceptionWithName:GBImmutabilityException reason:@"You can only set the reuseIdentifier once. Once it's been set it cannot be changed" userInfo:nil];
    }
}

-(NSString *)reuseIdentifier {
    return objc_getAssociatedObject(self, &gb_reuseIdentifier_key);
}

#pragma mark - Memory

-(id)initWithReuseIdentifier:(NSString *)reuseIdentifier {
    id that = [self init];
    if (that && [that isKindOfClass:[UIView class]]) {
        ((UIView *)that).reuseIdentifier = reuseIdentifier;
    }

    return that;
}

-(id)initWithFrame:(CGRect)frame reuseIdentifier:(NSString *)reuseIdentifier {
    id that = [self initWithFrame:frame];
    if (that && [that isKindOfClass:[UIView class]]) {
        ((UIView *)that).reuseIdentifier = reuseIdentifier;
    }
    
    return that;
}

@end
