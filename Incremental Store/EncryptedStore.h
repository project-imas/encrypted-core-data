// 
// EncryptedStore.h
//
// Copyright 2012 - 2014 The MITRE Corporation, All Rights Reserved.
//
//

#import <sqlite3.h>
#import <objc/runtime.h>
#import <CoreData/CoreData.h>

extern NSString * const EncryptedStoreType;
extern NSString * const EncryptedStorePassphraseKey;
extern NSString * const EncryptedStoreErrorDomain;
extern NSString * const EncryptedStoreErrorMessageKey;
extern NSString * const EncryptedStoreDatabaseLocation;
extern NSString * const EncryptedStoreCacheSize;

@interface EncryptedStore : NSIncrementalStore
+ (NSPersistentStoreCoordinator *)makeStore:(NSManagedObjectModel *) objModel
                                           :(NSString *) passcode;
+ (NSPersistentStoreCoordinator *)makeStoreWithOptions:(NSDictionary *)options managedObjectModel:(NSManagedObjectModel *)objModel;


- (NSNumber *)maximumObjectIDInTable:(NSString *)table;
- (NSDictionary *)whereClauseWithFetchRequest:(NSFetchRequest *)request andContext: (NSManagedObjectContext*) context;
- (void)bindWhereClause:(NSDictionary *)clause toStatement:(sqlite3_stmt *)statement;
- (NSString *)columnsClauseWithProperties:(NSArray *)properties andTableName: (NSString *) tableName;
- (NSString *) joinedTableNameForComponents: (NSArray *) componentsArray forRelationship:(BOOL)forRelationship;
- (id)valueForProperty:(NSPropertyDescription *)property
           inStatement:(sqlite3_stmt *)statement
               atIndex:(int)index
             forEntity:(NSEntityDescription*)entity;
- (NSString *)foreignKeyColumnForRelationshipP:(NSRelationshipDescription *)relationship;
- (NSString *)foreignKeyColumnForRelationship:(NSRelationshipDescription *)relationship;
- (void)bindProperty:(NSPropertyDescription *)property
           withValue:(id)value
              forKey:(NSString *)key
         toStatement:(sqlite3_stmt *)statement
             atIndex:(int)index;


@end
