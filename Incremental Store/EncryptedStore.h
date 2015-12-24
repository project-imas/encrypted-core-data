//
// EncryptedStore.h
//
// Copyright 2012 - 2014 The MITRE Corporation, All Rights Reserved.
//
//

#import <CoreData/CoreData.h>

typedef struct _options {
    char * passphrase;
    char * database_location;
    int * cache_size;
} EncryptedStoreOptions;

extern NSString * const EncryptedStoreType;
extern NSString * const EncryptedStorePassphraseKey;
extern NSString * const EncryptedStoreErrorDomain;
extern NSString * const EncryptedStoreErrorMessageKey;
extern NSString * const EncryptedStoreDatabaseLocation;
extern NSString * const EncryptedStoreCacheSize;

typedef NS_ENUM(NSInteger, EncryptedStoreError)
{
    EncryptedStoreErrorIncorrectPasscode = 6000,
    EncryptedStoreErrorMigrationFailed
};

@interface EncryptedStore : NSIncrementalStore
+ (NSPersistentStoreCoordinator *)makeStoreWithOptions:(NSDictionary *)options managedObjectModel:(NSManagedObjectModel *)objModel;
+ (NSPersistentStoreCoordinator *)makeStoreWithStructOptions:(EncryptedStoreOptions *) options managedObjectModel:(NSManagedObjectModel *)objModel;
+ (NSPersistentStoreCoordinator *)makeStore:(NSManagedObjectModel *) objModel
                                   passcode:(NSString *) passcode;

+ (NSPersistentStoreCoordinator *)makeStoreWithOptions:(NSDictionary *)options managedObjectModel:(NSManagedObjectModel *)objModel error:(NSError * __autoreleasing*)error;
+ (NSPersistentStoreCoordinator *)makeStoreWithStructOptions:(EncryptedStoreOptions *) options managedObjectModel:(NSManagedObjectModel *)objModel error:(NSError * __autoreleasing*)error;
+ (NSPersistentStoreCoordinator *)makeStore:(NSManagedObjectModel *) objModel
                                   passcode:(NSString *) passcode error:(NSError * __autoreleasing*)error;

- (BOOL)configureDatabasePassphrase:(NSError *__autoreleasing*)error;
- (BOOL)checkDatabaseStatusWithError:(NSError *__autoreleasing*)error;
- (BOOL)changeDatabasePassphrase:(NSString *)passphrase error:(NSError *__autoreleasing*)error;
- (BOOL)setDatabasePassphrase:(NSString *)passphrase error:(NSError *__autoreleasing*)error;
// Warning! // This method could close database connection ( look at implementation for details )
- (BOOL)validateDatabasePassphrase:(NSString *)passphrase error:(NSError *__autoreleasing*)error;
- (BOOL)changeDatabasePassphrase:(NSString *)oldPassphrase toNewPassphrase:(NSString *)newPassphrase error:(NSError *__autoreleasing*)error;


@end
