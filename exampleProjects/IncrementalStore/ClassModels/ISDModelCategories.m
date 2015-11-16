//
//  ISDModelCategories.m
//  Incremental Store
//
//  Created by Richard Hodgkins on 31/08/2014.
//  Copyright (c) 2014 Caleb Davenport. All rights reserved.
//

#import "ISDModelCategories.h"

#import "ISDRoot.h"
#import "ISDParent.h"
#import "ISDChildA.h"
#import "ISDChildB.h"

@implementation NSManagedObject (ISDHelper)

+(NSString *)entityName
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Override in subclasses" userInfo:nil];
}

+(instancetype)insertInManagedObjectContext:(NSManagedObjectContext *)context
{
    return [NSEntityDescription insertNewObjectForEntityForName:[self entityName] inManagedObjectContext:context];
}

+(NSFetchRequest *)fetchRequest
{
    return [NSFetchRequest fetchRequestWithEntityName:[self entityName]];
}

@end

@implementation ISDRoot (ISDHelper)

+(NSString *)entityName
{
    return @"Root";
}

@end

@implementation ISDChildA (ISDHelper)

+(NSString *)entityName
{
    return @"ChildA";
}

@end

@implementation ISDChildB (ISDHelper)

+(NSString *)entityName
{
    return @"ChildB";
}

@end
