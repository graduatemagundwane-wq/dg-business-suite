"""PASH Auto v0.2 operational modules: explicit authorization and tenant scoping.

No simulated payments, AI answers, external delivery, or equipment commands occur here.
"""
from datetime import datetime, timezone, timedelta
from decimal import Decimal
from secrets import token_urlsafe
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select, func
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from db import get_db
from security import current_user, permit
from models import (User, Customer, Vehicle, Job, Part, StockMovement, Course, Enrollment, AuditEvent,
                    Supplier, PurchaseOrder, Equipment, WorkLog, Expense, Warranty, WarrantyClaim,
                    Fleet, FleetVehicle, CourseLesson, AcademyAssessment, AssessmentAttempt,
                    Certificate, ServiceReview, StaffQualification, Notification, Invoice, Payment, Attendance, now)

router = APIRouter(prefix='/api', tags=['Expanded operations'])
TECH = {'owner','manager','mechanic','dsg_specialist','battery_specialist'}
MANAGERS = {'owner','manager'}

def one(db, typ, pk, user):
    obj = db.scalar(select(typ).where(typ.id == pk, typ.organization_id == user.organization_id))
    if obj is None: raise HTTPException(404, 'Record not found')
    return obj

def audit(db, u, action, entity, pk, **payload):
    db.add(AuditEvent(organization_id=u.organization_id, actor_id=u.id,
                      action=action, entity=entity, entity_id=pk, data=payload))

def commit(db):
    try: db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, 'Conflicting or duplicate record')

def row(obj, *fields):
    values = {}
    for field in fields:
        value = getattr(obj, field)
        values[field] = value.isoformat() if isinstance(value, datetime) else str(value) if isinstance(value, Decimal) else value
    return values

def is_staff(u): return bool(set(u.roles or []).intersection(MANAGERS|{'service_advisor','accountant','inventory','instructor'}|TECH))

def owns_vehicle(db, u, vehicle):
    if is_staff(u): return
    if 'customer' not in (u.roles or []): raise HTTPException(403, 'Customer account required')
    customer = db.scalar(select(Customer).where(Customer.user_id == u.id, Customer.organization_id == u.organization_id))
    if not customer or customer.id != vehicle.customer_id: raise HTTPException(403, 'Vehicle not linked to account')

def owns_job(db,u,job):
    vehicle = one(db,Vehicle,job.vehicle_id,u)
    owns_vehicle(db,u,vehicle)
    return vehicle

def assigned_or_manager(u,job):
    permit(u,'manager','mechanic','dsg_specialist','battery_specialist')
    if not set(u.roles or []).intersection(MANAGERS) and job.assigned_to!=u.id:
        raise HTTPException(403,'Job not assigned to this technician')

# Supplier purchase lifecycle and atomic parts receiving
class SupplierInput(BaseModel):
    name: str = Field(min_length=2, max_length=160)
    phone: str = ''
    email: str = ''
    notes: str = ''

class POLine(BaseModel):
    part_id: int = Field(gt=0)
    quantity: int = Field(gt=0)
    unit_cost: Decimal = Field(ge=0, max_digits=12, decimal_places=2)

class POInput(BaseModel):
    supplier_id: int = Field(gt=0)
    lines: list[POLine] = Field(min_length=1, max_length=100)

@router.get('/suppliers')
def suppliers(u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','inventory','accountant')
    return [row(x,'id','name','phone','email','notes') for x in db.scalars(select(Supplier).where(Supplier.organization_id==u.organization_id)).all()]

@router.post('/suppliers',status_code=201)
def supplier_create(d:SupplierInput,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','inventory')
    s=Supplier(organization_id=u.organization_id,**d.model_dump());db.add(s);db.flush()
    audit(db,u,'create','supplier',s.id);commit(db)
    return row(s,'id','name','phone','email','notes')

@router.get('/purchase-orders')
def purchase_orders(u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','inventory','accountant')
    return [row(x,'id','supplier_id','lines','total','status','created_at','received_at') for x in db.scalars(select(PurchaseOrder).where(PurchaseOrder.organization_id==u.organization_id).order_by(PurchaseOrder.id.desc())).all()]

@router.post('/purchase-orders',status_code=201)
def create_order(d:POInput,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','inventory')
    one(db,Supplier,d.supplier_id,u)
    if len({x.part_id for x in d.lines})!=len(d.lines):raise HTTPException(422,'Duplicate part in purchase order')
    for x in d.lines: one(db,Part,x.part_id,u)
    total=sum((x.quantity*x.unit_cost for x in d.lines),Decimal('0'))
    p=PurchaseOrder(organization_id=u.organization_id,supplier_id=d.supplier_id,
                    lines=[{'part_id':x.part_id,'quantity':x.quantity,'unit_cost':str(x.unit_cost)} for x in d.lines],
                    total=total,created_by=u.id)
    db.add(p);db.flush();audit(db,u,'create','purchase_order',p.id,total=str(total));commit(db)
    return row(p,'id','supplier_id','lines','total','status')

@router.post('/purchase-orders/{purchase_order_id}/receive')
def receive_order(purchase_order_id:int,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','inventory')
    p=db.scalar(select(PurchaseOrder).where(PurchaseOrder.id==purchase_order_id,PurchaseOrder.organization_id==u.organization_id).with_for_update())
    if not p:raise HTTPException(404,'Order not found')
    if p.status!='draft':raise HTTPException(409,'Order already received or closed')
    # Atomic state transition and stock increments, all within the same transaction.
    for ln in p.lines:
        part=db.scalar(select(Part).where(Part.id==ln['part_id'],Part.organization_id==u.organization_id).with_for_update())
        if not part:raise HTTPException(409,'A purchase order part no longer exists')
        part.quantity+=ln['quantity']
        db.add(StockMovement(organization_id=u.organization_id,part_id=part.id,actor_id=u.id,
                             quantity_delta=ln['quantity'],reason='purchase_order_received'))
    p.status='received';p.received_at=now();audit(db,u,'receive','purchase_order',p.id);commit(db)
    return row(p,'id','status','received_at')

# Calibration and equipment availability
class EquipmentInput(BaseModel):
    name: str = Field(min_length=2)
    serial: str = Field(min_length=2)
    category: str = Field(min_length=2)
    location: str = ''
    calibration_due: datetime | None = None
class EquipmentUpdate(BaseModel):
    status: str = Field(pattern='^(available|in_use|maintenance|quarantined|retired)$')
    calibration_due: datetime | None = None

@router.get('/equipment')
def equipment(u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','inventory','mechanic','dsg_specialist','battery_specialist')
    return [row(x,'id','name','serial','category','status','location','calibration_due') for x in db.scalars(select(Equipment).where(Equipment.organization_id==u.organization_id)).all()]

@router.post('/equipment',status_code=201)
def equipment_create(d:EquipmentInput,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','inventory')
    e=Equipment(organization_id=u.organization_id,**d.model_dump());db.add(e);db.flush();audit(db,u,'create','equipment',e.id);commit(db)
    return row(e,'id','name','serial','category','status','location','calibration_due')

@router.patch('/equipment/{equipment_id}')
def equipment_update(equipment_id:int,d:EquipmentUpdate,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','inventory')
    e=one(db,Equipment,equipment_id,u);e.status=d.status
    if d.calibration_due is not None:e.calibration_due=d.calibration_due
    audit(db,u,'update','equipment',e.id,status=e.status);commit(db)
    return row(e,'id','name','serial','status','calibration_due')

# Technician accountability
class WorkLogInput(BaseModel):
    job_id: int = Field(gt=0)
    minutes: int = Field(gt=0,le=1440)
    description: str = Field(min_length=3,max_length=4000)

@router.get('/work-logs')
def work_logs(job_id:int|None=None,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','mechanic','dsg_specialist','battery_specialist')
    stmt=select(WorkLog).where(WorkLog.organization_id==u.organization_id)
    if job_id is not None:
        j=one(db,Job,job_id,u);assigned_or_manager(u,j)
        stmt=stmt.where(WorkLog.job_id==job_id)
    if not set(u.roles).intersection(MANAGERS):stmt=stmt.where(WorkLog.technician_id==u.id)
    return [row(x,'id','job_id','technician_id','minutes','description','logged_at') for x in db.scalars(stmt.order_by(WorkLog.id.desc())).all()]

@router.post('/work-logs',status_code=201)
def log_work(d:WorkLogInput,u:User=Depends(current_user),db:Session=Depends(get_db)):
    j=one(db,Job,d.job_id,u);assigned_or_manager(u,j)
    if j.status=='delivered':raise HTTPException(409,'Cannot log labor after delivery')
    w=WorkLog(organization_id=u.organization_id,job_id=j.id,technician_id=u.id,minutes=d.minutes,description=d.description)
    db.add(w);db.flush();audit(db,u,'record','work_log',w.id,job_id=j.id);commit(db)
    return row(w,'id','job_id','technician_id','minutes','description','logged_at')

# Actual recorded expenses only. No fictitious revenue or bank integration.
class ExpenseInput(BaseModel):
    category: str = Field(min_length=2,max_length=70)
    description: str = Field(min_length=3,max_length=4000)
    amount: Decimal = Field(gt=0,max_digits=12,decimal_places=2)
    currency: str = Field(default='USD',pattern='^(USD|ZWG)$')

@router.get('/expenses')
def expenses(u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','accountant')
    return [row(x,'id','category','description','amount','currency','recorded_by','occurred_at') for x in db.scalars(select(Expense).where(Expense.organization_id==u.organization_id).order_by(Expense.id.desc())).all()]

@router.post('/expenses',status_code=201)
def expense_create(d:ExpenseInput,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','accountant')
    x=Expense(organization_id=u.organization_id,recorded_by=u.id,**d.model_dump());db.add(x);db.flush();audit(db,u,'record','expense',x.id,amount=str(x.amount),currency=x.currency);commit(db)
    return row(x,'id','category','description','amount','currency','occurred_at')

@router.get('/reports/finance')
def finance_report(u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','accountant')
    org=u.organization_id
    # Do not subtract multi-currency expenses without conversion: report each currency separately.
    received=db.scalar(select(func.sum(Payment.amount)).where(Payment.organization_id==org)) or Decimal('0')
    invoiced=db.scalar(select(func.sum(Invoice.total)).where(Invoice.organization_id==org)) or Decimal('0')
    paid=db.scalar(select(func.sum(Invoice.paid)).where(Invoice.organization_id==org)) or Decimal('0')
    result=db.execute(select(Expense.currency,func.sum(Expense.amount)).where(Expense.organization_id==org).group_by(Expense.currency)).all()
    return {'invoiced_usd_assumed':str(invoiced),'recorded_payments':str(received),
            'outstanding_receivables':str(invoiced-paid),'expenses_by_currency':{currency:str(amount) for currency,amount in result},
            'notice':'No exchange-rate conversion or full general-ledger profit calculation is performed.'}

# Warranty terms and verifiable customer claims
class WarrantyInput(BaseModel):
    job_id: int = Field(gt=0)
    coverage: str = Field(min_length=5)
    duration_days: int = Field(ge=1,le=3650)
    mileage_limit: int|None = Field(default=None,ge=0)
class ClaimInput(BaseModel):
    warranty_id: int = Field(gt=0)
    description: str = Field(min_length=10)
class ClaimDecision(BaseModel):
    status: str = Field(pattern='^(under_review|approved|rejected|resolved)$')
    resolution: str = ''

@router.get('/warranties')
def warranties(u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','service_advisor','customer')
    items=db.scalars(select(Warranty).where(Warranty.organization_id==u.organization_id)).all()
    if not is_staff(u):
        c=db.scalar(select(Customer).where(Customer.user_id==u.id,Customer.organization_id==u.organization_id))
        if not c:raise HTTPException(403,'Customer profile required')
        owned_vehicles=select(Vehicle.id).where(Vehicle.organization_id==u.organization_id,Vehicle.customer_id==c.id)
        owned_jobs=set(db.scalars(select(Job.id).where(Job.organization_id==u.organization_id,Job.vehicle_id.in_(owned_vehicles))).all())
        items=[x for x in items if x.job_id in owned_jobs]
    return [row(x,'id','job_id','coverage','starts_at','expires_at','mileage_limit','status') for x in items]

@router.post('/warranties',status_code=201)
def warranty_create(d:WarrantyInput,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','service_advisor')
    j=one(db,Job,d.job_id,u)
    if j.status!='delivered':raise HTTPException(409,'Warranty can only be issued after delivery')
    w=Warranty(organization_id=u.organization_id,job_id=j.id,coverage=d.coverage,expires_at=now()+timedelta(days=d.duration_days),mileage_limit=d.mileage_limit)
    db.add(w);db.flush();audit(db,u,'issue','warranty',w.id,job_id=j.id);commit(db)
    return row(w,'id','job_id','coverage','starts_at','expires_at','mileage_limit','status')

@router.get('/warranty-claims')
def claims(u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','service_advisor','customer')
    stmt=select(WarrantyClaim).where(WarrantyClaim.organization_id==u.organization_id)
    if not is_staff(u):
        c=db.scalar(select(Customer).where(Customer.user_id==u.id,Customer.organization_id==u.organization_id))
        if not c:raise HTTPException(403,'Customer account required')
        stmt=stmt.where(WarrantyClaim.customer_id==c.id)
    return [row(x,'id','warranty_id','customer_id','description','status','resolution','created_at') for x in db.scalars(stmt).all()]

@router.post('/warranty-claims',status_code=201)
def claim_create(d:ClaimInput,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'customer','manager','service_advisor')
    w=one(db,Warranty,d.warranty_id,u)
    j=one(db,Job,w.job_id,u)
    v=owns_job(db,u,j)
    c=one(db,Customer,v.customer_id,u)
    if w.status!='active' or w.expires_at.replace(tzinfo=timezone.utc)<now():raise HTTPException(409,'Warranty expired or inactive')
    x=WarrantyClaim(organization_id=u.organization_id,warranty_id=w.id,customer_id=c.id,description=d.description)
    db.add(x);db.flush();audit(db,u,'submit','warranty_claim',x.id);commit(db)
    return row(x,'id','warranty_id','status','description')

@router.patch('/warranty-claims/{claim_id}')
def claim_update(claim_id:int,d:ClaimDecision,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','service_advisor')
    x=one(db,WarrantyClaim,claim_id,u)
    x.status=d.status;x.resolution=d.resolution;audit(db,u,'decision','warranty_claim',x.id,status=x.status);commit(db)
    return row(x,'id','status','resolution')

# Fleet accounts and explicit vehicle membership
class FleetInput(BaseModel):
    customer_id:int=Field(gt=0)
    name:str=Field(min_length=2)
    contact:str=''
class FleetVehicleInput(BaseModel):
    vehicle_id:int=Field(gt=0)

@router.get('/fleets')
def fleets(u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','service_advisor','customer')
    stmt=select(Fleet).where(Fleet.organization_id==u.organization_id)
    if not is_staff(u):
        c=db.scalar(select(Customer).where(Customer.user_id==u.id,Customer.organization_id==u.organization_id))
        if not c:raise HTTPException(403,'Customer profile required')
        stmt=stmt.where(Fleet.customer_id==c.id)
    return [row(x,'id','customer_id','name','contact') for x in db.scalars(stmt).all()]

@router.post('/fleets',status_code=201)
def fleet_create(d:FleetInput,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','service_advisor')
    one(db,Customer,d.customer_id,u)
    f=Fleet(organization_id=u.organization_id,**d.model_dump());db.add(f);db.flush();audit(db,u,'create','fleet',f.id);commit(db)
    return row(f,'id','customer_id','name','contact')

@router.post('/fleets/{fleet_id}/vehicles',status_code=201)
def fleet_add_vehicle(fleet_id:int,d:FleetVehicleInput,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','service_advisor')
    f=one(db,Fleet,fleet_id,u);v=one(db,Vehicle,d.vehicle_id,u)
    if v.customer_id!=f.customer_id:raise HTTPException(422,'Vehicle belongs to a different customer')
    x=FleetVehicle(organization_id=u.organization_id,fleet_id=f.id,vehicle_id=v.id);db.add(x);db.flush();audit(db,u,'add_vehicle','fleet',f.id,vehicle_id=v.id);commit(db)
    return row(x,'id','fleet_id','vehicle_id')

@router.get('/fleets/{fleet_id}/vehicles')
def fleet_vehicles(fleet_id:int,u:User=Depends(current_user),db:Session=Depends(get_db)):
    f=one(db,Fleet,fleet_id,u)
    if not is_staff(u):
        permit(u,'customer')
        c=db.scalar(select(Customer).where(Customer.user_id==u.id,Customer.organization_id==u.organization_id))
        if not c or c.id!=f.customer_id:raise HTTPException(403,'Fleet access denied')
    return [row(x,'id','fleet_id','vehicle_id') for x in db.scalars(select(FleetVehicle).where(FleetVehicle.organization_id==u.organization_id,FleetVehicle.fleet_id==f.id)).all()]

# Academy lessons, exams, scoring, and independently verifiable certificates.
class LessonInput(BaseModel):
    course_id:int=Field(gt=0)
    title:str=Field(min_length=3)
    body:str=Field(min_length=10)
    position:int=Field(default=1,ge=1)
    published:bool=False
class QuestionInput(BaseModel):
    prompt:str=Field(min_length=5)
    choices:list[str]=Field(min_length=2,max_length=6)
    answer:int=Field(ge=0,le=5)
class AssessmentInput(BaseModel):
    course_id:int=Field(gt=0)
    title:str=Field(min_length=3)
    questions:list[QuestionInput]=Field(min_length=1,max_length=100)
    passing_percent:int=Field(default=70,ge=0,le=100)
    published:bool=False
class AttemptInput(BaseModel):
    answers:list[int]=Field(min_length=1,max_length=100)
class CertificateInput(BaseModel):
    student_id:int=Field(gt=0)
    course_id:int=Field(gt=0)

@router.get('/academy/lessons')
def lessons(course_id:int|None=None,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'student','instructor','manager')
    q=select(CourseLesson).where(CourseLesson.organization_id==u.organization_id)
    if course_id is not None:
        one(db,Course,course_id,u);q=q.where(CourseLesson.course_id==course_id)
    if not set(u.roles).intersection({'instructor','manager','owner'}):
        q=q.where(CourseLesson.published==True)
        enrollment_ids=select(Enrollment.course_id).where(Enrollment.organization_id==u.organization_id,Enrollment.student_id==u.id)
        q=q.where(CourseLesson.course_id.in_(enrollment_ids))
    return [row(x,'id','course_id','title','body','position','published') for x in db.scalars(q.order_by(CourseLesson.position)).all()]

@router.post('/academy/lessons',status_code=201)
def lesson_create(d:LessonInput,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'instructor','manager')
    one(db,Course,d.course_id,u)
    l=CourseLesson(organization_id=u.organization_id,**d.model_dump());db.add(l);db.flush();audit(db,u,'create','lesson',l.id);commit(db)
    return row(l,'id','course_id','title','body','position','published')

class PublishLesson(BaseModel):
    published: bool

@router.patch('/academy/lessons/{lesson_id}/publish')
def lesson_publish(lesson_id:int,d:PublishLesson,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','instructor')
    lesson=one(db,CourseLesson,lesson_id,u)
    lesson.published=d.published
    audit(db,u,'publish' if d.published else 'unpublish','lesson',lesson.id)
    commit(db)
    return row(lesson,'id','course_id','title','published')

@router.get('/academy/assessments')
def assessments(course_id:int|None=None,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'instructor','manager','student')
    q=select(AcademyAssessment).where(AcademyAssessment.organization_id==u.organization_id)
    if course_id is not None:
        one(db,Course,course_id,u);q=q.where(AcademyAssessment.course_id==course_id)
    if not set(u.roles).intersection({'owner','manager','instructor'}):
        enroll_ids=select(Enrollment.course_id).where(Enrollment.organization_id==u.organization_id,Enrollment.student_id==u.id)
        q=q.where(AcademyAssessment.published==True,AcademyAssessment.course_id.in_(enroll_ids))
    return [{'id':x.id,'course_id':x.course_id,'title':x.title,'passing_percent':x.passing_percent,'published':x.published,
             'questions':[{'prompt':v['prompt'],'choices':v['choices']} for v in x.questions]} for x in db.scalars(q).all()]

@router.post('/academy/assessments',status_code=201)
def assessment_create(d:AssessmentInput,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'instructor','manager')
    one(db,Course,d.course_id,u)
    for q in d.questions:
        if q.answer>=len(q.choices):raise HTTPException(422,'Answer index must match available choices')
    x=AcademyAssessment(organization_id=u.organization_id,course_id=d.course_id,title=d.title,
                        questions=[q.model_dump() for q in d.questions],passing_percent=d.passing_percent,published=d.published)
    db.add(x);db.flush();audit(db,u,'create','assessment',x.id);commit(db)
    return {'id':x.id,'title':x.title,'questions_count':len(x.questions)}

@router.patch('/academy/assessments/{assessment_id}/publish')
def assessment_publish(assessment_id:int,d:PublishLesson,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','instructor')
    a=one(db,AcademyAssessment,assessment_id,u)
    a.published=d.published
    audit(db,u,'publish' if d.published else 'unpublish','assessment',a.id)
    commit(db)
    return {'id':a.id,'published':a.published}

@router.post('/academy/assessments/{assessment_id}/attempt',status_code=201)
def attempt(assessment_id:int,d:AttemptInput,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'student')
    if 'student' not in u.roles:raise HTTPException(403,'Student account required')
    assessment=one(db,AcademyAssessment,assessment_id,u)
    if not assessment.published:raise HTTPException(403,'Assessment not published')
    enrolled=db.scalar(select(Enrollment.id).where(Enrollment.organization_id==u.organization_id,Enrollment.course_id==assessment.course_id,Enrollment.student_id==u.id))
    if not enrolled:raise HTTPException(403,'Not enrolled in this course')
    if len(d.answers)!=len(assessment.questions):raise HTTPException(422,'Answers count mismatch')
    for i,answer in enumerate(d.answers):
        if answer<0 or answer>=len(assessment.questions[i]['choices']):raise HTTPException(422,'Invalid answer option')
    correct=sum(int(answer==q['answer']) for answer,q in zip(d.answers,assessment.questions))
    score=round(correct*100/len(assessment.questions));passed=score>=assessment.passing_percent
    x=AssessmentAttempt(organization_id=u.organization_id,assessment_id=assessment.id,student_id=u.id,
                        answers=d.answers,score=score,passed=passed)
    db.add(x);db.flush();audit(db,u,'submit','assessment_attempt',x.id,score=score);commit(db)
    return {'attempt_id':x.id,'score':score,'passed':passed}

@router.get('/academy/attempts')
def attempts(u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'student','instructor','manager')
    stmt=select(AssessmentAttempt).where(AssessmentAttempt.organization_id==u.organization_id)
    if not set(u.roles).intersection({'owner','manager','instructor'}):stmt=stmt.where(AssessmentAttempt.student_id==u.id)
    return [row(x,'id','assessment_id','student_id','score','passed','attempted_at') for x in db.scalars(stmt).all()]

@router.post('/academy/certificates',status_code=201)
def certificate_create(d:CertificateInput,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager')  # Instructor grades; management certifies.
    student=one(db,User,d.student_id,u);course=one(db,Course,d.course_id,u)
    if 'student' not in student.roles:raise HTTPException(422,'Not a student')
    enrol=db.scalar(select(Enrollment).where(Enrollment.organization_id==u.organization_id,
                                             Enrollment.student_id==student.id,Enrollment.course_id==course.id))
    if not enrol or enrol.progress!=100:raise HTTPException(409,'Verified course completion required')
    cert=Certificate(organization_id=u.organization_id,student_id=student.id,course_id=course.id,
                     issued_by=u.id,verification_code=token_urlsafe(24))
    db.add(cert);db.flush();audit(db,u,'issue','certificate',cert.id);commit(db)
    return row(cert,'id','student_id','course_id','verification_code','issued_at','revoked')

@router.get('/academy/certificates')
def certificates(u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'student','instructor','manager')
    stmt=select(Certificate).where(Certificate.organization_id==u.organization_id)
    if not set(u.roles).intersection({'owner','manager','instructor'}):stmt=stmt.where(Certificate.student_id==u.id)
    return [row(c,'id','student_id','course_id','verification_code','issued_at','revoked') for c in db.scalars(stmt).all()]

@router.post('/academy/enrollments/{enrollment_id}/complete')
def complete_enrollment(enrollment_id:int,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','instructor')
    e=one(db,Enrollment,enrollment_id,u)
    # An assessment must have a verified passing submission from this student.
    assessment_ids=select(AcademyAssessment.id).where(AcademyAssessment.organization_id==u.organization_id,AcademyAssessment.course_id==e.course_id,AcademyAssessment.published==True)
    had_assessment=db.scalar(select(AcademyAssessment.id).where(AcademyAssessment.organization_id==u.organization_id,AcademyAssessment.course_id==e.course_id,AcademyAssessment.published==True).limit(1))
    passed=db.scalar(select(AssessmentAttempt.id).where(AssessmentAttempt.organization_id==u.organization_id,
                       AssessmentAttempt.student_id==e.student_id,AssessmentAttempt.assessment_id.in_(assessment_ids),AssessmentAttempt.passed==True).limit(1))
    if not had_assessment or not passed:raise HTTPException(409,'Passing a published course assessment is required')
    e.progress=100;e.status='completed';audit(db,u,'complete','enrollment',e.id);commit(db)
    return row(e,'id','student_id','course_id','progress','status')

@router.patch('/academy/certificates/{certificate_id}/revoke')
def revoke_certificate(certificate_id:int,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager')
    c=one(db,Certificate,certificate_id,u)
    c.revoked=True;audit(db,u,'revoke','certificate',c.id);commit(db)
    return {'id':c.id,'revoked':True}

@router.get('/verify/certificate/{code}')
def verify_certificate(code:str,db:Session=Depends(get_db)):
    c=db.scalar(select(Certificate).where(Certificate.verification_code==code))
    if not c:raise HTTPException(404,'Certificate not found')
    student=db.get(User,c.student_id);course=db.get(Course,c.course_id)
    return {'valid':not c.revoked,'course':course.title,'student':student.name,'issued_at':c.issued_at.isoformat()}

# Customer feedback visible only to own customer or authorized management.
class ReviewInput(BaseModel):
    job_id:int=Field(gt=0)
    rating:int=Field(ge=1,le=5)
    comment:str=''

@router.post('/reviews',status_code=201)
def review_create(d:ReviewInput,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'customer')
    if 'customer' not in u.roles:raise HTTPException(403,'Customer account required')
    j=one(db,Job,d.job_id,u);v=owns_job(db,u,j)
    if j.status!='delivered':raise HTTPException(409,'Review available after service delivery')
    x=ServiceReview(organization_id=u.organization_id,customer_id=v.customer_id,job_id=j.id,rating=d.rating,comment=d.comment)
    db.add(x);db.flush();audit(db,u,'create','review',x.id);commit(db)
    return row(x,'id','job_id','rating','comment')

@router.get('/reviews')
def reviews(u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'customer','manager','service_advisor')
    stmt=select(ServiceReview).where(ServiceReview.organization_id==u.organization_id)
    if not is_staff(u):
        c=db.scalar(select(Customer).where(Customer.user_id==u.id,Customer.organization_id==u.organization_id))
        if not c:raise HTTPException(403,'Customer account required')
        stmt=stmt.where(ServiceReview.customer_id==c.id)
    return [row(x,'id','customer_id','job_id','rating','comment','created_at') for x in db.scalars(stmt).all()]

# Verified competency records: no electronic high voltage switching is implemented.
class QualificationInput(BaseModel):
    user_id:int=Field(gt=0)
    qualification:str=Field(min_length=3)
    high_voltage_approved:bool=False
    expires_at:datetime|None=None

@router.post('/staff/qualifications',status_code=201)
def qualification_create(d:QualificationInput,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager')
    candidate=one(db,User,d.user_id,u)
    if not set(candidate.roles).intersection({'mechanic','dsg_specialist','battery_specialist'}):raise HTTPException(422,'Technician account required')
    q=StaffQualification(organization_id=u.organization_id,verified_by=u.id,**d.model_dump())
    db.add(q);db.flush();audit(db,u,'verify','qualification',q.id,high_voltage_approved=q.high_voltage_approved);commit(db)
    return row(q,'id','user_id','qualification','high_voltage_approved','expires_at','verified_by')

@router.get('/staff/qualifications')
def qualifications(u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','mechanic','dsg_specialist','battery_specialist')
    stmt=select(StaffQualification).where(StaffQualification.organization_id==u.organization_id)
    if not set(u.roles).intersection(MANAGERS):stmt=stmt.where(StaffQualification.user_id==u.id)
    return [row(x,'id','user_id','qualification','high_voltage_approved','expires_at','verified_by') for x in db.scalars(stmt).all()]

# Server-persisted in-app notifications. Does NOT claim SMS/WhatsApp delivery.
class NotificationInput(BaseModel):
    recipient_id:int=Field(gt=0)
    message:str=Field(min_length=3,max_length=500)

@router.get('/notifications')
def notifications(u:User=Depends(current_user),db:Session=Depends(get_db)):
    return [row(x,'id','recipient_id','message','read','created_at') for x in db.scalars(select(Notification).where(Notification.organization_id==u.organization_id,Notification.recipient_id==u.id).order_by(Notification.id.desc())).all()]

@router.post('/notifications',status_code=201)
def notify(d:NotificationInput,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','service_advisor','instructor')
    one(db,User,d.recipient_id,u)
    n=Notification(organization_id=u.organization_id,recipient_id=d.recipient_id,message=d.message)
    db.add(n);db.flush();audit(db,u,'create','notification',n.id);commit(db)
    return row(n,'id','recipient_id','message','read')

@router.patch('/notifications/{notification_id}/read')
def mark_read(notification_id:int,u:User=Depends(current_user),db:Session=Depends(get_db)):
    n=one(db,Notification,notification_id,u)
    if n.recipient_id!=u.id:raise HTTPException(403,'Not your notification')
    n.read=True;commit(db);return {'id':n.id,'read':True}

# A documented supervisor-reviewed permit is required before recording high-voltage battery jobs.
# This is NOT a substitute for electrical isolation, PPE, equipment and qualified supervision.
from models import HVSafetyPermit
class HVPermitInput(BaseModel):
    job_id:int=Field(gt=0)
    technician_id:int=Field(gt=0)
    risk_assessed:bool
    isolation_verified:bool
    ppe_checked:bool
    emergency_plan_confirmed:bool

@router.post('/battery-safety-permits',status_code=201)
def approve_hv_permit(d:HVPermitInput,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager')
    j=one(db,Job,d.job_id,u)
    t=one(db,User,d.technician_id,u)
    if j.category!='battery':raise HTTPException(422,'Battery job required')
    if j.assigned_to!=t.id or 'battery_specialist' not in (t.roles or []):raise HTTPException(403,'Assigned battery specialist required')
    q=db.scalar(select(StaffQualification).where(StaffQualification.organization_id==u.organization_id,
                StaffQualification.user_id==t.id,StaffQualification.high_voltage_approved==True))
    if not q or (q.expires_at and q.expires_at.replace(tzinfo=q.expires_at.tzinfo or timezone.utc)<now()):
        raise HTTPException(403,'Current approved high voltage qualification required')
    if not all([d.risk_assessed,d.isolation_verified,d.ppe_checked,d.emergency_plan_confirmed]):
        raise HTTPException(422,'All documented safety prerequisites must be verified')
    x=HVSafetyPermit(organization_id=u.organization_id,job_id=j.id,technician_id=t.id,
                    authorized_by=u.id,checklist=d.model_dump(exclude={'job_id','technician_id'}))
    db.add(x);db.flush();audit(db,u,'authorize','hv_safety_permit',x.id);commit(db)
    return row(x,'id','job_id','technician_id','authorized_by','checklist','created_at')

@router.get('/battery-safety-permits')
def hv_permits(u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','battery_specialist')
    stmt=select(HVSafetyPermit).where(HVSafetyPermit.organization_id==u.organization_id)
    if not set(u.roles).intersection(MANAGERS):stmt=stmt.where(HVSafetyPermit.technician_id==u.id)
    return [row(x,'id','job_id','technician_id','authorized_by','checklist','created_at') for x in db.scalars(stmt).all()]

@router.get('/inspections')
def inspections(u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager','service_advisor','mechanic','dsg_specialist','battery_specialist')
    from models import Inspection
    q=select(Inspection).where(Inspection.organization_id==u.organization_id)
    if not set(u.roles).intersection({'owner','manager','service_advisor'}):
        assigned=select(Job.id).where(Job.organization_id==u.organization_id,Job.assigned_to==u.id)
        q=q.where(Inspection.job_id.in_(assigned))
    return [row(x,'id','job_id','inspector_id','checklist','notes','created_at') for x in db.scalars(q.order_by(Inspection.id.desc())).all()]

# Staff attendance approvals, unpaid breaks and payroll-safe summaries.
# Clock-in always reflects the actual server time, never the approval time.
from zoneinfo import ZoneInfo
from datetime import date
from typing import Literal
import os

HARARE = ZoneInfo('Africa/Harare')

class AttendanceDecision(BaseModel):
    decision: Literal['approve','reject']
    note: str = Field(default='',max_length=500)

class ClockOutInput(BaseModel):
    unpaid_break_minutes: int = Field(default=0,ge=0,le=1440)

def as_utc(value):
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)

def attendance_record(a):
    result=row(a,'id','user_id','clock_in','clock_out','approval_status',
               'decision_by','decision_at','decision_note','unpaid_break_minutes')
    start=as_utc(a.clock_in)
    end=as_utc(a.clock_out) if a.clock_out else None
    # SQLite may return naive timestamps; always emit canonical UTC instants.
    result['clock_in']=start.isoformat()
    result['clock_out']=end.isoformat() if end else None
    result['decision_at']=as_utc(a.decision_at).isoformat() if a.decision_at else None
    raw=max(0,int((end-start).total_seconds()//60)) if end else None
    net=max(0,raw-a.unpaid_break_minutes) if raw is not None else None
    result['worked_minutes']=net
    result['payable_minutes']=net if a.approval_status=='approved' and net is not None else 0
    result['overnight']=bool(end and start.astimezone(HARARE).date()!=end.astimezone(HARARE).date())
    result['missing_checkout']=bool(not end and (now()-start)>timedelta(hours=18))
    return result

@router.get('/attendance/me')
def my_attendance(u:User=Depends(current_user),db:Session=Depends(get_db)):
    if not is_staff(u):raise HTTPException(403,'Employee account required')
    q=select(Attendance).where(Attendance.organization_id==u.organization_id,
                               Attendance.user_id==u.id).order_by(Attendance.id.desc()).limit(120)
    return [attendance_record(x) for x in db.scalars(q).all()]

@router.get('/attendance')
def team_attendance(u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager')
    q=select(Attendance).where(Attendance.organization_id==u.organization_id).order_by(Attendance.id.desc()).limit(500)
    return [attendance_record(x) for x in db.scalars(q).all()]

@router.post('/attendance/clock-in')
def clock_in(u:User=Depends(current_user),db:Session=Depends(get_db)):
    if not is_staff(u):raise HTTPException(403,'Employee account required')
    open_shift=db.scalar(select(Attendance).where(Attendance.organization_id==u.organization_id,
                 Attendance.user_id==u.id,Attendance.clock_out.is_(None)).order_by(Attendance.id.desc()).limit(1).with_for_update())
    if open_shift:raise HTTPException(409,'You must clock out of the previous shift first')
    a=Attendance(organization_id=u.organization_id,user_id=u.id,clock_in=now(),approval_status='pending')
    db.add(a);db.flush();audit(db,u,'clock_in','attendance',a.id)
    people=db.scalars(select(User).where(User.organization_id==u.organization_id,User.active.is_(True))).all()
    for person in people:
        if person.id!=u.id and set(person.roles or []).intersection({'owner','manager'}):
            db.add(Notification(organization_id=u.organization_id,recipient_id=person.id,
                                message=f'{u.name} checked in. Attendance #{a.id} is pending approval.'))
    commit(db)
    return attendance_record(a)

@router.post('/attendance/clock-out')
def clock_out(payload:ClockOutInput|None=None,u:User=Depends(current_user),db:Session=Depends(get_db)):
    if not is_staff(u):raise HTTPException(403,'Employee account required')
    a=db.scalar(select(Attendance).where(Attendance.organization_id==u.organization_id,
                 Attendance.user_id==u.id,Attendance.clock_out.is_(None)).order_by(Attendance.id.desc()).limit(1).with_for_update())
    if not a:raise HTTPException(409,'No active clock-in to close')
    moment=now()
    elapsed=max(0,int((moment-as_utc(a.clock_in)).total_seconds()//60))
    breaks=payload.unpaid_break_minutes if payload else 0
    if breaks>elapsed:raise HTTPException(422,'Unpaid break cannot exceed the shift duration')
    a.clock_out=moment;a.unpaid_break_minutes=breaks
    audit(db,u,'clock_out','attendance',a.id,unpaid_break_minutes=breaks);commit(db)
    return attendance_record(a)

@router.post('/attendance/{attendance_id}/decision')
def attendance_decision(attendance_id:int,payload:AttendanceDecision,u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager')
    a=db.scalar(select(Attendance).where(Attendance.id==attendance_id,
                      Attendance.organization_id==u.organization_id).with_for_update())
    if not a:raise HTTPException(404,'Attendance record not found')
    if a.approval_status!='pending':raise HTTPException(409,'Attendance has already been reviewed')
    if a.user_id==u.id and 'owner' not in (u.roles or []):raise HTTPException(403,'Managers cannot approve their own attendance')
    if payload.decision=='reject' and not payload.note.strip():
        raise HTTPException(422,'A rejection reason is required')
    a.approval_status='approved' if payload.decision=='approve' else 'rejected'
    a.decision_by=u.id;a.decision_at=now();a.decision_note=payload.note.strip()
    audit(db,u,'attendance_'+a.approval_status,'attendance',a.id,worker_id=a.user_id,note=a.decision_note)
    db.add(Notification(organization_id=u.organization_id,recipient_id=a.user_id,
                        message=f'Your attendance #{a.id} was {a.approval_status} by {u.name}.'))
    commit(db)
    return attendance_record(a)

@router.get('/attendance/summary')
def attendance_summary(start_date:str|None=None,end_date:str|None=None,
                       u:User=Depends(current_user),db:Session=Depends(get_db)):
    permit(u,'manager')
    today=now().astimezone(HARARE).date()
    try:
        first=date.fromisoformat(start_date) if start_date else today.replace(day=1)
        last=date.fromisoformat(end_date) if end_date else today
    except ValueError:raise HTTPException(422,'Use YYYY-MM-DD for start_date and end_date')
    if last<first or (last-first).days>92:raise HTTPException(422,'Date range must be 1 to 93 days')
    items=db.scalars(select(Attendance).where(Attendance.organization_id==u.organization_id)
                     .order_by(Attendance.id.desc()).limit(10000)).all()
    filtered=[a for a in items if first<=as_utc(a.clock_in).astimezone(HARARE).date()<=last]
    daily={};staff={};pending=0;rejected=0
    for a in filtered:
        if a.approval_status=='pending':pending+=1
        if a.approval_status=='rejected':rejected+=1
        if a.approval_status!='approved' or not a.clock_out:continue
        minutes=attendance_record(a)['payable_minutes']
        key=(a.user_id,as_utc(a.clock_in).astimezone(HARARE).date().isoformat())
        daily[key]=daily.get(key,0)+minutes
        staff[a.user_id]=staff.get(a.user_id,0)+minutes
    target_env=os.getenv('PASH_STANDARD_DAILY_MINUTES','').strip()
    daily_target=int(target_env) if target_env.isdigit() and 1<=int(target_env)<=1440 else None
    overtime=sum(max(0,minutes-daily_target) for minutes in daily.values()) if daily_target is not None else None
    return {'start_date':first.isoformat(),'end_date':last.isoformat(),
            'approved_paid_minutes':sum(staff.values()),
            'overtime_minutes':overtime,'standard_daily_minutes':daily_target,
            'pending_count':pending,'rejected_count':rejected,
            'by_staff':[{'user_id':uid,'payable_minutes':minutes} for uid,minutes in sorted(staff.items())],
            'by_day':[{'user_id':uid,'date':day,'payable_minutes':minutes}
                      for (uid,day),minutes in sorted(daily.items())]}
