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
        [object setValue:[NSNumber numberWithInteger:i] forKey:@"age"];
        id nickname = [NSEntityDescription insertNewObjectForEntityForName:@"Nickname" inManagedObjectContext:context];
        [nickname setValue:object forKey:@"user"];
        [nickname setValue:[NSString stringWithFormat:@"%lu nickname",(unsigned long)i] forKey:@"name"];
    }
    
    error = nil;
    BOOL save = [context save:&error];
    XCTAssertTrue(save, @"Unable to perform save.\n%@", error);
    
    [context reset];
    
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
    
    [context reset];
    
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
    
    [context reset];
    
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
    [context reset];
    
    return retval;
}

- (NSArray *)createUnsortedUserArray:(NSUInteger)count {
    NSMutableArray *users = [NSMutableArray array];
    char a = 'a';
    
    for (NSUInteger i = 0; i < count; i++) {
        id user = [NSEntityDescription insertNewObjectForEntityForName:@"User" inManagedObjectContext:context];
        if(arc4random_uniform(2) == 1) a = 'A';
        NSString *name = [NSString stringWithFormat:@"%cusername",(char)(arc4random_uniform(26) + a)];
        [user setValue:name forKey:@"name"];
        [user setValue:@0 forKey:@"age"];
        [user setValue:@NO forKey:@"admin"];
        [users addObject:user];
    }
    
    NSError *error = nil;
    BOOL save = [context save:&error];
    XCTAssertTrue(save, @"Error saving context.\n%@",error);
    [context reset];
    
    // test count (is it necessary?)
    error = nil;
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
    NSUInteger testCount = [context countForFetchRequest:request error:&error];
    XCTAssertNil(error, @"Could not execute fetch request.");
    XCTAssertEqual(testCount, count, @"The number of users is wrong.");
    
    return users;
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

- (void)test_createUserNicknames {
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
    NSSet *nickNames = [user valueForKey:@"nicknames"];
    XCTAssertEqual(nickNames.count, 1,@"Nicknames not found!");
    
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

    [context reset];
    
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

-(void)test_predicateForObjectRelation_multipleAttributes {
    NSError __block *error = nil;
    NSUInteger count = 3;
    NSFetchRequest __block *request = nil;
    [self createUsersWithTagsDictionary:count];
    
    request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
    NSArray *users = [context executeFetchRequest:request error:&error];
    
    [users enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        error = nil;
        request = [[NSFetchRequest alloc] initWithEntityName:@"Tag"];
        NSString *name = [obj valueForKey:@"name"];
        NSNumber *age = [obj valueForKey:@"age"];
        [request setPredicate:
         [NSPredicate predicateWithFormat:@"ANY hasUsers.name = %@ AND hasUsers.age = %@", name, age]];
        NSArray *tags = [context executeFetchRequest:request error:&error];
        XCTAssertNil(error, @"Unable to perform fetch request.");
        XCTAssertEqual([tags count], count, @"Invalid number of results.");
        NSManagedObject *tag = [tags lastObject];
        XCTAssertNotNil(tag, @"No object found.");
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

-(void)test_predicateForSelfInComparisonWithUnpersistedObjects {
    NSArray *users = @[
        [NSEntityDescription insertNewObjectForEntityForName:@"User" inManagedObjectContext:context],
        [NSEntityDescription insertNewObjectForEntityForName:@"User" inManagedObjectContext:context]
    ];

    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"User"];
    [request setPredicate:[NSPredicate predicateWithFormat:@"SELF IN %@", users]];

    NSError *error;
    NSArray<NSManagedObject *> *results = [context executeFetchRequest:request error:&error];
    XCTAssertNotNil(results);
    XCTAssertEqual([results count], 2);
}

-(void)test_batchFetchWithNestedContextsAndUnpersistedObjects {
    NSManagedObjectContext *parentContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    [parentContext setPersistentStoreCoordinator: coordinator];

    NSManagedObjectContext *childContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    [childContext setParentContext:parentContext];
    NSManagedObject *user = [NSEntityDescription insertNewObjectForEntityForName:@"User" inManagedObjectContext:childContext];

    NSError *error;
    BOOL saved = [childContext save:&error];
    XCTAssertTrue(saved, @"Failed to save child context: %@", error);

    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"User"];
    [request setFetchBatchSize:20];

    NSArray<NSManagedObject *> *results = [childContext executeFetchRequest:request error:&error];
    XCTAssertNotNil(results, @"Failed to fetch saved user from parent context: %@", error);
    XCTAssertEqual([results count], 1);
    XCTAssertEqualObjects([results[0] objectID], [user objectID]);
}

-(void)test_sumExpression {
    
    [self createUsers:10];
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    
    NSEntityDescription *entityDescription = [NSEntityDescription
                                              entityForName:@"User" inManagedObjectContext:context];
    
    [fetchRequest setEntity:entityDescription];
    [fetchRequest setResultType:NSDictionaryResultType];
    
    NSExpression *expression = [NSExpression expressionForKeyPath:@"age"];
    NSExpression *sumExpression = [NSExpression expressionForFunction:@"sum:"
                                                            arguments:[NSArray arrayWithObject:expression]];
    NSExpressionDescription *sumExpressionDescription = [[NSExpressionDescription alloc] init];
    [sumExpressionDescription setName:@"total age"];
    [sumExpressionDescription setExpression:sumExpression];
    [sumExpressionDescription setExpressionResultType:NSInteger64AttributeType];
    
    [fetchRequest setPropertiesToFetch:@[sumExpressionDescription]];
    
    NSError *error = nil;
    NSArray *age = [context executeFetchRequest:fetchRequest error:&error];
    XCTAssertNil(error, @"Error running query %@",error);
    XCTAssertNotNil(age, @"No Results");
    XCTAssertEqual(age.count, 1, @"Incorrect fetch count");
    
    NSDictionary *results = [age firstObject];
    
    NSInteger expectedAge = 45;
    
    NSNumber *totalAge = [results objectForKey:@"total age"];
    XCTAssertEqual(totalAge.integerValue, expectedAge, @"Incorrect total %ld expected %ld",(long)totalAge.integerValue,(long)expectedAge);
}

-(void)test_predicateWithBoolValue
{
    const NSUInteger usersCount = 30;
    
    [self createUsers:usersCount];
    
    NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"User"];
    NSError *error;
    
    // Test true predicate
    req.predicate = [NSPredicate predicateWithValue:YES];
    NSUInteger count = [context countForFetchRequest:req error:&error];
    XCTAssertNil(error, @"Unable to perform fetch request.");
    XCTAssertTrue(count == usersCount, @"Incorrect fetch count.");
    
    // Test false predicate
    req.predicate = [NSPredicate predicateWithValue:NO];
    count = [context countForFetchRequest:req error:&error];
    XCTAssertNil(error, @"Unable to perform fetch request.");
    XCTAssertTrue(count == 0, @"Incorrect fetch count.");
}

-(void)test_predicateCompound
{
    const NSUInteger usersCount = 30;
    
    [self createUsers:usersCount];
    
    __block NSError *error = nil;
    
    [@{ [NSPredicate predicateWithFormat:@"TRUEPREDICATE && FALSEPREDICATE"] : @(0),
        [NSPredicate predicateWithFormat:@"TRUEPREDICATE || FALSEPREDICATE"] : @(usersCount),
        [NSPredicate predicateWithFormat:@"!TRUEPREDICATE"] : @(0),
        } enumerateKeysAndObjectsUsingBlock:^(NSPredicate *predicate, NSNumber *expectedCount, BOOL *stop) {
            
            NSFetchRequest *req = [[NSFetchRequest alloc] initWithEntityName:@"User"];
            req.predicate = predicate;
            
            NSUInteger count = [context countForFetchRequest:req error:&error];
            
            XCTAssertFalse(count == NSNotFound, @"Error with fetch: %@", error);
            XCTAssertEqual(count, [expectedCount unsignedIntegerValue], @"Incorrect fetch count");
        }];
}

- (void)test_aggregateExpressions {
    NSManagedObject *user = [NSEntityDescription insertNewObjectForEntityForName:@"User" inManagedObjectContext:context];

    // Create tags not assigned to any user
    NSArray *unusedTagNames = @[@"tag 1", @"Tag 2", @"Täg 3"];
    for (NSString *tagName in unusedTagNames) {
        NSManagedObject *tag = [NSEntityDescription insertNewObjectForEntityForName:@"Tag" inManagedObjectContext:context];
        [tag setValue:tagName forKey:@"name"];
    }

    // Create tags assigned to user
    NSArray *usedTagNames = @[@"User Tag 1", @"User Tag 2"];
    for (NSString *tagName in usedTagNames) {
        NSManagedObject *tag = [NSEntityDescription insertNewObjectForEntityForName:@"Tag" inManagedObjectContext:context];
        [tag setValue:tagName forKey:@"name"];

        [tag setValue:[NSSet setWithObject:user] forKey:@"hasUsers"];
    }

    [context save:nil];

    // Create aggregate expression consisting of (a) constant and (b) key path expressions
    NSString *constantValue = unusedTagNames[1];
    NSArray *aggregate = @[[NSExpression expressionForConstantValue:constantValue],
                           [NSExpression expressionForKeyPath:@"hasUsers.hasTags.name"]];

    NSExpression *aggregateExpression = [NSExpression expressionForAggregate:aggregate];

    // Query tags with names in aggregate expression
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Tag"];
    req.predicate = [NSPredicate predicateWithFormat:@"name IN %@", aggregateExpression];
    NSArray *result = [context executeFetchRequest:req error:nil];

    // Compare query result with expected values
    NSSet *resultSet = [NSSet setWithArray:[result valueForKey:@"name"]];
    NSSet *expectedSet = [NSSet setWithArray:[[NSMutableArray arrayWithObject:constantValue]
                                              arrayByAddingObjectsFromArray:usedTagNames]];

    XCTAssertEqualObjects(resultSet, expectedSet);
}

- (void)test_aggregateFunctions {
    NSArray *data = @[@1, @2, @3, @4, @7];
    
    for (NSNumber *obj in data) {
        NSManagedObject *add = [NSEntityDescription insertNewObjectForEntityForName:@"User" inManagedObjectContext:context];
        [add setValue:obj forKey:@"age"];
    }
    [context save:nil];
    
    NSSet*(^query)(NSString*)  =  ^(NSString *function){
        NSExpressionDescription *expressionDescription = [NSExpressionDescription new];
        expressionDescription.name = @"age";
        expressionDescription.expression = [NSExpression expressionForFunction:function arguments:@[[NSExpression expressionForKeyPath:@"age"]]];
        expressionDescription.expressionResultType = NSDoubleAttributeType;
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"User"];
        req.propertiesToFetch = @[expressionDescription];
        req.resultType = NSDictionaryResultType;
        
        NSDictionary * result = [context executeFetchRequest:req error:nil].firstObject;
        return result[@"age"];
    };
    
    XCTAssertEqualObjects(query(@"sum:"), @17);
    XCTAssertEqualObjects(query(@"count:"), @5);
    XCTAssertEqualObjects(query(@"min:"), @1);
    XCTAssertEqualObjects(query(@"max:"), @7);
    XCTAssertEqualObjects(query(@"average:"), @3.4);
    
    //unsupported in default sqlite store
    //XCTAssertEqualObjects(query(@"median:"), @0);
    //XCTAssertEqualObjects(query(@"mode:"), @0);
    //XCTAssertEqualObjects(query(@"stddev:"), @0);
}

- (void)test_stringComparision {
    NSArray *data = @[@"testa", @"testą", @"TESTĄ", @"TESTA"];
    
    for (NSString *obj in data) {
        NSManagedObject *add = [NSEntityDescription insertNewObjectForEntityForName:@"Post" inManagedObjectContext:context];
        [add setValue:obj forKey:@"title"];
    }
    [context save:nil];
    
    NSSet*(^query)(NSString*, NSString*)  =  ^(NSString *query, NSString *value){
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"Post"];
        req.predicate = [NSPredicate predicateWithFormat:query, value];
        NSArray *queryResult = [context executeFetchRequest:req error:nil];
        NSMutableSet *result = [NSMutableSet new];
        
        for (NSManagedObject *obj in queryResult) {
            [result addObject:[obj valueForKey:@"title"]];
        }
        
        return result;
    };
    NSArray* expected;
    
    expected = @[@"testa"];
    XCTAssertEqualObjects(query(@"title like %@", @"testa"), [NSSet setWithArray:expected]);
    
    expected = @[@"testa", @"TESTA"];
    XCTAssertEqualObjects(query(@"title like[c] %@", @"testa"), [NSSet setWithArray:expected]);
    
    expected = @[@"testa", @"testą"];
    XCTAssertEqualObjects(query(@"title like[d] %@", @"testa"), [NSSet setWithArray:expected]);
    
    expected = data;
    XCTAssertEqualObjects(query(@"title like[cd] %@", @"testa"), [NSSet setWithArray:expected]);
    
    expected = @[@"testą"];
    XCTAssertEqualObjects(query(@"title like %@", @"testą"), [NSSet setWithArray:expected]);
    
    expected = data;
    XCTAssertEqualObjects(query(@"TRUEPREDICATE", nil), [NSSet setWithArray:expected]);
}

- (void)test_fetchAccountsByManyToManyRelationship {
    // Create three Account entities with transfer relationships set up this way:
    //
    // - account0 can transfer to account1 and account2
    // - account1 can transfer to account2
    //
    // The fetch request is set up to fetch those entities that can send to at least one other Account AND
    // can receive from at least one other Account.

    NSString *const entityName = @"Account";
    NSManagedObject *const account0 = [NSEntityDescription insertNewObjectForEntityForName:entityName
                                                                    inManagedObjectContext:context];
    NSManagedObject *const account1 = [NSEntityDescription insertNewObjectForEntityForName:entityName
                                                                    inManagedObjectContext:context];
    NSManagedObject *const account2 = [NSEntityDescription insertNewObjectForEntityForName:entityName
                                                                    inManagedObjectContext:context];

    NSString *const accountID0 = @"account0";
    NSString *const accountID1 = @"account1";
    NSString *const accountID2 = @"account2";
    NSString *const idKey = @"accountID";
    NSString *const transferFromAccountsKey = @"transferFromAccounts";
    NSString *const transferToAccountsKey = @"transferToAccounts";

    [account0 setValue:accountID0 forKey:idKey];
    [account1 setValue:accountID1 forKey:idKey];
    [account2 setValue:accountID2 forKey:idKey];

    NSMutableSet *const transferToAccounts0 = [account0 mutableSetValueForKey:transferToAccountsKey];
    [transferToAccounts0 addObject:account1];
    [transferToAccounts0 addObject:account2];

    NSMutableSet *const transferToAccounts1 = [account1 mutableSetValueForKey:transferToAccountsKey];
    [transferToAccounts1 addObject:account2];

    NSSet *transferFromAccounts;
    NSSet *transferToAccounts;

    transferFromAccounts = [account0 valueForKey:transferFromAccountsKey];
    transferToAccounts = [account0 valueForKey:transferToAccountsKey];
    XCTAssertEqual(transferFromAccounts.count, 0,
                   @"The %@ entity with ID %@ should have an empty set for %@", entityName, accountID0,
                   transferFromAccountsKey);
    XCTAssertEqual(transferToAccounts.count, 2,
                   @"The %@ entity with ID %@ should be able to send to two %@ entities", entityName,
                   accountID0, entityName);

    transferFromAccounts = [account1 valueForKey:transferFromAccountsKey];
    transferToAccounts = [account1 valueForKey:transferToAccountsKey];
    XCTAssertEqual(transferFromAccounts.count, 1,
                   @"The %@ entity with ID %@ should be able to receive from one other %@", entityName,
                   accountID1, entityName);
    XCTAssertTrue([transferFromAccounts containsObject:account0],
                  @"The %@ entity with ID %@ should have %@ in its transfer-from set", entityName,
                  accountID1, accountID0);
    XCTAssertEqual(transferToAccounts.count, 1,
                   @"The %@ entity with ID %@ should be able to send to one other %@", entityName,
                   accountID1, entityName);

    transferFromAccounts = [account2 valueForKey:transferFromAccountsKey];
    transferToAccounts = [account2 valueForKey:transferToAccountsKey];
    XCTAssertEqual(transferFromAccounts.count, 2,
                   @"The %@ entity with ID %@ should be able to receive from two other %@ entities",
                   entityName, accountID1, entityName);
    XCTAssertTrue([transferFromAccounts containsObject:account0],
                  @"The %@ entity with ID %@ should have %@ in its transfer-from set", entityName,
                  accountID2, accountID0);
    XCTAssertTrue([transferFromAccounts containsObject:account1],
                  @"The %@ entity with ID %@ should have %@ in its transfer-from set", entityName,
                  accountID2, accountID1);
    XCTAssertEqual(transferToAccounts.count, 0,
                   @"The %@ entity with ID %@ should have an empty set for %@", entityName, accountID2,
                   transferToAccountsKey);

    [context save:nil];

    NSFetchRequest *const fetchRequest = [NSFetchRequest fetchRequestWithEntityName:entityName];
    NSPredicate *const linkageCountPredicate = [NSPredicate predicateWithFormat:@"%K.@count > 0 AND %K.@count > 0",
                                                transferToAccountsKey, transferFromAccountsKey];
    fetchRequest.predicate = linkageCountPredicate;

    NSError * __autoreleasing error;
    NSArray *fetchedAccounts = [context executeFetchRequest:fetchRequest error:&error];
    XCTAssertNotNil(fetchedAccounts, @"Failed to fetch %@ entities: %@", entityName, error);
    XCTAssertEqual(fetchedAccounts.count, 1, @"Should have only fetched one %@ (the one with ID %@)",
                   entityName, accountID1);
    XCTAssertTrue([fetchedAccounts containsObject:account1], @"Expected %@ to be in %@", account1, fetchedAccounts);
}

@end
