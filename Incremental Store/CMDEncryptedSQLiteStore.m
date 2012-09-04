//
//  CMDEncryptedSQLiteStore.m
//
//  Created by Caleb Davenport on 7/26/12.
//  Copyright (c) 2012 Caleb Davenport. All rights reserved.
//

#if !__has_feature(objc_arc)
#error This class requires ARC.
#endif

#import <sqlite3.h>

#import "CMDEncryptedSQLiteStore.h"

NSString * const CMDEncryptedSQLiteStoreType = @"CMDEncryptedSQLiteStore";
NSString * const CMDEncryptedSQLiteStorePassphraseKey = @"CMDEncryptedSQLiteStorePassphrase";
NSString * const CMDEncryptedSQLiteStoreErrorDomain = @"CMDEncryptedSQLiteStoreErrorDomain";
NSString * const CMDEncryptedSQLiteStoreErrorMessageKey = @"CMDEncryptedSQLiteStoreErrorMessage";

#pragma mark - category interfaces

@interface NSArray (CMDEncryptedSQLiteStoreAdditions)

/*
 
 
 
 */
+ (NSArray *)cmd_arrayWithObject:(id)object times:(NSUInteger)times;

/*
 
 
 
 
 */
- (NSArray *)cmd_collect:(id (^) (id object))block;

/*
 
 
 
 */
- (NSArray *)cmd_flatten;

@end

@interface CMDIncrementalStoreNode : NSIncrementalStoreNode

@end

@implementation CMDIncrementalStoreNode

- (void)updateWithValues:(NSDictionary *)values version:(uint64_t)version {
    [super updateWithValues:values version:version];
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

@end

@implementation CMDEncryptedSQLiteStore {
    
    // database resources
    sqlite3 *database;
    
    // cache money
    NSMutableDictionary *objectIDCache;
    NSMutableDictionary *nodeCache;
    NSMutableDictionary *objectCountCache;
    
}

+ (void)load {
    @autoreleasepool {
        [NSPersistentStoreCoordinator
         registerStoreClass:[CMDEncryptedSQLiteStore class]
         forStoreType:CMDEncryptedSQLiteStoreType];
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
    [array enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSEntityDescription *entity = [(NSManagedObject *)obj entity];
        NSString *table = [self tableNameForEntity:entity];
        NSNumber *value = [self maximumObjectIDInTable:table];
        if (value == nil) {
            if (error) { *error = [self databaseError]; }
            *stop = YES;
            objectIDs = nil;
            return;
        }
        NSManagedObjectID *objectID = [self newObjectIDForEntity:entity referenceObject:value];
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
        NSString *table = [self tableNameForEntity:entity];
        NSDictionary *condition = [self whereClauseWithFetchRequest:fetchRequest];
        NSString *order = [self orderClauseWithSortDescriptors:[fetchRequest sortDescriptors]];
        NSString *limit = ([fetchRequest fetchLimit] > 0 ? [NSString stringWithFormat:@" LIMIT %ld", (unsigned long)[fetchRequest fetchLimit]] : @"");
        
        // return objects or ids
        if (type == NSManagedObjectResultType || type == NSManagedObjectIDResultType) {
            NSString *string = [NSString stringWithFormat:
                                @"SELECT ID FROM %@%@%@%@;",
                                table,
                                [condition objectForKey:@"query"],
                                order,
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
            
            // many side of a one-to-many
            if (![obj isToMany] && [inverse isToMany]) {
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
    
    // many side of a one-to-many
    if ([relationship isToMany] && ![inverseRelationship isToMany]) {
        NSString *string = [NSString stringWithFormat:
                            @"SELECT ID FROM %@ WHERE %@=?",
                            [self tableNameForEntity:destinationEntity],
                            [self foreignKeyColumnForRelationship:inverseRelationship]];
        statement = [self preparedStatementForQuery:string];
        sqlite3_bind_int64(statement, 1, key);
    }
    
    // one side of a one-to-many
    else if (![relationship isToMany] && [inverseRelationship isToMany]) {
        NSString *string = [NSString stringWithFormat:
                            @"SELECT %@ FROM %@ WHERE ID=?",
                            [self foreignKeyColumnForRelationship:relationship],
                            [self tableNameForEntity:sourceEntity]];
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
    return CMDEncryptedSQLiteStoreType;
}

#pragma mark - initialize database

- (BOOL)loadMetadata:(NSError **)error {
    if (sqlite3_open([[[self URL] path] UTF8String], &database) == SQLITE_OK) {
        
        // passphrase
        if (![self configureDatabasePassphrase]) {
            *error = [self databaseError];
            sqlite3_close(database);
            database = NULL;
            return NO;
        }
        
        // load metadata
        BOOL success = [self performInTransaction:^{
            static NSString * const table = @"meta";
            NSString *string = nil;
            NSDictionary *metadata = nil;
            sqlite3_stmt *statement = NULL;
            int count = 0;
            
            // check for meta table
            string = [NSString stringWithFormat:
                      @"SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='%@';",
                      table];
            statement = [self preparedStatementForQuery:string];
            if (statement != NULL && sqlite3_step(statement) == SQLITE_ROW) {
                count = sqlite3_column_int(statement, 0);
            }
            else {
                sqlite3_finalize(statement);
                *error = [self databaseError];
                return NO;
            }
            sqlite3_finalize(statement);
            
            // this is a new store
            if (count == 0) {
                
                // create table
                string = [NSString stringWithFormat:@"CREATE TABLE %@(plist);", table];
                statement = [self preparedStatementForQuery:string];
                sqlite3_step(statement);
                if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK) {
                    *error = [self databaseError];
                    return NO;
                }
                
                // run migrations
                NSManagedObjectModel *model = [[self persistentStoreCoordinator] managedObjectModel];
                if (![self initializeDatabaseWithModel:model]) {
                    *error = [self databaseError];
                    return NO;
                }
                
                // create and set metadata
                metadata = @{
                    NSStoreUUIDKey : [[self class] identifierForNewStoreAtURL:[self URL]],
                    NSStoreTypeKey : [self type]
                };
                [self setMetadata:metadata];
                if (![self saveMetadata]) {
                    *error = [self databaseError];
                    return NO;
                }
                
            }
            
            // load existing metadata
            else {
                
                // load
                string = [NSString stringWithFormat:
                          @"SELECT plist FROM %@ LIMIT 1;",
                          table];
                sqlite3_stmt *statement = [self preparedStatementForQuery:string];
                if (statement != NULL && sqlite3_step(statement) == SQLITE_ROW) {
                    const void *bytes = sqlite3_column_blob(statement, 0);
                    unsigned int length = sqlite3_column_bytes(statement, 0);
                    NSData *data = [NSData dataWithBytes:bytes length:length];
                    metadata = [NSKeyedUnarchiver unarchiveObjectWithData:data];
                    [self setMetadata:metadata];
                }
                else {
                    sqlite3_finalize(statement);
                    *error = [self databaseError];
                    return NO;
                }
                sqlite3_finalize(statement);
                
                // run migrations
                NSMutableArray *bundles = [NSMutableArray array];
                [bundles addObjectsFromArray:[NSBundle allBundles]];
                [bundles addObjectsFromArray:[NSBundle allFrameworks]];
                NSManagedObjectModel *oldModel = [NSManagedObjectModel
                                                  mergedModelFromBundles:bundles
                                                  forStoreMetadata:metadata];
                NSManagedObjectModel *newModel = [[self persistentStoreCoordinator] managedObjectModel];
                if (![oldModel isEqual:newModel]) {
                    
                    // generate mapping model
                    NSMappingModel *mappingModel = [NSMappingModel
                                                    inferredMappingModelForSourceModel:oldModel
                                                    destinationModel:newModel
                                                    error:error];
                    if (mappingModel == nil) {
                        return NO;
                    }
                    
                    // run migrations
                    if (![self migrateToModel:newModel withMappingModel:mappingModel]) {
                        *error = [self databaseError];
                        return NO;
                    }
                    
                    // update metadata
                    NSMutableDictionary *mutableMetadata = [metadata mutableCopy];
                    [mutableMetadata setObject:[newModel entityVersionHashesByName] forKey:NSStoreModelVersionHashesKey];
                    [self setMetadata:mutableMetadata];
                    if (![self saveMetadata]) {
                        *error = [self databaseError];
                        return NO;
                    }
                    
                }
                
            }
            
            // worked
            return YES;
            
        }];
        
        // finish up
        if (!success) {
            sqlite3_close(database);
            database = NULL;
            return NO;
        }
        
        // return
        return YES;
        
    }
    
    // return
    *error = [self databaseError];
    database = NULL;
    return NO;
    
}

- (BOOL)saveMetadata {
    NSString *string;
    sqlite3_stmt *statement;
    
    // delete
    string = @"DELETE FROM meta;";
    statement = [self preparedStatementForQuery:string];
    sqlite3_step(statement);
    if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK) { return NO; }
    
    // save
    string = @"INSERT INTO meta (plist) VALUES(?);";
    statement = [self preparedStatementForQuery:string];
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:[self metadata]];
    sqlite3_bind_blob(statement, 1, [data bytes], [data length], SQLITE_TRANSIENT);
    sqlite3_step(statement);
    if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK) { return NO; }
    
    return YES;
}

- (BOOL)configureDatabasePassphrase {
    NSString *passphrase = [[self options] objectForKey:CMDEncryptedSQLiteStorePassphraseKey];
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

- (BOOL)migrateToModel:(NSManagedObjectModel *)toModel withMappingModel:(NSMappingModel *)mappingModel {
    BOOL __block succuess = YES;
    
    // grab final entity snapshot
    NSDictionary *entities = [toModel entitiesByName];
    
    // enumerate over entities
    [[mappingModel entityMappings] enumerateObjectsUsingBlock:^(NSEntityMapping *entityMapping, NSUInteger idx, BOOL *stop) {
        NSString *entityName = [entityMapping destinationEntityName];
        NSEntityDescription *entityDescription = [entities objectForKey:entityName];
        NSEntityMappingType type = [entityMapping mappingType];
        
        
        // add a new entity from final snapshot
        if (type == NSAddEntityMappingType) {
            succuess = [self createTableForEntity:entityDescription];
        }
        
        // drop table for deleted entity
        else if (type == NSRemoveEntityMappingType) {
            succuess = [self dropTableForEntity:entityDescription];
        }
        
        else if (type == NSTransformEntityMappingType) {
            succuess = [self alterTableForEntity:entityDescription withMapping:entityMapping];
        }
        
        if (!succuess) { *stop = YES; }
    }];
    
    return succuess;
}

- (BOOL)initializeDatabaseWithModel:(NSManagedObjectModel *)model {
    BOOL __block success = YES;
    [[model entities] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if (![self createTableForEntity:obj]) {
            success = NO;
            *stop = YES;
        }
    }];
    return success;
}

- (BOOL)createTableForEntity:(NSEntityDescription *)entity {
    
    // prepare columns
    NSMutableArray *columns = [NSMutableArray arrayWithObject:@"id integer primary key"];
    NSArray *attributeNames = [[entity attributesByName] allKeys];
    [columns addObjectsFromArray:attributeNames];
    [[entity relationshipsByName] enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSRelationshipDescription *inverse = [obj inverseRelationship];
        
        // many side of a one-to-many
        if (![obj isToMany] && [inverse isToMany]) {
            NSString *column = [self foreignKeyColumnForRelationship:obj];
            [columns addObject:column];
        }
        
    }];
    
    // create table
    NSString *string = [NSString stringWithFormat:
                        @"CREATE TABLE %@(%@);",
                        [self tableNameForEntity:entity],
                        [columns componentsJoinedByString:@", "]];
    sqlite3_stmt *statement = [self preparedStatementForQuery:string];
    sqlite3_step(statement);
    return (statement != NULL && sqlite3_finalize(statement) == SQLITE_OK);
    
}

- (BOOL)dropTableForEntity:(NSEntityDescription *)entity {
    NSString *string = [NSString stringWithFormat:
                        @"DROP TABLE %@;",
                        [self tableNameForEntity:entity]];
    sqlite3_stmt *statement = [self preparedStatementForQuery:string];
    sqlite3_step(statement);
    return (statement != NULL && sqlite3_finalize(statement) == SQLITE_OK);
}

- (BOOL)alterTableForEntity:(NSEntityDescription *)entity withMapping:(NSEntityMapping *)mapping {
    [[mapping attributeMappings] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
//        NSExpression *expression = [obj valueExpression];
//        if (expression == nil) {
//            // create column
//        }
//        else {
//            NSExpression *source = [expression operand];
//            NSString *function = [expression function];
//            [source perform]
//        }
//        NSLog(@"%@", obj);
//        NSLog(@"%@", expression);
    }];
    return YES;
}

#pragma mark - save changes to the database

- (NSArray *)handleSaveChangesRequest:(NSSaveChangesRequest *)request error:(NSError **)error {
    NSMutableDictionary *localNodeCache = [nodeCache mutableCopy];
    BOOL success = [self performInTransaction:^{
        BOOL insert = [self handleInsertedObjectsInSaveReuqest:request error:error];
        BOOL update = [self handleUpdatedObjectsInSaveReuqest:request cache:localNodeCache error:error];
        BOOL delete = [self handleDeletedObjectsInSaveReuqest:request error:error];
        return (BOOL)(insert && update && delete);
    }];
    if (success) {
        nodeCache = localNodeCache;
        return [NSArray array];
    }
    if (error) { *error = [self databaseError]; }
    return nil;
}

- (BOOL)handleInsertedObjectsInSaveReuqest:(NSSaveChangesRequest *)request error:(NSError **)error {
    BOOL __block success = YES;
    [[request insertedObjects] enumerateObjectsUsingBlock:^(NSManagedObject *object, BOOL *stop) {
        
        // get values
        NSEntityDescription *entity = [object entity];
        NSMutableArray *keys = [NSMutableArray array];
        NSMutableArray *columns = [NSMutableArray arrayWithObject:@"id"];
        NSDictionary *properties = [entity propertiesByName];
        [properties enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            if ([obj isKindOfClass:[NSAttributeDescription class]]) {
                [keys addObject:key];
                [columns addObject:key];
            }
            else if ([obj isKindOfClass:[NSPropertyDescription class]]) {
                NSRelationshipDescription *inverse = [obj inverseRelationship];
                
                // many side of a many-to-one
                if (![obj isToMany] && [inverse isToMany]) {
                    [keys addObject:key];
                    NSString *column = [self foreignKeyColumnForRelationship:obj];
                    [columns addObject:column];
                }
                
            }
        }];
        
        // prepare statement
        NSString *string = [NSString stringWithFormat:
                            @"INSERT INTO %@ (%@) VALUES(%@);",
                            [self tableNameForEntity:entity],
                            [columns componentsJoinedByString:@", "],
                            [[NSArray cmd_arrayWithObject:@"?" times:[columns count]] componentsJoinedByString:@", "]];
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

- (BOOL)handleUpdatedObjectsInSaveReuqest:(NSSaveChangesRequest *)request cache:(NSMutableDictionary *)cache error:(NSError **)error {
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
                NSRelationshipDescription *inverse = [property inverseRelationship];
                
                // many side of a many-to-one
                if (![property isToMany] && [inverse isToMany]) {
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

- (BOOL)handleDeletedObjectsInSaveReuqest:(NSSaveChangesRequest *)request error:(NSError **)error {
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

- (NSError *)databaseError {
    NSDictionary *userInfo = @{
        CMDEncryptedSQLiteStoreErrorMessageKey : [NSString stringWithUTF8String:sqlite3_errmsg(database)]
    };
    return [NSError
            errorWithDomain:NSSQLiteErrorDomain
            code:sqlite3_errcode(database)
            userInfo:userInfo];
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

- (NSString *)orderClauseWithSortDescriptors:(NSArray *)descriptors {
    NSMutableArray *columns = [NSMutableArray arrayWithCapacity:[descriptors count]];
    [descriptors enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [columns addObject:[NSString stringWithFormat:
                            @"%@ %@",
                            [obj key],
                            ([obj ascending]) ? @"ASC" : @"DESC"]];
    }];
    if ([columns count]) {
        return [NSString stringWithFormat:@" ORDER BY %@", [columns componentsJoinedByString:@", "]];
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
                sqlite3_bind_int(statement, index, [value boolValue] ? 0 : 1);
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
    NSDictionary *result = [self recursive_whereClauseWithFetchRequest:request predicate:[request predicate]];
    if (result) {
        NSString *query = [result objectForKey:@"query"];
        query = [NSString stringWithFormat:@" WHERE %@", query];
        result = [result mutableCopy];
        [(NSMutableDictionary *)result setObject:query forKey:@"query"];
        return result;
    }
    else {
        return @{ @"query" : @"" };
    }
}

- (NSDictionary *)recursive_whereClauseWithFetchRequest:(NSFetchRequest *)request predicate:(NSPredicate *)predicate {
    
//    enum {
//        NSMatchesPredicateOperatorType,
//        NSCustomSelectorPredicateOperatorType,
//        NSBetweenPredicateOperatorType
//    };
//    typedef NSUInteger NSPredicateOperatorType;
    
    static NSDictionary *operators = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        operators = @{
            @(NSEqualToPredicateOperatorType)       : @{ @"operator" : @"=",        @"format" : @"%@" },
            @(NSNotEqualToPredicateOperatorType)    : @{ @"operator" : @"!=",       @"format" : @"%@" },
            @(NSContainsPredicateOperatorType)      : @{ @"operator" : @"LIKE",     @"format" : @"%%%@%%" },
            @(NSBeginsWithPredicateOperatorType)    : @{ @"operator" : @"LIKE",     @"format" : @"%@%%" },
            @(NSEndsWithPredicateOperatorType)      : @{ @"operator" : @"LIKE",     @"format" : @"%%%@" },
            @(NSLikePredicateOperatorType)          : @{ @"operator" : @"LIKE",     @"format" : @"%@" },
            @(NSInPredicateOperatorType)            : @{ @"operator" : @"IN",       @"format" : @"(%@)" },
            @(NSLessThanPredicateOperatorType)      : @{ @"operator" : @"<", @"format" : @"%@" },
            @(NSLessThanOrEqualToPredicateOperatorType) : @{ @"operator" : @"<=", @"format" : @"%@" },
            @(NSGreaterThanPredicateOperatorType) : @{ @"operator" : @">", @"format" : @"%@" },
            @(NSGreaterThanOrEqualToPredicateOperatorType) : @{ @"operator" : @">=", @"format" : @"%@" }
        };
    });
    
    if ([predicate isKindOfClass:[NSCompoundPredicate class]]) {
        
        // get subpredicates
        NSCompoundPredicateType type = [(id)predicate compoundPredicateType];
        NSMutableArray *queries = [NSMutableArray array];
        NSMutableArray *bindings = [NSMutableArray array];
        [[(id)predicate subpredicates] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSDictionary *result = [self recursive_whereClauseWithFetchRequest:request predicate:obj];
            [queries addObject:[result objectForKey:@"query"]];
            [bindings addObjectsFromArray:[result objectForKey:@"bindings"]];
        }];
        
        // build query
        NSString *query = nil;
        if (type == NSAndPredicateType) {
            query = [NSString stringWithFormat:
                     @"(%@)",
                     [queries componentsJoinedByString:@" AND "]];
        }
        else if (type == NSOrPredicateType) {
            query = [NSString stringWithFormat:
                     @"(%@)",
                     [queries componentsJoinedByString:@" OR "]];
        }
        
        // build result and return
        return @{
            @"query" : query,
            @"bindings" : bindings
        };
        
    }
    
    else if ([predicate isKindOfClass:[NSComparisonPredicate class]]) {
        NSNumber *type = @([(id)predicate predicateOperatorType]);
        NSDictionary *operator = [operators objectForKey:type];
        
        // left expression
        id leftOperand = nil;
        id leftBindings = nil;
        [self
         parseExpression:[(id)predicate leftExpression]
         inPredicate:(id)predicate
         inFetchRequest:request
         operator:operator
         operand:&leftOperand
         bindings:&leftBindings];
        
        // right expression
        id rightOperand = nil;
        id rightBindings = nil;
        [self
         parseExpression:[(id)predicate rightExpression]
         inPredicate:(id)predicate
         inFetchRequest:request
         operator:operator
         operand:&rightOperand
         bindings:&rightBindings];
        
        // build result and return
        NSMutableArray *bindings = [NSMutableArray arrayWithCapacity:2];
        if (leftBindings) { [bindings addObject:leftBindings]; }
        if (rightBindings) { [bindings addObject:rightBindings]; }
        NSString *query = [NSString stringWithFormat:
                           @"%@ %@ %@",
                           leftOperand,
                           [operator objectForKey:@"operator"],
                           rightOperand];
        return @{
            @"query" : query,
            @"bindings" : [bindings cmd_flatten]
        };
        
    }
    
    // no result
    return nil;
    
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
    
    // reference a column in the query
    if (type == NSKeyPathExpressionType) {
        id value = [expression keyPath];
        NSEntityDescription *entity = [request entity];
        NSDictionary *properties = [entity propertiesByName];
        id property = [properties objectForKey:value];
        if ([property isKindOfClass:[NSRelationshipDescription class]]) {
            value = [self foreignKeyColumnForRelationship:property];
        }
        *operand = value;
    }
    else if (type == NSEvaluatedObjectExpressionType) {
        *operand = @"id";
    }
    
    // a value to be bound to the query
    else if (type == NSConstantValueExpressionType) {
        id value = [expression constantValue];
        if ([value isKindOfClass:[NSSet class]]) {
            NSUInteger count = [value count];
            NSArray *parameters = [NSArray cmd_arrayWithObject:@"?" times:count];
            *bindings = [value allObjects];
            *operand = [NSString stringWithFormat:
                        [operator objectForKey:@"format"],
                        [parameters componentsJoinedByString:@", "]];
        }
        else if ([value isKindOfClass:[NSArray class]]) {
            NSUInteger count = [value count];
            NSArray *parameters = [NSArray cmd_arrayWithObject:@"?" times:count];
            *bindings = value;
            *operand = [NSString stringWithFormat:
                        [operator objectForKey:@"format"],
                        [parameters componentsJoinedByString:@", "]];
        }
        if ([value isKindOfClass:[NSString class]]) {
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

- (NSString *)foreignKeyColumnForRelationship:(NSRelationshipDescription *)relationship {
    NSEntityDescription *destination = [relationship destinationEntity];
    return [NSString stringWithFormat:@"%@_id", [destination name]];
}

@end

#pragma mark - category implementations

@implementation NSArray (CMDEncryptedSQLiteStoreAdditions)

+ (NSArray *)cmd_arrayWithObject:(id)object times:(NSUInteger)times {
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:times];
    for (NSUInteger i = 0; i < times; i++) {
        [array addObject:object];
    }
    return [array copy];
}

- (NSArray *)cmd_collect:(id (^) (id object))block {
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:[self count]];
    [self enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [array addObject:block(obj)];
    }];
    return array;
}

- (NSArray *)cmd_flatten {
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:[self count]];
    [self enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([obj isKindOfClass:[NSArray class]]) {
            [array addObjectsFromArray:[obj cmd_flatten]];
        }
        else {
            [array addObject:obj];
        }
    }];
    return array;
}

@end
