//
//  SMTagListViewController.h
//  FailedBankCD
//
//  Created by cesarerocchi on 5/24/12.
//  Copyright (c) 2012 Adam Burkepile. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FailedBankDetails.h"
#import "Tag.h"

@interface SMTagListViewController : UITableViewController <UIAlertViewDelegate>

@property (nonatomic, strong) FailedBankDetails *bankDetails;
@property (nonatomic, strong) NSMutableSet *pickedTags;
@property (nonatomic, strong) NSFetchedResultsController *fetchedResultsController;


- (id) initWithBankDetails:(FailedBankDetails *) details;


@end
