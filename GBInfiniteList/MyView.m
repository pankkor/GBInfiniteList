//
//  MyView.m
//  GBInfiniteList
//
//  Created by Luka Mirosevic on 03/05/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//

#import "MyView.h"

@interface MyView ()

@property (strong, nonatomic) UILabel *label;

@end


@implementation MyView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        
        self.label = [[UILabel alloc] initWithFrame:frame];
        self.label.textAlignment = NSTextAlignmentCenter;
        self.label.textColor = [UIColor whiteColor];
        self.label.font = [UIFont fontWithName:@"ArialRoundedMTBold" size:20];
        self.label.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        self.label.backgroundColor = [UIColor clearColor];
        
        [self addSubview:self.label];
    }
    return self;
}

-(void)setText:(NSString *)text {
    self.label.text = text;
}

-(void)setHue:(CGFloat)hue {
    self.backgroundColor = [UIColor colorWithHue:hue saturation:0.5 brightness:0.5 alpha:1];
}

@end
