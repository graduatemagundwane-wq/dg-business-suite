package zw.co.doublegeetech.tatezdg;

import android.app.Activity;
import android.app.DownloadManager;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.net.ConnectivityManager;
import android.net.NetworkCapabilities;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.Message;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.DownloadListener;
import android.webkit.URLUtil;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

public final class MainActivity extends Activity {
    private static final String HOME = "https://tatez-smart-apply.vercel.app/owner";
    private static final String ALLOWED_HOST = "tatez-smart-apply.vercel.app";
    private WebView browser;
    private LinearLayout errorScreen;
    private ProgressBar loading;
    private FrameLayout page;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setStatusBarColor(Color.rgb(8, 42, 59));
        getWindow().setNavigationBarColor(Color.rgb(8, 42, 59));
        page = new FrameLayout(this);
        browser = new WebView(this);
        browser.setBackgroundColor(Color.WHITE);
        browser.setOverScrollMode(View.OVER_SCROLL_NEVER);
        page.addView(browser, new FrameLayout.LayoutParams(-1, -1));
        configureBrowser();

        loading = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        loading.setMax(100);
        FrameLayout.LayoutParams progress = new FrameLayout.LayoutParams(-1, dp(3));
        progress.gravity = Gravity.TOP;
        page.addView(loading, progress);
        loading.setVisibility(View.GONE);

        buildErrorPanel();
        setContentView(page);
        browser.loadUrl(HOME);
    }

    private void configureBrowser() {
        WebSettings settings = browser.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);
        settings.setSupportMultipleWindows(true);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setBuiltInZoomControls(false);
        settings.setDisplayZoomControls(false);
        settings.setLoadWithOverviewMode(true);
        settings.setUseWideViewPort(true);
        if (Build.VERSION.SDK_INT >= 26) settings.setSafeBrowsingEnabled(true);

        CookieManager cookies = CookieManager.getInstance();
        cookies.setAcceptCookie(true);
        cookies.setAcceptThirdPartyCookies(browser, false);

        browser.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView webView, WebResourceRequest request) {
                Uri url = request.getUrl();
                if (trusted(url)) {
                    if (downloadEndpoint(url)) {
                        download(url.toString(), "TATEZ-application.pdf", "application/pdf");
                        return true;
                    }
                    return false;
                }
                external(url);
                return true;
            }

            @Override
            public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
                hideError();
                loading.setProgress(8);
                loading.setVisibility(View.VISIBLE);
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                loading.setVisibility(View.GONE);
                CookieManager.getInstance().flush();
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame()) showError();
            }

            @Override
            public void onReceivedHttpError(WebView view, WebResourceRequest request,
                                            android.webkit.WebResourceResponse response) {
                if (request.isForMainFrame() && response.getStatusCode() >= 500) showError();
            }
        });
        browser.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onProgressChanged(WebView view, int newProgress) {
                loading.setProgress(newProgress);
                if (newProgress >= 100) loading.setVisibility(View.GONE);
            }
            @Override
            public boolean onCreateWindow(WebView parent, boolean isDialog, boolean isUserGesture, Message msg) {
                WebView popup = new WebView(MainActivity.this);
                popup.setWebViewClient(new WebViewClient() {
                    @Override
                    public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                        Uri url = request.getUrl();
                        if (trusted(url) && downloadEndpoint(url)) {
                            download(url.toString(), "TATEZ-application.pdf", "application/pdf");
                        } else if (trusted(url)) {
                            browser.loadUrl(url.toString());
                        } else {
                            external(url);
                        }
                        view.postDelayed(view::destroy, 400);
                        return true;
                    }
                });
                ((WebView.WebViewTransport) msg.obj).setWebView(popup);
                msg.sendToTarget();
                return true;
            }
        });
        browser.setDownloadListener(new DownloadListener() {
            @Override
            public void onDownloadStart(String url, String userAgent, String disposition,
                                        String mimeType, long contentLength) {
                Uri uri = Uri.parse(url);
                if (trusted(uri)) {
                    String name = URLUtil.guessFileName(url, disposition, mimeType);
                    download(url, name, mimeType);
                } else {
                    external(uri);
                }
            }
        });
    }

    private boolean trusted(Uri uri) {
        return "https".equalsIgnoreCase(uri.getScheme())
                && ALLOWED_HOST.equalsIgnoreCase(uri.getHost());
    }

    private boolean downloadEndpoint(Uri uri) {
        return trusted(uri)
                && "/api/index".equals(uri.getPath())
                && ("download".equals(uri.getQueryParameter("action"))
                    || "pdf".equals(uri.getQueryParameter("action")));
    }

    private void external(Uri uri) {
        if (!"https".equalsIgnoreCase(uri.getScheme())) {
            Toast.makeText(this, "Only secure links can be opened", Toast.LENGTH_SHORT).show();
            return;
        }
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE));
        } catch (Exception e) {
            Toast.makeText(this, "No browser available to open the link", Toast.LENGTH_SHORT).show();
        }
    }

    private void download(String url, String filename, String mimeType) {
        if (Build.VERSION.SDK_INT < 29) {
            Toast.makeText(this, "Document downloads require Android 10 or later", Toast.LENGTH_LONG).show();
            return;
        }
        try {
            DownloadManager.Request request = new DownloadManager.Request(Uri.parse(url));
            String cookies = CookieManager.getInstance().getCookie(url);
            if (cookies != null) request.addRequestHeader("Cookie", cookies);
            request.addRequestHeader("User-Agent", browser.getSettings().getUserAgentString());
            request.setTitle("TATEZ private document");
            request.setDescription("Downloading to Downloads");
            request.setMimeType(mimeType == null || mimeType.isEmpty() ? "application/octet-stream" : mimeType);
            request.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
            request.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, safeFilename(filename));
            ((DownloadManager) getSystemService(Context.DOWNLOAD_SERVICE)).enqueue(request);
            Toast.makeText(this, "Download started", Toast.LENGTH_SHORT).show();
        } catch (Exception e) {
            Toast.makeText(this, "Unable to start download. Please retry.", Toast.LENGTH_LONG).show();
        }
    }

    private String safeFilename(String name) {
        String cleaned = name == null ? "" : name.replaceAll("[^a-zA-Z0-9._-]", "_");
        if (cleaned.isEmpty() || cleaned.equals(".") || cleaned.equals(".."))
            cleaned = "TATEZ-document.pdf";
        return cleaned;
    }

    private void buildErrorPanel() {
        errorScreen = new LinearLayout(this);
        errorScreen.setOrientation(LinearLayout.VERTICAL);
        errorScreen.setGravity(Gravity.CENTER);
        errorScreen.setPadding(dp(26), dp(26), dp(26), dp(26));
        errorScreen.setBackgroundColor(Color.WHITE);
        TextView headline = new TextView(this);
        headline.setText(R.string.connection_issue);
        headline.setTextSize(23);
        headline.setTextColor(Color.rgb(8, 42, 59));
        headline.setGravity(Gravity.CENTER);
        headline.setTypeface(null, 1);
        errorScreen.addView(headline);
        TextView details = new TextView(this);
        details.setText(R.string.check_data);
        details.setTextSize(15);
        details.setTextColor(Color.rgb(94, 116, 126));
        details.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams detailsMargin = new LinearLayout.LayoutParams(-1, -2);
        detailsMargin.topMargin = dp(14);
        detailsMargin.bottomMargin = dp(20);
        errorScreen.addView(details, detailsMargin);
        Button retry = new Button(this);
        retry.setText(R.string.reload);
        retry.setOnClickListener(v -> {
            hideError();
            browser.loadUrl(HOME);
        });
        errorScreen.addView(retry);
        FrameLayout.LayoutParams panel = new FrameLayout.LayoutParams(-1, -1);
        page.addView(errorScreen, panel);
        errorScreen.setVisibility(View.GONE);
    }
    private int dp(int n) { return Math.round(n * getResources().getDisplayMetrics().density); }
    private void showError() { if (errorScreen != null) errorScreen.setVisibility(View.VISIBLE); }
    private void hideError() { if (errorScreen != null) errorScreen.setVisibility(View.GONE); }

    @Override
    public void onBackPressed() {
        if (errorScreen.getVisibility() == View.VISIBLE) {
            hideError();
            if (browser.canGoBack()) browser.goBack();
            else browser.loadUrl(HOME);
        } else if (browser.canGoBack()) {
            browser.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        CookieManager.getInstance().flush();
        browser.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        browser.onResume();
    }
}
