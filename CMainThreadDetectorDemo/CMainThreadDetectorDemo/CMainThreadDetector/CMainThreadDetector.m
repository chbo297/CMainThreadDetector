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

#define DETECT_INTERVAL     0.1f
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
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *pre = [CMainThreadDetector sharedDetector].outputView.text;
            [CMainThreadDetector sharedDetector].outputView.text = [[stackSymbols description] stringByAppendingString:[NSString stringWithFormat:@"\n===========================\n%@", pre]];
        });
    }
    
    
    return;
}

@implementation CMainThreadDetector
{
    pthread_t _detectThread;
    dispatch_source_t _cyclePingTimer;
    volatile dispatch_source_t _waitingPongTimer;
    
    UIWindow *_window;
    NSValue *_panBeginPoint;
    NSValue *_dragBeginPoint;
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

#pragma mark - output view

- (UITextView *)outputView
{
    if (!_outputView) {
        
        CGSize textsize = CGSizeMake((UIScreen.mainScreen.bounds.size.width), 120);
        _outputView = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, textsize.width, textsize.height)];
        _outputView.editable = NO;
        _outputView.backgroundColor = [UIColor greenColor];
        _outputView.text = @"display stack symbols when main thread slow";
        
        UIView *panview = [[UIView alloc] initWithFrame:CGRectMake(textsize.width - 50, textsize.height, 50, 50)];
        panview.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        [panview addGestureRecognizer:pan];
        
        
        UIView *dragview = [[UIView alloc] initWithFrame:CGRectMake(0, textsize.height, 50, 50)];
        dragview.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        [dragview addGestureRecognizer:drag];
        
        UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0,
                                                                      textsize.width,
                                                                      textsize.height + panview.bounds.size.height)];
        UIViewController *vc = [UIViewController new];
        [window setRootViewController:vc];
        window.windowLevel = UIWindowLevelStatusBar + 1;
        [window addSubview:vc.view];
        vc.view.frame = window.bounds;
        [vc.view addSubview:_outputView];
        [vc.view addSubview:panview];
        [vc.view addSubview:dragview];
        
        _outputView.autoresizingMask = UIViewAutoresizingFlexibleHeight;
        panview.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
        dragview.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
        
        window.hidden = NO;
        _window = window;
    }
    return _outputView;
}

- (void)pan:(UIPanGestureRecognizer *)pan
{
    if (UIGestureRecognizerStateBegan == pan.state) {
        _panBeginPoint = [NSValue valueWithCGPoint:[pan locationInView:pan.view]];
    } else if (UIGestureRecognizerStateChanged == pan.state) {
        if (_panBeginPoint) {
            CGPoint current = [pan locationInView:pan.view];
            CGPoint begin = [_panBeginPoint CGPointValue];
            CGFloat move = current.y - begin.y;
            CGRect frame = _window.frame;
            frame.origin.y += move;
            frame.origin.y = MIN([UIScreen mainScreen].bounds.size.height - frame.size.height, frame.origin.y);
            frame.origin.y = MAX(- (frame.size.height - 50), frame.origin.y);
            _window.frame = frame;
        }
    } else if (UIGestureRecognizerStateEnded == pan.state) {
        _panBeginPoint = nil;
    } else if (UIGestureRecognizerStateCancelled == pan.state) {
        _panBeginPoint = nil;
    } else if (UIGestureRecognizerStateFailed == pan.state) {
        _panBeginPoint = nil;
    }
}

- (void)drag:(UIPanGestureRecognizer *)pan
{
    if (UIGestureRecognizerStateBegan == pan.state) {
        _dragBeginPoint = [NSValue valueWithCGPoint:[pan locationInView:pan.view]];
    } else if (UIGestureRecognizerStateChanged == pan.state) {
        if (_dragBeginPoint) {
            CGPoint current = [pan locationInView:pan.view];
            CGPoint begin = [_dragBeginPoint CGPointValue];
            CGFloat move = current.y - begin.y;
            CGRect frame = _window.frame;
            frame.size.height += move;
            frame.size.height = MAX(50, frame.size.height);
            frame.size.height = MIN([UIScreen mainScreen].bounds.size.height - frame.origin.y, frame.size.height);
            _window.frame = frame;
        }
    } else if (UIGestureRecognizerStateEnded == pan.state) {
        _dragBeginPoint = nil;
    } else if (UIGestureRecognizerStateCancelled == pan.state) {
        _dragBeginPoint = nil;
    } else if (UIGestureRecognizerStateFailed == pan.state) {
        _dragBeginPoint = nil;
    }
}

@end
