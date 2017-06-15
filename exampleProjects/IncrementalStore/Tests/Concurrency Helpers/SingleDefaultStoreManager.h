//
//  SingleDefaultStoreManager.h
//  Incremental Store
//
//  Created by Nacho on 5/7/16.
//  Copyright © 2016 Ignacio Delgado. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PersistenceManagerDelegate.h"

@interface SingleDefaultStoreManager : NSObject <PersistenceManagerDelegate>
@property (readonly, strong, nonatomic) NSManagedObjectModel *managedObjectModel;
+ (NSURL *)applicationDocumentsDirectory;
- (NSPersistentStoreCoordinator *)createPersistentStoreCoordinator:(__autoreleasing NSError **)error;
@end
