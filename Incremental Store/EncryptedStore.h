// 
// EncryptedStore.h
//
// Copyright 2012 - 2014 The MITRE Corporation, All Rights Reserved.
//
//

#import <sqlite3.h>
#import <objc/runtime.h>
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


- (NSNumber *)maximumObjectIDInTable:(NSString *)table;
- (NSDictionary *)whereClauseWithFetchRequest:(NSFetchRequest *)request;
- (void)bindWhereClause:(NSDictionary *)clause toStatement:(sqlite3_stmt *)statement;
- (NSString *)columnsClauseWithProperties:(NSArray *)properties;
- (NSString *) joinedTableNameForComponents: (NSArray *) componentsArray forRelationship:(BOOL)forRelationship;
- (id)valueForProperty:(NSPropertyDescription *)property
           inStatement:(sqlite3_stmt *)statement
               atIndex:(int)index;
- (NSString *)foreignKeyColumnForRelationship:(NSRelationshipDescription *)relationship;
- (void)bindProperty:(NSPropertyDescription *)property
           withValue:(id)value
              forKey:(NSString *)key
         toStatement:(sqlite3_stmt *)statement
             atIndex:(int)index;


@end
