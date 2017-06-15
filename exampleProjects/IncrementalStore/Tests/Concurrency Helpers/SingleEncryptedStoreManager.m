//
//  SingleEncryptedStoreManager.m
//  Incremental Store
//
//  Created by Nacho on 5/7/16.
//  Copyright © 2016 Ignacio Delgado. All rights reserved.
//

#import "EncryptedStore.h"
#import "SingleEncryptedStoreManager.h"

@implementation SingleEncryptedStoreManager

+ (NSURL *)databaseURL
{
  return [[self applicationDocumentsDirectory] URLByAppendingPathComponent:@"ConcurrencyEncrypted.sqlite"];
}

- (NSPersistentStoreCoordinator *)createPersistentStoreCoordinator:(__autoreleasing NSError **)error
{
  return [EncryptedStore makeStoreWithOptions:@{
                                                EncryptedStoreType : NSSQLiteStoreType,
                                                EncryptedStorePassphraseKey : @"129837/asg$",
                                                EncryptedStoreDatabaseLocation : [[self class] databaseURL],
                                                NSInferMappingModelAutomaticallyOption : @YES,
                                                NSMigratePersistentStoresAutomaticallyOption : @YES,
                                                NSSQLitePragmasOption : @{@"synchronous" : @"OFF"}
                                                }
                           managedObjectModel:self.managedObjectModel
                                        error:error];
}

@end