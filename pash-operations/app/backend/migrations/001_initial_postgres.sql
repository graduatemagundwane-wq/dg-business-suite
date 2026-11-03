-- PASH AUTO Operations v0.1 initial PostgreSQL schema. New, empty database only.


CREATE TABLE organizations (
	id SERIAL NOT NULL, 
	name VARCHAR(140) NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE NOT NULL, 
	PRIMARY KEY (id)
)

;


CREATE TABLE courses (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	title VARCHAR(150) NOT NULL, 
	description TEXT, 
	price NUMERIC(12, 2) NOT NULL, 
	published BOOLEAN NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id)
)

;


CREATE TABLE parts (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	sku VARCHAR(80) NOT NULL, 
	name VARCHAR(160) NOT NULL, 
	quantity INTEGER NOT NULL, 
	reorder_level INTEGER, 
	cost NUMERIC(12, 2) NOT NULL, 
	price NUMERIC(12, 2) NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_org_sku UNIQUE (organization_id, sku), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id)
)

;


CREATE TABLE users (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	name VARCHAR(120) NOT NULL, 
	email VARCHAR(200) NOT NULL, 
	password_hash VARCHAR(250) NOT NULL, 
	roles JSON NOT NULL, 
	active BOOLEAN NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_org_email UNIQUE (organization_id, email), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id)
)

;


CREATE TABLE audit_events (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	actor_id INTEGER NOT NULL, 
	action VARCHAR(80) NOT NULL, 
	entity VARCHAR(60) NOT NULL, 
	entity_id INTEGER NOT NULL, 
	data JSON, 
	created_at TIMESTAMP WITH TIME ZONE, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(actor_id) REFERENCES users (id)
)

;


CREATE TABLE customers (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	user_id INTEGER, 
	name VARCHAR(150) NOT NULL, 
	phone VARCHAR(35), 
	email VARCHAR(200), 
	fleet_company VARCHAR(150), 
	created_at TIMESTAMP WITH TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	UNIQUE (user_id), 
	FOREIGN KEY(user_id) REFERENCES users (id)
)

;


CREATE TABLE enrollments (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	student_id INTEGER NOT NULL, 
	course_id INTEGER NOT NULL, 
	status VARCHAR(20), 
	progress INTEGER NOT NULL, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_student_course UNIQUE (student_id, course_id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(student_id) REFERENCES users (id), 
	FOREIGN KEY(course_id) REFERENCES courses (id)
)

;


CREATE TABLE vehicles (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	customer_id INTEGER NOT NULL, 
	registration VARCHAR(30) NOT NULL, 
	make VARCHAR(80) NOT NULL, 
	model VARCHAR(80) NOT NULL, 
	year INTEGER, 
	vin VARCHAR(40), 
	transmission VARCHAR(60), 
	mileage INTEGER, 
	PRIMARY KEY (id), 
	CONSTRAINT uq_org_registration UNIQUE (organization_id, registration), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(customer_id) REFERENCES customers (id)
)

;


CREATE TABLE bookings (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	customer_id INTEGER NOT NULL, 
	vehicle_id INTEGER NOT NULL, 
	service VARCHAR(100) NOT NULL, 
	scheduled_at TIMESTAMP WITH TIME ZONE NOT NULL, 
	status VARCHAR(25) NOT NULL, 
	notes TEXT, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(customer_id) REFERENCES customers (id), 
	FOREIGN KEY(vehicle_id) REFERENCES vehicles (id)
)

;


CREATE TABLE jobs (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	vehicle_id INTEGER NOT NULL, 
	category VARCHAR(30) NOT NULL, 
	complaint TEXT NOT NULL, 
	diagnosis TEXT, 
	assigned_to INTEGER, 
	status VARCHAR(40) NOT NULL, 
	opened_at TIMESTAMP WITH TIME ZONE NOT NULL, 
	updated_at TIMESTAMP WITH TIME ZONE NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(vehicle_id) REFERENCES vehicles (id), 
	FOREIGN KEY(assigned_to) REFERENCES users (id)
)

;


CREATE TABLE battery_reports (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	job_id INTEGER NOT NULL, 
	chemistry VARCHAR(60) NOT NULL, 
	battery_serial VARCHAR(100) NOT NULL, 
	voltage NUMERIC(7, 3), 
	health_percent INTEGER, 
	notes TEXT, 
	technician_id INTEGER NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(job_id) REFERENCES jobs (id), 
	FOREIGN KEY(technician_id) REFERENCES users (id)
)

;


CREATE TABLE gearbox_reports (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	job_id INTEGER NOT NULL, 
	transmission_code VARCHAR(80) NOT NULL, 
	fault_codes JSON, 
	components_replaced JSON, 
	test_results TEXT, 
	technician_id INTEGER NOT NULL, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(job_id) REFERENCES jobs (id), 
	FOREIGN KEY(technician_id) REFERENCES users (id)
)

;


CREATE TABLE inspections (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	job_id INTEGER NOT NULL, 
	inspector_id INTEGER NOT NULL, 
	checklist JSON NOT NULL, 
	notes TEXT, 
	created_at TIMESTAMP WITH TIME ZONE, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(job_id) REFERENCES jobs (id), 
	FOREIGN KEY(inspector_id) REFERENCES users (id)
)

;


CREATE TABLE quotes (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	job_id INTEGER NOT NULL, 
	items JSON NOT NULL, 
	total NUMERIC(12, 2) NOT NULL, 
	status VARCHAR(20) NOT NULL, 
	decided_at TIMESTAMP WITH TIME ZONE, 
	created_at TIMESTAMP WITH TIME ZONE, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(job_id) REFERENCES jobs (id)
)

;


CREATE TABLE stock_movements (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	part_id INTEGER NOT NULL, 
	job_id INTEGER, 
	actor_id INTEGER NOT NULL, 
	quantity_delta INTEGER NOT NULL, 
	reason VARCHAR(100) NOT NULL, 
	occurred_at TIMESTAMP WITH TIME ZONE, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(part_id) REFERENCES parts (id), 
	FOREIGN KEY(job_id) REFERENCES jobs (id), 
	FOREIGN KEY(actor_id) REFERENCES users (id)
)

;


CREATE TABLE invoices (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	quote_id INTEGER NOT NULL, 
	total NUMERIC(12, 2) NOT NULL, 
	paid NUMERIC(12, 2) NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	UNIQUE (quote_id), 
	FOREIGN KEY(quote_id) REFERENCES quotes (id)
)

;


CREATE TABLE payments (
	id SERIAL NOT NULL, 
	organization_id INTEGER NOT NULL, 
	invoice_id INTEGER NOT NULL, 
	actor_id INTEGER NOT NULL, 
	amount NUMERIC(12, 2) NOT NULL, 
	method VARCHAR(30) NOT NULL, 
	created_at TIMESTAMP WITH TIME ZONE, 
	PRIMARY KEY (id), 
	FOREIGN KEY(organization_id) REFERENCES organizations (id), 
	FOREIGN KEY(invoice_id) REFERENCES invoices (id), 
	FOREIGN KEY(actor_id) REFERENCES users (id)
)

;

CREATE INDEX ix_courses_organization_id ON courses (organization_id);

CREATE INDEX ix_parts_organization_id ON parts (organization_id);

CREATE INDEX ix_users_organization_id ON users (organization_id);

CREATE INDEX ix_audit_events_organization_id ON audit_events (organization_id);

CREATE INDEX ix_customers_organization_id ON customers (organization_id);

CREATE INDEX ix_enrollments_organization_id ON enrollments (organization_id);

CREATE INDEX ix_vehicles_organization_id ON vehicles (organization_id);

CREATE INDEX ix_bookings_organization_id ON bookings (organization_id);

CREATE INDEX ix_jobs_organization_id ON jobs (organization_id);

CREATE INDEX ix_battery_reports_organization_id ON battery_reports (organization_id);

CREATE INDEX ix_gearbox_reports_organization_id ON gearbox_reports (organization_id);

CREATE INDEX ix_inspections_organization_id ON inspections (organization_id);

CREATE INDEX ix_quotes_organization_id ON quotes (organization_id);

CREATE INDEX ix_stock_movements_organization_id ON stock_movements (organization_id);

CREATE INDEX ix_invoices_organization_id ON invoices (organization_id);

CREATE INDEX ix_payments_organization_id ON payments (organization_id);
