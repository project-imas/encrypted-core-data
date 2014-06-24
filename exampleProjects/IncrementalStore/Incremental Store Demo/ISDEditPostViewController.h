//
//  ISDEditPostViewController.h
//  Incremental Store Demo
//
// Copyright 2012 - 2014 The MITRE Corporation, All Rights Reserved.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

@interface ISDEditPostViewController : UIViewController

@property (nonatomic, weak) IBOutlet UITextView *bodyTextView;
@property (nonatomic, weak) IBOutlet UITextField *titleTextField;
@property (nonatomic, weak) IBOutlet UITextField *tagsTextField;
@property (nonatomic, strong) NSManagedObject *post;

- (IBAction)save:(id)sender;
- (IBAction)cancel:(id)sender;

@end
