//
//  DoubleEncryptedStoreManager.m
//  Incremental Store
//
//  Created by Nacho on 5/7/16.
//  Copyright © 2016 Caleb Davenport. All rights reserved.
//

#import "DoubleEncryptedStoreManager.h"

@interface DoubleEncryptedStoreManager ()
@property (readonly, strong, nonatomic) NSPersistentStoreCoordinator *privatePersistentStoreCoordinator;
@end

@implementation DoubleEncryptedStoreManager

@synthesize privatePersistentStoreCoordinator = _privatePersistentStoreCoordinator;
@synthesize privateContext = _privateContext;

- (NSPersistentStoreCoordinator *)privatePersistentStoreCoordinator
{
  // The persistent store coordinator for the application. This implementation creates and returns a coordinator, having added the store for the application to it.
  if (_privatePersistentStoreCoordinator != nil) {
    return _privatePersistentStoreCoordinator;
  }
  
  // Create the coordinator and store
  NSError *error = nil;
  _privatePersistentStoreCoordinator = [self createPersistentStoreCoordinator:&error];
  NSAssert(_privatePersistentStoreCoordinator, @"Unable to add persistent store: %@", error);
  
  return _privatePersistentStoreCoordinator;
}

- (NSManagedObjectContext *)privateContext
{
  if (_privateContext != nil) {
    return _privateContext;
  }
  
  NSPersistentStoreCoordinator *coordinator = [self privatePersistentStoreCoordinator];
  if (!coordinator) {
    return nil;
  }
  
  _privateContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
  [_privateContext setPersistentStoreCoordinator:coordinator];
  _privateContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy;
  
  return _privateContext;
}

- (void)contextDidSaveMainContext:(NSNotification *)notification
{
  // Ignore this notification
}

@end
