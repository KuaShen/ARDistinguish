//
//  UIFont+DIExtension.m
//  ARDistinguish_Example
//
//  Created by mac on 2019/4/29.
//  Copyright © 2019 KuaShen. All rights reserved.
//

#import "UIFont+DIExtension.h"

@implementation UIFont (DIExtension)

+ (UIFont *)fontWithTraits:(UIFontDescriptorSymbolicTraits)traits{
    
    UIFontDescriptor *descriptor = [[UIFontDescriptor alloc]init];
    descriptor = [descriptor fontDescriptorWithSymbolicTraits:traits];
    
    return [UIFont fontWithDescriptor:descriptor size:0];
}

@end
