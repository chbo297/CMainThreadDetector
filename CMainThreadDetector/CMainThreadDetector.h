//
//  CMainThreadDetector.h
//  CMainThreadDetector
//
//  Created by bo on 25/02/2017.
//  Copyright © 2017 bo. All rights reserved.
//

#import <Foundation/Foundation.h>


@protocol CMainThreadDetectorDelegate <NSObject>

- (void)mainThreadSlowDetectDump:(NSArray<NSString *> *)stackSymbols;

@end

@interface CMainThreadDetector : NSObject

+ (instancetype)sharedDetector;

@property (nonatomic, weak) id<CMainThreadDetectorDelegate> delegate;

- (void)startDetecting;

- (void)stopDetecting;

@end
