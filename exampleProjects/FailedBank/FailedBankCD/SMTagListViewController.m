//
//  SMTagListViewController.m
//  FailedBankCD
//
//  Created by cesarerocchi on 5/24/12.
//  Copyright (c) 2012 Adam Burkepile. All rights reserved.
//

#import "SMTagListViewController.h"

@interface SMTagListViewController ()

@end

@implementation SMTagListViewController

@synthesize bankDetails = _bankDetails;
@synthesize pickedTags;
@synthesize fetchedResultsController = _fetchedResultsController;


- (id) initWithBankDetails:(FailedBankDetails *) details {

    if (self = [super init]) {
    
        _bankDetails = details;
        
    }
    
    return self;
    
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.pickedTags = [[NSMutableSet alloc] init];
    
    // Retrieve all tags
    NSError *error;    
    if (![self.fetchedResultsController performFetch:&error]) {
	    NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
	    abort();
	}
    
    // Each tag attached to the details is included in the array
    NSSet *tags = self.bankDetails.tags;
    
    for (Tag *tag in tags) {    
        
        [pickedTags addObject:tag];   
        
    } 
    
    // setting up add button
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addTag)];
}

- (void) viewWillDisappear:(BOOL)animated {
    
    [super viewWillDisappear:animated]; 
    self.bankDetails.tags = pickedTags;
    
    NSError *error = nil;
    if (![self.bankDetails.managedObjectContext save:&error]) {        
        NSLog(@"Core data error %@, %@", error, [error userInfo]);
        abort();
    }         
}

#pragma mark - Actions 

- (void) addTag {

    UIAlertView *newTagAlert = [[UIAlertView alloc] initWithTitle:@"New tag" message:@"Insert new tag name" delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Save", nil];
    
    newTagAlert.alertViewStyle = UIAlertViewStylePlainTextInput;
    
    [newTagAlert show];
    
}


#pragma mark - Alert view delegate 


- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {

    if (buttonIndex == 0) {
    
        NSLog(@"cancel");
        
    } else {
    
        
        NSString *tagName = [[alertView textFieldAtIndex:0] text];
        
        Tag *tag = [NSEntityDescription insertNewObjectForEntityForName:@"Tag"
                                                 inManagedObjectContext:self.bankDetails.managedObjectContext];
        tag.name = tagName;
        
        NSError *error = nil;
        if (![tag.managedObjectContext save:&error]) {        
            NSLog(@"Core data error %@, %@", error, [error userInfo]);
            abort();
        } 
        
        [self.fetchedResultsController performFetch:&error];
        
        [self.tableView reloadData];
    }
    
}


#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    id <NSFetchedResultsSectionInfo> sectionInfo = [[self.fetchedResultsController sections] objectAtIndex:section];
    return [sectionInfo numberOfObjects];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"TagCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    
    if (cell == nil) {
        cell = [[UITableViewCell alloc] 
                initWithStyle:UITableViewCellStyleDefault 
                reuseIdentifier:CellIdentifier];
    }    
    cell.accessoryType = UITableViewCellAccessoryNone;
    
    Tag *tag = (Tag *)[self.fetchedResultsController objectAtIndexPath:indexPath];
    if ([pickedTags containsObject:tag]) {        
        cell.accessoryType = UITableViewCellAccessoryCheckmark;        
    }
    
    cell.textLabel.text = tag.name;    
    return cell; 
    
    return cell;
}

/*
// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the specified item to be editable.
    return YES;
}
*/

/*
// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the row from the data source
        [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }   
    else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }   
}
*/



#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    
    Tag *tag = (Tag *)[self.fetchedResultsController objectAtIndexPath:indexPath];
    UITableViewCell * cell = [self.tableView  cellForRowAtIndexPath:indexPath];
    [cell setSelected:NO animated:YES];                    
    
    if ([pickedTags containsObject:tag]) { 
        
        [pickedTags removeObject:tag];
        cell.accessoryType = UITableViewCellAccessoryNone;   
        
    } else {    
        
        [pickedTags addObject:tag];
        cell.accessoryType = UITableViewCellAccessoryCheckmark;     
        
    }    
}

#pragma mark - Result controller

- (NSFetchedResultsController *)fetchedResultsController
{
    if (_fetchedResultsController != nil) {
        return _fetchedResultsController;
    }        
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];    
    
    NSEntityDescription *entity = [NSEntityDescription 
                                   entityForName:@"Tag" 
                                   inManagedObjectContext:self.bankDetails.managedObjectContext];    
    [fetchRequest setEntity:entity];
    
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] 
                                        initWithKey:@"name" 
                                        ascending:NO];
    NSArray *sortDescriptors = [NSArray arrayWithObjects:sortDescriptor, nil];    
    [fetchRequest setSortDescriptors:sortDescriptors];
    
    NSFetchedResultsController *aFetchedResultsController = [[NSFetchedResultsController alloc]  initWithFetchRequest:fetchRequest 
                                                                                                 managedObjectContext:self.bankDetails.managedObjectContext      
                                                                                                   sectionNameKeyPath:nil 
                                                                                                            cacheName:nil];
    
    self.fetchedResultsController = aFetchedResultsController;
    
	NSError *error = nil;
    if (![self.fetchedResultsController performFetch:&error]) {
	    NSLog(@"Core data error %@, %@", error, [error userInfo]);
	    abort();
	}    
    
    return _fetchedResultsController;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}


@end
