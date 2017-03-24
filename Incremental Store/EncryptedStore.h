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
extern NSString * const EncryptedStoreFileManagerOption;
typedef NS_ENUM(NSInteger, EncryptedStoreError)
{
    EncryptedStoreErrorIncorrectPasscode = 6000,
    EncryptedStoreErrorMigrationFailed
};

@interface EncryptedStoreFileManagerConfiguration : NSObject
#pragma mark - Initialization
- (instancetype)initWithOptions:(NSDictionary *)options;
#pragma mark - Properties
@property (nonatomic, readwrite) NSFileManager *fileManager;
@property (nonatomic, readwrite) NSBundle *bundle;
@property (nonatomic, readwrite) NSString *databaseName;
@property (nonatomic, readwrite) NSString *databaseExtension;
@property (nonatomic, readonly) NSString *databaseFilename;
@property (nonatomic, readwrite) NSURL *databaseURL;
@end

@interface EncryptedStoreFileManagerConfiguration (OptionsKeys)
+ (NSString *)optionFileManager;
+ (NSString *)optionBundle;
+ (NSString *)optionDatabaseName;
+ (NSString *)optionDatabaseExtension;
+ (NSString *)optionDatabaseURL;
@end

@interface EncryptedStoreFileManager : NSObject
#pragma mark - Initialization
+ (instancetype)defaultManager;
- (instancetype)initWithConfiguration:(EncryptedStoreFileManagerConfiguration *)configuration;

#pragma mark - Setup
- (void)setupDatabaseWithOptions:(NSDictionary *)options error:(NSError * __autoreleasing*)error;

#pragma mark - Getters
@property (nonatomic, readwrite) EncryptedStoreFileManagerConfiguration *configuration;
@property (nonatomic, readonly) NSURL *databaseURL;
@end

@interface EncryptedStoreFileManager (FileManagerExtensions)
@property (nonatomic, readonly) NSURL *applicationSupportURL;
- (void)setAttributes:(NSDictionary *)attributes ofItemAtURL:(NSURL *)url error:(NSError * __autoreleasing*)error;
@end

@interface EncryptedStore : NSIncrementalStore
#pragma mark - Initialization
+ (NSPersistentStoreCoordinator *)makeStoreWithOptions:(NSDictionary *)options managedObjectModel:(NSManagedObjectModel *)objModel;
+ (NSPersistentStoreCoordinator *)makeStoreWithStructOptions:(EncryptedStoreOptions *) options managedObjectModel:(NSManagedObjectModel *)objModel;
+ (NSPersistentStoreCoordinator *)makeStore:(NSManagedObjectModel *) objModel
                                   passcode:(NSString *) passcode;

//+ (NSPersistentStoreCoordinator *)makeStoreWithOptions:(NSDictionary *)options managedObjectModel:(NSManagedObjectModel *)objModel error:(NSError * __autoreleasing*)error;
+ (NSPersistentStoreCoordinator *)makeStoreWithStructOptions:(EncryptedStoreOptions *) options managedObjectModel:(NSManagedObjectModel *)objModel error:(NSError * __autoreleasing*)error;
+ (NSPersistentStoreCoordinator *)makeStore:(NSManagedObjectModel *) objModel
                                   passcode:(NSString *) passcode error:(NSError * __autoreleasing*)error;

#pragma mark - Passphrase manipulation
#pragma mark - Public

/**
 @discussion Check old passphrase and if success change old passphrase to new passphrase.
 
 @param oldPassphrase The old passhrase with which database was previously opened.
 @param newPassphrase The new passhrase which is desired for database.
 @param error Inout error.
 @return The status of operation.
 */
- (BOOL)checkAndChangeDatabasePassphrase:(NSString *)oldPassphrase toNewPassphrase:(NSString *)newPassphrase error:(NSError *__autoreleasing*)error;


/**
 @discussion Check database passphrase.
 
 @param passphrase The desired passphrase to test for.
 @param error Inout error.
 @return The status of operation.
 */
- (BOOL)checkDatabasePassphrase:(NSString *)passphrase error:(NSError *__autoreleasing*)error;

#pragma mark - Internal

/**
 @brief Configure database with passhrase.
 
 @discussion Configure database with passphrase stored in options dictionary.
 
 @attention Internal usage.

 @pre (error != NULL)
 
 @param error Inout error.
 @return The status of operation.
 */
- (BOOL)configureDatabasePassphrase:(NSError *__autoreleasing*)error;

/**
 @brief Test database connection against simple sql request.
 @discussion Test database connection against simple sql request. Success means database open state and correctness of previous passphrase manipulation operation.

 @attention Internal usage.
 
 @pre (error != NULL)
 
 @param error Inout error.
 @return The status of operation.
 */
- (BOOL)checkDatabaseStatusWithError:(NSError *__autoreleasing*)error;


/**
 @brief
 Primitive change passphrase operation.
 
 @discussion Ignores database state and tries to change database passphrase.
 Behaviour is unknown if used before old passphrase validation.
 
 @attention Internal usage.

 @pre (error != NULL)

 @param passphrase The new passphrase.
 @param error Inout error.
 @return The status of operation.
 */
- (BOOL)changeDatabasePassphrase:(NSString *)passphrase error:(NSError *__autoreleasing*)error;


/**
 @brief Primitive set passphrase operation.
 
 @discussion Ignores database state and tries to set database passphrase.
 One of first-call functions in database setup.

 @attention Internal usage.
 
 @pre (error != NULL)

 @param passphrase The desired first passphrase of database.
 @param error Inout error.
 @return The status of operation.
 */
- (BOOL)setDatabasePassphrase:(NSString *)passphrase error:(NSError *__autoreleasing*)error;


/**
 @brief Validates database passphrase for correctness.
 
 @discussion Tries to reopen database on provided passphrase.
 Closes database and try to open in on provided passphrase.
 
 @warning Could close database connection ( look at an implementation for details ).
 
 @pre (error != NULL)

 @param passphrase The desired passphrase to validate.
 @param error Inout error.
 @return The status of operation.
 */
- (BOOL)validateDatabasePassphrase:(NSString *)passphrase error:(NSError *__autoreleasing*)error;

/**
 @brief Primitive database change passphrase operation.
 
 @discussion Tries to open database on provided oldPassphrase and in success it tries to change passphrase to new passphrase.

 @attention Internal usage.
 
 @pre (error != NULL)

 @param oldPassphrase: The old passphrase.
 @param newPassphrase: The new passphrase.
 @param error: Inout error.
 @return The status of operation.
 */
- (BOOL)changeDatabasePassphrase:(NSString *)oldPassphrase toNewPassphrase:(NSString *)newPassphrase error:(NSError *__autoreleasing*)error;


@end

@interface EncryptedStore (Initialization)
+ (NSPersistentStoreCoordinator *)makeStoreWithOptions:(NSDictionary *)options managedObjectModel:(NSManagedObjectModel *)objModel error:(NSError * __autoreleasing*)error;
+ (NSPersistentStoreCoordinator *)coordinator:(NSPersistentStoreCoordinator *)coordinator byAddingStoreAtURL:(NSURL *)url configuration:(NSString *)configuration options:(NSDictionary *)options error:(NSError * __autoreleasing*)error;
+ (NSPersistentStoreDescription *)makeDescriptionWithOptions:(NSDictionary *)options configuration:(NSString *)configuration error:(NSError * __autoreleasing*)error API_AVAILABLE(macosx(10.12),ios(10.0),tvos(10.0),watchos(3.0));
@end

@interface EncryptedStore (Configuration)
//alias to options.
@property (copy, nonatomic, readonly) NSDictionary *configurationOptions;
@property (strong, nonatomic, readonly) EncryptedStoreFileManager *fileManager;
@end

@interface EncryptedStore (OptionsKeys)
+ (NSString *)optionType;
+ (NSString *)optionPassphraseKey;
+ (NSString *)optionErrorDomain;
+ (NSString *)optionErrorMessageKey;
+ (NSString *)optionDatabaseLocation;
+ (NSString *)optionCacheSize;
+ (NSString *)optionFileManager;
@end
