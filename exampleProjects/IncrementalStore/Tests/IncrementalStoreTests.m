//
//  IncrementalStoreTests.m
//  Incremental Store Tests
//
// Copyright 2012 - 2014 The MITRE Corporation, All Rights Reserved.
//
#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "EncryptedStore.h"

/*
 
 Flip between 0 and 1 to use the system SQLite store and custom incremental
 store subclass respectively.
 
 */
#define USE_ENCRYPTED_STORE 1

@interface IncrementalStoreTests : XCTestCase

@end

@implementation IncrementalStoreTests {
    NSPersistentStoreCoordinator *coordinator;
    NSPersistentStore *store;
    NSManagedObjectContext *context;
    NSString *wildcard;
}

+ (void)initialize {
    if (self == [IncrementalStoreTests class]) {
        srand((int)time(NULL));
    }
}

+ (NSBundle *)bundle {
    return [NSBundle bundleForClass:[EncryptedStore class]];
}

+ (NSURL *)databaseURL {
    NSBundle *bundle = [IncrementalStoreTests bundle];
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
    [manager removeItemAtURL:[IncrementalStoreTests databaseURL] error:nil];
}

- (void)createTags:(NSUInteger)count {
    NSError *error;
    
    //insert and save tags
    for (NSUInteger i=0; i<count; i++) {
        id obj = [NSEntityDescription insertNewObjectForEntityForName:@"Tag" inManagedObjectContext:context];
        [obj setValue:[NSString stringWithFormat:@"%lu tagname",(unsigned long)i] forKey:@"name"];
    }
    error = nil;
    BOOL save = [context save:&error];
    XCTAssertTrue(save, @"Unable to perform save.\n%@",error);
    
    // test count
    error = nil;
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"Tag"];
    NSUInteger testCount = [context countForFetchRequest:request error:&error];
    XCTAssertNil(error, @"Could not execute fetch request.");
    XCTAssertEqual(testCount, count, @"The number of tags is wrong.");

}

- (void)createUsers:(NSUInteger)count {
    NSError *error;
    
    // insert users and save
    for (NSUInteger i = 0; i < count; i++) {
        id object = [NSEntityDescription insertNewObjectForEntityForName:@"User" inManagedObjectContext:context];
        [object setValue:[NSString stringWithFormat:@"%lu username",(unsigned long)i] forKey:@"name"];
    }
    error = nil;
    BOOL save = [context save:&error];
    XCTAssertTrue(save, @"Unable to perform save.\n%@", error);
    
    // test count
    error = nil;
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
    NSUInteger testCount = [context countForFetchRequest:request error:&error];
    XCTAssertNil(error, @"Could not execute fetch request.");
    XCTAssertEqual(testCount, count, @"The number of users is wrong.");
    
}

- (void)createUsers:(NSUInteger)count adminCount:(NSUInteger)adminCount {
    NSError *error;
    
    // insert users and save
    for (NSUInteger i = 0; i < count; i++) {
        id object = [NSEntityDescription insertNewObjectForEntityForName:@"User" inManagedObjectContext:context];
        [object setValue:[NSString stringWithFormat:@"%lu username",(unsigned long)i] forKey:@"name"];
    }
    // insert admin users and save
    for (NSUInteger i = 0; i < adminCount; i++) {
        id object = [NSEntityDescription insertNewObjectForEntityForName:@"User" inManagedObjectContext:context];
        [object setValue:[NSString stringWithFormat:@"%lu username",(unsigned long)i] forKey:@"name"];
        [object setValue:@(YES) forKeyPath:@"admin"];
    }
    error = nil;
    BOOL save = [context save:&error];
    XCTAssertTrue(save, @"Unable to perform save.\n%@", error);
    
    // test count
    error = nil;
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
    request.predicate = [NSPredicate predicateWithFormat:@"admin == NO || admin == nil"];
    NSUInteger testCount = [context countForFetchRequest:request error:&error];
    XCTAssertNil(error, @"Could not execute fetch request.");
    XCTAssertEqual(testCount, count, @"The number of users is wrong.");
    
    // test admin count
    error = nil;
    request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
    request.predicate = [NSPredicate predicateWithFormat:@"admin == YES"];
    testCount = [context countForFetchRequest:request error:&error];
    XCTAssertNil(error, @"Could not execute fetch request.");
    XCTAssertEqual(testCount, adminCount, @"The number of admin users is wrong.");
    
}

- (void)createPosts:(NSUInteger)count forUser:(NSManagedObject *)user {
    NSError *error;
    
    // insert posts and save
    for (NSUInteger i = 0; i < count; i++) {
        id object = [NSEntityDescription insertNewObjectForEntityForName:@"Post" inManagedObjectContext:context];
        [object setValue:@"adventures" forKey:@"title"];
        [object setValue:@"fundamental" forKey:@"body"];
        [object setValue:user forKey:@"user"];
        NSDate *date = [NSDate dateWithTimeIntervalSinceNow:3600 * i];
        [object setValue:date forKey:@"timestamp"];
    }
    error = nil;
    BOOL save = [context save:&error];
    XCTAssertTrue(save, @"Unable to perform save.\n%@", error);
    
    // test count
    error = nil;
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"Post"];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"user = %@", user];
    [request setPredicate:predicate];
    NSUInteger testCount = [context countForFetchRequest:request error:&error];
    XCTAssertNil(error, @"Could not execute fetch request.");
    XCTAssertEqual(testCount, count, @"The number of posts is wrong.");
    
}

- (NSDictionary *)createUsersWithTagsDictionary:(NSUInteger)count {
    
    // create users and tags
    NSMutableArray *users = [NSMutableArray array];
    NSMutableArray *tags = [NSMutableArray array];
    NSDictionary *retval = [NSDictionary dictionaryWithObjects:@[users,tags] forKeys:@[@"users",@"tags"]];
    
    for (NSUInteger i = 0; i < count; i++) {
        id user = [NSEntityDescription insertNewObjectForEntityForName:@"User" inManagedObjectContext:context];
        [user setValue:[NSString stringWithFormat:@"%lu username",(unsigned long)i] forKey:@"name"];
        [users addObject:user];
        
        id tag = [NSEntityDescription insertNewObjectForEntityForName:@"Tag" inManagedObjectContext:context];
        [tag setValue:[NSString stringWithFormat:@"%lu tagname", (unsigned long)i] forKey:@"name"];
        [tags addObject:tag];
    }
    
    // give every user every tag, and vice versa.
    for (NSUInteger i = 0; i < count; i++) {
        [[users objectAtIndex:i] setValue:[NSMutableSet setWithArray:tags] forKey:@"hasTags"];
        [[tags objectAtIndex:i] setValue:[NSMutableSet setWithArray:users] forKey:@"hasUsers"];
    }
    
    NSError *error = nil;
    BOOL save = [context save:&error];
    XCTAssertTrue(save, @"Error saving context.\n%@",error);
    
    return retval;
}

- (NSArray *)createUnsortedUserArray:(NSUInteger)count {
    NSMutableArray *users = [NSMutableArray array];
    char a = 'a';
    
    for (NSUInteger i = 0; i < count; i++) {
        id user = [NSEntityDescription insertNewObjectForEntityForName:@"User" inManagedObjectContext:context];
        if(arc4random_uniform(2) == 1) a = 'A';
        [user setValue:[NSString stringWithFormat:@"%cusername",(char)(arc4random_uniform(26) + a)] forKey:@"name"];
        [users addObject:user];
    }
    
    NSError *error = nil;
    BOOL save = [context save:&error];
    XCTAssertTrue(save, @"Error saving context.\n%@",error);
    
    // test count (is it necessary?)
    error = nil;
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
    NSUInteger testCount = [context countForFetchRequest:request error:&error];
    XCTAssertNil(error, @"Could not execute fetch request.");
    XCTAssertEqual(testCount, count, @"The number of users is wrong.");
    
}

- (void)setUp {
    [super setUp];
    [IncrementalStoreTests deleteDatabase];
    NSURL *URL;
    
    // get the model
    NSBundle *bundle = [IncrementalStoreTests bundle];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:[bundle URLForResource:@"Model" withExtension:@"momd"]];
    
    // get the coordinator
    coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    
    // add store
    NSDictionary *options = @{
        EncryptedStorePassphraseKey : @"DB_KEY_HERE",
        NSMigratePersistentStoresAutomaticallyOption : @YES,
        NSInferMappingModelAutomaticallyOption : @YES
    };
    URL = [IncrementalStoreTests databaseURL];
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

- (void)tearDown {
    if (store) { [coordinator removePersistentStore:store error:nil];store = nil; }
    [IncrementalStoreTests deleteDatabase];
    coordinator = nil;
    context = nil;
    [super tearDown];
}

- (void)test_thereShouldBeNoUsers {
    [self createUsers:0];
}

- (void)test_createOneUser {
    [self createUsers:1];
}

- (void)test_createSomeUsers {
    [self createUsers:10];
}

- (void)test_createMoreUsers {
    [self createUsers:1000];
}

- (void)test_thereShouldBeNoUsersOrAdminUsers {
    [self createUsers:0 adminCount:0];
}

- (void)test_createOneUserAndOneAdminUsers {
    [self createUsers:1 adminCount:1];
}

- (void)test_createSomeUsersAndSomeAdminUsers {
    [self createUsers:10 adminCount:10];
}

- (void)test_createMoreUsersAndMoreAdminUsers {
    [self createUsers:1000 adminCount:10];
}

- (void)test_createAndDeleteSomeUsers {
    NSUInteger count = 1000;
    NSUInteger limit = 10;
    [self createUsers:count];
    NSError *error;
    NSFetchRequest *request;
    
    // fetch some users
    error = nil;
    request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
    [request setFetchLimit:limit];
    NSArray *users = [context executeFetchRequest:request error:&error];
    XCTAssertNil(error, @"Unable to perform fetch request.");
    XCTAssertEqual([users count], limit, @"Invalid number of results.");
    
    // delete users
    [users enumerateObjectsUsingBlock:^(id user, NSUInteger index, BOOL *stop) {
        [context deleteObject:user];
    }];
    error = nil;
    BOOL save = [context save:&error];
    XCTAssertTrue(save, @"Unable to perform save.\n%@", error);
    
    // perform count
    error = nil;
    request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
    NSUInteger countTest = [context countForFetchRequest:request error:&error];
    XCTAssertEqual(countTest, count - limit, @"Invalid number of results.");
    
}

- (void)test_createAndEditUser {
    NSUInteger limit = 1;
    [self createUsers:limit];
    NSError *error = nil;
    NSFetchRequest *request;
    
    // fetch user
    error = nil;
    request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
    [request setFetchLimit:limit];
    NSArray *users = [context executeFetchRequest:request error:&error];
    XCTAssertNil(error, @"Unable to perform fetch request.");
    XCTAssertEqual([users count], limit, @"Invalid number of results.");
    NSManagedObject *user = [users lastObject];
    XCTAssertNotNil(user, @"No user found.");
    
    // edit and save
    for (NSUInteger i = 0; i < 10; i++) {
        [user setValue:[[NSProcessInfo processInfo] globallyUniqueString] forKey:@"name"];
        BOOL save = [context save:&error];
        XCTAssertTrue(save, @"Unable to perform save at index:%lu.\n%@", (unsigned long)i, error);
    }
    
}

- (void)test_createUserAndSetNilValue {
    NSUInteger limit = 1;
    [self createUsers:limit];
    NSError *error = nil;
    NSFetchRequest *request;
    BOOL save;
    
    // fetch user
    error = nil;
    request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
    [request setFetchLimit:limit];
    NSArray *users = [context executeFetchRequest:request error:&error];
    XCTAssertNil(error, @"Unable to perform fetch request.");
    XCTAssertEqual([users count], limit, @"Invalid number of results.");
    NSManagedObject *user = [users lastObject];
    XCTAssertNotNil(user, @"No user found.");
    
    // edit and save
    error = nil;
    [user setValue:nil forKey:@"name"];
    save = [context save:&error];
    XCTAssertTrue(save, @"Unable to perform save.\n%@", error);
    
}

- (void)test_createOneUserWithPosts {
    id user = [NSEntityDescription insertNewObjectForEntityForName:@"User" inManagedObjectContext:context];
    [self createPosts:5 forUser:user];
}

- (void)test_createSeveralUsersWithPosts {
    NSUInteger numberOfusers = 5;
    NSUInteger numberOfPostsPerUser = 5;
    NSError *error;
    NSUInteger count;
    NSFetchRequest *request;
    
    // insert users and posts
    for (NSUInteger i = 0; i < numberOfusers; i++) {
        id user = [NSEntityDescription insertNewObjectForEntityForName:@"User" inManagedObjectContext:context];
        [self createPosts:numberOfPostsPerUser forUser:user];
    }
    
    // overall user count
    error = nil;
    request = [NSFetchRequest fetchRequestWithEntityName:@"User"];
    count = [context countForFetchRequest:request error:&error];
    XCTAssertNil(error, @"Unable to perform fetch request.");
    XCTAssertEqual(numberOfusers, count, @"Invalid number of results.");
    
    // overall post count
    error = nil;
    request = [NSFetchRequest fetchRequestWithEntityName:@"Post"];
    count = [context countForFetchRequest:request error:&error];
    XCTAssertNil(error, @"Unable to perform fetch request.");
    XCTAssertEqual(numberOfPostsPerUser * numberOfusers, count, @"Invalid number of results.");
    
}

- (void)test_createUsersWithPostsAndDeleteUser {
    NSUInteger numberOfusers = 5;
    NSUInteger numberOfPostsPerUser = 5;
    NSFetchRequest *request;
    NSError *error;
    BOOL save;
    NSUInteger count;
    
    // insert users and posts
    for (NSUInteger i = 0; i < numberOfusers; i++) {
        id user = [NSEntityDescription insertNewObjectForEntityForName:@"User" inManagedObjectContext:context];
        [self createPosts:numberOfPostsPerUser forUser:user];
    }
    
    // get a random user
    error = nil;
    request = [NSFetchRequest fetchRequestWithEntityName:@"User"];
    NSArray *matching = [context executeFetchRequest:request error:&error];
    XCTAssertNotNil(matching, @"Unable to perform fetch request.\n%@", error);
    XCTAssertEqual(numberOfusers, [matching count], @"Invalid number of users.");
    id user = [matching objectAtIndex:rand() % [matching count]];
    
    // delete user and save
    error = nil;
    [context deleteObject:user];
    save = [context save:&error];
    XCTAssertTrue(save, @"Unable to perform save.\n%@", error);
    
    // make sure we have one less user
    error = nil;
    request = [NSFetchRequest fetchRequestWithEntityName:@"User"];
    count = [context countForFetchRequest:request error:&error];
    XCTAssertNil(error, @"Unable to perform fetch request.");
    XCTAssertEqual(numberOfusers - 1, count, @"Invalid number of users.");
    
    // make sure we have one less user worth of posts
    error = nil;
    request = [NSFetchRequest fetchRequestWithEntityName:@"Post"];
    count = [context countForFetchRequest:request error:&error];
    XCTAssertNil(error, @"Unable to perform fetch request.");
    XCTAssertEqual((numberOfusers - 1) * numberOfPostsPerUser, count, @"Invalid number of posts.");
    
}

- (void)test_createUserWithPostsAndDeletePost {
    NSUInteger limit = 1;
    [self createUsers:limit];
    NSError *error;
    NSFetchRequest *request;
    BOOL save;
    
    // fetch user
    error = nil;
    request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
    [request setFetchLimit:limit];
    NSArray *users = [context executeFetchRequest:request error:&error];
    XCTAssertNil(error, @"Unable to perform fetch request.");
    XCTAssertEqual([users count], limit, @"Invalid number of results.");
    NSManagedObject *user = [users lastObject];
    
    XCTAssertNotNil(user, @"No object found.");
    
    // create posts
    [self createPosts:5 forUser:user];
    
    // fetch post
    error = nil;
    request = [[NSFetchRequest alloc] initWithEntityName:@"Post"];
    [request setFetchLimit:limit];
    [request setPredicate:[NSPredicate predicateWithFormat:@"user = %@", user]];
    NSArray *posts = [context executeFetchRequest:request error:&error];
    XCTAssertNil(error, @"Unable to perform fetch request.");
    XCTAssertEqual([posts count], limit, @"Invalid number of results.");
    NSManagedObject *post = [posts lastObject];
    XCTAssertNotNil(post, @"No object found.");
    
    // delete and save
    [context deleteObject:post];
    save = [context save:&error];
    XCTAssertTrue(save, @"Unable to perform save.\n%@", error);
    
}

- (void)test_createUsersAndSearch {
    NSUInteger limit = 5;
    [self createUsers:limit];
    NSError *__block error;
    NSFetchRequest *__block request;
    
    // fetch users
    NSArray *predicates = @[
        [NSPredicate predicateWithFormat:@"name like[cd] %@", @"*name"],
        [NSPredicate predicateWithFormat:@"name contains[cd] %@", @"name"],
        [NSPredicate predicateWithFormat:@"name endswith[cd] %@", @"name"]
    ];
    [predicates enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        error = nil;
        request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
        [request setPredicate:obj];
        NSArray *users = [context executeFetchRequest:request error:&error];
        XCTAssertNil(error, @"Unable to perform fetch request.");
        XCTAssertEqual([users count], limit, @"Invalid number of results.");
        NSManagedObject *user = [users lastObject];
        XCTAssertNotNil(user, @"No object found.");
    }];
}

- (void)test_createSeveralUsersWithPostsAndComplexSearch {
    NSUInteger limit = 1;
    [self createUsers:limit];
    NSError *error;
    NSFetchRequest *request;
    NSError *__block errorBlock;
    NSFetchRequest *__block requestBlock;
    
    // fetch user
    error = nil;
    request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
    [request setFetchLimit:limit];
    NSArray *users = [context executeFetchRequest:request error:&error];
    XCTAssertNil(error, @"Unable to perform fetch request.");
    XCTAssertEqual([users count], limit, @"Invalid number of results.");
    NSManagedObject *user = [users lastObject];
    XCTAssertNotNil(user, @"No object found.");
    
    // create posts
    [self createPosts:5 forUser:user];
    
    // fetch users
    NSArray *predicates = @[
    [NSPredicate predicateWithFormat:@"ANY posts.title like[cd] %@",@"*adventures"],
    [NSPredicate predicateWithFormat:@"ANY posts.title contains[cd] %@", @"adventure"],
    [NSPredicate predicateWithFormat:@"ANY posts.title endswith[cd] %@", @"ventures"]
    ];
    [predicates enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        errorBlock = nil;
        requestBlock = [[NSFetchRequest alloc] initWithEntityName:@"User"];
        [request setPredicate:obj];
        NSArray *users = [context executeFetchRequest:request error:&errorBlock];
        XCTAssertNil(error, @"Unable to perform fetch request.");
        XCTAssertEqual([users count], limit, @"Invalid number of results.");
        NSManagedObject *user = [users lastObject];
        XCTAssertNotNil(user, @"No object found.");
    }];
}

/*
 * Test many-to-many relations (Users to Tags)
 */

- (void)test_createUsersWithTags_inserts {
    NSUInteger count = 3;
    // this function creates users, tags, and relationships, and saves all at once
    [self createUsersWithTagsDictionary:count];
}

- (void)test_createUsersWithTags_updates {
    NSUInteger count = 3;
    [self createUsers:count];
    [self createTags:count];
    
    // at this point, users and tags are already saved
    
    NSError *error;
    NSFetchRequest *request;
    
    // fetch all users
    error = nil;
    request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
    NSArray *users = [context executeFetchRequest:request error:&error];
    
    // fetch all tags
    error = nil;
    request = [[NSFetchRequest alloc] initWithEntityName:@"Tag"];
    NSArray *tags = [context executeFetchRequest:request error:&error];
    
    // give every user every tag, and vice versa.
    for (NSUInteger i = 0; i < count; i++) {
        [[users objectAtIndex:i] setValue:[NSMutableSet setWithArray:tags] forKey:@"hasTags"];
        [[tags objectAtIndex:i] setValue:[NSMutableSet setWithArray:users] forKey:@"hasUsers"];
    }
    
    // save relations only (many-to-many update)
    BOOL success = [context save:&error];
    XCTAssertTrue(success, @"Unable to perform save.\n%@",error);
    
}

- (void)test_createUsersWithTags_deletes {
    NSError *error = nil;
    NSUInteger count = 5;
    NSDictionary *dictionary = [self createUsersWithTagsDictionary:count];
    
    NSArray *users = [dictionary valueForKey:@"users"];
    NSArray *tags = [dictionary valueForKey:@"tags"];
    
    for (NSUInteger i = 0; i < [users count]; i++) {
        [context deleteObject:[users objectAtIndex:i]];
        [context deleteObject:[tags objectAtIndex:i]];
    }
    
    BOOL save = [context save:&error];
    XCTAssertTrue(save, @"Unable to perform save.\n%@",error);
}

-(void)test_createUsersWithTags_selects {
    NSError __block *error = nil;
    NSUInteger count = 3;
    NSFetchRequest __block *request = nil;
    [self createUsersWithTagsDictionary:count];
    
    NSArray *predicates = @[
                            [NSPredicate predicateWithFormat:@"ANY hasTags.name like[cd] %@",@"*name"],
                            [NSPredicate predicateWithFormat:@"ANY hasTags.name contains[cd] %@", @"name"],
                            [NSPredicate predicateWithFormat:@"ANY hasTags.name endswith[cd] %@", @"name"]
                            ];
    [predicates enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        error = nil;
        request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
        [request setPredicate:obj];
        NSArray *users = [context executeFetchRequest:request error:&error];
        XCTAssertNil(error, @"Unable to perform fetch request.");
        XCTAssertEqual([users count], count, @"Invalid number of results.");
        NSManagedObject *user = [users lastObject];
        XCTAssertNotNil(user, @"No object found.");
    }];
}

/*
 * Test sort descriptors
 */

- (void)test_sortUserArrayUsingSortDescriptors {
    NSArray *users = [self createUnsortedUserArray:5];
    NSSortDescriptor *sortCaseSensitive;
    NSSortDescriptor *sortCaseInsensitive;
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
    NSError *error = nil;
    
    // test with case-sensitive (default) sort descriptor
    sortCaseSensitive = [[NSSortDescriptor alloc]
            initWithKey:@"name"
            ascending:YES];
    // sort array using descriptor in ECD
    [request setSortDescriptors:[NSArray arrayWithObject:sortCaseSensitive]];
    users = [context executeFetchRequest:request error:&error];
    
    // check if array was sorted by comparing against array sorted w/out ECD
    NSArray *sortedUsers = [users sortedArrayUsingDescriptors:[NSArray arrayWithObject:sortCaseSensitive]];
    XCTAssertTrue([users isEqualToArray:sortedUsers],
                 @"The array was not sorted properly (case-sensitive).");
    
    // test with case-INsensitive sort descriptor
    sortCaseInsensitive = [[NSSortDescriptor alloc]
                         initWithKey:@"name"
                         ascending:YES
                         selector:@selector(caseInsensitiveCompare:)];
    // sort array using descriptor in ECD
    [request setSortDescriptors:[NSArray arrayWithObject:sortCaseInsensitive]];
    users = [context executeFetchRequest:request error:&error];
    
    // check if array was sorted by comparing against array sorted w/out ECD
    sortedUsers = [users sortedArrayUsingDescriptors:[NSArray arrayWithObject:sortCaseInsensitive]];
    XCTAssertTrue([users isEqualToArray:sortedUsers],
                 @"The array was not sorted properly (case-sensitive).");
}

-(void)test_predicateForObjectRelation_singleDepth {
    NSError __block *error = nil;
    NSUInteger count = 3;
    NSFetchRequest __block *request = nil;
    [self createUsersWithTagsDictionary:count];
    
    request = [[NSFetchRequest alloc] initWithEntityName:@"Tag"];
    NSArray *tags = [context executeFetchRequest:request error:&error];
    
    [tags enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        error = nil;
        request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
        [request setPredicate:
         [NSPredicate predicateWithFormat:@"ANY hasTags = %@",obj]];
        NSArray *users = [context executeFetchRequest:request error:&error];
        XCTAssertNil(error, @"Unable to perform fetch request.");
        XCTAssertEqual([users count], count, @"Invalid number of results.");
        NSManagedObject *user = [users lastObject];
        XCTAssertNotNil(user, @"No object found.");
    }];
}

-(void)test_predicateForObjectRelation_multipleDepth {
    NSError __block *error = nil;
    NSUInteger count = 3;
    NSFetchRequest __block *request = nil;
    [self createUsersWithTagsDictionary:count];
    
    request = [[NSFetchRequest alloc] initWithEntityName:@"Tag"];
    NSArray *tags = [context executeFetchRequest:request error:&error];
    
    [tags enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        error = nil;
        request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
        [request setPredicate:
         [NSPredicate predicateWithFormat:@"ANY hasTags.hasUsers.hasTags = %@",obj]];
        NSArray *users = [context executeFetchRequest:request error:&error];
        XCTAssertNil(error, @"Unable to perform fetch request.");
        XCTAssertEqual([users count], count, @"Invalid number of results.");
        NSManagedObject *user = [users lastObject];
        XCTAssertNotNil(user, @"No object found.");
    }];
}

-(void)test_predicateEqualityComparison {
    NSError __block *error = nil;
    NSUInteger count = 3;
    NSFetchRequest __block *req = nil;
    NSArray __block *results = nil;
    
    NSManagedObject *user = [NSEntityDescription insertNewObjectForEntityForName:@"User" inManagedObjectContext:context];
    [user setValue:@"Maggie" forKey:@"name"];
    [user setValue:@(50) forKey:@"age"];
    [context save:&error];
    XCTAssertNil(error, @"Error saving database.");
    
    [self createPosts:count forUser:user];
    
    [@[[NSPredicate predicateWithFormat:@"name = %@",@"Maggie"],
       [NSPredicate predicateWithFormat:@"name == %@",@"Maggie"],
       [NSPredicate predicateWithFormat:@"age = %@",@(50)],
       [NSPredicate predicateWithFormat:@"age == %@",@(50)]]
     enumerateObjectsUsingBlock:^(NSPredicate *pred, NSUInteger idx, BOOL *stop) {
    
        req = [[NSFetchRequest alloc] initWithEntityName:@"User"];
        [req setPredicate:pred];
        results = [context executeFetchRequest:req error:&error];
        XCTAssertNil(error, @"Error in fetch request.");
        XCTAssertFalse([results count] == 0, @"No results found");
         NSManagedObject *u = [results firstObject];
        XCTAssertEqualObjects([u valueForKey:@"name"], @"Maggie", @"Fetch error.");
        XCTAssertEqualObjects([u valueForKey:@"age"], @(50), @"Fetch error.");
         
     }];
    
}

-(void)test_predicateEqualityComparisonUsingDates
{
    const NSUInteger count = 30;

    __block NSError *error = nil;
    NSManagedObject *user = [NSEntityDescription insertNewObjectForEntityForName:@"User" inManagedObjectContext:context];
    [context save:&error];
    XCTAssertNil(error, @"Error saving database.");

    NSDate *now = [NSDate date];
    
    [self createPosts:count forUser:user];
    
    [@{ [NSPredicate predicateWithFormat:@"timestamp < %@", now] : @(0),
        [NSPredicate predicateWithFormat:@"timestamp > %@", now] : @(count),
        [NSPredicate predicateWithFormat:@"timestamp BETWEEN %@", @[[now dateByAddingTimeInterval:100], [now dateByAddingTimeInterval:4000]]] : @(1),
        [NSPredicate predicateWithFormat:@"timestamp BETWEEN %@", @[now, [now dateByAddingTimeInterval:30 * 3601]]] : @(count),
        [NSPredicate predicateWithFormat:@"timestamp BETWEEN %@", @[[now dateByAddingTimeInterval:100], [now dateByAddingTimeInterval:10 * 3602]]] : @(10)
       } enumerateKeysAndObjectsUsingBlock:^(NSPredicate *predicate, NSNumber *expectedCount, BOOL *stop) {
        
           NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"Post"];
           req.predicate = predicate;
           
           NSUInteger count = [context countForFetchRequest:req error:&error];
        
           XCTAssertFalse(count == NSNotFound, @"Error with fetch: %@", error);
           XCTAssertEqual(count, [expectedCount unsignedIntegerValue], @"Incorrect fetch count");
    }];
}

@end
