"""Browser smoke QA for DG POS activation, login, owner and cashier navigation.

Optional local QA: requires Playwright and a headless Chromium executable. It
starts temporary real cloud and desktop instances and never touches live data.
"""
import base64, json, os, subprocess, sys, tempfile, time, urllib.request, urllib.error
from urllib.parse import urlsplit
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT=Path(__file__).resolve().parents[1]
CLOUD='http://127.0.0.1:19990'; DESKTOP='http://127.0.0.1:19987'

def req(base,path,method='GET',payload=None,headers=None):
    data=json.dumps(payload).encode() if payload is not None else None
    h={'Content-Type':'application/json',**(headers or {})}
    with urllib.request.urlopen(urllib.request.Request(base+path,data=data,headers=h,method=method),timeout=5) as r:return json.load(r)

def wait(url):
    for i in range(90):
        try: return req(url,'/api/health')
        except Exception:time.sleep(.15)
    raise RuntimeError('Server did not start: '+url)

def main():
    with tempfile.TemporaryDirectory(prefix='dgpos-browser-') as tmp:
        td=Path(tmp);ck=td/'c.key'
        cloud_env=os.environ|{'DG_CLOUD_ADMIN_KEY':'browser-smoke-test-only','DG_CLOUD_DB':str(td/'cloud.db'),'DG_LICENSE_KEY_FILE':str(ck),'DG_CLOUD_PORT':'19990','DG_REQUIRE_MASTER_CONTROL':'0'}
        desktop_env=os.environ|{'DG_CLOUD_URL':CLOUD,'DG_POS_DATA_DIR':str(td/'client'),'DG_POS_PORT':'19987'}
        with (td/'cloud.log').open('w') as cl,(td/'client.log').open('w') as dl:
            cp=subprocess.Popen([sys.executable,str(ROOT/'cloud/cloud_server.py')],env=cloud_env,cwd=ROOT,stdout=cl,stderr=subprocess.STDOUT)
            dp=None
            try:
                wait(CLOUD)
                desktop_env['DG_POS_TEST_TRUSTED_PUBLIC_KEY_B64']=req(CLOUD,'/api/public-key')['public_key']
                dp=subprocess.Popen([sys.executable,str(ROOT/'desktop/local_server.py')],env=desktop_env,cwd=ROOT,stdout=dl,stderr=subprocess.STDOUT)
                wait(DESKTOP)
                with sync_playwright() as pw:
                    browser=pw.chromium.launch(headless=True,executable_path=os.getenv('DG_BROWSER_PATH','/usr/bin/chromium'),args=['--no-sandbox','--disable-dev-shm-usage'])
                    page=browser.new_page(viewport={'width':1280,'height':800})
                    # The browser sandbox blocks real navigation in this hosted
                    # environment. Render the original HTML and route fetch via
                    # the Python test harness to the local HTTPS-equivalent API.
                    def test_fetch(url,opt=None):
                        from urllib.parse import urlsplit
                        opt=opt or {}
                        path=urlsplit(url).path
                        if urlsplit(url).query:path+='?'+urlsplit(url).query
                        raw=opt.get('body')
                        if raw is not None and isinstance(raw,str): raw=raw.encode()
                        hdr={'Content-Type':'application/json',**(opt.get('headers') or {})}
                        request=urllib.request.Request(DESKTOP+path,data=raw,method=opt.get('method','GET'),headers=hdr)
                        try:
                            with urllib.request.urlopen(request,timeout=8) as res:
                                return {'status':res.status,'body':res.read().decode('utf-8','replace'),'ctype':res.headers.get('Content-Type','application/json')}
                        except urllib.error.HTTPError as error:
                            return {'status':error.code,'body':error.read().decode('utf-8','replace'),'ctype':error.headers.get('Content-Type','application/json')}
                    page.expose_function('qaFetch',test_fetch)
                    shim="<script>window.fetch=(url,opt={})=>window.qaFetch(url,opt).then(r=>new Response(r.body,{status:r.status,headers:{'Content-Type':r.ctype}}));</script>"
                    errors=[]
                    page.on('pageerror',lambda ex:errors.append(str(ex)))
                    # On the sandboxed about:blank document, browser storage is
                    # prohibited; emulate only localStorage for UI smoke QA.
                    page.evaluate("""() => { const s=new Map();Object.defineProperty(window,'localStorage', {configurable:true,value:{getItem:k=>s.get(k)||null,setItem:(k,v)=>s.set(k,String(v)),removeItem:k=>s.delete(k),clear:()=>s.clear()}}); }""")
                    # about:blank cannot load /static assets. Inline the ORIGINAL PNG
                    # only for browser screenshots so branding QA is representative.
                    brand=base64.b64encode((ROOT/'desktop/static/dg-logo-mark.png').read_bytes()).decode()
                    html=(ROOT/'desktop/static/index.html').read_text().replace('/static/dg-logo-mark.png','data:image/png;base64,'+brand)
                    page.set_content(html.replace('<script>',shim+'<script>',1),wait_until='domcontentloaded')
                    page.wait_for_timeout(500)
                    page.locator('#actBusiness').wait_for(timeout=10000)
                    page.locator('#actBusiness').fill('DG Browser QA Store');page.locator('#actOwner').fill('QA Owner')
                    page.locator('#actPhone').fill('0771234567');page.locator('#actPin').fill('54321');page.get_by_role('button',name='Request activation').click()
                    page.locator('#requestCode').wait_for(timeout=7000);page.wait_for_function("document.querySelector('#requestCode').textContent.startsWith('YL-')",timeout=6000)
                    code=page.locator('#requestCode').text_content().strip()
                    approved=req(CLOUD,f'/api/admin/activations/{code}/approve','POST',{'branch_name':'Main Branch'}, {'X-Admin-Key':'browser-smoke-test-only'})
                    page.get_by_role('button',name='Check Approval & Activate').click()
                    page.locator('#loginUsers .userpick').first.wait_for(timeout=12000)
                    page.locator('#loginUsers .userpick').first.click();page.locator('#loginPin').fill('54321')
                    page.get_by_role('button',name='Open Yola').click();page.locator('#app:not(.hidden)').wait_for(timeout=12000)
                    page.locator('#sideBusiness').wait_for()
                    assert page.locator('#sideBusiness').text_content().strip()=='DG Browser QA Store'
                    assert page.locator('#page-dashboard').is_visible()
                    page.screenshot(path=str(ROOT/'qa-browser-owner.png'),full_page=True)
                    page.locator('[data-page="sell"]').first.click()
                    assert page.locator('#page-sell').is_visible()
                    # Create cashier using the active owner session; then exercise cashier UX.
                    session=page.evaluate('state.session')
                    cashier=req(DESKTOP,'/api/users','POST',{'name':'Cashier QA','role':'cashier','pin':'7416'}, {'X-Session-Token':session})
                    page.evaluate('logoutStaff()');page.locator('#loginUsers .userpick').filter(has_text='Cashier QA').wait_for(timeout=10000)
                    page.locator('#loginUsers .userpick').filter(has_text='Cashier QA').click();page.locator('#loginPin').fill('7416');page.get_by_role('button',name='Open Yola').click()
                    page.wait_for_function("state.user?.role==='cashier' && !document.querySelector('#app').classList.contains('hidden')",timeout=12000)
                    assert page.locator('#page-sell').is_visible()
                    assert not page.locator('#page-money').is_visible()
                    assert not page.locator('.sidebar [data-page="money"]').is_visible()
                    assert not page.locator('.sidebar [data-page="products"]').is_visible()
                    page.evaluate("openPage('money')")
                    assert page.locator('#page-sell').is_visible()
                    assert not errors,errors
                    screenshot=ROOT/'qa-browser-cashier.png'
                    page.screenshot(path=str(screenshot),full_page=True)
                    print(json.dumps({'status':'PASS','cloud_business_id':approved['business_id'],'activations':1,'owner_login':True,'cashier_login':True,'cashier_restricted':True,'javascript_errors':errors,'screenshot':str(screenshot),'owner_screenshot':str(ROOT/'qa-browser-owner.png')},indent=2))
                    browser.close()
            finally:
                
                if dp: dp.terminate()
                cp.terminate()
                for p in (dp,cp):
                    if p is None:continue
                    try:p.wait(timeout=5)
                    except Exception:p.kill()
                cl.flush();dl.flush()
                print('CLIENT_LOG_TAIL:',(td/'client.log').read_text(errors='replace')[-450:] )
if __name__=='__main__':main()