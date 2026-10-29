package zw.co.pashauto.erp;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.DownloadManager;
import android.content.Intent;
import android.content.Context;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.view.View;
import android.view.ViewGroup;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.webkit.CookieManager;
import android.webkit.DownloadListener;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.SslErrorHandler;
import android.net.http.SslError;

public class MainActivity extends Activity {
 private WebView web;
 private ValueCallback<Uri[]> fileCallback;
 private static final int FILE_PICKER = 73;
 private String companyUrl="";
 @Override public void onCreate(Bundle state){super.onCreate(state);
   companyUrl=getPreferences(0).getString("pash_company_url","");
   LinearLayout layout=new LinearLayout(this);layout.setOrientation(LinearLayout.VERTICAL);
   ProgressBar progress=new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal);progress.setIndeterminate(true);progress.setVisibility(View.GONE);
   layout.addView(progress,new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,4));
   web=new WebView(this);layout.addView(web,new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,0,1));setContentView(layout);
   web.getSettings().setJavaScriptEnabled(true);web.getSettings().setDomStorageEnabled(true);
   web.getSettings().setAllowFileAccess(false);web.getSettings().setAllowContentAccess(true);
   web.getSettings().setMixedContentMode(android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW);
   if(android.os.Build.VERSION.SDK_INT>=26) web.getSettings().setSafeBrowsingEnabled(true);
   CookieManager.getInstance().setAcceptCookie(true);
   web.setWebViewClient(new WebViewClient(){
      @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request){Uri uri=request.getUrl();if(uri==null)return false;
       Uri base=Uri.parse(companyUrl);
       if("https".equalsIgnoreCase(uri.getScheme())&&base.getHost()!=null&&base.getHost().equalsIgnoreCase(uri.getHost()))return false;
       try{startActivity(new Intent(Intent.ACTION_VIEW,uri));}catch(Exception ignored){}return true;}
      @Override public void onReceivedSslError(WebView view,SslErrorHandler handler,SslError error){handler.cancel();new AlertDialog.Builder(MainActivity.this).setTitle("Connection not secure").setMessage("The PASH ERP server failed its TLS certificate check. Connection blocked.").setPositiveButton("OK",(d,w)->{}).show();}
   });
   web.setWebChromeClient(new WebChromeClient(){
       @Override public void onProgressChanged(WebView v,int newProgress){progress.setVisibility(newProgress>=100?View.GONE:View.VISIBLE);}
       @Override public boolean onShowFileChooser(WebView v,ValueCallback<Uri[]> cb,FileChooserParams params){if(fileCallback!=null)fileCallback.onReceiveValue(null);fileCallback=cb;try{Intent i=params.createIntent();startActivityForResult(i,FILE_PICKER);return true;}catch(Exception ex){fileCallback=null;return false;}}
   });
   web.setDownloadListener((url,ua,disposition,mime,length)->{try{
      if(!"https".equalsIgnoreCase(Uri.parse(url).getScheme()))throw new IllegalArgumentException("Downloads require HTTPS");
      DownloadManager.Request r=new DownloadManager.Request(Uri.parse(url));
      String cookie=CookieManager.getInstance().getCookie(url);
      if(cookie!=null)r.addRequestHeader("Cookie",cookie);
      r.setMimeType(mime);r.setTitle("PASH ERP document");
      r.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
      r.setDestinationInExternalFilesDir(MainActivity.this,Environment.DIRECTORY_DOWNLOADS,"PASH-"+System.currentTimeMillis()+".pdf");
      ((DownloadManager)getSystemService(Context.DOWNLOAD_SERVICE)).enqueue(r);
   }catch(Exception ex){new AlertDialog.Builder(MainActivity.this).setMessage("Download failed: "+ex.getMessage()).setPositiveButton("OK",null).show();}});
   if(companyUrl.isEmpty())configureServer();else web.loadUrl(companyUrl);
 }
 private void configureServer(){EditText input=new EditText(this);input.setSingleLine(true);input.setText(companyUrl.isEmpty()?"https://":companyUrl);input.setSelectAllOnFocus(true);
  new AlertDialog.Builder(this).setTitle("Connect PASH Auto ERP").setMessage("Enter the secure HTTPS address of PASH Auto's live ERP server.").setView(input).setCancelable(false).setPositiveButton("Connect",(d,w)->{
    String url=input.getText().toString().trim();Uri parsed=Uri.parse(url);
    if(!"https".equalsIgnoreCase(parsed.getScheme())||parsed.getHost()==null||parsed.getUserInfo()!=null){companyUrl="";configureServer();return;}
    companyUrl=url.replaceAll("/+$","");getPreferences(0).edit().putString("pash_company_url",companyUrl).apply();web.loadUrl(companyUrl);
  }).setNegativeButton("Exit",(d,w)->finish()).show();}
 @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);if(request==FILE_PICKER&&fileCallback!=null){fileCallback.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(result,data));fileCallback=null;}}
 @Override public void onBackPressed(){if(web!=null&&web.canGoBack())web.goBack();else new AlertDialog.Builder(this).setTitle("PASH Auto ERP").setItems(new String[]{"Change server address","Exit app","Cancel"},(d,which)->{if(which==0)configureServer();if(which==1)finish();}).show();}
 @Override protected void onDestroy(){if(web!=null){web.destroy();web=null;}super.onDestroy();}
}