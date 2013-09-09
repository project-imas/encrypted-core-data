//  Copyright (c) 2012 The MITRE Corporation.

#import <sqlite3.h>
#import <objc/runtime.h>
#import <CoreData/CoreData.h>

extern NSString * const EncryptedStoreType;
extern NSString * const EncryptedStorePassphraseKey;
extern NSString * const EncryptedStoreErrorDomain;
extern NSString * const EncryptedStoreErrorMessageKey;

@interface EncryptedStore : NSIncrementalStore
+ (NSPersistentStoreCoordinator *)makeStore:(NSManagedObjectModel *) objModel
                                           :(NSString *) passcode;
+ (NSPersistentStoreCoordinator *)makeStoreWithDatabaseURL:(NSURL *)databaseURL managedObjectModel:(NSManagedObjectModel *)objModel :(NSString*)passcode;


- (NSNumber *)maximumObjectIDInTable:(NSString *)table;
- (NSDictionary *)whereClauseWithFetchRequest:(NSFetchRequest *)request;
- (void)bindWhereClause:(NSDictionary *)clause toStatement:(sqlite3_stmt *)statement;
- (NSString *)columnsClauseWithProperties:(NSArray *)properties;
- (NSString *) joinedTableNameForComponents: (NSArray *) componentsArray;
- (id)valueForProperty:(NSPropertyDescription *)property
           inStatement:(sqlite3_stmt *)statement
               atIndex:(int)index;
- (NSString *)foreignKeyColumnForRelationshipP:(NSRelationshipDescription *)relationship;
- (NSString *)foreignKeyColumnForRelationship:(NSRelationshipDescription *)relationship;
- (void)bindProperty:(NSPropertyDescription *)property
           withValue:(id)value
              forKey:(NSString *)key
         toStatement:(sqlite3_stmt *)statement
             atIndex:(int)index;


@end
