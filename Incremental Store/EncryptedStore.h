//  Copyright (c) 2012 The MITRE Corporation.


#import <CoreData/CoreData.h>

extern NSString * const EncryptedStoreType;
extern NSString * const EncryptedStorePassphraseKey;
extern NSString * const EncryptedStoreErrorDomain;
extern NSString * const EncryptedStoreErrorMessageKey;

@interface EncryptedStore : NSIncrementalStore
+ (NSPersistentStoreCoordinator *)makeStore:(NSManagedObjectModel *) objModel
                                           :(NSString *) passcode;

@end
