//
//  SMSearchViewControllerViewController.m
//  FailedBankCD
//
//  Created by cesarerocchi on 5/22/12.
//  Copyright (c) 2012 Adam Burkepile. All rights reserved.
//

#import "SMSearchViewControllerViewController.h"



@interface SMSearchViewControllerViewController ()
- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath;
@end

@implementation SMSearchViewControllerViewController

@synthesize managedObjectContext;
@synthesize fetchedResultsController = _fetchedResultsController;
@synthesize searchBar,tView;
@synthesize noResultsLabel;

- (IBAction)closeSearch {

    [self dismissModalViewControllerAnimated:YES];
    
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.searchBar.delegate = self;
    self.tView.delegate = self;
    self.tView.dataSource = self;
    
    noResultsLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 90, 200, 30)];
    [self.view addSubview:noResultsLabel];
    noResultsLabel.text = @"No Results";
    [noResultsLabel setHidden:YES];

}

- (void) viewWillAppear:(BOOL)animated {

    [super viewWillAppear:animated];
    [self.searchBar becomeFirstResponder];
    
}

#pragma mark - Search bar delegate

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {

    NSError *error;
    
	if (![[self fetchedResultsController] performFetch:&error]) {
        
		NSLog(@"Error in search %@, %@", error, [error userInfo]);
        
	} else {
    
        [self.tView reloadData];
        [self.searchBar resignFirstResponder];
        
        [noResultsLabel setHidden:_fetchedResultsController.fetchedObjects.count > 0];
        
    }
    
}


#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    id  sectionInfo =
    [[_fetchedResultsController sections] objectAtIndex:section];
    return [sectionInfo numberOfObjects];
    
}

- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    FailedBankInfo *info = [_fetchedResultsController objectAtIndexPath:indexPath];
    cell.textLabel.text = info.name;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@, %@",
                                 info.city, info.state];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
    }
    
    [self configureCell:cell atIndexPath:indexPath];
    
    return cell;
}


#pragma mark - fetchedResultsController

// Change this value to experiment with different predicates
#define SEARCH_TYPE 0 


- (NSFetchedResultsController *)fetchedResultsController {
    
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription
                                   entityForName:@"FailedBankInfo" inManagedObjectContext:managedObjectContext];
    [fetchRequest setEntity:entity];
    
    NSSortDescriptor *sort = [[NSSortDescriptor alloc]
                              initWithKey:@"details.closeDate" ascending:NO];
    [fetchRequest setSortDescriptors:[NSArray arrayWithObject:sort]];
    [fetchRequest setFetchBatchSize:20];
    
    NSArray *queryArray;
    
    if ([self.searchBar.text rangeOfString:@":"].location != NSNotFound) {
    
        queryArray = [self.searchBar.text componentsSeparatedByString:@":"];
        
    }
    
    NSLog(@"search is %@", self.searchBar.text);
    
    NSPredicate *pred;
    
    switch (SEARCH_TYPE) {
            
        case 0: // name contains, case sensitive
            pred = [NSPredicate predicateWithFormat:@"name CONTAINS %@", self.searchBar.text];
            break;
            
        case 1: // name contains, case insensitive
            pred = [NSPredicate predicateWithFormat:@"name CONTAINS[c] %@", self.searchBar.text];
            break;
            
        case 2: // name is exactly the same
            pred = [NSPredicate predicateWithFormat:@"name == %@", self.searchBar.text];
            break;
            
        case 3: { // name begins with
            pred = [NSPredicate predicateWithFormat:@"name BEGINSWITH[c] %@", self.searchBar.text];
            break;
        }
            
        case 4: { // name matches with, e.g. .*nk
            pred = [NSPredicate predicateWithFormat:@"name MATCHES %@", self.searchBar.text];
            break;
        }
            
        case 5: { // zip ends with
                        
            pred = [NSPredicate predicateWithFormat: @"details.zip ENDSWITH %@", self.searchBar.text];            
            break;
        }
            
        case 6: { // date is greater than, e.g 2011-12-14
            
            NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
            [dateFormatter setDateFormat:@"yyyy-MM-dd"];
            NSDate *date = [dateFormatter dateFromString:self.searchBar.text];
                        
            pred = [NSPredicate predicateWithFormat: @"details.closeDate > %@", date];
            
            break;
        }
            
        case 7: { // has at least a tag
            
            pred = [NSPredicate predicateWithFormat: @"details.tags.@count > 0"];
            
            break;
        }
            
            
        case 8: // string contains (case insensitive) X and zip is exactly equal to Y. e.g. bank:ville
            pred = [NSPredicate predicateWithFormat:@"(name CONTAINS[c] %@) AND (city CONTAINS[c] %@)", [queryArray objectAtIndex:0], [queryArray objectAtIndex:1]
                    ];
            break;
            
        case 9: // name contains X and zip is exactly equal to Y, e.g. bank:123
            pred = [NSPredicate predicateWithFormat:@"(name CONTAINS[c] %@) AND (details.zip == %i)", [queryArray objectAtIndex:0], 
                    [[queryArray objectAtIndex:1] intValue]
                    ];
            break;
            
       
            
        case 10: // name contains X and tag name is exactly equal to Y, e.g. bank:tag1
            pred = [NSPredicate predicateWithFormat:@"(name CONTAINS[c] %@) AND (details.tags == %i)", [queryArray objectAtIndex:0], 
                    [[queryArray objectAtIndex:1] intValue]
                    ];
            break;
            
        case 11: { // has a tag whose name contains
            
            pred = [NSPredicate predicateWithFormat: @"ANY details.tags.name contains[c] %@", self.searchBar.text];
            break;
        }
            
        default:
            break;
    }
    
    [fetchRequest setPredicate:pred];
    
    NSFetchedResultsController *theFetchedResultsController =
    [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
                                        managedObjectContext:managedObjectContext sectionNameKeyPath:nil
                                                   cacheName:nil]; // better to not use cache
    self.fetchedResultsController = theFetchedResultsController;
    _fetchedResultsController.delegate = self;
    
    return _fetchedResultsController;
    
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

@end
