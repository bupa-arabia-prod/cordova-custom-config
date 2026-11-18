@import Foundation;
@import UIKit;
@import ObjectiveC;
@import os.log;

#import <Cordova/CDVPlugin.h>

@protocol BupaSceneConnectionOptionsProtocol <NSObject>
@property (nonatomic, readonly, copy) NSSet<NSUserActivity *> *userActivities;
@end

@interface UniversalLinkBridge : CDVPlugin
- (void)dispatchUserActivityToJS:(NSUserActivity *)userActivity;
@end

static NSString *const kCDVContinueUserActivityNotification = @"CDVPluginContinueUserActivityNotification";
static NSUserActivity *sPendingUserActivity = nil;
static BOOL sBridgeInitialized = NO;
static __weak UniversalLinkBridge *sActiveBridge = nil;

static BOOL bupa_continueUserActivity(id self, SEL _cmd, UIApplication *application, NSUserActivity *userActivity, void (^restorationHandler)(NSArray *)) {
    if ([userActivity isKindOfClass:[NSUserActivity class]] &&
        [userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] &&
        userActivity.webpageURL != nil) {
        os_log(OS_LOG_DEFAULT, "[UniversalLinkBridge] AppDelegate continueUserActivity fired: %{public}@", userActivity.webpageURL.absoluteString);
        if (sBridgeInitialized && sActiveBridge != nil) {
            [sActiveBridge dispatchUserActivityToJS:userActivity];
        } else {
            sPendingUserActivity = userActivity;
        }
        return YES;
    }
    return NO;
}

@implementation UniversalLinkBridge

+ (void)load {
    // 1. CordovaLib SceneDelegate Notification (using string literal so OutSystems CordovaLib fork never fails symbol lookup)
    [[NSNotificationCenter defaultCenter] addObserverForName:kCDVContinueUserActivityNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        if ([note.object isKindOfClass:[NSUserActivity class]]) {
            NSUserActivity *act = (NSUserActivity *)note.object;
            os_log(OS_LOG_DEFAULT, "[UniversalLinkBridge] Scene notification fired: %{public}@", act.webpageURL.absoluteString);
            if (!sBridgeInitialized) {
                sPendingUserActivity = act;
            }
        }
    }];

    // 2. UIScene Cold-Start Connection Options
    Class sceneOptionsClass = NSClassFromString(@"UISceneConnectionOptions");
    if (sceneOptionsClass != nil) {
        [[NSNotificationCenter defaultCenter] addObserverForName:@"UISceneWillConnectNotification"
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            for (id val in note.userInfo.allValues) {
                if ([val isKindOfClass:sceneOptionsClass] && [val respondsToSelector:@selector(userActivities)]) {
                    NSSet<NSUserActivity *> *activities = [(id<BupaSceneConnectionOptionsProtocol>)val userActivities];
                    for (NSUserActivity *activity in activities) {
                        if ([activity isKindOfClass:[NSUserActivity class]] &&
                            [activity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] &&
                            activity.webpageURL != nil) {
                            os_log(OS_LOG_DEFAULT, "[UniversalLinkBridge] Scene cold-start URL: %{public}@", activity.webpageURL.absoluteString);
                            sPendingUserActivity = activity;
                            break;
                        }
                    }
                }
            }
        }];
    }

    // 3. AppDelegate Cold-Start & Runtime Hook (for MABS builds using AppDelegate)
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        NSDictionary *launchOptions = note.userInfo;
        NSDictionary *activityDict = launchOptions[UIApplicationLaunchOptionsUserActivityDictionaryKey];
        if ([activityDict isKindOfClass:[NSDictionary class]]) {
            for (id val in activityDict.allValues) {
                if ([val isKindOfClass:[NSUserActivity class]]) {
                    NSUserActivity *launchActivity = (NSUserActivity *)val;
                    if ([launchActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] && launchActivity.webpageURL != nil) {
                        os_log(OS_LOG_DEFAULT, "[UniversalLinkBridge] AppDelegate cold-start URL: %{public}@", launchActivity.webpageURL.absoluteString);
                        if (sBridgeInitialized && sActiveBridge != nil) {
                            [sActiveBridge dispatchUserActivityToJS:launchActivity];
                        } else {
                            sPendingUserActivity = launchActivity;
                        }
                        break;
                    }
                }
            }
        }

        id<UIApplicationDelegate> delegate = [UIApplication sharedApplication].delegate;
        if (delegate != nil) {
            Class delegateClass = [delegate class];
            SEL sel = @selector(application:continueUserActivity:restorationHandler:);
            if (![delegateClass instancesRespondToSelector:sel]) {
                class_addMethod(delegateClass, sel, (IMP)bupa_continueUserActivity, "B@:@@@?");
                os_log(OS_LOG_DEFAULT, "[UniversalLinkBridge] Added continueUserActivity to %{public}@", NSStringFromClass(delegateClass));
            }
        }
    }];
}

- (void)pluginInitialize {
    sBridgeInitialized = YES;
    sActiveBridge = self;
    os_log(OS_LOG_DEFAULT, "[UniversalLinkBridge] pluginInitialize executed!");

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleContinueUserActivity:)
                                                 name:kCDVContinueUserActivityNotification
                                               object:nil];

    if (sPendingUserActivity != nil) {
        NSUserActivity *activity = sPendingUserActivity;
        sPendingUserActivity = nil;
        [self dispatchUserActivityToJS:activity];
    }
}

- (void)handleContinueUserActivity:(NSNotification *)notification {
    if ([notification.object isKindOfClass:[NSUserActivity class]]) {
        [self dispatchUserActivityToJS:(NSUserActivity *)notification.object];
    }
}

static NSString *sLastDispatchedUrl = nil;
static NSTimeInterval sLastDispatchedTime = 0;

- (void)dispatchUserActivityToJS:(NSUserActivity *)userActivity {
    if ([userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] &&
        userActivity.webpageURL != nil) {

        NSString *urlString = userActivity.webpageURL.absoluteString;

        // Deduplicate: ignore identical URL fired twice during cold start (DidFinishLaunching + continueUserActivity)
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if (sLastDispatchedUrl != nil &&
            [sLastDispatchedUrl isEqualToString:urlString] &&
            (now - sLastDispatchedTime) < 2.0) {
            os_log(OS_LOG_DEFAULT, "[UniversalLinkBridge] Duplicate URL ignored: %{public}@", urlString);
            return;
        }
        sLastDispatchedUrl = urlString;
        sLastDispatchedTime = now;

        os_log(OS_LOG_DEFAULT, "[UniversalLinkBridge] Dispatching to JS: %{public}@", urlString);
        NSString *escapedUrl = [urlString stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];

        NSString *js = [NSString stringWithFormat:
            @"(function() {"
            @"  var url = '%@';"
            @"  window.__bupaPendingUniversalLink = url;"
            @"  var attempts = 0;"
            @"  var timer = setInterval(function() {"
            @"    attempts++;"
            @"    if (typeof window.handleAdjustUniversalLink === 'function') {"
            @"      clearInterval(timer);"
            @"      window.__bupaPendingUniversalLink = null;"
            @"      window.handleAdjustUniversalLink(url);"
            @"    } else if (attempts >= 100) {"
            @"      clearInterval(timer);"
            @"    }"
            @"  }, 100);"
            @"})();",
            escapedUrl];

        [self.commandDelegate evalJs:js];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
