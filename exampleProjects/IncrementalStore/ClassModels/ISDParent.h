//
//  ISDParent.h
//  Incremental Store
//
//  Created by Richard Hodgkins on 31/08/2014.
//  Copyright (c) 2014 Caleb Davenport. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class ISDRoot;

@interface ISDParent : NSManagedObject

@property (nonatomic, retain) NSString * name;
@property (nonatomic, retain) ISDRoot *oneToManyInverse;
@property (nonatomic, retain) ISDRoot *oneToOneInverse;
@property (nonatomic, retain) ISDRoot *oneToOneNilInverse;
@property (nonatomic, retain) NSSet *manyToManyInverse;
@end

@interface ISDParent (CoreDataGeneratedAccessors)

- (void)addManyToManyInverseObject:(ISDRoot *)value;
- (void)removeManyToManyInverseObject:(ISDRoot *)value;
- (void)addManyToManyInverse:(NSSet *)values;
- (void)removeManyToManyInverse:(NSSet *)values;

@end
