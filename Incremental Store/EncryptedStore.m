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
#import <limits.h>

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

@interface NSEntityDescription (CMDTypeHash)

@property (nonatomic, readonly) long typeHash;

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
    NSError * error;
    return [self makeStoreWithOptions:options managedObjectModel:objModel error:&error];
}
+ (NSPersistentStoreCoordinator *)makeStoreWithStructOptions:(EncryptedStoreOptions *) options managedObjectModel:(NSManagedObjectModel *)objModel
{
    NSError * error;
    return [self makeStoreWithStructOptions:options managedObjectModel:objModel error:&error];
}
+ (NSPersistentStoreCoordinator *)makeStore:(NSManagedObjectModel *)objModel passcode:(NSString *)passcode
{
    NSError * error;
    return [self makeStore:objModel passcode:passcode error:&error];
}

+ (NSPersistentStoreCoordinator *)makeStoreWithOptions:(NSDictionary *)options managedObjectModel:(NSManagedObjectModel *)objModel error:(NSError *__autoreleasing *)error
{
    NSPersistentStoreCoordinator * persistentCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:objModel];
    
    //  NSString* appSupportDir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    
    BOOL backup = YES;
    NSURL *databaseURL;
    id dburl = [options objectForKey:EncryptedStoreDatabaseLocation];
    if(dburl != nil) {
        if ([dburl isKindOfClass:[NSString class]]){
            databaseURL = [NSURL URLWithString:[options objectForKey:EncryptedStoreDatabaseLocation]];
            backup = NO;
        }
        else if ([dburl isKindOfClass:[NSURL class]]){
            databaseURL = dburl;
            backup = NO;
        }
    }
    
    if (backup){
        NSString *dbNameKey = (__bridge NSString *)kCFBundleNameKey;
        NSString *dbName = NSBundle.mainBundle.infoDictionary[dbNameKey];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSURL *applicationSupportURL = [[fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
        [fileManager createDirectoryAtURL:applicationSupportURL withIntermediateDirectories:NO attributes:nil error:nil];
        databaseURL = [applicationSupportURL URLByAppendingPathComponent:[dbName stringByAppendingString:@".sqlite"]];

    }
    
    [persistentCoordinator addPersistentStoreWithType:EncryptedStoreType configuration:nil URL:databaseURL
        options:options error:error];

    if (*error)
    {
        NSLog(@"Unable to add persistent store.");
        NSLog(@"Error: %@\n%@\n%@", *error, [*error userInfo], [*error localizedDescription]);
    }
    
    return persistentCoordinator;
}

+ (NSPersistentStoreCoordinator *)makeStoreWithStructOptions:(EncryptedStoreOptions *) options managedObjectModel:(NSManagedObjectModel *)objModel error:(NSError *__autoreleasing *)error {
    
    NSMutableDictionary *newOptions = [NSMutableDictionary dictionary];
    if (options->passphrase) {
        [newOptions setValue:[NSString stringWithUTF8String:options->passphrase] forKey:EncryptedStorePassphraseKey];
    }
    
    if (options->database_location)
        [newOptions setValue:[NSString stringWithUTF8String:options->database_location] forKey:EncryptedStoreDatabaseLocation];
    
    if (options->cache_size)
        [newOptions setValue:[NSNumber numberWithInt:*(options->cache_size)] forKey:EncryptedStoreCacheSize];
    
    return [self makeStoreWithOptions:newOptions managedObjectModel:objModel error:error];
}

+ (NSPersistentStoreCoordinator *)makeStore:(NSManagedObjectModel *)objModel passcode:(NSString *)passcode error:(NSError *__autoreleasing *)error
{
    NSDictionary *options = passcode ? @{ EncryptedStorePassphraseKey : passcode } : nil;
    
    return [self makeStoreWithOptions:options managedObjectModel:objModel error:error];
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
        for (NSEntityDescription * entity in [[root managedObjectModel] entitiesForConfiguration:name]) {
            // TODO: should check for [entity isAbstract] and not add it to the cache
            if ([self entityNeedsEntityTypeColumn:entity]) {
                [entityTypeCache setObject:entity forKey:@(entity.typeHash)];
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

-(NSArray *)storeEntities
{
    return [[self.persistentStoreCoordinator managedObjectModel] entitiesForConfiguration:[self configurationName]];
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
        NSString * joinStatement = [self getJoinClause:fetchRequest withPredicate:[fetchRequest predicate] initial:YES];
        
        NSString *table = [self tableNameForEntity:entity];
        NSDictionary *condition = [self whereClauseWithFetchRequest:fetchRequest];
        NSDictionary *ordering = [self orderClause:fetchRequest forEntity:entity];
        NSString *limit = ([fetchRequest fetchLimit] > 0 ? [NSString stringWithFormat:@" LIMIT %lu", (unsigned long)[fetchRequest fetchLimit]] : @"");
        if ([fetchRequest fetchOffset] > 0) {
            NSString * offset = [NSString stringWithFormat:@" OFFSET %lu", (unsigned long)[fetchRequest fetchOffset]];
            if ([limit isEqualToString:@""])
                limit = offset;
            else
                limit = [limit stringByAppendingString:offset];
        }
        BOOL isDistinctFetchEnabled = [fetchRequest returnsDistinctResults];
        
        // NOTE: this would probably clash with DISTINCT
        // Disable the combination for now until we can figure out a way to handle both and
        // have a proper test case
        BOOL shouldFetchEntityType = [self entityNeedsEntityTypeColumn:entity] && !isDistinctFetchEnabled;
        // return objects or ids
        if (type == NSManagedObjectResultType || type == NSManagedObjectIDResultType) {
            NSString *string = [NSString stringWithFormat:
                                @"SELECT %@%@.__objectID%@ FROM %@ %@%@%@%@;",
                                (isDistinctFetchEnabled)?@"DISTINCT ":@"",
                                table,
                                (shouldFetchEntityType)?[NSString stringWithFormat:@", %@.__entityType", table]:@"",
                                table,
                                joinStatement,
                                [condition objectForKey:@"query"],
                                [ordering objectForKey:@"order"],
                                limit];
            NSRange endHavingRange = [string rangeOfString:@"END_HAVING"];
            if(endHavingRange.location != NSNotFound) { // String manipulation to handle SUM
                // Between HAVING and END_HAVING
                NSRange havingRange = [string rangeOfString:@"HAVING"];
                NSUInteger length = endHavingRange.location - havingRange.location;
                NSUInteger location = havingRange.location;
                NSRange substrRange = NSMakeRange(location,length);
                
                NSInteger endHavingEnd = endHavingRange.location + endHavingRange.length;
                NSString *groupHaving = [NSString stringWithFormat: @" GROUP BY %@.__objectID %@ %@", table, [string substringWithRange:substrRange], [string substringWithRange:NSMakeRange(endHavingEnd, [string length] - endHavingEnd)]];
                
                // Rebuild entire SQL string
                string = [NSString stringWithFormat:
                          @"SELECT %@%@.__objectID%@ FROM %@ %@%@%@%@;",
                          (isDistinctFetchEnabled)?@"DISTINCT ":@"",
                          table,
                          (shouldFetchEntityType)?[NSString stringWithFormat:@", %@.__entityType", table]:@"",
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
                NSEntityDescription * entityToFetch = nil;
                if (shouldFetchEntityType) {
                    long long entityType = sqlite3_column_int64(statement, 1);
                    entityToFetch = [entityTypeCache objectForKey:@(entityType)];
                }
                if (!entityToFetch) {
                    entityToFetch = entity;
                }
                NSManagedObjectID *objectID = [self newObjectIDForEntity:entityToFetch referenceObject:@(primaryKey)];
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
            // NOTE - this now supports joins but in a limited fashion. It will successfully
            // retrieve properties that are to-one relationships
            
            NSString *string = [NSString stringWithFormat:
                                @"SELECT %@%@ FROM %@ %@%@%@%@;",
                                (isDistinctFetchEnabled)?@"DISTINCT ":@"",
                                propertiesToFetchString,
                                table,
                                joinStatement,
                                [condition objectForKey:@"query"],
                                [ordering objectForKey:@"order"],
                                limit];
            sqlite3_stmt *statement = [self preparedStatementForQuery:string];
            [self bindWhereClause:condition toStatement:statement];
            while (sqlite3_step(statement) == SQLITE_ROW) {
                NSMutableDictionary* singleResult = [NSMutableDictionary dictionary];
                [propertiesToFetch enumerateObjectsUsingBlock:^(id property, NSUInteger idx, BOOL *stop) {
                    id value = [self valueForProperty:property inStatement:statement atIndex:(int)idx];
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
    NSMutableArray *typeJoins = [NSMutableArray array];
    NSMutableSet *entityTypes = [NSMutableSet set];
    unsigned long long primaryKey = [[self referenceObjectForObjectID:objectID] unsignedLongLongValue];
    
    NSString *table = [self tableNameForEntity:entity];
    
    // enumerate properties
    NSDictionary *properties = [entity propertiesByName];
    [properties enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSPropertyDescription *obj, BOOL *stop) {
        if ([obj isKindOfClass:[NSAttributeDescription class]]) {
            [columns addObject:[NSString stringWithFormat:@"%@.%@", table, key]];
            [keys addObject:key];
        }
        else if ([obj isKindOfClass:[NSRelationshipDescription class]]) {
            NSRelationshipDescription *relationship = (NSRelationshipDescription *) obj;
            NSEntityDescription *destinationEntity = relationship.destinationEntity;
            
            
            // Handle many-to-one and one-to-one
            if (![relationship isToMany]) {
                NSString *column = [self foreignKeyColumnForRelationship:relationship];
                [columns addObject:[NSString stringWithFormat:@"%@.%@", table, column]];
                [keys addObject:key];
                
                // We need to fetch the direct entity not its super type
                if ([self entityNeedsEntityTypeColumn:destinationEntity]) {
                    // Get the destination table for the type look up
                    NSString *destinationTable = [self tableNameForEntity:destinationEntity];
                    
                    // Add teh type column to the query
                    NSString *typeColumn = [NSString stringWithFormat:@"%@.__entityType", destinationTable];
                    [columns addObject:typeColumn];
                    
                    // Create the join
                    NSString *join = [NSString stringWithFormat:@" INNER JOIN %@ ON %@.__objectid=%@.%@", destinationTable, destinationTable, table, column];
                    [typeJoins addObject:join];
                    
                    // Mark that this relation needs a type lookup
                    [entityTypes addObject:key];
                }
            }
            
        }
    }];
    
    // prepare query
    NSString *string = [NSString stringWithFormat:
                        @"SELECT %@ FROM %@%@ WHERE %@.__objectid=?;",
                        [columns componentsJoinedByString:@", "],
                        table, [typeJoins componentsJoinedByString:@""], table];
    sqlite3_stmt *statement = [self preparedStatementForQuery:string];
    
    // run query
    sqlite3_bind_int64(statement, 1, primaryKey);
    if (sqlite3_step(statement) == SQLITE_ROW) {
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
        NSMutableArray * allProperties = [NSMutableArray new];
        
        __block int offset = 0;
        
        [keys enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            NSPropertyDescription *property = [properties objectForKey:obj];
            id value = [self valueForProperty:property inStatement:statement atIndex:(int)idx + offset];
            
            if ([entityTypes containsObject:obj]) {
                // This key needs an entity type - the next column will be it, so shift all values from now on
                offset++;
            }
            
            if (value) {
                [dictionary setObject:value forKey:obj];
            }
            [allProperties addObject:property];
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
    
    // We need to fetch the direct entity not its super type
    BOOL shouldFetchDestinationEntityType = [self entityNeedsEntityTypeColumn:destinationEntity];
    
    if (![relationship isToMany]) {
        // to-one relationship, foreign key exists in source entity table
        
        NSString *string = [NSString stringWithFormat:
                            @"SELECT %@%@ FROM %@ WHERE __objectID=?",
                            [self foreignKeyColumnForRelationship:relationship],
                            shouldFetchDestinationEntityType ? @", __entityType" : @"",
                            [self tableNameForEntity:sourceEntity]];
        statement = [self preparedStatementForQuery:string];
        sqlite3_bind_int64(statement, 1, key);
        
    } else if ([relationship isToMany] && [inverseRelationship isToMany]) {
        // many-to-many relationship, foreign key exists in relation table, join to get the type
        
        
        NSString *firstIDColumn, *secondIDColumn, *firstOrderColumn, *secondOrderColumn;
        BOOL firstColumnIsSource = [self relationships:relationship firstIDColumn:&firstIDColumn secondIDColumn:&secondIDColumn firstOrderColumn:&firstOrderColumn secondOrderColumn:&secondOrderColumn];
        
        NSString *relationTable = [self tableNameForRelationship:relationship];
        NSString *sourceIDColumn = firstColumnIsSource ? firstIDColumn : secondIDColumn;
        NSString *destinationIDColumn = firstColumnIsSource ? secondIDColumn : firstIDColumn;
        
        NSString *join = @"";
        NSString *destinationTypeColumn = @"";
        if (shouldFetchDestinationEntityType) {
            NSString *destinationTable = [self tableNameForEntity:destinationEntity];
            destinationTypeColumn = [NSString stringWithFormat:@", %@.__entityType", destinationTable];
            join = [NSString stringWithFormat:@" INNER JOIN %@ ON %@.__objectid=%@.%@", destinationTable, destinationTable, relationTable, destinationIDColumn];
            
            // Add tables so we don't get ambigious column errors
            sourceIDColumn = [relationTable stringByAppendingFormat:@".%@", sourceIDColumn];
            destinationIDColumn = [relationTable stringByAppendingFormat:@".%@", destinationIDColumn];
        }
        
        NSString *orderColumn = firstColumnIsSource ? secondOrderColumn : firstOrderColumn;
        NSString *string = [NSString stringWithFormat:@"SELECT %@%@ FROM %@%@ WHERE %@=? ORDER BY %@ ASC", destinationIDColumn, destinationTypeColumn, relationTable, join, sourceIDColumn, orderColumn];
        
        statement = [self preparedStatementForQuery:string];
        sqlite3_bind_int64(statement, 1, key);
        
    } else {
        // one-to-many relationship, foreign key exists in desination entity table
        NSString *destinationTable = [self tableNameForEntity:destinationEntity];
        
        NSString *string = [NSString stringWithFormat:
                            @"SELECT __objectID%@ FROM %@ WHERE %@=? ORDER BY %@ ASC",
                            shouldFetchDestinationEntityType ? @", __entityType" : @"",
                            destinationTable,
                            [self foreignKeyColumnForRelationship:inverseRelationship],
                            [NSString stringWithFormat:@"%@_order", inverseRelationship.name]];
        statement = [self preparedStatementForQuery:string];
        sqlite3_bind_int64(statement, 1, key);
    }
    
    // run query
    NSMutableArray *objectIDs = [NSMutableArray array];
    while (sqlite3_step(statement) == SQLITE_ROW) {
        if (sqlite3_column_type(statement, 0) != SQLITE_NULL) {
            NSNumber *value = @(sqlite3_column_int64(statement, 0));
           
            // If we need to get the type of the entity to make sure the eventual entity that gets created is of the correct subentity type
            NSEntityDescription *resolvedDestinationEntity = nil;
            if (shouldFetchDestinationEntityType) {
                long long entityType = sqlite3_column_int64(statement, 1);
                resolvedDestinationEntity = [entityTypeCache objectForKey:@(entityType)];
            }
            if (!resolvedDestinationEntity) {
                resolvedDestinationEntity = destinationEntity;
            }
            
            NSManagedObjectID *objectID = [self newObjectIDForEntity:resolvedDestinationEntity referenceObject:value];
            [objectIDs addObject:objectID];
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
        if (![self configureDatabasePassphrase:error]) {
            sqlite3_close(database);
            database = NULL;
            return NO;
        }
        if (![self configureDatabaseCacheSize]) {
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
                    [bundles addObject:[NSBundle mainBundle]];
                    NSManagedObjectModel *oldModel = [NSManagedObjectModel
                                                      mergedModelFromBundles:bundles
                                                      forStoreMetadata:metadata];
                    NSManagedObjectModel *newModel = [[self persistentStoreCoordinator] managedObjectModel];
                    if (oldModel && newModel) {
                        
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
                        
                    } else {
                        NSLog(@"Failed to create NSManagedObject models for migration.");
                        if (error) {
                            NSDictionary * userInfo = @{EncryptedStoreErrorMessageKey : @"Missing old model, cannot migrate database"};
                            *error = [NSError errorWithDomain:EncryptedStoreErrorDomain code:EncryptedStoreErrorMigrationFailed userInfo:userInfo];
                        }
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
                
                // Create the tables for all entities
                if (![self initializeDatabase:error]) {
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
    if (error && *error == nil) { *error = [self databaseError]; }
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
    sqlite3_bind_blob(statement, 1, [data bytes], (int)[data length], SQLITE_TRANSIENT);
    sqlite3_step(statement);
    if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK) { return NO; }
    
    return YES;
}

#pragma mark - passphrase

- (BOOL)configureDatabasePassphrase:(NSError *__autoreleasing*)error {
    NSString *passphrase = [[self options] objectForKey:EncryptedStorePassphraseKey];
    
    int status;
    if ([passphrase length] > 0) {
        // Password provided, use it to key the DB
        const char *string = [passphrase UTF8String];
        status = sqlite3_key(database, string, (int)strlen(string));
        string = NULL;
        passphrase = nil;
    } else {
        // No password
        status = SQLITE_OK;
    }
    
    if (status == SQLITE_OK) {
        // Check if the password is correct as per http://sqlcipher.net/sqlcipher-api/#key section "Testing the Key"
        status = sqlite3_exec(database, (const char*) "SELECT count(*) FROM sqlite_master;", NULL, NULL, NULL);
        if (status == SQLITE_OK) {
            // Correct passcode
        } else {
            // Incorrect passcode
            if (error) {
                NSMutableDictionary *userInfo = [@{NSLocalizedDescriptionKey : @"Incorrect passcode"} mutableCopy];
                // If we have a DB error keep it for extra info
                NSError *underlyingError = [self databaseError];
                if (underlyingError) {
                    userInfo[NSUnderlyingErrorKey] = underlyingError;
                }
                *error = [NSError errorWithDomain:EncryptedStoreErrorDomain code:EncryptedStoreErrorIncorrectPasscode userInfo:userInfo];
            }
        }
    }
    return (status == SQLITE_OK);
}

-(BOOL)configureDatabaseCacheSize
{
    NSNumber *cacheSize = [[self options] objectForKey:EncryptedStoreCacheSize];
    if (cacheSize != nil) {
        NSString *string = [NSString stringWithFormat:@"PRAGMA cache_size = %d;", [cacheSize intValue]];
        sqlite3_stmt *statement = [self preparedStatementForQuery:string];
        sqlite3_step(statement);
        
        if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK) {
            // TO-DO: handle error with statement
            NSLog(@"Error: statement is NULL or could not be finalized");
            return NO;
        } else {
            // prepare another pragma cache_size statement and compare actual cache size
            NSString *string = @"PRAGMA cache_size;";
            sqlite3_stmt *checkStatement = [self preparedStatementForQuery:string];
            sqlite3_step(checkStatement);
            if (checkStatement == NULL || sqlite3_finalize(checkStatement) != SQLITE_OK) {
                // TO-DO: handle error with statement
                NSLog(@"Error: checkStatement is NULL or could not be finalized");
                return NO;
            }
            
            int actualCacheSize = sqlite3_column_int(checkStatement,0);
            if (actualCacheSize == [cacheSize intValue]) {
                // succeeded
                NSLog(@"Cache size successfully set to %d", actualCacheSize);
            } else {
                // failed...
                NSLog(@"Error: cache size set to %d, not %d", actualCacheSize, [cacheSize intValue]);
                return NO;
            }
        }
    }
    return YES;
}

#pragma mark - user functions

static void dbsqliteRegExp(sqlite3_context *context, int argc, const char **argv) {
    NSUInteger numberOfMatches = 0;
    NSString *pattern, *string;
    
    if (argc == 2) {
        
        const char *aux = (const char *)sqlite3_value_text((sqlite3_value*)argv[0]);
        
        /*Safeguard against null returns*/
        if (aux)
            pattern = [NSString stringWithUTF8String:aux];
        
        aux     = (const char *)sqlite3_value_text((sqlite3_value*)argv[1]);
        
        if (aux)
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
    
	(void)sqlite3_result_int(context, (int)numberOfMatches);
}

#pragma mark - migration helpers

- (BOOL)migrateFromModel:(NSManagedObjectModel *)fromModel toModel:(NSManagedObjectModel *)toModel error:(NSError **)error {
    BOOL __block success = YES;
    
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
            success &= [self createTableForEntity:destinationEntity error:error];
        }
        
        // drop table for deleted entity
        else if (type == NSRemoveEntityMappingType) {
            success &= [self dropTableForEntity:sourceEntity];
        }
        
        // change an entity
        else if (type == NSTransformEntityMappingType) {
            success &= [self
                        alterTableForSourceEntity:sourceEntity
                        destinationEntity:destinationEntity
                        withMapping:entityMapping
                        error:error];
            if (success)
            {
                success &= [self alterRelationshipForSourceEntity:sourceEntity
                                                destinationEntity:destinationEntity
                                                      withMapping:entityMapping
                                                            error:error];
            }
        }
    }];
    return success;
}

- (BOOL)initializeDatabase:(NSError**)error {
    BOOL __block success = YES;
    NSMutableSet *manytomanys = [NSMutableSet set];
    
    if (success) {
        NSArray *entities = [self storeEntities];
        [entities enumerateObjectsUsingBlock:^(NSEntityDescription *entity, NSUInteger idx, BOOL *stop) {
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
    NSMutableArray *entityIds = [NSMutableArray arrayWithObject:@(entity.typeHash)];
    
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
        NSString *column = [self foreignKeyColumnForRelationship:description];
        NSString *orderColumn = [NSString stringWithFormat:@"%@_order", [description name]];
        
        if (quotedNames) {
            column = [NSString stringWithFormat:@"'%@'", column];
            orderColumn = [NSString stringWithFormat:@"'%@' integer default 0", orderColumn];
        }
        [columns addObject:column];
        [columns addObject:orderColumn];
    }];
    
    for (NSEntityDescription *subentity in entity.subentities) {
        [columns addObjectsFromArray:[self columnNamesForEntity:subentity
                                                    indexedOnly:indexedOnly
                                                    quotedNames:quotedNames]];
    }
    
    return [columns allObjects];
}

-(BOOL)entityNeedsEntityTypeColumn:(NSEntityDescription *)entity
{
    return entity.subentities.count > 0 || entity.superentity;;
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
        [columns addObject:@"'__entityType' integer"];
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
    if (!result && error) {
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
                            @"CREATE INDEX %@_%@_INDEX ON %@ (`%@`)",
                            tableName,
                            column,
                            tableName,
                            column];
        sqlite3_stmt *statement = [self preparedStatementForQuery:query];
        sqlite3_step(statement);
        BOOL result = (statement != NULL && sqlite3_finalize(statement) == SQLITE_OK);
        if (!result && error) {
            *error = [self databaseError];
            return result;
        }
    }
    return YES;
}

- (BOOL)dropIndicesForEntity:(NSEntityDescription *)entity error:(NSError **)error
{
    if (entity.superentity) {
        return YES;
    }

    NSArray * indexedColumns = [self columnNamesForEntity:entity indexedOnly:YES quotedNames:NO];
    NSString * tableName = [self tableNameForEntity:entity];
    for (NSString * column in indexedColumns) {
        NSString * query = [NSString stringWithFormat:
                            @"DROP INDEX IF EXISTS %@_%@_INDEX",
                            tableName,
                            column];
        sqlite3_stmt *statement = [self preparedStatementForQuery:query];
        sqlite3_step(statement);
        BOOL result = (statement != NULL && sqlite3_finalize(statement) == SQLITE_OK);
        if (!result && error) {
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

    if (![self dropIndicesForEntity:destinationEntity error:error]) {
        return NO;
    }

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
    
    [[mapping relationshipMappings] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSRelationshipDescription *destinationRelationship = [destinationEntity relationshipsByName][[obj name]];
        NSRelationshipDescription * relationship = [sourceEntity relationshipsByName][([destinationRelationship renamingIdentifier] ? [destinationRelationship renamingIdentifier] : [obj name])];
        if (![relationship isToMany])
        {
            NSExpression *expression = [obj valueExpression];
            if (expression != nil) {
                NSString *destination = [self foreignKeyColumnForRelationshipName:[obj name]];
                [destinationColumns addObject:destination];
                NSString *source = [[[expression arguments] objectAtIndex:0] constantValue];
                source = [self foreignKeyColumnForRelationshipName:source];
                [sourceColumns addObject:source];
            }
        }
    }];
    
    // copy data
    if (destinationEntity.subentities.count > 0) {
        string = [NSString stringWithFormat:
                  @"INSERT INTO %@ ('__entityType', %@)"
                  @"SELECT %ld, %@ "
                  @"FROM %@",
                  destinationTableName,
                  [destinationColumns componentsJoinedByString:@", "],
                  destinationEntity.typeHash,
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

- (BOOL)createTableForRelationship:(NSRelationshipDescription *)relationship error:(NSError **)error
{
    NSString *firstIDColumn;
    NSString *secondIDColumn;
    NSString *firstOrderColumn;
    NSString *secondOrderColumn;
    [self relationships:relationship firstIDColumn:&firstIDColumn secondIDColumn:&secondIDColumn firstOrderColumn:&firstOrderColumn secondOrderColumn:&secondOrderColumn];
    
    NSString *relationTable = [self tableNameForRelationship:relationship];
    
    // create table
    NSString *string = [NSString stringWithFormat:
                        @"CREATE TABLE %@ ('%@' INTEGER NOT NULL, '%@' INTEGER NOT NULL, '%@' INTEGER DEFAULT 0, '%@' INTEGER DEFAULT 0, PRIMARY KEY('%@', '%@'));",
                        relationTable,
                        firstIDColumn, secondIDColumn, firstOrderColumn, secondOrderColumn, firstIDColumn, secondIDColumn];

    sqlite3_stmt *statement = [self preparedStatementForQuery:string];
    sqlite3_step(statement);
    
    BOOL result = (statement != NULL && sqlite3_finalize(statement) == SQLITE_OK);
    if (!result) {
        *error = [self databaseError];
        return result;
    }
    return YES;
}

- (BOOL)alterRelationshipForSourceEntity:(NSEntityDescription *)sourceEntity
                       destinationEntity:(NSEntityDescription *)destinationEntity
                             withMapping:(NSEntityMapping *)mapping
                                   error:(NSError**)error
{
    // locate all the many-to-many relationship tables
    BOOL __block success = YES;
    
    [[mapping relationshipMappings] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSRelationshipDescription *destinationRelationship = [destinationEntity relationshipsByName][[obj name]];
        NSRelationshipDescription * relationship = [sourceEntity relationshipsByName][([destinationRelationship renamingIdentifier] ? [destinationRelationship renamingIdentifier] : [obj name])];
        if ([relationship isToMany] && [relationship.inverseRelationship isToMany] && [destinationRelationship isToMany] && [destinationRelationship.inverseRelationship isToMany])
        {
            sqlite3_stmt *statement;
            NSString *oldTableName = [self tableNameForPreviousRelationship:destinationRelationship];
            
            //check if table exists
            BOOL tableExists = NO;
            NSString *checkExistenceOfTable = [NSString stringWithFormat:@"SELECT count(*) FROM %@", oldTableName];
            statement = [self preparedStatementForQuery:checkExistenceOfTable];
            sqlite3_step(statement);
            if (statement != NULL && sqlite3_finalize(statement) == SQLITE_OK)
            {
                tableExists = YES;
            }
            
            //if tableExists = YES; it probably means we haven't upgraded the table yet.
            if (tableExists)
            {
                NSString *newTableName = [self tableNameForRelationship:destinationRelationship];
                NSString *temporaryTableName = [NSString stringWithFormat:@"_T_%@", oldTableName];
                
                //rename old table
                NSString *string = [NSString stringWithFormat:
                                    @"ALTER TABLE %@ "
                                    @"RENAME TO %@;",
                                    oldTableName,
                                    temporaryTableName];
                statement = [self preparedStatementForQuery:string];
                sqlite3_step(statement);
                
                if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK)
                {
                    success &= NO;
                    return;
                }
                
                //create new table
                if (![self createTableForRelationship:destinationRelationship error:error])
                {
                    success &= NO;
                    return;
                }
                
                //insert records
                NSString *firstIDColumn;
                NSString *secondIDColumn;
                NSString *firstOrderColumn;
                NSString *secondOrderColumn;
                [self relationships:destinationRelationship firstIDColumn:&firstIDColumn secondIDColumn:&secondIDColumn firstOrderColumn:&firstOrderColumn secondOrderColumn:&secondOrderColumn];
                
                NSString *previousFirstIDColumn;
                NSString *previousSecondIDColumn;
                NSString *previousFirstOrderColumn;
                NSString *previousSecondOrderColumn;
                [self previousRelationships:destinationRelationship firstIDColumn:&previousFirstIDColumn secondIDColumn:&previousSecondIDColumn firstOrderColumn:&previousFirstOrderColumn secondOrderColumn:&previousSecondOrderColumn];
                
                string = [NSString stringWithFormat:
                          @"INSERT INTO %@ (%@)"
                          @"SELECT %@ "
                          @"FROM %@",
                          newTableName,
                          [@[firstIDColumn, secondIDColumn, firstOrderColumn, secondOrderColumn] componentsJoinedByString:@", "],
                          [@[previousFirstIDColumn, previousSecondIDColumn, previousFirstOrderColumn, previousSecondOrderColumn] componentsJoinedByString:@", "],
                          temporaryTableName];
                statement = [self preparedStatementForQuery:string];
                sqlite3_step(statement);
                if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK) {
                    success &= NO;
                    return;
                }
                
                
                //drop old temporary table
                if (![self dropTableNamed:temporaryTableName])
                {
                    success &= NO;
                    return;
                }
                
                
            }

        }
    }];
    
    return success;
}

/// Performs case insensitive comparsion using the fixed EN-US POSIX locale
-(NSComparator)fixedLocaleCaseInsensitiveComparator
{
    return ^NSComparisonResult(NSString *obj1, NSString *obj2) {
        static NSLocale *enPOSIXLocale;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            enPOSIXLocale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        });
        
        return [obj1 compare:obj2 options:NSCaseInsensitiveSearch range:NSMakeRange(0, [obj1 length]) locale:enPOSIXLocale];
    };
}

-(NSString *)tableNameForRelationship:(NSRelationshipDescription *)relationship {
    NSRelationshipDescription *inverse = [relationship inverseRelationship];
    NSArray *names = [@[[relationship name],[inverse name]] sortedArrayUsingComparator:[self fixedLocaleCaseInsensitiveComparator]];
    return [NSString stringWithFormat:@"ecd_%@",[names componentsJoinedByString:@"_"]];
}

- (NSString *)tableNameForPreviousRelationship:(NSRelationshipDescription *)relationship
{
    NSRelationshipDescription *inverse = [relationship inverseRelationship];
    NSArray *names = [@[([relationship renamingIdentifier] ? [relationship renamingIdentifier] : [relationship name]), ([inverse renamingIdentifier] ? [inverse renamingIdentifier] : [inverse name])] sortedArrayUsingComparator:[self fixedLocaleCaseInsensitiveComparator]];
    return [NSString stringWithFormat:@"ecd_%@",[names componentsJoinedByString:@"_"]];
}
/// Create columns for both object IDs. @returns YES  if the relationship.entity was first
-(BOOL)relationships:(NSRelationshipDescription *)relationship firstIDColumn:(NSString *__autoreleasing*)firstIDColumn secondIDColumn:(NSString *__autoreleasing*)secondIDColumn firstOrderColumn:(NSString *__autoreleasing*)firstOrderColumn secondOrderColumn:(NSString *__autoreleasing*)secondOrderColumn
{
    NSParameterAssert(firstIDColumn);
    NSParameterAssert(secondIDColumn);
    NSParameterAssert(firstOrderColumn);
    NSParameterAssert(secondOrderColumn);
    
    NSEntityDescription *rootSourceEntity = [self rootForEntity:relationship.entity];
    NSEntityDescription *rootDestinationEntity = [self rootForEntity:relationship.destinationEntity];
    
    static NSString *format = @"%@__objectid";
    static NSString *orderFormat = @"%@_order";
    
    if ([rootSourceEntity isEqual:rootDestinationEntity]) {
        *firstIDColumn = [NSString stringWithFormat:format, [rootSourceEntity.name stringByAppendingString:@"_1"]];
        *secondIDColumn = [NSString stringWithFormat:format, [rootDestinationEntity.name stringByAppendingString:@"_2"]];
        *firstOrderColumn = [NSString stringWithFormat:orderFormat, [rootSourceEntity.name stringByAppendingString:@"_1"]];
        *firstOrderColumn = [NSString stringWithFormat:orderFormat, [rootDestinationEntity.name stringByAppendingString:@"_2"]];
        
        return YES;
    }
    
    NSArray *orderedEntities = [@[rootSourceEntity, rootDestinationEntity] sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(name)) ascending:YES comparator:[self fixedLocaleCaseInsensitiveComparator]]]];
    
    NSEntityDescription *firstEntity = [orderedEntities firstObject];
    NSEntityDescription *secondEntity = [orderedEntities lastObject];
    
    // 1st
    *firstIDColumn = [NSString stringWithFormat:format, firstEntity.name];
    *firstOrderColumn = [NSString stringWithFormat:orderFormat, firstEntity.name];
    
    // 2nd
    *secondIDColumn = [NSString stringWithFormat:format, secondEntity.name];
    *secondOrderColumn = [NSString stringWithFormat:orderFormat, secondEntity.name];
    
    // Return if the relationship.entity was first
    return orderedEntities[0] == rootSourceEntity;
}

/// Create columns for both object IDs. @returns YES  if the relationship.entity was first
-(BOOL)previousRelationships:(NSRelationshipDescription *)relationship firstIDColumn:(NSString *__autoreleasing*)firstIDColumn secondIDColumn:(NSString *__autoreleasing*)secondIDColumn firstOrderColumn:(NSString *__autoreleasing*)firstOrderColumn secondOrderColumn:(NSString *__autoreleasing*)secondOrderColumn
{
    NSParameterAssert(firstIDColumn);
    NSParameterAssert(secondIDColumn);
    NSParameterAssert(firstOrderColumn);
    NSParameterAssert(secondOrderColumn);
    
    NSEntityDescription *rootSourceEntity = [self rootForEntity:relationship.entity];
    NSEntityDescription *rootDestinationEntity = [self rootForEntity:relationship.destinationEntity];
    
    static NSString *format = @"%@__objectid";
    static NSString *orderFormat = @"%@_order";
    
    if ([rootSourceEntity isEqual:rootDestinationEntity]) {
        *firstIDColumn = [NSString stringWithFormat:format, [rootSourceEntity.name stringByAppendingString:@"_1"]];
        *secondIDColumn = [NSString stringWithFormat:format, [rootDestinationEntity.name stringByAppendingString:@"_2"]];
        *firstOrderColumn = [NSString stringWithFormat:orderFormat, [rootSourceEntity.name stringByAppendingString:@"_1"]];
        *firstOrderColumn = [NSString stringWithFormat:orderFormat, [rootDestinationEntity.name stringByAppendingString:@"_2"]];
        
        return YES;
    }
    
    NSArray *orderedEntities = [@[rootSourceEntity, rootDestinationEntity] sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(name)) ascending:YES comparator:[self fixedLocaleCaseInsensitiveComparator]]]];
    
    NSEntityDescription *firstEntity = [orderedEntities firstObject];
    NSEntityDescription *secondEntity = [orderedEntities lastObject];
    
    // 1st
    *firstIDColumn = [NSString stringWithFormat:format, (firstEntity.renamingIdentifier ? firstEntity.renamingIdentifier : firstEntity.name)];
    *firstOrderColumn = [NSString stringWithFormat:orderFormat, (firstEntity.renamingIdentifier ? firstEntity.renamingIdentifier : firstEntity.name)];
    
    // 2nd
    *secondIDColumn = [NSString stringWithFormat:format, (secondEntity.renamingIdentifier ? secondEntity.renamingIdentifier : secondEntity.name)];
    *secondOrderColumn = [NSString stringWithFormat:orderFormat, (secondEntity.renamingIdentifier ? secondEntity.renamingIdentifier : secondEntity.name)];
    
    // Return if the relationship.entity was first
    return orderedEntities[0] == rootSourceEntity;
}

/// Create columns for both object IDs. @returns YES  if the relationship.entity was first
-(BOOL)relationships:(NSRelationshipDescription *)relationship firstIDColumn:(NSString *__autoreleasing*)firstIDColumn secondIDColumn:(NSString *__autoreleasing*)secondIDColumn
{
    NSParameterAssert(firstIDColumn);
    NSParameterAssert(secondIDColumn);
    
    NSEntityDescription *rootSourceEntity = [self rootForEntity:relationship.entity];
    NSEntityDescription *rootDestinationEntity = [self rootForEntity:relationship.destinationEntity];
    
    static NSString *format = @"%@__objectid";
    
    if ([rootSourceEntity isEqual:rootDestinationEntity]) {
        *firstIDColumn = [NSString stringWithFormat:format, [rootSourceEntity.name stringByAppendingString:@"_1"]];
        *secondIDColumn = [NSString stringWithFormat:format, [rootDestinationEntity.name stringByAppendingString:@"_2"]];
        
        return YES;
    }
    
    NSArray *orderedEntities = [@[rootSourceEntity, rootDestinationEntity] sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(name)) ascending:YES comparator:[self fixedLocaleCaseInsensitiveComparator]]]];
    
    NSEntityDescription *firstEntity = [orderedEntities firstObject];
    NSEntityDescription *secondEntity = [orderedEntities lastObject];
    
    // 1st
    *firstIDColumn = [NSString stringWithFormat:format, firstEntity.name];
    
    // 2nd
    *secondIDColumn = [NSString stringWithFormat:format, secondEntity.name];
    
    // Return if the relationship.entity was first
    return orderedEntities[0] == rootSourceEntity;
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
        
        BOOL __block containsOrder = NO;
        NSMutableArray * orderValues = [[NSMutableArray alloc] init];
        
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
                    
                    //NSLog(@"entity: %@", [self rootForEntity:desc.entity].name);
                    //NSLog(@"destinationEntity: %@", [self rootForEntity:desc.destinationEntity].name);
                    //NSLog(@"inverse == nil: %@", inverse == nil ? @"YES" : @"NO");
                    //NSLog(@"inverse isToMany: %@", inverse.isToMany ? @"YES" : @"NO");
                    
                    // if an inverse relationship exists and if it is to-many
                    if (inverse != nil && [inverse isToMany]) {
                        NSManagedObject * relationshipObject = [object valueForKey:[desc name]];
                        
                        //NSLog(@"Inverse Relationship Name: %@", [inverse name]);
                        
                        NSObject* values = [relationshipObject valueForKey:[inverse name]];
                        
                        //NSLog(@"VALUES: %@", values);
                        //NSLog(@"Value class: %@", [values class]);
                        //NSLog(@"is NSSet: %@", [values isKindOfClass:[NSSet class]] ? @"YES" : @"NO");
                        //NSLog(@"is NSOrderedSet: %@", [values isKindOfClass:[NSOrderedSet class]] ? @"YES" : @"NO");
                        
                        if ([values isKindOfClass:[NSOrderedSet class]]) {
                            containsOrder = YES;
                            
                            NSOrderedSet* orderedValues = (NSOrderedSet*) values;
                            
                            // highest order if not found
                            NSNumber* orderSequence = @(INT_MAX);
                            if ([orderedValues containsObject:object]) {
                                orderSequence = @([orderedValues indexOfObject:object]);
                            }
                            
                            [orderValues addObject:@{
                                                     @"k":[NSString stringWithFormat:@"'%@_order'", [desc name]],
                                                     @"v":orderSequence
                                                     }];
                        }
                }
                }
                else if ([desc isToMany] && [inverse isToMany]) {
                    if (![self handleUpdatedRelationInSaveRequest:desc forObject:object error:error]) {
                        success = NO;
                    }
                }
                
            }
        }];
        
        if (containsOrder) {
            for (NSDictionary * dict in orderValues) {
                [columns addObject:[dict objectForKey:@"k"]];
            }
        }
        
        // prepare statement
        NSString *string = nil;
        if (entity.superentity != nil) {
            string = [NSString stringWithFormat:
                      @"INSERT INTO %@ ('__entityType', %@) VALUES(%ld, %@);",
                      [self tableNameForEntity:entity],
                      [columns componentsJoinedByString:@", "],
                      entity.typeHash,
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
        int __block columnIndex;
        [keys enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            // SQL indexes start at 1
            columnIndex = (int)idx + 1;
            NSPropertyDescription *property = [properties objectForKey:obj];
            // Add 1 to column index as the first bind is the objectID
            [self bindProperty:property withValue:[object valueForKey:obj] forKey:obj toStatement:statement atIndex:columnIndex + 1];
        }];
        
        if (containsOrder) {
            columnIndex++;
            for (NSDictionary * dict in orderValues) {
                sqlite3_bind_int(statement, columnIndex + 1, [[dict objectForKey:@"v"] intValue]);
                columnIndex++;
            }
        }
        
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

    
- (int)nextOrderForColumnInRelationship:(NSRelationshipDescription *)relationship forObject:(NSManagedObject *)object andSource:(BOOL)source {
    int order = 0;
    
    // Object
    unsigned long long objectID = [[self referenceObjectForObjectID:[object objectID]] unsignedLongLongValue];
    
    NSString *tableName = [self tableNameForRelationship:relationship];
    
    NSString *firstIDColumn, *secondIDColumn, *firstOrderColumn, *secondOrderColumn;
    
    BOOL firstColumnIsSource = [self relationships:relationship firstIDColumn:&firstIDColumn secondIDColumn:&secondIDColumn firstOrderColumn:&firstOrderColumn secondOrderColumn:&secondOrderColumn];
        
    NSString *string = [NSString stringWithFormat:
                        @"SELECT MAX(%@) FROM %@ WHERE %@=%llu;",
                        source ?
                        (firstColumnIsSource ? firstOrderColumn : secondOrderColumn):
                        (firstColumnIsSource ? secondOrderColumn : firstOrderColumn),
                        tableName,
                        source ?
                        (firstColumnIsSource ? secondIDColumn : firstIDColumn):
                        (firstColumnIsSource ? firstIDColumn : secondIDColumn),
                        objectID];
        
        sqlite3_stmt *statement = [self preparedStatementForQuery:string];
    if (sqlite3_step(statement) == SQLITE_ROW) {
        order = sqlite3_column_int(statement, 0);
            }
    if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK) {
        }
    return order + 1;
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
                    // find order!
                    NSString *column = [self foreignKeyColumnForRelationship:property];
                    NSString *orderColumn = [NSString stringWithFormat:@"%@_order", [desc name]];
                    NSNumber *orderSequence = @(0);
                    
                    NSManagedObject * relationshipObject = [object valueForKey:[desc name]];
                    if (inverse) {
                        NSSet* values = [relationshipObject valueForKey:[inverse name]];
                        if ([values isKindOfClass:[NSOrderedSet class]]) {
                            NSOrderedSet* orderedValues = (NSOrderedSet*) values;
                            orderSequence = @([orderedValues indexOfObject:object]);
                        }
                    }
                    
                    
                    [columns addObject:[NSString stringWithFormat:@"%@=?", column]];
                    [columns addObject:[NSString stringWithFormat:@"%@=%ld", orderColumn, (long)[orderSequence integerValue]]];
                    
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
                if ([property isKindOfClass:[NSRelationshipDescription class]]) {
                    [cacheChanges setObject:[value objectID] forKey:obj];
                } else {
                    [cacheChanges setObject:value forKey:obj];
                }
            }
            else {
                [cacheChanges setObject: [NSNull null] forKey: obj];
            }
#endif
            [self
             bindProperty:property
             withValue:value
             forKey:obj
             toStatement:statement
             atIndex:((int)idx + 1)];
        }];
        
        // execute
        NSNumber *number = [self referenceObjectForObjectID:objectID];
        sqlite3_bind_int64(statement, ((int)[keys count] + 1), [number unsignedLongLongValue]);
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


- (BOOL)handleUpdatedRelationInSaveRequest:(NSRelationshipDescription *)relationship forObject:(NSManagedObject *)object error:(NSError **)error {
    // Inverse
    NSSet *inverseObjects = [object valueForKey:[relationship name]];
    
    if ([inverseObjects count] == 0) {
        // No objects to add so finish
        return YES;
    }
    
    NSString *tableName = [self tableNameForRelationship:relationship];
    
    NSString *firstIDColumn, *secondIDColumn, *firstOrderColumn, *secondOrderColumn;
    
    BOOL firstColumnIsSource = [self relationships:relationship firstIDColumn:&firstIDColumn secondIDColumn:&secondIDColumn firstOrderColumn:&firstOrderColumn secondOrderColumn:&secondOrderColumn];
    
    // Object
    unsigned long long objectID = [[self referenceObjectForObjectID:[object objectID]] unsignedLongLongValue];
    
    NSString *values = [NSString stringWithFormat:(firstColumnIsSource ? @"%llu, ?, ?, ?" : @"?, %llu, ?, ?"), objectID];
    NSString *insert = [NSString stringWithFormat:@"INSERT INTO %@ (%@, %@, %@, %@) VALUES (%@);", tableName, firstIDColumn, secondIDColumn, firstOrderColumn, secondOrderColumn, values];
    NSString *update = [NSString stringWithFormat:@"UPDATE %@ SET %@ = ? WHERE %@ = ? AND %@ = ?", tableName, firstColumnIsSource ? secondOrderColumn : firstOrderColumn, firstIDColumn, secondIDColumn];
    
    __block BOOL success = YES;
    int x = 1;
    
    NSMutableArray * inverseObjectIDs = [[NSMutableArray alloc] init];
    
    for (NSManagedObject *obj in inverseObjects) {
        
        NSNumber *inverseObjectID = [self referenceObjectForObjectID:[obj objectID]];
        unsigned long long refObjectID = [[self referenceObjectForObjectID:[obj objectID]] unsignedLongLongValue];
        
        NSString *countQuery = [NSString stringWithFormat:@"SELECT COUNT(*) FROM %@ WHERE %@ = %llu AND %@ = %llu", tableName, firstIDColumn, firstColumnIsSource ? objectID : refObjectID, secondIDColumn, firstColumnIsSource ? refObjectID : objectID];
        
        if ([self hasRows:countQuery]) {
            // relationship exists, update!
            sqlite3_stmt *statement = [self preparedStatementForQuery:update];
            
            int ord = x;
            
            if (firstColumnIsSource) {
                sqlite3_bind_int(statement, 1, ord);
                sqlite3_bind_int64(statement, 2, objectID);
                sqlite3_bind_int64(statement, 3, [inverseObjectID unsignedLongLongValue]);
            } else {
                sqlite3_bind_int(statement, 1, ord);
                sqlite3_bind_int64(statement, 2, [inverseObjectID unsignedLongLongValue]);
                sqlite3_bind_int64(statement, 3, objectID);
            }
            
            sqlite3_step(statement);
            
            int finalize = sqlite3_finalize(statement);
            if (finalize != SQLITE_OK && finalize != SQLITE_CONSTRAINT) {
                if (error != nil) {
                    *error = [self databaseError];
                }
                success = NO;
            } else {
                success = YES;
            }
            
        } else {
            // insert
            
            int firstOrder = [self nextOrderForColumnInRelationship:relationship forObject:obj andSource:YES];
            int secondOrder = x;
            
            sqlite3_stmt *statement = [self preparedStatementForQuery:insert];
            
            // Add the related objects properties
            sqlite3_bind_int64(statement, 1, [inverseObjectID unsignedLongLongValue]);
            
            if (firstColumnIsSource) {
                sqlite3_bind_int(statement, 2, firstOrder);
                sqlite3_bind_int(statement, 3, secondOrder);
                //NSLog(@"%@ = %d, %@ = %d", firstOrderColumn, firstOrder, secondOrderColumn, secondOrder);
            } else {
                sqlite3_bind_int(statement, 2, secondOrder);
                sqlite3_bind_int(statement, 3, firstOrder);
                //NSLog(@"%@ = %d, %@ = %d", firstOrderColumn, secondOrder, secondOrderColumn, firstOrder);
}

            sqlite3_step(statement);
            
            int finalize = sqlite3_finalize(statement);
            if (finalize != SQLITE_OK && finalize != SQLITE_CONSTRAINT) {
                if (error != nil) {
                    *error = [self databaseError];
                }
                success = NO;
            } else {
                success = YES;
            }
        }
        
        [inverseObjectIDs addObject:inverseObjectID];
        
        x++;
        
        if (!success)
            break;
    }
    
    if (success) {
        // delete the rest of the relations
        NSString *notInValues = [inverseObjectIDs componentsJoinedByString:@","];
    
        NSString *deleteQuery = [NSString stringWithFormat:@"DELETE FROM %@ WHERE %@=? AND %@ NOT IN (%@);",
                                 [self tableNameForRelationship:relationship],
                                 firstColumnIsSource ? firstIDColumn : secondIDColumn,
                                 firstColumnIsSource ? secondIDColumn : firstIDColumn,
                                 notInValues];
    
        sqlite3_stmt *statement = [self preparedStatementForQuery:deleteQuery];
    
    NSNumber *number = [self referenceObjectForObjectID:[object objectID]];
    sqlite3_bind_int64(statement, 1, [number unsignedLongLongValue]);
    
    sqlite3_step(statement);
    
    if (statement == NULL || sqlite3_finalize(statement) != SQLITE_OK) {
        if (error != nil) { *error = [self databaseError]; }
        success = NO;
        }
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
                                    [self tableNameForRelationship:desc],[[self rootForEntity:[desc entity]] name]];
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

- (BOOL)hasRows:(NSString *)query {
    int count = 0;
    sqlite3_stmt *statement = [self preparedStatementForQuery:query];
    if (statement != NULL && sqlite3_step(statement) == SQLITE_ROW) {
        count = sqlite3_column_int(statement, 0);
    }
    sqlite3_finalize(statement);
    return (count > 0);
}

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

- (NSString *)tableNameForEntity:(NSEntityDescription *)entity
{
    return [NSString stringWithFormat:@"ecd%@", [self rootForEntity:entity].name];
}

/// Traverses up the object hierarchy and finds the base entity
- (NSEntityDescription *)rootForEntity:(NSEntityDescription *)entity
{
    NSEntityDescription *targetEntity = entity;
    while ([targetEntity superentity] != nil) {
        targetEntity = [targetEntity superentity];
    }
    return targetEntity;
}

- (sqlite3_stmt *)preparedStatementForQuery:(NSString *)query {
    static BOOL debug = NO;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        debug = [[NSUserDefaults standardUserDefaults] boolForKey:@"com.apple.CoreData.SQLDebug"];
    });
    if (debug)
    {NSLog(@"SQL DEBUG: %@", query); }
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
            tableName = [self joinedTableNameForComponents:[components subarrayWithRange:NSMakeRange(0, components.count -1)] forRelationship:NO];
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

- (NSString *) getJoinClause: (NSFetchRequest *) fetchRequest withPredicate:(NSPredicate*)predicate initial:(BOOL)initial{
    return [self getJoinClause:fetchRequest withPredicate:predicate initial:initial withStatements:nil];
}
    
- (NSString *) getJoinClause: (NSFetchRequest *) fetchRequest withPredicate:(NSPredicate*)predicate initial:(BOOL)initial withStatements: (NSMutableSet *) previousJoinStatementsSet {
    NSEntityDescription *entity = [fetchRequest entity];
    // We use a set to only add one join table per relationship.
    NSMutableSet *joinStatementsSet;
    if (previousJoinStatementsSet != nil) {
        joinStatementsSet = previousJoinStatementsSet;
    } else {
        joinStatementsSet = [NSMutableSet set];
    }
    // We use an array to ensure the order of join statements
    NSMutableArray *joinStatementsArray = [NSMutableArray array];
    
    if (initial) {
        // First look at all sort descriptor keys
        NSArray *descs = [fetchRequest sortDescriptors];
        for (NSSortDescriptor *sd in descs) {
            NSString *sortKey = [sd key];
            if ([sortKey rangeOfString:@"."].location != NSNotFound) {
                if ([self maybeAddJoinStatementsForKey:sortKey toStatementArray:joinStatementsArray withExistingStatementSet:joinStatementsSet rootEntity:entity]) {
                    [fetchRequest setReturnsDistinctResults:YES];
                }
            }
        }
    }
    
    if ([predicate isKindOfClass:[NSCompoundPredicate class]]) {
        NSCompoundPredicate * compoundPred = (NSCompoundPredicate*) predicate;
        for (id subpred in [compoundPred subpredicates]){
            [joinStatementsArray addObject:[self getJoinClause:fetchRequest withPredicate:subpred initial:NO withStatements: joinStatementsSet]];
        }
    }
    else if ([predicate isKindOfClass:[NSComparisonPredicate class]]){
        NSComparisonPredicate *comparisonPred = (NSComparisonPredicate*) predicate;
        NSString *predicateString = [predicate predicateFormat];
        if (predicateString != nil ) {
            NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:@"\\b([a-zA-Z]\\w*\\.[^= ]+)\\b" options:0 error:nil];
            NSArray* matches = [regex matchesInString:predicateString options:0 range:NSMakeRange(0, [predicateString length])];
            for ( NSTextCheckingResult* match in matches )
            {
                NSString* matchText = [predicateString substringWithRange:[match range]];
                if ([matchText hasSuffix:@".@count"]) {
                    // @count queries should be handled by sub-expressions rather than joins
                    continue;
                }
                if ([self maybeAddJoinStatementsForKey:matchText toStatementArray:joinStatementsArray withExistingStatementSet:joinStatementsSet rootEntity:entity]) {
                    [fetchRequest setReturnsDistinctResults:YES];
                }
            }
        }
        NSExpression *leftExp = [comparisonPred leftExpression];
        if ([leftExp expressionType] == NSKeyPathExpressionType) {
            id property = [[[fetchRequest entity] propertiesByName] objectForKey:[leftExp keyPath]];
            if([property isKindOfClass:[NSRelationshipDescription class]]){
                NSRelationshipDescription *desc = (NSRelationshipDescription*)property;
                if ([desc isToMany] && [[desc inverseRelationship] isToMany]) {
                    if ([self maybeAddJoinStatementsForKey:[leftExp keyPath] toStatementArray:joinStatementsArray withExistingStatementSet:joinStatementsSet rootEntity:entity]) {
                        [fetchRequest setReturnsDistinctResults:YES];
                    }
                }
            }
        }
        NSExpression *rightExp = [comparisonPred rightExpression];
        if ([rightExp expressionType] == NSKeyPathExpressionType){
            id property = [[[fetchRequest entity] propertiesByName] objectForKey:[rightExp keyPath]];
            if([property isKindOfClass:[NSRelationshipDescription class]]){
                NSRelationshipDescription *desc = (NSRelationshipDescription*)property;
                if ([desc isToMany] && [[desc inverseRelationship] isToMany]) {
                    if ([self maybeAddJoinStatementsForKey:[rightExp keyPath] toStatementArray:joinStatementsArray withExistingStatementSet:joinStatementsSet rootEntity:entity]) {
                        [fetchRequest setReturnsDistinctResults:YES];
                    }
                }
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
                           rootEntity: (NSEntityDescription *) rootEntity {
    
    BOOL retval = NO;
    
    // We support have deeper relationships (e.g. child.parent.name ) by bracketing the
    // intermediate tables and updating the keys in the WHERE or ORDERBY to use the bracketed
    // table: EG
    // child.parent.name -> [child.parent].name and we generate a double join
    // JOIN childTable as child on mainTable.child_id = child.ID
    // JOIN parentTable as [child.parent] on child.parent_id = [child.parent].ID
    // child.name == %@ AND child.parent.name == %@ doesn't add the child relationship twice
    // Care must be taken to ensure unique join table names so that a WHERE clause like:
    NSArray *keysArray = [key componentsSeparatedByString:@"."];
    
    // We terminate when there is one item left since that is the field of interest
    NSEntityDescription *currentEntity = rootEntity;
    NSString *fullJoinClause;
    NSString *lastTableName = [self tableNameForEntity:currentEntity];
    for (int i = 0 ; i < keysArray.count; i++) {
        
        // alt names for tables for safety
        NSString *relTableName = [self joinedTableNameForComponents:
                                  [keysArray subarrayWithRange: NSMakeRange(0, i+1)]
                                                    forRelationship:YES];
        
        NSString *nextTableName = [self joinedTableNameForComponents:
                                   [keysArray subarrayWithRange: NSMakeRange(0, i+1)]
                                                     forRelationship:NO];
        
        NSRelationshipDescription *rel = [[currentEntity relationshipsByName]
                                          objectForKey:[keysArray objectAtIndex:i]];
        NSRelationshipDescription *inverse = [rel inverseRelationship];
        
        if (rel != nil) {
            
            retval = YES;
            
            if ([rel isToMany] && [inverse isToMany]) {
                
                // ID columns
                NSString *firstIDColumn;
                NSString *secondIDColumn;
                BOOL sourceFirst = [self relationships:rel firstIDColumn:&firstIDColumn secondIDColumn:&secondIDColumn];
                
                NSString *clause1Column;
                NSString *clause2Column;
                if (sourceFirst) {
                    clause1Column = firstIDColumn;
                    clause2Column = secondIDColumn;
                } else {
                    clause1Column = secondIDColumn;
                    clause2Column = firstIDColumn;
                }
                
                NSString *joinTableAsClause1 = [NSString stringWithFormat:@"%@ AS %@",
                                                [self tableNameForRelationship:rel],
                                                relTableName];
                
                NSString *joinTableOnClause1 = [NSString stringWithFormat:@"%@.__objectID = %@.%@",
                                               lastTableName,
                                               relTableName,
                                               clause1Column];
                
                NSString *firstJoinClause = [NSString stringWithFormat:@"LEFT OUTER JOIN %@ ON %@", joinTableAsClause1, joinTableOnClause1];
                
                NSString *joinTableAsClause2 = [NSString stringWithFormat:@"%@ AS %@",
                                                [self tableNameForEntity:[rel destinationEntity]],
                                                nextTableName];
                
                NSString *joinTableOnClause2 = [NSString stringWithFormat:@"%@.%@ = %@.__objectID",
                                                relTableName,
                                                clause2Column,
                                                nextTableName];
                
                NSString *secondJoinClause = [NSString stringWithFormat:@"LEFT OUTER JOIN %@ ON %@", joinTableAsClause2, joinTableOnClause2];
                
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
                // NOTE: we use an outer join instead of an inner one because the where clause might also
                // be explicitely looking for cases where the relationship is null or has a specific value
                // consider the following predicate: "entity.rel = null || entity.rel.field = 'something'".
                // If we were to use an inner join the first part of the or clause would never work because
                // those objects would get discarded by the join.
                // Also, note that NSSQLiteStoreType correctly generates an outer join for this case but regular
                // joins for others. That's obviously better for performance but for now, correctness should
                // take precedence over performance. This should obviously be revisited at some point.
                fullJoinClause = [NSString stringWithFormat:@"LEFT OUTER JOIN %@ ON %@", joinTableAsClause, joinTableOnClause];
            }
            
            currentEntity = rel.destinationEntity;
            lastTableName = nextTableName;
            if (![statementsSet containsObject:fullJoinClause]) {
                [statementsSet addObject:fullJoinClause];
                [statementArray addObject:fullJoinClause];
            }
        }
    }
    
    return retval;
}


- (NSString *)expressionDescriptionTypeString:(NSExpressionDescription *)expressionDescription {
    
    switch (expressionDescription.expressionResultType) {
        case NSObjectIDAttributeType:
            return @"__objectID";
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
            return @"";
            break;
    }
}

- (NSString *)columnsClauseWithProperties:(NSArray *)properties {
    NSMutableArray *columns = [NSMutableArray arrayWithCapacity:[properties count]];
    
    [properties enumerateObjectsUsingBlock:^(NSPropertyDescription *prop, NSUInteger idx, BOOL *stop) {
        if ([prop isKindOfClass:[NSRelationshipDescription class]]) {
            if (![(NSRelationshipDescription *)prop isToMany]) {
                [columns addObject:[self foreignKeyColumnForRelationship:(NSRelationshipDescription *)prop]];
            }
        } else if ([prop isKindOfClass:[NSExpressionDescription class]]) {
            [columns addObject:[self expressionDescriptionTypeString:(NSExpressionDescription *)prop]];
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
                sqlite3_bind_blob(statement, index, [value bytes], (int)[value length], SQLITE_TRANSIENT);
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
                sqlite3_bind_blob(statement, index, [data bytes], (int)[data length], SQLITE_TRANSIENT);
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
        if ([self entityNeedsEntityTypeColumn:target]) {
            long long entityType = sqlite3_column_int64(statement, index + 1);
            NSEntityDescription *resolvedTarget = [entityTypeCache objectForKey:@(entityType)];
            if (resolvedTarget) {
                target = resolvedTarget;
            }
        }
        NSNumber *number = @(sqlite3_column_int64(statement, index));
        return [self newObjectIDForEntity:target referenceObject:number];
    }
    
    else if ([property isKindOfClass:[NSExpressionDescription class]]) {
        NSNumber *number = @(sqlite3_column_int64(statement, index));
        return [self expressionDescriptionTypeValue:(NSExpressionDescription *)property withReferenceNumber:number];
    }
    
    return nil;
}

-(id)expressionDescriptionTypeValue:(NSExpressionDescription *)expressionDescription
                withReferenceNumber:(NSNumber *)number {
    
    switch ([expressionDescription expressionResultType]) {
        case NSObjectIDAttributeType:
            if ([expressionDescription entity])
                return [self newObjectIDForEntity:[expressionDescription entity] referenceObject:number];
            else if (expressionDescription.name) {
                NSEntityDescription * e = [[[self persistentStoreCoordinator] managedObjectModel] entitiesByName][expressionDescription.name];
                return [self newObjectIDForEntity:e referenceObject:number];
            }
            else
            {
                return nil;
            }
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
                      @(NSGreaterThanOrEqualToPredicateOperatorType) : @{ @"operator" : @">=",     @"format" : @"%@" },
                      @(NSBetweenPredicateOperatorType)              : @{ @"operator" : @"BETWEEN",     @"format" : @"%@ AND %@" }
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
        if (rightOperand && !rightBindings) {
            if([[operator objectForKey:@"operator"] isEqualToString:@"!="]) {
                query = [@[leftOperand, @"IS NOT", rightOperand] componentsJoinedByString:@" "];
            } else {
                query = [@[leftOperand, @"IS", rightOperand] componentsJoinedByString:@" "];
            }
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
            entityWhere = [NSString stringWithFormat:@"%@.__entityType IN (%@)",
                           [self tableNameForEntity:request.entity],
                           [[self entityIdsForEntity:request.entity] componentsJoinedByString:@", "]];
        } else {
            entityWhere = [NSString stringWithFormat:@"%@.__entityType = %ld",
                           [self tableNameForEntity:request.entity],
                           request.entity.typeHash];
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
            const char* str = [obj UTF8String];
			int len = (int)strlen(str);

			if (str[0] == '\'' && str[len-1] == '\'')
				sqlite3_bind_text(statement, (int)(idx + 1), str+1, len-2, SQLITE_TRANSIENT);
			else
				sqlite3_bind_text(statement, (int)(idx + 1), str, len, SQLITE_TRANSIENT);
        }

        // number
        else if ([obj isKindOfClass:[NSNumber class]]) {
            
            switch (CFNumberGetType((CFNumberRef)obj)) {
                case kCFNumberFloat32Type:
                case kCFNumberFloat64Type:
                case kCFNumberFloatType:
                case kCFNumberDoubleType:
                case kCFNumberCGFloatType:
                    sqlite3_bind_double(statement, ((int)idx + 1), [obj doubleValue]);
                    break;
                    
                default:
                    sqlite3_bind_int64(statement, ((int)idx + 1), [obj longLongValue]);
                    break;
            }
        }
        
        // managed object id
        else if ([obj isKindOfClass:[NSManagedObjectID class]]) {
            id referenceObject = [self referenceObjectForObjectID:obj];
            sqlite3_bind_int64(statement, ((int)idx + 1), [referenceObject unsignedLongLongValue]);
        }
        
        // managed object
        else if ([obj isKindOfClass:[NSManagedObject class]]) {
            NSManagedObjectID *objectID = [obj objectID];
            id referenceObject = [self referenceObjectForObjectID:objectID];
            sqlite3_bind_int64(statement, ((int)idx + 1), [referenceObject unsignedLongLongValue]);
        }
        
        // date
        else if ([obj isKindOfClass:[NSDate class]]) {
            sqlite3_bind_double(statement, ((int)idx + 1), [obj timeIntervalSince1970]);
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
        BOOL foundPredicate = NO;
        NSEntityDescription *entity = [request entity];
        NSDictionary *properties = [entity propertiesByName];
        id property = [properties objectForKey:value];
        if ([property isKindOfClass:[NSRelationshipDescription class]]) {
            NSRelationshipDescription * desc = (NSRelationshipDescription*)property;
            if ([desc isToMany] && [[desc inverseRelationship] isToMany]) {
                NSArray *keys = [value componentsSeparatedByString:@"."];
                value = [NSString stringWithFormat:@"%@.%@",
                         [self joinedTableNameForComponents:keys forRelationship:NO],
                         @"__objectid"];
                    
            }
            else {
                value = [NSString stringWithFormat:@"%@.%@",
                         [self tableNameForEntity:entity],
                         [self foreignKeyColumnForRelationship:property]];
            }
        }
        else if (property != nil) {
            value = [NSString stringWithFormat:@"%@.%@",
                     [self tableNameForEntity:entity],
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
                NSString * destinationName = [self tableNameForEntity:rel.destinationEntity];
                NSString * entityTableName = [self tableNameForEntity:entity];
                value = [NSString stringWithFormat:@"(SELECT COUNT(*) FROM %@ [%@] WHERE [%@].%@ = %@.__objectid",
                         destinationName,
                         rel.name,
                         rel.name,
                         [self foreignKeyColumnForRelationship:rel.inverseRelationship],
                         entityTableName];
                if (rel.destinationEntity.superentity != nil) {
                    value = [value stringByAppendingString:
                             [NSString stringWithFormat:@" AND [%@].__entityType = %ld",
                              rel.name,
                              rel.destinationEntity.typeHash]];
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
                    [request setReturnsDistinctResults:YES];
                    lastComponentName = @"__objectID";
                }
                
                value = [NSString stringWithFormat:@"%@.%@",
                     [self joinedTableNameForComponents:[pathComponents subarrayWithRange:NSMakeRange(0, pathComponents.count -1)] forRelationship:NO], lastComponentName];
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
            *bindings = value;
            *operand = @"?";
        }
        else if ([value isKindOfClass:[NSArray class]]) {
            if (predicate.predicateOperatorType == NSBetweenPredicateOperatorType) {
                *bindings = value;
                *operand = [NSString stringWithFormat:[operator objectForKey:@"format"], @"?", @"?"];
            } else {
                NSUInteger count = [value count];
                NSArray *parameters = [NSArray cmdArrayWithObject:@"?" times:count];
                *bindings = value;
                *operand = [NSString stringWithFormat:
                            [operator objectForKey:@"format"],
                            [parameters componentsJoinedByString:@", "]];
            }
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
                *bindings = value;
            }
        }
        else if (!value || value == [NSNull null]) {
            *bindings = nil;
            *operand = @"NULL";
        }
        else {
            *bindings = value;
            *operand = @"?";
        }
    }
    
    // unsupported type
    else {
        NSLog(@"%s Unsupported expression type %lu", __PRETTY_FUNCTION__, (unsigned long)type);
    }
}

- (NSString *)foreignKeyColumnForRelationshipName:(NSString *)relationshipName {
    return [NSString stringWithFormat:@"%@__objectid", relationshipName];
}

- (NSString *)foreignKeyColumnForRelationship:(NSRelationshipDescription *)relationship {
    return [self foreignKeyColumnForRelationshipName:[relationship name]];
}

- (NSString *) joinedTableNameForComponents: (NSArray *) componentsArray forRelationship:(BOOL)forRelationship{
    assert(componentsArray.count > 0);
    NSString *tableName = [componentsArray componentsJoinedByString:@"."];
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
        id value = newValue ?: [self valueForPropertyDescription:key];
        if (value && ![value isEqual: [NSNull null]]) {
            [updateValues setObject:value forKey:key.name];
        }
    }
    [self updateWithValues:updateValues version:self.version+1];
}

@end

@implementation NSEntityDescription (CMDTypeHash)

-(long)typeHash
{
    long hash = (long)self.name.hash;
    return hash;
}

@end
