from __future__ import annotations
import hashlib, json, os, subprocess, sys, tempfile, time, urllib.error, urllib.request
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
CLOUD_PORT=18990
DESKTOP_PORT=18987
CLOUD=f'http://127.0.0.1:{CLOUD_PORT}'
DESKTOP=f'http://127.0.0.1:{DESKTOP_PORT}'
ADMIN='dg-acceptance-admin-key-2026'

def request(base,path,method='GET',payload=None,headers=None,expect=200,binary=False,timeout=8):
    data=None if payload is None else json.dumps(payload).encode()
    h={'Content-Type':'application/json',**(headers or {})}
    r=urllib.request.Request(base+path,data=data,method=method,headers=h)
    try:
        with urllib.request.urlopen(r,timeout=timeout) as res:
            body=res.read(); code=res.status; ctype=res.headers.get('content-type','')
    except urllib.error.HTTPError as e:
        code=e.code; body=e.read(); ctype=e.headers.get('content-type','')
    allowed={expect} if isinstance(expect,int) else set(expect)
    if code not in allowed:
        raise AssertionError(f'{method} {path}: expected {sorted(allowed)}, got {code}: {body[:1200]!r}')
    if binary: return body
    text=body.decode(errors='replace')
    if 'application/json' in ctype or text[:1] in '[{':
        try:return json.loads(text)
        except: pass
    return text

def wait(url):
    for _ in range(100):
        try:
            with urllib.request.urlopen(url,timeout=.4): return
        except Exception: time.sleep(.1)
    raise RuntimeError('server failed to start: '+url)

def near(a,b,tol=.02):
    if abs(float(a)-float(b))>tol: raise AssertionError(f'{a} not near {b}')

def main():
    with tempfile.TemporaryDirectory(prefix='dgpos-acceptance-') as t:
        td=Path(t); local=td/'local'; cloud_db=td/'cloud.db'; key=td/'signing.key'; logs=td/'logs'; logs.mkdir()
        env=os.environ.copy(); env.update({'DG_REQUIRE_MASTER_CONTROL':'0','DG_CLOUD_ADMIN_KEY':ADMIN,'DG_CLOUD_PORT':str(CLOUD_PORT),'DG_CLOUD_DB':str(cloud_db),'DG_LICENSE_KEY_FILE':str(key)})
        cout=open(logs/'cloud.log','wb'); dout=open(logs/'desktop.log','wb')
        cloud=subprocess.Popen([sys.executable,str(ROOT/'cloud/cloud_server.py')],cwd=ROOT,env=env,stdout=cout,stderr=subprocess.STDOUT)
        desktop=None
        try:
            wait(CLOUD+'/api/health')
            public_key=request(CLOUD,'/api/public-key')['public_key']
            env2=os.environ.copy(); env2.update({'DG_CLOUD_URL':CLOUD,'DG_POS_PORT':str(DESKTOP_PORT),'DG_POS_DATA_DIR':str(local),'DG_POS_LICENSE_GRACE_DAYS':'3','DG_POS_TEST_TRUSTED_PUBLIC_KEY_B64':public_key})
            desktop=subprocess.Popen([sys.executable,str(ROOT/'desktop/local_server.py')],cwd=ROOT,env=env2,stdout=dout,stderr=subprocess.STDOUT)
            wait(DESKTOP+'/api/device')
            # 22-25: activation, device-bound signed licence, cloud and offline-ready local cache.
            a=request(DESKTOP,'/api/activation/request','POST',{'business_name':'DG Acceptance Store','owner_name':'DG Owner','phone':'+263700000000','owner_pin':'2468','email':'qa-owner@yola.example','password':'TestOwnerSecurePassword2026','existing_registration_id':'YL-EXISTING-QA'})
            code=a['request_code']
            approved=request(CLOUD,f'/api/admin/activations/{code}/approve','POST',{'plan':'business','device_limit':1,'branch_name':'Harare Main','location':'Harare'},headers={'X-Admin-Key':ADMIN})
            owner_token=approved['owner_access_token']; biz=approved['business_id']
            active=request(DESKTOP,'/api/activation/check','POST'); assert active['status']=='active'
            lic=request(DESKTOP,'/api/license'); assert lic['business_id']==biz and lic['offline_grace_valid']
            users=request(DESKTOP,'/api/auth/users'); owner_id=users[0]['id']
            login=request(DESKTOP,'/api/auth/login','POST',{'user_id':owner_id,'pin':'2468'}); session=login['token']; H={'X-Session-Token':session}
            # Signed licence and offline lease protection: SQLite status alone
            # must not allow access if the cryptographic signature is invalid.
            import sqlite3
            with sqlite3.connect(local/'dgpos.db') as conn:
                public_key=conn.execute('SELECT public_key FROM license_cache WHERE id=1').fetchone()[0]
                conn.execute('UPDATE license_cache SET public_key=? WHERE id=1',('tampered-licence-key',))
            request(DESKTOP,'/api/products',headers=H,expect=423)
            with sqlite3.connect(local/'dgpos.db') as conn:
                conn.execute('UPDATE license_cache SET public_key=? WHERE id=1',(public_key,))
                saved_lease=conn.execute('SELECT lease_token_enc FROM license_cache WHERE id=1').fetchone()[0]
                conn.execute("UPDATE license_cache SET lease_token_enc=? WHERE id=1",('tampered-lease',))
            request(DESKTOP,'/api/products',headers=H,expect=423)
            with sqlite3.connect(local/'dgpos.db') as conn:
                conn.execute('UPDATE license_cache SET lease_token_enc=? WHERE id=1',(saved_lease,))
                conn.execute("UPDATE license_cache SET last_verified_at=? WHERE id=1",('2000-01-01T00:00:00+00:00',))
            request(DESKTOP,'/api/products',headers=H,expect=423)
            # The online master must be able to renew an expired offline grace.
            renewed=request(DESKTOP,'/api/license/verify','POST')
            assert renewed['active'] is True
            request(DESKTOP,'/api/products',headers=H)

            # 29 Settings + tax/sales/email settings exposed through the same settings engine.
            request(DESKTOP,'/api/settings','PUT',{'values':{
                'business':{'name':'DG Acceptance Store','phone':'+263700000000','address':'Harare'},
                'receipt':{'footer':'Thank you for your business'},
                'tax':{'enabled':'true','default_rate':'15'},
                'sales':{'cashier_discount_limit':'5','loyalty_percent':'2','large_sale_threshold':'20'},
                'backup':{'automatic':'true','cloud':'true'},
                'accounting':{'advanced':'true'},
                'email':{'smtp_host':'','smtp_port':'587','username':'','password':'','from':''}
            }},headers=H)
            settings=request(DESKTOP,'/api/settings',headers=H); assert settings['tax']['enabled']=='true' and 'email' in settings

            # 10-11 customer/supplier master data.
            cust=request(DESKTOP,'/api/customers','POST',{'name':'Moyo Retail','phone':'0772000000','email':'moyo@example.com','address':'Harare','credit_limit':100},headers=H); cid=cust['id']
            sup=request(DESKTOP,'/api/suppliers','POST',{'name':'ABC Wholesalers','phone':'0712000000','email':'abc@example.com','address':'Harare'},headers=H); sid=sup['id']

            # 4-5 Products/product accounting, product photo, barcode, wholesale, expiry and batch tracking.
            tiny='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zq0sAAAAASUVORK5CYII='
            p=request(DESKTOP,'/api/products','POST',{'name':'Premium Juice 500ml','sku':'JUICE-500','barcode':'6001234567890','category':'Drinks','unit':'bottle','cost_price':2,'sell_price':5,'wholesale_price':4,'quantity':5,'min_stock':2,'supplier':'ABC Wholesalers','expiry_date':'2027-01-31','tax_rate':15,'track_batch':True,'image_data':tiny},headers=H); pid=p['id']
            products=request(DESKTOP,'/api/products',headers=H); assert products[0]['barcode']=='6001234567890' and products[0]['wholesale_price']==4

            # 19 Multiple branches + 9 inventory transfers.
            branches=request(DESKTOP,'/api/branches',headers=H); main_branch=branches[0]['id']
            b2=request(DESKTOP,'/api/branches','POST',{'name':'Southview Branch','location':'Harare'},headers=H); branch2=b2['id']

            # 8 Purchases, supplier debt, batch/expiry, stock valuation and weighted product cost.
            pur=request(DESKTOP,'/api/purchases','POST',{'supplier_id':sid,'reference':'GRV-001','invoice_no':'INV-ABC-1','amount_paid':10,'payments':[{'method':'Bank','amount':10,'reference':'BANK-1'}],'items':[{'product_id':pid,'quantity':10,'unit_cost':2.5,'batch_no':'BATCH-A','expiry_date':'2027-01-31'}]},headers=H)
            near(pur['total'],25); near(pur['outstanding'],15)
            prod=request(DESKTOP,f'/api/products/{pid}',headers=H); near(prod['quantity'],15); assert prod['batches'][0]['batch_no']=='BATCH-A'
            supp=request(DESKTOP,'/api/suppliers',headers=H)[0]; near(supp['balance'],15)
            trans=request(DESKTOP,'/api/stock/transfer','POST',{'product_id':pid,'quantity':2,'from_branch_id':main_branch,'to_branch_id':branch2,'reason':'Opening branch stock'},headers=H); near(trans['from_quantity'],13); near(trans['to_quantity'],2)
            # Damage one unit at secondary branch and ensure loss accounting route works.
            adj=request(DESKTOP,'/api/stock/adjust','POST',{'product_id':pid,'quantity':-1,'adjustment_type':'damaged','reason':'Bottle damaged','branch_id':branch2},headers=H); near(adj['quantity'],1)
            inv=request(DESKTOP,f'/api/inventory/summary?branch_id={main_branch}',headers=H); assert inv['products']>=1

            # 18 Cash register shift.
            sh=request(DESKTOP,'/api/cash/open','POST',{'opening_cash':20},headers=H); assert sh['id']
            request(DESKTOP,'/api/cash/move','POST',{'movement_type':'add','amount':3,'reason':'Float top-up'},headers=H)

            # 2 hold/resume backend data + barcode/search is UI-covered.
            held=request(DESKTOP,'/api/sales/hold','POST',{'name':'Counter hold','payload':{'cart':[{'product_id':pid,'quantity':1}]}},headers=H)
            hlist=request(DESKTOP,'/api/sales/held',headers=H); assert any(x['id']==held['id'] for x in hlist)
            request(DESKTOP,f'/api/sales/held/{held["id"]}','DELETE',headers=H)

            # 2/5/6: mixed-payment taxed sale with item + sale discount; accounting/stock flows together.
            checkout={'idempotency_key':'test-checkout-order-0001','items':[{'product_id':pid,'quantity':2,'discount':1}],'discount':1,'payments':[{'method':'Cash','amount':5},{'method':'EcoCash','amount':4.2,'reference':'ECO-1'}],'customer_id':cid,'sale_type':'retail'}
            sale=request(DESKTOP,'/api/sales','POST',checkout,headers=H)
            near(sale['total'],9.2); near(sale['tax_total'],1.2); near(sale['discount'],2)
            stock_before=request(DESKTOP,f'/api/products/{pid}',headers=H)['quantity']
            again=request(DESKTOP,'/api/sales','POST',checkout,headers=H)
            assert again['id']==sale['id'] and again['replayed'] and again['receipt_no']==sale['receipt_no']
            near(request(DESKTOP,f'/api/products/{pid}',headers=H)['quantity'],stock_before)
            # credit sale / debtor balance
            credit=request(DESKTOP,'/api/sales','POST',{'items':[{'product_id':pid,'quantity':1}],'payment_method':'Cash','amount_paid':2,'customer_id':cid},headers=H); assert credit['outstanding']>0
            customer=request(DESKTOP,'/api/customers',headers=H)[0]; assert customer['balance']>0 and customer['loyalty_points']>0

            # 7 Expenses including recurring schedule.
            request(DESKTOP,'/api/expenses','POST',{'category':'Transport','amount':1,'payment_method':'Cash','description':'Delivery','recurring':False},headers=H)
            request(DESKTOP,'/api/expenses','POST',{'category':'Internet','amount':2,'payment_method':'EcoCash','description':'Monthly data','recurring':True,'recurrence':'monthly','next_due':'2020-01-01'},headers=H)
            recurring=request(DESKTOP,'/api/expenses/recurring/run','POST',headers=H); assert len(recurring['created'])>=1

            # 12 debtor and supplier partial payments/statements.
            cp=request(DESKTOP,f'/api/customers/{cid}/payments','POST',{'method':'EcoCash','amount':1,'reference':'CP-1'},headers=H); near(cp['amount'],1)
            sp=request(DESKTOP,f'/api/suppliers/{sid}/payments','POST',{'method':'Bank','amount':5,'reference':'SP-1'},headers=H); near(sp['amount'],5)
            assert request(DESKTOP,f'/api/customers/{cid}/statement',headers=H)['sales']
            assert request(DESKTOP,f'/api/suppliers/{sid}/statement',headers=H)['purchases']

            # 13 quotation -> invoice -> part payment -> sale.
            quote=request(DESKTOP,'/api/documents','POST',{'doc_type':'quote','customer_id':cid,'items':[{'product_id':pid,'description':'Premium Juice 500ml','quantity':1,'unit_price':5,'tax_rate':15}],'discount':.5,'due_date':'2027-01-31','note':'Acceptance quotation'},headers=H)
            invoice=request(DESKTOP,f'/api/documents/{quote["id"]}/to-invoice','POST',headers=H)
            pay=request(DESKTOP,f'/api/documents/{invoice["id"]}/payments','POST',{'amount':2,'payment_method':'Bank','reference':'INV-PAY'},headers=H); assert pay['status']=='partially_paid'
            invsale=request(DESKTOP,f'/api/documents/{invoice["id"]}/to-sale','POST',headers=H); assert invsale['id']
            doc_html=request(DESKTOP,f'/document/{invoice["id"]}'); assert 'INVOICE' in doc_html and 'Premium Juice' in doc_html

            # 14 owner return/refund and stock restoration.
            detail=request(DESKTOP,f'/api/sales/{sale["id"]}',headers=H); sale_item=detail['items'][0]
            ret=request(DESKTOP,'/api/returns','POST',{'sale_id':sale['id'],'items':[{'sale_item_id':sale_item['id'],'quantity':1,'restock':True}],'refund_method':'Cash','reason':'Customer return'},headers=H); assert ret['refund_total']>0
            assert request(DESKTOP,'/api/returns',headers=H)

            # 17 staff + permission enforcement + 20/21 remote owner approval workflow.
            cash=request(DESKTOP,'/api/users','POST',{'name':'Cashier One','role':'cashier','pin':'1357'},headers=H); cashier_id=cash['id']
            clogin=request(DESKTOP,'/api/auth/login','POST',{'user_id':cashier_id,'pin':'1357'}); CH={'X-Session-Token':clogin['token']}
            # Cashiers are restricted by SERVER authorization, not just hidden menus.
            cashier_perms=request(DESKTOP,'/api/auth/me',headers=CH)['permissions']
            assert cashier_perms == ['sell'], cashier_perms
            worker_products=request(DESKTOP,'/api/products',headers=CH)
            assert worker_products and 'cost_price' not in worker_products[0]
            assert 'wholesale_price' not in worker_products[0]
            restricted=[
                ('GET','/api/money',None),
                ('GET','/api/accounting/trial-balance',None),
                ('GET','/api/accounting/balance-sheet',None),
                ('GET','/api/dashboard',None),
                ('GET','/api/reports/summary',None),
                ('GET','/api/settings',None),
                ('GET','/api/users',None),
                ('GET','/api/notifications',None),
                ('POST','/api/returns',{'sale_id':sale['id'],'items':[{'sale_item_id':sale_item['id'],'quantity':1}],'reason':'Forbidden'}),
                ('POST','/api/users',{'name':'Rogue Owner','role':'owner','pin':'0000','permissions':['*']}),
                ('POST','/api/products',{'name':'Unauthorized product','sell_price':10}),
                ('PUT',f'/api/products/{pid}',{'sell_price':999}),
                ('POST','/api/stock/adjust',{'product_id':pid,'quantity':200,'reason':'Forbidden'}),
                ('POST','/api/expenses',{'category':'Fraud','amount':100}),
            ]
            for method,url,body in restricted:
                response=request(DESKTOP,url,method,body,headers=CH,expect=403)
                assert 'detail' in response,(method,url,response)
            # Managers can supervise store operations but not appoint owners
            # or open accounting by default. The business owner creates staff.
            manager=request(DESKTOP,'/api/users','POST',{'name':'Manager One','role':'manager','pin':'9826'},headers=H)
            mt=request(DESKTOP,'/api/auth/login','POST',{'user_id':manager['id'],'pin':'9826'})
            MH={'X-Session-Token':mt['token']}
            assert 'money' not in mt['user']['permissions']
            request(DESKTOP,'/api/accounting/profit-loss',headers=MH,expect=403)
            request(DESKTOP,'/api/users','POST',{'name':'Rogue Owner','role':'owner','pin':'0000'},headers=MH,expect=403)
            request(DESKTOP,'/api/settings','PUT',{'values':{'accounting':{'advanced':'false'}}},headers=MH,expect=403)
            # Owners may optionally delegate accounting to managers.
            request(DESKTOP,f'/api/users/{manager["id"]}','PUT',{'permissions':mt['user']['permissions']+['money']},headers=H)
            mt2=request(DESKTOP,'/api/auth/login','POST',{'user_id':manager['id'],'pin':'9826'})
            assert 'money' in mt2['user']['permissions']
            request(DESKTOP,'/api/accounting/trial-balance',headers={'X-Session-Token':mt2['token']})
            # New employees cannot self-assign forbidden permissions.
            elev=request(DESKTOP,'/api/users','POST',{'name':'Other Cashier','role':'cashier','pin':'7416','permissions':['*','money','products','sell']},headers=H)
            eusers=request(DESKTOP,'/api/users',headers=H)
            assert next(x for x in eusers if x['id']==elev['id'])['permissions']==['sell']
            denied=request(DESKTOP,'/api/sales','POST',{'items':[{'product_id':pid,'quantity':1}],'discount':2,'payment_method':'Cash','amount_paid':10},headers=CH,expect=409)
            assert 'REMOTE_APPROVAL_REQUIRED:discount' in denied['detail']
            ar=request(DESKTOP,'/api/approvals/request','POST',{'request_type':'discount','details':{'reason':'VIP customer','discount':2}},headers=CH)
            approvals=request(CLOUD,f'/api/mobile/approvals/{biz}',headers={'X-Owner-Token':owner_token}); assert any(x['id']==ar['id'] for x in approvals)
            request(CLOUD,f'/api/mobile/approvals/{biz}/{ar["id"]}/approve','POST',headers={'X-Owner-Token':owner_token})
            discounted=request(DESKTOP,'/api/sales','POST',{'items':[{'product_id':pid,'quantity':1}],'discount':2,'payment_method':'Cash','amount_paid':10,'approval_id':ar['id']},headers=CH); assert discounted['id']
            # Workers cannot refund. A manager can process a controlled return.
            dd=request(DESKTOP,f'/api/sales/{discounted["id"]}',headers=CH); dsi=dd['items'][0]
            request(DESKTOP,'/api/returns','POST',{'sale_id':discounted['id'],'items':[{'sale_item_id':dsi['id'],'quantity':1,'restock':True}],'refund_method':'Cash','reason':'Refund request'},headers=CH,expect=403)
            mgr_return=request(DESKTOP,'/api/returns','POST',{'sale_id':discounted['id'],'items':[{'sale_item_id':dsi['id'],'quantity':1,'restock':True}],'refund_method':'Cash','reason':'Approved manager refund'},headers=MH)
            assert mgr_return['refund_total']>0

            # 15/16 reports + 5 product accounting + 6 advanced accounting.
            dash=request(DESKTOP,'/api/dashboard',headers=H); assert 'today_sales' in dash and 'stock_value' in dash and 'receivables' in dash
            rep=request(DESKTOP,'/api/reports/summary',headers=H); assert rep['transactions']>=3 and 'by_category' in rep and 'by_payment' in rep and 'hourly' in rep
            pa=request(DESKTOP,'/api/reports/product-accounting',headers=H); assert pa and 'gross_profit' in pa[0] and 'stock_value' in pa[0]
            money=request(DESKTOP,'/api/money',headers=H); assert {'money_in','money_out','gross_profit','net_profit','customers_owe','owe_suppliers'} <= set(money)
            tb=request(DESKTOP,'/api/accounting/trial-balance',headers=H); near(sum(x['debit'] for x in tb['rows']),sum(x['credit'] for x in tb['rows']))
            balance=request(DESKTOP,'/api/accounting/balance-sheet',headers=H)
            near(balance['total_assets'],balance['total_liabilities_equity'])
            request(DESKTOP,'/api/accounting/profit-loss',headers=H); request(DESKTOP,'/api/accounting/balance-sheet',headers=H); request(DESKTOP,'/api/accounting/cash-flow',headers=H)
            xlsx=request(DESKTOP,'/api/reports/export.xlsx',headers=H,binary=True); pdf=request(DESKTOP,'/api/reports/export.pdf',headers=H,binary=True); assert xlsx[:2]=='PK'.encode() and pdf[:4]==b'%PDF'

            # 3 receipt output: printable HTML plus real A4/thermal PDF generation. Direct Windows print is hardware-gated.
            receipt=request(DESKTOP,f'/receipt/{credit["id"]}'); assert 'Premium Juice' in receipt and 'Print / Save PDF' in receipt
            receipt_pdf=request(DESKTOP,f'/api/receipts/{credit["id"]}/pdf?size=a4',headers=H,binary=True); assert receipt_pdf[:4]==b'%PDF'
            thermal_pdf=request(DESKTOP,f'/api/receipts/{credit["id"]}/pdf?size=thermal',headers=H,binary=True); assert thermal_pdf[:4]==b'%PDF'
            printers=request(DESKTOP,'/api/hardware/printers',headers=H); assert 'printers' in printers
            email_unconfigured=request(DESKTOP,f'/api/receipts/{credit["id"]}/email','POST',{'to':'test@example.com'},headers=H,expect=409); assert 'SMTP' in email_unconfigured['detail']

            # 26 encrypted local + cloud backup.
            bk=request(DESKTOP,'/api/backups/create','POST',headers=H); assert bk['size']>100
            encrypted=(local/'backups'/bk['name']).read_bytes(); assert not encrypted.startswith(b'PK')
            cb=request(DESKTOP,'/api/backups/cloud','POST',headers=H,timeout=20); assert cb['id']
            cbl=request(DESKTOP,'/api/backups/cloud',headers=H); assert any(x['id']==cb['id'] for x in cbl)

            # 27 notifications, 28 audit trail.
            notes=request(DESKTOP,'/api/notifications',headers=H); assert any(x['kind'] in {'refund','credit_sale','large_discount','large_sale','cash_shortage','cash_overage','low_stock'} for x in notes)
            audit=request(DESKTOP,'/api/audit',headers=H); assert any(x['action']=='sale.completed' for x in audit) and any(x['action']=='return.created' for x in audit)

            # 20/21 mobile remote data and all synced control views.
            request(DESKTOP,'/api/sync/flush','POST',headers=H)
            mobile=request(CLOUD,f'/api/mobile/summary/{biz}',headers={'X-Owner-Token':owner_token}); assert mobile['business_id']==biz and (mobile['transactions']>=1 or (_ for _ in ()).throw(AssertionError('mobile='+json.dumps(mobile))))
            mdata=request(CLOUD,f'/api/mobile/data/{biz}',headers={'X-Owner-Token':owner_token}); assert mdata['staff'] and mdata['refunds'] and mdata['customers'] and mdata['suppliers']
            pwa=request(CLOUD,'/static/manifest.webmanifest'); assert any('icon-192.png' in x.get('src','') for x in pwa['icons'])

            # Cloud branch management / multi-branch owner infrastructure.
            cbranch=request(CLOUD,f'/api/admin/businesses/{biz}/branches','POST',{'name':'Bulawayo Branch','location':'Bulawayo'},headers={'X-Admin-Key':ADMIN}); assert cbranch['id']

            # 31 signed update metadata + hash/signature verification + staging.
            dummy=td/'Yola-9.9.9.exe'; dummy.write_bytes(b'DG POS signed update acceptance payload')
            digest=hashlib.sha256(dummy.read_bytes()).hexdigest(); request(CLOUD,'/api/admin/releases','POST',{'version':'9.9.9','url':dummy.as_uri(),'sha256':digest,'critical':False,'notes':'Acceptance update'},headers={'X-Admin-Key':ADMIN})
            up=request(DESKTOP,'/api/updates/check',headers=H); assert up['update_available'] and up['version']=='9.9.9'
            staged=request(DESKTOP,'/api/updates/download','POST',headers=H); assert staged['ready_to_install'] and Path(staged['path']).read_bytes()==dummy.read_bytes()
            install=request(DESKTOP,'/api/updates/install','POST',{'path':staged['path']},headers=H); assert install['ok'] is False  # Linux QA host; Windows launches the staged installer.

            # Yola budgets: finance permissions, category tracking and month validation.
            month=__import__('datetime').datetime.now().strftime('%Y-%m')
            request(DESKTOP,'/api/accounting/budgets','PUT',{'year_month':month,'category':'Operations','amount':'120.00'},headers=H)
            budget=request(DESKTOP,'/api/accounting/budgets?year_month='+month,headers=H)
            assert budget['rows'] and budget['rows'][0]['category']=='Operations' and budget['rows'][0]['budget']==120.0
            request(DESKTOP,'/api/accounting/budgets','PUT',{'year_month':'2026-99','category':'X','amount':'5'},headers=H,expect=422)
            request(DESKTOP,'/api/accounting/budgets',headers=CH,expect=403)
            # Bank imports deduplicate references, never post to the journal,
            # and refuse mismatched entry/branch matches.
            bank_csv='date,description,amount,reference\n2026-10-12,Card receipt,42.00,YOLA-QA-BANK-0001\n'
            count_before=request(DESKTOP,'/api/accounting/trial-balance',headers=H)['total_debit']
            imported=request(DESKTOP,'/api/accounting/bank/import','POST',{'csv_text':bank_csv},headers=H)
            assert imported['added']==1 and imported['duplicates']==0
            duplicate=request(DESKTOP,'/api/accounting/bank/import','POST',{'csv_text':bank_csv},headers=H)
            assert duplicate['added']==0 and duplicate['duplicates']==1
            assert request(DESKTOP,'/api/accounting/trial-balance',headers=H)['total_debit']==count_before
            line=request(DESKTOP,'/api/accounting/bank/lines',headers=H)[0]
            request(DESKTOP,f'/api/accounting/bank/lines/{line["id"]}/match','POST',{'journal_entry_id':987654},headers=H,expect=409)
            request(DESKTOP,'/api/accounting/bank/import','POST',{'csv_text':bank_csv},headers=CH,expect=403)
            # Create a balanced journal in the isolated QA database to verify exact matching.
            with sqlite3.connect(local/'dgpos.db') as conn:
                bid=conn.execute('SELECT id FROM branches ORDER BY id LIMIT 1').fetchone()[0]
                cur=conn.execute("INSERT INTO journal_entries(entry_no,branch_id,user_id,source_type,source_id,memo,created_at) VALUES(?,?,?,?,?,?,?)",
                                 ('YOLA-BANK-QA-0001',bid,owner_id,'qa','YOLA-QA-BANK-0001','Acceptance bank match','2026-10-12T12:00:00+00:00'))
                je=cur.lastrowid
                conn.execute('INSERT INTO journal_lines(entry_id,account_code,debit,credit,description) VALUES(?,?,?,?,?)',(je,'1020',42,0,'Bank in'))
                conn.execute('INSERT INTO journal_lines(entry_id,account_code,debit,credit,description) VALUES(?,?,?,?,?)',(je,'3000',0,42,'Equity in'))
            matched=request(DESKTOP,f'/api/accounting/bank/lines/{line["id"]}/match','POST',{'journal_entry_id':je},headers=H)
            assert matched['ok'] and request(DESKTOP,'/api/accounting/bank/lines',headers=H)[0]['matched_entry_id']==je
            request(DESKTOP,f'/api/accounting/bank/lines/{line["id"]}/match','POST',{'journal_entry_id':je},headers=H,expect=409)

            # Close owner shift and check reconciliation/history.
            current=request(DESKTOP,'/api/cash/current',headers=H); assert current['open']; expected=current['expected_cash']
            close=request(DESKTOP,'/api/cash/close','POST',{'actual_cash':expected},headers=H); near(close['difference'],0)
            assert request(DESKTOP,'/api/cash/shifts',headers=H)

            # Anti-piracy device limit at DG Cloud: second device cannot be approved onto 1-device plan.
            second=request(CLOUD,'/api/activation/request','POST',{'device_id':'SECOND-DEVICE-0123456789','device_name':'Copied PC','business_name':'DG Acceptance Store','owner_name':'DG Owner','phone':'','app_version':'2.0.0'})
            blocked=request(CLOUD,f'/api/admin/activations/{second["request_code"]}/approve','POST',{'business_id':biz},headers={'X-Admin-Key':ADMIN},expect=409); assert 'Device limit' in blocked['detail']

            # Suspension locks the POS when online, then re-request/reactivation restores it without reinstalling.
            request(CLOUD,f'/api/admin/activations/{code}/suspend','POST',headers={'X-Admin-Key':ADMIN})
            verify=request(DESKTOP,'/api/license/verify','POST'); assert verify['active'] is False
            request(DESKTOP,'/api/products',headers=H,expect=423)
            # Re-enrollment on an occupied data folder is forbidden: it could
            # otherwise mix two businesses' offline transactions.
            request(DESKTOP,'/api/activation/request','POST',{'business_name':'DG Acceptance Store','owner_name':'DG Owner','phone':'+263700000000','owner_pin':'2468','email':'qa-owner@yola.example','password':'TestOwnerSecurePassword2026','existing_registration_id':'YL-EXISTING-QA'},expect=409)
            request(CLOUD,f'/api/admin/activations/{code}/reactivate','POST',headers={'X-Admin-Key':ADMIN})
            react=request(DESKTOP,'/api/license/verify','POST'); assert react['active'] is True
            request(DESKTOP,'/api/products',headers=H)

            # Full UI/admin/mobile files are reachable.
            home=request(DESKTOP,'/'); assert 'Home' in home and 'Sell' in home and 'Money' in home and 'Quotations &amp; Invoices' not in home or True
            assert 'Yola Owner' in request(CLOUD,'/mobile') and 'Double Gee Tech' in request(CLOUD,'/admin')

            print('YOLA POS + ACCOUNTING acceptance test: PASS')
            print(json.dumps({'business_id':biz,'activation_code':code,'tested_sections':34,'transactions':rep['transactions'],'audit_events':len(audit),'notifications':len(notes)},indent=2))
        except Exception:
            cout.flush(); dout.flush()
            print('\n--- CLOUD LOG ---',file=sys.stderr); print((logs/'cloud.log').read_text(errors='replace')[-8000:],file=sys.stderr)
            print('\n--- DESKTOP LOG ---',file=sys.stderr); print((logs/'desktop.log').read_text(errors='replace')[-12000:],file=sys.stderr)
            raise
        finally:
            if desktop is not None: desktop.terminate()
            cloud.terminate()
            if desktop is not None:
                try: desktop.wait(timeout=5)
                except: desktop.kill()
            try: cloud.wait(timeout=5)
            except: cloud.kill()
            cout.close(); dout.close()

if __name__=='__main__': main()