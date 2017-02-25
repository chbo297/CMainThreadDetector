//
//  CMainThreadDetector.m
//  CMainThreadDetector
//
//  Created by bo on 25/02/2017.
//  Copyright © 2017 bo. All rights reserved.
//

#import "CMainThreadDetector.h"
#include <pthread.h>
#include <signal.h>

#define DETECT_INTERVAL     1.0f
#define DETECT_TIMELIMIT     (1.0f/60.0f)

#define PING_NOTIFICATION @"ping_notification"
#define PONG_NOTIFICATION @"pong_notification"

#define DUMPSTACK_SIGNAL SIGUSR1

/**
 该方法被注册在主线程中，
 当检测线程发现主线程发生卡顿时，发送signal，
 主线程接收到DUMPSTACK_SIGNAL，输出当前stackSymbols。
 */
static void receiveDumpStackSignal(int sig)
{
    if (sig != DUMPSTACK_SIGNAL) {
        return;
    }
    
    NSArray* stackSymbols = [NSThread callStackSymbols];
    
    id<CMainThreadDetectorDelegate> delegate = [CMainThreadDetector sharedDetector].delegate;
    if ([delegate respondsToSelector:@selector(mainThreadSlowDetectDump:)]) {
        [delegate mainThreadSlowDetectDump:stackSymbols];
    }
    else
    {
        NSLog(@"mainThreadSlow:\n%@", stackSymbols);
    }
    
    return;
}

@implementation CMainThreadDetector
{
    pthread_t _detectThread;
    dispatch_source_t _cyclePingTimer;
    dispatch_source_t _waitingPongTimer;
}

+ (instancetype)sharedDetector {
    static CMainThreadDetector *detector = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        detector = [CMainThreadDetector new];
    });
    return detector;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (BOOL)commonInit {
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(detectPing)
                                                 name:PING_NOTIFICATION
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(detectPong)
                                                 name:PONG_NOTIFICATION
                                               object:nil];
    
    [self initSignal];
    
    return YES;
}

#pragma mark - thread signal

- (void)initSignal {
    void(^blcok)(void) = ^{
        _detectThread = pthread_self();
        signal(DUMPSTACK_SIGNAL, receiveDumpStackSignal);
    };
    
    if ([NSThread isMainThread]) {
        blcok();
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            blcok();
        });
    }
}

- (void)signalMainThreadDumpStack {
    pthread_kill(_detectThread, DUMPSTACK_SIGNAL);
}

#pragma mark - ping/pong notification

- (void)detectPing
{
    [[NSNotificationCenter defaultCenter] postNotificationName:PONG_NOTIFICATION object:nil];
}

- (void)detectPong
{
    [self cancelPongWaitingTimer];
}

#pragma mark - ping/pong timer

- (void)startPingTimer {
    if (_cyclePingTimer) {
        NSLog(@"cyclePingTimer has already started");
        return;
    }
    
    int64_t interval = DETECT_INTERVAL * NSEC_PER_SEC;
    _cyclePingTimer = createTimerInWorkerThread(interval, ^{
        [self pingMainThreadAndWaitingPong];
    });
}

- (void)pingMainThreadAndWaitingPong
{
    if ([self startPongWaitingTimer]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:PING_NOTIFICATION object:nil];
        });
        
    }
}

- (void)cancelPingTimer {
    if (_cyclePingTimer) {
        dispatch_source_cancel(_cyclePingTimer);
        _cyclePingTimer = nil;
    }
}


- (BOOL)startPongWaitingTimer {
    
    if (_waitingPongTimer) {
        NSLog(@"cyclePingTimer has already started");
        return NO;
    }
    
    int64_t interval = DETECT_TIMELIMIT * NSEC_PER_SEC;
    _waitingPongTimer = createTimerInWorkerThread(interval, ^{
        [self pongWaitingTimeout];
    });
    
    return YES;
}

- (void)pongWaitingTimeout
{
    [self cancelPongWaitingTimer];
    [self signalMainThreadDumpStack];
}

- (void)cancelPongWaitingTimer {
    if (_waitingPongTimer) {
        dispatch_source_cancel(_waitingPongTimer);
        _waitingPongTimer = nil;
    }
}

dispatch_source_t createTimerInWorkerThread(uint64_t interval, dispatch_block_t block)
{
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                     dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    if (timer)
    {
        dispatch_source_set_timer(timer, dispatch_walltime(NULL, interval), interval, 0);
        dispatch_source_set_event_handler(timer, block);
        dispatch_resume(timer);
    }
    return timer;
}

#pragma mark - API

- (void)startDetecting {
    if (![NSThread isMainThread]) {
        NSLog(@"error: %s must be executing in mainthread", __func__);
        return;
    }
    
    [self startPingTimer];
}

- (void)stopDetecting {
    if (![NSThread isMainThread]) {
        NSLog(@"error: %s must be executing in mainthread", __func__);
        return;
    }
    
    [self cancelPingTimer];
}

@end
