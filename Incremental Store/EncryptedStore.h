//  Copyright (c) 2012 The MITRE Corporation.


#import <CoreData/CoreData.h>

extern NSString * const EncryptedStoreType;
extern NSString * const EncryptedStorePassphraseKey;
extern NSString * const EncryptedStoreErrorDomain;
extern NSString * const EncryptedStoreErrorMessageKey;

@interface EncryptedStore : NSIncrementalStore


+ (NSPersistentStoreCoordinator *)makeStoreWithDatabaseURL:(NSURL *)databaseURL managedObjectModel:(NSManagedObjectModel *)objModel:(NSString*)passcode;
+ (NSPersistentStoreCoordinator *)makeStore:(NSManagedObjectModel *) objModel
                                           :(NSString *) passcode;

@end
