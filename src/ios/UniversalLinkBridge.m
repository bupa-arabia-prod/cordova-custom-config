#import <Cordova/CDVPlugin.h>
#import <objc/runtime.h>
#import <os/log.h>



@interface UniversalLinkBridge : CDVPlugin
- (void)dispatchUserActivityToJS:(NSUserActivity *)userActivity;
@end

static NSUserActivity *sPendingUserActivity = nil;
static BOOL sBridgeInitialized = NO;
static UniversalLinkBridge *sActiveBridge = nil;

// C-function hook for AppDelegate's application:continueUserActivity:restorationHandler:
static BOOL bupa_continueUserActivity(id self, SEL _cmd, UIApplication *application, NSUserActivity *userActivity, void (^restorationHandler)(NSArray *)) {
    os_log(OS_LOG_DEFAULT, "[UniversalLinkBridge] AppDelegate continueUserActivity fired: %{public}@", userActivity.webpageURL.absoluteString);
    if ([userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] && userActivity.webpageURL != nil) {
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
    // 1. Hook SceneDelegate notification (for local Xcode / UIScene-based builds)
    [[NSNotificationCenter defaultCenter] addObserverForName:CDVPluginContinueUserActivityNotification
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

    // 2. Hook UIScene cold-start connection options
    if (@available(iOS 13.0, *)) {
        [[NSNotificationCenter defaultCenter] addObserverForName:UISceneWillConnectNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            UISceneConnectionOptions *options = note.userInfo[UISceneConnectionOptionsKey];
            for (NSUserActivity *activity in options.userActivities) {
                if ([activity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] && activity.webpageURL != nil) {
                    os_log(OS_LOG_DEFAULT, "[UniversalLinkBridge] Scene cold-start URL: %{public}@", activity.webpageURL.absoluteString);
                    sPendingUserActivity = activity;
                    break;
                }
            }
        }];
    }

    // 3. Hook AppDelegate directly (for OutSystems MABS builds without SceneDelegate)
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        // Check cold-start launchOptions dictionary
        NSDictionary *launchOptions = note.userInfo;
        NSDictionary *activityDict = launchOptions[UIApplicationLaunchOptionsUserActivityDictionaryKey];
        NSUserActivity *launchActivity = activityDict[UIApplicationLaunchOptionsUserActivityKey];
        if ([launchActivity isKindOfClass:[NSUserActivity class]] && launchActivity.webpageURL != nil) {
            os_log(OS_LOG_DEFAULT, "[UniversalLinkBridge] AppDelegate cold-start URL: %{public}@", launchActivity.webpageURL.absoluteString);
            if (sBridgeInitialized && sActiveBridge != nil) {
                [sActiveBridge dispatchUserActivityToJS:launchActivity];
            } else {
                sPendingUserActivity = launchActivity;
            }
        }

        // Inject application:continueUserActivity:restorationHandler: onto AppDelegate if missing
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
                                                 name:CDVPluginContinueUserActivityNotification
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

- (void)dispatchUserActivityToJS:(NSUserActivity *)userActivity {
    if ([userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] &&
        userActivity.webpageURL != nil) {

        NSString *urlString = userActivity.webpageURL.absoluteString;
        os_log(OS_LOG_DEFAULT, "[UniversalLinkBridge] Dispatching to JS: %{public}@", urlString);
        NSString *escapedUrl = [urlString stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];

        NSString *js = [NSString stringWithFormat:
            @"(function() {"
            @"  var url = '%@';"
            @"  var attempts = 0;"
            @"  var timer = setInterval(function() {"
            @"    attempts++;"
            @"    if (typeof window.handleOpenURL === 'function') {"
            @"      clearInterval(timer);"
            @"      window.handleOpenURL(url);"
            @"    } else if (attempts >= 50) {"
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
