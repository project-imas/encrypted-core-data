//
//  ISDPostListViewController.m
//  Incremental Store Demo
//
// Copyright 2012 - 2014 The MITRE Corporation, All Rights Reserved.
//

#import "ISDPostListViewController.h"
#import "ISDEditPostViewController.h"

#import "ISDAppDelegate.h"

@implementation ISDPostListViewController {
    NSArray *posts;
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

- (void)setUser:(NSManagedObject *)user {
    _user = user;
    [self reloadData];
    NSString *name = [_user valueForKey:@"name"];
    self.title = [NSString stringWithFormat:@"%@'s Posts", name];
}

- (void)managedObjectContextDidSave {
    [self reloadData];
    [self.tableView reloadData];
}

- (void)reloadData {
    if ([self isViewLoaded]) {
        NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"Post"];
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"user == %@", _user];
        [request setPredicate:predicate];
        NSManagedObjectContext *context = [ISDAppDelegate managedObjectContext];
        NSError *error = nil;
        posts = [context executeFetchRequest:request error:&error];
        if (error) { NSLog(@"%@", error); }
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return (orientation == UIInterfaceOrientationPortrait);
}

- (void)didReceiveMemoryWarning {
    if ([self isViewLoaded] && !self.view.window) {
        posts = nil;
    }
    [super didReceiveMemoryWarning];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [posts count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    NSManagedObject *object = [posts objectAtIndex:indexPath.row];
    cell.textLabel.text = [object valueForKey:@"title"];
    return cell;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSManagedObject *object = [posts objectAtIndex:indexPath.row];
        NSManagedObjectContext *context = [object managedObjectContext];
        [context deleteObject:object];
        NSError *error = nil;
        BOOL save = [context save:&error];
        NSAssert(save, @"%@", error);
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSManagedObject *object = [posts objectAtIndex:indexPath.row];
    ISDEditPostViewController *controller = [self.storyboard instantiateViewControllerWithIdentifier:@"EditPostViewController"];
    controller.post = object;
    [self.navigationController pushViewController:controller animated:YES];
}

@end
