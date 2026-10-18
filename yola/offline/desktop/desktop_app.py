"""Yola Premium Offline Windows shell — local API, never a hosted web wrapper."""
import json,os,socket,sys,tempfile,time,traceback,threading,urllib.request,webbrowser
from pathlib import Path
import uvicorn
from hybrid_app import app
from offline_web import STATIC_DIR

def free_port():
    with socket.socket(socket.AF_INET,socket.SOCK_STREAM) as sock:
        sock.bind(('127.0.0.1',0));return sock.getsockname()[1]

def server(port):
    try:
        config=uvicorn.Config(app,host='127.0.0.1',port=port,log_level='error',access_log=False,log_config=None,loop='asyncio',http='h11',ws='none')
        uvicorn.Server(config).run()
    except Exception:
        Path(tempfile.gettempdir(),'yola_offline_error.log').write_text(traceback.format_exc(),encoding='utf8')

def wait(port):
    deadline=time.time()+20
    while time.time()<deadline:
        try:
            with urllib.request.urlopen(f'http://127.0.0.1:{port}/api/health',timeout=1) as r:
                if json.load(r).get('localData'):return
        except Exception:pass
        time.sleep(.17)
    raise RuntimeError('Yola offline service could not start; check local antivirus and diagnostic logs.')

class DeviceBridge:
    """Windows peripheral detection, no unsupported universal device claims."""
    def list_devices(self):
        if sys.platform!='win32':return {'supported':False,'printers':[],'devices':[]}
        import subprocess
        printers=[];devices=[]
        try:
            import win32print
            printers=[p[2] for p in win32print.EnumPrinters(win32print.PRINTER_ENUM_LOCAL|win32print.PRINTER_ENUM_CONNECTIONS)]
        except Exception:pass
        try:
            script="Get-PnpDevice -PresentOnly | Where-Object {$_.Class -in @('HIDClass','USB','Ports','Printer','Keyboard','Mouse','Bluetooth')} | Select-Object Class,FriendlyName,Status | ConvertTo-Json -Compress"
            proc=subprocess.run(['powershell','-NoProfile','-NonInteractive','-Command',script],capture_output=True,timeout=12,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            if proc.returncode==0:
                j=json.loads(proc.stdout.decode('utf-8-sig',errors='replace'))
                devices=j if isinstance(j,list) else [j]
        except Exception:pass
        return {'supported':True,'printers':printers[:100],'devices':devices[:150]}

def main():
    for p in ('index.html','workspace.html','pos.js','pos.css','premium.css','device-activation.html'):
        if not (STATIC_DIR/p).is_file():raise RuntimeError('Missing Yola UI: '+p)
    port=free_port();threading.Thread(target=server,args=(port,),daemon=True).start();wait(port)
    if '--self-test' in sys.argv:
        # The packaged build passes only if its complete offline server started.
        out=Path(tempfile.gettempdir(),'yola_offline_premium_selftest.log')
        out.write_text('PASS',encoding='utf-8');return 0
    url=f'http://127.0.0.1:{port}/'
    try:
        import webview
        webview.create_window('Yola — Powered by Double Gee Tech',url,width=1440,height=900,min_size=(1000,680),background_color='#f4f7fa',js_api=DeviceBridge())
        webview.start(gui='edgechromium',debug=False,private_mode=False)
    except Exception:
        webbrowser.open(url)
        try:
            while True:time.sleep(3600)
        except KeyboardInterrupt:pass
    return 0
if __name__=='__main__':
    try:sys.exit(main())
    except Exception as ex:
        out=Path(tempfile.gettempdir(),'yola_offline_premium_selftest.log')
        out.write_text(traceback.format_exc(),encoding='utf-8')
        if '--self-test' not in sys.argv:
            try:
                import ctypes
                ctypes.windll.user32.MessageBoxW(None,str(ex),'Yola startup error',0x10)
            except Exception:pass
        raise