//
//  ISDAppDelegate.m
//  Incremental Store Demo
//
//  Created by Caleb Davenport on 8/29/12.
//

#import <EncryptedStore.h>

#import "ISDAppDelegate.h"

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
        NSDictionary *options = @{
            EncryptedStorePassphraseKey : @"DB_KEY_HERE",
            NSMigratePersistentStoresAutomaticallyOption : @YES,
            NSInferMappingModelAutomaticallyOption : @YES
        };
        NSError *error = nil;
        NSPersistentStore *store = [coordinator
                                    addPersistentStoreWithType:EncryptedStoreType
                                    configuration:nil
                                    URL:databaseURL
                                    options:options
                                    error:&error];
        NSAssert(store, @"Unable to add persistent store\n%@", error);
        
    });
    return coordinator;
}

+ (NSManagedObjectContext *)managedObjectContext {
    static NSManagedObjectContext *context = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        [context setPersistentStoreCoordinator:[self persistentStoreCoordinator]];
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
            NSArray *array = [NSArray arrayWithObjects:@"Caleb", @"Jon", @"Andrew", @"Marshall", nil];
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
