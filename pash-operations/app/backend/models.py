from datetime import datetime, timezone
from sqlalchemy import Column, Integer, String, Boolean, ForeignKey, DateTime, Numeric, JSON, Text, UniqueConstraint, LargeBinary
from sqlalchemy.orm import declarative_base

Base = declarative_base()
def now(): return datetime.now(timezone.utc)

class Organization(Base):
    __tablename__ = 'organizations'
    id = Column(Integer, primary_key=True)
    name = Column(String(140), nullable=False)
    created_at = Column(DateTime(timezone=True), default=now, nullable=False)

class User(Base):
    __tablename__ = 'users'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    name = Column(String(120), nullable=False)
    email = Column(String(200), nullable=False)
    password_hash = Column(String(250), nullable=False)
    roles = Column(JSON, nullable=False, default=list)
    active = Column(Boolean, nullable=False, default=True)
    token_version = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), default=now, nullable=False)
    __table_args__ = (UniqueConstraint('organization_id', 'email', name='uq_org_email'),)

class Customer(Base):
    __tablename__ = 'customers'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=True, unique=True)
    name = Column(String(150), nullable=False)
    phone = Column(String(35), default='')
    email = Column(String(200), default='')
    fleet_company = Column(String(150), default='')
    created_at = Column(DateTime(timezone=True), default=now, nullable=False)

class Vehicle(Base):
    __tablename__ = 'vehicles'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    customer_id = Column(Integer, ForeignKey('customers.id'), nullable=False)
    registration = Column(String(30), nullable=False)
    make = Column(String(80), nullable=False)
    model = Column(String(80), nullable=False)
    year = Column(Integer, nullable=True)
    vin = Column(String(40), default='')
    transmission = Column(String(60), default='')
    mileage = Column(Integer, nullable=True)
    __table_args__ = (UniqueConstraint('organization_id', 'registration', name='uq_org_registration'),)

class Booking(Base):
    __tablename__ = 'bookings'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    customer_id = Column(Integer, ForeignKey('customers.id'), nullable=False)
    vehicle_id = Column(Integer, ForeignKey('vehicles.id'), nullable=False)
    service = Column(String(100), nullable=False)
    scheduled_at = Column(DateTime(timezone=True), nullable=False)
    status = Column(String(25), nullable=False, default='requested')
    notes = Column(Text, default='')

class Job(Base):
    __tablename__ = 'jobs'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    vehicle_id = Column(Integer, ForeignKey('vehicles.id'), nullable=False)
    category = Column(String(30), nullable=False, default='mechanical')
    complaint = Column(Text, nullable=False)
    diagnosis = Column(Text, default='')
    assigned_to = Column(Integer, ForeignKey('users.id'), nullable=True)
    status = Column(String(40), nullable=False, default='received')
    opened_at = Column(DateTime(timezone=True), default=now, nullable=False)
    updated_at = Column(DateTime(timezone=True), default=now, onupdate=now, nullable=False)

class Inspection(Base):
    __tablename__ = 'inspections'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    job_id = Column(Integer, ForeignKey('jobs.id'), nullable=False)
    inspector_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    checklist = Column(JSON, nullable=False)
    notes = Column(Text, default='')
    created_at = Column(DateTime(timezone=True), default=now)

class GearboxReport(Base):
    __tablename__ = 'gearbox_reports'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    job_id = Column(Integer, ForeignKey('jobs.id'), nullable=False)
    transmission_code = Column(String(80), nullable=False)
    fault_codes = Column(JSON, default=list)
    components_replaced = Column(JSON, default=list)
    test_results = Column(Text, default='')
    technician_id = Column(Integer, ForeignKey('users.id'), nullable=False)

class BatteryReport(Base):
    __tablename__ = 'battery_reports'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    job_id = Column(Integer, ForeignKey('jobs.id'), nullable=False)
    chemistry = Column(String(60), nullable=False)
    battery_serial = Column(String(100), nullable=False)
    high_voltage = Column(Boolean, nullable=False, default=False)
    voltage = Column(Numeric(7, 3), nullable=True)
    health_percent = Column(Integer, nullable=True)
    notes = Column(Text, default='')
    technician_id = Column(Integer, ForeignKey('users.id'), nullable=False)

class Part(Base):
    __tablename__ = 'parts'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    sku = Column(String(80), nullable=False)
    name = Column(String(160), nullable=False)
    quantity = Column(Integer, nullable=False, default=0)
    reorder_level = Column(Integer, default=2)
    cost = Column(Numeric(12, 2), nullable=False, default=0)
    price = Column(Numeric(12, 2), nullable=False, default=0)
    __table_args__ = (UniqueConstraint('organization_id', 'sku', name='uq_org_sku'),)

class StockMovement(Base):
    __tablename__ = 'stock_movements'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    part_id = Column(Integer, ForeignKey('parts.id'), nullable=False)
    job_id = Column(Integer, ForeignKey('jobs.id'), nullable=True)
    actor_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    quantity_delta = Column(Integer, nullable=False)
    reason = Column(String(100), nullable=False)
    occurred_at = Column(DateTime(timezone=True), default=now)

class Quote(Base):
    __tablename__ = 'quotes'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    job_id = Column(Integer, ForeignKey('jobs.id'), nullable=False)
    items = Column(JSON, nullable=False)
    total = Column(Numeric(12, 2), nullable=False)
    status = Column(String(20), nullable=False, default='pending')
    decided_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), default=now)

class Invoice(Base):
    __tablename__ = 'invoices'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    quote_id = Column(Integer, ForeignKey('quotes.id'), nullable=False, unique=True)
    total = Column(Numeric(12, 2), nullable=False)
    paid = Column(Numeric(12, 2), nullable=False, default=0)
    created_at = Column(DateTime(timezone=True), default=now)

class Payment(Base):
    __tablename__ = 'payments'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    invoice_id = Column(Integer, ForeignKey('invoices.id'), nullable=False)
    actor_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    amount = Column(Numeric(12, 2), nullable=False)
    method = Column(String(30), nullable=False)
    created_at = Column(DateTime(timezone=True), default=now)

class Course(Base):
    __tablename__ = 'courses'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    title = Column(String(150), nullable=False)
    description = Column(Text, default='')
    price = Column(Numeric(12, 2), nullable=False, default=0)
    published = Column(Boolean, nullable=False, default=False)

class Enrollment(Base):
    __tablename__ = 'enrollments'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    student_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    course_id = Column(Integer, ForeignKey('courses.id'), nullable=False)
    status = Column(String(20), default='enrolled')
    progress = Column(Integer, nullable=False, default=0)
    __table_args__ = (UniqueConstraint('student_id', 'course_id', name='uq_student_course'),)

class AuditEvent(Base):
    __tablename__ = 'audit_events'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    actor_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    action = Column(String(80), nullable=False)
    entity = Column(String(60), nullable=False)
    entity_id = Column(Integer, nullable=False)
    data = Column(JSON, default=dict)
    created_at = Column(DateTime(timezone=True), default=now)

# Expansion modules (v0.2.0). Every business row carries an explicit organization scope.
class Supplier(Base):
    __tablename__ = 'suppliers'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    name = Column(String(160), nullable=False)
    phone = Column(String(40), default='')
    email = Column(String(200), default='')
    notes = Column(Text, default='')

class PurchaseOrder(Base):
    __tablename__ = 'purchase_orders'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    supplier_id = Column(Integer, ForeignKey('suppliers.id'), nullable=False)
    lines = Column(JSON, nullable=False)
    total = Column(Numeric(12, 2), nullable=False)
    status = Column(String(25), nullable=False, default='draft')
    created_by = Column(Integer, ForeignKey('users.id'), nullable=False)
    created_at = Column(DateTime(timezone=True), default=now, nullable=False)
    received_at = Column(DateTime(timezone=True), nullable=True)

class Equipment(Base):
    __tablename__ = 'equipment'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    name = Column(String(160), nullable=False)
    serial = Column(String(110), nullable=False)
    category = Column(String(90), nullable=False)
    status = Column(String(30), nullable=False, default='available')
    location = Column(String(120), default='')
    calibration_due = Column(DateTime(timezone=True), nullable=True)
    __table_args__ = (UniqueConstraint('organization_id', 'serial', name='uq_org_equipment_serial'),)

class WorkLog(Base):
    __tablename__ = 'work_logs'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    job_id = Column(Integer, ForeignKey('jobs.id'), nullable=False)
    technician_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    minutes = Column(Integer, nullable=False)
    description = Column(Text, nullable=False)
    logged_at = Column(DateTime(timezone=True), default=now, nullable=False)

class Expense(Base):
    __tablename__ = 'expenses'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    category = Column(String(70), nullable=False)
    description = Column(Text, nullable=False)
    amount = Column(Numeric(12, 2), nullable=False)
    currency = Column(String(5), nullable=False, default='USD')
    recorded_by = Column(Integer, ForeignKey('users.id'), nullable=False)
    occurred_at = Column(DateTime(timezone=True), default=now, nullable=False)

class Warranty(Base):
    __tablename__ = 'warranties'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    job_id = Column(Integer, ForeignKey('jobs.id'), nullable=False)
    coverage = Column(Text, nullable=False)
    starts_at = Column(DateTime(timezone=True), default=now, nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    mileage_limit = Column(Integer, nullable=True)
    status = Column(String(25), nullable=False, default='active')

class WarrantyClaim(Base):
    __tablename__ = 'warranty_claims'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    warranty_id = Column(Integer, ForeignKey('warranties.id'), nullable=False)
    customer_id = Column(Integer, ForeignKey('customers.id'), nullable=False)
    description = Column(Text, nullable=False)
    status = Column(String(25), nullable=False, default='submitted')
    resolution = Column(Text, default='')
    created_at = Column(DateTime(timezone=True), default=now, nullable=False)

class Fleet(Base):
    __tablename__ = 'fleets'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    customer_id = Column(Integer, ForeignKey('customers.id'), nullable=False)
    name = Column(String(160), nullable=False)
    contact = Column(String(120), default='')

class FleetVehicle(Base):
    __tablename__ = 'fleet_vehicles'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    fleet_id = Column(Integer, ForeignKey('fleets.id'), nullable=False)
    vehicle_id = Column(Integer, ForeignKey('vehicles.id'), nullable=False)
    __table_args__ = (UniqueConstraint('organization_id', 'vehicle_id', name='uq_org_fleet_vehicle'),)

class CourseLesson(Base):
    __tablename__ = 'course_lessons'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    course_id = Column(Integer, ForeignKey('courses.id'), nullable=False)
    title = Column(String(180), nullable=False)
    body = Column(Text, nullable=False)
    position = Column(Integer, nullable=False, default=1)
    published = Column(Boolean, nullable=False, default=False)

class AcademyAssessment(Base):
    __tablename__ = 'academy_assessments'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    course_id = Column(Integer, ForeignKey('courses.id'), nullable=False)
    title = Column(String(180), nullable=False)
    questions = Column(JSON, nullable=False) # private: [{prompt, choices: [...], answer: 0-based index}]
    passing_percent = Column(Integer, nullable=False, default=70)
    published = Column(Boolean, nullable=False, default=False)

class AssessmentAttempt(Base):
    __tablename__ = 'assessment_attempts'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    assessment_id = Column(Integer, ForeignKey('academy_assessments.id'), nullable=False)
    student_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    answers = Column(JSON, nullable=False)
    score = Column(Integer, nullable=False)
    passed = Column(Boolean, nullable=False)
    attempted_at = Column(DateTime(timezone=True), default=now, nullable=False)

class Certificate(Base):
    __tablename__ = 'certificates'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    student_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    course_id = Column(Integer, ForeignKey('courses.id'), nullable=False)
    verification_code = Column(String(90), nullable=False, unique=True)
    issued_by = Column(Integer, ForeignKey('users.id'), nullable=False)
    issued_at = Column(DateTime(timezone=True), default=now, nullable=False)
    revoked = Column(Boolean, nullable=False, default=False)
    __table_args__ = (UniqueConstraint('organization_id', 'student_id', 'course_id', name='uq_cert_student_course'),)

class ServiceReview(Base):
    __tablename__ = 'service_reviews'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    customer_id = Column(Integer, ForeignKey('customers.id'), nullable=False)
    job_id = Column(Integer, ForeignKey('jobs.id'), nullable=False)
    rating = Column(Integer, nullable=False)
    comment = Column(Text, default='')
    created_at = Column(DateTime(timezone=True), default=now, nullable=False)
    __table_args__ = (UniqueConstraint('organization_id','customer_id','job_id', name='uq_customer_job_review'),)

class StaffQualification(Base):
    __tablename__ = 'staff_qualifications'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    qualification = Column(String(140), nullable=False)
    high_voltage_approved = Column(Boolean, nullable=False, default=False)
    expires_at = Column(DateTime(timezone=True), nullable=True)
    verified_by = Column(Integer, ForeignKey('users.id'), nullable=False)

class Notification(Base):
    __tablename__ = 'notifications'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    recipient_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    message = Column(Text, nullable=False)
    read = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime(timezone=True), default=now, nullable=False)

class HVSafetyPermit(Base):
    __tablename__ = 'hv_safety_permits'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    job_id = Column(Integer, ForeignKey('jobs.id'), nullable=False)
    technician_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    authorized_by = Column(Integer, ForeignKey('users.id'), nullable=False)
    checklist = Column(JSON, nullable=False)
    created_at = Column(DateTime(timezone=True), default=now, nullable=False)
    __table_args__ = (UniqueConstraint('organization_id','job_id','technician_id', name='uq_hv_job_tech'),)

class LoginAttempt(Base):
    __tablename__ = 'login_attempts'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    email = Column(String(200), nullable=False)
    failed_count = Column(Integer, nullable=False, default=0)
    blocked_until = Column(DateTime(timezone=True), nullable=True)
    __table_args__ = (UniqueConstraint('organization_id','email', name='uq_org_login_email'),)

class Attendance(Base):
    __tablename__='attendance'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False, index=True)
    clock_in = Column(DateTime(timezone=True), nullable=False, default=now)
    clock_out = Column(DateTime(timezone=True), nullable=True)


class JobPhoto(Base):
    """Small authenticated workshop evidence images; future object storage can replace blob."""
    __tablename__ = 'job_photos'
    id = Column(Integer, primary_key=True)
    organization_id = Column(Integer, ForeignKey('organizations.id'), nullable=False, index=True)
    job_id = Column(Integer, ForeignKey('jobs.id'), nullable=False, index=True)
    uploaded_by = Column(Integer, ForeignKey('users.id'), nullable=False)
    kind = Column(String(25), nullable=False)
    content_type = Column(String(30), nullable=False)
    sha256 = Column(String(64), nullable=False)
    byte_size = Column(Integer, nullable=False)
    content = Column(LargeBinary, nullable=False)
    created_at = Column(DateTime(timezone=True), default=now, nullable=False)
