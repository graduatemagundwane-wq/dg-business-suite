"""Real Yola production activation -> signed local offline -> reconciliation -> suspension -> expiry -> renewal.
Disposable QA business, registered via the normal web API, requires DG Master Control approval.
No production secrets are printed or embedded in this script.
"""
from __future__ import annotations
import base64
import hashlib
import http.cookiejar
import json
import os
import secrets
import sys
import tempfile
import time
import uuid
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

CLOUD='https://yola-onboarding.vercel.app'
STATE=Path(os.environ.get('RUNNER_TEMP',tempfile.gettempdir()))/'yola-live-qa-phase.json'
PREFIX='YOLA RELEASE QA'
DEVICE_TIMEOUT=10

def call(url, payload=None, jar=None):
    opening=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar)) if jar is not None else urllib.request.build_opener()
    method='POST' if payload is not None else 'GET'
    data=json.dumps(payload).encode() if payload is not None else None
    request=urllib.request.Request(url,data=data,headers={'Content-Type':'application/json','User-Agent':'Yola-QA-Release/1.0'},method=method)
    try:
        with opening.open(request,timeout=DEVICE_TIMEOUT) as r:
            body=r.read(100_000)
            return r.status,json.loads(body)
    except urllib.error.HTTPError as e:
        body=e.read(100_000)
        try:obj=json.loads(body)
        except Exception:obj={'error':body.decode(errors='replace')[:180]}
        return e.code,obj


def check(ok,message):
    if not ok:raise AssertionError(message)
    print('PASS '+message,flush=True)


def verify_public_key(key):
    status,remote=call(CLOUD+'/api/public-key')
    check(status==200 and remote.get('public_key')==key,'live production public key equals pinned Windows public key')


def spin(note,predicate,timeout=700,interval=4):
    print('WAIT '+note,flush=True)
    end=time.monotonic()+timeout
    while time.monotonic()<end:
        try:
            if predicate():return True
        except (urllib.error.URLError,TimeoutError,ValueError):pass
        time.sleep(interval)
    raise TimeoutError('Timed out waiting for Master Control '+note)


def main():
    # Truly disposable credentials remain in memory only, never in source or CI logs.
    account='yola-release-qa-'+uuid.uuid4().hex[:12]+'@example.invalid'
    password=secrets.token_urlsafe(28)+'Aa1'
    owner='DG Release QA Owner'
    company=PREFIX+' '+uuid.uuid4().hex[:8].upper()
    jar=http.cookiejar.CookieJar()
    status,registered=call(CLOUD+'/api/register',{'business':company,'name':owner,'email':account,'password':password,'phone':''},jar)
    check(status==201 and registered.get('businessCode','').startswith('YOLA-'),'registration created a genuine pending Master Control business')
    code=registered['businessCode']
    STATE.write_text(json.dumps({'business':company,'code':code,'stage':'registered','utc':datetime.now(timezone.utc).isoformat()}))
    print('QA REGISTRATION CODE: '+code,flush=True)  # not a credential; used for approval+cleanup only
    status,user=call(CLOUD+'/api/me',jar=jar)
    check(status==200 and user.get('user',{}).get('license',{}).get('active') is False,'new installation is locked before approval')
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'desktop'))
    os.environ['DG_POS_DATA_DIR']=str(Path(os.environ.get('RUNNER_TEMP',tempfile.gettempdir()))/('yola-live-qa-'+uuid.uuid4().hex[:7]))
    import local_server, offline_web
    from fastapi.testclient import TestClient
    pin=local_server.trusted_license_public_key()
    verify_public_key(pin)
    native=TestClient(local_server.app)
    args={'business_name':company,'owner_name':owner,'phone':'+263000000','owner_pin':'387159','existing_registration_id':code,'email':account,'password':password}
    reply=native.post('/api/activation/request',json=args)
    check(reply.status_code==403,'Master Control prevents desktop device enrollment while business is pending')
    def approved():
        st,u=call(CLOUD+'/api/me',jar=jar)
        return st==200 and u.get('user',{}).get('license',{}).get('active') is True
    spin('Activate only the QA business in DG Tech Master Control',approved,timeout=900)
    status,remote=call(CLOUD+'/api/me',jar=jar)
    check(remote['user']['businessCode']==code,'Master Control approval is bound to the original installation')
    reply=native.post('/api/activation/request',json=args)
    check(reply.status_code==200 and reply.json().get('status')=='pending','approved owner can enroll this Windows device')
    claim=native.post('/api/activation/check',json={})
    check(claim.status_code==200 and claim.json().get('active') is True,'live signer authorizes device with signed licence and lease')
    lic=local_server.read_license()
    check(local_server.cached_license_valid(),'native SQLite stores verifiable signed offline licence')
    payload=lic['license_token'].split('.')[0]
    signed_info=json.loads(base64.urlsafe_b64decode(payload+'='*(-len(payload)%4)))
    check(signed_info.get('master_installation_id') and signed_info.get('device_id')==local_server.DEVICE_ID,'device licence is bound to real Master installation and device')
    client=TestClient(offline_web.app)
    signed_in=client.post('/api/login',json={'email':account,'password':password})
    check(signed_in.status_code==200,'first owner login verified against the live cloud')
    # Disable network solely inside the local POS, not at the Master Control server.
    source_online=offline_web.cloud_json
    def disconnected(*args,**kwargs):raise OSError('Simulated shop internet outage')
    offline_web.cloud_json=disconnected
    client.post('/api/logout',json={})
    offline_web.verify_online_password=lambda *args,**kwargs: (_ for _ in ()).throw(OSError('Shop internet unavailable'))
    r=client.post('/api/login',json={'email':account,'password':password})
    check(r.status_code==200,'previously verified owner signs in without internet')
    r=client.post('/api/pos/product',json={'name':'Yola QA bottled water','category':'Beverages','price_cents':200,'cost_cents':60,'stock_qty':11,'min_stock':5})
    check(r.status_code==200 and r.json().get('id'),'local SKU/inventory can be created offline')
    product=r.json()['id']
    checkout={'items':[{'id':product,'qty':7}],'idempotency_key':uuid.uuid4().hex+'abc','payment_method':'cash','discount_cents':0,'customer_name':'QA shopper'}
    sale=client.post('/api/pos/checkout',json=checkout)
    check(sale.status_code==200 and sale.json().get('sale',{}).get('id'),'true offline cash checkout commits sale to local SQLite')
    check(client.get('/api/pos/accounts').json()['trial_balance']['balanced'],'offline accounting trial balance reconciles after sale')
    status=client.get('/api/sync/status')
    check(status.status_code==200 and status.json().get('pending',0)>=2,'unsubmitted offline events remain durable in local retry queue')
    pending_before=status.json()['pending']
    offline_web.cloud_json=source_online
    sync=client.post('/api/sync/flush',json={})
    check(sync.status_code==200 and sync.json().get('pending')==0 and sync.json().get('reconciled',0)>=2,'reconnect commits product and sale to live cloud without losing queue entries')
    again=client.post('/api/sync/flush',json={})
    check(again.status_code==200 and again.json().get('reconciled')==0,'sync retries do not duplicate previously acknowledged events')
    STATE.write_text(json.dumps({'business':company,'code':code,'stage':'synced','pending_before':pending_before,'utc':datetime.now(timezone.utc).isoformat()}))
    print('WAIT Master Control suspension of QA account (after first cloud sync)',flush=True)
    def suspended():
        st,obj=call(CLOUD+'/api/license/verify',{'device_id':local_server.DEVICE_ID,'license_token':lic['license_token']})
        return st==200 and obj.get('active') is False and obj.get('status') in ('suspended','inactive','revoked')
    spin('Suspend only the QA business',suspended,timeout=900,interval=5)
    local=native.post('/api/license/verify',json={})
    check(local.status_code==200 and local.json().get('active') is False,'online revocation locks signed device on next online verification')
    check(not local_server.cached_license_valid(),'revoked Windows device cannot continue offline after it learns of suspension')
    blocked=client.get('/api/pos/products')
    check(blocked.status_code==403,'suspended device cannot open its local stock or sell')
    print('WAIT Master Control expiry of QA business (active status, expiry in past)',flush=True)
    def expired():
        st,obj=call(CLOUD+'/api/license/verify',{'device_id':local_server.DEVICE_ID,'license_token':lic['license_token']})
        return st==200 and obj.get('active') is False and obj.get('status') not in ('suspended','inactive','revoked')
    spin('Set QA business active with expiry in the past',expired,timeout=900,interval=5)
    check(not local_server.cached_license_valid(),'expired signed local licence stays locked')
    print('WAIT Master Control renewal of QA business',flush=True)
    def renewed():
        st,obj=call(CLOUD+'/api/license/verify',{'device_id':local_server.DEVICE_ID,'license_token':lic['license_token']})
        return st==200 and obj.get('active') is True and obj.get('status')=='active' and 'lease_token' in obj
    spin('Renew only the QA business with a future expiry',renewed,timeout=900,interval=5)
    local=native.post('/api/license/verify',json={})
    check(local.status_code==200 and local.json().get('active') is True,'renewal restores a fresh signed offline lease')
    check(local_server.cached_license_valid(),'reconnected device unlocks after verified Master Control renewal')
    check(client.get('/api/pos/products').status_code==200,'offline store inventory reopens after renewal')
    STATE.write_text(json.dumps({'business':company,'code':code,'stage':'complete','utc':datetime.now(timezone.utc).isoformat()}))
    print('ALL FOUR PRODUCTION YOLA RELEASE SCENARIOS PASSED; QA REGISTRATION CODE '+code,flush=True)

if __name__=='__main__':
    try:main()
    except Exception as e:
        print('E2E VALIDATION FAILURE: '+type(e).__name__+' '+str(e)[:450],file=sys.stderr,flush=True)
        raise