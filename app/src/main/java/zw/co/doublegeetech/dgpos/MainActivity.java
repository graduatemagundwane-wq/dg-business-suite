package zw.co.doublegeetech.dgpos;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.AlertDialog;
import android.os.Bundle;
import android.graphics.Color;
import android.webkit.CookieManager;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebChromeClient;
import android.webkit.JsResult;
import android.webkit.JsPromptResult;
import android.webkit.WebSettings;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.ProgressBar;
import android.widget.Toast;
import android.content.Intent;
import android.net.Uri;

/** Distinct Android apps for the three DG POS roles. All call the same secured Neon API. */
public class MainActivity extends Activity {
    private static final String HOST = "dg-pos-business.vercel.app";
    private WebView webView;
    private ProgressBar progress;

    @SuppressLint("SetJavaScriptEnabled")
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().setStatusBarColor(Color.rgb(20, 41, 59));
        getWindow().setNavigationBarColor(Color.rgb(20, 41, 59));
        FrameLayout layout = new FrameLayout(this);
        webView = new WebView(this);
        webView.setOverScrollMode(View.OVER_SCROLL_NEVER);
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true); // persisted POS session and offline outbox
        settings.setDatabaseEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);
        settings.setSupportMultipleWindows(false);
        settings.setCacheMode(WebSettings.LOAD_DEFAULT);
        webView.setHorizontalScrollBarEnabled(false);
        CookieManager.getInstance().setAcceptCookie(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, false);
        progress = new ProgressBar(this);
        FrameLayout.LayoutParams p = new FrameLayout.LayoutParams(88,88);
        p.gravity = android.view.Gravity.CENTER;
        layout.addView(webView);
        layout.addView(progress,p);
        webView.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri url=request.getUrl();
                if("https".equals(url.getScheme()) && HOST.equals(url.getHost())) return false;
                if("http".equals(url.getScheme()) || "https".equals(url.getScheme())) {
                    try {startActivity(new Intent(Intent.ACTION_VIEW,url));} catch(Exception ignored) {}
                }
                return true;
            }
            @Override public void onPageFinished(WebView view,String url){progress.setVisibility(View.GONE);}
            @Override public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if(request.isForMainFrame()) {
                    progress.setVisibility(View.GONE);
                    Toast.makeText(MainActivity.this,"Could not load DG POS. Check your data and reconnect.",Toast.LENGTH_LONG).show();
                }
            }
        });
        webView.setWebChromeClient(new WebChromeClient() {
            @Override public boolean onJsConfirm(WebView view,String url,String message,JsResult result){
                new AlertDialog.Builder(MainActivity.this).setMessage(message)
                    .setPositiveButton("Confirm",(dialog,which)->result.confirm())
                    .setNegativeButton("Cancel",(dialog,which)->result.cancel())
                    .setOnCancelListener(dialog->result.cancel()).show();
                return true;
            }
            @Override public boolean onJsAlert(WebView view,String url,String message,JsResult result){
                new AlertDialog.Builder(MainActivity.this).setMessage(message)
                    .setPositiveButton("OK",(dialog,which)->result.confirm())
                    .setOnCancelListener(dialog->result.confirm()).show();
                return true;
            }
        });
        setContentView(layout);
        webView.loadUrl(BuildConfig.ENTRY_URL);
    }
    @Override public void onBackPressed(){
        if(webView!=null && webView.canGoBack()) webView.goBack();
        else new AlertDialog.Builder(this).setMessage("Close DG POS?")
           .setNegativeButton("Stay",(d,w)->{})
           .setPositiveButton("Exit",(d,w)->finish()).show();
    }
    @Override protected void onDestroy(){
        if(webView!=null){webView.destroy();webView=null;}
        super.onDestroy();
    }
}
