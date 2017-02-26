# CMainThreadDetector
##起
软件发布后，偶尔会有这样的反馈信息：  
“打开某个页面时卡了一会儿”、“在某种情况下，做某种操作时软件很卡”。  
这时，开发者拿起手机打开某个页面，试呀试呀试呀试，难以重现。。。  
这些问题，   
可能是在特定用户的特定环境下才会发生，  
可能需要极特殊的时机下才会出现，  
难以重现，难以发觉。大多数情况下只能去沿着代码逻辑细细推敲。  
于是，有了这个MainThreadDetector的需求。  
##承  
（以下部分内容节选自：[微信iOS卡顿监控系统](http://mp.weixin.qq.com/s?__biz=MzAwNDY1ODY2OQ==&mid=207890859&idx=1&sn=e98dd604cdb854e7a5808d2072c29162&scene=21#wechat_redirect)）  

发生卡顿，原因大致可分为以下几种：  
* 抢锁：主线程需要访问 DB，而此时某个子线程往 DB 插入大量数据。通常抢锁的体验是偶尔卡一阵子，过会就恢复了。
* 主线程大量 IO：主线程为了方便直接写入大量数据，会导致界面卡顿。
* 主线程大量计算：算法不合理，导致主线程某个函数占用大量 CPU。
* 大量的 UI 绘制：复杂的 UI、图文混排等，带来大量的 UI 绘制。  
  
针对这些问题，如何解决呢？  
* 抢锁不好办，将锁等待时间打出来用处不大，我们还需要知道是谁占了锁。
* 大量 IO 可以在函数开始结束打点，将占用时间打到日志中。
* 大量计算同理可以将耗时打到日志中。
* 大量 UI 绘制一般是必现，还好办；如果是偶现的话，想加日志点都没地方，因为是慢在系统函数里面。  
  
如果可以将当时的线程堆栈捕捉下来，那么上述难题都迎刃而解。主线程在什么函数哪一行卡住，在等什么锁，而这个锁又是被哪个子线程的哪个函数占用，有了堆栈，我们都可以知道。自然也能知道是慢在UI绘制，还是慢在我们的代码。
所以，思路就是`监控主线程，如果发现有卡顿，就将堆栈 dump 下来`。  
  
  实现思路：  
  1.基于Runtime的sendMessage机制，检测特定方法的执行时间。  
  2.基于RunLoop机制下，检测每次loop的时长。  
  3.在子线程中养一只小狗，不停地呼叫主线程，主线程进行响应，如果响应超时，说明主线程卡住了。  
  
##转  
  
  上述三个思路：  
  第1个思路，  
  需要在每次message的传递过程中添加额外程序段，但我们目前需求是检测主线程，对message检测使程序变得过于冗杂。  
  这个思路只用在检测特定方法时使用，比如只检测每个Controller的加载时长，就重写或者扩展viewDidLoad方法来检测每次这个方法的执行时长，统计页面初始化的用时。  
  
  第2个思路，  
  检测RunLoop的时长，可以准确的获得发生卡顿的RunLoop，此时打出堆栈即可。  
  但笔者用这个思路实现后才发现，打出的堆栈信息离发生卡顿的地方想去甚远。在一次RunLoop过程中，某处卡顿结束后，后面还会进出非常多正常的堆栈信息，结果就是，在RunLoop的最后获取到堆栈时，完全找不到卡顿发生的地方，这是一个小坑。  
  
  第3个思路，  
  起一个类似于看门狗的子线程，在子线程中每隔一段时间（例如1秒）呼叫一下主线程，主线程进行回馈，如果子线程超过一定时间没有接收到回馈（例如1/60秒，也就是一帧的时间），那么说明主线程发生卡顿了，此时获取主线程的堆栈即可。  
  
  本项目使用第3个思路。  

##合  
  
  先开启子线程，并在其中执行timer用来ping主线程，这个timer不能因为程序卡顿而停止，需要一个以真实时间为准的timer：  
  
```

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

```
  在子线程中开启timer，每隔一段时间就执行ping操作：
  
```

  createTimerInWorkerThread(interval, ^{
        [self pingMainThreadAndWaitingPong];
    });
    
  - (void)pingMainThreadAndWaitingPong
{
    if ([self startPongWaitingTimer]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:PING_NOTIFICATION object:nil];
        });
        
    }
}

```
  
  主线程中响应ping：  
  
```

- (void)detectPing
{
    [[NSNotificationCenter defaultCenter] postNotificationName:PONG_NOTIFICATION object:nil];
}

```
  
  如果子线程在规定时间没有的到，则响应响应超时，开始要求主线程输出堆栈：
  
```

- (void)signalMainThreadDumpStack {
    pthread_kill(_detectThread, DUMPSTACK_SIGNAL);  //_detectThread是主线程
}

```
  
  这里是向主线程发送了一个用户自定义的signal，主线程接收到signal后会停止当前工作，进行一些定义的响应操作，在使用这个signal之前需要向主线程注册这个signal和相应操作的block：
  
```

static void dumpStackSignalHandler(int sig)
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

signal(DUMPSTACK_SIGNAL, dumpStackSignalHandler);


```
  
  以上。  
  CMainThreadDetector可以检测到主线程发生的卡顿，然后输出堆栈信息。  
  这里有一个Demo模拟大量运算产生的卡顿，进行测试（不可以在调试环境测试哦，调试环境下gdb也在向主线程发送signal，导致detector的signal失效，若要测试，安装到虚拟机／手机上运行即可）。
  
##续  
  
  这个工具可以作为一个帮助你检测程序性能问题的助手，告诉你程序在哪里发生了卡顿。  
  欢迎有更多开发者加入进来，扩展它的实用性。  
  比如：  
  添加时间检测算法，可设置时间阈值，对多次短时卡顿的识别功能；  
  添加卡顿堆栈数据本地存储和上传功能；  
  
  
  
