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
from local_server import db, cached_license_valid, read_license, STATIC_DIR as LEGACY_STATIC
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
          synced INTEGER NOT NULL DEFAULT 0);
        CREATE INDEX IF NOT EXISTS yola_l_product_tenant ON yola_local_products(tenant,active,name);
        CREATE INDEX IF NOT EXISTS yola_l_sale_tenant ON yola_local_sales(tenant,created_at);
        CREATE INDEX IF NOT EXISTS yola_l_event_unsynced ON yola_local_events(tenant,synced);
        """)

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


def auth(request,allowed=None):
    tenant,license_info=lease()
    token=request.cookies.get('yola_offline_session','')
    if not token:raise HTTPException(401,'Please sign in')
    with db() as c:
        u=one(c,"""SELECT a.* FROM yola_local_accounts a JOIN yola_local_sessions s ON s.account_id=a.id
            WHERE s.token_hash=? AND s.expires_at>? AND a.active=1 AND a.tenant=?""",phash(token),now(),tenant)
    if not u:raise HTTPException(401,'Please sign in')
    if allowed and u['role'] not in allowed:raise HTTPException(403,'This account does not have permission')
    return u,tenant,license_info


def journal(c,tenant,source,source_id,description,entries):
    if sum(a for _,a,_ in entries)!=sum(a for _,_,a in entries):raise ValueError('Unbalanced journal')
    if not sum(x[1] for x in entries):return
    id=uid();c.execute("INSERT INTO yola_local_journals VALUES (?,?,?,?,?,?)",(id,tenant,source,source_id,description,now()))
    for code,debit,credit in entries:
        if debit or credit:c.execute('INSERT INTO yola_local_entries VALUES(?,?,?,?,?,?)',(uid(),tenant,id,code,debit,credit))


def event(c,tenant,kind,obj):
    c.execute('INSERT INTO yola_local_events VALUES(?,?,?,?,?,0)',(uid(),tenant,kind,json.dumps(obj),now()))


def low_stock(c,tenant,p,old_count,new_count):
    if old_count>p['min_stock'] and new_count<=p['min_stock']:
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
        products=rows(c,'SELECT * FROM yola_local_products WHERE tenant=? AND active=1 ORDER BY name LIMIT 1000',t)
    if u['role']=='worker':
        for p in products:p.pop('cost_cents',None)
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
        if u['role']!='worker':counts.update(one(c,'SELECT count(*) AS products,coalesce(sum(CASE WHEN stock_qty<=min_stock THEN 1 ELSE 0 END),0) AS low_stock FROM yola_local_products WHERE tenant=? AND active=1',t))
    return {'summary':counts}

@app.post('/api/pos/product')
async def product(request:Request):
    u,t,_=auth(request,{'owner','manager'});b=await request.json();name=str(b.get('name','')).strip()[:140]
    if not name:raise HTTPException(422,'Product name required')
    price=cents(b.get('price_cents',-1));cost=cents(b.get('cost_cents',0));initial=cents(b.get('stock_qty',0));min_stock=cents(b.get('min_stock',5));tax=cents(b.get('tax_bps',0))
    if tax>3000:raise HTTPException(422,'Invalid tax')
    p={'id':uid(),'tenant':t,'name':name,'sku':str(b.get('sku','')).strip()[:70] or 'YL-'+secrets.token_hex(6).upper(),
    'barcode':str(b.get('barcode') or ''),'category':str(b.get('category') or 'General'),'price_cents':price,'cost_cents':cost,'tax_bps':tax,'stock_qty':initial,'min_stock':min_stock,'active':1,'created_at':now()}
    try:
        with db() as c:
            c.execute('INSERT INTO yola_local_products VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',tuple(p.values()))
            if initial*cost:journal(c,t,'opening_stock',p['id'],'Opening stock '+name,[('1200',initial*cost,0),('3000',0,initial*cost)])
            low_stock(c,t,p,min_stock+1,initial)
            event(c,t,'product.create',p)
    except sqlite3.IntegrityError:raise HTTPException(409,'SKU already registered')
    return {'id':p['id']}

@app.post('/api/pos/archive-product')
async def archive(request:Request):
    u,t,_=auth(request,{'owner','manager'});b=await request.json()
    with db() as c:
        cur=c.execute('UPDATE yola_local_products SET active=0 WHERE id=? AND tenant=? AND active=1',(b.get('product_id'),t))
        if not cur.rowcount:raise HTTPException(404,'Product not found')
        event(c,t,'product.archive',{'product_id':b.get('product_id')})
    return {'success':True,'archived':True}

@app.post('/api/pos/stock')
async def stock(request:Request):
    u,t,_=auth(request,{'owner','manager'});b=await request.json();delta=b.get('delta')
    if isinstance(delta,bool) or not isinstance(delta,int) or delta==0 or abs(delta)>100000:raise HTTPException(422,'Invalid stock adjustment')
    with db() as c:
        p=one(c,'SELECT * FROM yola_local_products WHERE id=? AND tenant=? AND active=1',b.get('product_id'),t)
        if not p:raise HTTPException(404,'Product not found')
        if p['stock_qty']+delta<0:raise HTTPException(422,'Insufficient stock')
        c.execute('UPDATE yola_local_products SET stock_qty=stock_qty+? WHERE id=?',(delta,p['id']))
        low_stock(c,t,p,p['stock_qty'],p['stock_qty']+delta)
        value=abs(delta*p['cost_cents'])
        if value:journal(c,t,'stock_adjustment',p['id'],'Stock adjustment', [('1200',value,0),('4900',0,value)] if delta>0 else [('6200',value,0),('1200',0,value)])
        event(c,t,'stock.adjust',{'product_id':p['id'],'delta':delta,'reason':str(b.get('reason',''))[:140]})
    return {'success':True}

@app.post('/api/pos/checkout')
async def checkout(request:Request):
    u,t,_=auth(request,{'owner','manager','worker'});b=await request.json();items=b.get('items')
    if not isinstance(items,list) or not 1<=len(items)<=100:raise HTTPException(422,'Add items to cart')
    if b.get('payment_method') not in {'cash','bank','card','mobile','credit'}:raise HTTPException(422,'Invalid payment method')
    key=str(b.get('idempotency_key') or '');
    if not 10<=len(key)<=100:raise HTTPException(422,'Checkout requires idempotency key')
    discount=cents(b.get('discount_cents',0))
    with db() as c:
        c.execute('BEGIN IMMEDIATE')
        prior=one(c,'SELECT id,number AS sale_number,total_cents FROM yola_local_sales WHERE tenant=? AND idempotency_key=?',t,key)
        if prior:return {'sale':{**prior,'duplicate':True}}
        lines=[];subtotal=cost=0
        for i in sorted(items,key=lambda q:str(q.get('id',''))):
            q=i.get('qty')
            if not isinstance(q,int) or isinstance(q,bool) or q<1 or q>100000:raise HTTPException(422,'Invalid quantity')
            p=one(c,'SELECT * FROM yola_local_products WHERE id=? AND tenant=? AND active=1',i.get('id'),t)
            if not p:raise HTTPException(404,'Product not found')
            if p['stock_qty']<q:raise HTTPException(422,'Insufficient stock for '+p['name'])
            if any(x['id']==p['id'] for x in lines):raise HTTPException(422,'Duplicate product')
            lines.append({**p,'qty':q});subtotal+=p['price_cents']*q;cost+=p['cost_cents']*q
        if discount>subtotal:raise HTTPException(422,'Discount exceeds sale subtotal')
        sale_no=c.execute('SELECT coalesce(max(number),0)+1 FROM yola_local_sales WHERE tenant=?',(t,)).fetchone()[0]
        taxes=0; computed=[]
        for p in lines:
            net=round(p['price_cents']*p['qty']*(subtotal-discount)/subtotal) if subtotal else 0
            tax=round(net*p['tax_bps']/10000);taxes+=tax;computed.append((p,net,tax))
        total=subtotal-discount+taxes;sid=uid()
        c.execute('INSERT INTO yola_local_sales VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',(sid,t,u['id'],sale_no,subtotal,discount,taxes,total,cost,b['payment_method'],str(b.get('customer_name') or '')[:120],key,now()))
        for p,net,tax in computed:
            c.execute('INSERT INTO yola_local_sale_lines VALUES(?,?,?,?,?,?,?,?,?,?,?)',(uid(),t,sid,p['id'],p['name'],p['qty'],p['price_cents'],p['cost_cents'],net,tax,net+tax))
            c.execute('UPDATE yola_local_products SET stock_qty=stock_qty-? WHERE id=?',(p['qty'],p['id']))
            low_stock(c,t,p,p['stock_qty'],p['stock_qty']-p['qty'])
        entries=[({'cash':'1000','bank':'1010','card':'1010','mobile':'1020','credit':'1100'}[b['payment_method']],total,0),('4000',0,subtotal-discount),('2000',0,taxes)]
        if cost:entries.extend([('5000',cost,0),('1200',0,cost)])
        journal(c,t,'sale',sid,'Sale #'+str(sale_no),entries)
        event(c,t,'sale.complete',{'id':sid,'number':sale_no,'items':[{'id':p['id'],'qty':p['qty']} for p in lines],'total_cents':total,'idempotency_key':key})
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
    u,t,_=auth(request,{'owner','manager'});b=await request.json();sid=b.get('sale_id');reason=str(b.get('reason') or '').strip();restock=b.get('restock') is True
    if len(reason)<3:raise HTTPException(422,'Refund reason required')
    with db() as c:
        c.execute('BEGIN IMMEDIATE')
        s=one(c,'SELECT * FROM yola_local_sales WHERE id=? AND tenant=?',sid,t)
        if not s:raise HTTPException(404,'Sale not found')
        if one(c,'SELECT id FROM yola_local_refunds WHERE tenant=? AND sale_id=?',t,sid):raise HTTPException(409,'Already refunded')
        c.execute('INSERT INTO yola_local_refunds VALUES(?,?,?,?,?,?)',(uid(),t,sid,reason,int(restock),now()))
        subtotal=s['subtotal_cents']-s['discount_cents']
        entries=[('4000',subtotal,0),('2000',s['tax_cents'],0),({'cash':'1000','card':'1010','mobile':'1020','bank':'1010','credit':'1100'}[s['payment_method']],0,s['total_cents'])]
        if restock:
            lines=rows(c,'SELECT * FROM yola_local_sale_lines WHERE tenant=? AND sale_id=?',t,sid)
            for line in lines:c.execute('UPDATE yola_local_products SET stock_qty=stock_qty+? WHERE id=? AND tenant=?',(line['qty'],line['product_id'],t))
            if s['cost_cents']:entries += [('1200',s['cost_cents'],0),('5000',0,s['cost_cents'])]
        journal(c,t,'refund',sid,reason,entries)
        event(c,t,'refund',{'sale_id':sid,'reason':reason,'restock':restock})
    return {'success':True}

@app.post('/api/pos/expense')
async def expense(request:Request):
    u,t,_=auth(request,{'owner'});b=await request.json();title=str(b.get('title') or '').strip()[:150];amount=cents(b.get('amount_cents',-1));method=b.get('payment_method')
    if not title or not amount or method not in {'cash','bank','mobile','card'}:raise HTTPException(422,'Invalid expense')
    expense_id=uid()
    with db() as c:
        c.execute('INSERT INTO yola_local_expenses VALUES(?,?,?,?,?,?,?)',(expense_id,t,title,amount,method,u['id'],now()))
        journal(c,t,'expense',expense_id,title,[('6100',amount,0),({'cash':'1000','bank':'1010','mobile':'1020','card':'1010'}[method],0,amount)])
        event(c,t,'expense',{'id':expense_id,'amount_cents':amount,'title':title})
    return {'id':expense_id}

@app.get('/api/pos/expenses')
def expenses(request:Request):
    u,t,_=auth(request,{'owner'});
    with db() as c:return {'expenses':rows(c,'''SELECT e.id,e.title,e.amount_cents,e.payment_method,e.created_at,u.name AS created_by FROM yola_local_expenses e JOIN yola_local_accounts u ON u.id=e.created_by WHERE e.tenant=? ORDER BY e.created_at DESC LIMIT 100''',t)}

CHART=[('1000','Cash','asset'),('1010','Bank and card clearing','asset'),('1020','Mobile money','asset'),('1100','Accounts receivable','asset'),('1200','Inventory','asset'),('2000','Tax payable','liability'),('3000','Opening capital','equity'),('4000','Sales revenue','income'),('4900','Stock adjustment income','income'),('5000','Cost of goods sold','expense'),('6100','Operating expenses','expense'),('6200','Stock shrinkage','expense')]
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
        event(c,t,'document.create',{'id':id,'kind':b['kind'],'total_cents':subtotal+tax})
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
        return {'staff':rows(c,'SELECT id,name,email,role,active FROM yola_local_accounts WHERE tenant=? ORDER BY name',t)}

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