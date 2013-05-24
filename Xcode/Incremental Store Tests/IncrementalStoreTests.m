//
//  IncrementalStoreTests.m
//  Incremental Store Tests
//
//  Created by Caleb Davenport on 8/7/12.
//

#import <SenTestingKit/SenTestingKit.h>
#import <CoreData/CoreData.h>
#import <EncryptedStore.h>

/*
 
 Flip between 0 and 1 to use the system SQLite store and custom incremental
 store subclass respectively.
 
 */
#define USE_ENCRYPTED_STORE 1

@interface IncrementalStoreTests : SenTestCase

@end

@implementation IncrementalStoreTests {
    NSPersistentStoreCoordinator *coordinator;
    NSPersistentStore *store;
    NSManagedObjectContext *context;
}

+ (void)initialize {
    if (self == [IncrementalStoreTests class]) {
        srand(time(NULL));
    }
}

+ (NSBundle *)bundle {
    return [NSBundle bundleForClass:[IncrementalStoreTests class]];
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

- (void)createUsers:(NSUInteger)count {
    NSError *error;
    
    // insert users and save
    for (NSUInteger i = 0; i < count; i++) {
        id object = [NSEntityDescription insertNewObjectForEntityForName:@"User" inManagedObjectContext:context];
        [object setValue:@"Test Name" forKey:@"name"];
    }
    error = nil;
    BOOL save = [context save:&error];
    STAssertTrue(save, @"Unable to perform save.\n%@", error);
    
    // test count
    error = nil;
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
    NSUInteger testCount = [context countForFetchRequest:request error:&error];
    STAssertNil(error, @"Could not execute fetch request.");
    STAssertEquals(testCount, count, @"The number of users is wrong.");
    
}

- (void)createPosts:(NSUInteger)count forUser:(NSManagedObject *)user {
    NSError *error;
    
    // insert posts and save
    for (NSUInteger i = 0; i < count; i++) {
        id object = [NSEntityDescription insertNewObjectForEntityForName:@"Post" inManagedObjectContext:context];
        [object setValue:@"Test Title" forKey:@"title"];
        [object setValue:@"Test body." forKey:@"body"];
        [object setValue:user forKey:@"user"];
    }
    error = nil;
    BOOL save = [context save:&error];
    STAssertTrue(save, @"Unable to perform save.\n%@", error);
    
    // test count
    error = nil;
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"Post"];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"user = %@", user];
    [request setPredicate:predicate];
    NSUInteger testCount = [context countForFetchRequest:request error:&error];
    STAssertNil(error, @"Could not execute fetch request.");
    STAssertEquals(testCount, count, @"The number of posts is wrong.");
    
}

- (void)setUp {
    [super setUp];
    [IncrementalStoreTests deleteDatabase];
    NSURL *URL;
    
    // get the model
    NSBundle *bundle = [IncrementalStoreTests bundle];
    NSManagedObjectModel *model = [NSManagedObjectModel mergedModelFromBundles:@[ bundle ]];
    
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
#if USE_ENCRYPTED_STORE
    store = [coordinator
             addPersistentStoreWithType:EncryptedStoreType
             configuration:nil
             URL:URL
             options:options
             error:&error];
#else
    store = [coordinator
             addPersistentStoreWithType:NSSQLiteStoreType
             configuration:nil
             URL:URL
             options:options
             error:&error];
#endif
    STAssertNotNil(store, @"Unable to add persistent store.\n%@", error);
    
    // load context
    context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSConfinementConcurrencyType];
    [context setPersistentStoreCoordinator:coordinator];
    STAssertNotNil(context, @"Unable to create context.\n%@", error);
    
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
    STAssertNil(error, @"Unable to perform fetch request.");
    STAssertEquals([users count], limit, @"Invalid number of results.");
    
    // delete users
    [users enumerateObjectsUsingBlock:^(id user, NSUInteger index, BOOL *stop) {
        [context deleteObject:user];
    }];
    error = nil;
    BOOL save = [context save:&error];
    STAssertTrue(save, @"Unable to perform save.\n%@", error);
    
    // perform count
    error = nil;
    request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
    NSUInteger countTest = [context countForFetchRequest:request error:&error];
    STAssertEquals(countTest, count - limit, @"Invalid number of results.");
    
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
    STAssertNil(error, @"Unable to perform fetch request.");
    STAssertEquals([users count], limit, @"Invalid number of results.");
    NSManagedObject *user = [users lastObject];
    STAssertNotNil(user, @"No user found.");
    
    // edit and save
    for (NSUInteger i = 0; i < 10; i++) {
        [user setValue:[[NSProcessInfo processInfo] globallyUniqueString] forKey:@"name"];
        BOOL save = [context save:&error];
        STAssertTrue(save, @"Unable to perform save at index:%lu.\n%@", (unsigned long)i, error);
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
    STAssertNil(error, @"Unable to perform fetch request.");
    STAssertEquals([users count], limit, @"Invalid number of results.");
    NSManagedObject *user = [users lastObject];
    STAssertNotNil(user, @"No user found.");
    
    // edit and save
    error = nil;
    [user setValue:nil forKey:@"name"];
    save = [context save:&error];
    STAssertTrue(save, @"Unable to perform save.\n%@", error);
    
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
    STAssertNil(error, @"Unable to perform fetch request.");
    STAssertEquals(numberOfusers, count, @"Invalid number of results.");
    
    // overall post count
    error = nil;
    request = [NSFetchRequest fetchRequestWithEntityName:@"Post"];
    count = [context countForFetchRequest:request error:&error];
    STAssertNil(error, @"Unable to perform fetch request.");
    STAssertEquals(numberOfPostsPerUser * numberOfusers, count, @"Invalid number of results.");
    
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
    STAssertNotNil(matching, @"Unable to perform fetch request.\n%@", error);
    STAssertEquals(numberOfusers, [matching count], @"Invalid number of users.");
    id user = [matching objectAtIndex:rand() % [matching count]];
    
    // delete user and save
    error = nil;
    [context deleteObject:user];
    save = [context save:&error];
    STAssertTrue(save, @"Unable to perform save.\n%@", error);
    
    // make sure we have one less user
    error = nil;
    request = [NSFetchRequest fetchRequestWithEntityName:@"User"];
    count = [context countForFetchRequest:request error:&error];
    STAssertNil(error, @"Unable to perform fetch request.");
    STAssertEquals(numberOfusers - 1, count, @"Invalid number of users.");
    
    // make sure we have one less user worth of posts
    error = nil;
    request = [NSFetchRequest fetchRequestWithEntityName:@"Post"];
    count = [context countForFetchRequest:request error:&error];
    STAssertNil(error, @"Unable to perform fetch request.");
    STAssertEquals((numberOfusers - 1) * numberOfPostsPerUser, count, @"Invalid number of posts.");
    
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
    STAssertNil(error, @"Unable to perform fetch request.");
    STAssertEquals([users count], limit, @"Invalid number of results.");
    NSManagedObject *user = [users lastObject];
    
    STAssertNotNil(user, @"No object found.");
    
    // create posts
    [self createPosts:5 forUser:user];
    
    // fetch post
    error = nil;
    request = [[NSFetchRequest alloc] initWithEntityName:@"Post"];
    [request setFetchLimit:limit];
    [request setPredicate:[NSPredicate predicateWithFormat:@"user = %@", user]];
    NSArray *posts = [context executeFetchRequest:request error:&error];
    STAssertNil(error, @"Unable to perform fetch request.");
    STAssertEquals([posts count], limit, @"Invalid number of results.");
    NSManagedObject *post = [posts lastObject];
    STAssertNotNil(post, @"No object found.");
    
    // delete and save
    [context deleteObject:post];
    save = [context save:&error];
    STAssertTrue(save, @"Unable to perform save.\n%@", error);
    
}

- (void)test_createUsersAndSearch {
    NSUInteger limit = 5;
    [self createUsers:limit];
    NSError *__block error;
    NSFetchRequest *__block request;
    
    // fetch users
    NSArray *predicates = @[
        [NSPredicate predicateWithFormat:@"name like[c] %@", @"test name"],
        [NSPredicate predicateWithFormat:@"name contains[c] %@", @"name"],
        [NSPredicate predicateWithFormat:@"name endswith[c] %@", @"name"]
    ];
    [predicates enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        error = nil;
        request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
        [request setPredicate:obj];
        NSArray *users = [context executeFetchRequest:request error:&error];
        STAssertNil(error, @"Unable to perform fetch request.");
        STAssertEquals([users count], limit, @"Invalid number of results.");
        NSManagedObject *user = [users lastObject];
        STAssertNotNil(user, @"No object found.");
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
    STAssertNil(error, @"Unable to perform fetch request.");
    STAssertEquals([users count], limit, @"Invalid number of results.");
    NSManagedObject *user = [users lastObject];
    STAssertNotNil(user, @"No object found.");
    
    // create posts
    [self createPosts:5 forUser:user];
    
    // fetch users
    NSArray *predicates = @[
    [NSPredicate predicateWithFormat:@"posts.title like[c] %@", @"title"],
    [NSPredicate predicateWithFormat:@"posts.title contains[c] %@", @"title"],
    [NSPredicate predicateWithFormat:@"posts.title endswith[c] %@", @"title"]
    ];
    [predicates enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        errorBlock = nil;
        requestBlock = [[NSFetchRequest alloc] initWithEntityName:@"User"];
        [request setPredicate:obj];
        NSArray *users = [context executeFetchRequest:request error:&errorBlock];
        STAssertNil(error, @"Unable to perform fetch request.");
        STAssertEquals([users count], limit, @"Invalid number of results.");
        NSManagedObject *user = [users lastObject];
        STAssertNotNil(user, @"No object found.");
    }];
}

@end
