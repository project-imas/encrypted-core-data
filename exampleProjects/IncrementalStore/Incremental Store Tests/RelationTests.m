//
//  RelationTests.m
//  Incremental Store
//
//  Created by Richard Hodgkins on 31/08/2014.
//  Copyright (c) 2014 Caleb Davenport. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>
#import <CoreData/CoreData.h>
#import "EncryptedStore.h"

#import "ISDModelCategories.h"
#import "ISDRoot.h"
#import "ISDChildA.h"
#import "ISDChildB.h"

/*
 
 Flip between 0 and 1 to use the system SQLite store and custom incremental
 store subclass respectively.
 
 */
#define USE_ENCRYPTED_STORE 1

@interface RelationTests : SenTestCase

@end

@implementation RelationTests {
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
    
    NSURL *modelURL = [[NSBundle bundleForClass:[EncryptedStore class]] URLForResource:@"ClassModel" withExtension:@"momd"];
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
    
    STAssertNotNil(store, @"Unable to add persistent store: %@", error);
    
    // load context
    context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSConfinementConcurrencyType];
    [context setPersistentStoreCoordinator:coordinator];
    STAssertNotNil(context, @"Unable to create context.\n%@", error);
    
    // log
    NSLog(@"Working with database at %@", [URL path]);
}

-(void)resetCoordinator
{
    if (coordinator) {
        NSError *error;
        STAssertTrue([coordinator removePersistentStore:[coordinator persistentStoreForURL:[[self class] databaseURL]] error:&error], @"Could not remove persistent store: %@", error);
        coordinator = nil;
    }
    context = nil;
}

/// Creates the CD stack and all the objects returning the root object
-(void)createObjectGraph
{
    [self createCoordinator];
    
    // insert root
    ISDRoot *root = [ISDRoot insertInManagedObjectContext:context];
    root.name = @"root";
    
    // Insert child A
    ISDChildA *childA = [ISDChildA insertInManagedObjectContext:context];
    childA.attributeA = @"String for child A - 1";
    childA.oneToManyInverse = root;
    
    childA = [ISDChildA insertInManagedObjectContext:context];
    childA.attributeA = @"String for child A - 2";
    childA.oneToManyInverse = root;
    
    // Insert child B
    ISDChildB *childB = [ISDChildB insertInManagedObjectContext:context];
    childB.attributeB = @"String for child B - 1";
    childB.oneToManyInverse = root;
    
    // Save
    NSError *error = nil;
    BOOL save = [context save:&error];
    STAssertTrue(save, @"Unable to perform save.\n%@", error);
    
    // Test from cache
    NSSet *relations = root.oneToMany;
    STAssertEquals([relations count], (NSUInteger)3, @"The number of relations is wrong.");
    
    // Here the counts are correct as the objects are exactly the same as we just inserted
    NSSet *childrenA = [relations filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"entity.name == %@", [ISDChildA entityName]]];
    NSSet *childrenB = [relations filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"entity.name == %@", [ISDChildB entityName]]];
    
    // This should be correct as this is how we entered the values in above
    STAssertEquals([childrenA count], (NSUInteger)2, @"Wrong ChildA count");
    STAssertEquals([childrenB count], (NSUInteger)1, @"Wrong ChildB count");
    // JUst for fun check the objects
    STAssertTrue([childrenA containsObject:childA], @"Inserted ChildA isn't in the set");
    STAssertTrue([childrenB anyObject] == childB, @"Inserted ChildB object isn't the same");
}

-(ISDRoot *)fetchRootObject
{
    NSError *error = nil;
    NSFetchRequest *request = [ISDRoot fetchRequest];
    request.predicate = [NSPredicate predicateWithFormat:@"name == %@", @"root"];
    NSArray *results = [context executeFetchRequest:request error:&error];
    STAssertNotNil(results, @"Could not execute fetch request.");
    STAssertEquals([results count], (NSUInteger)1, @"The number of root objects is wrong.");
    return [results firstObject];
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

-(void)testFetchingOneToManyFromCache
{
    [self checkOneToManyWithChildACount:2 childBCount:1];
}

-(void)testFetchingOneToManyFromDatabase
{
    // Make sure we're loading directly from DB
    [self resetCoordinator];
    [self createCoordinator];
    
    [self checkOneToManyWithChildACount:2 childBCount:1];
}

#pragma mark - Check methods

/// Checks that the root object has the correct number of ChildA and ChildB objects
-(void)checkOneToManyWithChildACount:(NSUInteger)childACount childBCount:(NSUInteger)childBCount
{
    ISDRoot *fetchedRoot = [self fetchRootObject];
    NSSet *relations = fetchedRoot.oneToMany;
    STAssertEquals([relations count], childACount + childBCount, @"The total number of oneToMany objects is wrong.");
    
    NSSet *childrenA = [relations filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"entity.name == %@", [ISDChildA entityName]]];
    NSSet *childrenB = [relations filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"entity.name == %@", [ISDChildB entityName]]];
    
    STAssertEquals([childrenA count], childACount, @"Wrong ChildA count");
    STAssertEquals([childrenB count], childBCount, @"Wrong ChildB count");
}

@end
