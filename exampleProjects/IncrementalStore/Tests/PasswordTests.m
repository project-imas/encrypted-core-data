//
//  PasswordTests.m
//  Incremental Store
//
//  Created by Richard Hodgkins on 18/08/2014.
//  Copyright (c) 2014 Caleb Davenport. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <CoreData/CoreData.h>
#import "EncryptedStore.h"

#import <sqlite3.h>

static BOOL const UseEncryptedStore = YES;

static NSString *const CorrectPassword = @"CorrectPassword";
static NSString *const IncorrectPassword = @"IncorrectPassword";

@interface PasswordTests : XCTestCase

@end

@implementation PasswordTests {
    __strong NSPersistentStoreCoordinator *coordinator;
}

+ (NSBundle *)bundle {
    return [NSBundle bundleForClass:self];
}

+ (NSManagedObjectModel *)model {
    return [NSManagedObjectModel mergedModelFromBundles:@[ [self bundle] ]];
}

+ (NSURL *)databaseURL {
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSError *error = nil;
    NSURL *applicationDocumentsDirectory = [fileManager URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];
    
    NSAssert(applicationDocumentsDirectory, @"Unable to get the Documents directory: %@", error);
    
    return [applicationDocumentsDirectory URLByAppendingPathComponent:@"database-password_tests.sqlite"];
}

- (NSPersistentStore *)openDatabaseWithPassword:(NSString *)password error:(NSError *__autoreleasing*)error
{
    NSURL *URL;
    
    // get the model
    NSManagedObjectModel *model = [[self class] model];
    
    // get the coordinator
    coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    
    // add store
    NSDictionary *options;
    if (password) {
        options = @{
                    EncryptedStorePassphraseKey : password
                    };
    } else {
        options = nil;
    }
    URL = [[self class] databaseURL];
    NSLog(@"Working with database at URL: %@", URL);
    
    NSString *storeType = UseEncryptedStore ? EncryptedStoreType : NSSQLiteStoreType;
    
    NSPersistentStore *store;
    store = [coordinator
             addPersistentStoreWithType:storeType
             configuration:nil
             URL:URL
             options:options
             error:error];
    
    return store;
}

- (void)setUp
{
    [super setUp];
    
    [[NSFileManager defaultManager] removeItemAtURL:[[self class] databaseURL] error:nil];
}

- (void)tearDown
{
    [[NSFileManager defaultManager] removeItemAtURL:[[self class] databaseURL] error:nil];
    
    [super tearDown];
}

- (void)cleanUp:(NSPersistentStore *)store
{
    if (store) {
        [coordinator removePersistentStore:store error:nil];
        store = nil;
    }
    coordinator = nil;
}

- (void)test_creatingDBAndOpeningWithCorrectPassword
{
    NSError *error;
    NSPersistentStore *store = [self openDatabaseWithPassword:CorrectPassword error:&error];
    
    XCTAssertNotNil(store, @"Nil store: %@", error);
    [self cleanUp:store];

    store = [self openDatabaseWithPassword:CorrectPassword error:&error];
    
    XCTAssertNotNil(store, @"Nil store: %@", error);
    [self cleanUp:store];
}

- (void)test_creatingDBAndOpeningWithIncorrectPassword
{
    NSError *error;
    NSPersistentStore *store = [self openDatabaseWithPassword:CorrectPassword error:&error];
    
    XCTAssertNotNil(store, @"Nil store: %@", error);
    [self cleanUp:store];
    
    store = [self openDatabaseWithPassword:IncorrectPassword error:&error];
    
    XCTAssertNil(store, @"Nil context");
    XCTAssertEqualObjects(error.domain, EncryptedStoreErrorDomain, @"Incorrect error domain");
    XCTAssertEqual(error.code, EncryptedStoreErrorIncorrectPasscode, @"Incorrect error code");
    
    NSError *sqliteError = error.userInfo[NSUnderlyingErrorKey];
    XCTAssertNotNil(sqliteError, @"Nil SQLite error");
    XCTAssertEqualObjects(sqliteError.domain, NSSQLiteErrorDomain, @"Incorrect error SQLite error domain");
    XCTAssertEqual(sqliteError.code, (NSInteger)SQLITE_NOTADB, @"Incorrect error SQLite error code");
    [self cleanUp:store];
    
    // Try again once more to be sure it still opens
    store = [self openDatabaseWithPassword:CorrectPassword error:&error];
    
    XCTAssertNotNil(store, @"Nil store: %@", error);
    [self cleanUp:store];
}

#pragma mark - Empty password

- (void)test_creatingDBAndOpeningWithEmptyPassword
{
    NSError *error;
    NSPersistentStore *store = [self openDatabaseWithPassword:@"" error:&error];
    
    XCTAssertNotNil(store, @"Nil store: %@", error);
    [self cleanUp:store];
    
    store = [self openDatabaseWithPassword:@"" error:&error];
    
    XCTAssertNotNil(store, @"Nil store: %@", error);
    [self cleanUp:store];
}

- (void)test_creatingDBAndOpeningWithNilPassword
{
    NSError *error;
    NSPersistentStore *store = [self openDatabaseWithPassword:nil error:&error];
    
    XCTAssertNotNil(store, @"Nil store: %@", error);
    [self cleanUp:store];
    
    store = [self openDatabaseWithPassword:nil error:&error];
    
    XCTAssertNotNil(store, @"Nil store: %@", error);
    [self cleanUp:store];
}

/// Creates with empty string, tries with incorrect string, tries again with nil
- (void)test_creatingEmptyPasswordDBAndOpeningWithIncorrectPassword
{
    NSError *error;
    NSPersistentStore *store = [self openDatabaseWithPassword:@"" error:&error];
    
    XCTAssertNotNil(store, @"Nil store: %@", error);
    [self cleanUp:store];
    
    store = [self openDatabaseWithPassword:IncorrectPassword error:&error];
    
    XCTAssertNil(store, @"Nil context");
    XCTAssertEqualObjects(error.domain, EncryptedStoreErrorDomain, @"Incorrect error domain");
    XCTAssertEqual(error.code, EncryptedStoreErrorIncorrectPasscode, @"Incorrect error code");
    
    NSError *sqliteError = error.userInfo[NSUnderlyingErrorKey];
    XCTAssertNotNil(sqliteError, @"Nil SQLite error");
    XCTAssertEqualObjects(sqliteError.domain, NSSQLiteErrorDomain, @"Incorrect error SQLite error domain");
    XCTAssertEqual(sqliteError.code, (NSInteger)SQLITE_NOTADB, @"Incorrect error SQLite error code");
    [self cleanUp:store];
    
    // Try again once more to be sure it still opens
    store = [self openDatabaseWithPassword:nil error:&error];
    
    XCTAssertNotNil(store, @"Nil store: %@", error);
    [self cleanUp:store];
}

- (void)test_storeHelperMethodsWithEmptyPassword
{
    NSPersistentStoreCoordinator *coord;
    
    // Dict
    NSDictionary *dictOpts = @{EncryptedStorePassphraseKey : @""};
    XCTAssertNoThrowSpecificNamed(coord = [EncryptedStore makeStoreWithOptions:dictOpts managedObjectModel:[[self class] model]], NSException, NSInternalInconsistencyException, @"Assert was triggered as the created store was nil");
    XCTAssertEqual([[coord persistentStores] count], (NSUInteger) 1, @"There should be one persistent store attached to the coordinator");
    
    // Struct
    EncryptedStoreOptions structOpts;
    structOpts.database_location = NULL;
    structOpts.cache_size = 0;
    structOpts.passphrase = "";
    XCTAssertNoThrowSpecificNamed(coord = [EncryptedStore makeStoreWithStructOptions:&structOpts managedObjectModel:[[self class] model]], NSException, NSInternalInconsistencyException, @"Assert was triggered as the created store was nil");
    XCTAssertEqual([[coord persistentStores] count], (NSUInteger) 1, @"There should be one persistent store attached to the coordinator");
    
    // Passcode
    XCTAssertNoThrowSpecificNamed(coord = [EncryptedStore makeStore:[[self class] model] passcode:@""], NSException, NSInternalInconsistencyException, @"Assert was triggered as the created store was nil");
    XCTAssertEqual([[coord persistentStores] count], (NSUInteger) 1, @"There should be one persistent store attached to the coordinator");
}

- (void)test_storeHelperMethodsWithNilPassword
{
    NSPersistentStoreCoordinator *coord;
    
    // Dict
    NSDictionary *dictOpts = @{};
    XCTAssertNoThrowSpecificNamed(coord = [EncryptedStore makeStoreWithOptions:dictOpts managedObjectModel:[[self class] model]], NSException, NSInternalInconsistencyException, @"Assert was triggered as the created store was nil");
    XCTAssertEqual([[coord persistentStores] count], (NSUInteger) 1, @"There should be one persistent store attached to the coordinator");
    
    // Struct
    EncryptedStoreOptions structOpts;
    structOpts.database_location = NULL;
    structOpts.cache_size = 0;
    structOpts.passphrase = NULL;
    XCTAssertNoThrowSpecificNamed(coord = [EncryptedStore makeStoreWithStructOptions:&structOpts managedObjectModel:[[self class] model]], NSException, NSInternalInconsistencyException, @"Assert was triggered as the created store was nil");
    XCTAssertEqual([[coord persistentStores] count], (NSUInteger) 1, @"There should be one persistent store attached to the coordinator");
    
    // Passcode
    XCTAssertNoThrowSpecificNamed(coord = [EncryptedStore makeStore:[[self class] model] passcode:nil], NSException, NSInternalInconsistencyException, @"Assert was triggered as the created store was nil");
    XCTAssertEqual([[coord persistentStores] count], (NSUInteger) 1, @"There should be one persistent store attached to the coordinator");
}

@end
