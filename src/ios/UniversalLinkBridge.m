#import <Cordova/CDVPlugin.h>

static NSUserActivity *sPendingUserActivity = nil;
static BOOL sBridgeInitialized = NO;

@interface UniversalLinkBridge : CDVPlugin
@end

@implementation UniversalLinkBridge

//+ (void)load {
//    [[NSNotificationCenter defaultCenter] addObserverForName:@"CDVPluginContinueUserActivityNotification"
//                                                      object:nil
//                                                       queue:[NSOperationQueue mainQueue]
//                                                  usingBlock:^(NSNotification *note) {
//        //if (!sBridgeInitialized) {
//            sPendingUserActivity = note.object;
//            [self dispatchUserActivityToJSGlobal:(NSUserActivity *)note.object];
//            NSLog(@"[UniversalLinkBridge] Buffered cold-start Universal Link: %@", sPendingUserActivity.webpageURL);
//        //}
//        NSLog(@"[UniversalLinkBridge] Buffered cold-start");
//    }];
//}

- (void)pluginInitialize {
    sBridgeInitialized = YES;
    NSLog(@"[UniversalLinkBridge] pluginInitialize executed!");

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleContinueUserActivity:)
                                                 name:@"CDVPluginContinueUserActivityNotification"
                                               object:nil];

    // Replay cold-start Universal Link if it arrived before pluginInitialize
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

+ (void)dispatchUserActivityToJSGlobal:(NSUserActivity *)userActivity {
    if ([userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] &&
        userActivity.webpageURL != nil) {

        NSString *urlString = userActivity.webpageURL.absoluteString;
        NSString *escapedUrl = [urlString stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
        NSLog(@"Universal Link%@", escapedUrl);

        NSString *js = [NSString stringWithFormat:
            @"setTimeout(function() { if (typeof window.handleOpenURL === 'function') { window.handleOpenURL('%@'); } }, 0);",
            escapedUrl];

        //[self.commandDelegate evalJs:js];
    }
}
- (void)dispatchUserActivityToJS:(NSUserActivity *)userActivity {
    if ([userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] &&
        userActivity.webpageURL != nil) {

        NSString *urlString = userActivity.webpageURL.absoluteString;
        NSString *escapedUrl = [urlString stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
        NSLog(@"Universal Link %@", escapedUrl);

        NSString *js = [NSString stringWithFormat:
            @"setTimeout(function() { if (typeof window.handleOpenURL === 'function') { window.handleOpenURL('%@'); } }, 0);",
            escapedUrl];

        [self.commandDelegate evalJs:js];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end






