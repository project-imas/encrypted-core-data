//
//  SMSearchViewControllerViewController.h
//  FailedBankCD
//
//  Created by cesarerocchi on 5/22/12.
//  Copyright (c) 2012 Adam Burkepile. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FailedBankInfo.h"

@interface SMSearchViewControllerViewController : UIViewController<UITableViewDelegate, UITableViewDataSource,NSFetchedResultsControllerDelegate, UISearchBarDelegate>

@property (nonatomic,strong) NSManagedObjectContext* managedObjectContext;
@property (nonatomic,retain) NSFetchedResultsController *fetchedResultsController;

@property (nonatomic, strong) IBOutlet UISearchBar *searchBar;
@property (nonatomic, strong) IBOutlet UITableView *tView;

@property (nonatomic, strong) UILabel *noResultsLabel;

- (IBAction)closeSearch;

@end
