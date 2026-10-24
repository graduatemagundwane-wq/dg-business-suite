"""Isolated acceptance for Mr Matenda's seven POS requests.
Uses a temp SQLite directory and synthetic accounts; never calls production.
"""
import os
import sys
import tempfile
from pathlib import Path
from datetime import datetime,timedelta,timezone

with tempfile.TemporaryDirectory(prefix='yola-client-qa-') as location:
    os.environ['DG_POS_DATA_DIR']=location
    sys.path.insert(0,str(Path(__file__).resolve().parent/'desktop'))
    from fastapi.testclient import TestClient
    import offline_web as y

    state={'tenant':'TENANT-CLIENT-QA'}
    y.lease=lambda: (state['tenant'],{
        'business_id':state['tenant'],'business_name':'Yola Synthetic QA',
        'request_code':'YOLA-QA','license_token':'fake in memory only',
        'lease_token':'fake in memory only'})
    y.verify_online_password=lambda email,password:{
        'id':'test-'+email,'name':email.split('@')[0],
        'email':email,'role':email.split('@')[0],
        'businessCode':'YOLA-QA','license':{'active':True}}
    def call(client,method,url,data=None,status=200):
        response=getattr(client,method)(url,json=data) if data is not None else getattr(client,method)(url)
        assert response.status_code==status,(method,url,response.status_code,response.text[:600])
        return response.json()
    owner=TestClient(y.app)
    worker=TestClient(y.app)
    manager=TestClient(y.app)
    call(owner,'post','/api/login',{'email':'owner@qa.local','password':'YolaTestOwner9876!'})
    call(worker,'post','/api/login',{'email':'worker@qa.local','password':'YolaTestWorker9876!'})
    call(manager,'post','/api/login',{'email':'manager@qa.local','password':'YolaTestManager9876!'})
    # (1) edit item name, quality, category and prices, and calculate margin.
    product=call(owner,'post','/api/pos/product',{
        'name':'Copier toner','category':'Office','price_cents':100,'cost_cents':50,'stock_qty':1})['id']
    items=call(owner,'get','/api/pos/products')['products']
    assert next(p for p in items if p['id']==product)['margin_percent']==50.0
    call(owner,'post','/api/pos/product/edit',{
        'product_id':product,'name':'Printer toner','quality':'OEM Grade A',
        'category':'Printing','price_cents':150,'cost_cents':50})
    toner=next(p for p in call(owner,'get','/api/pos/products')['products'] if p['id']==product)
    assert toner['name']=='Printer toner' and toner['quality']=='OEM Grade A'
    assert toner['category']=='Printing' and round(toner['margin_percent'],2)==66.67
    call(worker,'post','/api/pos/product/edit',{'product_id':product,'name':'hack'},status=403)

    # (2) no oversell, even using a stale checkout request.
    once={'items':[{'id':product,'qty':1}],'payment_method':'cash',
          'idempotency_key':'toner-sale-123456'}
    call(owner,'post','/api/pos/checkout',once)
    call(owner,'post','/api/pos/checkout',{**once,'idempotency_key':'toner-sale-654321'},status=422)
    assert next(p for p in call(owner,'get','/api/pos/products')['products'] if p['id']==product)['stock_qty']==0

    # (3) service sales are not stock-bound and do not invent inventory assets.
    service=call(owner,'post','/api/pos/product',{
        'name':'Photocopying','category':'Services','kind':'service',
        'price_cents':200,'cost_cents':80,'stock_qty':0})['id']
    call(owner,'post','/api/pos/stock',{'product_id':service,'delta':2},status=422)
    call(owner,'post','/api/pos/checkout',{
        'items':[{'id':service,'qty':3}],'payment_method':'cash',
        'idempotency_key':'service-sale-123456'})
    assert next(p for p in call(owner,'get','/api/pos/products')['products'] if p['id']==service)['stock_qty']==0

    # (4-5) margin and categorised stock are visible and correct.
    listing=call(owner,'get','/api/pos/products')['products']
    assert [x['category'] for x in listing]==sorted(x['category'] for x in listing)
    assert next(p for p in listing if p['id']==service)['margin_percent']==60.0

    # (6) owner-controlled staff restrictions, immediate session invalidation.
    call(owner,'post','/api/staff/access',{'email':'manager@qa.local','enabled':True,
        'permissions':{'inventory':False,'customers':True,'credit':True,'refund':False}})
    call(manager,'post','/api/pos/stock',{'product_id':product,'delta':1},status=403)
    call(manager,'post','/api/pos/customer',{'name':'Allowed customer','terms_days':10})
    call(owner,'post','/api/staff/access',{'email':'manager@qa.local','enabled':False,'permissions':{}})
    call(manager,'get','/api/staff',status=401)
    call(manager,'post','/api/login',{'email':'manager@qa.local','password':'YolaTestManager9876!'},status=403)
    call(owner,'post','/api/staff/access',{'email':'manager@qa.local','enabled':True,'permissions':{}})

    # (7) credit, deposits, receivables, payments, outstanding and overdue alerts.
    cust=call(owner,'post','/api/pos/customer',{
        'name':'Arch-Tech synthetic client','terms_days':7,'credit_limit_cents':1000})['id']
    call(worker,'post','/api/pos/checkout',{
        'items':[{'id':service,'qty':1}],'payment_method':'credit',
        'idempotency_key':'worker-credit-blocked','customer_id':cust},status=403)
    credit_order={'items':[{'id':service,'qty':2}],'payment_method':'credit',
        'idempotency_key':'credit-sale-123456','customer_id':cust}
    invoice=call(owner,'post','/api/pos/checkout',credit_order)['sale']
    assert call(owner,'post','/api/pos/checkout',credit_order)['sale']['duplicate']
    customer=call(owner,'get','/api/pos/customer?id='+cust)
    assert customer['due_cents']==400
    call(owner,'post','/api/pos/customer/settle',{
        'customer_id':cust,'kind':'deposit','amount_cents':200,
        'payment_method':'cash','idempotency_key':'customer-deposit-100'})
    customer=call(owner,'get','/api/pos/customer?id='+cust)
    assert customer['deposit_cents']==200 and customer['due_cents']==400
    call(owner,'post','/api/pos/customer/settle',{
        'customer_id':cust,'kind':'apply_deposit','amount_cents':200,
        'payment_method':'deposit','idempotency_key':'customer-apply-100'})
    assert call(owner,'get','/api/pos/customer?id='+cust)['due_cents']==200
    payment={'customer_id':cust,'kind':'payment','amount_cents':100,
        'payment_method':'bank','idempotency_key':'customer-payment-100'}
    call(owner,'post','/api/pos/customer/settle',payment)
    assert call(owner,'post','/api/pos/customer/settle',payment)['duplicate']
    customer=call(owner,'get','/api/pos/customer?id='+cust)
    assert customer['due_cents']==100 and customer['deposit_cents']==0
    call(owner,'post','/api/pos/customer/settle',{
        'customer_id':cust,'kind':'payment','amount_cents':200,
        'payment_method':'bank','idempotency_key':'customer-overpayment-100'},status=422)
    with y.db() as db:
        db.execute('UPDATE yola_local_sales SET due_date=? WHERE id=?',
            ((datetime.now(timezone.utc)-timedelta(days=2)).date().isoformat(),invoice['id']))
    flagged=next(c for c in call(owner,'get','/api/pos/customers')['customers'] if c['id']==cust)
    assert flagged['overdue_cents']==100
    accounts=call(owner,'get','/api/pos/accounts')
    assert accounts['trial_balance']['balanced'] and accounts['balance_sheet']['balanced']

    # Cross-tenant isolation with same device cookie and SQLite file.
    state['tenant']='TENANT-OTHER-QA'
    call(owner,'get','/api/pos/customers',status=401)
    print('PASS: seven Yola client requests, margin, stock, services, categories, staff, receivables and tenant scope.')
