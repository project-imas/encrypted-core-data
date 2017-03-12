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
- (BOOL)configureDatabasePassphrase:(NSError *__autoreleasing*)error;
- (BOOL)checkDatabaseStatusWithError:(NSError *__autoreleasing*)error;
- (BOOL)changeDatabasePassphrase:(NSString *)passphrase error:(NSError *__autoreleasing*)error;
- (BOOL)setDatabasePassphrase:(NSString *)passphrase error:(NSError *__autoreleasing*)error;
// Warning! // This method could close database connection ( look at implementation for details )
- (BOOL)validateDatabasePassphrase:(NSString *)passphrase error:(NSError *__autoreleasing*)error;
- (BOOL)changeDatabasePassphrase:(NSString *)oldPassphrase toNewPassphrase:(NSString *)newPassphrase error:(NSError *__autoreleasing*)error;


@end

@interface EncryptedStore (Initialization)
+ (NSPersistentStoreCoordinator *)makeStoreWithOptions:(NSDictionary *)options managedObjectModel:(NSManagedObjectModel *)objModel error:(NSError * __autoreleasing*)error;
+ (NSPersistentStoreCoordinator *)coordinator:(NSPersistentStoreCoordinator *)coordinator byAddingStoreAtURL:(NSURL *)url configuration:(NSString *)configuration options:(NSDictionary *)options error:(NSError * __autoreleasing*)error;
@end

@interface EncryptedStore (Configuration)
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
