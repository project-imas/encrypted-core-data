//
//  SMBankDetailViewController.m
//  FailedBankCD
//
//  Created by cesarerocchi on 5/24/12.
//  Copyright (c) 2012 Adam Burkepile. All rights reserved.
//

#import "SMBankDetailViewController.h"

@interface SMBankDetailViewController ()
- (void) hidePicker;
- (void) showPicker;
@end

@implementation SMBankDetailViewController

@synthesize bankInfo = _bankInfo;
@synthesize nameField;
@synthesize cityField;
@synthesize zipField;
@synthesize stateField;
@synthesize tagsLabel;
@synthesize dateLabel;
@synthesize datePicker;

- (id) initWithBankInfo:(FailedBankInfo *) info {

    if (self = [super init]) {
    
        _bankInfo = info;
        
    }
    
    return self;
    
}

- (void)viewDidLoad {
    
    [super viewDidLoad];
    
    self.title = self.bankInfo.name;
    
    // setting the right button
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(saveBankInfo)];
    
    // setting interaction on tag label
    self.tagsLabel.userInteractionEnabled = YES;
    UITapGestureRecognizer *tagsTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self 
                                                                                        action:@selector(tagsTapped)];
    [self.tagsLabel addGestureRecognizer:tagsTapRecognizer];
    
    // setting interaction on date label
    self.dateLabel.userInteractionEnabled = YES;
    UITapGestureRecognizer *dateTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self 
                                                                                        action:@selector(dateTapped)];
    [self.dateLabel addGestureRecognizer:dateTapRecognizer];
    
    // setting labels background
    self.tagsLabel.backgroundColor = self.dateLabel.backgroundColor = [UIColor lightGrayColor];
    
     
    [datePicker addTarget:self
                   action:@selector(dateHasChanged:)
         forControlEvents:UIControlEventValueChanged];
    
    
    
}

- (void)dateHasChanged:(id) sender {
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateStyle:NSDateFormatterMediumStyle];
    self.dateLabel.text = [formatter stringFromDate:self.datePicker.date];
    
}

- (void) viewWillAppear:(BOOL)animated {

    [super viewWillAppear:animated];
    
    // setting values to fields
    self.nameField.text = self.bankInfo.name;
    self.cityField.text = self.bankInfo.city;
    self.zipField.text = [self.bankInfo.details.zip stringValue];
    self.stateField.text = self.bankInfo.state;
    NSSet *tags = self.bankInfo.details.tags;
    NSMutableArray *tagNamesArray = [[NSMutableArray alloc] initWithCapacity:tags.count];
    
    for (Tag *tag in tags) {
        
        [tagNamesArray addObject:tag.name];
        
    }
    
    self.tagsLabel.text = [tagNamesArray componentsJoinedByString:@","];
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateStyle:NSDateFormatterMediumStyle];
    self.dateLabel.text = [formatter stringFromDate:self.bankInfo.details.closeDate];
    
}

#pragma mark - Actions

- (void) tagsTapped {

    SMTagListViewController *tagPicker = [[SMTagListViewController alloc] initWithBankDetails:self.bankInfo.details];
    [self.navigationController pushViewController:tagPicker 
                                         animated:YES];
}

- (void) dateTapped {
    
    [self showPicker];
    
}

- (void) showPicker {
    
    [self.zipField resignFirstResponder];
    [self.nameField resignFirstResponder];
    [self.stateField resignFirstResponder];
    [self.cityField resignFirstResponder];
    
    [UIView beginAnimations:@"SlideInPicker" context:nil];
	[UIView setAnimationDuration:0.5];
	self.datePicker.transform = CGAffineTransformMakeTranslation(0, -216);
	[UIView commitAnimations];
    
}

- (void) hidePicker {

    [UIView beginAnimations:@"SlideOutPicker" context:nil];
	[UIView setAnimationDuration:0.5];
	self.datePicker.transform = CGAffineTransformMakeTranslation(0, 216);
	[UIView commitAnimations];
    
}

- (void) saveBankInfo {

    self.bankInfo.name = self.nameField.text;
    self.bankInfo.city = self.cityField.text;
    self.bankInfo.details.zip = [NSNumber numberWithInt:[self.zipField.text intValue]];
    self.bankInfo.state = self.stateField.text;
    
    NSError *error;
    if ([self.bankInfo.managedObjectContext hasChanges] && ![self.bankInfo.managedObjectContext save:&error]) {
        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        abort();
    } 
    
    [self.navigationController popViewControllerAnimated:YES];
    
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

@end
