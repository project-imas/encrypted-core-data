//
//  PasswordTests.m
//  Incremental Store
//
//  Created by Richard Hodgkins on 18/08/2014.
//  Copyright (c) 2014 Caleb Davenport. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>
#import <CoreData/CoreData.h>
#import "EncryptedStore.h"

#import <sqlite3.h>

static BOOL const UseEncryptedStore = YES;

static NSString *const CorrectPassword = @"CorrectPassword";
static NSString *const IncorrectPassword = @"IncorrectPassword";

@interface PasswordTests : SenTestCase

@end

@implementation PasswordTests {
    __strong NSPersistentStoreCoordinator *coordinator;
}

+ (NSBundle *)bundle {
    return [NSBundle bundleForClass:self];
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
    NSBundle *bundle = [[self class] bundle];
    NSManagedObjectModel *model = [NSManagedObjectModel mergedModelFromBundles:@[ bundle ]];
    
    // get the coordinator
    coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    
    // add store
    NSDictionary *options = @{
                              EncryptedStorePassphraseKey : password
                              };
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
    
    STAssertNotNil(store, @"Nil store: %@", error);
    [self cleanUp:store];

    store = [self openDatabaseWithPassword:CorrectPassword error:&error];
    
    STAssertNotNil(store, @"Nil store: %@", error);
    [self cleanUp:store];
}

- (void)test_creatingDBAndOpeningWithIncorrectPassword
{
    NSError *error;
    NSPersistentStore *store = [self openDatabaseWithPassword:CorrectPassword error:&error];
    
    STAssertNotNil(store, @"Nil store: %@", error);
    [self cleanUp:store];
    
    store = [self openDatabaseWithPassword:IncorrectPassword error:&error];
    
    STAssertNil(store, @"Nil context");
    STAssertEqualObjects(error.domain, EncryptedStoreErrorDomain, @"Incorrect error domain");
    STAssertEquals(error.code, EncryptedStoreErrorIncorrectPasscode, @"Incorrect error code");
    
    NSError *sqliteError = error.userInfo[NSUnderlyingErrorKey];
    STAssertNotNil(sqliteError, @"Nil SQLite error");
    STAssertEqualObjects(sqliteError.domain, NSSQLiteErrorDomain, @"Incorrect error SQLite error domain");
    STAssertEquals(sqliteError.code, (NSInteger)SQLITE_NOTADB, @"Incorrect error SQLite error code");
    [self cleanUp:store];
    
    // Try again once more to be sure it still opens
    store = [self openDatabaseWithPassword:CorrectPassword error:&error];
    
    STAssertNotNil(store, @"Nil store: %@", error);
    [self cleanUp:store];
}

@end
