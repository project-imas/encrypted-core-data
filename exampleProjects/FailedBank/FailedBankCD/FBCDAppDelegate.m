//
//  FBCDAppDelegate.m
//  FailedBankCD
//
//  Created by Adam Burkepile on 3/23/12.
//  Copyright (c) 2012 Adam Burkepile. All rights reserved.
//

#import "FBCDAppDelegate.h"
#import "FBCDMasterViewController.h"
#import "FailedBankInfo.h"
#import "FailedBankDetails.h"
#import "EncryptedStore.h"

/*
 *  USE_ENCRYPTED_STORE
 *      0 : Core Data
 *      1 : EncryptedStore makeStore:passcode:
 *      2 : EncryptedStore makeStoreWithOptions:managedObjectModel:
 *      3 : EncryptedStore makeStoreWithStructOptions:managedObjectModel:
 */

#define USE_ENCRYPTED_STORE 3

@implementation FBCDAppDelegate

@synthesize window = _window;
@synthesize managedObjectContext = __managedObjectContext;
@synthesize managedObjectModel = __managedObjectModel;
@synthesize persistentStoreCoordinator = __persistentStoreCoordinator;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{

    
    
//    NSError *error;
//    
//    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"FailedBankDetails"];
//    NSArray *fetched = [[self managedObjectContext] executeFetchRequest:req error:&error];
//    NSDate *this = [[fetched lastObject] closeDate];
//    
//    [req setPredicate:[NSPredicate predicateWithFormat:@"ANY closeDate < %@",this]];
//    fetched = [[self managedObjectContext] executeFetchRequest:req error:&error];
//    NSLog(@"%d---%@",[this timeIntervalSince1970] == [[[fetched lastObject] closeDate] timeIntervalSince1970],fetched);
    
    // Override point for customization after application launch.
    UINavigationController *navigationController = (UINavigationController *)self.window.rootViewController;
    FBCDMasterViewController *controller = (FBCDMasterViewController *)navigationController.topViewController;
    controller.managedObjectContext = self.managedObjectContext;
    return YES;
}
							
- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Saves changes in the application's managed object context before the application terminates.
    [self saveContext];
}

- (void)saveContext
{
    NSError *error = nil;
    NSManagedObjectContext *managedObjectContext = self.managedObjectContext;
    if (managedObjectContext != nil) {
        if ([managedObjectContext hasChanges] && ![managedObjectContext save:&error]) {
             // Replace this implementation with code to handle the error appropriately.
             // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development. 
            NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
            abort();
        } 
    }
}

#pragma mark - Core Data stack

// Returns the managed object context for the application.
// If the context doesn't already exist, it is created and bound to the persistent store coordinator for the application.
- (NSManagedObjectContext *)managedObjectContext
{
    if (__managedObjectContext != nil) {
        return __managedObjectContext;
    }

    NSPersistentStoreCoordinator *coordinator;
    
#if USE_ENCRYPTED_STORE == 1
    coordinator = [EncryptedStore makeStore:[self managedObjectModel] passcode:@"SOME_PASSWORD"];
#elif USE_ENCRYPTED_STORE == 2
    
    [[NSFileManager defaultManager] createDirectoryAtURL:[[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject] withIntermediateDirectories:NO attributes:nil error:nil];
    
    NSURL *databaseURL = [[[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject] URLByAppendingPathComponent:[NSString stringWithFormat:@"FailedBankCD.sqlite"]];
    
    int cache = 2345;
    EncryptedStoreOptions options;
    options.passphrase = "SOME_PASSWORD";
    options.database_location = (char*)[[databaseURL description] UTF8String];
    options.cache_size = &cache;
    
    coordinator = [EncryptedStore makeStoreWithStructOptions:&options managedObjectModel:[self managedObjectModel]];

#elif USE_ENCRYPTED_STORE == 3
    
    [[NSFileManager defaultManager] createDirectoryAtURL:[[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject] withIntermediateDirectories:NO attributes:nil error:nil];
    
    NSURL *databaseURL = [[[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject] URLByAppendingPathComponent:[NSString stringWithFormat:@"FailedBankCD.sqlite"]];
    
    coordinator = [EncryptedStore makeStoreWithOptions:@{
                    EncryptedStorePassphraseKey : @"SOME_PASSWORD",
                    EncryptedStoreDatabaseLocation : [databaseURL description],
                    EncryptedStoreCacheSize : @(2345)}
                                    managedObjectModel:[self managedObjectModel]];
#else
    coordinator = [self persistentStoreCoordinator];
#endif
    

    if (coordinator != nil) {
        __managedObjectContext = [[NSManagedObjectContext alloc] init];
        [__managedObjectContext setPersistentStoreCoordinator:coordinator];
    }
    return __managedObjectContext;
}

// Returns the managed object model for the application.
// If the model doesn't already exist, it is created from the application's model.
- (NSManagedObjectModel *)managedObjectModel
{
    if (__managedObjectModel != nil) {
        return __managedObjectModel;
    }
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"FailedBankCD" withExtension:@"momd"];
    __managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return __managedObjectModel;
}

// Returns the persistent store coordinator for the application.
// If the coordinator doesn't already exist, it is created and the application's store added to it.
- (NSPersistentStoreCoordinator *)persistentStoreCoordinator
{
    if (__persistentStoreCoordinator != nil) {
        return __persistentStoreCoordinator;
    }
    
    NSURL *storeURL = [[self applicationDocumentsDirectory] URLByAppendingPathComponent:@"FailedBankCD.sqlite"];
    
    NSError *error = nil;
    __persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self managedObjectModel]];
    if (![__persistentStoreCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:&error]) {
        /*
         Replace this implementation with code to handle the error appropriately.
         
         abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development. 
         
         Typical reasons for an error here include:
         * The persistent store is not accessible;
         * The schema for the persistent store is incompatible with current managed object model.
         Check the error message to determine what the actual problem was.
         
         
         If the persistent store is not accessible, there is typically something wrong with the file path. Often, a file URL is pointing into the application's resources directory instead of a writeable directory.
         
         If you encounter schema incompatibility errors during development, you can reduce their frequency by:
         * Simply deleting the existing store:
         [[NSFileManager defaultManager] removeItemAtURL:storeURL error:nil]
         
         * Performing automatic lightweight migration by passing the following dictionary as the options parameter: 
         [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], NSMigratePersistentStoresAutomaticallyOption, [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption, nil];
         
         Lightweight migration will only work for a limited set of schema changes; consult "Core Data Model Versioning and Data Migration Programming Guide" for details.
         
         */
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    }    
    
    return __persistentStoreCoordinator;
}

#pragma mark - Application's Documents directory

// Returns the URL to the application's Documents directory.
- (NSURL *)applicationDocumentsDirectory
{
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

@end
