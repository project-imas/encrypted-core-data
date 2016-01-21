//
//  RelationTests.m
//  Incremental Store
//
//  Created by Richard Hodgkins on 31/08/2014.
//  Copyright (c) 2014 Caleb Davenport. All rights reserved.
//

#import <XCTest/XCTest.h>
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

@interface RelationTests : XCTestCase

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
    
    // insert root
    ISDRoot *root = [ISDRoot insertInManagedObjectContext:context];
    root.name = @"root";
    
    /////////////////
    // One-to-many //
    /////////////////
    
    // Insert child A
    ISDChildA *childAOneToMany = [ISDChildA insertInManagedObjectContext:context];
    childAOneToMany.attributeA = @"String for child A - 1";
    childAOneToMany.oneToManyInverse = root;
    
    childAOneToMany = [ISDChildA insertInManagedObjectContext:context];
    childAOneToMany.attributeA = @"String for child A - 2";
    childAOneToMany.oneToManyInverse = root;
    
    // Insert child B
    ISDChildB *childBOneToMany = [ISDChildB insertInManagedObjectContext:context];
    childBOneToMany.attributeB = @"String for child B - 1";
    childBOneToMany.oneToManyInverse = root;
    
    ////////////////
    // One-to-one //
    ////////////////
    
    // Insert child A
    ISDChildA *childAOneToOne = [ISDChildA insertInManagedObjectContext:context];
    childAOneToOne.attributeA = @"String for child A - 3";
    childAOneToOne.oneToOneInverse = root;
    
    //////////////////
    // Many-to-Many //
    //////////////////
    ISDRoot *manyRoot = [ISDRoot insertInManagedObjectContext:context];
    manyRoot.name = @"manyRoot";
    
    // Insert child A
    ISDChildA *childAManyToMany = [ISDChildA insertInManagedObjectContext:context];
    childAManyToMany.attributeA = @"String for child A - 4";
    [childAManyToMany addManyToManyInverseObject:root];
    [childAManyToMany addManyToManyInverseObject:manyRoot];
    
    childAManyToMany = [ISDChildA insertInManagedObjectContext:context];
    childAManyToMany.attributeA = @"String for child A - 5";
    [childAManyToMany addManyToManyInverseObject:root];
    [childAManyToMany addManyToManyInverseObject:manyRoot];
    
    // Insert child B
    ISDChildB *childBManyToMany = [ISDChildB insertInManagedObjectContext:context];
    childBManyToMany.attributeB = @"String for child B - 2";
    [childBManyToMany addManyToManyInverseObject:root];
    [childBManyToMany addManyToManyInverseObject:manyRoot];
    
    childBManyToMany = [ISDChildB insertInManagedObjectContext:context];
    childBManyToMany.attributeB = @"String for child B - 3";
    [childBManyToMany addManyToManyInverseObject:root];
    [childBManyToMany addManyToManyInverseObject:manyRoot];
    
    childBManyToMany = [ISDChildB insertInManagedObjectContext:context];
    childBManyToMany.attributeB = @"String for child B - 4";
    [childBManyToMany addManyToManyInverseObject:root];
    [childBManyToMany addManyToManyInverseObject:manyRoot];

    //////////////////////////
    // Multiple One-to-many //
    //////////////////////////

    // Insert child A
    ISDChildA *childAMultipleOneToMany = [ISDChildA insertInManagedObjectContext:context];
    childAMultipleOneToMany.attributeA = @"String for child A - 6";
    childAMultipleOneToMany.multipleOneToMany = root;

    // Insert child B
    ISDChildB *childBMultipleOneToMany = [ISDChildB insertInManagedObjectContext:context];
    childBMultipleOneToMany.attributeB = @"String for child B - 5";
    childBMultipleOneToMany.multipleOneToMany = root;

    childBMultipleOneToMany = [ISDChildB insertInManagedObjectContext:context];
    childBMultipleOneToMany.attributeB = @"String for child B - 6";
    childBMultipleOneToMany.multipleOneToMany = root;
    
    // Save
    NSError *error = nil;
    BOOL save = [context save:&error];
    XCTAssertTrue(save, @"Unable to perform save.\n%@", error);
    
    // Test one-to-many from cache
    {
        NSSet *oneToManyRelations = root.oneToMany;
        XCTAssertEqual([oneToManyRelations count], (NSUInteger)3, @"The number of one-to-many relations is wrong.");
        
        // Here the counts are correct as the objects are exactly the same as we just inserted
        NSSet *childrenA = [oneToManyRelations filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"entity.name == %@", [ISDChildA entityName]]];
        NSSet *childrenB = [oneToManyRelations filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"entity.name == %@", [ISDChildB entityName]]];
        
        // This should be correct as this is how we entered the values in above
        XCTAssertEqual([childrenA count], (NSUInteger)2, @"Wrong ChildA count");
        XCTAssertEqual([childrenB count], (NSUInteger)1, @"Wrong ChildB count");
        // Just for fun check the objects
        XCTAssertTrue([childrenA containsObject:childAOneToMany], @"Inserted ChildA isn't in the set");
        XCTAssertTrue([childrenB anyObject] == childBOneToMany, @"Inserted ChildB object isn't the same");
    }
    
    // Test one-to-one from cache
    {
        XCTAssertTrue(root.oneToOne == childAOneToOne, @"Inserted one-to-one ChildA isn't the same");
    }
    
    // Test many-to-many from cache
    {
        NSSet *manyToManyRelations = root.manyToMany;
        XCTAssertEqual([manyToManyRelations count], (NSUInteger)5, @"The number of many-to-many relations is wrong.");
        
        // Here the counts are correct as the objects are exactly the same as we just inserted
        NSSet *childrenA = [manyToManyRelations filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"entity.name == %@", [ISDChildA entityName]]];
        NSSet *childrenB = [manyToManyRelations filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"entity.name == %@", [ISDChildB entityName]]];
        
        // This should be correct as this is how we entered the values in above
        XCTAssertEqual([childrenA count], (NSUInteger)2, @"Wrong ChildA count");
        XCTAssertEqual([childrenB count], (NSUInteger)3, @"Wrong ChildB count");
        // Just for fun check the objects
        XCTAssertTrue([childrenA containsObject:childAManyToMany], @"Inserted ChildA isn't in the many-to-many set");
        XCTAssertTrue([childrenB containsObject:childBManyToMany], @"Inserted ChildB isn't in the many-to-many set");
    }

    // Test multiple one-to-many from cache
    {
        NSSet *oneToManyChildA = root.multipleOneToManyChildA;
        NSSet *oneToManyChildB = root.multipleOneToManyChildB;
        XCTAssertEqual([oneToManyChildA count], (NSUInteger)1, @"The number of multiple one-to-many child A relations is wrong.");
        XCTAssertEqual([oneToManyChildB count], (NSUInteger)2, @"The number of multiple one-to-many child B relations is wrong.");

        // Check the objects
        XCTAssertTrue([oneToManyChildA anyObject] == childAMultipleOneToMany, @"Inserted ChildA object isn't the same");
        XCTAssertTrue([oneToManyChildB containsObject:childBMultipleOneToMany], @"Inserted ChildB isn't in the set");
    }
}

-(ISDRoot *)fetchRootObject
{
    NSError *error = nil;
    NSFetchRequest *request = [ISDRoot fetchRequest];
    request.predicate = [NSPredicate predicateWithFormat:@"name == %@", @"root"];
    NSArray *results = [context executeFetchRequest:request error:&error];
    XCTAssertNotNil(results, @"Could not execute fetch request.");
    XCTAssertEqual([results count], (NSUInteger)1, @"The number of root objects is wrong.");
    ISDRoot *root = [results firstObject];
    XCTAssertEqualObjects(root.name, @"root", @"The name of the root object is wrong.");
    return root;
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

-(void)testFetchingOneToOneFromCache
{
    [self checkOneToOneWithChildA:YES childB:NO];
}

-(void)testFetchingOneToOneFromDatabase
{
    // Make sure we're loading directly from DB
    [self resetCoordinator];
    [self createCoordinator];
    
    [self checkOneToOneWithChildA:YES childB:NO];
}

-(void)testFetchingOneToOneNilFromCache
{
    [self checkOneToOneNil];
}

-(void)testFetchingOneToOneNilFromDatabase
{
    // Make sure we're loading directly from DB
    [self resetCoordinator];
    [self createCoordinator];
    
    [self checkOneToOneNil];
}

-(void)testFetchingManyToManyFromCache
{
    [self checkManyToManyWithChildACount:2 childBCount:3];
}

-(void)testFetchingManyToManyFromDatabase
{
    // Make sure we're loading directly from DB
    [self resetCoordinator];
    [self createCoordinator];
    
    [self checkManyToManyWithChildACount:2 childBCount:3];
}


/**
 Multiple one-to-many is designed to test the case where one entity (Root) has two one-to-many
 relationships that are queried using a shared attribute.
 */
-(void)testFetchingMultipleOneToManyFromDatabase
{
    // Make sure we're loading directly from DB
    [self resetCoordinator];
    [self createCoordinator];

    [self checkMultipleOneToManyWithChildACount:1 childBCount:2];
}

#pragma mark - Check methods

/// Checks that the root object has the correct number of one-to-many relational ChildA and ChildB objects
-(void)checkOneToManyWithChildACount:(NSUInteger)childACount childBCount:(NSUInteger)childBCount
{
    ISDRoot *fetchedRoot = [self fetchRootObject];
    NSSet *relations = fetchedRoot.oneToMany;
    XCTAssertEqual([relations count], childACount + childBCount, @"The total number of oneToMany objects is wrong.");
    
    NSSet *childrenA = [relations filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"entity.name == %@", [ISDChildA entityName]]];
    NSSet *childrenB = [relations filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"entity.name == %@", [ISDChildB entityName]]];
    
    XCTAssertEqual([childrenA count], childACount, @"Wrong ChildA count");
    XCTAssertEqual([childrenB count], childBCount, @"Wrong ChildB count");
}

/// Checks that the root object has the correct one-to-one relational ChildA/ChildB
-(void)checkOneToOneWithChildA:(BOOL)childA childB:(BOOL)childB
{
    ISDRoot *fetchedRoot = [self fetchRootObject];
    ISDParent *child = fetchedRoot.oneToOne;
    XCTAssertNotNil(child, @"Nil one-to-one relation");
    
    if (childA) {
        XCTAssertEqualObjects([child.entity name], [ISDChildA entityName], @"One-to-one child is of wrong entity");
        if ([child respondsToSelector:@selector(attributeA)]) {
            XCTAssertTrue([((ISDChildA *) child).attributeA hasPrefix:@"String for child A"], @"One-to-one childs attribute does not start with the correct prefix, got: %@, expecting prefix: %@", ((ISDChildA *) child).attributeA, @"String for child A");
        } else {
            XCTFail(@"One-to-one child does not have the correct attribute: %@", child);
        }
        XCTAssertTrue([child isKindOfClass:[ISDChildA class]], @"One-to-one child is of wrong class, got: %@, expecting: %@", NSStringFromClass([child class]), NSStringFromClass([ISDChildA class]));
        XCTAssertFalse([child isKindOfClass:[ISDChildB class]], @"One-to-one child is of wrong class, got: %@, expecting: %@", NSStringFromClass([child class]), NSStringFromClass([ISDChildA class]));
    }
    if (childB) {
        XCTAssertEqualObjects([child.entity name], [ISDChildB entityName], @"One-to-one child is of wrong entity");
        if ([child respondsToSelector:@selector(attributeB)]) {
            XCTAssertTrue([((ISDChildB *) child).attributeB hasPrefix:@"String for child B"], @"One-to-one childs attribute does not start with the correct prefix, got: %@, expecting prefix: %@", ((ISDChildB *) child).attributeB, @"String for child B");
        } else {
            XCTFail(@"One-to-one child does not have the correct attribute: %@", child);
        }
        XCTAssertTrue([child isKindOfClass:[ISDChildB class]], @"One-to-one child is of wrong class, got: %@, expecting: %@", NSStringFromClass([child class]), NSStringFromClass([ISDChildB class]));
        XCTAssertFalse([child isKindOfClass:[ISDChildA class]], @"One-to-one child is of wrong class, got: %@, expecting: %@", NSStringFromClass([child class]), NSStringFromClass([ISDChildB class]));
    }
}
  
-(void)checkOneToOneNil
{
    ISDRoot *fetchedRoot = [self fetchRootObject];
    XCTAssert(fetchedRoot.oneToOneNil == nil, @"We didn't set it, should be nil");
}

/// Checks that the root object has the correct number of many-to-many relational ChildA and ChildB objects
-(void)checkManyToManyWithChildACount:(NSUInteger)childACount childBCount:(NSUInteger)childBCount
{
    ISDRoot *fetchedRoot = [self fetchRootObject];
    NSSet *relations = fetchedRoot.manyToMany;
    XCTAssertEqual([relations count], childACount + childBCount, @"The total number of oneToMany objects is wrong.");
    
    NSSet *childrenA = [relations filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"entity.name == %@", [ISDChildA entityName]]];
    NSSet *childrenB = [relations filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"entity.name == %@", [ISDChildB entityName]]];
    
    XCTAssertEqual([childrenA count], childACount, @"Wrong ChildA count");
    XCTAssertEqual([childrenB count], childBCount, @"Wrong ChildB count");
}

/// Checks that the root object has the correct number of multiple one-to-many relational ChildA and ChildB objects
-(void)checkMultipleOneToManyWithChildACount:(NSUInteger)childACount childBCount:(NSUInteger)childBCount
{
    ISDRoot *fetchedRoot = [self fetchRootObject];
    NSSet *multipleChildA = fetchedRoot.multipleOneToManyChildA;
    NSSet *multipleChildB = fetchedRoot.multipleOneToManyChildB;

    XCTAssertEqual([multipleChildA count], childACount, @"Wrong ChildA count");
    XCTAssertEqual([multipleChildB count], childBCount, @"Wrong ChildB count");
}

@end
