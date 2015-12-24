//
//  ISDMigrationTests.m
//  Incremental Store
//
//  Created by Daniel Broad on 22/12/2015.
//  Copyright © 2015 Caleb Davenport. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "EncryptedStore.h"

#define USE_ENCRYPTED_STORE 1

@interface ISDMigrationTests : XCTestCase

@end

@implementation ISDMigrationTests {
    NSPersistentStoreCoordinator *coordinator;
    NSPersistentStore *store;
    NSManagedObjectContext *context;
}

+ (void)initialize {
    if (self == [ISDMigrationTests class]) {
        srand((int)time(NULL));
    }
}

+ (NSBundle *)bundle {
    return [NSBundle bundleForClass:[EncryptedStore class]];
}

+ (NSURL *)databaseURL {
    NSBundle *bundle = [self bundle];
    NSString *identifier = [[bundle infoDictionary] objectForKey:@"CFBundleIdentifier"];
    NSString *path = NSTemporaryDirectory();
    path = [path stringByAppendingPathComponent:identifier];
    NSURL *URL = [NSURL fileURLWithPath:path];
    [[NSFileManager defaultManager] createDirectoryAtURL:URL withIntermediateDirectories:YES attributes:nil error:nil];
    URL = [URL URLByAppendingPathComponent:@"database-test.sqlite"];
    return URL;
}

+ (void)deleteDatabase {
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager removeItemAtURL:[self databaseURL] error:nil];
}

- (NSManagedObjectModel *)managedObjectModelForVersion:(NSString *)version
{
    NSURL *modelURL = [[NSBundle mainBundle] URLForResource:[NSString stringWithFormat:@"Migration.momd/%@",version] withExtension:@"mom"];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    return model;
}

-(void)createObjectGraph
{
    
    // Jobs
    NSManagedObject *job = [NSEntityDescription insertNewObjectForEntityForName:@"Task" inManagedObjectContext:context];
    [job setValue:@"A-Task" forKey:@"name"];
    
    // Update
    NSManagedObject *update = [NSEntityDescription insertNewObjectForEntityForName:@"TaskStatusUpdate" inManagedObjectContext:context];
    [update setValue:@"TaskStatusUpdate" forKey:@"name"];
    [update setValue:[NSDate date] forKey:@"timeStamp"];
    [update setValue:job forKey:@"task"];
    
    NSManagedObject *projectupdate = [NSEntityDescription insertNewObjectForEntityForName:@"TaskGroupStatusUpdate" inManagedObjectContext:context];
    [projectupdate setValue:[NSSet setWithObject:update] forKey:@"taskStatus"];
    [projectupdate setValue:@"TaskStatusUpdate" forKey:@"name"];
    [projectupdate setValue:[NSDate date] forKey:@"timeStamp"];
    
    // Save
    NSError *error = nil;
    BOOL save = [context save:&error];
    XCTAssertTrue(save, @"Unable to perform save.\n%@", error);
}

-(void)migrateStore {
    [coordinator removePersistentStore:store error:nil];
    [self setUpDBWithModel:@"New"];
}

- (void)setUpDBWithModel: (NSString*) modelName {
    // get the model
    NSManagedObjectModel *model = [self managedObjectModelForVersion:modelName];
    
    // get the coordinator
    coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    
    // add store
    NSDictionary *options = @{
                              EncryptedStorePassphraseKey : @"DB_KEY_HERE",
                              NSMigratePersistentStoresAutomaticallyOption : @YES,
                              NSInferMappingModelAutomaticallyOption : @YES,
                              EncryptedStoreCacheSize: @1000
                              };
    NSURL *URL = [self.class databaseURL];
    NSLog(@"Working with database at URL: %@", URL);
    NSError *error = nil;
    
    NSString *storeType = nil;
#if USE_ENCRYPTED_STORE
    storeType = EncryptedStoreType;
#else
    storeType = NSSQLiteStoreType;
#endif
    
    store = [coordinator
             addPersistentStoreWithType:storeType
             configuration:nil
             URL:URL
             options:options
             error:&error];
    
    XCTAssertNotNil(store, @"Unable to add persistent store.\n%@", error);
    
    // load context
    context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSConfinementConcurrencyType];
    [context setPersistentStoreCoordinator:coordinator];
    XCTAssertNotNil(context, @"Unable to create context.\n%@", error);
    
    // log
    NSLog(@"Working with database at %@", [URL path]);

}
- (void)setUp {
    [super setUp];

    [self.class deleteDatabase];
    
    [self setUpDBWithModel:@"Migration"];
    
    [self createObjectGraph];
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (NSManagedObject*)integrityCheck {
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"Task"];
    
    NSError *error;
    NSArray *tasks = [context executeFetchRequest:request error:&error];
    XCTAssertNil(error,@"Error fetching %@",error);
    XCTAssertEqual(tasks.count, 1,@"Did not find 1 job");
    
    NSManagedObject *task = [tasks firstObject];
    
    XCTAssertTrue([[task valueForKey:@"name"] isEqualToString:@"A-Task"],@"Task name check");
    
    NSSet *statusUpdates = [task valueForKey:@"statusUpdates"];
    
    XCTAssertNotNil(statusUpdates,@"Status updates relationship check");
    XCTAssertEqual(statusUpdates.count,1,@"Status updates relationship count");
    
    NSManagedObject *taskStatusUpdate = [statusUpdates anyObject];
    
    XCTAssertNotNil([taskStatusUpdate valueForKey:@"task"],@"status update must have a task");
    XCTAssertNotNil([taskStatusUpdate valueForKey:@"timeStamp"],@"status update must have a timeStamp");
    
    NSManagedObject *projectStatusUpdate = [taskStatusUpdate valueForKey:@"projectUpdate"];
    XCTAssertNotNil(projectStatusUpdate,@"status update must have a project");
    
    XCTAssertNotNil([projectStatusUpdate valueForKey:@"name"],@"status update must have a name");
    XCTAssertNotNil([projectStatusUpdate valueForKey:@"timeStamp"],@"status update must have a timeStamp");

    NSSet *projectStatusUpdates = [projectStatusUpdate valueForKey:@"taskStatus"];
    XCTAssertNotNil(projectStatusUpdates,@"Project Status updates relationship check");
    XCTAssertEqual(projectStatusUpdates.count,1,@"Project Status updates relationship count");

    return projectStatusUpdate;
    
}

- (void)testUnmigratedStore {
    [self integrityCheck];
}

- (void)testMigrationPerformance {
    // This is an example of a performance test case.
    [self measureBlock:^{
        [self migrateStore];
    }];
}

- (void) testMigratedStore {
    [self migrateStore];
    NSManagedObject *projectStatusUpdate = [self integrityCheck];
    
    NSManagedObject *taskStatus = [[projectStatusUpdate valueForKey:@"taskStatus"] anyObject];
    
    [taskStatus setValue:@"A-Task-Update-Text" forKey:@"updateText"]; // will fail if not correctly migrated
    
    NSManagedObject *task = [taskStatus valueForKey:@"task"];
    
    [task setValue:@1 forKey:@"newAttribute"]; // will fail if not correctly migrated
}


@end
