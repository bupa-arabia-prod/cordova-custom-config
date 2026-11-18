#import <Cordova/CDVPlugin.h>

@interface UniversalLinkBridge : CDVPlugin
@end

@implementation UniversalLinkBridge

- (void)pluginInitialize {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleContinueUserActivity:)
                                                 name:@"CDVPluginContinueUserActivityNotification"
                                               object:nil];
}

- (void)handleContinueUserActivity:(NSNotification *)notification {
    NSUserActivity *userActivity = notification.object;
    if ([userActivity isKindOfClass:[NSUserActivity class]] &&
        [userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] &&
        userActivity.webpageURL != nil) {
        
        NSString *urlString = userActivity.webpageURL.absoluteString;
        NSString *escapedUrl = [urlString stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
        
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
