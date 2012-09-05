//
//  ISDAppDelegate.h
//  Incremental Store Demo
//
//  Created by Caleb Davenport on 8/29/12.
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
