#import <SenTestingKit/SenTestingKit.h>
#import "EncryptedStore.h"

@interface ECDAccount : NSManagedObject

@property (nonatomic, retain) NSString *name;
@property (nonatomic, retain) NSSet *transactions;

@end

@implementation ECDAccount

@dynamic name;
@dynamic transactions;

@end

@interface ECDTransaction : NSManagedObject

@property (nonatomic, retain) NSDecimalNumber *amount;
@property (nonatomic, retain) NSDate *date;
@property (nonatomic, retain) ECDAccount *account;

@end

@implementation ECDTransaction

@dynamic amount;
@dynamic date;
@dynamic account;

@end

@interface ECDCoreDataStack : NSObject

@property (nonatomic, strong) NSManagedObjectModel *managedObjectModel;
@property (nonatomic, strong) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (nonatomic, strong) NSManagedObjectContext *mainContext;
@property (nonatomic, copy) NSString *storeType;

- (id)initWithManagedObjectModel:(NSManagedObjectModel *)managedObjectModel;

- (BOOL)openStoreAtURL:(NSURL *)storeURL
             storeType:(NSString *)storeType
               options:(NSDictionary *)options
                 error:(NSError * __autoreleasing *)error;

@end

@implementation ECDCoreDataStack

- (id)initWithManagedObjectModel:(NSManagedObjectModel *)managedObjectModel
{
    self = [super init];
    
    if (self)
    {
        self.managedObjectModel = managedObjectModel;
    }
    
    return self;
}

- (BOOL)openStoreAtURL:(NSURL *)storeURL
             storeType:(NSString *)storeType
               options:(NSDictionary *)options
                 error:(NSError * __autoreleasing *)error
{
    self.persistentStoreCoordinator =
    [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.managedObjectModel];
    
    NSPersistentStore *const persistentStore =
    [self.persistentStoreCoordinator addPersistentStoreWithType:storeType
                                                  configuration:nil
                                                            URL:storeURL
                                                        options:options
                                                          error:error];
    
    if (nil != persistentStore)
    {
        self.mainContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        self.mainContext.persistentStoreCoordinator = self.persistentStoreCoordinator;
        self.storeType = storeType;
    }
    
    return nil != persistentStore;
}

@end

@interface EncryptedCoreDataTests : SenTestCase

@property (nonatomic, strong) NSURL *storeURL;
@property (nonatomic, strong) NSURL *destinationURL;
@property (nonatomic, copy) NSDictionary *options;

@end

@implementation EncryptedCoreDataTests

- (NSManagedObjectModel *)newManagedObjectModel
{
    NSEntityDescription *const accountEntity = [NSEntityDescription new];
    accountEntity.name = @"Account";
    accountEntity.managedObjectClassName = NSStringFromClass([ECDAccount class]);
    
    NSEntityDescription *const transactionEntity = [NSEntityDescription new];
    transactionEntity.name = @"Transaction";
    transactionEntity.managedObjectClassName = NSStringFromClass([ECDTransaction class]);
    
    NSAttributeDescription *const accountNameDescription = [NSAttributeDescription new];
    accountNameDescription.name = @"name";
    accountNameDescription.attributeType = NSStringAttributeType;
    accountNameDescription.optional = YES;
    
    NSRelationshipDescription *const accountTransactionsDescription = [NSRelationshipDescription new];
    accountTransactionsDescription.name = @"transactions";
    accountTransactionsDescription.minCount = 0;
    accountTransactionsDescription.maxCount = NSUIntegerMax;
    accountTransactionsDescription.optional = YES;
    accountTransactionsDescription.destinationEntity = transactionEntity;
    
    accountEntity.properties = @[
                                 accountNameDescription,
                                 accountTransactionsDescription
                                 ];
    
    NSRelationshipDescription *const transactionAccountDescription = [NSRelationshipDescription new];
    transactionAccountDescription.name = @"account";
    transactionAccountDescription.minCount = 1;
    transactionAccountDescription.maxCount = 1;
    transactionAccountDescription.optional = NO;
    transactionAccountDescription.destinationEntity = accountEntity;
    
    NSAttributeDescription *const transactionAmountDescription = [NSAttributeDescription new];
    transactionAmountDescription.name = @"amount";
    transactionAmountDescription.optional = YES;
    transactionAmountDescription.attributeType = NSDecimalAttributeType;
    
    NSAttributeDescription *const transactionDateDescription = [NSAttributeDescription new];
    transactionDateDescription.name = @"date";
    transactionDateDescription.optional = YES;
    transactionDateDescription.attributeType = NSDateAttributeType;
    
    NSAttributeDescription *const transactionIndexDescription = [NSAttributeDescription new];
    transactionIndexDescription.name = @"index";
    transactionIndexDescription.optional = YES;
    transactionIndexDescription.attributeType = NSInteger64AttributeType;
    
    transactionEntity.properties = @[
                                     transactionAmountDescription,
                                     transactionDateDescription,
                                     transactionIndexDescription,
                                     transactionAccountDescription
                                     ];
    
    NSManagedObjectModel *const managedObjectModel = [NSManagedObjectModel new];
    managedObjectModel.entities = @[accountEntity, transactionEntity];
    
    return managedObjectModel;
}

- (ECDCoreDataStack *)newCoreDataStackUsingECD:(BOOL)useECD
{
    NSManagedObjectModel *const managedObjectModel = [self newManagedObjectModel];
    
    NSString *const storeType = useECD ? EncryptedStoreType : NSSQLiteStoreType;
    
    NSError * __autoreleasing error;
    ECDCoreDataStack *const coreDataStack = [[ECDCoreDataStack alloc] initWithManagedObjectModel:managedObjectModel];
    const BOOL opened = [coreDataStack openStoreAtURL:self.storeURL
                                            storeType:storeType
                                              options:self.options
                                                error:&error];
    STAssertTrue(opened, @"An unexpected error occurred: %@", error);
    
    return opened ? coreDataStack : nil;
}

- (void)removeSQLiteStoreAtPath:(NSString *)storePath
{
    NSFileManager *const fileManager = [NSFileManager defaultManager];
    
    if ([fileManager fileExistsAtPath:storePath])
    {
        NSError * __autoreleasing error;
        BOOL removed = [fileManager removeItemAtPath:storePath error:&error];
        STAssertTrue(removed, @"Failed to remove SQLite store at %@: %@", storePath, error.localizedDescription);
        
        NSString *const shmStorePath = [storePath stringByAppendingString:@"-shm"];
        NSString *const walStorePath = [storePath stringByAppendingString:@"-wal"];
        
        if ([fileManager fileExistsAtPath:shmStorePath])
        {
            error = nil;
            removed = [fileManager removeItemAtPath:shmStorePath error:&error];
            STAssertTrue(removed, @"Failed to remove SQLite SHM file at %@: %@", shmStorePath,
                         error.localizedDescription);
        }
        
        if ([fileManager fileExistsAtPath:walStorePath])
        {
            error = nil;
            [fileManager removeItemAtPath:walStorePath error:&error];
            STAssertTrue(removed, @"Failed to remove SQLite write-ahead log file at %@: %@", walStorePath,
                         error.localizedDescription);
        }
    }
}

- (void)setUp
{
    [super setUp];
    
    NSFileManager *const fileManager = [[NSFileManager alloc] init];
    NSURL *const documentsURL =
    [[fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    
    NSString *const documentsPath = documentsURL.path;
    BOOL isDirectory = NO;
    BOOL exists = [fileManager fileExistsAtPath:documentsPath isDirectory:&isDirectory];
    
    if (! exists)
    {
        NSError * __autoreleasing error;
        exists = [fileManager createDirectoryAtPath:documentsPath
                        withIntermediateDirectories:YES
                                         attributes:nil
                                              error:&error];
        STAssertTrue(exists, @"Failed to create %@: %@", documentsPath, error.localizedDescription);
    }
    
    NSString *const storeName = [NSString stringWithFormat:@"%@_%@", NSStringFromClass([self class]), self.name];
    self.storeURL = [documentsURL URLByAppendingPathComponent:storeName];
    self.destinationURL = [documentsURL URLByAppendingPathComponent:[storeName stringByAppendingString:@"_new"]];
    self.options = @{ EncryptedStorePassphraseKey : self.name };
}

- (void)tearDown
{
    [self removeSQLiteStoreAtPath:self.storeURL.path];
    [self removeSQLiteStoreAtPath:self.destinationURL.path];
    
    [super tearDown];
}

- (void)testFetchObjectWithTemporaryID
{
    ECDCoreDataStack *const coreDataStack = [self newCoreDataStackUsingECD:YES];
    NSManagedObjectModel *const managedObjectModel = coreDataStack.managedObjectModel;
    
    NSEntityDescription *const accountEntity = managedObjectModel.entitiesByName[@"Account"];
    NSEntityDescription *const transactionEntity = managedObjectModel.entitiesByName[@"Transaction"];
    
    NSManagedObjectContext *const mainContext = coreDataStack.mainContext;
    
    ECDAccount *const account0 = [[ECDAccount alloc] initWithEntity:accountEntity
                                     insertIntoManagedObjectContext:mainContext];
    
    ECDTransaction *const transaction0 = [[ECDTransaction alloc] initWithEntity:transactionEntity
                                                 insertIntoManagedObjectContext:mainContext];
    transaction0.account = account0;
    
    NSFetchRequest *const fetchRequest = [NSFetchRequest fetchRequestWithEntityName:transactionEntity.name];
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"account == %@", account0];
    
    NSError * __autoreleasing error = nil;
    NSArray *const objects = [mainContext executeFetchRequest:fetchRequest error:&error];
    STAssertNil(error, @"An unexpected error occurred: %@", error);
    STAssertEquals(objects.count, 1u, @"Expected to fetch 1 %@ entity", fetchRequest.entityName);
}

- (void)testMigration
{
    ECDCoreDataStack *const coreDataStack = [self newCoreDataStackUsingECD:YES];
    NSManagedObjectModel *const oldManagedObjectModel = coreDataStack.managedObjectModel;
    NSError * __autoreleasing error;
    
    {
        NSEntityDescription *const accountEntity = oldManagedObjectModel.entitiesByName[@"Account"];
        NSEntityDescription *const transactionEntity = oldManagedObjectModel.entitiesByName[@"Transaction"];
        
        NSManagedObjectContext *const mainContext = coreDataStack.mainContext;
        
        ECDAccount *const account0 = [[ECDAccount alloc] initWithEntity:accountEntity
                                         insertIntoManagedObjectContext:mainContext];
        account0.name = @"Test Account";
        
        ECDTransaction *const transaction0 = [[ECDTransaction alloc] initWithEntity:transactionEntity
                                                     insertIntoManagedObjectContext:mainContext];
        transaction0.date = [NSDate date];
        transaction0.account = account0;
        
        const BOOL saved = [mainContext save:&error];
        STAssertTrue(saved, @"Failed to save context: %@", error);
    }
    
    NSManagedObjectModel *const newManagedObjectModel = [oldManagedObjectModel copy];
    
    NSAttributeDescription *const transactionStatusDescription = [NSAttributeDescription new];
    transactionStatusDescription.name = @"status";
    transactionStatusDescription.attributeType = NSInteger16AttributeType;
    transactionStatusDescription.optional = YES;
    
    NSEntityDescription *const transactionDescription = newManagedObjectModel.entitiesByName[@"Transaction"];
    NSArray *const transactionProperties =
    [transactionDescription.properties arrayByAddingObject:transactionStatusDescription];
    transactionDescription.properties = transactionProperties;
    
    error = nil;
    NSMappingModel *const mappingModel = [NSMappingModel inferredMappingModelForSourceModel:oldManagedObjectModel
                                                                           destinationModel:newManagedObjectModel
                                                                                      error:&error];
    STAssertNotNil(mappingModel, @"Failed to create inferred mapping model: %@", error);
    
    NSMigrationManager *const migrationManager = [[NSMigrationManager alloc] initWithSourceModel:oldManagedObjectModel
                                                                                destinationModel:newManagedObjectModel];
    
    error = nil;
    const BOOL migrated = [migrationManager migrateStoreFromURL:self.storeURL
                                                           type:coreDataStack.storeType
                                                        options:self.options
                                               withMappingModel:mappingModel
                                               toDestinationURL:self.destinationURL
                                                destinationType:coreDataStack.storeType
                                             destinationOptions:self.options
                                                          error:&error];
    STAssertTrue(migrated, @"Failed to migrate to the new managed object model: %@", error);
}

@end