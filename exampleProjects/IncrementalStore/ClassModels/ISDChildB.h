//
//  ISDChildB.h
//  Incremental Store
//
//  Created by Richard Hodgkins on 31/08/2014.
//  Copyright (c) 2014 Caleb Davenport. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "ISDParent.h"


@interface ISDChildB : ISDParent

@property (nonatomic, retain) NSString * attributeB;
@property (nonatomic, retain) ISDRoot *multipleOneToMany;

@end
