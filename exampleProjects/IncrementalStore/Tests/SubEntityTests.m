//
//  SubEntityTests.m
//  Incremental Store
//
//  Created by Richard Hodgkins on 23/09/2014.
//  Copyright (c) 2014 Caleb Davenport. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "EncryptedStore.h"

/*
 
 Flip between 0 and 1 to use the system SQLite store and custom incremental
 store subclass respectively.
 
 */
#define USE_ENCRYPTED_STORE 1

@interface SubEntityTests : XCTestCase

@end

@implementation SubEntityTests {
    __strong NSPersistentStoreCoordinator *coordinator;
    __strong NSManagedObjectContext *context;
}

+(NSURL *)databaseURL {
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSError *error = nil;
    NSURL *applicationDocumentsDirectory = [fileManager URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];
    
    NSAssert(applicationDocumentsDirectory, @"Unable to get the Documents directory: %@", error);
    
    NSString *name = [NSString stringWithFormat:@"database-%@", [NSStringFromClass([self class]) lowercaseString]];
#if USE_ENCRYPTED_STORE
    name = [name stringByAppendingString:@"-encrypted"];
#endif
    name = [name stringByAppendingString:@".sqlite"];
    
    return [applicationDocumentsDirectory URLByAppendingPathComponent:name];
}

+ (void)deleteDatabase {
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager removeItemAtURL:[self databaseURL] error:nil];
}

-(void)createCoordinator
{
    NSURL *URL;
    
    NSURL *modelURL = [[NSBundle bundleForClass:[EncryptedStore class]] URLForResource:@"SubEntitiesModel" withExtension:@"momd"];
    // get the model
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    
    // get the coordinator
    coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    
    // add store
    NSDictionary *options = @{
                              EncryptedStorePassphraseKey : @"DB_KEY_HERE"
                              };
    URL = [[self class] databaseURL];
    NSLog(@"Working with database at URL: %@", URL);
    NSError *error = nil;
    
    NSString *storeType = nil;
#if USE_ENCRYPTED_STORE
    storeType = EncryptedStoreType;
#else
    storeType = NSSQLiteStoreType;
#endif
    
    NSPersistentStore *store = [coordinator
                                addPersistentStoreWithType:storeType
                                configuration:nil
                                URL:URL
                                options:options
                                error:&error];
    
    XCTAssertNotNil(store, @"Unable to add persistent store: %@", error);
    
    // load context
    context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSConfinementConcurrencyType];
    [context setPersistentStoreCoordinator:coordinator];
    XCTAssertNotNil(context, @"Unable to create context.\n%@", error);
    
    // log
    NSLog(@"Working with database at %@", [URL path]);
}

-(void)resetCoordinator
{
    if (coordinator) {
        NSError *error;
        XCTAssertTrue([coordinator removePersistentStore:[coordinator persistentStoreForURL:[[self class] databaseURL]] error:&error], @"Could not remove persistent store: %@", error);
        coordinator = nil;
    }
    context = nil;
}

/// Creates the CD stack and all the objects returning the root object
-(void)createObjectGraph
{
    [self createCoordinator];
    
    // Jobs
    NSManagedObject *fullJob = [NSEntityDescription insertNewObjectForEntityForName:@"FullJob" inManagedObjectContext:context];
    [fullJob setValue:@"A-FullJob" forKey:@"name"];
    [fullJob setValue:@(INT64_MAX) forKey:@"longNumber"];
    NSManagedObject *lightweightJob = [NSEntityDescription insertNewObjectForEntityForName:@"LightweightJob" inManagedObjectContext:context];
    [lightweightJob setValue:@"B-LightweightJob" forKey:@"name"];
    
    // Update
    NSManagedObject *update = [NSEntityDescription insertNewObjectForEntityForName:@"JobStatusUpdate" inManagedObjectContext:context];
    [update setValue:@"update-JobStatusUpdate" forKey:@"name"];
    
    // Save
    NSError *error = nil;
    BOOL save = [context save:&error];
    XCTAssertTrue(save, @"Unable to perform save.\n%@", error);
}

-(void)setUp
{
    [super setUp];
    [[self class] deleteDatabase];
    
    [self createObjectGraph];
}

-(void)tearDown
{
    [self resetCoordinator];
    [[self class] deleteDatabase];
    [super tearDown];
}

-(void)testFetchingObjectsFromCache
{
    [self checkObjects];
}

-(void)testFetchingObjectsFromDatabase
{
    // Make sure we're loading directly from DB
    [self resetCoordinator];
    [self createCoordinator];
    
    [self checkObjects];
}

-(void)checkObjects
{
    NSError *error;
    
    {
        // Jobs
        NSFetchRequest *jobsRequest = [NSFetchRequest fetchRequestWithEntityName:@"Job"];
        jobsRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]];
        
        NSArray *jobs = [context executeFetchRequest:jobsRequest error:&error];
        XCTAssertNotNil(jobs, @"Error fetching jobs: %@", error);
        XCTAssertNil(error, @"Error");
        
        XCTAssertEqual([jobs count], (NSUInteger)2, @"Incorrect number of jobs");
        NSManagedObject *fullJob = [jobs firstObject];
        XCTAssertNotNil(fullJob, @"No full job");
        XCTAssertEqualObjects([fullJob entity].name, @"FullJob", @"Wrong full job entity type");
        NSManagedObject *lightweightJob = [jobs lastObject];
        XCTAssertNotNil(lightweightJob, @"No lightweight job");
        XCTAssertEqualObjects([lightweightJob entity].name, @"LightweightJob", @"Wrong full job entity type");
        
        XCTAssertEqualObjects([fullJob valueForKey:@"name"], @"A-FullJob", @"name property not correct");
        XCTAssertEqualObjects([fullJob valueForKey:@"longNumber"], @((long long)INT64_MAX), @"longNumber property value not correct");
        XCTAssertEqual([[fullJob valueForKey:@"longNumber"] longLongValue], (long long)INT64_MAX, @"longNumber property primitive value not correct");
        
        XCTAssertEqualObjects([lightweightJob valueForKey:@"name"], @"B-LightweightJob", @"name property not correct");
    }

    error = nil;
    {
        // Statuses
        NSFetchRequest *statusesRequest = [NSFetchRequest fetchRequestWithEntityName:@"BaseStatusUpdate"];
        
        NSArray *statuses = [context executeFetchRequest:statusesRequest error:&error];
        XCTAssertNotNil(statuses, @"Error fetching statuses: %@", error);
        XCTAssertNil(error, @"Error");
        
        XCTAssertEqual([statuses count], (NSUInteger)1, @"Incorrect number of statuses");
        NSManagedObject *status = [statuses firstObject];
        XCTAssertNotNil(status, @"No status");
        XCTAssertEqualObjects([status entity].name, @"JobStatusUpdate", @"Wrong full job entity type");
        
        XCTAssertEqualObjects([status valueForKey:@"name"], @"update-JobStatusUpdate", @"name property not correct");
    }
}

@end
