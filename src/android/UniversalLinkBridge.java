package sa.com.bupa.deeplink;

import android.content.Intent;
import android.net.Uri;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CallbackContext;
import org.apache.cordova.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;

public class UniversalLinkBridge extends CordovaPlugin {
    private static String pendingUniversalLink = null;

    @Override
    public void pluginInitialize() {
        super.pluginInitialize();
        // Cold-start intent check (Jab app bilkul band thi aur link se khuli)
        Intent intent = cordova.getActivity().getIntent();
        handleIntent(intent);
    }

    @Override
    public void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        // Warm-state intent check (Jab app background mein thi aur naya link click hua)
        handleIntent(intent);
    }

    private void handleIntent(Intent intent) {
        if (intent != null) {
            String action = intent.getAction();
            if (Intent.ACTION_VIEW.equals(action)) {
                Uri data = intent.getData();
                if (data != null) {
                    String url = data.toString();
                    pendingUniversalLink = url;
                    emitUrlToJS(url);
                }
            }
        }
    }

    private void emitUrlToJS(final String url) {
        if (webView != null) {
            cordova.getActivity().runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    String escapedUrl = url.replace("'", "\\'");
                    String js = "if (typeof window.handleAdjustUniversalLink === 'function') { " +
                                "    window.handleAdjustUniversalLink('" + escapedUrl + "'); " +
                                "}";
                    webView.loadUrl("javascript:" + js);
                }
            });
        }
    }

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
        if ("getPendingUniversalLink".equals(action)) {
            String link = pendingUniversalLink;
            pendingUniversalLink = null; // Read hone ke baad clear kar dein taake duplicate na ho
            PluginResult result = new PluginResult(PluginResult.Status.OK, link);
            callbackContext.sendPluginResult(result);
            return true;
        }
        return false;
    }
}