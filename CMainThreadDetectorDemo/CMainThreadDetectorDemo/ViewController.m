//
//  ViewController.m
//  CMainThreadDetectorDemo
//
//  Created by bo on 25/02/2017.
//  Copyright © 2017 bo. All rights reserved.
//

#import "ViewController.h"
#import "CMainThreadDetector.h"

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UITextView *textView;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (IBAction)blockingTheMainThread:(id)sender {
    NSMutableString *str = [NSMutableString new];
    
    for (int o = 0; o < 10; o++) {
        for (int i = 0; i < 100; i ++) {
            for (int j = 0; j < 10000; j++) {
                [str appendString:@"hah"];
                [str deleteCharactersInRange:NSMakeRange(str.length-3, 3)];
            }
            
        }
    }
}


@end
