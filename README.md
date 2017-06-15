# CMainThreadDetector  
[![Build Status](https://travis-ci.org/chbo297/CMainThreadDetector.svg?branch=master)](https://travis-ci.org/chbo297/CMainThreadDetector)
[![Version](https://img.shields.io/cocoapods/v/CMainThreadDetector.svg?style=flat)](http://cocoapods.org/pods/CMainThreadDetector)
![License](https://img.shields.io/cocoapods/l/CMainThreadDetector.svg?style=flat)
![Platform](https://img.shields.io/cocoapods/p/CMainThreadDetector.svg?style=flat)  

## 实现原理
开启一个子线程，  
每隔一段时间ping一下主线程（比如一帧的时间1/60s），主线程pong反馈，  
如果超时未响应，则代表主线程卡住了。  
此时发送中断信号，强制中断主线程并输出当前堆栈信息。  

## 使用方法  

调用[[CMainThreadDetector sharedDetector] startDetecting]开启检测，比如可以在程序启动后开启：  


```  
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    [[CMainThreadDetector sharedDetector] startDetecting];
    
    return YES;
}

```  

可以通过设置这两个值调整监测的频率和阈值。

```  

#define DETECT_INTERVAL     0.1f
#define DETECT_TIMELIMIT     (1.0f/60.0f)

```  

可以通过设置delegate获取输出的堆栈，自行存储在文件中。

 
需要注意的是，demo不可以在调试环境测试，因为调试环境下gdb也在向主线程发送signal，导致detector的signal失效，测试时，安装到虚拟机／手机上运行即可。  
