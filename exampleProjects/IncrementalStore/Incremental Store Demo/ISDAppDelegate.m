//
//  ISDAppDelegate.m
//  Incremental Store Demo
//
// Copyright 2012 - 2014 The MITRE Corporation, All Rights Reserved.
//

#import "EncryptedStore.h"

#import "ISDAppDelegate.h"

// TOGGLE ECD ON = 1 AND OFF = 0
#define USE_ENCRYPTED_STORE 1

@implementation ISDAppDelegate

+ (NSPersistentStoreCoordinator *)persistentStoreCoordinator {
    static NSPersistentStoreCoordinator *coordinator = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
    
        // get the model
        NSManagedObjectModel *model = [NSManagedObjectModel mergedModelFromBundles:nil];
        
        // get the coordinator
        coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
        
        // add store
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSURL *applicationSupportURL = [[fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
        [fileManager createDirectoryAtURL:applicationSupportURL withIntermediateDirectories:NO attributes:nil error:nil];
        NSURL *databaseURL = [applicationSupportURL URLByAppendingPathComponent:@"database.sqlite"];
        NSError *error = nil;
        
//        [[NSFileManager defaultManager] removeItemAtURL:databaseURL error:&error];
        
        NSDictionary *options = @{
            EncryptedStorePassphraseKey : @"DB_KEY_HERE",
//            EncryptedStoreDatabaseLocation : databaseURL,
//            NSMigratePersistentStoresAutomaticallyOption : @YES,
            NSInferMappingModelAutomaticallyOption : @YES
        };
        NSPersistentStore *store = [coordinator
                                    addPersistentStoreWithType:EncryptedStoreType
                                    configuration:nil
                                    URL:databaseURL
                                    options:options
                                    error:&error];
//        coordinator = [EncryptedStore makeStoreWithOptions:options managedObjectModel:model];
        
        NSAssert(store, @"Unable to add persistent store!\n%@", error);
        
    });
    return coordinator;
}

+ (NSPersistentStoreCoordinator *)persistentStoreCoordinator_CoreData {
    NSError *error = nil;
    NSURL *storeURL = [[[[NSFileManager defaultManager]
                         URLsForDirectory:NSDocumentDirectory
                         inDomains:NSUserDomainMask]
                            lastObject]
                                URLByAppendingPathComponent:@"cleardb.sqlite"];
    
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[NSManagedObjectModel mergedModelFromBundles:nil]];
    [coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error];
    
    return coordinator;
    
}

+ (NSManagedObjectContext *)managedObjectContext {
    static NSManagedObjectContext *context = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
#if USE_ENCRYPTED_STORE
        [context setPersistentStoreCoordinator:[self persistentStoreCoordinator]];
#else
        [context setPersistentStoreCoordinator:[self persistentStoreCoordinator_CoreData]];
#endif
    });
    return context;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    // insert a few objects if we don't have any
    {
        NSManagedObjectContext *context = [ISDAppDelegate managedObjectContext];
        NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
        NSUInteger count = [context countForFetchRequest:request error:nil];
        if (count == 0) {
            NSArray *array = [NSArray arrayWithObjects:@"Gregg", @"Jon", @"Jase", @"Gavin", nil];
            [array enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                NSManagedObject *user = [NSEntityDescription insertNewObjectForEntityForName:@"User" inManagedObjectContext:context];
                [user setValue:obj forKey:@"name"];
                for (NSInteger i = 0; i < 3; i++) {
                    NSManagedObject *post = [NSEntityDescription insertNewObjectForEntityForName:@"Post" inManagedObjectContext:context];
                    [post setValue:@"Test Title" forKey:@"title"];
                    [post setValue:@"Test body" forKey:@"body"];
                    [post setValue:user forKey:@"user"];
                }
            }];
            [context save:nil];
        }
    }
    
    // return
    return YES;
    
}

@end
