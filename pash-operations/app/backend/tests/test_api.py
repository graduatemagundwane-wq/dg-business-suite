import os
os.environ['PASH_JWT_SECRET']='local-tests-only-separate-from-deployments-'+('z'*70)
from datetime import datetime,timedelta,timezone
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from db import get_db
from models import Base,Organization,User,Customer,Vehicle,Job,Part
from security import password_hash
from main import app

PASS='OnlyForTesting!2026'
@pytest.fixture
def appctx():
    engine=create_engine('sqlite://',connect_args={'check_same_thread':False},poolclass=StaticPool)
    Base.metadata.create_all(engine)
    Session=sessionmaker(bind=engine,expire_on_commit=False)
    with Session() as d:
        a=Organization(name='PASH AUTO QA'); b=Organization(name='Unrelated QA'); d.add_all([a,b]);d.flush()
        users={}
        for role,org in [('owner',a),('manager',a),('service_advisor',a),('mechanic',a),('dsg_specialist',a),('battery_specialist',a),('inventory',a),('accountant',a),('instructor',a),('customer',a),('foreign',b)]:
            roles=['owner'] if role=='foreign' else [role]
            u=User(organization_id=org.id,name=role.title(),email=role+'@example.test',password_hash=password_hash(PASS),roles=roles)
            d.add(u);d.flush();users[role]=u.id
        c=Customer(organization_id=a.id,user_id=users['customer'],name='Test Customer',email='customer@example.test')
        b_customer=Customer(organization_id=b.id,name='Foreign Customer'); d.add_all([c,b_customer]);d.flush()
        v=Vehicle(organization_id=a.id,customer_id=c.id,registration='QA-100',make='Volkswagen',model='Golf',transmission='DSG')
        vb=Vehicle(organization_id=b.id,customer_id=b_customer.id,registration='QA-FOREIGN',make='Ford',model='Ranger')
        d.add_all([v,vb]);d.flush()
        ids={'org':a.id,'foreign_org':b.id,'customer':c.id,'vehicle':v.id,'foreign_vehicle':vb.id,'users':users}
        d.commit()
    def override():
        with Session() as db:yield db
    app.dependency_overrides[get_db]=override
    with TestClient(app) as client:
        headers={}
        for role,id in ids['users'].items():
            org=ids['foreign_org'] if role=='foreign' else ids['org']
            r=client.post('/api/auth/login',json={'email':role+'@example.test','password':PASS,'organization_id':org})
            assert r.status_code==200,(role,r.text)
            headers[role]={'Authorization':'Bearer '+r.json()['access_token']}
        yield client,ids,headers
    app.dependency_overrides.clear()
    engine.dispose()

def post(ctx,role,path,payload):
    client,_,h=ctx
    return client.post('/api'+path,json=payload,headers=h[role])
def get(ctx,role,path):
    client,_,h=ctx
    return client.get('/api'+path,headers=h[role])

def test_login_errors(appctx):
    c,ids,h=appctx
    assert c.get('/api/auth/me').status_code==401
    assert c.post('/api/auth/login',json={'email':'owner@example.test','password':'wrong','organization_id':ids['org']}).status_code==401
    assert c.get('/api/auth/me',headers=h['owner']).json()['roles']==['owner']
    assert c.get('/api/health').json()['status']=='ok'

def test_owner_and_technician_dashboard(appctx):
    c,ids,h=appctx
    assert get(appctx,'owner','/dashboard').json()['vehicles']==1
    assert get(appctx,'mechanic','/dashboard').status_code==200
    assert get(appctx,'customer','/dashboard').json()['vehicles']==1
    assert get(appctx,'foreign','/dashboard').json()['vehicles']==1

def test_customer_registration_cannot_escalate_role(appctx):
    c,ids,h=appctx
    r=c.post('/api/auth/customer-signup',json={'organization_id':ids['org'],'name':'New Customer','email':'new@example.test','password':PASS,'phone':'+263700000000','roles':['owner']})
    assert r.status_code==201,r.text
    login=c.post('/api/auth/login',json={'organization_id':ids['org'],'email':'new@example.test','password':PASS})
    assert login.json()['user']['roles']==['customer']

def test_staff_permissions(appctx):
    c,ids,h=appctx
    assert get(appctx,'mechanic','/admin/users').status_code==403
    assert get(appctx,'customer','/admin/users').status_code==403
    assert post(appctx,'mechanic','/admin/users',{'name':'E Valid','email':'e@example.test','password':PASS,'roles':['owner']}).status_code==403
    r=post(appctx,'manager','/admin/users',{'name':'A Legit Employee','email':'worker@example.test','password':PASS,'roles':['mechanic','dsg_specialist']})
    assert r.status_code==201,r.text
    assert set(r.json()['roles'])=={'mechanic','dsg_specialist'}
    assert post(appctx,'manager','/admin/users',{'name':'Wrong Privilege','email':'bad@example.test','password':PASS,'roles':['owner']}).status_code==403

def test_cross_company_separation(appctx):
    c,ids,h=appctx
    assert len(get(appctx,'owner','/vehicles').json())==1
    assert len(get(appctx,'foreign','/vehicles').json())==1
    j=post(appctx,'owner','/jobs',{'vehicle_id':ids['foreign_vehicle'],'category':'dsg','complaint':'Shifting failure'})
    assert j.status_code==404
    assert post(appctx,'customer','/bookings',{'customer_id':ids['customer'],'vehicle_id':ids['foreign_vehicle'],'service':'Check transmission','scheduled_at':(datetime.now(timezone.utc)+timedelta(days=1)).isoformat()}).status_code==404

def test_tech_sees_only_assigned_jobs(appctx):
    c,ids,h=appctx
    j=post(appctx,'owner','/jobs',{'vehicle_id':ids['vehicle'],'category':'mechanical','complaint':'Rough idle','assigned_to':ids['users']['mechanic']})
    assert j.status_code==201,j.text
    assert len(get(appctx,'mechanic','/jobs').json())==1
    assert get(appctx,'dsg_specialist','/jobs').json()==[]
    assert len(get(appctx,'customer','/jobs').json())==1
    r=c.patch(f"/api/jobs/{j.json()['id']}/status",json={'status':'diagnosis'},headers=h['dsg_specialist'])
    assert r.status_code==403
    r=c.patch(f"/api/jobs/{j.json()['id']}/status",json={'status':'diagnosis','diagnosis':'Vibration observed'},headers=h['mechanic'])
    assert r.status_code==200 and r.json()['status']=='diagnosis'
    r=c.patch(f"/api/jobs/{j.json()['id']}/status",json={'status':'ready'},headers=h['mechanic'])
    assert r.status_code==409

def test_inspection_and_specialist_report_scope(appctx):
    c,ids,h=appctx
    dsg=post(appctx,'owner','/jobs',{'vehicle_id':ids['vehicle'],'category':'dsg','complaint':'Jerks in traffic','assigned_to':ids['users']['dsg_specialist']}).json()
    r=post(appctx,'dsg_specialist','/gearbox-reports',{'job_id':dsg['id'],'transmission_code':'DQ200','fault_codes':['P17BF'],'components_replaced':['Clutch'],'test_results':'Test recorded'})
    assert r.status_code==201,r.text
    assert post(appctx,'battery_specialist','/gearbox-reports',{'job_id':dsg['id'],'transmission_code':'XX'}).status_code==403
    bat=post(appctx,'owner','/jobs',{'vehicle_id':ids['vehicle'],'category':'battery','complaint':'No start','assigned_to':ids['users']['battery_specialist']}).json()
    r=post(appctx,'battery_specialist','/battery-reports',{'job_id':bat['id'],'chemistry':'Lead-acid','battery_serial':'BATT-1','voltage':'12.5','health_percent':80})
    assert r.status_code==201,r.text
    assert post(appctx,'mechanic','/inspections',{'job_id':bat['id'],'checklist':{'checked':True}}).status_code==403
    assert post(appctx,'battery_specialist','/inspections',{'job_id':bat['id'],'checklist':{'checked':True}}).status_code==201

def test_booking_ownership(appctx):
    c,ids,h=appctx
    start=(datetime.now(timezone.utc)+timedelta(days=4)).isoformat()
    r=post(appctx,'customer','/bookings',{'customer_id':ids['customer'],'vehicle_id':ids['vehicle'],'service':'DSG diagnosis','scheduled_at':start})
    assert r.status_code==201,r.text
    assert len(get(appctx,'customer','/bookings').json())==1
    assert post(appctx,'customer','/bookings',{'customer_id':1000,'vehicle_id':ids['vehicle'],'service':'DSG diagnosis','scheduled_at':start}).status_code==404
    assert post(appctx,'customer','/bookings',{'customer_id':ids['customer'],'vehicle_id':ids['vehicle'],'service':'Inspection','scheduled_at':(datetime.now(timezone.utc)-timedelta(days=1)).isoformat()}).status_code==422

def test_quote_customer_approval_and_invoice(appctx):
    c,ids,h=appctx
    j=post(appctx,'owner','/jobs',{'vehicle_id':ids['vehicle'],'category':'dsg','complaint':'Fault light'}).json()
    q=post(appctx,'service_advisor','/quotes',{'job_id':j['id'],'items':[{'label':'Diagnostic labour','quantity':2,'unit_price':'35.50'},{'label':'Part','quantity':1,'unit_price':'100'}]})
    assert q.status_code==201,q.text
    quote=q.json(); assert quote['total']=='171.00'
    assert post(appctx,'owner',f"/invoices/from-quote/{quote['id']}",{}).status_code==409
    assert post(appctx,'customer',f"/quotes/{quote['id']}/decision",{'decision':'approved'}).status_code==200
    assert post(appctx,'customer',f"/quotes/{quote['id']}/decision",{'decision':'rejected'}).status_code==409
    inv=post(appctx,'accountant',f"/invoices/from-quote/{quote['id']}",{})
    assert inv.status_code==201,inv.text
    assert post(appctx,'accountant',f"/invoices/from-quote/{quote['id']}",{}).status_code==409
    iid=inv.json()['id']
    assert post(appctx,'customer',f'/invoices/{iid}/payments',{'amount':'50','method':'cash'}).status_code==403
    pay=post(appctx,'accountant',f'/invoices/{iid}/payments',{'amount':'50','method':'cash'})
    assert pay.status_code==201 and pay.json()['balance']=='121.00',pay.text
    assert post(appctx,'accountant',f'/invoices/{iid}/payments',{'amount':'999','method':'bank'}).status_code==409
    assert len(get(appctx,'customer','/invoices').json())==1

def test_stock_levels_and_audit(appctx):
    c,ids,h=appctx
    j=post(appctx,'owner','/jobs',{'vehicle_id':ids['vehicle'],'category':'dsg','complaint':'No reverse'}).json()
    p=post(appctx,'inventory','/parts',{'sku':'DQ200-CP','name':'Clutch pack','quantity':3,'cost':'60','price':'90'})
    assert p.status_code==201,p.text
    part_id=p.json()['id']
    assert post(appctx,'mechanic',f'/parts/{part_id}/issue',{'job_id':j['id'],'quantity':1}).status_code==403
    assert post(appctx,'inventory',f'/parts/{part_id}/issue',{'job_id':j['id'],'quantity':4}).status_code==409
    issued=post(appctx,'inventory',f'/parts/{part_id}/issue',{'job_id':j['id'],'quantity':2})
    assert issued.status_code==200 and issued.json()['remaining']==1,issued.text
    assert get(appctx,'owner','/parts').json()[0]['quantity']==1
    events=get(appctx,'owner','/audit').json()
    assert any(e['entity']=='part' and e['action']=='issue' for e in events)
    assert get(appctx,'mechanic','/audit').status_code==403

def test_courses_and_student_access(appctx):
    c,ids,h=appctx
    r=post(appctx,'instructor','/courses',{'title':'DSG diagnostic fundamentals','description':'Theory','price':'250','published':False})
    assert r.status_code==201,r.text
    assert len(get(appctx,'customer','/courses').json())==0
    r=post(appctx,'manager','/courses',{'title':'Intro to automotive mechanics','description':'Foundation','price':'75','published':True})
    assert r.status_code==201,r.text
    assert len(get(appctx,'customer','/courses').json())==1

def test_ai_not_fabricated(appctx):
    r=post(appctx,'owner','/ai/ask',{'question':'Is this DSG safe?'})
    assert r.status_code==503

def test_customer_can_add_only_their_own_vehicle(appctx):
    c,ids,h=appctx
    r=post(appctx,'customer','/vehicles',{'customer_id':ids['customer'],'registration':'QA-NEW','make':'Toyota','model':'Aqua'})
    assert r.status_code==201,r.text
    assert len(get(appctx,'customer','/vehicles').json())==2
    assert post(appctx,'customer','/vehicles',{'customer_id':1000,'registration':'QA-NOT-MINE','make':'Honda','model':'Fit'}).status_code==404
    assert post(appctx,'customer','/vehicles',{'customer_id':ids['customer'],'registration':'QA-NEW','make':'Toyota','model':'Aqua'}).status_code==409

def test_student_enrollment_is_scoped(appctx):
    c,ids,h=appctx
    r=c.post('/api/auth/student-signup',json={'organization_id':ids['org'],'name':'Learner Example','email':'learner@example.test','password':PASS})
    assert r.status_code==201,r.text
    student_id=r.json()['student_id']
    login=c.post('/api/auth/login',json={'organization_id':ids['org'],'email':'learner@example.test','password':PASS})
    hh={'Authorization':'Bearer '+login.json()['access_token']}
    course=post(appctx,'instructor','/courses',{'title':'EV Fundamentals','description':'Intro','price':120,'published':True}).json()
    r=c.post('/api/enrollments',json={'student_id':student_id,'course_id':course['id']},headers=hh)
    assert r.status_code==201,r.text
    assert c.get('/api/dashboard',headers=hh).json()['courses_enrolled']==1
    assert c.get('/api/enrollments',headers=hh).json()[0]['course_id']==course['id']


def test_repair_authorization_and_final_quality_gate(appctx):
    c,ids,h=appctx
    j=post(appctx,'owner','/jobs',{'vehicle_id':ids['vehicle'],'category':'mechanical','complaint':'Check engine','assigned_to':ids['users']['mechanic']}).json()
    jid=j['id']
    def move(step,role='owner'):
        return c.patch(f'/api/jobs/{jid}/status',json={'status':step},headers=h[role])
    assert move('diagnosis').status_code==200
    assert move('awaiting_approval').status_code==200
    assert move('repairing').status_code==409
    quote=post(appctx,'service_advisor','/quotes',{'job_id':jid,'items':[{'label':'Approved work','quantity':1,'unit_price':'20'}]}).json()
    assert post(appctx,'customer',f"/quotes/{quote['id']}/decision",{'decision':'approved'}).status_code==200
    assert move('repairing').status_code==200
    assert move('quality_check').status_code==200
    assert move('ready').status_code==409
    assert post(appctx,'mechanic','/inspections',{'job_id':jid,'checklist':{'quality_passed':True},'notes':'Self-certified QA'}).status_code==403
    assert post(appctx,'owner','/inspections',{'job_id':jid,'checklist':{'quality_passed':True},'notes':'Supervisor QA inspected'}).status_code==201
    assert move('ready').status_code==200
    assert move('delivered').status_code==200
