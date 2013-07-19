#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class FailedBankDetails;

@interface Tag : NSManagedObject

@property (nonatomic, retain) NSString * name;
@property (nonatomic, retain) NSSet *detail;
@end

@interface Tag (CoreDataGeneratedAccessors)

- (void)addDetailObject:(FailedBankDetails *)value;
- (void)removeDetailObject:(FailedBankDetails *)value;
- (void)addDetail:(NSSet *)values;
- (void)removeDetail:(NSSet *)values;

@end
