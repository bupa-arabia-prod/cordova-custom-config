@import Foundation;
@import UIKit;
@import ObjectiveC;
@import os.log;

#import <Cordova/CDVPlugin.h>

@protocol BupaSceneConnectionOptionsProtocol <NSObject>
@property (nonatomic, readonly, copy) NSSet<NSUserActivity *> *userActivities;
@end

@interface UniversalLinkBridge : CDVPlugin
- (void)storeAndDispatchURL:(NSURL *)webpageURL;
- (void)getPendingUniversalLink:(CDVInvokedUrlCommand *)command;
@end

static NSString *const kCDVContinueUserActivityNotification = @"CDVPluginContinueUserActivityNotification";
static NSString *const kCDVHandleOpenURLNotification = @"CDVPluginHandleOpenURLNotification";
static NSString *sPendingUrl = nil;
static NSString *sLastHandledUrl = nil;
static NSTimeInterval sLastHandledTime = 0;
static BOOL sBridgeInitialized = NO;
static __weak UniversalLinkBridge *sActiveBridge = nil;

// Helper function to parse Universal Link, convert to bupa:// scheme, and store/dispatch
static void bupa_captureUrl(NSURL *webpageURL) {
    if (webpageURL == nil) return;
    
    // Convert https://bupadebug.go.link/... into bupa://path?query format
    NSURLComponents *components = [NSURLComponents componentsWithURL:webpageURL resolvingAgainstBaseURL:YES];
    NSString *path = components.path;
    if (path.length == 0) {
        path = @"/";
    }
    
    // Build query string if parameters exist
    NSMutableString *customSchemeString = [NSMutableString stringWithFormat:@"bupa://%@", path];
    NSArray<NSURLQueryItem *> *queryItems = components.queryItems;
    if (queryItems != nil && queryItems.count > 0) {
        NSMutableArray *paramPairs = [NSMutableArray array];
        for (NSURLQueryItem *item in queryItems) {
            NSString *name = item.name ?: @"";
            NSString *value = item.value ?: @"";
            [paramPairs addObject:[NSString stringWithFormat:@"%@=%@", name, value]];
        }
        [customSchemeString appendFormat:@"?%@", [paramPairs componentsJoinedByString:@"&"]];
    }
    
    NSString *urlString = customSchemeString;
    if (urlString.length == 0) return;

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (sLastHandledUrl != nil &&
        [sLastHandledUrl isEqualToString:urlString] &&
        (now - sLastHandledTime) < 2.0) {
        os_log(OS_LOG_DEFAULT, "[UniversalLinkBridge] Duplicate URL ignored: %{public}@", urlString);
        return;
    }
    sLastHandledUrl = urlString;
    sLastHandledTime = now;

    // Store in native memory so OutSystems can pull it on OnApplicationReady
    sPendingUrl = urlString;
    os_log(OS_LOG_DEFAULT, "[UniversalLinkBridge] Converted and stored custom scheme URL: %{public}@", urlString);

    // Push immediately if app is already warm and running
    if (sBridgeInitialized && sActiveBridge != nil) {
        [sActiveBridge storeAndDispatchURL:[NSURL URLWithString:urlString]];
    }
}

static BOOL bupa_continueUserActivity(id self, SEL _cmd, UIApplication *application, NSUserActivity *userActivity, void (^restorationHandler)(NSArray *)) {
    if ([userActivity isKindOfClass:[NSUserActivity class]] &&
        [userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] &&
        userActivity.webpageURL != nil) {
        os_log(OS_LOG_DEFAULT, "[UniversalLinkBridge] AppDelegate continueUserActivity fired: %{public}@", userActivity.webpageURL.absoluteString);
        bupa_captureUrl(userActivity.webpageURL);
        return YES;
    }
    return NO;
}

@implementation UniversalLinkBridge

+ (void)load {
    // 1. CordovaLib SceneDelegate Notification
    [[NSNotificationCenter defaultCenter] addObserverForName:kCDVContinueUserActivityNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        if ([note.object isKindOfClass:[NSUserActivity class]]) {
            NSUserActivity *act = (NSUserActivity *)note.object;
            if ([act.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) {
                bupa_captureUrl(act.webpageURL);
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
                            bupa_captureUrl(activity.webpageURL);
                            break;
                        }
                    }
                }
            }
        }];
    }

    // 3. AppDelegate Cold-Start & Runtime Hook
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
                        bupa_captureUrl(launchActivity.webpageURL);
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
}

- (void)handleContinueUserActivity:(NSNotification *)notification {
    if ([notification.object isKindOfClass:[NSUserActivity class]]) {
        NSUserActivity *act = (NSUserActivity *)notification.object;
        if ([act.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) {
            bupa_captureUrl(act.webpageURL);
        }
    }
}

// Post CDVPluginHandleOpenURLNotification so Cordova's native CDVHandleOpenURL automatically processes it
- (void)storeAndDispatchURL:(NSURL *)webpageURL {
    if (webpageURL == nil) return;
    os_log(OS_LOG_DEFAULT, "[UniversalLinkBridge] Posting CDVPluginHandleOpenURLNotification for URL: %{public}@", webpageURL.absoluteString);
    [[NSNotificationCenter defaultCenter] postNotificationName:kCDVHandleOpenURLNotification object:webpageURL];
}

// Pull from JS on cold start inside OutSystems OnApplicationReady
- (void)getPendingUniversalLink:(CDVInvokedUrlCommand *)command {
    NSString *urlToReturn = sPendingUrl;
    sPendingUrl = nil; // Consume once so it doesn't re-trigger on refresh
    os_log(OS_LOG_DEFAULT, "[UniversalLinkBridge] JS pulled pending URL: %{public}@", urlToReturn ?: @"(none)");

    CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                messageAsString:urlToReturn];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
