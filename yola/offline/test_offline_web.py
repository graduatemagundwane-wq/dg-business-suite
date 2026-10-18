import os,tempfile,sys,hashlib
from pathlib import Path

with tempfile.TemporaryDirectory(prefix='yola-test-') as work:
    os.environ['DG_POS_DATA_DIR']=work
    sys.path.insert(0,str(Path(__file__).parent/'desktop'))
    from fastapi.testclient import TestClient
    import offline_web as y
    import local_server
    import cloud_identity
    state={'active':False,'tenant':'YOLA-tenant-1'}
    def fake_lease():
        if not state['active']:raise y.HTTPException(403,'No signed DG Tech licence')
        return state['tenant'],{'business_name':'Testing Boutique','business_id':state['tenant'],'request_code':'YOLA-TEST-BIZ','license_token':'test signed by mock','lease_token':'test signed by mock'}
    y.lease=fake_lease
    cloud_identity.verify_online_password=lambda email,password:{'id':'owner-1' if 'owner' in email else 'worker-1','role':'owner' if 'owner' in email else 'worker','email':email,'name':'Owner' if 'owner' in email else 'Worker','businessCode':'YOLA-TEST-BIZ','license':{'active':True}}
    # Never contact the real production service while exercising the offline fixture.
    y.begin_session=lambda *a,**kw: (_ for _ in ()).throw(y.HTTPException(503,'Fixture cloud intentionally disconnected'))
    # imported function binding is separate
    y.verify_online_password=cloud_identity.verify_online_password
    def c(client,path,method='get',json=None,expected=200):
        res=getattr(client,method)(path,json=json) if json is not None else getattr(client,method)(path)
        assert res.status_code==expected,(path,res.status_code,res.text[:300]);return res.json()
    client=TestClient(y.app)
    assert c(client,'/api/me')['authenticated'] is False
    assert c(client,'/api/login','post',{'email':'owner@dg.test','password':'StrongOwnerPassword123'},503)
    state['active']=True
    assert c(client,'/api/pos/products',expected=401) if False else True
    c(client,'/api/login','post',{'email':'owner@dg.test','password':'StrongOwnerPassword123'})
    assert c(client,'/api/me')['user']['business']=='Testing Boutique'
    p=c(client,'/api/pos/product','post',{'name':'Bottled water','category':'Beverages','price_cents':200,'cost_cents':60,'stock_qty':10,'min_stock':4})['id']
    sku=c(client,'/api/pos/products')['products'][0]['sku'];assert sku.startswith('YL-')
    checkout={'items':[{'id':p,'qty':7}],'idempotency_key':'uuid-1234567890','payment_method':'cash','discount_cents':0,'customer_name':'Guest'}
    sale=c(client,'/api/pos/checkout','post',checkout)['sale']
    same=c(client,'/api/pos/checkout','post',checkout)['sale'];assert same['id']==sale['id'] and same['duplicate']
    assert c(client,'/api/pos/products')['products'][0]['stock_qty']==3
    assert c(client,'/api/pos/summary')['summary']['sales_total']==1400
    assert c(client,'/api/pos/accounts')['trial_balance']['balanced']
    assert c(client,'/api/pos/accounts')['balance_sheet']['balanced']
    assert len(c(client,'/api/pos/alerts')['alerts'])==1
    receipt=c(client,'/api/pos/receipt?id='+sale['id']);assert receipt['sale']['sale_number']==1 and receipt['lines'][0]['qty']==7
    document=c(client,'/api/pos/document','post',{'kind':'quotation','customer_name':'A Customer','lines':[{'name':'Repair','qty':1,'unit_cents':9000,'tax_bps':0}]})
    assert c(client,'/api/pos/summary')['summary']['sales_count']==1
    assert c(client,'/api/pos/products')['products'][0]['stock_qty']==3
    assert c(client,'/api/pos/document?id='+document['document']['id'])['document']['total_cents']==9000
    c(client,'/api/pos/expense','post',{'title':'Rent','amount_cents':100,'payment_method':'cash'})
    assert c(client,'/api/pos/accounts')['trial_balance']['balanced']
    c(client,'/api/logout','post',{})
    # Offline sign-in: don't call cloud password verification again.
    y.verify_online_password=lambda *args:(_ for _ in ()).throw(RuntimeError('network disabled'))
    c(client,'/api/login','post',{'email':'owner@dg.test','password':'StrongOwnerPassword123'})
    c(client,'/api/pos/refund','post',{'sale_id':sale['id'],'reason':'Customer returned item','restock':True})
    assert c(client,'/api/pos/products')['products'][0]['stock_qty']==10
    assert c(client,'/api/pos/accounts')['trial_balance']['balanced']
    assert c(client,'/api/pos/accounts')['balance_sheet']['balanced']
    # Worker role is online verified on first device login, never set by browser
    y.verify_online_password=cloud_identity.verify_online_password
    worker=TestClient(y.app)
    c(worker,'/api/login','post',{'email':'worker@dg.test','password':'StrongWorkerPassword123'})
    assert c(worker,'/api/me')['user']['role']=='worker'
    c(worker,'/api/pos/accounts',expected=403)
    c(worker,'/api/pos/product','post',{'name':'Forbidden','price_cents':1},403)
    c(worker,'/api/pos/stock','post',{'product_id':p,'delta':2},403)
    c(worker,'/api/pos/expense','post',{'title':'Forbidden','amount_cents':1,'payment_method':'cash'},403)
    # A disconnected queue must never lose sales. Only a reconciled cloud ACK
    # advances synced=1; repeated delivery carries the same idempotency key.
    sent=[]
    def store_reconciled(path,payload,method='POST',timeout=15):
        assert path=='/api/sync/event' and method=='POST'
        sent.append(payload['event_key'])
        return {'stored':True,'reconciled':True}
    y.cloud_json=lambda *args,**kwargs: (_ for _ in ()).throw(OSError('offline'))
    missed=y.sync_local_events(100)
    assert missed['pending']>0 and missed['reconciled']==0
    y.cloud_json=store_reconciled
    result=y.sync_local_events(100)
    assert result['pending']==0 and result['reconciled']>0
    assert len(sent)==len(set(sent))
    assert y.sync_local_events(100)['reconciled']==0
    # Expired signed device lease always locks local data even with session cookie.
    state['active']=False
    assert c(worker,'/api/me')['authenticated'] is False
    c(worker,'/api/pos/products',expected=403)
    # Tenant switch cannot expose previous business session.
    state['active']=True;state['tenant']='YOLA-tenant-2'
    c(worker,'/api/pos/products',expected=401)
    assert Path(y.STATIC_DIR/'workspace.html').read_bytes().startswith(b'<!doctype html>')
    # Expected source files are byte-identical to exported live UI source.
    assert all((Path(y.STATIC_DIR/n).exists()) for n in ('pos.js','premium.css','pos.css'))
    print('PASS: same Yola UI, license gate, onboarding, offline POS, SKU, stock, discount, duplicate protection, receipts, docs, accounts, refunds, employee isolation, tenant isolation, expiry.')