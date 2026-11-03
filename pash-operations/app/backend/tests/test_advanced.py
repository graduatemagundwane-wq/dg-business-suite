"""End-to-end API authorization + persistence tests for newly added modules."""
from datetime import datetime, timezone, timedelta
from test_api import appctx, post, get, PASS


def create_delivered_job(ctx, category='dsg', assigned='dsg_specialist'):
    client,ids,headers=ctx
    job=post(ctx,'owner','/jobs',{'vehicle_id':ids['vehicle'],'category':category,'complaint':'Reported customer repair issue',
                                 'assigned_to':ids['users'][assigned]}).json()
    jid=job['id']
    def move(status,role='owner'):
        return client.patch(f'/api/jobs/{jid}/status',json={'status':status},headers=headers[role])
    assert move('diagnosis').status_code==200
    assert move('awaiting_approval').status_code==200
    quote=post(ctx,'owner','/quotes',{'job_id':jid,'items':[{'label':'Repair work','quantity':1,'unit_price':'45'}]}).json()
    assert post(ctx,'customer',f"/quotes/{quote['id']}/decision",{'decision':'approved'}).status_code==200
    assert move('repairing').status_code==200
    assert move('quality_check').status_code==200
    if category == 'dsg':
        assert post(ctx,'dsg_specialist','/gearbox-reports',{'job_id':jid,'transmission_code':'DQ200',
                        'fault_codes':[],'components_replaced':[],'test_results':'Road test completed'}).status_code==201
    if category == 'battery':
        assert post(ctx,'battery_specialist','/battery-reports',{'job_id':jid,'chemistry':'Lead-acid',
                        'battery_serial':'QA-B-1','voltage':'12.5','notes':'Load test completed'}).status_code==201
    assert post(ctx,'owner','/inspections',{'job_id':jid,'checklist':{'quality_passed':True},'notes':'Supervisor approved'}).status_code==201
    assert move('ready').status_code==200
    assert move('delivered').status_code==200
    return job


def test_suppliers_receive_once_and_enforce_tenant(appctx):
    c,ids,h=appctx
    s=post(appctx,'inventory','/suppliers',{'name':'Parts Distributor','phone':'123'}).json()
    assert get(appctx,'customer','/suppliers').status_code==403
    assert get(appctx,'foreign','/suppliers').json()==[]
    p=post(appctx,'inventory','/parts',{'sku':'S001','name':'Diagnostic adapter','quantity':1,'cost':'10','price':'20'}).json()
    assert post(appctx,'foreign','/purchase-orders',{'supplier_id':s['id'],'lines':[{'part_id':p['id'],'quantity':2,'unit_cost':'5'}]}).status_code==404
    q=post(appctx,'inventory','/purchase-orders',{'supplier_id':s['id'],'lines':[{'part_id':p['id'],'quantity':4,'unit_cost':'12.50'}]})
    assert q.status_code==201,q.text
    assert q.json()['total']=='50.00'
    k=q.json()['id']
    assert post(appctx,'mechanic',f'/purchase-orders/{k}/receive',{}).status_code==403
    assert post(appctx,'inventory',f'/purchase-orders/{k}/receive',{}).status_code==200
    assert post(appctx,'inventory',f'/purchase-orders/{k}/receive',{}).status_code==409
    assert next(item for item in get(appctx,'owner','/parts').json() if item['id']==p['id'])['quantity']==5


def test_equipment_and_work_logs_scope(appctx):
    c,ids,h=appctx
    x=post(appctx,'inventory','/equipment',{'name':'Oscilloscope','serial':'OSC-101','category':'Electrical'}).json()
    assert get(appctx,'foreign','/equipment').json()==[]
    assert post(appctx,'inventory','/equipment',{'name':'Duplicate','serial':'OSC-101','category':'Electrical'}).status_code==409
    assert c.patch(f"/api/equipment/{x['id']}",json={'status':'maintenance'},headers=h['inventory']).status_code==200
    j=post(appctx,'owner','/jobs',{'vehicle_id':ids['vehicle'],'category':'mechanical','complaint':'Noise','assigned_to':ids['users']['mechanic']}).json()
    assert post(appctx,'mechanic','/work-logs',{'job_id':j['id'],'minutes':45,'description':'Inspected suspension'}).status_code==201
    assert post(appctx,'dsg_specialist','/work-logs',{'job_id':j['id'],'minutes':12,'description':'Not assigned'}).status_code==403
    assert len(get(appctx,'mechanic','/work-logs').json())==1
    assert get(appctx,'dsg_specialist',f"/work-logs?job_id={j['id']}").status_code==403


def test_accounting_expenses_and_report_isolation(appctx):
    assert post(appctx,'customer','/expenses',{'category':'Fuel','description':'Fleet fuel expense','amount':'3.5'}).status_code==403
    assert post(appctx,'accountant','/expenses',{'category':'Fuel','description':'Van petrol','amount':'37.50','currency':'USD'}).status_code==201
    assert post(appctx,'accountant','/expenses',{'category':'Utilities','description':'Power for workshop','amount':'200','currency':'ZWG'}).status_code==201
    x=get(appctx,'accountant','/reports/finance')
    assert x.status_code==200,x.text
    assert x.json()['expenses_by_currency']=={'USD':'37.50','ZWG':'200.00'}
    assert get(appctx,'foreign','/expenses').json()==[]


def test_warranty_claim_customer_visibility_and_decision(appctx):
    c,ids,h=appctx
    j=create_delivered_job(appctx)
    w=post(appctx,'owner','/warranties',{'job_id':j['id'],'coverage':'Gearbox parts and labour','duration_days':90})
    assert w.status_code==201,w.text
    assert len(get(appctx,'customer','/warranties').json())==1
    assert get(appctx,'foreign','/warranties').json()==[]
    claim=post(appctx,'customer','/warranty-claims',{'warranty_id':w.json()['id'],'description':'Transmission fault returned'})
    assert claim.status_code==201,claim.text
    assert post(appctx,'foreign','/warranty-claims',{'warranty_id':w.json()['id'],'description':'Unauthorized claim'}).status_code==404
    assert c.patch(f"/api/warranty-claims/{claim.json()['id']}",json={'status':'approved'},headers=h['customer']).status_code==403
    assert c.patch(f"/api/warranty-claims/{claim.json()['id']}",json={'status':'under_review'},headers=h['owner']).status_code==200


def test_fleet_vehicle_owner_and_tenant_constraints(appctx):
    c,ids,h=appctx
    f=post(appctx,'owner','/fleets',{'customer_id':ids['customer'],'name':'Company Fleet'}).json()
    assert post(appctx,'owner',f"/fleets/{f['id']}/vehicles",{'vehicle_id':ids['foreign_vehicle']}).status_code==404
    assert post(appctx,'owner',f"/fleets/{f['id']}/vehicles",{'vehicle_id':ids['vehicle']}).status_code==201
    assert post(appctx,'owner',f"/fleets/{f['id']}/vehicles",{'vehicle_id':ids['vehicle']}).status_code==409
    assert len(get(appctx,'customer','/fleets').json())==1
    assert get(appctx,'foreign','/fleets').json()==[]


def test_student_exam_answer_keys_never_exposed(appctx):
    c,ids,h=appctx
    signup=c.post('/api/auth/student-signup',json={'organization_id':ids['org'],'name':'Student Smith','email':'studentx@example.test','password':PASS})
    student_id=signup.json()['student_id']
    auth=c.post('/api/auth/login',json={'organization_id':ids['org'],'email':'studentx@example.test','password':PASS}).json()['access_token']
    hh={'Authorization':'Bearer '+auth}
    course=post(appctx,'instructor','/courses',{'title':'DSG training course','description':'Training','price':'70','published':True}).json()
    assert post(appctx,'instructor','/academy/lessons',{'course_id':course['id'],'title':'Clutch fundamentals','body':'A detailed foundational lesson','published':True}).status_code==201
    assert c.get('/api/academy/lessons',headers=hh).json()==[]
    e=c.post('/api/enrollments',json={'student_id':student_id,'course_id':course['id']},headers=hh)
    assert e.status_code==201,e.text
    assert len(c.get('/api/academy/lessons',headers=hh).json())==1
    a=post(appctx,'instructor','/academy/assessments',{'course_id':course['id'],'title':'DSG basic test','published':True,
        'questions':[{'prompt':'A dual-clutch gearbox uses how many clutches?','choices':['One','Two','Three'],'answer':1}]}).json()
    r=c.get('/api/academy/assessments',headers=hh)
    assert r.status_code==200
    assert 'answer' not in str(r.json())
    assert c.post(f"/api/academy/assessments/{a['id']}/attempt",json={'answers':[100]},headers=hh).status_code==422
    assert c.post(f"/api/academy/assessments/{a['id']}/attempt",json={'answers':[1]},headers=hh).json()['passed']
    assert post(appctx,'owner','/academy/certificates',{'student_id':student_id,'course_id':course['id']}).status_code==409
    assert post(appctx,'instructor',f"/academy/enrollments/{e.json()['enrollment_id']}/complete",{}).status_code==200
    cert=post(appctx,'owner','/academy/certificates',{'student_id':student_id,'course_id':course['id']})
    assert cert.status_code==201,cert.text
    verify=c.get('/api/verify/certificate/'+cert.json()['verification_code'])
    assert verify.json()['valid'] is True
    assert c.patch(f"/api/academy/certificates/{cert.json()['id']}/revoke",json={},headers=h['owner']).status_code==200
    assert c.get('/api/verify/certificate/'+cert.json()['verification_code']).json()['valid'] is False


def test_review_only_after_delivery_and_notifications_private(appctx):
    c,ids,h=appctx
    j=post(appctx,'owner','/jobs',{'vehicle_id':ids['vehicle'],'category':'dsg','complaint':'Shudder'}).json()
    assert post(appctx,'customer','/reviews',{'job_id':j['id'],'rating':5}).status_code==409
    n=post(appctx,'owner','/notifications',{'recipient_id':ids['users']['mechanic'],'message':'Inspect assigned repairs'}).json()
    assert get(appctx,'customer','/notifications').json()==[]
    assert len(get(appctx,'mechanic','/notifications').json())==1
    assert c.patch(f"/api/notifications/{n['id']}/read",headers=h['customer']).status_code==403
    assert c.patch(f"/api/notifications/{n['id']}/read",headers=h['mechanic']).status_code==200


def test_technician_qualifications_are_manager_controlled(appctx):
    c,ids,h=appctx
    payload={'user_id':ids['users']['battery_specialist'],'qualification':'EV High Voltage Certified','high_voltage_approved':True}
    assert post(appctx,'battery_specialist','/staff/qualifications',payload).status_code==403
    assert post(appctx,'owner','/staff/qualifications',payload).status_code==201
    assert len(get(appctx,'battery_specialist','/staff/qualifications').json())==1
    assert get(appctx,'mechanic','/staff/qualifications').json()==[]
