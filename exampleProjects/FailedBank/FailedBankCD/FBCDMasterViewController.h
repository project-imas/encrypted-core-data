//
//  FBCDMasterViewController.h
//  FailedBankCD
//
//  Created by Adam Burkepile on 3/23/12.
//  Copyright (c) 2012 Adam Burkepile. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SMSearchViewControllerViewController.h"
#import "Tag.h"
#import "SMBankDetailViewController.h"

@interface FBCDMasterViewController : UITableViewController <NSFetchedResultsControllerDelegate>

@property (nonatomic,strong) NSManagedObjectContext* managedObjectContext;
@property (nonatomic, retain) NSFetchedResultsController *fetchedResultsController;
@end
