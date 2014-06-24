//
//  ISDAppDelegate.h
//  Incremental Store Demo
//
// Copyright 2012 - 2014 The MITRE Corporation, All Rights Reserved.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

@interface ISDAppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

/*
 
 A shared application context created with the main queue concurrency type.
 
 */
+ (NSManagedObjectContext *)managedObjectContext;

@end
