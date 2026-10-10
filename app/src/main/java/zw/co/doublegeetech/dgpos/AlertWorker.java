package zw.co.doublegeetech.dgpos;

import android.content.Context;
import androidx.annotation.NonNull;
import androidx.work.Worker;
import androidx.work.WorkerParameters;
import org.json.JSONArray;
import org.json.JSONObject;
import java.net.URL;
import java.net.HttpURLConnection;
import java.io.InputStream;
import java.io.ByteArrayOutputStream;
import java.util.HashSet;
import java.util.Set;

public class AlertWorker extends Worker {
  public AlertWorker(@NonNull Context c,@NonNull WorkerParameters p){super(c,p);}
  @NonNull @Override public Result doWork(){
    Context ctx=getApplicationContext();String token=NotificationHelper.getToken(ctx);
    if(token==null || token.isEmpty())return Result.success();
    HttpURLConnection conn=null;
    try {
      conn=(HttpURLConnection)new URL(NotificationHelper.HOST).openConnection();
      conn.setRequestMethod("GET");conn.setConnectTimeout(8000);conn.setReadTimeout(8000);
      conn.setRequestProperty("Authorization","Bearer "+token);
      conn.setRequestProperty("Accept","application/json");
      int status=conn.getResponseCode();
      if(status==401 || status==403){
        NotificationHelper.postOnce(ctx,"account-needs-attention","POS account needs attention","Your business access was changed. Open the app and contact the administrator.");
        return Result.success();
      }
      if(status!=200)return Result.retry();
      InputStream in=conn.getInputStream();ByteArrayOutputStream bytes=new ByteArrayOutputStream();byte[] b=new byte[4096];int count;
      while((count=in.read(b))>=0 && bytes.size()<100000)bytes.write(b,0,count);in.close();
      JSONArray arr=new JSONObject(bytes.toString("UTF-8")).optJSONArray("alerts");
      if(arr==null)return Result.success();
      Set<String> active=new HashSet<>();
      for(int i=0;i<Math.min(arr.length(),20);i++){
        JSONObject a=arr.getJSONObject(i);String id=a.optString("id"),title=a.optString("title"),message=a.optString("message");
        if(id.length()>0){active.add(id);NotificationHelper.postOnce(ctx,id,title,message);}
      }
      NotificationHelper.markResolved(ctx,active);
      return Result.success();
    }catch(Exception e){return Result.retry();}finally{if(conn!=null)conn.disconnect();}
  }
}
