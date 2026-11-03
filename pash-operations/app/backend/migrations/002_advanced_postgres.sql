-- PASH Auto Operations v0.2 additive PostgreSQL migration. Apply after 001 on a BACKED-UP, approved environment.
-- NEVER run against the WhatsApp chatbot, Dexter, or any unrelated database.

ALTER TABLE battery_reports ADD COLUMN IF NOT EXISTS high_voltage BOOLEAN NOT NULL DEFAULT FALSE;


CREATE TABLE IF NOT EXISTS equipment (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	name VARCHAR(160) NOT NULL, 
	serial VARCHAR(110) NOT NULL, 
	category VARCHAR(90) NOT NULL, 
	status VARCHAR(30) NOT NULL, 
	location VARCHAR(120), 
	calibration_due TIMESTAMP WITH TIME ZONE, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_org_equipment_serial UNIQUE (organization_id, serial), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id)
)

;

CREATE INDEX IF NOT EXISTS ix_equipment_organization_id ON equipment (organization_id);


CREATE TABLE IF NOT EXISTS login_attempts (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	email VARCHAR(200) NOT NULL, 
	failed_count INTEGER NOT NULL, 
	blocked_until TIMESTAMP WITH TIME ZONE, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_org_login_email UNIQUE (organization_id, email), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id)
)

;

CREATE INDEX IF NOT EXISTS ix_login_attempts_organization_id ON login_attempts (organization_id);


CREATE TABLE IF NOT EXISTS suppliers (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	name VARCHAR(160) NOT NULL, 
	phone VARCHAR(40), 
	email VARCHAR(200), 
	notes TEXT, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id)
)

;

CREATE INDEX IF NOT EXISTS ix_suppliers_organization_id ON suppliers (organization_id);


CREATE TABLE IF NOT EXISTS academy_assessments (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	course_id INTEGER NOT NULL, 
	title VARCHAR(180) NOT NULL, 
	questions JSON NOT NULL, 
	passing_percent INTEGER NOT NULL, 
	published BOOLEAN NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(course_id) REFERENCES courses (id)
)

;

CREATE INDEX IF NOT EXISTS ix_academy_assessments_organization_id ON academy_assessments (organization_id);


CREATE TABLE IF NOT EXISTS certificates (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	student_id INTEGER NOT NULL, 
	course_id INTEGER NOT NULL, 
	verification_code VARCHAR(90) NOT NULL, 
	issued_by INTEGER NOT NULL, 
	issued_at TIMESTAMP WITH TIME ZONE NOT NULL, 
	revoked BOOLEAN NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_cert_student_course UNIQUE (organization_id, student_id, course_id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(student_id) REFERENCES users (id), 
	FOREIGN KEY(course_id) REFERENCES courses (id), 
	UNIQUE (verification_code), 
	FOREIGN KEY(issued_by) REFERENCES users (id)
)

;

CREATE INDEX IF NOT EXISTS ix_certificates_organization_id ON certificates (organization_id);


CREATE TABLE IF NOT EXISTS course_lessons (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	course_id INTEGER NOT NULL, 
	title VARCHAR(180) NOT NULL, 
	body TEXT NOT NULL, 
	position INTEGER NOT NULL, 
	published BOOLEAN NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(course_id) REFERENCES courses (id)
)

;

CREATE INDEX IF NOT EXISTS ix_course_lessons_organization_id ON course_lessons (organization_id);


CREATE TABLE IF NOT EXISTS expenses (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	category VARCHAR(70) NOT NULL, 
	description TEXT NOT NULL, 
	amount NUMERIC(12, 2) NOT NULL, 
	currency VARCHAR(5) NOT NULL, 
	recorded_by INTEGER NOT NULL, 
	occurred_at TIMESTAMP WITH TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(recorded_by) REFERENCES users (id)
)

;

CREATE INDEX IF NOT EXISTS ix_expenses_organization_id ON expenses (organization_id);


CREATE TABLE IF NOT EXISTS notifications (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	recipient_id INTEGER NOT NULL, 
	message TEXT NOT NULL, 
	read BOOLEAN NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(recipient_id) REFERENCES users (id)
)

;

CREATE INDEX IF NOT EXISTS ix_notifications_organization_id ON notifications (organization_id);


CREATE TABLE IF NOT EXISTS purchase_orders (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	supplier_id INTEGER NOT NULL, 
	lines JSON NOT NULL, 
	total NUMERIC(12, 2) NOT NULL, 
	status VARCHAR(25) NOT NULL, 
	created_by INTEGER NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE NOT NULL, 
	received_at TIMESTAMP WITH TIME ZONE, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(supplier_id) REFERENCES suppliers (id), 
	FOREIGN KEY(created_by) REFERENCES users (id)
)

;

CREATE INDEX IF NOT EXISTS ix_purchase_orders_organization_id ON purchase_orders (organization_id);


CREATE TABLE IF NOT EXISTS staff_qualifications (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	user_id INTEGER NOT NULL, 
	qualification VARCHAR(140) NOT NULL, 
	high_voltage_approved BOOLEAN NOT NULL, 
	expires_at TIMESTAMP WITH TIME ZONE, 
	verified_by INTEGER NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(user_id) REFERENCES users (id), 
	FOREIGN KEY(verified_by) REFERENCES users (id)
)

;

CREATE INDEX IF NOT EXISTS ix_staff_qualifications_organization_id ON staff_qualifications (organization_id);


CREATE TABLE IF NOT EXISTS assessment_attempts (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	assessment_id INTEGER NOT NULL, 
	student_id INTEGER NOT NULL, 
	answers JSON NOT NULL, 
	score INTEGER NOT NULL, 
	passed BOOLEAN NOT NULL, 
	attempted_at TIMESTAMP WITH TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(assessment_id) REFERENCES academy_assessments (id), 
	FOREIGN KEY(student_id) REFERENCES users (id)
)

;

CREATE INDEX IF NOT EXISTS ix_assessment_attempts_organization_id ON assessment_attempts (organization_id);


CREATE TABLE IF NOT EXISTS fleets (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	customer_id INTEGER NOT NULL, 
	name VARCHAR(160) NOT NULL, 
	contact VARCHAR(120), 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(customer_id) REFERENCES customers (id)
)

;

CREATE INDEX IF NOT EXISTS ix_fleets_organization_id ON fleets (organization_id);


CREATE TABLE IF NOT EXISTS fleet_vehicles (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	fleet_id INTEGER NOT NULL, 
	vehicle_id INTEGER NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_org_fleet_vehicle UNIQUE (organization_id, vehicle_id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(fleet_id) REFERENCES fleets (id), 
	FOREIGN KEY(vehicle_id) REFERENCES vehicles (id)
)

;

CREATE INDEX IF NOT EXISTS ix_fleet_vehicles_organization_id ON fleet_vehicles (organization_id);


CREATE TABLE IF NOT EXISTS hv_safety_permits (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	job_id INTEGER NOT NULL, 
	technician_id INTEGER NOT NULL, 
	authorized_by INTEGER NOT NULL, 
	checklist JSON NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_hv_job_tech UNIQUE (organization_id, job_id, technician_id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(job_id) REFERENCES jobs (id), 
	FOREIGN KEY(technician_id) REFERENCES users (id), 
	FOREIGN KEY(authorized_by) REFERENCES users (id)
)

;

CREATE INDEX IF NOT EXISTS ix_hv_safety_permits_organization_id ON hv_safety_permits (organization_id);


CREATE TABLE IF NOT EXISTS service_reviews (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	customer_id INTEGER NOT NULL, 
	job_id INTEGER NOT NULL, 
	rating INTEGER NOT NULL, 
	comment TEXT, 
	created_at TIMESTAMP WITH TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_customer_job_review UNIQUE (organization_id, customer_id, job_id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(customer_id) REFERENCES customers (id), 
	FOREIGN KEY(job_id) REFERENCES jobs (id)
)

;

CREATE INDEX IF NOT EXISTS ix_service_reviews_organization_id ON service_reviews (organization_id);


CREATE TABLE IF NOT EXISTS warranties (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	job_id INTEGER NOT NULL, 
	coverage TEXT NOT NULL, 
	starts_at TIMESTAMP WITH TIME ZONE NOT NULL, 
	expires_at TIMESTAMP WITH TIME ZONE NOT NULL, 
	mileage_limit INTEGER, 
	status VARCHAR(25) NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(job_id) REFERENCES jobs (id)
)

;

CREATE INDEX IF NOT EXISTS ix_warranties_organization_id ON warranties (organization_id);


CREATE TABLE IF NOT EXISTS work_logs (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	job_id INTEGER NOT NULL, 
	technician_id INTEGER NOT NULL, 
	minutes INTEGER NOT NULL, 
	description TEXT NOT NULL, 
	logged_at TIMESTAMP WITH TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(job_id) REFERENCES jobs (id), 
	FOREIGN KEY(technician_id) REFERENCES users (id)
)

;

CREATE INDEX IF NOT EXISTS ix_work_logs_organization_id ON work_logs (organization_id);


CREATE TABLE IF NOT EXISTS warranty_claims (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	warranty_id INTEGER NOT NULL, 
	customer_id INTEGER NOT NULL, 
	description TEXT NOT NULL, 
	status VARCHAR(25) NOT NULL, 
	resolution TEXT, 
	created_at TIMESTAMP WITH TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(warranty_id) REFERENCES warranties (id), 
	FOREIGN KEY(customer_id) REFERENCES customers (id)
)

;

CREATE INDEX IF NOT EXISTS ix_warranty_claims_organization_id ON warranty_claims (organization_id);

