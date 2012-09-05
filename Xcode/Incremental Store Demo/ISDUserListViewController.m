//
//  ISDUserListViewController.m
//  Incremental Store Demo
//
//  Created by Caleb Davenport on 7/31/12.
//

#import <CoreData/CoreData.h>

#import "ISDUserListViewController.h"
#import "ISDPostListViewController.h"

#import "ISDAppDelegate.h"

@implementation ISDUserListViewController {
    NSArray *users;
    NSNumberFormatter *formatter;
}

- (id)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [[NSNotificationCenter defaultCenter]
         addObserver:self
         selector:@selector(managedObjectContextDidSave)
         name:NSManagedObjectContextDidSaveNotification
         object:[ISDAppDelegate managedObjectContext]];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)managedObjectContextDidSave {
    [self reloadData];
    [self.tableView reloadData];
}

- (void)reloadData {
    if ([self isViewLoaded]) {
        NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"User"];
        [request setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ]];
        NSManagedObjectContext *context = [ISDAppDelegate managedObjectContext];
        users = [context executeFetchRequest:request error:nil];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self reloadData];
    formatter = [[NSNumberFormatter alloc] init];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return (orientation == UIInterfaceOrientationPortrait);
}

- (void)didReceiveMemoryWarning {
    if ([self isViewLoaded] && !self.view.window) {
        users = nil;
        formatter = nil;
    }
    [super didReceiveMemoryWarning];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [users count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    NSManagedObject *object = [users objectAtIndex:indexPath.row];
    cell.textLabel.text = [object valueForKey:@"name"];
    NSUInteger count = [[object valueForKey:@"posts"] count];
    NSNumber *number = [NSNumber numberWithUnsignedInteger:count];
    cell.detailTextLabel.text = [formatter stringFromNumber:number];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSManagedObject *object = [users objectAtIndex:indexPath.row];
    ISDPostListViewController *posts = [self.storyboard instantiateViewControllerWithIdentifier:@"PostsViewController"];
    posts.user = object;
    [self.navigationController pushViewController:posts animated:YES];
}

@end
