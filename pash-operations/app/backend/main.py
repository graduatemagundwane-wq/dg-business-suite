"""PASH Auto Operations: independently deployable API for staff, admin and customer portals."""
import os
from datetime import datetime, timezone, timedelta
from decimal import Decimal
from pathlib import Path
from typing import Literal
from fastapi import FastAPI, Depends, HTTPException
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from sqlalchemy import select, func, inspect, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from db import engine, get_db
from models import (Base, Organization, User, Customer, Vehicle, Booking, Job, Inspection,
                    GearboxReport, BatteryReport, Part, StockMovement, Quote, Invoice,
                    Payment, Course, Enrollment, AuditEvent, StaffQualification, HVSafetyPermit, LoginAttempt, Notification, now)
from security import password_hash, password_verify, issue_token, current_user, permit, staff

# Explicit create-schema command for first-run developer setup; migrations required before production.
app=FastAPI(title='PASH Auto Operations API',version='0.5.0',docs_url='/api/docs',openapi_url='/api/openapi.json')

@app.exception_handler(IntegrityError)
def integrity_exception(request, exc):
    # Never expose database constraint details or raw SQL in a client error.
    return JSONResponse(status_code=409,content={'detail':'Duplicate or conflicting record'})


class Login(BaseModel):
    email: str
    password: str
    organization_id: int = Field(gt=0)
class NewStaff(BaseModel):
    name: str = Field(min_length=2)
    email: str
    password: str = Field(min_length=12)
    roles: list[str] = Field(min_length=1)
class NewCustomer(BaseModel):
    name: str = Field(min_length=2)
    phone: str = ''
    email: str = ''
    fleet_company: str = ''
class Signup(BaseModel):
    organization_id: int = Field(gt=0)
    name: str = Field(min_length=2)
    email: str
    password: str = Field(min_length=12)
    phone: str = ''
class NewVehicle(BaseModel):
    customer_id: int = Field(gt=0)
    registration: str = Field(min_length=2)
    make: str = Field(min_length=2)
    model: str = Field(min_length=1)
    year: int | None = Field(default=None, ge=1900, le=2100)
    vin: str = ''
    transmission: str = ''
    mileage: int | None = Field(default=None, ge=0)
class NewBooking(BaseModel):
    customer_id: int = Field(gt=0)
    vehicle_id: int = Field(gt=0)
    service: str = Field(min_length=3)
    scheduled_at: datetime
    notes: str = ''
class NewJob(BaseModel):
    vehicle_id: int = Field(gt=0)
    category: Literal['mechanical','dsg','battery','electrical','diagnostics']
    complaint: str = Field(min_length=3)
    assigned_to: int | None = None
class StatusPatch(BaseModel):
    status: Literal['diagnosis','awaiting_approval','awaiting_parts','repairing','quality_check','ready','delivered']
    diagnosis: str | None = None
class NewInspection(BaseModel):
    job_id: int
    checklist: dict
    notes: str = ''
class NewGearbox(BaseModel):
    job_id: int
    transmission_code: str = Field(min_length=2)
    fault_codes: list[str] = []
    components_replaced: list[str] = []
    test_results: str = ''
class NewBattery(BaseModel):
    job_id: int
    chemistry: str = Field(min_length=2)
    battery_serial: str = Field(min_length=2)
    voltage: Decimal | None = Field(default=None,ge=0,le=1000)
    health_percent: int | None = Field(default=None,ge=0,le=100)
    notes: str = ''
    high_voltage: bool = False
class NewPart(BaseModel):
    sku: str = Field(min_length=1)
    name: str = Field(min_length=2)
    quantity: int = Field(ge=0)
    reorder_level: int = Field(default=2,ge=0)
    cost: Decimal = Field(ge=0)
    price: Decimal = Field(ge=0)
class IssuePart(BaseModel):
    job_id: int
    quantity: int = Field(gt=0)
class QuoteItem(BaseModel):
    label: str = Field(min_length=2)
    quantity: int = Field(gt=0)
    unit_price: Decimal = Field(ge=0)
class NewQuote(BaseModel):
    job_id: int
    items: list[QuoteItem] = Field(min_length=1)
class QuoteDecision(BaseModel):
    decision: Literal['approved','rejected']
class NewPayment(BaseModel):
    amount: Decimal = Field(gt=0)
    method: Literal['cash','card','bank','mobile_money']
class NewCourse(BaseModel):
    title: str = Field(min_length=3)
    description: str = ''
    price: Decimal = Field(ge=0)
    published: bool = False
class NewEnrollment(BaseModel):
    student_id: int = Field(gt=0)
    course_id: int = Field(gt=0)

ALL_ROLES={'owner','manager','service_advisor','mechanic','dsg_specialist','battery_specialist','inventory','accountant','instructor','customer','student'}
WORKSHOP={'owner','manager','service_advisor','mechanic','dsg_specialist','battery_specialist'}
ALLOWED_STATUS={
    'received':{'diagnosis'},
    'diagnosis':{'awaiting_approval','awaiting_parts'},
    'awaiting_approval':{'awaiting_parts','repairing'},
    'awaiting_parts':{'repairing'},
    'repairing':{'quality_check'},
    'quality_check':{'repairing','ready'},
    'ready':{'delivered'}, 'delivered':set(),
}

def record(db,u,action,entity,item_id,**data):
    db.add(AuditEvent(organization_id=u.organization_id,actor_id=u.id,action=action,entity=entity,entity_id=item_id,data=data))

def save(db):
    try: db.commit()
    except IntegrityError:
        db.rollback();raise HTTPException(409,'Duplicate or conflicting record')

def one(db,cls,item_id,u):
    obj=db.scalar(select(cls).where(cls.id==item_id,cls.organization_id==u.organization_id))
    if not obj: raise HTTPException(404,'Record not found')
    return obj

def customer_for(db,u):
    cust=db.scalar(select(Customer).where(Customer.user_id==u.id, Customer.organization_id==u.organization_id))
    if not cust: raise HTTPException(403,'No customer profile for account')
    return cust

def customer_scope(db,u,cust_id):
    c=one(db,Customer,cust_id,u)
    if 'customer' in (u.roles or []) and not set(u.roles).intersection(WORKSHOP|{'accountant','inventory'}):
        if c.user_id!=u.id: raise HTTPException(403,'Not your customer record')
    return c

def job_scope(db,u,job,allow_customer=False):
    v=one(db,Vehicle,job.vehicle_id,u)
    if 'customer' in (u.roles or []) and not set(u.roles).intersection(WORKSHOP|{'accountant','inventory'}):
        customer_scope(db,u,v.customer_id)
    elif not set(u.roles or []).intersection(WORKSHOP|{'inventory','accountant','owner'}):
        raise HTTPException(403,'No access to job')
    return v

def represent(obj,*keys):
    d={k:getattr(obj,k) for k in keys}
    for k,v in d.items():
        if isinstance(v,Decimal): d[k]=str(v)
        elif isinstance(v,datetime): d[k]=v.isoformat()
    return d

def jrow(j): return represent(j,'id','vehicle_id','category','complaint','diagnosis','assigned_to','status','opened_at')
def vrow(v): return represent(v,'id','customer_id','registration','make','model','year','vin','transmission','mileage')
def crow(c): return represent(c,'id','name','phone','email','fleet_company')
def brow(b): return represent(b,'id','customer_id','vehicle_id','service','scheduled_at','status','notes')
def prow(p): return represent(p,'id','sku','name','quantity','reorder_level','cost','price')
def qrow(q): return represent(q,'id','job_id','items','total','status','created_at')

@app.get('/api/health')
def health(): return {'status':'ok','service':'pash-auto-operations'}

@app.get('/api/ready', include_in_schema=True)
def readiness(db:Session=Depends(get_db)):
    """Non-sensitive readiness gate: DB accessible, complete schema, production config.

    A liveness signal alone must never be mistaken for acceptance. This endpoint
    only establishes that the API process and expected database schema respond.
    """
    try:
        db.execute(text('SELECT 1')).scalar_one()
        inspector=inspect(db.get_bind())
        present=set(inspector.get_table_names())
        required=set(Base.metadata.tables)
        complete=required.issubset(present)
        advanced_column='high_voltage' in {col['name'] for col in inspector.get_columns('battery_reports')} if 'battery_reports' in present else False
        configured=len(os.getenv('PASH_JWT_SECRET',''))>=48
        safe_runtime=os.getenv('PASH_ENV','development').lower() not in ('production','staging') or not str(db.get_bind().url).startswith('sqlite:')
        if not (complete and advanced_column and configured and safe_runtime):
            return JSONResponse(status_code=503,content={'ready':False,'schema_complete':complete,'advanced_schema':advanced_column,'configuration_ok':configured and safe_runtime})
        return {'ready':True,'schema_complete':True,'advanced_schema':True,'configuration_ok':True}
    except Exception:
        return JSONResponse(status_code=503,content={'ready':False,'detail':'Service database not ready'})

@app.post('/api/auth/login')
def login(data:Login,db:Session=Depends(get_db)):
    email=data.email.strip().lower()
    attempt=db.scalar(select(LoginAttempt).where(LoginAttempt.organization_id==data.organization_id,LoginAttempt.email==email).with_for_update())
    if attempt and attempt.blocked_until:
        until=attempt.blocked_until.replace(tzinfo=attempt.blocked_until.tzinfo or timezone.utc)
        if until>now():raise HTTPException(429,'Too many login attempts. Please retry later.')
    user=db.scalar(select(User).where(User.organization_id==data.organization_id,func.lower(User.email)==email))
    if not user or not user.active or not password_verify(user.password_hash,data.password):
        if db.get(Organization,data.organization_id):
            if not attempt:
                attempt=LoginAttempt(organization_id=data.organization_id,email=email,failed_count=0)
                db.add(attempt)
            attempt.failed_count=(attempt.failed_count or 0)+1
            attempt.blocked_until=now()+timedelta(minutes=15) if attempt.failed_count>=5 else None
            save(db)
        raise HTTPException(401,'Invalid credentials')
    if attempt:
        attempt.failed_count=0;attempt.blocked_until=None;save(db)
    return {'access_token':issue_token(user),'token_type':'bearer','user':{'id':user.id,'name':user.name,'roles':user.roles,'organization_id':user.organization_id}}

@app.post('/api/auth/logout')
def logout_all_sessions(u:User=Depends(current_user),db:Session=Depends(get_db)):
    # Server invalidation, including other devices; the client deletes its local token.
    u.token_version=(u.token_version or 0)+1
    record(db,u,'revoke','sessions',u.id)
    save(db)
    return {'revoked':True}

class PasswordChange(BaseModel):
    current_password: str
    new_password: str = Field(min_length=12)

@app.post('/api/auth/change-password')
def change_password(data:PasswordChange,u:User=Depends(current_user),db:Session=Depends(get_db)):
    if not password_verify(u.password_hash,data.current_password):raise HTTPException(403,'Current password is incorrect')
    if data.new_password==data.current_password:raise HTTPException(422,'New password must differ from old password')
    u.password_hash=password_hash(data.new_password)
    u.token_version=(u.token_version or 0)+1
    record(db,u,'change','password',u.id)
    save(db)
    return {'changed':True,'all_sessions_revoked':True}

@app.get('/api/auth/me')
def me(u:User=Depends(current_user)): return {'id':u.id,'name':u.name,'email':u.email,'roles':u.roles,'organization_id':u.organization_id}

@app.post('/api/auth/customer-signup',status_code=201)
def customer_signup(data:Signup,db:Session=Depends(get_db)):
    # First public enrollment is a customer only; cannot self-assign staff privileges.
    if not db.get(Organization,data.organization_id): raise HTTPException(404,'Organization unavailable')
    u=User(organization_id=data.organization_id,name=data.name,email=data.email.strip().lower(),password_hash=password_hash(data.password),roles=['customer'])
    db.add(u); db.flush()
    c=Customer(organization_id=u.organization_id,user_id=u.id,name=u.name,email=u.email,phone=data.phone)
    db.add(c); record(db,u,'signup','customer',u.id); save(db)
    return {'customer_id':c.id,'user_id':u.id}

@app.post('/api/auth/student-signup',status_code=201)
def student_signup(data:Signup,db:Session=Depends(get_db)):
    if not db.get(Organization,data.organization_id): raise HTTPException(404,'Organization unavailable')
    u=User(organization_id=data.organization_id,name=data.name,email=data.email.strip().lower(),password_hash=password_hash(data.password),roles=['student'])
    db.add(u);db.flush();record(db,u,'signup','student',u.id);save(db)
    return {'student_id':u.id}

@app.get('/api/admin/users')
def users(u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager')
    arr=db.scalars(select(User).where(User.organization_id==u.organization_id).order_by(User.id.desc())).all()
    return [represent(v,'id','name','email','roles','active') for v in arr]

@app.post('/api/admin/users',status_code=201)
def create_staff(data:NewStaff,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager')
    roles=set(data.roles)
    if roles-ALL_ROLES or 'customer' in roles or 'student' in roles: raise HTTPException(422,'Invalid staff roles')
    if 'owner' in roles and 'owner' not in u.roles: raise HTTPException(403,'Only owners may create owners')
    x=User(organization_id=u.organization_id,name=data.name,email=data.email.strip().lower(),password_hash=password_hash(data.password),roles=sorted(roles))
    db.add(x);db.flush();record(db,u,'create','user',x.id,roles=x.roles);save(db)
    return represent(x,'id','name','email','roles')

@app.get('/api/customers')
def customers(u:User=Depends(current_user),db:Session=Depends(get_db)):
    if 'customer' in u.roles and not set(u.roles).intersection(WORKSHOP|{'accountant'}):
        c=customer_for(db,u);return [crow(c)]
    permit(u,'manager','service_advisor','accountant')
    return [crow(c) for c in db.scalars(select(Customer).where(Customer.organization_id==u.organization_id).order_by(Customer.id.desc())).all()]

@app.post('/api/customers',status_code=201)
def add_customer(data:NewCustomer,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','service_advisor')
    c=Customer(organization_id=u.organization_id,**data.model_dump());db.add(c);db.flush();record(db,u,'create','customer',c.id);save(db);return crow(c)

@app.get('/api/vehicles')
def vehicles(u:User=Depends(current_user),db:Session=Depends(get_db)):
    stmt=select(Vehicle).where(Vehicle.organization_id==u.organization_id)
    if 'customer' in u.roles and not set(u.roles).intersection(WORKSHOP): stmt=stmt.where(Vehicle.customer_id==customer_for(db,u).id)
    else: permit(u,'manager','service_advisor','mechanic','dsg_specialist','battery_specialist','accountant','inventory')
    return [vrow(v) for v in db.scalars(stmt.order_by(Vehicle.id.desc())).all()]

@app.post('/api/vehicles',status_code=201)
def add_vehicle(data:NewVehicle,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','service_advisor','customer')
    customer_scope(db,u,data.customer_id)
    v=Vehicle(organization_id=u.organization_id,**data.model_dump());db.add(v);db.flush();record(db,u,'create','vehicle',v.id);save(db);return vrow(v)

@app.get('/api/bookings')
def bookings(u:User=Depends(current_user),db:Session=Depends(get_db)):
    stmt=select(Booking).where(Booking.organization_id==u.organization_id)
    if 'customer' in u.roles and not set(u.roles).intersection(WORKSHOP):stmt=stmt.where(Booking.customer_id==customer_for(db,u).id)
    else:permit(u,'manager','service_advisor','mechanic','dsg_specialist','battery_specialist')
    return [brow(b) for b in db.scalars(stmt.order_by(Booking.id.desc())).all()]

@app.post('/api/bookings',status_code=201)
def add_booking(data:NewBooking,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'customer','manager','service_advisor')
    customer_scope(db,u,data.customer_id)
    v=one(db,Vehicle,data.vehicle_id,u)
    if v.customer_id!=data.customer_id: raise HTTPException(422,'Vehicle does not belong to customer')
    scheduled = data.scheduled_at.replace(tzinfo=timezone.utc) if data.scheduled_at.tzinfo is None else data.scheduled_at.astimezone(timezone.utc)
    if scheduled < now(): raise HTTPException(422,'Booking must be in the future')
    b=Booking(organization_id=u.organization_id,**data.model_dump());db.add(b);db.flush();record(db,u,'request','booking',b.id);save(db);return brow(b)

@app.get('/api/jobs')
def jobs(u:User=Depends(current_user),db:Session=Depends(get_db)):
    stmt=select(Job).where(Job.organization_id==u.organization_id)
    roles=set(u.roles or [])
    if 'customer' in roles and not roles.intersection(WORKSHOP|{'accountant','inventory'}):
        ids=select(Vehicle.id).where(Vehicle.organization_id==u.organization_id,Vehicle.customer_id==customer_for(db,u).id)
        stmt=stmt.where(Job.vehicle_id.in_(ids))
    elif roles.intersection({'mechanic','dsg_specialist','battery_specialist'}) and not roles.intersection({'owner','manager','service_advisor'}):
        stmt=stmt.where(Job.assigned_to==u.id)
    else:permit(u,'manager','service_advisor','accountant','inventory')
    return [jrow(j) for j in db.scalars(stmt.order_by(Job.id.desc())).all()]

@app.post('/api/jobs',status_code=201)
def add_job(data:NewJob,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','service_advisor')
    one(db,Vehicle,data.vehicle_id,u)
    if data.assigned_to:
        assignee=one(db,User,data.assigned_to,u)
        if not set(assignee.roles or []).intersection({'mechanic','dsg_specialist','battery_specialist'}): raise HTTPException(422,'Assignee must be a technician')
    j=Job(organization_id=u.organization_id,**data.model_dump());db.add(j);db.flush();record(db,u,'create','job',j.id);save(db);return jrow(j)

@app.patch('/api/jobs/{job_id}/status')
def change_status(job_id:int,data:StatusPatch,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','service_advisor','mechanic','dsg_specialist','battery_specialist')
    j=one(db,Job,job_id,u)
    if not set(u.roles).intersection({'owner','manager','service_advisor'}) and j.assigned_to!=u.id: raise HTTPException(403,'Job not assigned to you')
    if data.status not in ALLOWED_STATUS.get(j.status,set()):raise HTTPException(409,f'Invalid job state transition: {j.status} to {data.status}')
    if data.status in {'ready','delivered'} and not set(u.roles).intersection({'owner','manager','service_advisor'}):raise HTTPException(403,'Manager approval required')
    if data.status=='repairing':
        approved=db.scalar(select(Quote.id).where(Quote.organization_id==u.organization_id,Quote.job_id==j.id,Quote.status=='approved').limit(1))
        if not approved: raise HTTPException(409,'Approved customer quotation required before repairs begin')
    if data.status=='ready':
        latest=db.scalar(select(Inspection).where(Inspection.organization_id==u.organization_id,Inspection.job_id==j.id).order_by(Inspection.id.desc()).limit(1))
        if not latest or latest.checklist.get('quality_passed') is not True:
            raise HTTPException(409,'Latest final inspection must pass before collection')
        if j.category=='dsg' and not db.scalar(select(GearboxReport.id).where(GearboxReport.organization_id==u.organization_id,GearboxReport.job_id==j.id).limit(1)):
            raise HTTPException(409,'DSG repair report required before collection')
        if j.category=='battery' and not db.scalar(select(BatteryReport.id).where(BatteryReport.organization_id==u.organization_id,BatteryReport.job_id==j.id).limit(1)):
            raise HTTPException(409,'Battery test report required before collection')
    old=j.status;j.status=data.status
    if data.diagnosis is not None:j.diagnosis=data.diagnosis
    record(db,u,'status','job',j.id,before=old,after=j.status);save(db);return jrow(j)

@app.post('/api/inspections',status_code=201)
def add_inspection(data:NewInspection,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','service_advisor','mechanic','dsg_specialist','battery_specialist')
    j=one(db,Job,data.job_id,u)
    if not set(u.roles).intersection({'owner','manager','service_advisor'}) and j.assigned_to!=u.id:raise HTTPException(403,'Job not assigned to you')
    if data.checklist.get('quality_passed') is True:
        if not set(u.roles).intersection({'owner','manager'}):
            raise HTTPException(403,'Only a manager may certify final quality')
        if j.status!='quality_check':
            raise HTTPException(409,'Final quality can only be certified during quality review')
    x=Inspection(organization_id=u.organization_id,inspector_id=u.id,**data.model_dump());db.add(x);db.flush();record(db,u,'inspect','job',j.id);save(db);return {'inspection_id':x.id}

@app.post('/api/gearbox-reports',status_code=201)
def add_gearbox(data:NewGearbox,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','dsg_specialist')
    j=one(db,Job,data.job_id,u)
    if j.category!='dsg':raise HTTPException(422,'Job is not a DSG job')
    if 'dsg_specialist' in u.roles and not set(u.roles).intersection({'owner','manager'}) and j.assigned_to!=u.id:raise HTTPException(403,'Job not assigned to you')
    x=GearboxReport(organization_id=u.organization_id,technician_id=u.id,**data.model_dump());db.add(x);db.flush();record(db,u,'report','gearbox',x.id);save(db);return {'report_id':x.id}

@app.post('/api/battery-reports',status_code=201)
def add_battery(data:NewBattery,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','battery_specialist')
    j=one(db,Job,data.job_id,u)
    if j.category!='battery':raise HTTPException(422,'Job is not a battery job')
    if 'battery_specialist' in u.roles and not set(u.roles).intersection({'owner','manager'}) and j.assigned_to!=u.id:raise HTTPException(403,'Job not assigned to you')
    if data.high_voltage:
        if 'battery_specialist' not in (u.roles or []):raise HTTPException(403,'High-voltage work requires battery specialist authorization')
        credential=db.scalar(select(StaffQualification).where(StaffQualification.organization_id==u.organization_id,StaffQualification.user_id==u.id,StaffQualification.high_voltage_approved==True))
        if not credential or (credential.expires_at and credential.expires_at.replace(tzinfo=credential.expires_at.tzinfo or timezone.utc)<now()):
            raise HTTPException(403,'Current verified high-voltage qualification required')
        safety_permit=db.scalar(select(HVSafetyPermit).where(HVSafetyPermit.organization_id==u.organization_id,HVSafetyPermit.job_id==j.id,HVSafetyPermit.technician_id==u.id))
        if not safety_permit:raise HTTPException(409,'Supervisor high-voltage safety permit required')
    x=BatteryReport(organization_id=u.organization_id,technician_id=u.id,**data.model_dump());db.add(x);db.flush();record(db,u,'report','battery',x.id);save(db);return {'report_id':x.id}

@app.get('/api/parts')
def parts(u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','inventory','service_advisor','mechanic','dsg_specialist','battery_specialist')
    return [prow(p) for p in db.scalars(select(Part).where(Part.organization_id==u.organization_id).order_by(Part.id.desc())).all()]

@app.post('/api/parts',status_code=201)
def add_part(data:NewPart,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','inventory')
    p=Part(organization_id=u.organization_id,**data.model_dump());db.add(p);db.flush();record(db,u,'create','part',p.id);save(db);return prow(p)

@app.post('/api/parts/{part_id}/issue')
def issue_part(part_id:int,data:IssuePart,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','inventory')
    part=one(db,Part,part_id,u);job=one(db,Job,data.job_id,u)
    # PostgreSQL row lock serializes concurrent stock issues; SQLite writes are serialized by DB.
    part=db.scalar(select(Part).where(Part.id==part.id,Part.organization_id==u.organization_id).with_for_update())
    if part.quantity<data.quantity:raise HTTPException(409,'Insufficient stock')
    part.quantity-=data.quantity
    m=StockMovement(organization_id=u.organization_id,part_id=part.id,job_id=job.id,actor_id=u.id,quantity_delta=-data.quantity,reason='issued_to_job')
    db.add(m);record(db,u,'issue','part',part.id,quantity=data.quantity,job_id=job.id);save(db)
    return {'stock_movement_id':m.id,'remaining':part.quantity}

@app.get('/api/quotes')
def quotes(u:User=Depends(current_user),db:Session=Depends(get_db)):
    stmt=select(Quote).where(Quote.organization_id==u.organization_id)
    if 'customer' in u.roles and not set(u.roles).intersection(WORKSHOP):
        vehicle_ids=select(Vehicle.id).where(Vehicle.organization_id==u.organization_id,Vehicle.customer_id==customer_for(db,u).id)
        job_ids=select(Job.id).where(Job.organization_id==u.organization_id,Job.vehicle_id.in_(vehicle_ids))
        stmt=stmt.where(Quote.job_id.in_(job_ids))
    else:permit(u,'manager','service_advisor','accountant')
    return [qrow(q) for q in db.scalars(stmt.order_by(Quote.id.desc())).all()]

@app.post('/api/quotes',status_code=201)
def add_quote(data:NewQuote,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','service_advisor')
    job=one(db,Job,data.job_id,u)
    if job.status=='delivered':raise HTTPException(409,'Delivered job cannot be quoted')
    items=[{'label':i.label,'quantity':i.quantity,'unit_price':str(i.unit_price)} for i in data.items]
    total=sum((i.unit_price*i.quantity for i in data.items),Decimal('0'))
    q=Quote(organization_id=u.organization_id,job_id=job.id,items=items,total=total)
    db.add(q);db.flush();record(db,u,'create','quote',q.id,total=str(total));save(db);return qrow(q)

@app.post('/api/quotes/{quote_id}/decision')
def decide_quote(quote_id:int,data:QuoteDecision,u:User=Depends(current_user),db:Session=Depends(get_db)):
    if 'customer' not in (u.roles or []):raise HTTPException(403,'Only the vehicle owner may authorize repairs')
    q=one(db,Quote,quote_id,u);j=one(db,Job,q.job_id,u)
    vehicle=one(db,Vehicle,j.vehicle_id,u)
    customer=customer_for(db,u)
    if vehicle.customer_id!=customer.id:raise HTTPException(403,'Not authorized to decide this quotation')
    if q.status!='pending':raise HTTPException(409,'Quote already decided')
    q.status=data.decision;q.decided_at=now();record(db,u,'decision','quote',q.id,decision=q.status);save(db);return qrow(q)

@app.get('/api/invoices')
def invoices(u:User=Depends(current_user),db:Session=Depends(get_db)):
    stmt=select(Invoice).where(Invoice.organization_id==u.organization_id)
    if 'customer' in u.roles and not set(u.roles).intersection({'manager','accountant'}):
        v_ids=select(Vehicle.id).where(Vehicle.customer_id==customer_for(db,u).id,Vehicle.organization_id==u.organization_id)
        job_ids=select(Job.id).where(Job.organization_id==u.organization_id,Job.vehicle_id.in_(v_ids))
        q_ids=select(Quote.id).where(Quote.organization_id==u.organization_id,Quote.job_id.in_(job_ids))
        stmt=stmt.where(Invoice.quote_id.in_(q_ids))
    else:permit(u,'manager','accountant','service_advisor')
    return [represent(i,'id','quote_id','total','paid','created_at') for i in db.scalars(stmt.order_by(Invoice.id.desc())).all()]

@app.post('/api/invoices/from-quote/{quote_id}',status_code=201)
def invoice_from_quote(quote_id:int,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','accountant')
    q=one(db,Quote,quote_id,u)
    if q.status!='approved':raise HTTPException(409,'Customer approval required')
    existing=db.scalar(select(Invoice).where(Invoice.organization_id==u.organization_id,Invoice.quote_id==q.id))
    if existing:raise HTTPException(409,'Quote already invoiced')
    i=Invoice(organization_id=u.organization_id,quote_id=q.id,total=q.total,paid=0);db.add(i);db.flush();record(db,u,'create','invoice',i.id);save(db)
    return represent(i,'id','quote_id','total','paid')

@app.post('/api/invoices/{invoice_id}/payments',status_code=201)
def add_payment(invoice_id:int,data:NewPayment,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','accountant')
    inv=one(db,Invoice,invoice_id,u)
    inv=db.scalar(select(Invoice).where(Invoice.id==inv.id,Invoice.organization_id==u.organization_id).with_for_update())
    if inv.paid+data.amount>inv.total:raise HTTPException(409,'Payment exceeds invoice balance')
    x=Payment(organization_id=u.organization_id,invoice_id=inv.id,actor_id=u.id,amount=data.amount,method=data.method)
    db.add(x);inv.paid+=data.amount;db.flush();record(db,u,'payment','invoice',inv.id,amount=str(data.amount),method=data.method);save(db)
    return {'payment_id':x.id,'paid':str(inv.paid),'balance':str(inv.total-inv.paid)}

@app.get('/api/courses')
def courses(u:User=Depends(current_user),db:Session=Depends(get_db)):
    stmt=select(Course).where(Course.organization_id==u.organization_id)
    if not set(u.roles).intersection({'owner','manager','instructor'}):stmt=stmt.where(Course.published==True)
    return [represent(c,'id','title','description','price','published') for c in db.scalars(stmt.order_by(Course.id.desc())).all()]

@app.post('/api/courses',status_code=201)
def add_course(data:NewCourse,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','instructor')
    c=Course(organization_id=u.organization_id,**data.model_dump());db.add(c);db.flush();record(db,u,'create','course',c.id);save(db)
    return represent(c,'id','title','description','price','published')

class PublishCourse(BaseModel):
    published: bool

@app.patch('/api/courses/{course_id}/publish')
def course_publish(course_id:int,data:PublishCourse,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','instructor')
    c=one(db,Course,course_id,u)
    c.published=data.published
    record(db,u,'publish' if c.published else 'unpublish','course',c.id)
    save(db)
    return represent(c,'id','title','published')

@app.post('/api/enrollments',status_code=201)
def enroll(data:NewEnrollment,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','instructor','student')
    student=one(db,User,data.student_id,u)
    if 'student' not in student.roles:raise HTTPException(422,'User is not a student')
    if 'student' in u.roles and not set(u.roles).intersection({'owner','manager','instructor'}) and u.id!=student.id:raise HTTPException(403,'Cannot enroll another student')
    c=one(db,Course,data.course_id,u)
    if not c.published and not set(u.roles).intersection({'owner','manager','instructor'}):raise HTTPException(403,'Course not published')
    e=Enrollment(organization_id=u.organization_id,**data.model_dump());db.add(e);db.flush();record(db,u,'enroll','course',c.id,student_id=student.id);save(db)
    return {'enrollment_id':e.id,'course_id':e.course_id,'student_id':e.student_id,'status':e.status}

@app.get('/api/enrollments')
def enrollments(u:User=Depends(current_user),db:Session=Depends(get_db)):
    stmt=select(Enrollment).where(Enrollment.organization_id==u.organization_id)
    if 'student' in u.roles and not set(u.roles).intersection({'owner','manager','instructor'}):
        stmt=stmt.where(Enrollment.student_id==u.id)
    else: permit(u,'manager','instructor')
    return [represent(e,'id','student_id','course_id','status','progress') for e in db.scalars(stmt.order_by(Enrollment.id.desc())).all()]

@app.get('/api/gearbox-reports')
def gearbox_reports(u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','dsg_specialist')
    stmt=select(GearboxReport).where(GearboxReport.organization_id==u.organization_id)
    if not set(u.roles).intersection({'owner','manager'}):
        job_ids=select(Job.id).where(Job.organization_id==u.organization_id,Job.assigned_to==u.id)
        stmt=stmt.where(GearboxReport.job_id.in_(job_ids))
    return [represent(r,'id','job_id','transmission_code','fault_codes','components_replaced','test_results') for r in db.scalars(stmt.order_by(GearboxReport.id.desc())).all()]

@app.get('/api/battery-reports')
def battery_reports(u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','battery_specialist')
    stmt=select(BatteryReport).where(BatteryReport.organization_id==u.organization_id)
    if not set(u.roles).intersection({'owner','manager'}):
        job_ids=select(Job.id).where(Job.organization_id==u.organization_id,Job.assigned_to==u.id)
        stmt=stmt.where(BatteryReport.job_id.in_(job_ids))
    return [represent(r,'id','job_id','chemistry','battery_serial','voltage','health_percent','notes','high_voltage') for r in db.scalars(stmt.order_by(BatteryReport.id.desc())).all()]

@app.get('/api/dashboard')
def dashboard(u:User=Depends(current_user),db:Session=Depends(get_db)):
    if 'customer' in u.roles and not set(u.roles).intersection(WORKSHOP|{'accountant'}):
        c=customer_for(db,u)
        vs=db.scalars(select(Vehicle).where(Vehicle.organization_id==u.organization_id,Vehicle.customer_id==c.id)).all()
        js=db.scalars(select(Job).where(Job.organization_id==u.organization_id,Job.vehicle_id.in_([v.id for v in vs]) if vs else False)).all()
        return {'audience':'customer','customer':crow(c),'vehicles':len(vs),'active_jobs':len([j for j in js if j.status!='delivered'])}
    if 'student' in u.roles and not set(u.roles).intersection({'owner','manager','instructor'}):
        n=db.scalar(select(func.count()).select_from(Enrollment).where(Enrollment.organization_id==u.organization_id,Enrollment.student_id==u.id))
        return {'audience':'student','courses_enrolled':n}
    staff(u)
    org=u.organization_id
    if not set(u.roles or []).intersection({'owner','manager','service_advisor','accountant','inventory','instructor'}):
        mine=db.scalars(select(Job).where(Job.organization_id==org,Job.assigned_to==u.id)).all()
        return {'audience':'technician','assigned_jobs':len(mine),'active_jobs':sum(j.status!='delivered' for j in mine),
                'awaiting_quality':sum(j.status=='quality_check' for j in mine)}
    org=u.organization_id
    def count(cls):return db.scalar(select(func.count()).select_from(cls).where(cls.organization_id==org))
    return {'audience':'staff','customers':count(Customer),'vehicles':count(Vehicle),'jobs':count(Job),
            'bookings':count(Booking),'parts':count(Part),'courses':count(Course),
            'pending_quotes':db.scalar(select(func.count()).select_from(Quote).where(Quote.organization_id==org,Quote.status=='pending'))}

@app.get('/api/audit')
def audit(u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager')
    stmt=select(AuditEvent).where(AuditEvent.organization_id==u.organization_id).order_by(AuditEvent.id.desc()).limit(100)
    return [represent(x,'id','actor_id','action','entity','entity_id','data','created_at') for x in db.scalars(stmt).all()]

@app.post('/api/ai/ask')
def ai_assistant(u:User=Depends(current_user)):
    # Explicitly unavailable until scoped retrieval, safety and vendor credentials are configured.
    raise HTTPException(503,'AI assistant is not configured; no diagnostic or financial advice was generated')

from advanced import router as advanced_router
app.include_router(advanced_router)
from photos import router as photos_router
app.include_router(photos_router)

WEB_DIR=Path(__file__).resolve().parent.parent/'web'
if WEB_DIR.exists():
    app.mount('/assets',StaticFiles(directory=str(WEB_DIR)),name='assets')
    @app.get('/')
    def landing():return FileResponse(WEB_DIR/'index.html')
    @app.get('/admin')
    def admin_ui():return FileResponse(WEB_DIR/'index.html')
    @app.get('/customer')
    def customer_ui():return FileResponse(WEB_DIR/'index.html')
