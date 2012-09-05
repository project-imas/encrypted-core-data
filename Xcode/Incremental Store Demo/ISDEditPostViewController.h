//
//  ISDEditPostViewController.h
//  Incremental Store Demo
//
//  Created by Caleb Davenport on 8/1/12.
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
