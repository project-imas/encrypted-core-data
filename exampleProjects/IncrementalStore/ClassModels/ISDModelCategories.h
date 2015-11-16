//
//  ISDModelCategories.h
//  Incremental Store
//
//  Created by Richard Hodgkins on 31/08/2014.
//  Copyright (c) 2014 Caleb Davenport. All rights reserved.
//

#import <CoreData/CoreData.h>

@interface NSManagedObject (ISDHelper)

+(NSString *)entityName;

+(instancetype)insertInManagedObjectContext:(NSManagedObjectContext *)context;

+(NSFetchRequest *)fetchRequest;

@end
