//
//  ISDPostListViewController.h
//  Incremental Store Demo
//
//  Created by Caleb Davenport on 7/31/12.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

@interface ISDPostListViewController : UITableViewController

@property (nonatomic, strong) NSManagedObject *user;

@end
