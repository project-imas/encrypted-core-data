//
//  ConcurrencyTests.m
//  Incremental Store
//
//  Created by Nacho on 5/7/16.
//  Copyright © 2016 Caleb Davenport. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "SingleDefaultStoreManager.h"
#import "SingleEncryptedStoreManager.h"
#import "DoubleEncryptedStoreManager.h"
#import "ISDChildA.h"
#import "ISDRoot.h"

#pragma mark - Helper Categories

@interface NSManagedObject (IDHelper)
+ (instancetype)findFirstByAttribute:(NSString *)attribute withValue:(id)value inContext:(NSManagedObjectContext *)context;
+ (instancetype)insert:(NSManagedObjectContext *)context;
+ (NSArray *)allObjectsInContext:(NSManagedObjectContext *)context;
@end
@implementation NSManagedObject (IDHelper)
+ (instancetype)findFirstByAttribute:(NSString *)attribute withValue:(id)value inContext:(NSManagedObjectContext *)context
{
  NSPredicate *searchByAttValue = [NSPredicate predicateWithFormat:@"%K = %@", attribute, value];
  NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:[self entityName]];
  fetchRequest.predicate = searchByAttValue;
  fetchRequest.fetchLimit = 1;
  NSArray *result = [context executeFetchRequest:fetchRequest error:nil];
  return [result firstObject];
}

+ (instancetype)insert:(NSManagedObjectContext *)context
{
  return [[NSManagedObject alloc] initWithEntity:[self entityDescriptor:context] insertIntoManagedObjectContext:context];
}

+ (NSArray *)allObjectsInContext:(NSManagedObjectContext *)context
{
  NSFetchRequest * fetchRequest = [NSFetchRequest fetchRequestWithEntityName:[self entityName]];
  return [context executeFetchRequest:fetchRequest error:nil];
}

#pragma mark Private methods

+ (NSString *)entityName
{
  return [NSStringFromClass(self) stringByReplacingOccurrencesOfString:@"ISD" withString:@""];
}

+ (NSEntityDescription *)entityDescriptor:(NSManagedObjectContext *)context
{
  return [NSEntityDescription entityForName:[self entityName] inManagedObjectContext:context];
}
@end

@interface ISDChildA (IDHelper)
+ (instancetype)createOrUpdateWithAttributeA:(NSString *)attributeA inContext:(NSManagedObjectContext *)context;
@end
@implementation ISDChildA (IDHelper)
+ (instancetype)createOrUpdateWithAttributeA:(NSString *)attributeA inContext:(NSManagedObjectContext *)context
{
  ISDChildA *result = [ISDChildA findFirstByAttribute:@"attributeA" withValue:attributeA inContext:context];
  if (!result){
    result = [ISDChildA insert:context];
  }
  result.attributeA = [attributeA copy];
  return result;
}
@end

@interface ISDRoot (IDHelper)
+ (instancetype)createOrUpdateWithName:(NSString *)name manyToMany:(NSSet *)manyToMany inContext:(NSManagedObjectContext *)context;
@end
@implementation ISDRoot (IDHelper)
+ (instancetype)createOrUpdateWithName:(NSString *)name manyToMany:(NSSet *)manyToMany inContext:(NSManagedObjectContext *)context
{
  ISDRoot *result = [ISDRoot findFirstByAttribute:@"name" withValue:name inContext:context];
  if (!result){
    result = [ISDRoot insert:context];
  }
  result.name = [name copy];
  result.manyToMany = [manyToMany copy];
  return result;
}
@end

#pragma mark - Tests

@interface ConcurrencyTests : XCTestCase
@end

@implementation ConcurrencyTests {
  id<PersistenceManagerDelegate> persistenceManager;
  NSTimer *timer;
  NSFetchedResultsController *fetchedResultsController;
}

- (void)setUp
{
  [super setUp];
  [SingleDefaultStoreManager deleteDatabase];
  [SingleEncryptedStoreManager deleteDatabase];
  persistenceManager = nil;
}

- (void)tearDown
{
  persistenceManager = nil;
  [timer invalidate];
  timer = nil;
  [super tearDown];
}

- (void)testConcurrentInsertOperationsOnDefaultStore
{
  persistenceManager = [SingleDefaultStoreManager new];
  [self doTestConcurrentInsertOperations];
}

- (void)testConcurrentUpdateOperationsOnDefaultStore
{
  persistenceManager = [SingleDefaultStoreManager new];
  [self doTestConcurrentUpdateOperations];
}

- (void)testConcurrentInsertOperationsOnDoubleEncryptedStore
{
  persistenceManager = [DoubleEncryptedStoreManager new];
  [self doTestConcurrentInsertOperations];
}

- (void)testConcurrentUpdateOperationsOnDoubleEncryptedStore
{
  persistenceManager = [DoubleEncryptedStoreManager new];
  [self doTestConcurrentUpdateOperations];
}

- (void)testConcurrentInsertOperationsOnEncryptedStore
{
  persistenceManager = [SingleEncryptedStoreManager new];
  [self doTestConcurrentInsertOperations];
}

- (void)testConcurrentUpdateOperationsOnEncryptedStore
{
  persistenceManager = [SingleEncryptedStoreManager new];
  [self doTestConcurrentUpdateOperations];
}

#pragma mark - Helper methods

- (void)createOrUpdateChildAObjectsInContext:(NSManagedObjectContext *)context sync:(BOOL)sync expectation:(XCTestExpectation *)expectation
{
  void (^createOrUpdateChildAObjects)() = ^(){
    for (NSInteger count = 0; count < 20; ++count){
      [ISDChildA createOrUpdateWithAttributeA:[NSString stringWithFormat:@"ChildA %ld", (long)count+1] inContext:context];
    }
    [persistenceManager saveContext:context];
    if (expectation){
      [expectation fulfill];
    }
  };
  if (sync){
    [context performBlockAndWait:^{
      createOrUpdateChildAObjects();
    }];
  }else{
    [context performBlock:^{
      createOrUpdateChildAObjects();
    }];
  }
}

- (void)createOrUpdateRootObjectsInContext:(NSManagedObjectContext *)context sync:(BOOL)sync expectation:(XCTestExpectation *)expectation
{
  void (^createOrUpdateRootObjects)() = ^(){
    NSDate *initDate = [NSDate date];
    NSArray *allChildA = [ISDChildA allObjectsInContext:context];
    for (NSInteger count = 0; count < 500; ++count){
      // Randomly assign 0-3 ChildA objects to the Root object
      NSInteger numChildsToAssign = arc4random_uniform(4);
      NSMutableArray *childs = [@[] mutableCopy];
      for (NSInteger i = 0; i < numChildsToAssign; ++i){
        [childs addObject:((ISDChildA *)allChildA[arc4random_uniform((uint)allChildA.count)]).attributeA];
      }
      [ISDRoot createOrUpdateWithName:[NSString stringWithFormat:@"Root %ld", (long) count]
                                manyToMany:[NSSet setWithArray:[allChildA filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"attributeA IN %@", childs]]]
                            inContext:context];
      if (count%100 == 0){
        [persistenceManager saveContext:context];
      }
    }
    [persistenceManager saveContext:context];
    NSTimeInterval elapsedTime = [[NSDate date] timeIntervalSinceDate:initDate];
    NSLog(@"Time required to insert|update Root objects: %fs", elapsedTime);
    if (expectation){
      [expectation fulfill];
    }
  };
  if (sync){
    [context performBlockAndWait:^{
      createOrUpdateRootObjects();
    }];
  }else{
    [context performBlock:^{
      createOrUpdateRootObjects();
    }];
  }
}

- (void)initializeFetchedResultsControllerInContext:(NSManagedObjectContext *)context
{
  NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Root"];
  NSSortDescriptor *nameSort = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES];
  [request setSortDescriptors:@[nameSort]];
  
  fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:request managedObjectContext:context sectionNameKeyPath:@"name" cacheName:nil];
  
  timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(doFetch) userInfo:nil repeats:YES];
}

- (void)doFetch
{
  NSError *error = nil;
  BOOL result = [fetchedResultsController performFetch:&error];
  XCTAssert(result, @"Error fetching results\n%@, %@", error, error.userInfo);
}

- (void)doTestConcurrentInsertOperations
{
  // Check Core Data stack model is empty
  NSUInteger rootObjects = [ISDRoot allObjectsInContext:persistenceManager.mainContext].count;
  XCTAssert(rootObjects == 0, @"There shouldn't be any Root objects, but there are %ld", rootObjects);
  NSUInteger childAObjects = [ISDChildA allObjectsInContext:persistenceManager.mainContext].count;
  XCTAssert(childAObjects == 0, @"There shouldn't be any ChildA objects, but there are %ld", childAObjects);
  
  // Initialize fetched results controller
  [self initializeFetchedResultsControllerInContext:persistenceManager.mainContext];
  
  // Create ChildA objects
  [self createOrUpdateChildAObjectsInContext:persistenceManager.mainContext sync:YES expectation:nil];
  [persistenceManager.privateContext reset];
  XCTAssert([ISDChildA allObjectsInContext:persistenceManager.mainContext].count == 20, @"There shouldn be 20 ChildA objects reachable from main context");
  
  // Create Root objects
  XCTestExpectation *expectation = [self expectationWithDescription:@"Create or Update Root objects finishes"];
  [self createOrUpdateRootObjectsInContext:persistenceManager.privateContext sync:NO expectation:expectation];
  [self waitForExpectationsWithTimeout:10.0 handler:^(NSError *error) {
    XCTAssert(!error, @"Expectation returned with error - %@", error);
  }];
}

- (void)doTestConcurrentUpdateOperations
{
  // Check Core Data stack model is empty
  NSUInteger rootObjects = [ISDRoot allObjectsInContext:persistenceManager.mainContext].count;
  XCTAssert(rootObjects == 0, @"There shouldn't be any Root objects, but there are %ld", rootObjects);
  NSUInteger childAObjects = [ISDChildA allObjectsInContext:persistenceManager.mainContext].count;
  XCTAssert(childAObjects == 0, @"There shouldn't be any ChildA objects, but there are %ld", childAObjects);
  
  // Create ChildA objects
  [self createOrUpdateChildAObjectsInContext:persistenceManager.mainContext sync:YES expectation:nil];
  [persistenceManager.privateContext reset];
  XCTAssert([ISDChildA allObjectsInContext:persistenceManager.mainContext].count == 20, @"There shouldn be 20 ChildA objects reachable from main context");
  
  // Create Root objects
  [self createOrUpdateRootObjectsInContext:persistenceManager.mainContext sync:YES expectation:nil];
  [persistenceManager.privateContext reset];
  XCTAssert([ISDRoot allObjectsInContext:persistenceManager.mainContext].count == 500, @"There shouldn be 500 Root objects reachable from main context");
  
  // Initialize fetched results controller
  [self initializeFetchedResultsControllerInContext:persistenceManager.mainContext];
  
  // Update Root objects
  XCTestExpectation *expectation = [self expectationWithDescription:@"Create or Update Root objects finishes"];
  [self createOrUpdateRootObjectsInContext:persistenceManager.privateContext sync:NO expectation:expectation];
  [self waitForExpectationsWithTimeout:10.0 handler:^(NSError *error) {
    XCTAssert(!error, @"Expectation returned with error - %@", error);
    [self doFetch];
    XCTAssert(fetchedResultsController.fetchedObjects.count == 500, @"There should be 500 Root objects after finishing processing updates, but there are %ld", fetchedResultsController.fetchedObjects.count);
  }];
}

@end
