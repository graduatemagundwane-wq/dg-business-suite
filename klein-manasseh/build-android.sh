#!/usr/bin/env bash
set -euo pipefail
ROOT="$(pwd)"
CACHE="$ROOT/.km-apk-cache"
WORK="$ROOT/.km-apk-build"
OUT="$ROOT/klein-manasseh/android-site"
mkdir -p "$CACHE/android-sdk/cmdline-tools" "$WORK" "$OUT"
if ! (command -v java >/dev/null 2>&1 && java -version 2>&1 | grep -qE '"(17|18|19|2[0-9])\.'); then
  curl -fsSL --retry 3 "https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse" -o "$CACHE/jdk.tar.gz"
  mkdir -p "$CACHE/java"
  tar -xzf "$CACHE/jdk.tar.gz" -C "$CACHE/java" --strip-components=1
  export JAVA_HOME="$CACHE/java"
  export PATH="$JAVA_HOME/bin:$PATH"
fi
export ANDROID_HOME="$CACHE/android-sdk"
if [ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
  curl -fsSL --retry 3 "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" -o "$CACHE/cmdtools.zip"
  unzip -qo "$CACHE/cmdtools.zip" -d "$ANDROID_HOME/cmdline-tools"
  mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
fi
yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_HOME" --licenses >/dev/null || true
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_HOME" "platforms;android-35" "build-tools;35.0.0"
base64 -d "$ROOT/klein-manasseh/android-native.tar.gz.b64" | tar -xzf - -C "$WORK"
python3 - "$WORK" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); java=p/'src/zw/co/doublegeetech/kleinmanasseh/MainActivity.java'
src=java.read_text()
old='serverUrl=getPreferences(MODE_PRIVATE).getString("server","");'
new='serverUrl=getPreferences(MODE_PRIVATE).getString("server","https://klein-manasseh-dg-chat-qa.onrender.com");'
assert old in src, 'Missing original startup setting'
java.write_text(src.replace(old,new))
mf=p/'AndroidManifest.xml'
s=mf.read_text()
assert 'android:versionCode="1"' in s
mf.write_text(s.replace('android:versionCode="1"','android:versionCode="2"').replace('android:versionName="1.0.0"','android:versionName="1.1.0"'))
print('Android startup loads Klein Manasseh DG Chat directly')
PY
SDK="$ANDROID_HOME/build-tools/35.0.0"
mkdir -p "$WORK/classes" "$WORK/dex"
"$SDK/aapt" package -f -M "$WORK/AndroidManifest.xml" -S "$WORK/res" -A "$WORK/assets" -I "$ANDROID_HOME/platforms/android-35/android.jar" -F "$WORK/unsigned.apk"
javac -source 8 -target 8 -Xlint:-options -cp "$ANDROID_HOME/platforms/android-35/android.jar" -d "$WORK/classes" "$WORK/src/zw/co/doublegeetech/kleinmanasseh/MainActivity.java"
"$SDK/d8" --lib "$ANDROID_HOME/platforms/android-35/android.jar" --output "$WORK/dex" $(find "$WORK/classes" -name '*.class')
(cd "$WORK/dex"; "$SDK/aapt" add "$WORK/unsigned.apk" classes.dex)
"$SDK/zipalign" -f 4 "$WORK/unsigned.apk" "$WORK/aligned.apk"
[ -n "$DG_KM_KEY_B64" ] && [ -n "$DG_KM_KEY_PASS" ] || { echo "Missing signing key configuration"; exit 1; }
printf '%s' "$DG_KM_KEY_B64" | base64 -d > "$WORK/dg-key.p12"
chmod 600 "$WORK/dg-key.p12"
"$SDK/apksigner" sign --ks "$WORK/dg-key.p12" --ks-type PKCS12 --ks-key-alias dg-klein-manasseh --ks-pass env:DG_KM_KEY_PASS --key-pass env:DG_KM_KEY_PASS --out "$OUT/Klein_Manasseh_DG_Chat_v1.1.0.apk" "$WORK/aligned.apk"
"$SDK/apksigner" verify --verbose "$OUT/Klein_Manasseh_DG_Chat_v1.1.0.apk"
"$SDK/aapt" dump badging "$OUT/Klein_Manasseh_DG_Chat_v1.1.0.apk" | head -5
sha256sum "$OUT/Klein_Manasseh_DG_Chat_v1.1.0.apk" > "$OUT/SHA256SUMS.txt"
(cd "$OUT"; python3 -c 'import zipfile; z=zipfile.ZipFile("Klein_Manasseh_DG_Chat_v1.1.0.zip","w",zipfile.ZIP_STORED); z.write("Klein_Manasseh_DG_Chat_v1.1.0.apk"); z.close()')
cat > "$OUT/index.html" <<'EOFHTML'
<!doctype html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Klein Manasseh DG Chat</title><style>body{margin:0;font-family:Arial,sans-serif;background:#f5faf7;color:#003e2f;padding:40px 20px;text-align:center}main{max-width:430px;margin:7vh auto;background:white;border:1px solid #deede5;border-radius:26px;padding:38px 25px;box-shadow:0 10px 40px #05452b12}h1{font-size:25px}p{font-size:15px;color:#687b72;line-height:1.55}a.button{display:block;background:#008d61;color:white;padding:17px;text-decoration:none;border-radius:13px;margin:24px 0 10px;font-weight:bold}a{text-decoration:none;color:#008d61}.small{font-size:12px;color:#7c9186}</style></head><body><main><h1>Klein Manasseh DG Chat</h1><p>Android Application · Version 1.1.0</p><a class="button" href="/Klein_Manasseh_DG_Chat_v1.1.0.apk">Download Android APK</a><a href="/Klein_Manasseh_DG_Chat_v1.1.0.zip">Download APK in ZIP</a><p>This APK opens your school chat web interface directly, without a manual server-address setup. Live WhatsApp requires the school's official Meta connection.</p><p class="small">DOUBLE GEE TECH · AUTOMATE. ENGAGE. GROW.</p></main></body></html>
EOFHTML
rm -f "$WORK/dg-key.p12"
echo "APK BUILD COMPLETE"
ls -lh "$OUT"