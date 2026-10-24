"""Yola exact-online-UI offline data adapter.

No alternate licensing authority is created. All data writes and sessions are
bound to a cryptographically authenticated, unexpired DG Master lease verified
by the existing local_server licence implementation. This app intentionally
blocks all access before desktop Master licensing is provisioned and activated.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from fastapi import FastAPI, Request, HTTPException, Response
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from local_server import db, cached_license_valid, read_license, DEVICE_ID, cloud_json, STATIC_DIR as LEGACY_STATIC
from cloud_identity import verify_online_password,begin_session,session_status

STATIC_DIR = Path(__file__).resolve().parent / "static"
app = FastAPI(title="Yola — Offline Business Suite")
APP_DATA_VERSION = 1


def now(): return datetime.now(timezone.utc).isoformat()
_pending_accounts={}  # short-lived onboarding cookies, never a licence grant
def uid(): return str(uuid.uuid4())
def cents(x):
    if isinstance(x,bool) or not isinstance(x,int) or x<0 or x>10**12:
        raise HTTPException(422,"Invalid amount in cents")
    return x

def sql_init():
    with db() as c:
        c.executescript("""
        CREATE TABLE IF NOT EXISTS yola_local_accounts (
          id TEXT PRIMARY KEY, tenant TEXT NOT NULL, email TEXT NOT NULL,
          name TEXT NOT NULL, role TEXT NOT NULL CHECK(role IN ('owner','manager','worker')),
          pass_salt TEXT NOT NULL, pass_hash TEXT NOT NULL,
          active INTEGER NOT NULL DEFAULT 1,
          UNIQUE(tenant,email));
        CREATE TABLE IF NOT EXISTS yola_local_sessions (
          token_hash TEXT PRIMARY KEY, account_id TEXT NOT NULL,
          expires_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS yola_local_products (
          id TEXT PRIMARY KEY, tenant TEXT NOT NULL, name TEXT NOT NULL,
          sku TEXT NOT NULL, barcode TEXT, category TEXT NOT NULL DEFAULT 'General',
          price_cents INTEGER NOT NULL CHECK(price_cents>=0),
          cost_cents INTEGER NOT NULL CHECK(cost_cents>=0),
          tax_bps INTEGER NOT NULL DEFAULT 0,
          stock_qty INTEGER NOT NULL DEFAULT 0 CHECK(stock_qty>=0),
          min_stock INTEGER NOT NULL DEFAULT 5, active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL, UNIQUE(tenant,sku));
        CREATE TABLE IF NOT EXISTS yola_local_sales (
          id TEXT PRIMARY KEY, tenant TEXT NOT NULL, cashier_id TEXT NOT NULL,
          number INTEGER NOT NULL, subtotal_cents INTEGER NOT NULL,
          discount_cents INTEGER NOT NULL, tax_cents INTEGER NOT NULL,
          total_cents INTEGER NOT NULL, cost_cents INTEGER NOT NULL,
          payment_method TEXT NOT NULL, customer_name TEXT,
          idempotency_key TEXT NOT NULL, created_at TEXT NOT NULL,
          UNIQUE(tenant,idempotency_key), UNIQUE(tenant,number));
        CREATE TABLE IF NOT EXISTS yola_local_sale_lines (
          id TEXT PRIMARY KEY, tenant TEXT NOT NULL, sale_id TEXT NOT NULL,
          product_id TEXT NOT NULL, name TEXT NOT NULL, qty INTEGER NOT NULL,
          unit_price_cents INTEGER NOT NULL, unit_cost_cents INTEGER NOT NULL,
          net_cents INTEGER NOT NULL, tax_cents INTEGER NOT NULL,
          total_cents INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS yola_local_journals (
          id TEXT PRIMARY KEY, tenant TEXT NOT NULL, source TEXT NOT NULL,
          source_id TEXT, note TEXT, created_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS yola_local_entries (
          id TEXT PRIMARY KEY, tenant TEXT NOT NULL, journal_id TEXT NOT NULL,
          code TEXT NOT NULL, debit_cents INTEGER NOT NULL, credit_cents INTEGER NOT NULL,
          CHECK((debit_cents>0 AND credit_cents=0) OR (credit_cents>0 AND debit_cents=0)));
        CREATE TABLE IF NOT EXISTS yola_local_expenses (
          id TEXT PRIMARY KEY, tenant TEXT NOT NULL, title TEXT NOT NULL,
          amount_cents INTEGER NOT NULL, payment_method TEXT NOT NULL,
          created_by TEXT NOT NULL, created_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS yola_local_documents (
          id TEXT PRIMARY KEY, tenant TEXT NOT NULL, document_no INTEGER NOT NULL,
          kind TEXT NOT NULL, customer_name TEXT NOT NULL, customer_contact TEXT,
          notes TEXT, items TEXT NOT NULL, subtotal_cents INTEGER NOT NULL,
          tax_cents INTEGER NOT NULL, total_cents INTEGER NOT NULL,
          created_by TEXT NOT NULL, created_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS yola_local_refunds (
          id TEXT PRIMARY KEY, tenant TEXT NOT NULL, sale_id TEXT NOT NULL,
          reason TEXT NOT NULL, restocked INTEGER NOT NULL, created_at TEXT NOT NULL,
          UNIQUE(tenant,sale_id));
        CREATE TABLE IF NOT EXISTS yola_local_settings (
          tenant TEXT PRIMARY KEY, whatsapp_phone TEXT, whatsapp_opt_in INTEGER DEFAULT 0,
          low_stock_alerts INTEGER DEFAULT 1, receipt_footer TEXT,
          receipt_phone TEXT, business_address TEXT, receipt_paper TEXT);
        CREATE TABLE IF NOT EXISTS yola_local_alerts (
          id TEXT PRIMARY KEY, tenant TEXT NOT NULL, product_id TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'queued', payload TEXT NOT NULL,
          created_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS yola_local_events (
          id TEXT PRIMARY KEY, tenant TEXT NOT NULL, kind TEXT NOT NULL,
          payload TEXT NOT NULL, created_at TEXT NOT NULL,
          synced INTEGER NOT NULL DEFAULT 0,
          uploaded_at TEXT, last_error TEXT);
        CREATE TABLE IF NOT EXISTS yola_local_customers (
          id TEXT PRIMARY KEY, tenant TEXT NOT NULL, name TEXT NOT NULL,
          phone TEXT, email TEXT, credit_limit_cents INTEGER NOT NULL DEFAULT 0,
          terms_days INTEGER NOT NULL DEFAULT 30, active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS yola_l_customer_tenant ON yola_local_customers(tenant,name);
        CREATE TABLE IF NOT EXISTS yola_local_customer_cash_entries (
          id TEXT PRIMARY KEY, tenant TEXT NOT NULL, customer_id TEXT NOT NULL,
          kind TEXT NOT NULL CHECK(kind IN ('payment','deposit','apply_deposit')),
          amount_cents INTEGER NOT NULL CHECK(amount_cents>0),
          payment_method TEXT NOT NULL, reference TEXT, idempotency_key TEXT NOT NULL,
          created_by TEXT NOT NULL, created_at TEXT NOT NULL, UNIQUE(tenant,idempotency_key));
        CREATE TABLE IF NOT EXISTS yola_local_customer_allocations (
          id TEXT PRIMARY KEY, tenant TEXT NOT NULL, entry_id TEXT NOT NULL,
          sale_id TEXT NOT NULL, amount_cents INTEGER NOT NULL CHECK(amount_cents>0),
          UNIQUE(tenant,entry_id,sale_id));
        CREATE TABLE IF NOT EXISTS yola_local_staff_rules (
          tenant TEXT NOT NULL, email TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1,
          permissions TEXT NOT NULL DEFAULT '{}', updated_by TEXT, updated_at TEXT NOT NULL,
          PRIMARY KEY(tenant,email));
        CREATE INDEX IF NOT EXISTS yola_l_product_tenant ON yola_local_products(tenant,active,name);
        CREATE INDEX IF NOT EXISTS yola_l_sale_tenant ON yola_local_sales(tenant,created_at);
        CREATE INDEX IF NOT EXISTS yola_l_event_unsynced ON yola_local_events(tenant,synced);
        """)
        # Non-destructive migration for existing local Yola databases.
        existing={r[1] for r in c.execute('PRAGMA table_info(yola_local_events)')}
        for col in ('uploaded_at','last_error'):
            if col not in existing:c.execute(f'ALTER TABLE yola_local_events ADD COLUMN {col} TEXT')
        # Safe additive migrations: older client databases and receipts are preserved.
        additions={
            'yola_local_products':[('quality',"TEXT NOT NULL DEFAULT ''"),('kind',"TEXT NOT NULL DEFAULT 'stock'")],
            'yola_local_sale_lines':[('kind',"TEXT NOT NULL DEFAULT 'stock'")],
            'yola_local_sales':[('customer_id',"TEXT"),('due_date',"TEXT")],
        }
        for table,columns in additions.items():
            existing={row[1] for row in c.execute(f'PRAGMA table_info({table})')}
            for col,definition in columns:
                if col not in existing:c.execute(f'ALTER TABLE {table} ADD COLUMN {col} {definition}')


sql_init()


def lease():
    # Never grant offline access from a local flag, app settings or an unsigned claim.
    # The legacy engine uses an Ed25519-pinned, device-bound lease with expiry.
    if not cached_license_valid():
        raise HTTPException(403,"A signed DG Tech Master Control licence is required or your offline lease expired. Reconnect to renew.")
    l=read_license()
    tenant=str(l.get("business_id") or "")
    if not tenant or not l.get("license_token") or not l.get("lease_token"):
        raise HTTPException(403,"An approved Yola device licence is required")
    return tenant,l


def json_row(row):return dict(row) if row else None

def rows(c,query,*args):return [dict(x) for x in c.execute(query,args).fetchall()]

def one(c,query,*args):return json_row(c.execute(query,args).fetchone())

def cache_verified_staff(tenant,license_info,email,password):
    # Cloud authentication verifies the real password, live Master approval,
    # and the role; the signed desktop device lease independently gates access.
    cloud=verify_online_password(email,password)
    if not cloud.get('license',{}).get('active'):
        raise HTTPException(403,'DG Tech Master Control has not approved this business')
    code=(license_info.get('request_code') or '').upper()
    if not code or cloud.get('businessCode','').upper()!=code:
        raise HTTPException(403,'Account does not belong to this signed device licence')
    if cloud.get('role') not in ('owner','manager','worker'):
        raise HTTPException(403,'Unsupported account role')
    salt,digest=new_password(password)
    with db() as c:
        policy=one(c,'SELECT enabled FROM yola_local_staff_rules WHERE tenant=? AND email=?',tenant,email.lower())
        if policy and not policy['enabled']:raise HTTPException(403,'Staff access disabled by the business owner')
        prior=one(c,'SELECT id FROM yola_local_accounts WHERE tenant=? AND lower(email)=?',tenant,email.lower())
        account_id=prior['id'] if prior else uid()
        c.execute('''INSERT INTO yola_local_accounts(id,tenant,email,name,role,pass_salt,pass_hash,active)
            VALUES(?,?,?,?,?,?,?,1)
            ON CONFLICT(tenant,email) DO UPDATE SET name=excluded.name,role=excluded.role,
              pass_salt=excluded.pass_salt,pass_hash=excluded.pass_hash,active=1''',(account_id,tenant,email.lower(),cloud.get('name') or email,cloud['role'],salt,digest))
        return one(c,'SELECT * FROM yola_local_accounts WHERE id=?',account_id)

def phash(token):return hashlib.sha256(token.encode()).hexdigest()

def hash_password(password,salt):return hashlib.scrypt(password.encode(),salt=bytes.fromhex(salt),n=16384,r=8,p=1,dklen=32).hex()

def new_password(password):
    if not isinstance(password,str) or len(password)<12:raise HTTPException(422,"Password must be at least 12 characters")
    salt=secrets.token_hex(16)
    return salt,hash_password(password,salt)


def auth(request,allowed=None,permission=None):
    tenant,license_info=lease()
    token=request.cookies.get('yola_offline_session','')
    if not token:raise HTTPException(401,'Please sign in')
    with db() as c:
        u=one(c,"""SELECT a.* FROM yola_local_accounts a JOIN yola_local_sessions s ON s.account_id=a.id
            WHERE s.token_hash=? AND s.expires_at>? AND a.active=1 AND a.tenant=?""",phash(token),now(),tenant)
    if not u:raise HTTPException(401,'Please sign in')
    if allowed and u['role'] not in allowed:raise HTTPException(403,'This account does not have permission')
    if u['role']!='owner':
        with db() as c:
            rule=one(c,'SELECT enabled,permissions FROM yola_local_staff_rules WHERE tenant=? AND email=?',tenant,u['email'])
        if rule and not rule['enabled']:raise HTTPException(403,'Staff access disabled')
        if permission:
            defaults={'manager':{'inventory','refund','customers','credit'},'worker':set()}
            default=permission in defaults.get(u['role'],set())
            effective=json.loads(rule['permissions']).get(permission,default) if rule else default
            # Owner rules can only revoke the default capabilities, never grant wider access.
            if not (default and effective is True):raise HTTPException(403,'Your account is restricted from '+permission)
    return u,tenant,license_info


def journal(c,tenant,source,source_id,description,entries):
    if sum(a for _,a,_ in entries)!=sum(a for _,_,a in entries):raise ValueError('Unbalanced journal')
    if not sum(x[1] for x in entries):return
    id=uid();c.execute("INSERT INTO yola_local_journals VALUES (?,?,?,?,?,?)",(id,tenant,source,source_id,description,now()))
    for code,debit,credit in entries:
        if debit or credit:c.execute('INSERT INTO yola_local_entries VALUES(?,?,?,?,?,?)',(uid(),tenant,id,code,debit,credit))


def event(c,tenant,kind,obj):
    c.execute('INSERT INTO yola_local_events(id,tenant,kind,payload,created_at,synced) VALUES(?,?,?,?,?,0)',(uid(),tenant,kind,json.dumps(obj),now()))


def low_stock(c,tenant,p,old_count,new_count):
    if p.get('kind','stock')!='service' and old_count>p['min_stock'] and new_count<=p['min_stock']:
        c.execute('INSERT INTO yola_local_alerts VALUES(?,?,?,?,?,?)',(uid(),tenant,p['id'],'queued',json.dumps({'name':p['name'],'sku':p['sku'],'stock':new_count}),now()))


def setting(c,tenant):
    return one(c,'SELECT * FROM yola_local_settings WHERE tenant=?',tenant) or {'whatsapp_phone':'','whatsapp_opt_in':0,'low_stock_alerts':1,'receipt_footer':'Thank you for shopping with us!','receipt_phone':'','business_address':'','receipt_paper':'80mm'}

@app.exception_handler(HTTPException)
async def error(request,exc):return JSONResponse({'error':str(exc.detail)},status_code=exc.status_code)

@app.get('/api/health')
def health():return {'ok':True,'service':'Yola offline local SQLite','licensingAuthority':'DG Tech Master Control','localData':True}

@app.get('/api/me')
def me(request:Request):
    try:u,tenant,l=auth(request)
    except HTTPException:
        setup=request.cookies.get('yola_setup')
        pending=_pending_accounts.get(setup) if setup else None
        if pending and pending['expires']>datetime.now(timezone.utc):
            cloud=session_status(pending['client'])
            if cloud:
                cloud=dict(cloud)
                remote_active=cloud.get('license',{}).get('active') is True
                # An activated MASTER business is not an activated Windows PC.
                cloud['license']={'active':False,'status':'device_enrolment_required' if remote_active else cloud.get('license',{}).get('status','inactive')}
                return {'authenticated':True,'user':cloud}
        return {'authenticated':False,'user':None}
    return {'authenticated':True,'user':{'id':u['id'],'name':u['name'],'email':u['email'],'business':l.get('business_name') or tenant,'businessCode':l.get('request_code') or tenant,'role':u['role'],'license':{'status':'active','active':True}}}

@app.post('/api/logout')
def logout(request:Request,response:Response):
    token=request.cookies.get('yola_offline_session')
    if token:
        with db() as c:c.execute('DELETE FROM yola_local_sessions WHERE token_hash=?',(phash(token),))
    response.delete_cookie('yola_offline_session')
    old=request.cookies.get('yola_setup')
    if old:_pending_accounts.pop(old,None)
    response.delete_cookie('yola_setup')
    return {'success':True}

@app.post('/api/local-enroll')
async def enroll(request:Request):
    """Only for an *already cryptographically licensed* device.

    Owner provides their Yola email/password as a local offline verifier. For
    first-time enrolment, the password MUST be rechecked online against cloud,
    via a separately authenticated cloud bridge before commercial release.
    Hence only accounts that already exist locally can change their verifier.
    """
    raise HTTPException(503,'Offline owner provisioning needs the signed live desktop bridge; not enabled in this development candidate')

@app.post('/api/login')
async def login(request:Request,response:Response):
    body=await request.json();email=str(body.get('email','')).lower().strip();password=body.get('password','')
    if not password:raise HTTPException(401,'Invalid credentials')
    try:tenant,_=lease()
    except HTTPException:
        result,client=begin_session('login',{'email':email,'password':password})
        token=secrets.token_urlsafe(32)
        _pending_accounts[token]={'client':client,'expires':datetime.now(timezone.utc)+timedelta(hours=2)}
        response.set_cookie('yola_setup',token,httponly=True,samesite='strict',max_age=7200)
        return result
    with db() as c:
        rule=one(c,'SELECT enabled FROM yola_local_staff_rules WHERE tenant=? AND email=?',tenant,email)
        if rule and not rule['enabled']:raise HTTPException(403,'Staff access disabled by owner')
        u=one(c,'SELECT * FROM yola_local_accounts WHERE tenant=? AND lower(email)=? AND active=1',tenant,email)
    if not u or not hmac.compare_digest(hash_password(password,u['pass_salt']),u['pass_hash']):
        # New user or password change: contact the actual Yola server once.
        u=cache_verified_staff(tenant,_,email,password)
    with db() as c:
        token=secrets.token_urlsafe(32)
        c.execute('INSERT INTO yola_local_sessions VALUES(?,?,?)',(phash(token),u['id'],(datetime.now(timezone.utc)+timedelta(hours=12)).isoformat()))
    response.set_cookie('yola_offline_session',token,httponly=True,samesite='strict',secure=False,max_age=12*3600)
    return {'success':True}

@app.post('/api/register')
async def register(request:Request,response:Response):
    # Initial account creation is sent to the ORIGINAL cloud Master-controlled
    # registration API. A local account or licence is never self-created.
    body=await request.json()
    result,client=begin_session('register',{k:body.get(k) for k in ('business','name','email','phone','password')})
    token=secrets.token_urlsafe(32)
    _pending_accounts[token]={'client':client,'expires':datetime.now(timezone.utc)+timedelta(hours=2)}
    response.set_cookie('yola_setup',token,httponly=True,samesite='strict',max_age=7200)
    return result

@app.post('/api/invites/accept')
async def accept_invite(request:Request,response:Response):
    body=await request.json()
    result,client=begin_session('invites/accept',{k:body.get(k) for k in ('token','name','email','password')})
    token=secrets.token_urlsafe(32)
    _pending_accounts[token]={'client':client,'expires':datetime.now(timezone.utc)+timedelta(hours=2)}
    response.set_cookie('yola_setup',token,httponly=True,samesite='strict',max_age=7200)
    return result

@app.get('/api/device-registration')
def registration_guide():
    return {'registrationUrl':'https://yola-onboarding.vercel.app/',
            'deviceActivationUrl':'/legacy/','activationAuthority':'DG Tech Master Control',
            'status':'pending' if not cached_license_valid() else 'active'}

@app.get('/api/pos/products')
def products(request:Request):
    u,t,_=auth(request,{'owner','manager','worker'})
    with db() as c:
        products=rows(c,'SELECT * FROM yola_local_products WHERE tenant=? AND active=1 ORDER BY category,name LIMIT 1000',t)
    for p in products:
        p['margin_percent']=round(100*(p['price_cents']-p['cost_cents'])/p['price_cents'],2) if p['price_cents'] else None
    if u['role']=='worker':
        for p in products:
            p.pop('cost_cents',None)
            p.pop('margin_percent',None)
    return {'products':products}

@app.get('/api/pos/summary')
def summary(request:Request):
    u,t,_=auth(request)
    with db() as c:
        today=datetime.now().strftime('%Y-%m-%d')
        query='SELECT count(*) AS sales_count,coalesce(sum(total_cents),0) AS sales_total FROM yola_local_sales WHERE tenant=? AND substr(created_at,1,10)=?'
        args=[t,today]
        if u['role']=='worker':query+=' AND cashier_id=?';args.append(u['id'])
        counts=one(c,query,*args)
        if u['role']!='worker':counts.update(one(c,"SELECT count(*) AS products,coalesce(sum(CASE WHEN kind='stock' AND stock_qty<=min_stock THEN 1 ELSE 0 END),0) AS low_stock FROM yola_local_products WHERE tenant=? AND active=1",t))
    return {'summary':counts}

@app.post('/api/pos/product')
async def product(request:Request):
    u,t,_=auth(request,{'owner','manager'},'inventory')
    b=await request.json()
    name=str(b.get('name') or '').strip()[:140]
    if not name:raise HTTPException(422,'Product name required')
    kind=b.get('kind','stock')
    if kind not in ('stock','service'):raise HTTPException(422,'Invalid item type')
    price=cents(b.get('price_cents',-1))
    cost=cents(b.get('cost_cents',0))
    initial=cents(b.get('stock_qty',0))
    min_stock=cents(b.get('min_stock',5))
    tax=cents(b.get('tax_bps',0))
    if tax>3000:raise HTTPException(422,'Invalid tax')
    if kind=='service' and initial:raise HTTPException(422,'Services cannot have stock quantities')
    p={'id':uid(),'tenant':t,'name':name,'sku':str(b.get('sku','')).strip()[:70] or 'YL-'+secrets.token_hex(6).upper(),
       'barcode':str(b.get('barcode') or '')[:140],'category':str(b.get('category') or 'General').strip()[:100],
       'quality':str(b.get('quality') or '').strip()[:120],'kind':kind,
       'price_cents':price,'cost_cents':cost,'tax_bps':tax,'stock_qty':initial,'min_stock':min_stock,'active':1,'created_at':now()}
    try:
        with db() as c:
            c.execute('''INSERT INTO yola_local_products
              (id,tenant,name,sku,barcode,category,quality,kind,price_cents,cost_cents,tax_bps,stock_qty,min_stock,active,created_at)
              VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',tuple(p.values()))
            if kind=='stock' and initial*cost:
                journal(c,t,'opening_stock',p['id'],'Opening stock '+name,[('1200',initial*cost,0),('3000',0,initial*cost)])
            low_stock(c,t,p,min_stock+1,initial)
            event(c,t,'product.create',p)
    except sqlite3.IntegrityError:raise HTTPException(409,'SKU already registered')
    return {'id':p['id'],'margin_percent':round(100*(price-cost)/price,2) if price else None}


@app.post('/api/pos/product/edit')
async def edit_product(request:Request):
    u,t,_=auth(request,{'owner','manager'},'inventory')
    b=await request.json()
    pid=str(b.get('product_id') or '')
    allowed=('name','quality','category','barcode','price_cents','cost_cents','tax_bps','min_stock')
    changes={}
    for key in allowed:
        if key not in b:continue
        if key in ('price_cents','cost_cents','tax_bps','min_stock'):
            changes[key]=cents(b[key])
        else:
            lengths={'name':140,'quality':120,'category':100,'barcode':140}
            changes[key]=str(b[key] or '').strip()[:lengths[key]]
    if not changes:raise HTTPException(422,'No valid changes')
    if 'name' in changes and not changes['name']:raise HTTPException(422,'Item name required')
    if 'category' in changes and not changes['category']:raise HTTPException(422,'Category required')
    if changes.get('tax_bps',0)>3000:raise HTTPException(422,'Invalid tax')
    with db() as c:
        c.execute('BEGIN IMMEDIATE')
        prior=one(c,'SELECT * FROM yola_local_products WHERE tenant=? AND id=? AND active=1',t,pid)
        if not prior:raise HTTPException(404,'Item not found')
        # Inventory quantities only change through stock adjustments (audited).
        c.execute('UPDATE yola_local_products SET '+','.join(k+'=?' for k in changes)+' WHERE tenant=? AND id=?',
                  (*changes.values(),t,pid))
        updated=one(c,'SELECT * FROM yola_local_products WHERE tenant=? AND id=?',t,pid)
        event(c,t,'product.edit',{'product_id':pid,'changed_fields':list(changes),'before':prior,'after':updated,'actor':u['id']})
        if 'min_stock' in changes:low_stock(c,t,updated,prior['min_stock']+1,updated['stock_qty'])
    return {'success':True,'product':updated,
        'margin_percent':round(100*(updated['price_cents']-updated['cost_cents'])/updated['price_cents'],2) if updated['price_cents'] else None}


@app.post('/api/pos/archive-product')
async def archive(request:Request):
    u,t,_=auth(request,{'owner','manager'},'inventory');b=await request.json()
    with db() as c:
        cur=c.execute('UPDATE yola_local_products SET active=0 WHERE id=? AND tenant=? AND active=1',(b.get('product_id'),t))
        if not cur.rowcount:raise HTTPException(404,'Product not found')
        event(c,t,'product.archive',{'product_id':b.get('product_id')})
    return {'success':True,'archived':True}

@app.post('/api/pos/stock')
async def stock(request:Request):
    u,t,_=auth(request,{'owner','manager'},'inventory');b=await request.json();delta=b.get('delta')
    if isinstance(delta,bool) or not isinstance(delta,int) or delta==0 or abs(delta)>100000:raise HTTPException(422,'Invalid stock adjustment')
    with db() as c:
        p=one(c,'SELECT * FROM yola_local_products WHERE id=? AND tenant=? AND active=1',b.get('product_id'),t)
        if not p:raise HTTPException(404,'Product not found')
        if p.get('kind')=='service':raise HTTPException(422,'Service items do not have stock')
        if p['stock_qty']+delta<0:raise HTTPException(422,'Insufficient stock')
        c.execute('UPDATE yola_local_products SET stock_qty=stock_qty+? WHERE id=?',(delta,p['id']))
        low_stock(c,t,p,p['stock_qty'],p['stock_qty']+delta)
        value=abs(delta*p['cost_cents'])
        if value:journal(c,t,'stock_adjustment',p['id'],'Stock adjustment', [('1200',value,0),('4900',0,value)] if delta>0 else [('6200',value,0),('1200',0,value)])
        event(c,t,'stock.adjust',{'product_id':p['id'],'delta':delta,'reason':str(b.get('reason',''))[:140]})
    return {'success':True}

def customer_snapshot(c,tenant,customer_id):
    customer=one(c,'SELECT * FROM yola_local_customers WHERE tenant=? AND id=? AND active=1',tenant,customer_id)
    if not customer:raise HTTPException(404,'Customer not found')
    sales=rows(c,'''SELECT s.id,s.number AS sale_number,s.total_cents,s.due_date,s.created_at,
        EXISTS(SELECT 1 FROM yola_local_refunds r WHERE r.tenant=s.tenant AND r.sale_id=s.id) AS refunded,
        coalesce((SELECT sum(a.amount_cents) FROM yola_local_customer_allocations a
          WHERE a.tenant=s.tenant AND a.sale_id=s.id),0) AS allocated_cents
        FROM yola_local_sales s WHERE s.tenant=? AND s.customer_id=?
        AND s.payment_method='credit' ORDER BY s.due_date,s.created_at''',tenant,customer_id)
    total_balance=overdue=0
    today=datetime.now(timezone.utc).date().isoformat()
    for sale in sales:
        sale['remaining_cents']=(0 if sale['refunded'] else sale['total_cents'])-sale['allocated_cents']
        total_balance+=sale['remaining_cents']
        if sale['due_date'] and sale['due_date']<today and sale['remaining_cents']>0:
            overdue+=sale['remaining_cents']
    money=rows(c,'''SELECT kind,coalesce(sum(amount_cents),0) AS amount FROM yola_local_customer_cash_entries
        WHERE tenant=? AND customer_id=? GROUP BY kind''',tenant,customer_id)
    kinds={x['kind']:x['amount'] for x in money}
    deposit=kinds.get('deposit',0)-kinds.get('apply_deposit',0)
    return {'customer':customer,'sales':sales,'balance_cents':total_balance,
            'due_cents':max(0,total_balance),'customer_credit_cents':max(0,-total_balance),
            'deposit_cents':deposit,'overdue_cents':overdue}


def _allocate_customer_credit(c,tenant,customer_id,entry_id,amount):
    remaining=amount
    snapshot=customer_snapshot(c,tenant,customer_id)
    for sale in snapshot['sales']:
        open_amount=max(0,sale['remaining_cents'])
        applying=min(open_amount,remaining)
        if applying:
            c.execute('''INSERT INTO yola_local_customer_allocations VALUES(?,?,?,?,?)''',
                (uid(),tenant,entry_id,sale['id'],applying))
            remaining-=applying
        if not remaining:break
    if remaining:raise HTTPException(409,'Amount exceeds outstanding invoices')


@app.get('/api/pos/customers')
def customers(request:Request):
    u,t,_=auth(request,{'owner','manager','worker'})
    with db() as c:
        listing=rows(c,'SELECT * FROM yola_local_customers WHERE tenant=? AND active=1 ORDER BY name',t)
        if u['role']=='worker':
            return {'customers':[{'id':v['id'],'name':v['name']} for v in listing]}
        return {'customers':[{**v,**{k:value for k,value in customer_snapshot(c,t,v['id']).items()
                   if k in ('due_cents','deposit_cents','overdue_cents','customer_credit_cents')}}
                   for v in listing]}


@app.get('/api/pos/customer')
def customer_detail(request:Request,id:str):
    u,t,_=auth(request,{'owner','manager'},'customers')
    with db() as c:
        result=customer_snapshot(c,t,id)
        result['payments']=rows(c,'''SELECT kind,amount_cents,payment_method,reference,created_at
            FROM yola_local_customer_cash_entries WHERE tenant=? AND customer_id=?
            ORDER BY created_at DESC LIMIT 150''',t,id)
        return result


@app.post('/api/pos/customer')
async def save_customer(request:Request):
    u,t,_=auth(request,{'owner','manager'},'customers')
    b=await request.json()
    name=str(b.get('name') or '').strip()[:140]
    if not name:raise HTTPException(422,'Customer name required')
    limit=cents(b.get('credit_limit_cents',0))
    days=b.get('terms_days',30)
    if isinstance(days,bool) or not isinstance(days,int) or not 0<=days<=365:
        raise HTTPException(422,'Payment terms must be 0–365 days')
    cid=str(b.get('id') or uid())
    with db() as c:
        prior=one(c,'SELECT id FROM yola_local_customers WHERE id=? AND tenant=? AND active=1',cid,t)
        if b.get('id') and not prior:raise HTTPException(404,'Customer not found')
        if prior:
            c.execute('''UPDATE yola_local_customers SET name=?,phone=?,email=?,credit_limit_cents=?,terms_days=?
                WHERE id=? AND tenant=?''',(name,str(b.get('phone') or '')[:50],
                str(b.get('email') or '')[:200],limit,days,cid,t))
        else:
            c.execute('''INSERT INTO yola_local_customers VALUES (?,?,?,?,?,?,?,?,?)''',
                      (cid,t,name,str(b.get('phone') or '')[:50],
                       str(b.get('email') or '')[:200],limit,days,1,now()))
        event(c,t,'customer.save',{'id':cid,'name':name,'terms_days':days,'actor':u['id']})
    return {'id':cid,'success':True}


@app.post('/api/pos/customer/settle')
async def settle_customer(request:Request):
    u,t,_=auth(request,{'owner','manager'},'customers')
    b=await request.json()
    kind=b.get('kind')
    if kind not in ('payment','deposit','apply_deposit'):raise HTTPException(422,'Invalid customer payment type')
    amount=cents(b.get('amount_cents',-1))
    if not amount:raise HTTPException(422,'Enter a positive amount')
    method=str(b.get('payment_method') or '')
    if kind!='apply_deposit' and method not in ('cash','bank','mobile','card'):
        raise HTTPException(422,'Invalid payment method')
    if kind=='apply_deposit':method='deposit'
    key=str(b.get('idempotency_key') or '')
    if not 10<=len(key)<=100:raise HTTPException(422,'Idempotency key required')
    cid=str(b.get('customer_id') or '')
    cash_code={'cash':'1000','bank':'1010','card':'1010','mobile':'1020'}.get(method)
    with db() as c:
        c.execute('BEGIN IMMEDIATE')
        old=one(c,'SELECT id,kind,amount_cents,customer_id FROM yola_local_customer_cash_entries WHERE tenant=? AND idempotency_key=?',t,key)
        if old:
            if (old['customer_id'],old['kind'],old['amount_cents'])!=(cid,kind,amount):
                raise HTTPException(409,'Payment key reused with different details')
            return {'success':True,'duplicate':True,'id':old['id']}
        snapshot=customer_snapshot(c,t,cid)
        if kind in ('payment','apply_deposit') and amount>snapshot['due_cents']:
            raise HTTPException(422,'Amount exceeds customer dues. Record excess as a deposit.')
        if kind=='apply_deposit' and amount>snapshot['deposit_cents']:
            raise HTTPException(422,'Insufficient customer deposit')
        eid=uid()
        c.execute('''INSERT INTO yola_local_customer_cash_entries
            (id,tenant,customer_id,kind,amount_cents,payment_method,reference,idempotency_key,created_by,created_at)
            VALUES (?,?,?,?,?,?,?,?,?,?)''',
            (eid,t,cid,kind,amount,method,str(b.get('reference') or '')[:160],key,u['id'],now()))
        if kind in ('payment','apply_deposit'):
            _allocate_customer_credit(c,t,cid,eid,amount)
        entries=(
            [(cash_code,amount,0),('1100',0,amount)] if kind=='payment'
            else [(cash_code,amount,0),('2100',0,amount)] if kind=='deposit'
            else [('2100',amount,0),('1100',0,amount)]
        )
        journal(c,t,'customer.'+kind,eid,kind+' for '+snapshot['customer']['name'],entries)
        event(c,t,'customer.'+kind,{'id':eid,'customer_id':cid,'kind':kind,
            'amount_cents':amount,'payment_method':method,'reference':str(b.get('reference') or '')[:160]})
        result=customer_snapshot(c,t,cid)
    return {'id':eid,'success':True,'due_cents':result['due_cents'],
            'deposit_cents':result['deposit_cents']}


@app.post('/api/pos/checkout')
async def checkout(request:Request):
    u,t,_=auth(request,{'owner','manager','worker'});b=await request.json();items=b.get('items')
    if not isinstance(items,list) or not 1<=len(items)<=100:raise HTTPException(422,'Add items to cart')
    if b.get('payment_method') not in {'cash','bank','card','mobile','credit'}:raise HTTPException(422,'Invalid payment method')
    if b['payment_method']=='credit':
        auth(request,{'owner','manager'},'credit')
    key=str(b.get('idempotency_key') or '');
    if not 10<=len(key)<=100:raise HTTPException(422,'Checkout requires idempotency key')
    discount=cents(b.get('discount_cents',0))
    with db() as c:
        c.execute('BEGIN IMMEDIATE')
        prior=one(c,'SELECT id,number AS sale_number,total_cents FROM yola_local_sales WHERE tenant=? AND idempotency_key=?',t,key)
        if prior:return {'sale':{**prior,'duplicate':True}}
        lines=[];subtotal=cost=stock_cost=service_cost=0
        for i in sorted(items,key=lambda q:str(q.get('id',''))):
            q=i.get('qty')
            if not isinstance(q,int) or isinstance(q,bool) or q<1 or q>100000:raise HTTPException(422,'Invalid quantity')
            p=one(c,'SELECT * FROM yola_local_products WHERE id=? AND tenant=? AND active=1',i.get('id'),t)
            if not p:raise HTTPException(404,'Product not found')
            if p.get('kind','stock')!='service' and p['stock_qty']<q:raise HTTPException(422,'Insufficient stock for '+p['name'])
            if any(x['id']==p['id'] for x in lines):raise HTTPException(422,'Duplicate product')
            lines.append({**p,'qty':q})
            subtotal+=p['price_cents']*q
            line_cost=p['cost_cents']*q
            cost+=line_cost
            if p.get('kind','stock')=='service':service_cost+=line_cost
            else:stock_cost+=line_cost
        if discount>subtotal:raise HTTPException(422,'Discount exceeds sale subtotal')
        sale_no=c.execute('SELECT coalesce(max(number),0)+1 FROM yola_local_sales WHERE tenant=?',(t,)).fetchone()[0]
        taxes=0; computed=[]
        for p in lines:
            net=round(p['price_cents']*p['qty']*(subtotal-discount)/subtotal) if subtotal else 0
            tax=round(net*p['tax_bps']/10000);taxes+=tax;computed.append((p,net,tax))
        total=subtotal-discount+taxes;sid=uid()
        customer_id=str(b.get('customer_id') or '') or None
        due_date=None
        customer_name=str(b.get('customer_name') or '')[:120]
        if b['payment_method']=='credit' and not customer_id:
            raise HTTPException(422,'Select a registered customer for credit sales')
        if customer_id:
            customer=customer_snapshot(c,t,customer_id)
            customer_name=customer['customer']['name']
            if b['payment_method']=='credit':
                limit=customer['customer']['credit_limit_cents']
                if limit and customer['due_cents']+total>limit:
                    raise HTTPException(422,'Customer credit limit exceeded')
                due_date=(datetime.now(timezone.utc)+timedelta(days=customer['customer']['terms_days'])).date().isoformat()
        c.execute('''INSERT INTO yola_local_sales
            (id,tenant,cashier_id,number,subtotal_cents,discount_cents,tax_cents,total_cents,
             cost_cents,payment_method,customer_name,idempotency_key,created_at,customer_id,due_date)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
            (sid,t,u['id'],sale_no,subtotal,discount,taxes,total,cost,
             b['payment_method'],customer_name,key,now(),customer_id,due_date))
        for p,net,tax in computed:
            c.execute('''INSERT INTO yola_local_sale_lines
                  (id,tenant,sale_id,product_id,name,qty,unit_price_cents,unit_cost_cents,net_cents,tax_cents,total_cents,kind)
                  VALUES(?,?,?,?,?,?,?,?,?,?,?,?)''',
                  (uid(),t,sid,p['id'],p['name'],p['qty'],p['price_cents'],p['cost_cents'],net,tax,net+tax,p.get('kind','stock')))
            if p.get('kind','stock')!='service':
                updated=c.execute('UPDATE yola_local_products SET stock_qty=stock_qty-? WHERE id=? AND tenant=? AND stock_qty>=?',
                                  (p['qty'],p['id'],t,p['qty']))
                if updated.rowcount!=1:raise HTTPException(409,'Stock changed. Please retry checkout')
                low_stock(c,t,p,p['stock_qty'],p['stock_qty']-p['qty'])
        entries=[({'cash':'1000','bank':'1010','card':'1010','mobile':'1020','credit':'1100'}[b['payment_method']],total,0),('4000',0,subtotal-discount),('2000',0,taxes)]
        if stock_cost:entries.extend([('5000',stock_cost,0),('1200',0,stock_cost)])
        if service_cost:entries.extend([('5100',service_cost,0),('2200',0,service_cost)])
        journal(c,t,'sale',sid,'Sale #'+str(sale_no),entries)
        event(c,t,'sale.complete',{'sale':one(c,'SELECT * FROM yola_local_sales WHERE tenant=? AND id=?',t,sid),
           'lines':rows(c,'SELECT * FROM yola_local_sale_lines WHERE tenant=? AND sale_id=?',t,sid),
           'cashier_email':u['email']})
    return {'sale':{'id':sid,'sale_number':sale_no,'total_cents':total}}

@app.get('/api/pos/sales')
def sales(request:Request):
    u,t,_=auth(request)
    with db() as c:
        query='''SELECT s.id,s.number AS sale_number,s.total_cents,s.tax_cents,s.payment_method,s.customer_name,s.created_at,u.name AS cashier_name,
            (SELECT count(*) FROM yola_local_refunds r WHERE r.tenant=s.tenant AND r.sale_id=s.id) AS refunded FROM yola_local_sales s
            JOIN yola_local_accounts u ON u.id=s.cashier_id WHERE s.tenant=?'''
        args=[t]
        if u['role']=='worker':query+=' AND s.cashier_id=?';args.append(u['id'])
        return {'sales':rows(c,query+' ORDER BY s.created_at DESC LIMIT 100',*args)}

@app.get('/api/pos/receipt')
def receipt(request:Request,id:str):
    u,t,_=auth(request)
    with db() as c:
        query='''SELECT s.id,s.number AS sale_number,s.subtotal_cents,s.discount_cents,s.tax_cents,s.total_cents,s.payment_method,
            s.customer_name,s.created_at,a.name AS cashier_name FROM yola_local_sales s JOIN yola_local_accounts a ON a.id=s.cashier_id
            WHERE s.id=? AND s.tenant=?'''
        args=[id,t]
        if u['role']=='worker':query+=' AND s.cashier_id=?';args.append(u['id'])
        sale=one(c,query,*args)
        if not sale:raise HTTPException(404,'Receipt not found')
        lines=rows(c,'SELECT name,qty,unit_price_cents,net_cents,tax_cents,total_cents FROM yola_local_sale_lines WHERE tenant=? AND sale_id=?',t,id)
        return {'sale':sale,'lines':lines,'branding':setting(c,t)}

@app.post('/api/pos/refund')
async def refund(request:Request):
    u,t,_=auth(request,{'owner','manager'},'refund');b=await request.json();sid=b.get('sale_id');reason=str(b.get('reason') or '').strip();restock=b.get('restock') is True
    if len(reason)<3:raise HTTPException(422,'Refund reason required')
    with db() as c:
        c.execute('BEGIN IMMEDIATE')
        s=one(c,'SELECT * FROM yola_local_sales WHERE id=? AND tenant=?',sid,t)
        if not s:raise HTTPException(404,'Sale not found')
        if one(c,'SELECT id FROM yola_local_refunds WHERE tenant=? AND sale_id=?',t,sid):raise HTTPException(409,'Already refunded')
        # A credit invoice with allocated customer payments needs a separate credit-note/
        # refund-allocation workflow. Never silently create negative receivables.
        if s['payment_method']=='credit' and one(c,'SELECT id FROM yola_local_customer_allocations WHERE tenant=? AND sale_id=?',t,sid):
            raise HTTPException(409,'Credit sale has allocated payments. Reconcile with a credit note before refunding.')
        rid=uid();c.execute('INSERT INTO yola_local_refunds VALUES(?,?,?,?,?,?)',(rid,t,sid,reason,int(restock),now()))
        subtotal=s['subtotal_cents']-s['discount_cents']
        entries=[('4000',subtotal,0),('2000',s['tax_cents'],0),({'cash':'1000','card':'1010','mobile':'1020','bank':'1010','credit':'1100'}[s['payment_method']],0,s['total_cents'])]
        if restock:
            lines=rows(c,'SELECT * FROM yola_local_sale_lines WHERE tenant=? AND sale_id=?',t,sid)
            stock_cost=sum(line['qty']*line['unit_cost_cents'] for line in lines if line.get('kind','stock')=='stock')
            for line in lines:
                if line.get('kind','stock')=='stock':
                    c.execute('UPDATE yola_local_products SET stock_qty=stock_qty+? WHERE id=? AND tenant=?',(line['qty'],line['product_id'],t))
            if stock_cost:entries += [('1200',stock_cost,0),('5000',0,stock_cost)]
        # Reversing a service sale also reverses its accrued delivery expense.
        # A stock return reverses COGS only if physically restocked.
        service_cost=c.execute('''SELECT coalesce(sum(qty*unit_cost_cents),0) FROM yola_local_sale_lines
            WHERE tenant=? AND sale_id=? AND kind='service' ''',(t,sid)).fetchone()[0]
        if service_cost:entries += [('2200',service_cost,0),('5100',0,service_cost)]
        journal(c,t,'refund',sid,reason,entries)
        event(c,t,'refund',{'id':rid,'sale_id':sid,'reason':reason,'restock':restock,'cashier_email':u['email']})
    return {'success':True}

@app.post('/api/pos/expense')
async def expense(request:Request):
    u,t,_=auth(request,{'owner'});b=await request.json();title=str(b.get('title') or '').strip()[:150];amount=cents(b.get('amount_cents',-1));method=b.get('payment_method')
    if not title or not amount or method not in {'cash','bank','mobile','card'}:raise HTTPException(422,'Invalid expense')
    expense_id=uid()
    with db() as c:
        c.execute('INSERT INTO yola_local_expenses VALUES(?,?,?,?,?,?,?)',(expense_id,t,title,amount,method,u['id'],now()))
        journal(c,t,'expense',expense_id,title,[('6100',amount,0),({'cash':'1000','bank':'1010','mobile':'1020','card':'1010'}[method],0,amount)])
        event(c,t,'expense',{'id':expense_id,'amount_cents':amount,'title':title,'payment_method':method,'owner_email':u['email'],'created_at':now()})
    return {'id':expense_id}

@app.get('/api/pos/expenses')
def expenses(request:Request):
    u,t,_=auth(request,{'owner'});
    with db() as c:return {'expenses':rows(c,'''SELECT e.id,e.title,e.amount_cents,e.payment_method,e.created_at,u.name AS created_by FROM yola_local_expenses e JOIN yola_local_accounts u ON u.id=e.created_by WHERE e.tenant=? ORDER BY e.created_at DESC LIMIT 100''',t)}

CHART=[('1000','Cash','asset'),('1010','Bank and card clearing','asset'),('1020','Mobile money','asset'),('2100','Customer advance deposits','liability'),('2200','Accrued service delivery costs','liability'),('1100','Accounts receivable','asset'),('1200','Inventory','asset'),('2000','Tax payable','liability'),('3000','Opening capital','equity'),('4000','Sales revenue','income'),('4900','Stock adjustment income','income'),('5000','Cost of goods sold','expense'),('5100','Service delivery costs','expense'),('6100','Operating expenses','expense'),('6200','Stock shrinkage','expense')]
@app.get('/api/pos/accounts')
def accounts(request:Request):
    u,t,_=auth(request,{'owner'});
    with db() as c:
        data={r['code']:r for r in rows(c,'SELECT code,sum(debit_cents) AS debits,sum(credit_cents) AS credits FROM yola_local_entries WHERE tenant=? GROUP BY code',t)}
    acc=[];debit=credit=revenue=expense=assets=liabilities=equity=0
    for code,name,type in CHART:
        d=data.get(code,{'debits':0,'credits':0});dr=d['debits'];cr=d['credits'];debit+=dr;credit+=cr
        acc.append({'code':code,'name':name,'type':type,'debit_cents':str(dr),'credit_cents':str(cr),'balance_cents':str(dr-cr)})
        if type=='income':revenue+=cr-dr
        if type=='expense':expense+=dr-cr
        if type=='asset':assets+=dr-cr
        if type=='liability':liabilities+=cr-dr
        if type=='equity':equity+=cr-dr
    return {'accounts':acc,'trial_balance':{'debits_cents':debit,'credits_cents':credit,'balanced':debit==credit},'profit_and_loss':{'revenue_cents':revenue,'expense_cents':expense,'profit_cents':revenue-expense},'balance_sheet':{'assets_cents':assets,'liabilities_cents':liabilities,'equity_cents':equity,'retained_earnings_cents':revenue-expense,'balanced':assets==liabilities+equity+revenue-expense}}

@app.get('/api/pos/documents')
def documents(request:Request):
    u,t,_=auth(request,{'owner','manager'});
    with db() as c:return {'documents':rows(c,"SELECT id,document_no,kind,customer_name,total_cents,created_at,'issued' AS status FROM yola_local_documents WHERE tenant=? ORDER BY created_at DESC LIMIT 100",t)}

@app.get('/api/pos/document')
def document(request:Request,id:str):
    u,t,_=auth(request,{'owner','manager'});
    with db() as c:
        d=one(c,'SELECT * FROM yola_local_documents WHERE tenant=? AND id=?',t,id)
        if not d:raise HTTPException(404,'Document not found')
        d['items']=json.loads(d['items'])
        return {'document':d,'branding':setting(c,t)}

@app.post('/api/pos/document')
async def create_document(request:Request):
    u,t,_=auth(request,{'owner','manager'});b=await request.json()
    if b.get('kind') not in {'invoice','quotation'}:raise HTTPException(422,'Invalid document kind')
    customer=str(b.get('customer_name') or '').strip()
    if len(customer)<2:raise HTTPException(422,'Customer name required')
    lines=b.get('lines');
    if not isinstance(lines,list) or not 1<=len(lines)<=100:raise HTTPException(422,'Add document items')
    clean=[];subtotal=tax=0
    for line in lines:
        name=str(line.get('name') or '').strip()[:150];q=line.get('qty');price=cents(line.get('unit_cents',-1));bps=cents(line.get('tax_bps',0))
        if not name or not isinstance(q,int) or q<1 or q>100000 or bps>3000:raise HTTPException(422,'Invalid document line')
        net=price*q;duty=round(net*bps/10000);subtotal+=net;tax+=duty
        clean.append({'name':name,'qty':q,'unit_cents':price,'tax_bps':bps,'net_cents':net,'tax_cents':duty,'total_cents':net+duty})
    id=uid()
    with db() as c:
        no=c.execute('SELECT coalesce(max(document_no),0)+1 FROM yola_local_documents WHERE tenant=?',(t,)).fetchone()[0]
        c.execute('INSERT INTO yola_local_documents VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',(id,t,no,b['kind'],customer,str(b.get('customer_contact') or ''),str(b.get('notes') or ''),json.dumps(clean),subtotal,tax,subtotal+tax,u['id'],now()))
        event(c,t,'document.create',{'document':{'id':id,'kind':b['kind'],'customer_name':customer,
          'customer_contact':str(b.get('customer_contact') or ''),'notes':str(b.get('notes') or ''),
          'items':clean,'subtotal_cents':subtotal,'tax_cents':tax,'total_cents':subtotal+tax,
          'created_at':now()},'owner_email':u['email']})
    return {'document':{'id':id,'document_no':no,'kind':b['kind'],'total_cents':subtotal+tax},'affectsSales':False,'affectsStock':False}

@app.get('/api/pos/settings')
def get_settings(request:Request):
    u,t,_=auth(request,{'owner'});
    with db() as c:
        s=setting(c,t)
        return {'settings':{**s,'whatsapp_opt_in':bool(s['whatsapp_opt_in']),'low_stock_alerts':bool(s['low_stock_alerts'])},'whatsapp':{'providerConfigured':False,'templateRequired':True}}

@app.post('/api/pos/settings')
async def save_settings(request:Request):
    u,t,_=auth(request,{'owner'});b=await request.json()
    if not isinstance(b.get('whatsapp_opt_in'),bool) or not isinstance(b.get('low_stock_alerts'),bool):raise HTTPException(422,'Invalid settings')
    phone=str(b.get('whatsapp_phone') or '').strip()
    if b['whatsapp_opt_in'] and not phone.startswith('+'):raise HTTPException(422,'Use country code (+263...) for WhatsApp')
    paper=b.get('receipt_paper') if b.get('receipt_paper') in {'58mm','80mm','A4'} else '80mm'
    with db() as c:
        c.execute('''INSERT INTO yola_local_settings VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(tenant) DO UPDATE SET
          whatsapp_phone=excluded.whatsapp_phone,whatsapp_opt_in=excluded.whatsapp_opt_in,low_stock_alerts=excluded.low_stock_alerts,
          receipt_footer=excluded.receipt_footer,receipt_phone=excluded.receipt_phone,business_address=excluded.business_address,receipt_paper=excluded.receipt_paper''',(t,phone,int(b['whatsapp_opt_in']),int(b['low_stock_alerts']),str(b.get('receipt_footer') or ''),str(b.get('receipt_phone') or ''),str(b.get('business_address') or ''),paper))
        event(c,t,'settings.update',{'receipt_paper':paper,'low_stock_alerts':b['low_stock_alerts']})
    return {'saved':True,'whatsappConfigured':False}

@app.get('/api/pos/alerts')
def alerts(request:Request):
    u,t,_=auth(request,{'owner'});
    with db() as c:
        return {'alerts':[dict(x,payload=json.loads(x['payload'])) for x in rows(c,'SELECT * FROM yola_local_alerts WHERE tenant=? ORDER BY created_at DESC LIMIT 30',t)],'providerConfigured':False}

@app.post('/api/pos/alerts/retry')
def retry_alerts(request:Request):
    auth(request,{'owner'})
    return {'delivery':{'configured':False,'sent':0}}

@app.get('/api/staff')
def staff(request:Request):
    u,t,_=auth(request,{'owner'});
    with db() as c:
        staff=rows(c,'''SELECT a.id,a.name,a.email,a.role,a.active,
                     coalesce(r.enabled,1) AS access_enabled,coalesce(r.permissions,'{}') AS permissions
                     FROM yola_local_accounts a
                     LEFT JOIN yola_local_staff_rules r ON r.tenant=a.tenant AND r.email=a.email
                     WHERE a.tenant=? ORDER BY a.name''',t)
        for person in staff:person['permissions']=json.loads(person['permissions'])
        return {'staff':staff}

@app.post('/api/staff/access')
async def staff_access(request:Request):
    """An owner may revoke staff access or narrow their existing cloud role.
    This cannot create accounts or elevate a worker to a manager.
    """
    owner,tenant,_=auth(request,{'owner'})
    b=await request.json()
    email=str(b.get('email') or '').strip().lower()
    active=b.get('enabled')
    if not isinstance(active,bool):raise HTTPException(422,'Enabled must be true or false')
    permissions=b.get('permissions',{})
    if not isinstance(permissions,dict) or set(permissions)-{'inventory','customers','credit','refund'}:
        raise HTTPException(422,'Unsupported staff permissions')
    if any(not isinstance(value,bool) for value in permissions.values()):
        raise HTTPException(422,'Permissions must be boolean')
    with db() as c:
        staff=one(c,'SELECT id,role FROM yola_local_accounts WHERE tenant=? AND email=?',tenant,email)
        if not staff:raise HTTPException(404,'Staff account not enrolled on this PC')
        if staff['role']=='owner' or staff['id']==owner['id']:
            raise HTTPException(403,'Owner account cannot be disabled or restricted here')
        if staff['role']=='worker' and any(permissions.values()):
            raise HTTPException(422,'Worker permissions cannot exceed the assigned sales-only cloud role')
        c.execute('''INSERT INTO yola_local_staff_rules(tenant,email,enabled,permissions,updated_by,updated_at)
            VALUES(?,?,?,?,?,?) ON CONFLICT(tenant,email) DO UPDATE SET
            enabled=excluded.enabled,permissions=excluded.permissions,updated_by=excluded.updated_by,
            updated_at=excluded.updated_at''',
            (tenant,email,int(active),json.dumps(permissions),owner['id'],now()))
        if not active:
            c.execute('''DELETE FROM yola_local_sessions WHERE account_id=?''',(staff['id'],))
        event(c,tenant,'staff.access',{'email':email,'enabled':active,'permissions':permissions,'actor':owner['id']})
    return {'success':True}


@app.post('/api/invites')
def offline_invites(request:Request):
    auth(request,{'owner'})
    raise HTTPException(503,'New staff invitations require an online Master Control sync. Offline staff can sign in if previously enrolled.')

# Serve precisely the live Yola screens/styles on local loopback. The JS/UI is unmodified.
@app.get('/')
def root():return FileResponse(STATIC_DIR/'index.html')

@app.get('/workspace.html')
def workspace():return FileResponse(STATIC_DIR/'workspace.html')

app.mount('/static',StaticFiles(directory=STATIC_DIR),name='static')
@app.get('/{asset}')
def static_asset(asset:str):
    if asset in {'pos.js','pos.css','premium.css','app.js','style.css','yola-brand.png','yola-brand-144.webp','yola-brand-180.webp'}:
        return FileResponse(STATIC_DIR/asset)
    raise HTTPException(404,'Not found')


# Upload from this PC is independent of checkout, so a missing connection NEVER
# interrupts a sale. ACK requires an actual committed Neon journal transaction.
def sync_local_events(limit=30):
    try:tenant,lic=lease()
    except HTTPException:return {'reconciled':0,'pending':0,'status':'licence_unavailable'}
    with db() as c:
        events=rows(c,'SELECT * FROM yola_local_events WHERE tenant=? AND synced=0 ORDER BY created_at,id LIMIT ?',tenant,limit)
    done=0
    for entry in events:
        try:
            ack=cloud_json('/api/sync/event',{'device_id':DEVICE_ID,'license_token':lic['license_token'],
                'event_key':entry['id'],'event_type':entry['kind'],
                'payload':json.loads(entry['payload'])},'POST',timeout=15)
            if not ack.get('stored'):raise RuntimeError('Cloud event was not durably stored')
            with db() as c:
                if ack.get('reconciled'):
                    c.execute('UPDATE yola_local_events SET synced=1,uploaded_at=?,last_error=NULL WHERE id=? AND tenant=?',(now(),entry['id'],tenant))
                    done+=1
                else:
                    c.execute('UPDATE yola_local_events SET uploaded_at=?,last_error=? WHERE id=? AND tenant=?',(now(),'Uploaded; awaiting confirmed accounting/inventory reconciliation',entry['id'],tenant))
            if not ack.get('reconciled'):break # preserve original ordering for dependent events
        except Exception as error:
            with db() as c:c.execute('UPDATE yola_local_events SET last_error=? WHERE id=? AND tenant=?',(str(error)[:500],entry['id'],tenant))
            break
    with db() as c:
        pending=c.execute('SELECT COUNT(*) FROM yola_local_events WHERE tenant=? AND synced=0',(tenant,)).fetchone()[0]
    return {'reconciled':done,'pending':pending,'status':'synced' if not pending else 'pending'}

@app.get('/api/sync/status')
def offline_sync_status(request:Request):
    u,t,_=auth(request,{'owner','manager'})
    with db() as c:
        count=c.execute('SELECT COUNT(*) FROM yola_local_events WHERE tenant=? AND synced=0',(t,)).fetchone()[0]
        latest=one(c,'SELECT last_error,uploaded_at FROM yola_local_events WHERE tenant=? AND synced=0 ORDER BY created_at LIMIT 1',t)
    return {'pending':count,'oldest':latest,'localOperationsContinueOffline':True}

@app.post('/api/sync/flush')
def offline_sync_flush(request:Request):
    auth(request,{'owner','manager'})
    return sync_local_events(limit=100)