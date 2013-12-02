//  Copyright (c) 2012 The MITRE Corporation.

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

@end

@implementation EncryptedStore {

    // database resources
    sqlite3 *database;

    // cache money
    NSMutableDictionary *objectIDCache;
    NSMutableDictionary *nodeCache;
    NSMutableDictionary *objectCountCache;

}

+ (NSPersistentStoreCoordinator *)makeStoreWithDatabaseURL:(NSURL *)databaseURL managedObjectModel:(NSManagedObjectModel *)objModel :(NSString*)passcode
{
    NSDictionary *options = @{ EncryptedStorePassphraseKey : passcode };
    NSPersistentStoreCoordinator * persistentCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:objModel];
    
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
    NSString *dbName = NSBundle.mainBundle.infoDictionary [@"CFBundleDisplayName"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *applicationSupportURL = [[fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
    [fileManager createDirectoryAtURL:applicationSupportURL withIntermediateDirectories:NO attributes:nil error:nil];
    NSURL *databaseURL = [applicationSupportURL URLByAppendingPathComponent:[dbName stringByAppendingString:@".sqlite"]];
    
    return [self makeStoreWithDatabaseURL:databaseURL managedObjectModel:objModel:passcode];
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
        NSDictionary *condition = [self whereClauseWithFetchRequest:fetchRequest];
        NSDictionary *ordering = [self orderClause:fetchRequest:entity];
        NSString *limit = ([fetchRequest fetchLimit] > 0 ? [NSString stringWithFormat:@" LIMIT %ld", (unsigned long)[fetchRequest fetchLimit]] : @"");
        BOOL isDistinctFetchEnabled = [fetchRequest returnsDistinctResults];

        // return objects or ids
        if (type == NSManagedObjectResultType || type == NSManagedObjectIDResultType) {
            NSString *string = [NSString stringWithFormat:
                                @"SELECT %@%@.ID FROM %@ %@%@%@%@;",
                                (isDistinctFetchEnabled)?@"DISTINCT ":@"",
                                table,
                                table,
                                joinStatement,
                                [condition objectForKey:@"query"],
                                [ordering objectForKey:@"order"],
                                limit];

            sqlite3_stmt *statement = [self preparedStatementForQuery:string];
            [self bindWhereClause:condition toStatement:statement];
            while (sqlite3_step(statement) == SQLITE_ROW) {
                unsigned long long primaryKey = sqlite3_column_int64(statement, 0);
                NSManagedObjectID *objectID = [self newObjectIDForEntity:entity referenceObject:@(primaryKey)];
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
            NSString * propertiesToFetchString = [self columnsClauseWithProperties:propertiesToFetch];

            // TODO: Need a test case to reach here, or remove it entirely
            // NOTE - this must run on only one table (no joins) we can select individual
            // properties of a specific table. To support joins we would need to know
            // that propertiesToFetch could somehow specific a field in a relationship table.
            NSString *string = [NSString stringWithFormat:
                                @"SELECT %@%@ FROM %@%@%@%@;",
                                (isDistinctFetchEnabled)?@"DISTINCT ":@"",
                                propertiesToFetchString,
                                table,
                                [condition objectForKey:@"query"],
                                [ordering objectForKey:@"order"],
                                limit];
            sqlite3_stmt *statement = [self preparedStatementForQuery:string];
            [self bindWhereClause:condition toStatement:statement];
            while (sqlite3_step(statement) == SQLITE_ROW) {
                NSMutableDictionary* singleResult = [NSMutableDictionary dictionary];
                [propertiesToFetch enumerateObjectsUsingBlock:^(id property, NSUInteger idx, BOOL *stop) {
                    id value = [self valueForProperty:property inStatement:statement atIndex:idx];
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
                                @"SELECT COUNT(*) FROM %@%@%@;",
                                table,
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
            [columns addObject:key];
            [keys addObject:key];
        }
        else if ([obj isKindOfClass:[NSRelationshipDescription class]]) {
            NSRelationshipDescription *inverse = [obj inverseRelationship];

            // Handle one-to-many and one-to-one
            if (![obj isToMany] || [inverse isToMany]) {
                NSString *column = [self foreignKeyColumnForRelationship:obj];
                [columns addObject:column];
                [keys addObject:key];
            }

        }
    }];

    // prepare query
    NSString *string = [NSString stringWithFormat:
                        @"SELECT %@ FROM %@ WHERE ID=?;",
                        [columns componentsJoinedByString:@", "],
                        [self tableNameForEntity:entity]];
    sqlite3_stmt *statement = [self preparedStatementForQuery:string];

    // run query
    sqlite3_bind_int64(statement, 1, primaryKey);
    if (sqlite3_step(statement) == SQLITE_ROW) {
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
        [keys enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSPropertyDescription *property = [properties objectForKey:obj];
            id value = [self valueForProperty:property inStatement:statement atIndex:idx];
            if (value) { [dictionary setObject:value forKey:obj]; }
        }];
        sqlite3_finalize(statement);
        NSIncrementalStoreNode *node = [[CMDIncrementalStoreNode alloc]
                                        initWithObjectID:objectID
                                        withValues:dictionary
                                        version:1];
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


    // one side of a one-to-many and one-to-one
    if (![relationship isToMany] || [inverseRelationship isToMany]) {
        NSString *string = [NSString stringWithFormat:
                            @"SELECT %@ FROM %@ WHERE ID=?",
                            [self foreignKeyColumnForRelationship:relationship],
                            [self tableNameForEntity:sourceEntity]];
        statement = [self preparedStatementForQuery:string];
        sqlite3_bind_int64(statement, 1, key);
    } else {
        NSString *string = [NSString stringWithFormat:
                            @"SELECT ID FROM %@ WHERE %@=?",
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
                    if (![oldModel isEqual:newModel]) {

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
    if (passphrase) {
        const char *string = [passphrase UTF8String];
        int status = sqlite3_key(database, string, strlen(string));
        string = NULL;
        passphrase = nil;
        return (status == SQLITE_OK);
    }
    passphrase = nil;
    return YES;
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

    if (success) {
        [[model entities] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            if (![self createTableForEntity:obj error:error]) {
                success = NO;
                *stop = YES;
            }
        }];
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

- (NSArray*)columnNamesForEntity:(NSEntityDescription*)entity {
    NSMutableSet *columns = [NSMutableSet setWithCapacity:entity.properties.count];

    NSArray *attributeNames = [[entity attributesByName] allKeys];
    
    for (NSString *attributeName in attributeNames) {
            [columns addObject:[NSString stringWithFormat:@"'%@'", attributeName]];
    }
    
    [[entity relationshipsByName] enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        // handle one-to-many and one-to-one
        NSString *column = [NSString stringWithFormat:@"'%@'", [self foreignKeyColumnForRelationship:obj]];
        [columns addObject:column];
    }];

    for (NSEntityDescription *subentity in entity.subentities) {
        [columns addObjectsFromArray:[self columnNamesForEntity:subentity]];
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
    NSMutableArray *columns = [NSMutableArray arrayWithObject:@"'id' integer primary key"];
    if (entity.subentities.count > 0) {
        // NOTE: Will use '-[NSString hash]' to determine the entity type so we can use
        //       faster integer-indexed queries.  Any string greater than 96-chars is
        //       not guaranteed to produce a unique hash value, but for entity names that
        //       shouldn't be a problem.
        [columns addObject:@"'_entityType' integer"];
    }

    [columns addObjectsFromArray:[self columnNamesForEntity:entity]];

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
    }

    return result;
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
    NSString *sourceEntityName = [sourceEntity name];
    NSString *temporaryTableName = [NSString stringWithFormat:@"_T_%@", sourceEntityName];
    NSString *destinationTableName = [destinationEntity name];

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
        NSMutableArray *columns = [NSMutableArray arrayWithObject:@"'id'"];
        NSDictionary *properties = [entity propertiesByName];
        [properties enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            if ([obj isKindOfClass:[NSAttributeDescription class]]) {
                [keys addObject:key];
                [columns addObject:[NSString stringWithFormat:@"'%@'", key]];
            }
            else if ([obj isKindOfClass:[NSPropertyDescription class]]) {
                NSRelationshipDescription *inverse = [obj inverseRelationship];

                // one side of both one-to-one and one-to-many
                if (![obj isToMany] || [inverse isToMany]){
                    [keys addObject:key];
                    NSString *column = [NSString stringWithFormat:@"'%@'", [self foreignKeyColumnForRelationship:obj]];
                    [columns addObject:column];
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
            @try {
              [self
                 bindProperty:property
                 withValue:[object valueForKey:obj]
                 forKey:obj
                  toStatement:statement
                  atIndex:(idx + 2)];
            }
            @catch (NSException *exception) {
                // TODO: Something is off the previous statement will die on some
                //       Many-to-many statements.  But ignoring it still works.
                //       Warrants specific testing, and figuring out where it went wrong
                NSLog(@"Exception: %@", exception.description);
                NSLog(@"Trace: %@", [exception callStackSymbols]);
            }
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
        NSIncrementalStoreNode *node = [cache objectForKey:objectID];
        uint64_t version = ([node version] + 1);
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
                // TODO: More edge case testing and handling
                if (![(NSRelationshipDescription *) property isToMany]||[[(NSRelationshipDescription *) property inverseRelationship] isToMany]) {
                  NSString *column = [self foreignKeyColumnForRelationship:property];
                  [columns addObject:[NSString stringWithFormat:@"%@=?", column]];
                  [keys addObject:key];
                }
            }
        }];

        // return if nothing needs updating
        if ([keys count] == 0) {
#if USE_MANUAL_NODE_CACHE
            [node updateWithValues:cacheChanges version:version];
#endif
            return;
        }

        // prepare statement
        NSString *string = [NSString stringWithFormat:
                            @"UPDATE %@ SET %@ WHERE ID=?;",
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
            [node updateWithValues:cacheChanges version:version];
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

- (BOOL)handleDeletedObjectsInSaveRequest:(NSSaveChangesRequest *)request error:(NSError **)error {
    BOOL __block success = YES;
    [[request deletedObjects] enumerateObjectsUsingBlock:^(NSManagedObject *object, BOOL *stop) {

        // get identifying information
        NSEntityDescription *entity = [object entity];
        NSNumber *objectID = [self referenceObjectForObjectID:[object objectID]];

        // delete object
        NSString *string = [NSString stringWithFormat:
                            @"DELETE FROM %@ WHERE ID=?;",
                            [self tableNameForEntity:entity]];
        sqlite3_stmt *statement = [self preparedStatementForQuery:string];
        sqlite3_bind_int64(statement, 1, [objectID unsignedLongLongValue]);
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
    return [targetEntity name];
}

- (sqlite3_stmt *)preparedStatementForQuery:(NSString *)query {
    static BOOL debug = NO;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        debug = [[NSUserDefaults standardUserDefaults] boolForKey:@"com.apple.CoreData.SQLDebug"];
    });
    if (debug) { NSLog(@"SQL DEBUG: %@", query); }
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(database, [query UTF8String], -1, &statement, NULL) == SQLITE_OK) { return statement; }
    return NULL;
}

- (NSDictionary *)orderClause:(NSFetchRequest *) fetchRequest
                             :(NSEntityDescription *) entity {
    NSArray *descriptors = [fetchRequest sortDescriptors];
    NSString *order = @"";

    NSMutableArray *columns = [NSMutableArray arrayWithCapacity:[descriptors count]];
    [descriptors enumerateObjectsUsingBlock:^(NSSortDescriptor *desc, NSUInteger idx, BOOL *stop) {
        // We throw and exception in the join if the key is more than one relationship deep.
        // We do need to detect the relationship though to know what table to prefix the key
        // with.
        NSString *tableName = [self tableNameForEntity:fetchRequest.entity];
        NSString *key = [desc key];
        if ([desc.key rangeOfString:@"."].location != NSNotFound) {
            NSArray *components = [desc.key componentsSeparatedByString:@"."];
            tableName = [self joinedTableNameForComponents:components];
            key = [components lastObject];
        }
        [columns addObject:[NSString stringWithFormat:
                            @"%@.%@ %@",
                            tableName,
                            key,
                            ([desc ascending]) ? @"ASC" : @"DESC"]];
    }];
    if (columns.count) {
        order = [NSString stringWithFormat:@" ORDER BY %@", [columns componentsJoinedByString:@", "]];
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
            [self maybeAddJoinStatementsForKey:sortKey toStatementArray:joinStatementsArray withExistingStatementSet:joinStatementsSet rootEntity:entity];
        }
    }
    NSString *predicateString = [fetchRequest predicate].predicateFormat;
    if (predicateString != nil ) {
        NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:@"\\b([a-zA-Z]\\w*\\.[^= ]+)\\b" options:0 error:nil];
        NSArray* matches = [regex matchesInString:predicateString options:0 range:NSMakeRange(0, [predicateString length])];
        for ( NSTextCheckingResult* match in matches )
        {
            NSString* matchText = [predicateString substringWithRange:[match range]];
            [self maybeAddJoinStatementsForKey:matchText toStatementArray:joinStatementsArray withExistingStatementSet:joinStatementsSet rootEntity:entity];
        }
    }
    if (joinStatementsArray.count > 0) {
        return [joinStatementsArray componentsJoinedByString:@" "];
    }
     
    return @"";
}

- (void) maybeAddJoinStatementsForKey: (NSString *) key
          toStatementArray: (NSMutableArray *) statementArray
          withExistingStatementSet: (NSMutableSet *) statementsSet
                           rootEntity: (NSEntityDescription *) rootEntity {
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
    NSString *lastTableName = [self tableNameForEntity:currentEntity];
    for (int i = 0 ; i < keysArray.count - 1; i++) {
        NSString *nextTableName = [self joinedTableNameForComponents:
                                   [keysArray subarrayWithRange: NSMakeRange(0, i+2)]];
        NSRelationshipDescription *rel = [[currentEntity relationshipsByName]
                                          objectForKey:[keysArray objectAtIndex:i]];
        if (rel != nil) {
            // We bracket all join table names so that periods are ok.
            NSString *joinTableAsClause = [NSString stringWithFormat:@"%@ AS %@",
                                           [self tableNameForEntity:rel.destinationEntity],
                                           nextTableName];
            NSString *joinTableOnClause = nil;
            if (rel.isToMany) {
                joinTableOnClause = [NSString stringWithFormat:@"%@.ID = %@.%@",
                                     lastTableName,
                                     nextTableName,
                                     [self foreignKeyColumnForRelationship:rel.inverseRelationship]];
            } else {
                joinTableOnClause = [NSString stringWithFormat:@"%@.%@ = %@.ID",
                                     lastTableName,
                                     [self foreignKeyColumnForRelationship:rel],
                                     nextTableName];
            }
            NSString *fullJoinClause = [NSString stringWithFormat:@"JOIN %@ ON %@", joinTableAsClause, joinTableOnClause];
            currentEntity = rel.destinationEntity;
            lastTableName = nextTableName;
            if (![statementsSet containsObject:fullJoinClause]) {
                [statementsSet addObject:fullJoinClause];
                [statementArray addObject:fullJoinClause];
            }
        }
    }
}

- (NSString *)columnsClauseWithProperties:(NSArray *)properties {
    NSMutableArray *columns = [NSMutableArray arrayWithCapacity:[properties count]];
    [properties enumerateObjectsUsingBlock:^(NSPropertyDescription *prop, NSUInteger idx, BOOL *stop) {
        [columns addObject:[NSString stringWithFormat:
                            @"%@",
                            prop.name
                            ]];
    }];
    if ([columns count]) {
        return [NSString stringWithFormat:@"%@", [columns componentsJoinedByString:@", "]];
    }
    return @"";
}

- (NSNumber *)maximumObjectIDInTable:(NSString *)table {
    NSNumber *value = [objectIDCache objectForKey:table];
    if (value == nil) {
        NSString *string = [NSString stringWithFormat:@"SELECT MAX(ID) FROM %@;", table];
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
                NSValueTransformer *transformer = [NSValueTransformer valueTransformerForName:name];
                NSData *data = [transformer reverseTransformedValue:value];
                sqlite3_bind_blob(statement, index, [data bytes], [data length], SQLITE_TRANSIENT);
            }

            // NSDecimalAttributeType
            // NSObjectIDAttributeType

        }
        else if ([property isKindOfClass:[NSRelationshipDescription class]]) {
            NSNumber *number = [self referenceObjectForObjectID:[value objectID]];
            sqlite3_bind_int64(statement, index, [number unsignedLongLongValue]);
        }
    }
}

- (id)valueForProperty:(NSPropertyDescription *)property
           inStatement:(sqlite3_stmt *)statement
               atIndex:(int)index {
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
            NSValueTransformer *transformer = [NSValueTransformer valueTransformerForName:name];
            const void *bytes = sqlite3_column_blob(statement, index);
            unsigned int length = sqlite3_column_bytes(statement, index);
            if (length > 0) {
                NSData *data = [NSData dataWithBytes:bytes length:length];
                return [transformer transformedValue:data];
            }
        }

        // NSDecimalAttributeType
        // NSObjectIDAttributeType

    }
    else if ([property isKindOfClass:[NSRelationshipDescription class]]) {
        NSEntityDescription *target = [(id)property destinationEntity];
        NSNumber *number = @(sqlite3_column_int64(statement, index));
        return [self newObjectIDForEntity:target referenceObject:number];
    }
    return nil;
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
- (NSDictionary *)whereClauseWithFetchRequest:(NSFetchRequest *)request {
    NSDictionary *result = [self recursiveWhereClauseWithFetchRequest:request predicate:[request predicate]];
    if ([(NSString*)result[@"query"] length] > 0) {
        NSMutableDictionary *mutableResult = [result mutableCopy];
        mutableResult[@"query"] = [NSString stringWithFormat:@" WHERE %@", result[@"query"]];
        result = mutableResult;
    }

    return result;
}

- (NSDictionary *)recursiveWhereClauseWithFetchRequest:(NSFetchRequest *)request predicate:(NSPredicate *)predicate {

//    enum {
//        NSCustomSelectorPredicateOperatorType,
//        NSBetweenPredicateOperatorType
//    };
//    typedef NSUInteger NSPredicateOperatorType;

    static NSDictionary *operators = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        operators = @{
            @(NSEqualToPredicateOperatorType)              : @{ @"operator" : @"=",      @"format" : @"%@" },
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
            NSDictionary *result = [self recursiveWhereClauseWithFetchRequest:request predicate:obj];
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
                     operator:operator
                      operand:&leftOperand
                     bindings:&leftBindings];

        // right expression
        id rightOperand = nil;
        id rightBindings = nil;
        [self parseExpression:comparisonPredicate.rightExpression
                  inPredicate:comparisonPredicate
               inFetchRequest:request
                     operator:operator
                      operand:&rightOperand
                     bindings:&rightBindings];

        // build result and return
        NSMutableArray *comparisonBindings = [NSMutableArray arrayWithCapacity:2];
        if (leftBindings)  [comparisonBindings addObject:leftBindings];
        if (rightBindings) [comparisonBindings addObject:rightBindings];
        if (rightOperand && !rightBindings) {
            if([[operator objectForKey:@"operator"] isEqualToString:@"!="]) {
                query = [@[leftOperand, @"IS NOT", rightOperand] componentsJoinedByString:@" "];
            } else {
                query = [@[leftOperand, @"IS", rightOperand] componentsJoinedByString:@" "];
            }
        } else {
            query = [@[leftOperand, [operator objectForKey:@"operator"], rightOperand] componentsJoinedByString:@" "];
        }
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

    }];
}

/*



 */
- (void)parseExpression:(NSExpression *)expression
            inPredicate:(NSComparisonPredicate *)predicate
         inFetchRequest:(NSFetchRequest *)request
               operator:(NSDictionary *)operator
                operand:(id *)operand
               bindings:(id *)bindings {
    NSExpressionType type = [expression expressionType];

    id value = nil;

    // key path expressed as function expression
    if (type == NSFunctionExpressionType) {
        NSString *methodString = NSStringFromSelector(@selector(valueForKeyPath:));

        if ([[expression function] isEqualToString:methodString]) {
            NSExpression *argumentExpression;
            argumentExpression = [[expression arguments] objectAtIndex:0];

            if ([argumentExpression expressionType] == NSConstantValueExpressionType) {
                value = [argumentExpression constantValue];
                type = NSKeyPathExpressionType;
            }
        }
    }

    // reference a column in the query
    if (type == NSKeyPathExpressionType) {
        if (value == nil) {
            value = [expression keyPath];
        }
        NSEntityDescription *entity = [request entity];
        NSDictionary *properties = [entity propertiesByName];
        id property = [properties objectForKey:value];
        if ([property isKindOfClass:[NSRelationshipDescription class]]) {
            value = [self foreignKeyColumnForRelationship:property];
        }
        if (property == nil && [value rangeOfString:@"."].location != NSNotFound) {
            // We have a join table property, we need to rewrite the query.
            NSArray *pathComponents = [value componentsSeparatedByString:@"."];
            value = [NSString stringWithFormat:@"%@.%@",
                     [self joinedTableNameForComponents:pathComponents],
                     [pathComponents lastObject]];
            
        }
        *operand = value;
    }
    else if (type == NSEvaluatedObjectExpressionType) {
        *operand = @"id";
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
                             [value uppercaseString]];
            }
            else {
                *operand = @"?";
                *bindings = [NSString stringWithFormat:
                             [operator objectForKey:@"format"],
                             value];
            }
        }
        else {
            *bindings = value;
            *operand = @"?";
        }
    }

    // unsupported type
    else {
        NSLog(@"%s Unsupported expression type %ld", __PRETTY_FUNCTION__, (unsigned long)type);
    }
}

- (NSString *)foreignKeyColumnForRelationshipP:(NSRelationshipDescription *)relationship {
    NSEntityDescription *destination = [relationship destinationEntity];
    NSLog(@"%@",[destination name]);
    return [NSString stringWithFormat:@"%@.id", [destination name]];
}

- (NSString *)foreignKeyColumnForRelationship:(NSRelationshipDescription *)relationship {
    return [NSString stringWithFormat:@"%@_id", [relationship name]];
}

- (NSString *) joinedTableNameForComponents: (NSArray *) componentsArray {
    assert(componentsArray.count > 0);
    NSString *tableName = [[componentsArray subarrayWithRange:NSMakeRange(0, componentsArray.count - 1)] componentsJoinedByString:@"."];
    return [NSString stringWithFormat: @"[%@]", tableName];
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

- (void)updateWithValues:(NSDictionary *)values version:(uint64_t)version {
    [super updateWithValues:values version:version];
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

@end
