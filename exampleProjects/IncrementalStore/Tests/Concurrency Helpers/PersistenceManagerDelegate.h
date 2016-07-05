//
// Created by Nacho on 4/7/16.
// Copyright (c) 2016 Ignacio Delgado. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@protocol PersistenceManagerDelegate <NSObject>
@property (nonatomic, strong) NSManagedObjectContext *mainContext;
@property (nonatomic, strong) NSManagedObjectContext *privateContext;
- (void)saveContext:(NSManagedObjectContext *)context;
+ (void)deleteDatabase;
@end