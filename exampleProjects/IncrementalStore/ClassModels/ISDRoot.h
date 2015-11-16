//
//  ISDRoot.h
//  Incremental Store
//
//  Created by Richard Hodgkins on 31/08/2014.
//  Copyright (c) 2014 Caleb Davenport. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class ISDParent;

@interface ISDRoot : NSManagedObject

@property (nonatomic, retain) NSString * name;
@property (nonatomic, retain) NSSet *oneToMany;
@property (nonatomic, retain) ISDParent *oneToOne;
@property (nonatomic, retain) NSSet *manyToMany;
@end

@interface ISDRoot (CoreDataGeneratedAccessors)

- (void)addOneToManyObject:(ISDParent *)value;
- (void)removeOneToManyObject:(ISDParent *)value;
- (void)addOneToMany:(NSSet *)values;
- (void)removeOneToMany:(NSSet *)values;

- (void)addManyToManyObject:(ISDParent *)value;
- (void)removeManyToManyObject:(ISDParent *)value;
- (void)addManyToMany:(NSSet *)values;
- (void)removeManyToMany:(NSSet *)values;

@end
