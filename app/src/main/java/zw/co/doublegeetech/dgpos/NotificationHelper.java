package zw.co.doublegeetech.dgpos;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.Manifest;
import android.content.pm.PackageManager;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import java.security.KeyStore;
import java.security.SecureRandom;
import java.util.concurrent.TimeUnit;
import androidx.core.app.NotificationCompat;
import androidx.work.Constraints;
import androidx.work.ExistingPeriodicWorkPolicy;
import androidx.work.NetworkType;
import androidx.work.OneTimeWorkRequest;
import androidx.work.PeriodicWorkRequest;
import androidx.work.WorkManager;

public final class NotificationHelper {
  static final String HOST="https://dg-pos-business.vercel.app/api/attention";
  static final String CHANNEL="dgpos_needs_attention_v1";
  static final String POLL="dgpos_attention_poll";
  private static final String PREFS="dgpos_secure_v1";
  private static final String ALIAS="DG_POS_SESSION_AES_KEY";
  private NotificationHelper(){}
  private static SharedPreferences prefs(Context c){return c.getSharedPreferences(PREFS,Context.MODE_PRIVATE);}
  static void createChannel(Context c){
    if(Build.VERSION.SDK_INT>=26){
      NotificationChannel channel=new NotificationChannel(CHANNEL,"DG POS • Needs attention",NotificationManager.IMPORTANCE_HIGH);
      channel.setDescription("Low stock, pending approvals and important POS alerts");
      ((NotificationManager)c.getSystemService(Context.NOTIFICATION_SERVICE)).createNotificationChannel(channel);
    }
  }
  private static SecretKey key() throws Exception {
    KeyStore ks=KeyStore.getInstance("AndroidKeyStore");ks.load(null);
    if(ks.containsAlias(ALIAS))return ((KeyStore.SecretKeyEntry)ks.getEntry(ALIAS,null)).getSecretKey();
    KeyGenerator g=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore");
    g.init(new KeyGenParameterSpec.Builder(ALIAS,KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT)
      .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
      .setKeySize(256).build());return g.generateKey();
  }
  static void saveToken(Context c,String token){try {
    byte[] iv=new byte[12];new SecureRandom().nextBytes(iv);
    Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.ENCRYPT_MODE,key(),new GCMParameterSpec(128,iv));
    String enc=Base64.encodeToString(cipher.doFinal(token.getBytes("UTF-8")),Base64.NO_WRAP);
    prefs(c).edit().putString("token",enc).putString("iv",Base64.encodeToString(iv,Base64.NO_WRAP)).apply();
  }catch(Exception ignored){} }
  static String getToken(Context c){try{
    String raw=prefs(c).getString("token",null),iv=prefs(c).getString("iv",null);if(raw==null||iv==null)return null;
    Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.DECRYPT_MODE,key(),new GCMParameterSpec(128,Base64.decode(iv,Base64.NO_WRAP)));
    return new String(cipher.doFinal(Base64.decode(raw,Base64.NO_WRAP)),"UTF-8");
  }catch(Exception e){return null;} }
  static void clearSession(Context c){prefs(c).edit().clear().apply();WorkManager.getInstance(c).cancelUniqueWork(POLL);}
  static void schedule(Context c){
    Constraints constraints=new Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build();
    PeriodicWorkRequest request=new PeriodicWorkRequest.Builder(AlertWorker.class,15,TimeUnit.MINUTES)
        .setConstraints(constraints).build();
    WorkManager.getInstance(c).enqueueUniquePeriodicWork(POLL,ExistingPeriodicWorkPolicy.KEEP,request);
    runNow(c);
  }
  static void runNow(Context c){ if(getToken(c)!=null){WorkManager.getInstance(c).enqueue(new OneTimeWorkRequest.Builder(AlertWorker.class).build());}}
  static void postOnce(Context c,String id,String title,String message){
    if(id.length()>200||title.length()>120||message.length()>400)return;
    if(Build.VERSION.SDK_INT>=33 && c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED)return;
    // One notification per alert state, notified again if alert was resolved then reappeared.
    SharedPreferences p=prefs(c);
    String hash=Integer.toHexString((id+"|"+message).hashCode());
    if(hash.equals(p.getString("seen_"+id,null)))return;
    p.edit().putString("seen_"+id,hash).apply();
    createChannel(c);
    Intent open=new Intent(c,MainActivity.class);open.setFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP|Intent.FLAG_ACTIVITY_SINGLE_TOP);
    PendingIntent pending=PendingIntent.getActivity(c,0,open,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
    NotificationCompat.Builder n=new NotificationCompat.Builder(c,CHANNEL)
      .setSmallIcon(android.R.drawable.ic_dialog_alert).setContentTitle(title).setContentText(message)
      .setStyle(new NotificationCompat.BigTextStyle().bigText(message))
      .setAutoCancel(true).setPriority(NotificationCompat.PRIORITY_HIGH).setContentIntent(pending);
    ((NotificationManager)c.getSystemService(Context.NOTIFICATION_SERVICE)).notify(id.hashCode(),n.build());
  }
  static void markResolved(Context c,java.util.Set<String> activeIds){
    SharedPreferences p=prefs(c);SharedPreferences.Editor e=p.edit();
    for(String k:p.getAll().keySet())if(k.startsWith("seen_")&&!activeIds.contains(k.substring(5)))e.remove(k);
    e.apply();
  }
}
