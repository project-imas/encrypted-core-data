//
//  SMBankDetailViewController.h
//  FailedBankCD
//
//  Created by cesarerocchi on 5/24/12.
//  Copyright (c) 2012 Adam Burkepile. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FailedBankInfo.h"
#import "FailedBankDetails.h"
#import "Tag.h"
#import "SMTagListViewController.h"

@interface SMBankDetailViewController : UIViewController

@property (nonatomic, strong) FailedBankInfo *bankInfo;
@property (nonatomic, strong) IBOutlet UITextField *nameField;
@property (nonatomic, strong) IBOutlet UITextField *cityField;
@property (nonatomic, strong) IBOutlet UITextField *zipField;
@property (nonatomic, strong) IBOutlet UITextField *stateField;
@property (nonatomic, strong) IBOutlet UILabel *tagsLabel;
@property (nonatomic, strong) IBOutlet UILabel *dateLabel;
@property (nonatomic, strong) IBOutlet UIDatePicker *datePicker;


- (id) initWithBankInfo:(FailedBankInfo *) info;

@end
