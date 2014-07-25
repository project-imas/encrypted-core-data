//
// EncryptedStore.m
//
// Copyright 2012 - 2014 The MITRE Corporation, All Rights Reserved.
//

#if !__has_feature(objc_arc)
#error This class requires ARC.
#endif

#import <sqlite3.h>
#import <objc/runtime.h>

#import "EncryptedStore.h"

NSString * const EncryptedStoreType = @"EncryptedStore";
NSString * const EncryptedStorePassphraseKey = @"EncryptedStorePassphrase";
NSString * const EncryptedStoreErrorDomain = @"EncryptedStoreErrorDomain";
NSString * const EncryptedStoreErrorMessageKey = @"EncryptedStoreErrorMessage";
NSString * const EncryptedStoreDatabaseLocation = @"EncryptedStoreDatabaseLocation";
NSString * const EncryptedStoreCacheSize = @"EncryptedStoreCacheSize";

static NSString * const EncryptedStoreMetadataTableName = @"meta";

#pragma mark - category interfaces

@interface NSArray (EncryptedStoreAdditions)

/*
 
 Creates an array with the given object repeated for the given number of times.
 
 */
+ (NSArray *)cmdArrayWithObject:(id<NSCopying>)object times:(NSUInteger)times;

/*
 
 Mirrors the Ruby Array collect method. Iterates over the receiver's contents
 and calls the given block with each object collecting the return value in
 a new array.
 
 */
- (NSArray *)cmdCollect:(id (^) (id object))block;

/*
 
 Recursively flattens the receiver. Any object that is another array inside
 the receiver has its contents flattened and added as siblings to all
 other objects.
 
 */
- (NSArray *)cmdFlatten;

@end

@interface CMDIncrementalStoreNode : NSIncrementalStoreNode

@property (nonatomic) NSArray * allProperties;

- (id)initWithObjectID:(NSManagedObjectID *)objectID
            withValues:(NSDictionary *)values version:(uint64_t)version
        withProperties:(NSArray *)properties;

- (void)updateWithChangedValues:(NSDictionary *)changedValues;


@end

@implementation EncryptedStore {
    
    // database resources
    sqlite3 *database;
    
    // cache money
    NSMutableDictionary *objectIDCache;
    NSMutableDictionary *nodeCache;
    NSMutableDictionary *objectCountCache;
    NSMutableDictionary *entityTypeCache;
    
}

+ (NSPersistentStoreCoordinator *)makeStoreWithOptions:(NSDictionary *)options managedObjectModel:(NSManagedObjectModel *)objModel
{
    NSPersistentStoreCoordinator * persistentCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:objModel];
    
    //  NSString* appSupportDir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    
    NSURL *databaseURL;
    if([options objectForKey:EncryptedStoreDatabaseLocation] != nil) {
        databaseURL = [[NSURL alloc] initFileURLWithPath:[options objectForKey:EncryptedStoreDatabaseLocation]];
    } else {
        NSString *dbName = NSBundle.mainBundle.infoDictionary [@"CFBundleDisplayName"];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSURL *applicationSupportURL = [[fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
        [fileManager createDirectoryAtURL:applicationSupportURL withIntermediateDirectories:NO attributes:nil error:nil];
        databaseURL = [applicationSupportURL URLByAppendingPathComponent:[dbName stringByAppendingString:@".sqlite"]];
    }
    
    NSError *error = nil;
    NSPersistentStore *store = [persistentCoordinator
                                addPersistentStoreWithType:EncryptedStoreType
                                configuration:nil
                                URL:databaseURL
                                options:options
                                error:&error];
    NSAssert(store, @"Unable to add persistent store\n%@", error);
    return persistentCoordinator;
}

+ (NSPersistentStoreCoordinator *)makeStore:(NSManagedObjectModel *)objModel :(NSString *)passcode
{
    NSDictionary *options = @{ EncryptedStorePassphraseKey : passcode };
    
    return [self makeStoreWithOptions:options managedObjectModel:objModel];
}

+ (void)load {
    @autoreleasepool {
        [NSPersistentStoreCoordinator
         registerStoreClass:[EncryptedStore class]
         forStoreType:EncryptedStoreType];
    }
}

#pragma mark - incremental store functions

- (id)initWithPersistentStoreCoordinator:(NSPersistentStoreCoordinator *)root
                       configurationName:(NSString *)name
                                     URL:(NSURL *)URL
                                 options:(NSDictionary *)options {
    self = [super initWithPersistentStoreCoordinator:root configurationName:name URL:URL options:options];
    if (self) {
        objectIDCache = [NSMutableDictionary dictionary];
        objectCountCache = [NSMutableDictionary dictionary];
        nodeCache = [NSMutableDictionary dictionary];
        entityTypeCache = [NSMutableDictionary dictionary];
        for (NSEntityDescription * entity in root.managedObjectModel.entities) {
            if (entity.superentity || entity.subentities.count > 0) {
                [entityTypeCache setObject:entity forKey:@(entity.name.hash)];
            }
        }
        database = NULL;
    }
    return self;
}

- (void)dealloc {
    sqlite3_close(database);
    database = NULL;
}

- (NSArray *)obtainPermanentIDsForObjects:(NSArray *)array error:(NSError **)error {
    NSMutableArray *__block objectIDs = [NSMutableArray arrayWithCapacity:[array count]];
    [array enumerateObjectsUsingBlock:^(NSManagedObject *obj, NSUInteger idx, BOOL *stop) {
        NSManagedObjectID *objectID = [obj objectID];
        
        if ([objectID isTemporaryID]) {
            NSEntityDescription *entity = [obj entity];
            NSString *table = [self tableNameForEntity:entity];
            NSNumber *value = [self maximumObjectIDInTable:table];
            if (value == nil) {
                if (error) { *error = [self databaseError]; }
                *stop = YES;
                objectIDs = nil;
                return;
            }
            objectID = [self newObjectIDForEntity:entity referenceObject:value];
        }
        
        [objectIDs addObject:objectID];
    }];
    return objectIDs;
}

- (id)executeRequest:(NSPersistentStoreRequest *)request
         withContext:(NSManagedObjectContext *)context
               error:(NSError **)error {
    
    if ([request requestType] == NSFetchRequestType) {
        
        // prepare values
        NSFetchRequest *fetchRequest = (id)request;
        NSEntityDescription *entity = [fetchRequest entity];
        NSFetchRequestResultType type = [fetchRequest resultType];
        NSMutableArray *results = [NSMutableArray array];
        NSString * joinStatement = [self getJoinClause:fetchRequest];
        
        NSString *table = [self tableNameForEntity:entity];
        NSDictionary *condition = [self whereClauseWithFetchRequest:fetchRequest andContext: context];
        NSDictionary *ordering = [self orderClause:fetchRequest forEntity:entity];
        NSString *limit = ([fetchRequest fetchLimit] > 0 ? [NSString stringWithFormat:@" LIMIT %ld", (unsigned long)[fetchRequest fetchLimit]] : @"");
        BOOL isDistinctFetchEnabled = [fetchRequest returnsDistinctResults];
        
        // NOTE: this would probably clash with DISTINCT
        // Disable the combination for now until we can figure out a way to handle both and
        // have a proper test case
        BOOL shouldFetchEntityType = (entity.subentities.count > 0 || entity.superentity) && !isDistinctFetchEnabled;
        // return objects or ids
        if (type == NSManagedObjectResultType || type == NSManagedObjectIDResultType) {
            NSString *string = [NSString stringWithFormat:
                                @"SELECT %@%@.__objectID%@ FROM %@ %@%@%@%@;",
                                (isDistinctFetchEnabled)?@"DISTINCT ":@"",
                                table,
                                (shouldFetchEntityType)?[NSString stringWithFormat:@", %@._entityType", table]:@"",
                                table,
                                joinStatement,
                                [condition objectForKey:@"query"],
                                [ordering objectForKey:@"order"],
                                limit];
            NSRange endHavingRange = [string rangeOfString:@"END_HAVING"];
            if(endHavingRange.location != NSNotFound) { // String manipulation to handle SUM
                // Between HAVING and END_HAVING
                NSRange havingRange = [string rangeOfString:@"HAVING"];
                int length = endHavingRange.location - havingRange.location;
                int location = havingRange.location;
                NSRange substrRange = NSMakeRange(location,length);
                
                NSInteger endHavingEnd = endHavingRange.location + endHavingRange.length;
                NSString *groupHaving = [NSString stringWithFormat: @" GROUP BY %@.__objectID %@ %@", table, [string substringWithRange:substrRange], [string substringWithRange:NSMakeRange(endHavingEnd, [string length] - endHavingEnd)]];
                
                // Rebuild entire SQL string
                string = [NSString stringWithFormat:
                          @"SELECT %@%@.__objectID%@ FROM %@ %@%@%@%@;",
                          (isDistinctFetchEnabled)?@"DISTINCT ":@"",
                          table,
                          (shouldFetchEntityType)?[NSString stringWithFormat:@", %@._entityType", table]:@"",
                          table,
                          joinStatement,
                          groupHaving,
                          [ordering objectForKey:@"order"],
                          limit];
            }

            sqlite3_stmt *statement = [self preparedStatementForQuery:string];
            [self bindWhereClause:condition toStatement:statement];
            while (sqlite3_step(statement) == SQLITE_ROW) {
                unsigned long long primaryKey = sqlite3_column_int64(statement, 0);
                NSEntityDescription * entityToFecth = nil;
                if (shouldFetchEntityType) {
                    NSUInteger entityType = sqlite3_column_int(statement, 1);
                    entityToFecth = [entityTypeCache objectForKey:@(entityType)];
                }
                if (!entityToFecth) {
                    entityToFecth = entity;
                }
                NSManagedObjectID *objectID = [self newObjectIDForEntity:entityToFecth referenceObject:@(primaryKey)];
                if (type == NSManagedObjectIDResultType) { [results addObject:objectID]; }
                else {
                    id object = [context objectWithID:objectID];
                    [results addObject:object];
                }
            }
            if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK) {
                if (error) { *error = [self databaseError]; }
                return nil;
            }
        }
        
        // return fetched dictionaries
        if (type == NSDictionaryResultType && [[fetchRequest propertiesToFetch] count] > 0) {
            BOOL isDistinctFetchEnabled = [fetchRequest returnsDistinctResults];
            NSArray * propertiesToFetch = [fetchRequest propertiesToFetch];
            NSString * propertiesToFetchString = [self columnsClauseWithProperties:propertiesToFetch andTableName:table];
            NSArray * propertiesToGroupBy = [fetchRequest propertiesToGroupBy];
            NSString * propertiesToGroupByString;
            if(propertiesToGroupBy.count)
                propertiesToGroupByString = [NSString stringWithFormat: @" GROUP BY %@ ",[self columnsClauseWithProperties: propertiesToGroupBy andTableName:table]];
            else
                propertiesToGroupByString = @"";
            // TODO: Need a test case to reach here, or remove it entirely
            // NOTE - this now supports joins but in a limited fashion. It will successfully
            // retrieve properties that are to-one relationships
            
            NSString *string = [NSString stringWithFormat:
                                @"SELECT %@%@ FROM %@ %@%@%@%@%@;",
                                (isDistinctFetchEnabled) ? @"DISTINCT ":@"",
                                propertiesToFetchString,
                                table,
                                joinStatement,
                                [condition objectForKey:@"query"],
                                propertiesToGroupByString,
                                [ordering objectForKey:@"order"],
                                limit];
            sqlite3_stmt *statement = [self preparedStatementForQuery:string];
            [self bindWhereClause:condition toStatement:statement];
            while (sqlite3_step(statement) == SQLITE_ROW) {
                NSMutableDictionary* singleResult = [NSMutableDictionary dictionary];
                [propertiesToFetch enumerateObjectsUsingBlock:^(id property, NSUInteger idx, BOOL *stop) {
                    id value = [self valueForProperty:property inStatement:statement atIndex:idx forEntity: fetchRequest.entity];
                    if (value)
                    {
                        [singleResult setValue:value forKey:[property name]];
                    }
                }];
                [results addObject:singleResult];
            }
            if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK) {
                if (error) { *error = [self databaseError]; }
                return nil;
            }
        }
        
        // return a count
        else if (type == NSCountResultType) {
            NSString *string = [NSString stringWithFormat:
                                @"SELECT COUNT(*) FROM %@ %@%@%@;",
                                table,
                                joinStatement,
                                [condition objectForKey:@"query"],
                                limit];
            sqlite3_stmt *statement = [self preparedStatementForQuery:string];
            [self bindWhereClause:condition toStatement:statement];
            if (sqlite3_step(statement) == SQLITE_ROW) {
                unsigned long long count = sqlite3_column_int64(statement, 0);
                [results addObject:@(count)];
            }
            if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK) {
                if (error) { *error = [self databaseError]; }
                return nil;
            }
        }
        
        // return
        return results;
        
    }
    else if ([request requestType] == NSSaveRequestType) {
        return [self handleSaveChangesRequest:(id)request error:error];
    }
    return nil;
}

- (NSIncrementalStoreNode *)newValuesForObjectWithID:(NSManagedObjectID *)objectID
                                         withContext:(NSManagedObjectContext *)context
                                               error:(NSError **)error {
    
    // cache hit
    {
        NSIncrementalStoreNode *node = [nodeCache objectForKey:objectID];
        if (node) { return node; }
    }
    
    // prepare values
    NSEntityDescription *entity = [objectID entity];
    NSMutableArray *columns = [NSMutableArray array];
    NSMutableArray *keys = [NSMutableArray array];
    unsigned long long primaryKey = [[self referenceObjectForObjectID:objectID] unsignedLongLongValue];
    
    // enumerate properties
    NSDictionary *properties = [entity propertiesByName];
    [properties enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if ([obj isKindOfClass:[NSAttributeDescription class]]) {
            NSString *quotedKey = [NSString stringWithFormat:@"`%@`", key];
            [columns addObject:quotedKey];
            [keys addObject:key];
        }
        else if ([obj isKindOfClass:[NSRelationshipDescription class]]) {
//            NSRelationshipDescription *inverse = [obj inverseRelationship];
            
            // Handle one-to-many and one-to-one
            if (![obj isToMany]) {
                NSString *column = [self foreignKeyColumnForRelationship:obj];
                NSString *quotedColumn = [NSString stringWithFormat:@"`%@`", column];
                [columns addObject:quotedColumn];
                [keys addObject:key];
            }
            
        }
    }];
    
    // prepare query
    NSString *string = [NSString stringWithFormat:
                        @"SELECT %@ FROM %@ WHERE __objectID=?;",
                        [columns componentsJoinedByString:@", "],
                        [self tableNameForEntity:entity]];
    sqlite3_stmt *statement = [self preparedStatementForQuery:string];
    
    // run query
    sqlite3_bind_int64(statement, 1, primaryKey);
    if (sqlite3_step(statement) == SQLITE_ROW) {
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
        NSMutableArray * allProperties = [NSMutableArray new];
        NSEntityDescription *entityDescription = objectID.entity;
        [keys enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSPropertyDescription *property = [properties objectForKey:obj];
            id value = [self valueForProperty:property inStatement:statement atIndex:idx forEntity:entityDescription];
            if (value) {
                [dictionary setObject:value forKey:obj];
                [allProperties addObject:property];
            }
        }];
        sqlite3_finalize(statement);
        NSIncrementalStoreNode *node = [[CMDIncrementalStoreNode alloc]
                                        initWithObjectID:objectID
                                        withValues:dictionary
                                        version:1
                                        withProperties:allProperties];
        [nodeCache setObject:node forKey:objectID];
        return node;
    }
    else {
        if (error) { *error = [self databaseError]; }
        sqlite3_finalize(statement);
        return nil;
    }
    
}

- (id)newValueForRelationship:(NSRelationshipDescription *)relationship
              forObjectWithID:(NSManagedObjectID *)objectID
                  withContext:(NSManagedObjectContext *)context
                        error:(NSError **)error {
    
    // prepare values
    unsigned long long key = [[self referenceObjectForObjectID:objectID] unsignedLongLongValue];
    NSEntityDescription *sourceEntity = [objectID entity];
    NSRelationshipDescription *inverseRelationship = [relationship inverseRelationship];
    NSEntityDescription *destinationEntity = [relationship destinationEntity];
    sqlite3_stmt *statement = NULL;
    
    if (![relationship isToMany]) {
        // to-one relationship, foreign key exists in source entity table
        
        NSString *string = [NSString stringWithFormat:
                            @"SELECT %@ FROM %@ WHERE __objectID=?",
                            [self foreignKeyColumnForRelationship:relationship],
                            [self tableNameForEntity:sourceEntity]];
        statement = [self preparedStatementForQuery:string];
        sqlite3_bind_int64(statement, 1, key);
        
    } else if ([relationship isToMany] && [inverseRelationship isToMany]) {
        // many-to-many relationship, foreign key exists in relation table
        
        NSString *string = [NSString stringWithFormat:
                            @"SELECT %@__objectid FROM %@ WHERE %@__objectid=?",
                            [destinationEntity name],
                            [self tableNameForRelationship:relationship],
                            [sourceEntity name]];
        statement = [self preparedStatementForQuery:string];
        sqlite3_bind_int64(statement, 1, key);
        
    } else {
        // one-to-many relationship, foreign key exists in desination entity table
        
        NSString *string = [NSString stringWithFormat:
                            @"SELECT __objectID FROM %@ WHERE %@=?",
                            [self tableNameForEntity:destinationEntity],
                            [self foreignKeyColumnForRelationship:inverseRelationship]];
        statement = [self preparedStatementForQuery:string];
        sqlite3_bind_int64(statement, 1, key);
    }
    
    // run query
    NSMutableArray *objectIDs = [NSMutableArray array];
    while (sqlite3_step(statement) == SQLITE_ROW) {
        if (sqlite3_column_type(statement, 0) != SQLITE_NULL) {
            NSNumber *value = @(sqlite3_column_int64(statement, 0));
            [objectIDs addObject:[self newObjectIDForEntity:destinationEntity referenceObject:value]];
        }
    }
    
    // error case
    if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK) {
        if (error) { *error = [self databaseError]; }
        return nil;
    }
    
    // to-many relationship
    if ([relationship isToMany]) {
        return objectIDs;
    }
    
    // null to-one relationship
    else if ([objectIDs count] == 0) {
        return [NSNull null];
    }
    
    // satisfied to-one relationship
    else {
        //return objectIDs;
        
        return [objectIDs lastObject];
    }
    
}

- (void)managedObjectContextDidRegisterObjectsWithIDs:(NSArray *)objectIDs {
    [objectIDs enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSUInteger value = [[objectCountCache objectForKey:obj] unsignedIntegerValue];
        [objectCountCache setObject:@(value + 1) forKey:obj];
    }];
}

- (void)managedObjectContextDidUnregisterObjectsWithIDs:(NSArray *)objectIDs {
    [objectIDs enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSNumber *value = [objectCountCache objectForKey:obj];
        if (value) {
            NSUInteger newValue = ([value unsignedIntegerValue] - 1);
            if (newValue == 0) {
                [objectCountCache removeObjectForKey:obj];
                [nodeCache removeObjectForKey:obj];
            }
            else { [objectCountCache setObject:@(newValue) forKey:obj]; }
        }
    }];
}

- (NSString *)type {
    return EncryptedStoreType;
}

#pragma mark - metadata helpers

- (BOOL)loadMetadata:(NSError **)error {
    if (sqlite3_open([[[self URL] path] UTF8String], &database) == SQLITE_OK) {
        
        // passphrase
        if (![self configureDatabasePassphrase]) {
            if (error) { *error = [self databaseError]; }
            sqlite3_close(database);
            database = NULL;
            return NO;
        }
        
        // load metadata
        BOOL success = [self performInTransaction:^{
            
            //enable regexp
            sqlite3_create_function(database, "REGEXP", 2, SQLITE_ANY, NULL, (void *)dbsqliteRegExp, NULL, NULL);
            
            // ask if we have a metadata table
            BOOL hasTable = NO;
            if (![self hasMetadataTable:&hasTable error:error]) { return NO; }
            
            // load existing metadata and optionally run migrations
            if (hasTable) {
                
                // load
                NSDictionary *metadata = nil;
                NSString *string = [NSString stringWithFormat:
                                    @"SELECT plist FROM %@ LIMIT 1;",
                                    EncryptedStoreMetadataTableName];
                sqlite3_stmt *statement = [self preparedStatementForQuery:string];
                if (statement != NULL && sqlite3_step(statement) == SQLITE_ROW) {
                    const void *bytes = sqlite3_column_blob(statement, 0);
                    unsigned int length = sqlite3_column_bytes(statement, 0);
                    NSData *data = [NSData dataWithBytes:bytes length:length];
                    metadata = [NSKeyedUnarchiver unarchiveObjectWithData:data];
                    [self setMetadata:metadata];
                }
                else {
                    if (error) { *error = [self databaseError]; }
                    sqlite3_finalize(statement);
                    return NO;
                }
                sqlite3_finalize(statement);
                
                // run migrations
                NSDictionary *options = [self options];
                if ([[options objectForKey:NSMigratePersistentStoresAutomaticallyOption] boolValue] &&
                    [[options objectForKey:NSInferMappingModelAutomaticallyOption] boolValue]) {
                    NSMutableArray *bundles = [NSMutableArray array];
                    [bundles addObjectsFromArray:[NSBundle allBundles]];
                    [bundles addObjectsFromArray:[NSBundle allFrameworks]];
                    NSManagedObjectModel *oldModel = [NSManagedObjectModel
                                                      mergedModelFromBundles:bundles
                                                      forStoreMetadata:metadata];
                    NSManagedObjectModel *newModel = [[self persistentStoreCoordinator] managedObjectModel];
                    if (oldModel && newModel && ![oldModel isEqual:newModel]) {
                        
                        // run migrations
                        if (![self migrateFromModel:oldModel toModel:newModel error:error]) {
                            return NO;
                        }
                        
                        // update metadata
                        NSMutableDictionary *mutableMetadata = [metadata mutableCopy];
                        [mutableMetadata setObject:[newModel entityVersionHashesByName] forKey:NSStoreModelVersionHashesKey];
                        [self setMetadata:mutableMetadata];
                        if (![self saveMetadata]) {
                            if (error) { *error = [self databaseError]; }
                            return NO;
                        }
                        
                    } else {
						NSLog(@"Failed to create NSManagedObject models for migration.");
						return NO;
					}
                }
                
            }
            
            // this is a new store
            else {
                // create table
                NSString *string = [NSString stringWithFormat:
                                    @"CREATE TABLE %@(plist);",
                                    EncryptedStoreMetadataTableName];
                sqlite3_stmt *statement = [self preparedStatementForQuery:string];
                sqlite3_step(statement);
                if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK) {
                    if (error) { *error = [self databaseError]; }
                    return NO;
                }
                
                // run migrations
                NSManagedObjectModel *model = [[self persistentStoreCoordinator] managedObjectModel];
                if (![self initializeDatabaseWithModel:model error:error]) {
                    return NO;
                }
                
                // create and set metadata
                NSDictionary *metadata = @{
                                           NSStoreUUIDKey : [[self class] identifierForNewStoreAtURL:[self URL]],
                                           NSStoreTypeKey : [self type]
                                           };
                [self setMetadata:metadata];
                if (![self saveMetadata]) {
                    if (error) { *error = [self databaseError]; }
                    return NO;
                }
            }
            
            // worked
            return YES;
            
        }];
        
        // finish up
        if (success) { return success; }
        
    }
    
    // load failed
    if (error) { *error = [self databaseError]; }
    sqlite3_close(database);
    database = NULL;
    return NO;
    
}

- (BOOL)hasMetadataTable:(BOOL *)hasTable error:(NSError **)error {
    return [self hasTable:hasTable withName:EncryptedStoreMetadataTableName error:error];
}

- (BOOL)saveMetadata {
    static NSString * const kSQL_DELETE = @"DELETE FROM %@;";
    static NSString * const kSQL_INSERT = @"INSERT INTO %@ (plist) VALUES(?);";
    NSString *string;
    sqlite3_stmt *statement;
    
    // delete
    string = [NSString stringWithFormat:kSQL_DELETE,EncryptedStoreMetadataTableName];
    statement = [self preparedStatementForQuery:string];
    sqlite3_step(statement);
    if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK) { return NO; }
    
    // save
    string = [NSString stringWithFormat:kSQL_INSERT,EncryptedStoreMetadataTableName];
    statement = [self preparedStatementForQuery:string];
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:[self metadata]];
    sqlite3_bind_blob(statement, 1, [data bytes], [data length], SQLITE_TRANSIENT);
    sqlite3_step(statement);
    if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK) { return NO; }
    
    return YES;
}

#pragma mark - passphrase

- (BOOL)configureDatabasePassphrase {
    NSString *passphrase = [[self options] objectForKey:EncryptedStorePassphraseKey];
    NSNumber *cacheSize = [[self options] objectForKey:EncryptedStoreCacheSize];
    
    if (passphrase == nil) return NO;
    const char *string = [passphrase UTF8String];
    int status = sqlite3_key(database, string, strlen(string));
    string = NULL;
    passphrase = nil;
    if(cacheSize != nil){
        NSString *string = [NSString stringWithFormat:@"PRAGMA cache_size = %d;", [cacheSize intValue]];
        sqlite3_stmt *statement = [self preparedStatementForQuery:string];
        sqlite3_step(statement);
        
        if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK){
            // TO-DO: handle error with statement
            NSLog(@"Error: statement is NULL or could not be finalized");
            return NO;
        } else {
            // prepare another pragma cache_size statement and compare actual cache size
            NSString *string = @"PRAGMA cache_size;";
            sqlite3_stmt *checkStatement = [self preparedStatementForQuery:string];
            sqlite3_step(checkStatement);
            int actualCacheSize = sqlite3_column_int(checkStatement,0);
            if(actualCacheSize == [cacheSize intValue]) {
                // succeeded
                NSLog(@"Cache size successfully set to %d", actualCacheSize);
            } else {
                // failed...
                NSLog(@"Error: cache size set to %d, not %d", actualCacheSize, [cacheSize intValue]);
                return NO;
            }
        }
    }
    return (status == SQLITE_OK);
}

#pragma mark - user functions

static void dbsqliteRegExp(sqlite3_context *context, int argc, const char **argv) {
    NSUInteger numberOfMatches = 0;
    NSString *pattern, *string;
    
    if (argc == 2) {
        
        const char *aux = (const char *)sqlite3_value_text((sqlite3_value*)argv[0]);
        
        pattern = [NSString stringWithUTF8String:aux];
        
        aux     = (const char *)sqlite3_value_text((sqlite3_value*)argv[1]);
        
        string  = [NSString stringWithUTF8String:aux];
        
        if(pattern != nil && string != nil){
            NSError *error;
            NSRegularExpression *regex = [NSRegularExpression
                                          regularExpressionWithPattern:pattern
                                          options:NSRegularExpressionCaseInsensitive
                                          error:&error];
            
            if(error == nil){
                numberOfMatches = [regex numberOfMatchesInString:string
                                                         options:0
                                                           range:NSMakeRange(0, [string length])];
            }
        }
	}
    
	(void)sqlite3_result_int(context, numberOfMatches);
}

#pragma mark - migration helpers

- (BOOL)migrateFromModel:(NSManagedObjectModel *)fromModel toModel:(NSManagedObjectModel *)toModel error:(NSError **)error {
    BOOL __block succuess = YES;
    
    // generate mapping model
    NSMappingModel *mappingModel = [NSMappingModel
                                    inferredMappingModelForSourceModel:fromModel
                                    destinationModel:toModel
                                    error:error];
    if (mappingModel == nil) { return NO; }
    
    // grab entity snapshots
    NSDictionary *sourceEntities = [fromModel entitiesByName];
    NSDictionary *destinationEntities = [toModel entitiesByName];
    
    // enumerate over entities
    [[mappingModel entityMappings] enumerateObjectsUsingBlock:^(NSEntityMapping *entityMapping, NSUInteger idx, BOOL *stop) {
        
        // get names
        NSString *sourceEntityName = [entityMapping sourceEntityName];
        NSString *destinationEntityName = [entityMapping destinationEntityName];
        
        // get entity descriptions
        NSEntityDescription *sourceEntity = [sourceEntities objectForKey:sourceEntityName];
        NSEntityDescription *destinationEntity = [destinationEntities objectForKey:destinationEntityName];
        
        // get mapping type
        NSEntityMappingType type = [entityMapping mappingType];
        
        // add a new entity from final snapshot
        if (type == NSAddEntityMappingType) {
            succuess = [self createTableForEntity:destinationEntity error:error];
        }
        
        // drop table for deleted entity
        else if (type == NSRemoveEntityMappingType) {
            succuess = [self dropTableForEntity:sourceEntity];
        }
        
        // change an entity
        else if (type == NSTransformEntityMappingType) {
            succuess = [self
                        alterTableForSourceEntity:sourceEntity
                        destinationEntity:destinationEntity
                        withMapping:entityMapping
                        error:error];
        }
        
        if (!succuess) { *stop = YES; }
    }];
    
    return succuess;
}

- (BOOL)initializeDatabaseWithModel:(NSManagedObjectModel *)model error:(NSError**)error {
    BOOL __block success = YES;
    NSMutableSet *manytomanys = [NSMutableSet set];
    
    if (success) {
        [[model entities] enumerateObjectsUsingBlock:^(NSEntityDescription *entity, NSUInteger idx, BOOL *stop) {
            if (![self createTableForEntity:entity error:error]) {
                success = NO;
                *stop = YES;
            }
            
            NSDictionary *relations = [entity relationshipsByName];
            for (NSString *key in relations) {
                NSRelationshipDescription *relation = [relations objectForKey:key];
                NSRelationshipDescription *inverse = [relation inverseRelationship];
                if ([relation isToMany] && [inverse isToMany] && ![manytomanys containsObject:inverse]) {
                    [manytomanys addObject:relation];
                }
            }
        }];
    }
    
    if (success) {
        for (NSRelationshipDescription *rel in manytomanys) {
            if (![self createTableForRelationship:rel error:error]) {
                success = NO;
                break;
            }
        }
    }
    
    return success;
}

- (NSArray*)entityIdsForEntity:(NSEntityDescription*)entity {
    NSMutableArray *entityIds = [NSMutableArray arrayWithObject:@(entity.name.hash)];
    
    for (NSEntityDescription *subentity in entity.subentities) {
        [entityIds addObjectsFromArray:[self entityIdsForEntity:subentity]];
    }
    
    return entityIds;
}

- (NSArray*)columnNamesForEntity:(NSEntityDescription*)entity
                     indexedOnly:(BOOL)indexedOnly
                     quotedNames:(BOOL)quotedNames {
    
    NSMutableSet *columns = [NSMutableSet setWithCapacity:entity.properties.count];
    
    [[entity attributesByName] enumerateKeysAndObjectsUsingBlock:^(NSString * name, NSAttributeDescription * description, BOOL * stop) {
        if (!indexedOnly || description.isIndexed) {
            if (quotedNames) {
                [columns addObject:[NSString stringWithFormat:@"'%@'", name]];
            } else {
                [columns addObject:name];
            }
        }
    }];
    
    [[entity relationshipsByName] enumerateKeysAndObjectsUsingBlock:^(NSString * name, NSRelationshipDescription * description, BOOL *stop) {
        // NOTE: all joins get indexed
        // handle *-to-one
        // NOTE: hack - include many to many because we generate erroneous where clauses
        // for those that will fail if we don't include them here
        if ([description isToMany]){// && !description.inverseRelationship.isToMany)) {
            return;
        }
        NSString * column;
        if (quotedNames) {
            column = [NSString stringWithFormat:@"'%@'", [self foreignKeyColumnForRelationship:description]];
        } else {
            column = [self foreignKeyColumnForRelationship:description];
        }
        [columns addObject:column];
    }];
    
    for (NSEntityDescription *subentity in entity.subentities) {
        [columns addObjectsFromArray:[self columnNamesForEntity:subentity
                                                    indexedOnly:indexedOnly
                                                    quotedNames:quotedNames]];
    }
    
    return [columns allObjects];
}

- (BOOL)createTableForEntity:(NSEntityDescription *)entity error:(NSError**)error {
    // Skip sub-entities since the super-entities should handle
    // creating columns for all their children.
    if (entity.superentity) {
        return YES;
    }
    
    // prepare columns
    NSMutableArray *columns = [NSMutableArray arrayWithObject:@"'__objectid' integer primary key"];
    if (entity.subentities.count > 0) {
        // NOTE: Will use '-[NSString hash]' to determine the entity type so we can use
        //       faster integer-indexed queries.  Any string greater than 96-chars is
        //       not guaranteed to produce a unique hash value, but for entity names that
        //       shouldn't be a problem.
        [columns addObject:@"'_entityType' integer"];
    }
    
    [columns addObjectsFromArray:[self columnNamesForEntity:entity indexedOnly:NO quotedNames:YES]];
    
    // create table
    NSString *string = [NSString stringWithFormat:
                        @"CREATE TABLE %@ (%@);",
                        [self tableNameForEntity:entity],
                        [columns componentsJoinedByString:@", "]];
    sqlite3_stmt *statement = [self preparedStatementForQuery:string];
    sqlite3_step(statement);
    
    BOOL result = (statement != NULL && sqlite3_finalize(statement) == SQLITE_OK);
    if (!result) {
        *error = [self databaseError];
        return result;
    }
    
    
    return [self createIndicesForEntity:entity error:error];
}

- (BOOL)createIndicesForEntity:(NSEntityDescription *)entity error:(NSError **)error
{
    if (entity.superentity) {
        return YES;
    }
    
    NSArray * indexedColumns = [self columnNamesForEntity:entity indexedOnly:YES quotedNames:NO];
    NSString * tableName = [self tableNameForEntity:entity];
    for (NSString * column in indexedColumns) {
        NSString * query = [NSString stringWithFormat:
                            @"CREATE INDEX %@_%@_INDEX ON %@ (%@)",
                            tableName,
                            column,
                            tableName,
                            column];
        sqlite3_stmt *statement = [self preparedStatementForQuery:query];
        sqlite3_step(statement);
        BOOL result = (statement != NULL && sqlite3_finalize(statement) == SQLITE_OK);
        if (!result) {
            *error = [self databaseError];
            return result;
        }
    }
    return YES;
}

- (BOOL)dropTableForEntity:(NSEntityDescription *)entity {
    NSString *name = [self tableNameForEntity:entity];
    return [self dropTableNamed:name];
}

- (BOOL)dropTableNamed:(NSString *)name {
    NSString *string = [NSString stringWithFormat:
                        @"DROP TABLE %@;",
                        name];
    sqlite3_stmt *statement = [self preparedStatementForQuery:string];
    sqlite3_step(statement);
    return (statement != NULL && sqlite3_finalize(statement) == SQLITE_OK);
}

- (BOOL)alterTableForSourceEntity:(NSEntityDescription *)sourceEntity
                destinationEntity:(NSEntityDescription *)destinationEntity
                      withMapping:(NSEntityMapping *)mapping
                            error:(NSError**)error {
    NSString *string;
    sqlite3_stmt *statement;
    NSString *sourceEntityName = [NSString stringWithFormat:@"ecd%@", [sourceEntity name]];
    NSString *temporaryTableName = [NSString stringWithFormat:@"_T_%@", sourceEntityName];
    NSString *destinationTableName = [NSString stringWithFormat:@"ecd%@", [destinationEntity name]];
    
    // move existing table to temporary new table
    string = [NSString stringWithFormat:
              @"ALTER TABLE %@ "
              @"RENAME TO %@;",
              sourceEntityName,
              temporaryTableName];
    statement = [self preparedStatementForQuery:string];
    sqlite3_step(statement);
    if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK) {
        return NO;
    }
    
    // create new table
    // TODO - add some tests around this. I think with a child entity
    // this won't actually create a table and the above initialized
    // destinationTableName will be wrong. It should be the table name
    // of the root entity in the inheritance tree.
    // Some work should be done to ensure that we work with the
    // correct table even if the migration only involves child
    // entities.
    if (![self createTableForEntity:destinationEntity error:error]) {
        return NO;
    }
    
    // get columns
    NSMutableArray *sourceColumns = [NSMutableArray array];
    NSMutableArray *destinationColumns = [NSMutableArray array];
    [[mapping attributeMappings] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSExpression *expression = [obj valueExpression];
        if (expression != nil) {
            [destinationColumns addObject:[NSString stringWithFormat:@"'%@'", [obj name]]];
            NSString *source = [[[expression arguments] objectAtIndex:0] constantValue];
            [sourceColumns addObject:source];
        }
    }];
    //    [[mapping relationshipMappings] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
    //        NSExpression *expression = [obj valueExpression];
    //        if (expression != nil) {
    //            NSString *destination = [self foreignKeyColumnWithName:[obj name]];
    //            [destinationColumns addObject:destination];
    //            NSString *source = [[[expression arguments] objectAtIndex:0] constantValue];
    //            source = [self foreignKeyColumnWithName:source];
    //            [sourceColumns addObject:source];
    //        }
    //    }];
    
    // copy data
    if (destinationEntity.subentities.count > 0) {
        string = [NSString stringWithFormat:
                  @"INSERT INTO %@ ('_entityType', %@)"
                  @"SELECT %u, %@ "
                  @"FROM %@",
                  destinationTableName,
                  [destinationColumns componentsJoinedByString:@", "],
                  destinationEntity.name.hash,
                  [sourceColumns componentsJoinedByString:@", "],
                  temporaryTableName];
    } else {
        string = [NSString stringWithFormat:
                  @"INSERT INTO %@ (%@)"
                  @"SELECT %@ "
                  @"FROM %@",
                  destinationTableName,
                  [destinationColumns componentsJoinedByString:@", "],
                  [sourceColumns componentsJoinedByString:@", "],
                  temporaryTableName];
        
    }
    statement = [self preparedStatementForQuery:string];
    sqlite3_step(statement);
    if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK) {
        return NO;
    }
    
    // delete old table
    if (![self dropTableNamed:temporaryTableName]) {
        return NO;
    }
    
    return YES;
}

- (BOOL)createTableForRelationship:(NSRelationshipDescription *)relationship error:(NSError **)error {
    // create table
    NSArray *columns = [self columnNamesForRelationship:relationship withQuotes:YES];
    NSString *string = [NSString stringWithFormat:
                        @"CREATE TABLE %@ (%@ INTEGER NOT NULL, %@ INTEGER NOT NULL, PRIMARY KEY(%@));",
                        [self tableNameForRelationship:relationship],
                        [columns objectAtIndex:0], [columns objectAtIndex:1],
                        [columns componentsJoinedByString:@", "]];
    sqlite3_stmt *statement = [self preparedStatementForQuery:string];
    sqlite3_step(statement);
    
    BOOL result = (statement != NULL && sqlite3_finalize(statement) == SQLITE_OK);
    if (!result) {
        *error = [self databaseError];
        return result;
    }
    return YES;
}

-(NSString *)tableNameForRelationship:(NSRelationshipDescription *)relationship {
    NSRelationshipDescription *inverse = [relationship inverseRelationship];
    NSArray *names = [@[[relationship name],[inverse name]] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    return [NSString stringWithFormat:@"ecd_%@",[names componentsJoinedByString:@"_"]];
}

-(NSArray *)columnNamesForRelationship:(NSRelationshipDescription *)relationship withQuotes:(BOOL)withQuotes {
    NSRelationshipDescription *inverse = [relationship inverseRelationship];
    NSArray *names = [@[[relationship name], [inverse name]] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    if (withQuotes) {
        if ([[names objectAtIndex:0] isEqualToString:[relationship name]]) {
            return @[[NSString stringWithFormat:@"'%@__objectid'",[[inverse entity] name]],
                     [NSString stringWithFormat:@"'%@__objectid'",[[relationship entity] name]]];
        } else {
            return @[[NSString stringWithFormat:@"'%@__objectid'",[[relationship entity] name]],
                     [NSString stringWithFormat:@"'%@__objectid'",[[inverse entity] name]]];
        }
    }
    else {
        if ([[names objectAtIndex:0] isEqualToString:[relationship name]]) {
            return @[[NSString stringWithFormat:@"%@__objectid",[[inverse entity] name]],
                     [NSString stringWithFormat:@"%@__objectid",[[relationship entity] name]]];
        } else {
            return @[[NSString stringWithFormat:@"%@__objectid",[[relationship entity] name]],
                     [NSString stringWithFormat:@"%@__objectid",[[inverse entity] name]]];
        }
    }
}

#pragma mark - save changes to the database

- (NSArray *)handleSaveChangesRequest:(NSSaveChangesRequest *)request error:(NSError **)error {
    
    NSMutableDictionary *localNodeCache = [nodeCache mutableCopy];
    BOOL success = [self performInTransaction:^{
        BOOL insert = [self handleInsertedObjectsInSaveRequest:request error:error];
        BOOL update = [self handleUpdatedObjectsInSaveRequest:request cache:localNodeCache error:error];
        BOOL delete = [self handleDeletedObjectsInSaveRequest:request error:error];
        return (BOOL)(insert && update && delete);
    }];
    if (success) {
        nodeCache = localNodeCache;
        return [NSArray array];
    }
    if (error) { *error = [self databaseError]; }
    return nil;
}

- (BOOL)handleInsertedObjectsInSaveRequest:(NSSaveChangesRequest *)request error:(NSError **)error {
    BOOL __block success = YES;
    
    [[request insertedObjects] enumerateObjectsUsingBlock:^(NSManagedObject *object, BOOL *stop) {
        
        // get values
        NSEntityDescription *entity = [object entity];
        NSMutableArray *keys = [NSMutableArray array];
        NSMutableArray *columns = [NSMutableArray arrayWithObject:@"'__objectid'"];
        NSDictionary *properties = [entity propertiesByName];
        [properties enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            if ([obj isKindOfClass:[NSAttributeDescription class]]) {
                [keys addObject:key];
                [columns addObject:[NSString stringWithFormat:@"'%@'", key]];
            }
            else if ([obj isKindOfClass:[NSRelationshipDescription class]]) {
                NSRelationshipDescription *desc = (NSRelationshipDescription *)obj;
                NSRelationshipDescription *inverse = [desc inverseRelationship];
                
                // one side of both one-to-one and one-to-many
                // EDIT: only to-one relations should have columns in entity tables
                if (![desc isToMany]){// || [inverse isToMany]){
                    [keys addObject:key];
                    NSString *column = [NSString stringWithFormat:@"'%@'", [self foreignKeyColumnForRelationship:desc]];
                    [columns addObject:column];
                }
                else if ([desc isToMany] && [inverse isToMany]) {
                    if (![self handleInsertedRelationInSaveRequest:desc forObject:object error:error]) {
                        success = NO;
                    }
                }
                
            }
        }];
        
        // prepare statement
        NSString *string = nil;
        if (entity.superentity != nil) {
            string = [NSString stringWithFormat:
                      @"INSERT INTO %@ ('_entityType', %@) VALUES(%u, %@);",
                      [self tableNameForEntity:entity],
                      [columns componentsJoinedByString:@", "],
                      entity.name.hash,
                      [[NSArray cmdArrayWithObject:@"?" times:[columns count]] componentsJoinedByString:@", "]];
        } else {
            string = [NSString stringWithFormat:
                      @"INSERT INTO %@ (%@) VALUES(%@);",
                      [self tableNameForEntity:entity],
                      [columns componentsJoinedByString:@", "],
                      [[NSArray cmdArrayWithObject:@"?" times:[columns count]] componentsJoinedByString:@", "]];
        }
        sqlite3_stmt *statement = [self preparedStatementForQuery:string];
        
        // bind id
        NSNumber *number = [self referenceObjectForObjectID:[object objectID]];
        sqlite3_bind_int64(statement, 1, [number unsignedLongLongValue]);
        
        // bind properties
        [keys enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSPropertyDescription *property = [properties objectForKey:obj];
                [self
                 bindProperty:property
                 withValue:[object valueForKey:obj]
                 forKey:obj
                 toStatement:statement
                 atIndex:(idx + 2)];
        }];
        
        // execute
        sqlite3_step(statement);
        
        // finish up
        if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK) {
            if (error != NULL) { *error = [self databaseError]; }
            *stop = YES;
            success = NO;
        }
        
    }];
    return success;
}

- (BOOL)handleInsertedRelationInSaveRequest:(NSRelationshipDescription *)desc forObject:(NSManagedObject *)object error:(NSError **)error {
    BOOL __block success = YES;
    
    NSNumber __block *one, *two;
    NSArray *names = [@[[desc name],[[desc inverseRelationship] name]] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    NSString *string = [NSString stringWithFormat:@"INSERT INTO %@ VALUES (?, ?);",
                        [self tableNameForRelationship:desc]];
    
    [[object valueForKey:[desc name]] enumerateObjectsUsingBlock:^(id relative, NSUInteger idx, BOOL *stop) {
        
        sqlite3_stmt *statement = [self preparedStatementForQuery:string];
        
        if ([[names objectAtIndex:0] isEqualToString:[desc name]]) {
            one = [self referenceObjectForObjectID:[relative objectID]];
            two = [self referenceObjectForObjectID:[object objectID]];
        } else {
            one = [self referenceObjectForObjectID:[object objectID]];
            two = [self referenceObjectForObjectID:[relative objectID]];
        }
        
        sqlite3_bind_int64(statement, 1, [one unsignedLongLongValue]);
        sqlite3_bind_int64(statement, 2, [two unsignedLongLongValue]);
        
        sqlite3_step(statement);
        
        int finalize = sqlite3_finalize(statement);
        if (finalize != SQLITE_OK && finalize != SQLITE_CONSTRAINT) {
            if (error != nil) { *error = [self databaseError]; }
            success = NO;
        }

    }];
    
    return success;
}

- (BOOL)handleUpdatedObjectsInSaveRequest:(NSSaveChangesRequest *)request cache:(NSMutableDictionary *)cache error:(NSError **)error {
    BOOL __block success = YES;
    [[request updatedObjects] enumerateObjectsUsingBlock:^(NSManagedObject *object, BOOL *stop) {
        
        /*
         
         Tell the incremental store to use an `NSIncrementalStoreNode` cache and
         increment manual version tracking.
         
         Default: 0
         
         */
#define USE_MANUAL_NODE_CACHE 1
        
        // cache stuff
        NSManagedObjectID *objectID = [object objectID];
#if USE_MANUAL_NODE_CACHE
        NSMutableDictionary *cacheChanges = [NSMutableDictionary dictionary];
        CMDIncrementalStoreNode *node = [cache objectForKey:objectID];
#endif
        
        // prepare values
        NSEntityDescription *entity = [object entity];
        NSDictionary *changedAttributes = [object changedValues];
        NSMutableArray *columns = [NSMutableArray array];
        NSMutableArray *keys = [NSMutableArray array];
        
        // enumerate changed properties
        NSDictionary *properties = [entity propertiesByName];
        [changedAttributes enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            id property = [properties objectForKey:key];
            if ([property isKindOfClass:[NSAttributeDescription class]]) {
                [columns addObject:[NSString stringWithFormat:@"%@=?", key]];
                [keys addObject:key];
            }
            else if ([property isKindOfClass:[NSRelationshipDescription class]]) {
                NSRelationshipDescription *desc = property;
                NSRelationshipDescription *inverse = [desc inverseRelationship];
                
                // TODO: More edge case testing and handling
                if (![desc isToMany]) {
                    NSString *column = [self foreignKeyColumnForRelationship:property];
                    [columns addObject:[NSString stringWithFormat:@"%@=?", column]];
                    [keys addObject:key];
                }
                else if ([desc isToMany] && [inverse isToMany]) {
                    if (![self handleUpdatedRelationInSaveRequest:desc forObject:object error:error]) {
                        success = NO;
                    }
                }
            }
        }];
        
        // return if nothing needs updating
        if ([keys count] == 0) {
#if USE_MANUAL_NODE_CACHE
            [node updateWithChangedValues:cacheChanges];
#endif
            return;
        }
        
        // prepare statement
        NSString *string = [NSString stringWithFormat:
                            @"UPDATE %@ SET %@ WHERE __objectID=?;",
                            [self tableNameForEntity:entity],
                            [columns componentsJoinedByString:@", "]];
        sqlite3_stmt *statement = [self preparedStatementForQuery:string];
        
        // bind values
        [keys enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            id value = [changedAttributes objectForKey:obj];
            id property = [properties objectForKey:obj];
#if USE_MANUAL_NODE_CACHE
            if (value && ![value isKindOfClass:[NSNull class]]) {
                [cacheChanges setObject:value forKey:obj];
            }
            else {
                [cacheChanges removeObjectForKey:obj];
            }
#endif
            [self
             bindProperty:property
             withValue:value
             forKey:obj
             toStatement:statement
             atIndex:(idx + 1)];
        }];
        
        // execute
        NSNumber *number = [self referenceObjectForObjectID:objectID];
        sqlite3_bind_int64(statement, ([columns count] + 1), [number unsignedLongLongValue]);
        sqlite3_step(statement);
        
        // finish up
        if (statement != NULL && sqlite3_finalize(statement) == SQLITE_OK) {
#if USE_MANUAL_NODE_CACHE
            [node updateWithChangedValues:cacheChanges];
#endif
        }
        else {
            if (error != NULL) { *error = [self databaseError]; }
            *stop = YES;
            success = NO;
        }
        
    }];
    return success;
}

- (BOOL)handleUpdatedRelationInSaveRequest:(NSRelationshipDescription *)desc forObject:(NSManagedObject *)object error:(NSError **)error {
    BOOL __block success = YES;
    
    NSString *string = [NSString stringWithFormat:@"DELETE FROM %@ WHERE %@__objectid=?;",
                        [self tableNameForRelationship:desc], [[object entity] name]];
    
    sqlite3_stmt *statement = [self preparedStatementForQuery:string];
    
    NSNumber *number = [self referenceObjectForObjectID:[object objectID]];
    sqlite3_bind_int64(statement, 1, [number unsignedLongLongValue]);
    
    sqlite3_step(statement);
    
    if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK) {
        if (error != nil) { *error = [self databaseError]; }
        success = NO;
    } else if (![self handleInsertedRelationInSaveRequest:desc forObject:object error:error]){
        success = NO;
    }
    
    return success;
}

- (BOOL)handleDeletedObjectsInSaveRequest:(NSSaveChangesRequest *)request error:(NSError **)error {
    BOOL __block success = YES;
    [[request deletedObjects] enumerateObjectsUsingBlock:^(NSManagedObject *object, BOOL *stop) {
        
        // get identifying information
        NSEntityDescription *entity = [object entity];
        NSNumber *objectID = [self referenceObjectForObjectID:[object objectID]];
        
        // delete object
        NSString *string = [NSString stringWithFormat:
                            @"DELETE FROM %@ WHERE __objectID=?;",
                            [self tableNameForEntity:entity]];
        sqlite3_stmt *statement = [self preparedStatementForQuery:string];
        sqlite3_bind_int64(statement, 1, [objectID unsignedLongLongValue]);
        sqlite3_step(statement);
        
        // finish up
        if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK) {
            if (error != NULL) { *error = [self databaseError]; }
            *stop = YES;
            success = NO;
        } else if (![self handleDeletedRelationInSaveRequest:object error:error]) {
            *stop = YES;
            success = NO;
        }
        
    }];
    return success;
}

- (BOOL)handleDeletedRelationInSaveRequest:(NSManagedObject *)object error:(NSError **)error {
    BOOL __block success = YES;
    
    [[[object entity] propertiesByName] enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSPropertyDescription *prop, BOOL *stop) {
        if ([prop isKindOfClass:[NSRelationshipDescription class]]) {
            NSRelationshipDescription *desc = (NSRelationshipDescription *)prop;
            NSRelationshipDescription *inverse = [desc inverseRelationship];
            if ([desc isToMany] && [inverse isToMany]) {
                
                NSString *string = [NSString stringWithFormat:@"DELETE FROM %@ WHERE %@__objectid=?;",
                                    [self tableNameForRelationship:desc],[[object entity] name]];
                sqlite3_stmt *statement = [self preparedStatementForQuery:string];
                NSNumber *number = [self referenceObjectForObjectID:[object objectID]];
                sqlite3_bind_int64(statement, 1, [number unsignedLongLongValue]);
                sqlite3_step(statement);
                
                if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK) {
                    if (error != NULL) { *error = [self databaseError]; }
                    *stop = YES;
                    success = NO;
                }
            }
        }
    }];
    
    return success;
}

# pragma mark - SQL helpers

- (BOOL)hasTable:(BOOL *)hasTable withName:(NSString*)name error:(NSError **)error {
    static NSString * const kSQL = @"SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='%@';";
    int count = 0;
    NSString *string = [NSString stringWithFormat:kSQL, name];
    sqlite3_stmt *statement = [self preparedStatementForQuery:string];
    if (statement != NULL && sqlite3_step(statement) == SQLITE_ROW) {
        count = sqlite3_column_int(statement, 0);
    }
    else {
        if (error) { *error = [self databaseError]; }
        sqlite3_finalize(statement);
        return NO;
    }
    sqlite3_finalize(statement);
    *hasTable = (count > 0);
    return YES;
}

- (NSError *)databaseError {
    int code = sqlite3_errcode(database);
    if (code) {
        NSDictionary *userInfo = @{
                                   EncryptedStoreErrorMessageKey : [NSString stringWithUTF8String:sqlite3_errmsg(database)]
                                   };
        return [NSError
                errorWithDomain:NSSQLiteErrorDomain
                code:code
                userInfo:userInfo];
    }
    return nil;
}

- (BOOL)performInTransaction:(BOOL (^) ())block {
    sqlite3_stmt *statement = NULL;
    
    // begin transaction
    statement = [self preparedStatementForQuery:@"BEGIN EXCLUSIVE;"];
    sqlite3_step(statement);
    if (sqlite3_finalize(statement) != SQLITE_OK) {
        return NO;
    }
    
    // run block
    BOOL success = block();
    
    // end transaction
    statement = [self preparedStatementForQuery:(success ? @"COMMIT;" : @"ROLLBACK;")];
    sqlite3_step(statement);
    if (sqlite3_finalize(statement) != SQLITE_OK) {
        return NO;
    }
    
    // return
    return success;
    
}

- (NSString *)tableNameForEntity:(NSEntityDescription *)entity {
    NSEntityDescription *targetEntity = entity;
    while ([targetEntity superentity] != nil) {
        targetEntity = [targetEntity superentity];
    }
    return [NSString stringWithFormat:@"ecd%@",[targetEntity name]];
}

- (sqlite3_stmt *)preparedStatementForQuery:(NSString *)query {
    static BOOL debug = NO;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        debug = [[NSUserDefaults standardUserDefaults] boolForKey:@"com.apple.CoreData.SQLDebug"];
    });
    if (debug) {NSLog(@"SQL DEBUG: %@", query); }
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(database, [query UTF8String], -1, &statement, NULL) == SQLITE_OK) { return statement; }
    if(debug) {NSLog(@"could not prepare statement: %s\n", sqlite3_errmsg(database));}
    return NULL;
}

- (NSDictionary *)orderClause:(NSFetchRequest *) fetchRequest forEntity:(NSEntityDescription *) entity {
    NSArray *descriptors = [fetchRequest sortDescriptors];
    NSString *order = @"";
    
    NSMutableArray *columns = [NSMutableArray arrayWithCapacity:[descriptors count]];
    [descriptors enumerateObjectsUsingBlock:^(NSSortDescriptor *desc, NSUInteger idx, BOOL *stop) {
        // We throw an exception in the join if the key is more than one relationship deep.
        // We do need to detect the relationship though to know what table to prefix the key
        // with.
        
        NSString *tableName = [self tableNameForEntity:fetchRequest.entity];
        NSString *key = [desc key];
        if ([desc.key rangeOfString:@"."].location != NSNotFound) {
            NSArray *components = [desc.key componentsSeparatedByString:@"."];
            tableName = [self joinedTableNameForComponents:components forRelationship:NO];
            key = [components lastObject];
        }
        
        NSString *collate = @"";
        // search for InsensitiveCompare instead of caseSensitiveCompare b/c could also be localizedCaseInsensitiveCompare
        if([NSStringFromSelector([desc selector]) rangeOfString:@"InsensitiveCompare"].location != NSNotFound) {
            collate = @"COLLATE NOCASE";
        }
        
        [columns addObject:[NSString stringWithFormat:
                            @"%@.%@ %@ %@",
                            tableName,
                            key,
                            collate,
                            ([desc ascending]) ? @"ASC" : @"DESC"]];
    }];
    if (columns.count) {
        order = [NSString stringWithFormat:@" ORDER BY %@",
                 [columns componentsJoinedByString:@", "]];
    }
    return @{ @"order": order };
}

- (NSString *) getJoinClause: (NSFetchRequest *) fetchRequest {
    
    NSEntityDescription *entity = [fetchRequest entity];
    // We use a set to only add one join table per relationship.
    NSMutableSet *joinStatementsSet = [NSMutableSet set];
    // We use an array to ensure the order of join statements
    NSMutableArray *joinStatementsArray = [NSMutableArray array];
    
    // First look at all sort descriptor keys
    NSArray *descs = [fetchRequest sortDescriptors];
    for (NSSortDescriptor *sd in descs) {
        NSString *sortKey = [sd key];
        if ([sortKey rangeOfString:@"."].location != NSNotFound) {
            if ([self maybeAddJoinStatementsForKey:sortKey toStatementArray:joinStatementsArray withExistingStatementSet:joinStatementsSet rootEntity:entity andJoinType:@"LEFT OUTER JOIN"]) {
                [fetchRequest setReturnsDistinctResults:YES];
            }
        }
    }
    
    NSString *predicateString = [[fetchRequest predicate] predicateFormat];
    
    if (predicateString != nil ) {
        
        NSRegularExpression* regexForDottedRelations = [NSRegularExpression regularExpressionWithPattern:@"\\b([a-zA-Z]\\w*\\.[^= ]+)\\b" options:0 error:nil];
        NSArray* dottedRelationMatches = [regexForDottedRelations matchesInString:predicateString options:0 range:NSMakeRange(0, [predicateString length])];

        
        NSRegularExpression* regexForAnyAllRelations = [NSRegularExpression regularExpressionWithPattern:@"(?<=\\b(ANY|ALL)(\\s))(\\S+)" options:0 error:nil];
        NSArray* anyAllRelationsMatches = [regexForAnyAllRelations matchesInString:predicateString options:0 range:NSMakeRange(0, [predicateString length])];

        NSMutableArray *matches = [NSMutableArray arrayWithArray:anyAllRelationsMatches];
        [matches addObjectsFromArray:dottedRelationMatches];
        
        for ( NSTextCheckingResult* match in matches )
        {
            NSString* matchText = [predicateString substringWithRange:[match range]];
            if ([matchText hasSuffix:@".@count"]) {
                // @count queries should be handled by sub-expressions rather than joins
                continue;
            }
            if ([self maybeAddJoinStatementsForKey:matchText toStatementArray:joinStatementsArray withExistingStatementSet:joinStatementsSet rootEntity:entity andJoinType:@"LEFT OUTER JOIN"]) {
                [fetchRequest setReturnsDistinctResults:YES];
            }
        }
    }
    if (joinStatementsArray.count > 0) {
        return [joinStatementsArray componentsJoinedByString:@" "];
    }
    
    return @"";
}

- (BOOL) maybeAddJoinStatementsForKey: (NSString *) key
                     toStatementArray: (NSMutableArray *) statementArray
             withExistingStatementSet: (NSMutableSet *) statementsSet
                           rootEntity: (NSEntityDescription *) rootEntity
                          andJoinType: (NSString *)joinType
{
    joinType = joinType ?: @"LEFT OUTER JOIN";
    BOOL retval = NO;
    
    // We support have deeper relationships (e.g. child.parent.name ) by bracketing the
    // intermediate tables and updating the keys in the WHERE or ORDERBY to use the bracketed
    // table: EG
    // child.parent.name -> [child.parent].name and we generate a double join
    // JOIN childTable as child on mainTable.child_id = child.ID
    // JOIN parentTable as [child.parent] on child.parent_id = [child.parent].ID
    // Care must be taken to ensure unique join table names so that a WHERE clause like:
    // child.name == %@ AND child.parent.name == %@ doesn't add the child relationship twice
    NSArray *keysArray = [key componentsSeparatedByString:@"."];
    
    // We terminate when there is one item left since that is the field of interest
    NSEntityDescription *currentEntity = rootEntity;
    NSString *fullJoinClause;
    NSString *secondFullJoinClause = @"";
    NSString *lastTableName = [self tableNameForEntity:currentEntity];
    int loopMax = (int) (keysArray.count == 1 ? 1 : keysArray.count - 1);
    for (int i = 0 ; i < loopMax; i++) {
        
        NSArray *miniKeyArray =   ( keysArray.count > 1) ? [keysArray subarrayWithRange: NSMakeRange(0, i+2)] : @[keysArray[0], @"foobbbbears"] ;
        
        // alt names for tables for safety
        NSString *relTableName = [self joinedTableNameForComponents:
                                  miniKeyArray
                                forRelationship:YES];
        
        NSString *nextTableName = [self joinedTableNameForComponents:
                                   miniKeyArray
                                 forRelationship:NO];
        
        
        NSRelationshipDescription *rel = [[currentEntity relationshipsByName]
                                          objectForKey:[keysArray objectAtIndex:i]];
        NSRelationshipDescription *inverse = [rel inverseRelationship];
        
        if (rel != nil) {
            
            retval = YES;
            
            if ([rel isToMany] && [inverse isToMany]) {
                
                // source entity table to relation table join
                NSUInteger index;
                NSArray *columns = [self columnNamesForRelationship:rel withQuotes:NO];
                NSString *entity_name = [[rel entity] name];
                
                if ([[columns objectAtIndex:0] isEqualToString:[NSString stringWithFormat:@"%@__objectid",entity_name]]) {
                    index = 0;
                } else {
                    index = 1;
                }
                
                NSString *joinTableAsClause1 = [NSString stringWithFormat:@"%@ AS %@",
                                                [self tableNameForRelationship:rel],
                                                relTableName];
                
                NSString *joinTableOnClause1 = [NSString stringWithFormat:@"%@.__objectID = %@.%@",
                                               lastTableName,
                                               relTableName,
                                               [columns objectAtIndex:index]];
                
                NSString *firstJoinClause = [NSString stringWithFormat:@"%@ %@ ON %@", joinType, joinTableAsClause1, joinTableOnClause1];
                
                // relation table to destination entity table join
                if (index == 1) { index = 0; }
                else { index = 1; }
                
                NSString *joinTableAsClause2 = [NSString stringWithFormat:@"%@ AS %@",
                                                [self tableNameForEntity:[rel destinationEntity]],
                                                nextTableName];
                
                NSString *joinTableOnClause2 = [NSString stringWithFormat:@"%@.%@ = %@.__objectID",
                                                relTableName,
                                                [columns objectAtIndex:index],
                                                nextTableName];
                
                NSString *secondJoinClause = [NSString stringWithFormat:@"%@  %@ ON %@", joinType, joinTableAsClause2, joinTableOnClause2];
                
                fullJoinClause = [NSString stringWithFormat:@"%@ %@",firstJoinClause,secondJoinClause];
            }
            else {
                
                // We bracket all join table names so that periods are ok.
                NSString *joinTableAsClause = [NSString stringWithFormat:@"%@ AS %@",
                                               [self tableNameForEntity:rel.destinationEntity],
                                               nextTableName];
                NSString *joinTableOnClause = nil;
                if (rel.isToMany) {
                    joinTableOnClause = [NSString stringWithFormat:@"%@.__objectID = %@.%@",
                                         lastTableName,
                                         nextTableName,
                                         [self foreignKeyColumnForRelationship:rel.inverseRelationship]];
                } else {
                    joinTableOnClause = [NSString stringWithFormat:@"%@.%@ = %@.__objectID",
                                         lastTableName,
                                         [self foreignKeyColumnForRelationship:rel],
                                         nextTableName];
                }
                
                
                if(i+1 < keysArray.count){
                    NSString *nextProp = keysArray[i+1];
                    NSDictionary *destinationArray = rel.destinationEntity.relationshipsByName;
                    NSRelationshipDescription *secondRelation = [destinationArray objectForKey:nextProp];
                    if(secondRelation){
                        NSString *lastTableName2 = nextTableName;
                        NSString *nextTableName2 = [self joinedTableNameForComponents: @[nextProp, @"foooobear"] forRelationship:YES];
                        
                        NSString *joinTableAsClause2;
                        NSString *joinTableOnClause2;
                        if(secondRelation.isToMany){
                            joinTableAsClause2 = [NSString stringWithFormat:@"%@ AS %@",
                                                  [self tableNameForRelationship: secondRelation],
                                                  nextTableName2];
                            joinTableOnClause2 = [NSString stringWithFormat:@"%@.__objectID = %@.%@",
                                                  lastTableName2,
                                                  nextTableName2,
                                                  [self foreignKeyColumnForToManyRelationship:secondRelation.inverseRelationship]];
                        } else {
                            joinTableAsClause2 = [NSString stringWithFormat:@"%@ AS %@",
                                                  [self tableNameForEntity:secondRelation.destinationEntity],
                                                  nextTableName2];
                            
                            joinTableOnClause2 = [NSString stringWithFormat:@"%@.%@ = %@.__objectID",
                                                  lastTableName2,
                                                  [self foreignKeyColumnForRelationship:secondRelation],
                                                  nextTableName2];
                        }
                        secondFullJoinClause = [NSString stringWithFormat: @" %@ %@ ON %@", joinType, joinTableAsClause2, joinTableOnClause2];
                    }
                }
                // NOTE: we use an outer join instead of an inner one because the where clause might also
                // be explicitely looking for cases where the relationship is null or has a specific value
                // consider the following predicate: "entity.rel = null || entity.rel.field = 'something'".
                // If we were to use an inner join the first part of the or clause would never work because
                // those objects would get discarded by the join.
                // Also, note that NSSQLiteStoreType correctly generates an outer join for this case but regular
                // joins for others. That's obviously better for performance but for now, correctness should
                // take precedence over performance. This should obviously be revisited at some point.
                fullJoinClause = [NSString stringWithFormat:@"%@ %@ ON %@", joinType, joinTableAsClause, joinTableOnClause];
            }
            
            currentEntity = rel.destinationEntity;
            lastTableName = nextTableName;
            if (![statementsSet containsObject:fullJoinClause]) {
                [statementsSet addObject:fullJoinClause];
                [statementArray addObject:fullJoinClause];
            }
            if (secondFullJoinClause.length > 0 && ![statementsSet containsObject:secondFullJoinClause]) {
                [statementsSet addObject:secondFullJoinClause];
                [statementArray addObject:secondFullJoinClause];
            }
            

        }
    }
    
    return retval;
}


-(NSString*) sqlFunctionForCoredataExpressionDescription: (NSString*) keyPath andTableName: (NSString*) tableName{
    NSDictionary *convertibleSetOperations = @{
                                               @"@avg." : @"avg",
                                                @"@max." : @"max",
                                                @"@min." : @"min",
                                                @"@sum." : @"sum",
                                               @"@count." : @"count",
                                               @"@distinctUnionOfObjects" : @"distinct",
                                               @".@avg" : @"avg",
                                               @".@max" : @"max",
                                               @".@min" : @"min",
                                               @".@sum" : @"sum",
                                               @".@count" : @"count",

                   };
    
    for (NSString *setOpt in [convertibleSetOperations allKeys])
    {
        if ([keyPath hasSuffix:setOpt] || [keyPath hasPrefix:setOpt] )
        {
            NSString *clean = [[keyPath stringByReplacingOccurrencesOfString: setOpt withString:@""] stringByReplacingOccurrencesOfString:@".." withString:@"."];
            return [NSString stringWithFormat:@"%@(%@.%@)",convertibleSetOperations[setOpt], tableName, clean];
        };
    };
    
    return nil;
}

- (NSString *)expressionDescriptionTypeString:(NSExpressionDescription *)expressionDescription andTableName: (NSString*) tableName {
    

    
    switch (expressionDescription.expressionResultType) {
        case NSObjectIDAttributeType:
            return [NSString stringWithFormat: @"%@.__objectID", tableName];
            break;
        
            /*  NSUndefinedAttributeType
             *  NSInteger16AttributeType
             *  NSInteger32AttributeType
             *  NSInteger64AttributeType
             *  NSDecimalAttributeType
             *  NSDoubleAttributeType
             *  NSFloatAttributeType
             *  NSStringAttributeType
             *  NSBooleanAttributeType
             *  NSDateAttributeType
             *  NSBinaryDataAttributeType
             *  NSTransformableAttributeType
             */
        
        default:
           return [self sqlFunctionForCoredataExpressionDescription: expressionDescription.expression.description andTableName: tableName];
//            if(!returnString){
//                    id operand = nil;
//                    id bindings = nil;
//                    [self parseExpression:expressionDescription.expression
//                              inPredicate: nil
//                           inFetchRequest: nil
//                                  context: nil
//                                 operator: nil
//                                  operand: &operand
//                                 bindings: &bindings
//                     ];
//                    NSLog(@"ok: %@", operand);
//                    NSLog(@"nok %@", bindings);
//                returnString = operand;
//            }
//            return returnString;
            break;
    }
}

- (NSString *)columnsClauseWithProperties:(NSArray *)properties andTableName: (NSString *) tableName {
    NSMutableArray *columns = [NSMutableArray arrayWithCapacity:[properties count]];
    
    [properties enumerateObjectsUsingBlock:^(NSPropertyDescription *prop, NSUInteger idx, BOOL *stop) {
        if ([prop isKindOfClass:[NSRelationshipDescription class]]) {
            if (![(NSRelationshipDescription *)prop isToMany]) {
                [columns addObject:[self foreignKeyColumnForRelationship:(NSRelationshipDescription *)prop]];
            }
        } else if ([prop isKindOfClass:[NSExpressionDescription class]]) {
            [columns addObject:[self expressionDescriptionTypeString: ((NSExpressionDescription *)prop) andTableName: tableName]];
        } else {
            [columns addObject:[NSString stringWithFormat:@"%@",prop.name]];
        }
    }];
    
    if ([columns count]) {
        return [NSString stringWithFormat:@"%@", [columns componentsJoinedByString:@", "]];
    }
    return @"";
}

- (NSNumber *)maximumObjectIDInTable:(NSString *)table {
    NSNumber *value = [objectIDCache objectForKey:table];
    if (value == nil) {
        NSString *string = [NSString stringWithFormat:@"SELECT MAX(__objectID) FROM %@;", table];
        sqlite3_stmt *statement = [self preparedStatementForQuery:string];
        if (sqlite3_step(statement) == SQLITE_ROW) {
            value = @(sqlite3_column_int64(statement, 0));
        }
        sqlite3_finalize(statement);
    }
    value = @([value unsignedLongLongValue] + 1);
    [objectIDCache setObject:value forKey:table];
    return value;
}

- (void)bindProperty:(NSPropertyDescription *)property
           withValue:(id)value
              forKey:(NSString *)key
         toStatement:(sqlite3_stmt *)statement
             atIndex:(int)index {
    if (value && ![value isKindOfClass:[NSNull class]]) {
        if ([property isKindOfClass:[NSAttributeDescription class]]) {
            NSAttributeType type = [(id)property attributeType];
            
            // string
            if (type == NSStringAttributeType) {
                sqlite3_bind_text(statement, index, [value UTF8String], -1, SQLITE_TRANSIENT);
            }
            
            // real numbers
            else if (type == NSDoubleAttributeType ||
                     type == NSFloatAttributeType) {
                sqlite3_bind_double(statement, index, [value doubleValue]);
            }
            
            // integers
            else if (type == NSInteger16AttributeType ||
                     type == NSInteger32AttributeType ||
                     type == NSInteger64AttributeType) {
                sqlite3_bind_int64(statement, index, [value longLongValue]);
            }
            
            // boolean
            else if (type == NSBooleanAttributeType) {
                sqlite3_bind_int(statement, index, [value boolValue] ? 1 : 0);
            }
            
            // date
            else if (type == NSDateAttributeType) {
                sqlite3_bind_double(statement, index, [value timeIntervalSince1970]);
            }
            
            // blob
            else if (type == NSBinaryDataAttributeType) {
                sqlite3_bind_blob(statement, index, [value bytes], [value length], SQLITE_TRANSIENT);
            }
            
            // optimus prime
            else if (type == NSTransformableAttributeType) {
                NSString *name = ([(id)property valueTransformerName] ?: NSKeyedUnarchiveFromDataTransformerName);
                if ([name isEqualToString:@""]) {
                    name = NSKeyedUnarchiveFromDataTransformerName;
                }
                const BOOL isDefaultTransformer = [name isEqualToString:NSKeyedUnarchiveFromDataTransformerName];
                NSValueTransformer *transformer = [NSValueTransformer valueTransformerForName:name];
                NSData *data = isDefaultTransformer ? [transformer reverseTransformedValue:value] : [transformer transformedValue:value];
                sqlite3_bind_blob(statement, index, [data bytes], [data length], SQLITE_TRANSIENT);
            }
            
            else if (type == NSDecimalAttributeType) {
                NSString *decimalString = [value stringValue];
                sqlite3_bind_text(statement, index, [decimalString UTF8String], -1, SQLITE_TRANSIENT);
            }
            
            // NSObjectIDAttributeType
            
        }
        else if ([property isKindOfClass:[NSRelationshipDescription class]]) {
            NSRelationshipDescription *desc = (NSRelationshipDescription *)property;
            
            if (![desc isToMany]) {
                NSNumber *number = [self referenceObjectForObjectID:[value objectID]];
                sqlite3_bind_int64(statement, index, [number unsignedLongLongValue]);
            }
        }
    }
}

- (id)valueForProperty:(NSPropertyDescription *)property
           inStatement:(sqlite3_stmt *)statement
               atIndex:(int)index
             forEntity:(NSEntityDescription*)entity
    {
    
    if (sqlite3_column_type(statement, index) == SQLITE_NULL) { return nil; }
    
    if ([property isKindOfClass:[NSAttributeDescription class]]) {
        NSAttributeType type = [(id)property attributeType];
        
        // string
        if (type == NSStringAttributeType) {
            const char *string = (char *)sqlite3_column_text(statement, index);
            return [NSString stringWithUTF8String:string];
        }
        
        // real numbers
        else if (type == NSDoubleAttributeType ||
                 type == NSFloatAttributeType) {
            return @(sqlite3_column_double(statement, index));
        }
        
        // integers
        else if (type == NSInteger16AttributeType ||
                 type == NSInteger32AttributeType ||
                 type == NSInteger64AttributeType) {
            return @(sqlite3_column_int64(statement, index));
        }
        
        // boolean
        else if (type == NSBooleanAttributeType) {
            return @((BOOL)sqlite3_column_int(statement, index));
        }
        
        // date
        else if (type == NSDateAttributeType) {
            return [NSDate dateWithTimeIntervalSince1970:sqlite3_column_double(statement, index)];
        }
        
        // blob
        else if (type == NSBinaryDataAttributeType) {
            const void *bytes = sqlite3_column_blob(statement, index);
            unsigned int length = sqlite3_column_bytes(statement, index);
            return [NSData dataWithBytes:bytes length:length];
        }
        
        // transformable
        else if (type == NSTransformableAttributeType) {
            NSString *name = ([(id)property valueTransformerName] ?: NSKeyedUnarchiveFromDataTransformerName);
            if ([name isEqualToString:@""]) {
                name = NSKeyedUnarchiveFromDataTransformerName;
            }
            NSValueTransformer *transformer = [NSValueTransformer valueTransformerForName:name];
            const void *bytes = sqlite3_column_blob(statement, index);
            unsigned int length = sqlite3_column_bytes(statement, index);
            if (length > 0) {
                const BOOL isDefaultTransformer = [name isEqualToString:NSKeyedUnarchiveFromDataTransformerName];
                NSData *data = [NSData dataWithBytes:bytes length:length];
                return isDefaultTransformer ? [transformer transformedValue:data] : [transformer reverseTransformedValue:data];
            }
        }
        
        else if (type == NSDecimalAttributeType) {
            const char *string = (char *)sqlite3_column_text(statement, index);
            return [NSDecimalNumber decimalNumberWithString:@(string)];
        }
        
        // NSObjectIDAttributeType
        
    }
    
    else if ([property isKindOfClass:[NSRelationshipDescription class]]) {
        NSEntityDescription *target = [(id)property destinationEntity];
        NSNumber *number = @(sqlite3_column_int64(statement, index));
        return [self newObjectIDForEntity:target referenceObject:number];
    }
    
    else if ([property isKindOfClass:[NSExpressionDescription class]]) {
        NSNumber *number = @(sqlite3_column_int64(statement, index));
        return [self expressionDescriptionTypeValue:(NSExpressionDescription *)property withReferenceNumber:number andEntity:entity];
    }
    
    return nil;
}

-(id)expressionDescriptionTypeValue:(NSExpressionDescription *)expressionDescription
                withReferenceNumber:(NSNumber *)number
{
    return [self expressionDescriptionTypeValue:expressionDescription withReferenceNumber:number andEntity:expressionDescription.entity];
}

-(id)expressionDescriptionTypeValue:(NSExpressionDescription *)expressionDescription
                withReferenceNumber:(NSNumber *)number
                          andEntity:(NSEntityDescription *)entity
    {
    
    switch ([expressionDescription expressionResultType]) {
        case NSObjectIDAttributeType:
            return [self newObjectIDForEntity:entity referenceObject:number];
            break;
            
            /*  NSUndefinedAttributeType
             *  NSInteger16AttributeType
             *  NSInteger32AttributeType
             *  NSInteger64AttributeType
             *  NSDecimalAttributeType
             *  NSDoubleAttributeType
             *  NSFloatAttributeType
             *  NSStringAttributeType
             *  NSBooleanAttributeType
             *  NSDateAttributeType
             *  NSBinaryDataAttributeType
             *  NSTransformableAttributeType
             */
            
        default:
            return nil;
            break;
    }
}

/*
 
 The family of whereClauseWithFetchRequest: methods will return a dictionary
 with the following schema:
 
 {
 "query": "query string with ? parameters",
 "bindings": [
 "array",
 "of",
 "bindings"
 ]
 }
 
 */
- (NSDictionary *)whereClauseWithFetchRequest:(NSFetchRequest *)request andContext: (NSManagedObjectContext*) context {
    NSDictionary *result = [self recursiveWhereClauseWithFetchRequest:request predicate:[request predicate] andContext:context];
    if ([(NSString*)result[@"query"] length] > 0) {
        NSMutableDictionary *mutableResult = [result mutableCopy];
        mutableResult[@"query"] = [NSString stringWithFormat:@" WHERE %@", result[@"query"]];
        result = mutableResult;
    }
    
    return result;
}

- (NSDictionary *)recursiveWhereClauseWithFetchRequest:(NSFetchRequest *)request predicate:(NSPredicate *)predicate andContext: (NSManagedObjectContext*) context {
    
    //    enum {
    //        NSCustomSelectorPredicateOperatorType,
    //        NSBetweenPredicateOperatorType
    //    };
    //    typedef NSUInteger NSPredicateOperatorType;
    
    static NSDictionary *operators = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        operators = @{
                      @(NSEqualToPredicateOperatorType)              : @{ @"operator" : @"=",      @"format" : @"'%@'" },
                      @(NSNotEqualToPredicateOperatorType)           : @{ @"operator" : @"!=",     @"format" : @"%@" },
                      @(NSContainsPredicateOperatorType)             : @{ @"operator" : @"LIKE",   @"format" : @"%%%@%%" },
                      @(NSBeginsWithPredicateOperatorType)           : @{ @"operator" : @"LIKE",   @"format" : @"%@%%" },
                      @(NSEndsWithPredicateOperatorType)             : @{ @"operator" : @"LIKE",   @"format" : @"%%%@" },
                      @(NSLikePredicateOperatorType)                 : @{ @"operator" : @"LIKE",   @"format" : @"%@" },
                      @(NSMatchesPredicateOperatorType)              : @{ @"operator" : @"REGEXP", @"format" : @"%@" },
                      @(NSInPredicateOperatorType)                   : @{ @"operator" : @"IN",     @"format" : @"(%@)" },
                      @(NSLessThanPredicateOperatorType)             : @{ @"operator" : @"<",      @"format" : @"%@" },
                      @(NSLessThanOrEqualToPredicateOperatorType)    : @{ @"operator" : @"<=",     @"format" : @"%@" },
                      @(NSGreaterThanPredicateOperatorType)          : @{ @"operator" : @">",      @"format" : @"%@" },
                      @(NSGreaterThanOrEqualToPredicateOperatorType) : @{ @"operator" : @">=",     @"format" : @"%@" }
                      };
    });
    
    NSString *query = @"";
    NSMutableArray *bindings = [NSMutableArray array];
    
    if ([predicate isKindOfClass:[NSCompoundPredicate class]]) {
        NSCompoundPredicate *compoundPredicate = (NSCompoundPredicate*)predicate;
        
        // get subpredicates
        NSMutableArray *queries = [NSMutableArray array];
        [compoundPredicate.subpredicates enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSDictionary *result = [self recursiveWhereClauseWithFetchRequest:request predicate:obj andContext:context];
            [queries addObject:[result objectForKey:@"query"]];
            [bindings addObjectsFromArray:[result objectForKey:@"bindings"]];
        }];
        
        // build query
        switch (compoundPredicate.compoundPredicateType) {
            case NSNotPredicateType:
                assert(queries.count == 1);
                query = [NSString stringWithFormat:@"(NOT %@)", queries[0]];
                break;
                
            case NSAndPredicateType:
                query = [NSString stringWithFormat:@"(%@)",
                         [queries componentsJoinedByString:@" AND "]];
                break;
                
            case NSOrPredicateType:
                query = [NSString stringWithFormat:@"(%@)",
                         [queries componentsJoinedByString:@" OR "]];
                break;
                
            default:
                break;
        }
    }
    
    else if ([predicate isKindOfClass:[NSComparisonPredicate class]]) {
        NSComparisonPredicate *comparisonPredicate = (NSComparisonPredicate*)predicate;
        
        NSNumber *type = @(comparisonPredicate.predicateOperatorType);
        NSComparisonPredicateModifier predicateModifier = comparisonPredicate.comparisonPredicateModifier;
        if (predicateModifier == NSAnyPredicateModifier) {
            [request setReturnsDistinctResults:YES];
        }
        NSDictionary *operator = [operators objectForKey:type];
        
        // left expression
        id leftOperand = nil;
        id leftBindings = nil;
        [self parseExpression:comparisonPredicate.leftExpression
                  inPredicate:comparisonPredicate
               inFetchRequest:request
                      context:context
                     operator:operator
                      operand:&leftOperand
                     bindings:&leftBindings];
        
        // right expression
        id rightOperand = nil;
        id rightBindings = nil;
        [self parseExpression:comparisonPredicate.rightExpression
                  inPredicate:comparisonPredicate
               inFetchRequest:request
                      context:context
                     operator:operator
                      operand:&rightOperand
                     bindings:&rightBindings];
        
        // build result and return
        if (rightOperand && !rightBindings) {
            if([[operator objectForKey:@"operator"] isEqualToString:@"!="]) {
                query = [@[leftOperand, @"IS NOT", rightOperand] componentsJoinedByString:@" "];
            }else if([[operator objectForKey:@"operator"] isEqualToString:@">="] || [[operator objectForKey:@"operator"] isEqualToString:@"<="]){
                query = [@[leftOperand, [operator objectForKey:@"operator"], rightOperand] componentsJoinedByString:@" "];
            } else {
                query = [@[leftOperand,  @"IS", rightOperand] componentsJoinedByString:@" "];
            }
        }
        else
            if([rightBindings class] != [NSManagedObject class]
                && ![rightBindings isKindOfClass: [NSData class]]
                && [[operator objectForKey:@"operator"] isEqualToString:@"="]) {
            query = [@[leftOperand, [operator objectForKey:@"operator"], rightBindings] componentsJoinedByString:@" "];
            // If we're including the right bindings directly in the query string, it should not be included
            // in the returned bindings. Otherwise, the indices passed to sqlite will be off and it *will* break stuff
            rightBindings = nil;
        }
        else {
            query = [@[leftOperand, [operator objectForKey:@"operator"], rightOperand] componentsJoinedByString:@" "];
        }
        
        NSMutableArray *comparisonBindings = [NSMutableArray arrayWithCapacity:2];
        if (leftBindings)  [comparisonBindings addObject:leftBindings];
        
        
        if ( [comparisonPredicate.rightExpression expressionType] == NSConstantValueExpressionType
            && [[comparisonPredicate.rightExpression constantValue] isKindOfClass:[NSDate class]]) {
            
            leftOperand = [NSString stringWithFormat:@"%@", leftOperand];
        }
        
        if (rightBindings) [comparisonBindings addObject:rightBindings];
        bindings = [[comparisonBindings cmdFlatten] mutableCopy];
    }
    
    NSString *entityWhere = nil;
    if (request.entity.superentity != nil) {
        if (request.entity.subentities.count > 0 && request.includesSubentities) {
            entityWhere = [NSString stringWithFormat:@"%@._entityType IN (%@)",
                           [self tableNameForEntity:request.entity],
                           [[self entityIdsForEntity:request.entity] componentsJoinedByString:@", "]];
        } else {
            entityWhere = [NSString stringWithFormat:@"%@._entityType = %u",
                           [self tableNameForEntity:request.entity],
                           request.entityName.hash];
        }
        
        if (query.length > 0) {
            query = [@[ entityWhere, query ] componentsJoinedByString:@" AND "];
        } else {
            query = entityWhere;
        }
    }
    
    return @{ @"query": query,
              @"bindings": bindings };
}

/*
 
 Binds a query set generated by the whereClauseWithFetchRequest: family of
 methods to a prepared SQLite statement
 
 */
- (void)bindWhereClause:(NSDictionary *)clause toStatement:(sqlite3_stmt *)statement {
    if (statement == NULL) { return; }
    NSArray *bindings = [clause objectForKey:@"bindings"];
    [bindings enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        
        // string
        if ([obj isKindOfClass:[NSString class]]) {
            sqlite3_bind_text(statement, (idx + 1), [obj UTF8String], -1, SQLITE_TRANSIENT);
        }
        
        // number
        else if ([obj isKindOfClass:[NSNumber class]]) {
            const char *type = [obj objCType];
            if (strcmp(type, @encode(BOOL)) == 0 ||
                strcmp(type, @encode(int)) == 0 ||
                strcmp(type, @encode(short)) == 0 ||
                strcmp(type, @encode(long)) == 0 ||
                strcmp(type, @encode(long long)) == 0 ||
                strcmp(type, @encode(unsigned short)) == 0 ||
                strcmp(type, @encode(unsigned int)) == 0 ||
                strcmp(type, @encode(unsigned long)) == 0 ||
                strcmp(type, @encode(unsigned long long)) == 0) {
                sqlite3_bind_int64(statement, (idx + 1), [obj longLongValue]);
            }
            else if (strcmp(type, @encode(double)) == 0 ||
                     strcmp(type, @encode(float)) == 0) {
                sqlite3_bind_double(statement, (idx + 1), [obj doubleValue]);
            }
        }
        
        // managed object id
        else if ([obj isKindOfClass:[NSManagedObjectID class]]) {
            id referenceObject = [self referenceObjectForObjectID:obj];
            sqlite3_bind_int64(statement, (idx + 1), [referenceObject unsignedLongLongValue]);
        }
        
        // managed object
        else if ([obj isKindOfClass:[NSManagedObject class]]) {
            NSManagedObjectID *objectID = [obj objectID];
            id referenceObject = [self referenceObjectForObjectID:objectID];
            sqlite3_bind_int64(statement, (idx + 1), [referenceObject unsignedLongLongValue]);
        }
        
        // date
        else if ([obj isKindOfClass:[NSDate class]]) {
            sqlite3_bind_double(statement, (idx + 1), [obj timeIntervalSince1970]);
        }
        
        // data
        else if([obj isKindOfClass:[NSData class] ]){
            sqlite3_bind_blob(statement, (idx + 1), [obj bytes], [obj length], SQLITE_TRANSIENT);
        }
        
    }];
}

-(NSPredicate*)cleansePredicate:(NSComparisonPredicate*)comparisonPredicate OfVariable:(NSString*)variable{
    NSString *oldPredString = [comparisonPredicate predicateFormat];
    
    if(comparisonPredicate.rightExpression.constantValue && [comparisonPredicate.rightExpression.constantValue isKindOfClass:[NSArray class]]){
        NSString *leftExpressionString =  [comparisonPredicate.leftExpression.description stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"$%@.", variable] withString:@""];
        NSExpression *newLeftExpression = [NSExpression expressionWithFormat: leftExpressionString ];
        NSPredicate *returnPredicate=  [NSComparisonPredicate
                                                predicateWithLeftExpression:newLeftExpression
                                                  rightExpression:comparisonPredicate.rightExpression
                                                         modifier: [comparisonPredicate comparisonPredicateModifier]
                                                             type: [comparisonPredicate predicateOperatorType]
                                                          options: [comparisonPredicate options]];
        return returnPredicate;
    }else{
        NSString *newPredString = [oldPredString stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"$%@.", variable] withString:@""];
        return [NSPredicate predicateWithFormat: newPredString];

    }
//    NSRange range = [newPredString rangeOfString:@"ANY "];
//    if (range.location == 0)
//    {
//        newPredString = [newPredString stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"ANY "] withString:@""];
//    }
}

-(NSPredicate*)rebuildExpressionPredicateAsForSubquery:(NSPredicate*)originalPredicate andReplaceVariable:(NSString*)variable{
    
    if([originalPredicate isKindOfClass:[NSCompoundPredicate class]]){
        NSMutableArray *predicateArray = [NSMutableArray array];
        for(NSPredicate *pred in ((NSCompoundPredicate*) originalPredicate).subpredicates){
            [predicateArray addObject:[self rebuildExpressionPredicateAsForSubquery:pred andReplaceVariable: variable]];
        }
        NSCompoundPredicateType compPredType = [( (NSCompoundPredicate*) originalPredicate) compoundPredicateType];
        if(compPredType == NSOrPredicateType){
            return [NSCompoundPredicate orPredicateWithSubpredicates:predicateArray];
        }else if(compPredType == NSAndPredicateType){
            return [NSCompoundPredicate andPredicateWithSubpredicates:predicateArray];
        }else if(compPredType == NSNotPredicateType){
            return [NSCompoundPredicate notPredicateWithSubpredicate:[predicateArray objectAtIndex:0]];
        }
        
    }
    if( [originalPredicate isKindOfClass:[NSComparisonPredicate class]]){
       return [self cleansePredicate: ((NSComparisonPredicate*)originalPredicate) OfVariable: variable ];
    }
        // ? What else is there?
        return nil;
}

- (void)parseExpression:(NSExpression *)expression
            inPredicate:(NSComparisonPredicate *)predicate
         inFetchRequest:(NSFetchRequest *)request
                context:context
               operator:(NSDictionary *)operator
                operand:(id *)operand
               bindings:(id *)bindings {
//    [self binaryValueFromExpression: expression];
    
    NSExpressionType type = [expression expressionType];
    
    id value = nil;
    NSEntityDescription *entity = [request entity];
    NSString *tableName = [self tableNameForEntity:entity];
    
    if(type==NSSubqueryExpressionType){
        
    }
    
    // key path expressed as function expression
    if (type == NSFunctionExpressionType) {
        NSString *methodString = NSStringFromSelector(@selector(valueForKeyPath:));
        
        NSExpression *argumentExpression;
        if ([[expression function] isEqualToString:methodString]) {
            argumentExpression = [[expression arguments] objectAtIndex:0];
            
            if ([argumentExpression expressionType] == NSConstantValueExpressionType) {
                value = [argumentExpression constantValue];
                type = NSKeyPathExpressionType;
            }else{
                NSString *aggregateFunctionString = [argumentExpression.constantValue stringByReplacingOccurrencesOfString:@"@" withString:@""];
                NSExpression *subqueryExpression = expression.operand;
                NSString *subqueryRelationString = ((NSExpression*)subqueryExpression.collection).keyPath;
                NSRelationshipDescription *relationshipDesc = [[request.entity relationshipsByName] objectForKey:subqueryRelationString	] ;
                
                NSEntityDescription *subqueryEntity = [NSEntityDescription entityForName:relationshipDesc.destinationEntity.name inManagedObjectContext: context];
                
                NSFetchRequest *subqueryMockFetchRequest = [[NSFetchRequest alloc] init ];
                [subqueryMockFetchRequest setEntity: subqueryEntity];
                NSPredicate *predicate = [self rebuildExpressionPredicateAsForSubquery: subqueryExpression.predicate andReplaceVariable:subqueryExpression.variable];

                
                [subqueryMockFetchRequest setPredicate:predicate];
                NSDictionary *whereClause = [self whereClauseWithFetchRequest:subqueryMockFetchRequest andContext:context];
                NSString *relationColumn = [self foreignKeyColumnForRelationship: relationshipDesc.inverseRelationship];
                [self tableNameForEntity:relationshipDesc.destinationEntity];
                
                NSMutableArray *joinStatementsArray = [NSMutableArray array];
                NSMutableSet *joinStatementsSet = [NSMutableSet set];

                NSString *predicateString = [[subqueryMockFetchRequest predicate] predicateFormat];
                if (predicateString != nil ) {
                    NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:@"\\b([a-zA-Z]\\w*\\.[^= ]+)\\b" options:0 error:nil];
                    NSArray* dottedRelationMatches = [regex matchesInString:predicateString options:0 range:NSMakeRange(0, [predicateString length])];
                    
                    NSRegularExpression* regexForAnyAllRelations = [NSRegularExpression regularExpressionWithPattern:@"(?<=\\b(ANY|ALL)(\\s))(\\S+)" options:0 error:nil];
                    NSArray* anyAllRelationsMatches = [regexForAnyAllRelations matchesInString:predicateString options:0 range:NSMakeRange(0, [predicateString length])];
                    
                    NSMutableArray *matches = [NSMutableArray arrayWithArray:anyAllRelationsMatches];
                    [matches addObjectsFromArray:dottedRelationMatches];
                    
                    for ( NSTextCheckingResult* match in matches )
                    {
                        NSString* matchText = [predicateString substringWithRange:[match range]];
                        if ([matchText hasSuffix:@".@count"]) {
                            // @count queries should be handled by sub-expressions rather than joins
                            continue;
                        }
                        if ([self maybeAddJoinStatementsForKey:matchText toStatementArray:joinStatementsArray withExistingStatementSet:joinStatementsSet rootEntity:subqueryEntity andJoinType:@"JOIN"]) {
                            [subqueryMockFetchRequest setReturnsDistinctResults:YES];
                        }
                    }
                }
                NSString *joinStatementsString = @"";
                if (joinStatementsArray.count > 0) {
                     joinStatementsString = [joinStatementsArray componentsJoinedByString:@" "];
                }

                
                NSString *subquery = [NSString stringWithFormat:@"( SELECT %@(*) FROM %@  %@  %@ AND %@ = %@.__objectId  )",
                                      aggregateFunctionString,
                                      [self tableNameForEntity:relationshipDesc.destinationEntity],
                                      joinStatementsString,
                                      [whereClause objectForKey:@"query"],
                                      relationColumn,
                                      [self tableNameForEntity: request.entity]
                                    ];
                *operand = subquery;
                *bindings = [whereClause objectForKey:@"bindings"];
                return;
            }
        }
    }
    
    // reference a column in the query
    if (type == NSKeyPathExpressionType) {
        if (value == nil) {
            value = [expression keyPath];
        }
        
        NSMutableArray *pathComponents = [[value componentsSeparatedByString:@"."] mutableCopy];
        NSString *firstCompontent = [pathComponents firstObject];
        NSString *lastComponent = [pathComponents lastObject];
        
        BOOL foundPredicate = NO;
        NSDictionary *properties = [entity propertiesByName];
        id firstProperty = [properties objectForKey:firstCompontent];
        id lastProperty = [properties objectForKey:lastComponent];
        id property = [properties objectForKey:value];
        if ([property isKindOfClass:[NSRelationshipDescription class]] ||
            ( ([firstProperty isKindOfClass:[NSRelationshipDescription class]] || [lastProperty isKindOfClass:[NSRelationshipDescription class]] ) && [value rangeOfString:@"@"].location == NSNotFound )) {
            NSString *relationString;
            
            // We terminate when there is one item left since that is the field of interest
            NSEntityDescription *currentEntity = request.entity;
            int loopMax = (int) (pathComponents.count == 1 ? 1 : pathComponents.count - 1);
            for (int i = 0 ; i < loopMax; i++) {
                NSArray *miniKeyArray =   ( pathComponents.count > 1) ? [pathComponents subarrayWithRange: NSMakeRange(0, i+2)] : @[pathComponents[0], @"foobbbbears"] ;
                // alt names for tables for safety
                NSRelationshipDescription *relation = [[currentEntity relationshipsByName] objectForKey: pathComponents[i]];
//                NSRelationshipDescription *inverse = [relation inverseRelationship];
            
                if(relation.isToMany){
                    relationString = [self foreignKeyColumnForToManyRelationship:relation];
                    tableName = [self joinedTableNameForComponents: miniKeyArray forRelationship: YES];
                }else{
                    relationString = [self foreignKeyColumnForRelationship:relation];
                }
                

                NSString *nextComponent = i+1 < pathComponents.count ? pathComponents[i+1] : nil;
                if(nextComponent){
                    NSDictionary *foreignEntityRelations = relation.destinationEntity.relationshipsByName;
                    NSRelationshipDescription *secondRelation = [foreignEntityRelations objectForKey:nextComponent];
                    if(secondRelation){
                        tableName = [self joinedTableNameForComponents: @[pathComponents[i+1], @""] forRelationship: YES];
                        if(secondRelation.isToMany){
                            relationString = [self foreignKeyColumnForToManyRelationship:secondRelation];
                        }else{
                            relationString = [self foreignKeyColumnForRelationship:secondRelation];
                        }

                    }else{
                        relationString = nextComponent;
                        tableName = [self joinedTableNameForComponents: miniKeyArray forRelationship: NO];
                    }
                }
                currentEntity = relation.destinationEntity;
            }
            
            
            
            value = [NSString stringWithFormat:@"%@.%@",
                     tableName,
                     relationString];
        }
        else if (property != nil) {
            value = [NSString stringWithFormat:@"%@.%@",
                     tableName,
                     value];
        }
        else if ([value rangeOfString:@"."].location != NSNotFound) {
            // We have a join table property, we need to rewrite the query.
            NSMutableArray *pathComponents = [[value componentsSeparatedByString:@"."] mutableCopy];
            NSString *lastComponent = [pathComponents lastObject];
            
            NSMutableString *sumBuilder = [NSMutableString stringWithString:@"HAVING SUM("];
            // Check if this is a sum, we assume it is and discard the results if not
            for (int i = 0 ; i < pathComponents.count; i++) {
                NSString* part = [pathComponents objectAtIndex:i];
                if([part isEqualToString:@"@sum"]) {
                    foundPredicate = YES;
                } else {
                    // Check if it is a relation
                    NSRelationshipDescription *rel = [[entity relationshipsByName]
                                                  objectForKey:[pathComponents objectAtIndex:i]];
                    NSRelationshipDescription *inverse = [rel inverseRelationship];
                    if(rel != nil) {
                        if ([rel isToMany] && [inverse isToMany]) {
                            [request setReturnsDistinctResults:YES];
                            [sumBuilder appendString:[NSString stringWithFormat:@"[%@].",[[inverse entity] name]]];
                        }
                        else {
                            [sumBuilder appendString:[NSString stringWithFormat:@"[%@].", [pathComponents objectAtIndex:i]]];
                        }
                    } else {
                        [sumBuilder appendString:[pathComponents objectAtIndex:i]];
                        [sumBuilder appendString:@")END_HAVING"];
                        if(foundPredicate) { // Was a SUM
                            value = [NSString stringWithString:sumBuilder];
                            break;
                        }
                    }
                }//
            }
            
            
            // Test if the last component is actually a predicate
            // TODO: Conflict if the model has an attribute named length?
            if ([lastComponent isEqualToString:@"length"]){
                                
                // We terminate when there is one item left since that is the field of interest
                for (int i = 0 ; i < pathComponents.count - 1; i++) {
                    NSRelationshipDescription *rel = [[entity relationshipsByName]
                                                      objectForKey:[pathComponents objectAtIndex:i]];
                    NSRelationshipDescription *inverse = [rel inverseRelationship];
                    
                    if(rel != nil) {
                        if ([rel isToMany] && [inverse isToMany]) {
                            [pathComponents replaceObjectAtIndex:0 withObject:
                             [NSString stringWithFormat:@"[%@]",[[inverse entity] name]]];
                            [request setReturnsDistinctResults:YES];
                        }
                        else {
                            // TODO: This should probably be objectAtIndex:i, need to retest now that changed
                            NSString* asComponent = [NSString stringWithFormat:@"[%@]", [pathComponents objectAtIndex:i]];
                            [pathComponents replaceObjectAtIndex:0 withObject:asComponent];
                        }
                    }
                }
                value = [NSString stringWithFormat:@"LENGTH(%@)", [[pathComponents subarrayWithRange:NSMakeRange(0, pathComponents.count - 1)] componentsJoinedByString:@"."]];
                foundPredicate = YES;
            }

            // We should probably provide for @count on nested relationships
            // This will do for now though
            if ([lastComponent isEqualToString:@"@count"] && pathComponents.count == 2){
                NSRelationshipDescription *rel = [self relationshipForEntity:entity
                                                                        name:[pathComponents objectAtIndex:0]];
                NSRelationshipDescription *inverse = [rel inverseRelationship];
                NSString * destinationName;
                NSString * destinationColumn;
                if(rel.isToMany && inverse.isToMany){
                    destinationName = [self tableNameForRelationship: rel];
                    destinationColumn = [self foreignKeyColumnForToManyRelationship: rel.inverseRelationship];
                }else{
                    destinationName  = [self tableNameForEntity:rel.destinationEntity];
                    destinationColumn = [self foreignKeyColumnForRelationship:rel.inverseRelationship];
                }
                NSString * entityTableName = [self tableNameForEntity:entity];

                value = [NSString stringWithFormat:@"(SELECT COUNT(*) FROM %@ [%@] WHERE [%@].%@ = %@.__objectid",
                         destinationName,
                         rel.name,
                         rel.name,
                         destinationColumn,
                         entityTableName];
                if (rel.destinationEntity.superentity != nil) {
                    value = [value stringByAppendingString:
                             [NSString stringWithFormat:@" AND [%@]._entityType = %u",
                              rel.name,
                              rel.destinationEntity.name.hash]];
                }
                value = [value stringByAppendingString:@")"];
                foundPredicate = YES;
            }
            
            if(!foundPredicate) {
                NSString * lastComponentName = lastComponent;
                
                // Handle the case where the last component points to a relationship rather than a simple attribute
                __block NSDictionary * subProperties = properties;
                __block id property = nil;
                [pathComponents enumerateObjectsUsingBlock:^(NSString * comp, NSUInteger idx, BOOL * stop) {
                    property = [subProperties objectForKey:comp];
                    if ([property isKindOfClass:[NSRelationshipDescription class]]) {
                        NSEntityDescription * entity = [property destinationEntity];
                        subProperties = entity.propertiesByName;
                    } else {
                        property = nil;
                        *stop = YES;
                    }
                }];
                
                if ([property isKindOfClass:[NSRelationshipDescription class]]) {
                    NSRelationshipDescription *desc = (NSRelationshipDescription *)property;
                    NSRelationshipDescription *inverse = [desc inverseRelationship];
                    
                    if ([desc isToMany] && [inverse isToMany]) {
                        // last component is a many-to-many relation name
                        [request setReturnsDistinctResults:YES];
                        lastComponentName = @"__objectID";
                    }
                    else {
                        lastComponentName = [self foreignKeyColumnForRelationship:property];
                    }
                }
                
                value = [NSString stringWithFormat:@"%@.%@",
                     [self joinedTableNameForComponents:pathComponents forRelationship:NO], lastComponentName];
            }
        }
        *operand = value;
    }
    else if (type == NSEvaluatedObjectExpressionType) {
        *operand = @"__objectid";
    }
    
    // a value to be bound to the query
    else if (type == NSConstantValueExpressionType) {
        value = [expression constantValue];
        if ([value isKindOfClass:[NSSet class]]) {
            NSUInteger count = [value count];
            NSArray *parameters = [NSArray cmdArrayWithObject:@"?" times:count];
            *bindings = [value allObjects];
            *operand = [NSString stringWithFormat:
                        [operator objectForKey:@"format"],
                        [parameters componentsJoinedByString:@", "]];
        }
        else if ([value isKindOfClass:[NSDate class]]) {
            value = [NSNumber numberWithDouble:[value timeIntervalSince1970]];
            *bindings = value;
            *operand = @"?";
        }
        else if ([value isKindOfClass:[NSArray class]]) {
            NSUInteger count = [value count];
            NSArray *parameters = [NSArray cmdArrayWithObject:@"?" times:count];
            *bindings = value;
            *operand = [NSString stringWithFormat:
                        [operator objectForKey:@"format"],
                        [parameters componentsJoinedByString:@", "]];
        }
        else if ([value isKindOfClass:[NSString class]]) {
            if ([predicate options] & NSCaseInsensitivePredicateOption) {
                *operand = @"UPPER(?)";
                *bindings = [NSString stringWithFormat:
                             [operator objectForKey:@"format"],
                             [[[value uppercaseString]
                               stringByReplacingOccurrencesOfString:@"*" withString:@"%"]
                              stringByReplacingOccurrencesOfString:@"?" withString:@"_"]];
            }
            else {
                *operand = @"?";
                *bindings = [NSString stringWithFormat:
                             [operator objectForKey:@"format"],
                             [[value stringByReplacingOccurrencesOfString:@"*" withString:@"%"]
                                stringByReplacingOccurrencesOfString:@"?" withString:@"_"]];
            }
        } else if ([value isKindOfClass:[NSManagedObject class]] || [value isKindOfClass:[NSManagedObjectID class]]) {
            NSManagedObjectID * objectId = [value isKindOfClass:[NSManagedObject class]] ? [value objectID]:value;
            *operand = @"?";
            // We're not going to be able to look up an object with a temporary id, it hasn't been inserted yet
            if ([objectId isTemporaryID]) {
                // Just look for an id we know will never match
                *bindings = @"-1";
            } else {
                unsigned long long key = [[self referenceObjectForObjectID:objectId] unsignedLongLongValue];
                *bindings = [NSString stringWithFormat:@"%llu",key];
            }
        }
        else if (!value || value == [NSNull null]) {
            *bindings = nil;
            *operand = @"NULL";
        }
        else if([value isKindOfClass:[NSData class]]){
            *bindings = value;
            *operand = @"?";
        }
        else {
            *bindings = value;
            *operand = @"?";
        }
    }else if(type==NSAggregateExpressionType){
        NSArray *array = (NSArray*)expression.constantValue;
        *bindings = array;
        *operand = [NSArray cmdArrayWithObject:@"?" times:array.count];
    }
    
    // unsupported type
    else {
        NSLog(@"%s Unsupported expression type %ld %@ ", __PRETTY_FUNCTION__, (unsigned long)type, expression);
    }
}

- (NSString *)foreignKeyColumnForRelationshipP:(NSRelationshipDescription *)relationship {
    NSEntityDescription *destination = [relationship destinationEntity];
    return [NSString stringWithFormat:@"%@.__objectid", destination.name];
}

- (NSString *)foreignKeyColumnForToManyRelationship:(NSRelationshipDescription *)relationship {
    NSEntityDescription *destination = [relationship destinationEntity];
    return [NSString stringWithFormat:@"%@__objectid", destination.name];
}


- (NSString *)foreignKeyColumnForRelationship:(NSRelationshipDescription *)relationship {
    return [NSString stringWithFormat:@"%@__objectid", relationship.name];
}

- (NSString *) joinedTableNameForComponents: (NSArray *) componentsArray forRelationship:(BOOL)forRelationship{
    assert(componentsArray.count > 0);
    NSString *tableName = [[componentsArray subarrayWithRange:NSMakeRange(0, componentsArray.count - 1)] componentsJoinedByString:@"."];
    if (forRelationship) {
        return [NSString stringWithFormat: @"[%@_rel]", tableName];
    }
    else {
        return [NSString stringWithFormat:@"[%@]", tableName];
    }
}

// First degree relationship by name
- (NSRelationshipDescription *) relationshipForEntity: (NSEntityDescription *) enitity
                                                 name: (NSString *) name {
    return [[enitity relationshipsByName] objectForKey:name];
}

@end

#pragma mark - category implementations

@implementation NSArray (EncryptedStoreAdditions)

+ (NSArray *)cmdArrayWithObject:(id)object times:(NSUInteger)times {
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:times];
    for (NSUInteger i = 0; i < times; i++) {
        [array addObject:object];
    }
    return [array copy];
}

- (NSArray *)cmdCollect:(id (^) (id object))block {
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:[self count]];
    [self enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [array addObject:block(obj)];
    }];
    return array;
}

- (NSArray *)cmdFlatten {
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:[self count]];
    [self enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([obj isKindOfClass:[NSArray class]]) {
            [array addObjectsFromArray:[obj cmdFlatten]];
        }
        else {
            [array addObject:obj];
        }
    }];
    return array;
}

@end

#pragma mark - incremental store node subclass

@implementation CMDIncrementalStoreNode

- (id)initWithObjectID:(NSManagedObjectID *)objectID withValues:(NSDictionary *)values version:(uint64_t)version withProperties:(NSArray *)properties
{
    self = [super initWithObjectID:objectID withValues:values version:version];
    if (self) {
        self.allProperties = properties;
    }
    return self;
    
}

- (void)updateWithChangedValues:(NSDictionary *)changedValues
{
    NSMutableDictionary * updateValues = [NSMutableDictionary dictionaryWithCapacity:self.allProperties.count];
    for (NSPropertyDescription * key in self.allProperties) {
        id newValue = [changedValues objectForKey:key.name];
        if (newValue) {
            [updateValues setObject:newValue forKey:key.name];
        } else {
            [updateValues setObject:[self valueForPropertyDescription:key] forKey:key.name];
        }
    }
    [self updateWithValues:updateValues version:self.version+1];
}

@end
