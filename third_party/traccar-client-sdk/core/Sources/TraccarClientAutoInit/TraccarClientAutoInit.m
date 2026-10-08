#import "TraccarClientAutoInit.h"
#import <UIKit/UIKit.h>
#import <TraccarClientSDK/TraccarClientSDK.h>

@interface TraccarClientAutoInit : NSObject
@end

@implementation TraccarClientAutoInit

+ (void)load {
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidFinishLaunchingNotification
        object:nil
        queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) {
            [[TCSDKIosBackgroundHeartbeat companion] register];
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                [TCSDKTrackerKt sharedTrackerWithCompletionHandler:^(TCSDKTracker *tracker, NSError *error) {}];
            });
        }];
}

@end
