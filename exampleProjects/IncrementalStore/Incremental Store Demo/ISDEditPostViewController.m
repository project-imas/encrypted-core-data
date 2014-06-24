//
//  ISDEditPostViewController.m
//  Incremental Store Demo
//
// Copyright 2012 - 2014 The MITRE Corporation, All Rights Reserved.
//

#import "ISDEditPostViewController.h"

@implementation ISDEditPostViewController

- (id)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        self.title = @"New Post";
    }
    return self;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return (orientation == UIInterfaceOrientationPortrait);
}

- (void)populateFieldsFromModel {
    self.titleTextField.text = [self.post valueForKey:@"title"];
    self.bodyTextView.text = [self.post valueForKey:@"body"];
    self.tagsTextField.text = [[self.post valueForKey:@"tags"] componentsJoinedByString:@" "];
}

- (void)setPost:(NSManagedObject *)post {
    _post = post;
    self.title = @"Edit Post";
    [self populateFieldsFromModel];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self populateFieldsFromModel];
    [self.titleTextField becomeFirstResponder];
}

- (IBAction)save:(id)sender {
    [self.post setValue:self.titleTextField.text forKey:@"title"];
    [self.post setValue:self.bodyTextView.text forKey:@"body"];
    [self.post setValue:[self.tagsTextField.text componentsSeparatedByString:@" "] forKey:@"tags"];
    NSError *error = nil;
    if ([[self.post managedObjectContext] save:&error]) {
        [self.navigationController popViewControllerAnimated:YES];
    }
    else {
        NSLog(@"%@", error);
        NSArray *array = [[error userInfo] objectForKey:NSPersistentStoreSaveConflictsErrorKey];
        [array enumerateObjectsUsingBlock:^(id conflict, NSUInteger index, BOOL *stop) {
            NSLog(@"%@", conflict);
        }];
    }
}

- (IBAction)cancel:(id)sender {
    [[self.post managedObjectContext] rollback];
    [self.navigationController popViewControllerAnimated:YES];
}

@end
