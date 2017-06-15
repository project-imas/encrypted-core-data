//
//  SingleDefaultStoreManager.m
//  Incremental Store
//
//  Created by Nacho on 5/7/16.
//  Copyright © 2016 Ignacio Delgado. All rights reserved.
//

#import "SingleDefaultStoreManager.h"
#import <CoreData/CoreData.h>
#import "EncryptedStore.h"

@interface SingleDefaultStoreManager ()
@property (nonatomic, strong) NSManagedObjectContext *persistentContext;
@property (readonly, strong, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@end

@implementation SingleDefaultStoreManager

#pragma mark - Core Data stack

@synthesize managedObjectModel = _managedObjectModel;
@synthesize persistentStoreCoordinator = _persistentStoreCoordinator;
@synthesize persistentContext = _persistentContext;
@synthesize mainContext = _mainContext;
@synthesize privateContext = _privateContext;

- (instancetype)init
{
  self =[super init];
  if (self){
    [self mainContext];
    [self privateContext];
  }
  return self;
}

+ (NSURL *)applicationDocumentsDirectory
{
  NSURL *result = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
  return result;
}

+ (NSURL *)databaseURL
{
  return [[self applicationDocumentsDirectory] URLByAppendingPathComponent:@"Concurrency.sqlite"];
}

- (NSManagedObjectModel *)managedObjectModel
{
  // The managed object model for the application. It is a fatal error for the application not to be able to find and load its model.
  if (_managedObjectModel != nil) {
    return _managedObjectModel;
  }
  NSURL *modelURL = [[NSBundle bundleForClass:[EncryptedStore class]] URLForResource:@"ClassModel" withExtension:@"momd"];
  _managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
  return _managedObjectModel;
}

- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
  // The persistent store coordinator for the application. This implementation creates and returns a coordinator, having added the store for the application to it.
  if (_persistentStoreCoordinator != nil) {
    return _persistentStoreCoordinator;
  }
  
  // Create the coordinator and store
  NSError *error = nil;
  _persistentStoreCoordinator = [self createPersistentStoreCoordinator:&error];
  NSAssert(_persistentStoreCoordinator, @"Unable to add persistent store: %@", error);
  
  return _persistentStoreCoordinator;
}

- (NSPersistentStoreCoordinator *)createPersistentStoreCoordinator:(__autoreleasing NSError **)error
{
  NSPersistentStoreCoordinator *result = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.managedObjectModel];
  
  if (![result addPersistentStoreWithType:NSSQLiteStoreType
                            configuration:nil
                                      URL:[[self class] databaseURL]
                                  options:@{
                                            NSSQLitePragmasOption: @{@"journal_mode":@"DELETE"}
                                            }
                                    error:error]) {
    return nil;
  }else{
    return result;
  }
}

- (NSManagedObjectContext *)persistentContext
{
  if (_persistentContext != nil) {
    return _persistentContext;
  }
  
  NSPersistentStoreCoordinator *coordinator = [self persistentStoreCoordinator];
  if (!coordinator) {
    return nil;
  }
  
  _persistentContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
  [_persistentContext setPersistentStoreCoordinator:coordinator];
  _persistentContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy;
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(contextDidSavePersistentContext:)
                                               name:NSManagedObjectContextDidSaveNotification
                                             object:_persistentContext];
  return _persistentContext;
}

- (NSManagedObjectContext *)mainContext
{
  if (_mainContext != nil) {
    return _mainContext;
  }
  _mainContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
  [_mainContext setParentContext:self.persistentContext];
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(contextDidSaveMainContext:)
                                               name:NSManagedObjectContextDidSaveNotification
                                             object:_mainContext];
  return _mainContext;
}

- (NSManagedObjectContext *)privateContext
{
  if (_privateContext != nil) {
    return _privateContext;
  }
  _privateContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
  [_privateContext setParentContext:self.persistentContext];
  return _privateContext;
}

#pragma mark - Core Data Saving support

- (void)saveContext:(NSManagedObjectContext *)managedObjectContext
{
  if (managedObjectContext != nil) {
    __block NSError *error = nil;
    if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error]) {
      NSAssert(NO, @"Unresolved error %@, %@", error, [error userInfo]);
    } else if (managedObjectContext.parentContext) { //If there is a parent context, chain up the save
      [managedObjectContext.parentContext performBlock:^{
        [managedObjectContext.parentContext save:nil];
      }];
    }
  }
}

- (void)contextDidSaveMainContext:(NSNotification *)notification
{
  [self.privateContext performBlock:^{
    [self.privateContext mergeChangesFromContextDidSaveNotification:notification];
  }];
}

- (void)contextDidSavePersistentContext:(NSNotification *)notification
{
  // We want to propagate the final ObjectIDs to the main context as soon as possible
  if (((NSSet *)notification.userInfo[NSInsertedObjectsKey]).count > 0 || ((NSSet *)notification.userInfo[NSUpdatedObjectsKey]).count > 0) {
    NSError *error = nil;
    if (![self.mainContext obtainPermanentIDsForObjects:_mainContext.registeredObjects.allObjects error:&error]) {
      NSAssert(NO, @"Error refreshing temporary ObjectID in main context - %@ - %@ -", error, error.userInfo);
    }
  }
}

#pragma mark - Helper methods

+ (void)deleteDatabase
{
  [[NSFileManager defaultManager] removeItemAtURL:[self databaseURL] error:nil];
}

@end
