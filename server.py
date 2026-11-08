#!/usr/bin/env python3
"""IrvinAero Aviation pilot platform: stdlib Python HTTP + SQLite, no external web dependencies.
This is a local/staging application, NOT a certified aviation system or live payment gateway.
"""
import os, json, sqlite3, time, re, uuid, hashlib, hmac, secrets, mimetypes, base64, io, urllib.parse, threading
from datetime import datetime, timezone
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path

BASE=Path(__file__).resolve().parent
DB=Path(os.environ.get('IRVINAERO_DB',str(BASE/'irvinaero.sqlite3')))
DB.parent.mkdir(parents=True,exist_ok=True)
STATIC=BASE/'static'; UPLOADS=Path(os.environ.get('IRVINAERO_UPLOADS',str(BASE/'uploads')))
UPLOADS.mkdir(parents=True,exist_ok=True)
HOST=os.environ.get('HOST','127.0.0.1'); PORT=int(os.environ.get('PORT','8765'))
DEMO=os.environ.get('IRVINAERO_DEMO','1') == '1'
SESSION_TTL=8*3600
lock=threading.RLock()
KINDS={'courses','lessons','assignments','questions','exams','submissions','classes','attendance','flights','payments','certificates','messages','tickets','applications','documents','notifications','intakes','aircraft','maintenance','staff','seminars','bookings','support','announcements','grades','settings','notes','competencies','refunds','expenses','resources','invoices','reports','audit','users','reviews'}
PUBLIC_KINDS={'courses','seminars','intakes','aircraft'}
STUDENT_WRITE={'applications','tickets','bookings','submissions','messages','support','documents','notes','payments','attendance','reviews'}
INSTRUCTOR_WRITE={'lessons','assignments','questions','exams','submissions','classes','attendance','flights','grades','resources','messages','competencies','notes','reviews'}|STUDENT_WRITE
FINANCE_WRITE={'payments','refunds','invoices','expenses','reports','messages'}|STUDENT_WRITE
STAFF_ROLES={'admin','ceo','instructor','finance','admissions'}

def dbconn():
 c=sqlite3.connect(str(DB),timeout=20,check_same_thread=False)
 c.row_factory=sqlite3.Row;c.execute('PRAGMA journal_mode=WAL');c.execute('PRAGMA busy_timeout=10000');return c

def now(): return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
def uid(): return uuid.uuid4().hex[:12]
def pw_hash(p,salt=None):
 salt=salt or secrets.token_hex(16)
 key=hashlib.pbkdf2_hmac('sha256',p.encode(),bytes.fromhex(salt),260_000)
 return salt+':'+key.hex()
def check_pw(p,stored):
 try: s,v=stored.split(':');return hmac.compare_digest(pw_hash(p,s),stored)
 except: return False

def init():
 with dbconn() as c:
  c.executescript('''CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY, name TEXT NOT NULL, email TEXT UNIQUE NOT NULL, passhash TEXT NOT NULL, role TEXT NOT NULL, created TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY,user_id TEXT NOT NULL,expires INTEGER NOT NULL);
  CREATE TABLE IF NOT EXISTS records(id TEXT PRIMARY KEY, kind TEXT NOT NULL,title TEXT NOT NULL, owner TEXT, data TEXT NOT NULL,created TEXT NOT NULL,updated TEXT NOT NULL);
  CREATE INDEX IF NOT EXISTS rec_kind ON records(kind);CREATE INDEX IF NOT EXISTS rec_owner ON records(owner);
  CREATE TABLE IF NOT EXISTS actions(id TEXT PRIMARY KEY,actor TEXT,action TEXT,entity TEXT,details TEXT,created TEXT NOT NULL);
  CREATE TABLE IF NOT EXISTS uploads(id TEXT PRIMARY KEY,owner TEXT,name TEXT,mime TEXT,path TEXT,size INTEGER,created TEXT NOT NULL);''')
  count=c.execute('SELECT count(*) n FROM users').fetchone()['n']
  if count==0:
   if DEMO:
    for role,name in [('admin','Academy Administrator'),('student','Demo Student'),('instructor','Captain Instructor'),('finance','Finance Officer'),('ceo','Academy Director'),('admissions','Admissions Officer')]:
     c.execute('INSERT INTO users VALUES(?,?,?,?,?,?)',(role,name,f'{role}@irvinaero.demo',pw_hash('Demo2026!'),role,now()))
   else:
    initial=os.environ.get('IRVINAERO_ADMIN_PASSWORD','')
    email=os.environ.get('IRVINAERO_ADMIN_EMAIL','')
    if len(initial)<16 or not re.fullmatch(r'[^@\s]+@[^@\s]+\.[^@\s]+',email):raise RuntimeError('Non-demo startup requires IRVINAERO_ADMIN_EMAIL and strong IRVINAERO_ADMIN_PASSWORD (16+ characters)')
    c.execute('INSERT INTO users VALUES(?,?,?,?,?,?)',('admin','Academy Administrator',email.lower(),pw_hash(initial),'admin',now()))
  count=c.execute('SELECT count(*) n FROM records').fetchone()['n']
  if count==0:
   def seed(kind,title,data,owner='admin'):
    c.execute('INSERT INTO records VALUES(?,?,?,?,?,?,?)',(uid(),kind,title,owner,json.dumps(data),now(),now()))
   programmes=[('Private Pilot Licence (PPL)','Pilot Training','Theory and flight training toward an eligible private pilot licence.'),('Commercial Pilot Licence (CPL)','Pilot Training','Advanced theory and practical commercial pilot training.'),('Night Rating','Ratings','Night flying training and assessment.'),('Instrument Rating','Ratings','Instrument and navigation training.'),('Flight Instructor Training','Pilot Training','Instructional training for qualified pilot candidates.'),('Cabin Crew Training','Cabin Crew','Cabin safety and passenger services programme.')]
   for n,cat,d in programmes: seed('courses',n,dict(category=cat,description=d,duration='Confirm with admissions',fee='Contact admissions',status='Published',syllabus='Air Law, Meteorology, Navigation, Aircraft Knowledge, Human Performance'))
   for i,(title,cat) in enumerate([('Air Law — Foundations','PPL'),('Meteorology — Weather Systems','PPL'),('Navigation — VFR Planning','PPL'),('Principles of Flight — Four Forces','PPL'),('Radio Communications','PPL'),('Human Performance','PPL'),('Aircraft General Knowledge','PPL')]):seed('lessons',title,dict(course='Private Pilot Licence (PPL)',module=cat,content=f'{title}: Study the official course material, consult your instructor, and complete the assessment.',duration='20 minutes',status='Published',order=i+1))
   seed('seminars','Pilot Training Seminar',dict(date='2026-12-12',time='09:00',venue='Dolphin House, 5th Floor, 123 Leopold Takawira Street, Harare',price='FREE',capacity=200,description='Career guidance, training pathways and questions with aviation instructors.',status='Open'))
   seed('intakes','PPL February Intake',dict(course='Private Pilot Licence (PPL)',start='2027-02-02',end='2027-04-30',capacity=60,status='Open'))
   seed('intakes','CPL April Intake',dict(course='Commercial Pilot Licence (CPL)',start='2027-04-05',end='2027-06-30',capacity=60,status='Upcoming'))
   seed('classes','Air Law — Theory',dict(course='Private Pilot Licence (PPL)',start='2026-12-09T09:00',end='2026-12-09T11:00',location='Room A1',instructor='Captain Instructor',status='Scheduled'))
   seed('classes','Meteorology — Live Class',dict(course='Private Pilot Licence (PPL)',start='2026-12-10T14:00',end='2026-12-10T16:00',location='Online',instructor='Captain Instructor',status='Scheduled'))
   for t in ['Z-KIA — Cessna 172','Z-KIB — Piper PA-28','Z-KIC — DA40'] : seed('aircraft',t,dict(status='Available',hours='0',nextInspection='2027-01-31',notes='Illustrative sample aircraft; replace with verified fleet data'))
   for t,options,correct in [('Which instrument indicates aircraft heading?',['Altimeter','Heading indicator','Airspeed indicator','VSI'],1),('Which control primarily controls yaw?',['Ailerons','Elevator','Rudder','Flaps'],2),('What is a key preflight check?',['Check fuel quantity','Skip weather briefing','Ignore documents','Omit walkaround'],0)]:seed('questions',t,dict(course='Private Pilot Licence (PPL)',options=options,correct=correct,points=1,explanation='Review the related lesson and instructor guidance.'))
   seed('assignments','Air Law — Case Study',dict(course='Private Pilot Licence (PPL)',due='2026-12-18',instructions='Review a hypothetical flight and discuss the relevant regulatory obligations.',status='Open'))
   seed('exams','PPL Practice Examination',dict(course='Private Pilot Licence (PPL)',minutes=20,passmark=70,status='Published'))
   seed('notifications','Welcome to IrvinAero Academy',dict(message='Explore courses, apply, and complete your training activities.',status='Published'))
   seed('maintenance','Scheduled 100-hour inspection',dict(aircraft='Z-KIA — Cessna 172',due='2027-01-31',status='Scheduled',notes='Illustrative record only'))
   seed('resources','PPL Study Guide',dict(course='Private Pilot Licence (PPL)',type='PDF',url='',notes='Upload approved training resources in administration'))
   if DEMO:
    seed('applications','Demo Student — Private Pilot Licence (PPL)',dict(name='Demo Student',email='student@irvinaero.demo',phone='0770 000 000',course='Private Pilot Licence (PPL)',status='Under Review',intake='February 2027',notes='Example application data, not a real applicant'),owner='student')
    seed('flights','DEMO — Dual General Handling',dict(date='2026-11-05',aircraft='Z-KIA — Cessna 172',instructor='Captain Instructor',dual='1.2',solo='0',route='Circuit training',status='Pending instructor review',remarks='Illustrative logbook entry'),owner='student')
    seed('flights','DEMO — Solo Circuit',dict(date='2026-11-06',aircraft='Z-KIA — Cessna 172',instructor='Captain Instructor',dual='0',solo='0.8',route='Supervised circuit exercise',status='Pending instructor review',remarks='Illustrative record; not regulator verified'),owner='student')
    seed('payments','DEMO — PPL Tuition Reference',dict(course='Private Pilot Licence (PPL)',amount='1200',method='EcoCash — manual verification',reference='DEMO-NOT-A-PAYMENT',status='Pending verification',notes='Illustrative reference only; no money collected'),owner='student')
    seed('invoices','DEMO — PPL Tuition Invoice',dict(student='Demo Student',course='Private Pilot Licence (PPL)',amount='1200',due='2027-02-02',status='Issued'),owner='student')
    seed('certificates','DEMO — Meteorology Theory Certificate',dict(student='Demo Student',course='PPL Meteorology Theory',completion='2026-11-02',type='Theory completion',status='Draft'),owner='student')
    seed('messages','Welcome from Academic Office',dict(recipient='Demo Student',message='Welcome to the IrvinAero staging academy. Your upcoming classes appear in the timetable.'),owner='student')
    seed('support','DEMO — Course Material Access',dict(category='Academics',message='Please confirm which materials are approved for study.',status='Open'),owner='student')
    seed('grades','DEMO — Air Law Practice Quiz',dict(score=2,total=3,percent=67,passed=False,assessmentType='quiz',status='Graded'),owner='student')
    seed('notes','DEMO — Meteorology note',dict(course='Private Pilot Licence (PPL)',lesson='Meteorology — Weather Systems',content='Review cloud types and METAR decoding.',completed='No'),owner='student')
    seed('attendance','DEMO — Air Law Attendance',dict(**{'class':'Air Law — Theory','student':'Demo Student','date':'2026-11-02','status':'Present'}),owner='student')
    seed('tickets','DEMO — Pilot Seminar Booking',dict(name='Demo Student',phone='+263770000000',email='student@irvinaero.demo',date='2026-12-12',status='Booked',verificationCode='DEMO123456'),owner='student')
    seed('bookings','DEMO — Introductory Flight Request',dict(name='Demo Student',phone='+263770000000',email='student@irvinaero.demo',preferredDate='2026-12-03',participants=1,status='Pending',verificationCode='DEMO654321'),owner='student')


def audit(actor, action,entity,details=''):
 with dbconn() as c:c.execute('INSERT INTO actions VALUES(?,?,?,?,?,?)',(uid(),actor,action,entity,str(details)[:1200],now()))

def user_sanitized(row):
 return dict(id=row['id'],name=row['name'],email=row['email'],role=row['role']) if row else None

def extract_session(cookie):
 token=None
 for part in (cookie or '').split(';'):
  if part.strip().startswith('irvin_session='):token=part.strip().split('=',1)[1];break
 if not token:return None
 with dbconn() as c:
  row=c.execute('SELECT u.* FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token=? AND s.expires>?',(token,int(time.time()))).fetchone()
 return user_sanitized(row)

def can_create(role,kind):
 if role in ('admin','ceo'):return True
 if role=='instructor':return kind in INSTRUCTOR_WRITE
 if role=='finance':return kind in FINANCE_WRITE
 if role=='admissions':return kind in {'applications','tickets','bookings','support','messages','documents','intakes','seminars','announcements','notifications'}
 if role=='student':return kind in STUDENT_WRITE
 return False

def can_read_record(user, row):
 kind=row['kind'];owner=row['owner']
 if kind in PUBLIC_KINDS:return True
 if user is None:return False
 if user['role'] in ('admin','ceo'):return True
 if user['role'] in ('finance','admissions') and kind in ('payments','invoices','refunds','applications','tickets','bookings','documents','support','users','audit'):return True
 if user['role']=='instructor' and kind in ('flights','assignments','submissions','questions','grades','exams','classes','attendance','lessons','resources','competencies','reviews'):return True
 if kind in ('lessons','classes','assignments','exams','questions','resources','announcements','notifications','intakes','aircraft','maintenance'):return True
 return owner==user['id']

class Handler(BaseHTTPRequestHandler):
 server_version='IrvinAero/0.1'
 def log_message(self,fmt,*args): pass
 def respond(self,status,data=None,ctype='application/json',headers=None):
  payload=json.dumps(data,ensure_ascii=False).encode('utf8') if ctype=='application/json' else data
  self.send_response(status);self.send_header('Content-Type',ctype);self.send_header('Content-Length',str(len(payload)))
  self.send_header('X-Content-Type-Options','nosniff');self.send_header('Referrer-Policy','same-origin')
  self.send_header('Cache-Control','no-store' if ctype=='application/json' else 'public, max-age=300')
  self.send_header('Content-Security-Policy',"default-src 'self'; img-src 'self' data:; script-src 'self'; style-src 'self' 'unsafe-inline'; object-src 'none'; frame-ancestors 'none'")
  for k,v in (headers or {}).items():self.send_header(k,v)
  self.end_headers();self.wfile.write(payload)
 def fail(self,code,msg):self.respond(code,{'error':msg})
 def jsonbody(self):
  n=int(self.headers.get('Content-Length','0'))
  if n>6_000_000:raise ValueError('Request too large (6 MB limit)')
  if n<1: return {}
  data=json.loads(self.rfile.read(n));
  if not isinstance(data,dict):raise ValueError('Expected JSON object')
  return data
 def auth(self):return extract_session(self.headers.get('Cookie',''))
 def need(self):
  u=self.auth()
  if u is None: self.fail(401,'Log in to continue')
  return u
 def do_GET(self):
  try:self.get()
  except Exception as e:self.fail(500,'Server error: '+str(e)[:160])
 def do_POST(self):
  try:self.post()
  except (ValueError,json.JSONDecodeError) as e:self.fail(400,str(e))
  except Exception as e:self.fail(500,'Server error: '+str(e)[:160])
 def do_PATCH(self):
  try:self.patch()
  except (ValueError,json.JSONDecodeError) as e:self.fail(400,str(e))
  except Exception as e:self.fail(500,'Server error: '+str(e)[:160])
 def do_DELETE(self):
  try:self.delete()
  except Exception as e:self.fail(500,'Server error: '+str(e)[:160])
 def get(self):
  parsed=urllib.parse.urlparse(self.path);path=parsed.path; query=urllib.parse.parse_qs(parsed.query)
  if path=='/api/me':return self.respond(200,{'user':self.auth(),'demo':DEMO,'paymentMode':'manual_approval','integrations':{'ecocash':'not_connected','sms':'not_connected','email':'not_connected','flight_regulator':'not_connected'}})
  if path=='/api/health':return self.respond(200,{'status':'ok','time':now(),'screens':64})
  if path in ('/api/public-ticket','/api/ticket-qr','/api/track'):
   rid=query.get('id',[''])[0];code=query.get('code',[''])[0]
   with dbconn() as c:row=c.execute('SELECT * FROM records WHERE id=?',(rid,)).fetchone()
   if not row or row['kind'] not in ('tickets','applications','bookings') or json.loads(row['data']).get('verificationCode')!=code:return self.fail(404,'Reference or verification code invalid')
   if path=='/api/ticket-qr':
    import qrcode
    out=io.BytesIO();qrcode.make('IRVINAERO|'+row['kind']+'|'+rid+'|'+code).save(out,format='PNG')
    return self.respond(200,out.getvalue(),'image/png')
   return self.respond(200,{'item':self.as_record(row)})
  if path=='/api/records':
   kind=query.get('kind',[''])[0];u=self.auth()
   if kind not in KINDS:return self.fail(400,'Invalid collection')
   with dbconn() as c:rows=c.execute('SELECT * FROM records WHERE kind=? ORDER BY created DESC LIMIT 800',(kind,)).fetchall()
   return self.respond(200,{'items':[self.safe_record(row,u) for row in rows if can_read_record(u,row)]})
  if path.startswith('/api/record/'):
   u=self.auth(); id=path.split('/')[-1]
   with dbconn() as c:row=c.execute('SELECT * FROM records WHERE id=?',(id,)).fetchone()
   if not row:return self.fail(404,'Record not found')
   if not can_read_record(u,row):return self.fail(403,'Not permitted')
   return self.respond(200,{'item':self.safe_record(row,u)})
  if path=='/api/questions':
   if not self.need():return
   with dbconn() as c:rows=c.execute('SELECT * FROM records WHERE kind=?',('questions',)).fetchall()
   return self.respond(200,{'items':[dict(id=r['id'],title=r['title'],options=json.loads(r['data']).get('options',[])) for r in rows]})
  if path=='/api/audit':
   u=self.need()
   if not u:return
   if u['role'] not in ('admin','ceo'):return self.fail(403,'Not permitted')
   with dbconn() as c:rows=c.execute('SELECT * FROM actions ORDER BY created DESC LIMIT 250').fetchall()
   return self.respond(200,{'items':[dict(r) for r in rows]})
  if path=='/api/overview':
   u=self.need()
   if not u:return
   if u['role'] not in STAFF_ROLES:return self.fail(403,'Staff access required')
   with dbconn() as c:
    records=c.execute("SELECT kind,data,created FROM records WHERE kind IN ('applications','payments','grades','flights','tickets','aircraft','courses','classes','certificates','refunds')").fetchall()
    students=c.execute("SELECT count(*) n FROM users WHERE role='student'").fetchone()['n']
   groups={k:[] for k in ('applications','payments','grades','flights','tickets','aircraft','courses','classes','certificates','refunds')}
   for row in records:
    groups[row['kind']].append(dict(json.loads(row['data']),_created=row['created']))
   paids=[x for x in groups['payments'] if x.get('status')=='Paid']
   pending=[x for x in groups['payments'] if x.get('status')=='Pending verification']
   graded=[x for x in groups['grades'] if x.get('percent') is not None]
   verified=[x for x in groups['flights'] if x.get('status')=='Verified']
   months={}
   for x in groups['applications']:
    key=x['_created'][:7];months[key]=months.get(key,0)+1
   result={'students':students,'applications':len(groups['applications']),'courses':len(groups['courses']),'classes':len(groups['classes']),'seminarBookings':len(groups['tickets']),'approvedApplications':sum(x.get('status')=='Approved' for x in groups['applications']),'paidRevenue':round(sum(float(x.get('amount') or 0) for x in paids),2),'pendingPayments':len(pending),'pendingAmount':round(sum(float(x.get('amount') or 0) for x in pending),2),'gradePassRate':round(100*sum(bool(x.get('passed')) for x in graded)/len(graded),1) if graded else 0,'gradedExams':len(graded),'verifiedFlightHours':round(sum(float(x.get('dual') or 0)+float(x.get('solo') or 0) for x in verified),1),'aircraftAvailable':sum(x.get('status')=='Available' for x in groups['aircraft']),'issuedCertificates':len(groups['certificates']),'refundRequests':len(groups['refunds']),'monthlyApplications':months}
   if u['role']=='instructor':
    for k in ('paidRevenue','pendingAmount','pendingPayments','refundRequests'):result[k]=None
   if u['role']=='admissions':
    for k in ('paidRevenue','pendingAmount','pendingPayments','refundRequests'):result[k]=None
   return self.respond(200,{'metrics':result})
  if path=='/api/backup':
   u=self.need()
   if not u:return
   if u['role'] not in ('admin','ceo'):return self.fail(403,'Admin required')
   import tempfile
   with tempfile.NamedTemporaryFile(suffix='.sqlite3',delete=False) as temporary:path_=temporary.name
   try:
    source=dbconn();dest=sqlite3.connect(path_)
    with dest:source.backup(dest)
    source.close();dest.close();payload=Path(path_).read_bytes()
   finally:Path(path_).unlink(missing_ok=True)
   audit(u['id'],'backup','database')
   return self.respond(200,payload,'application/octet-stream',{'Content-Disposition':'attachment; filename="irvinaero-backup.sqlite3"'})
  if path=='/api/students':
   u=self.need()
   if not u:return
   if u['role'] not in STAFF_ROLES:return self.fail(403,'Not permitted')
   with dbconn() as c:rows=c.execute("SELECT id,name,role FROM users WHERE role='student' ORDER BY created").fetchall()
   return self.respond(200,{'items':[dict(r) for r in rows]})
  if path=='/api/users':
   u=self.need()
   if not u:return
   if u['role'] not in ('admin','ceo'):return self.fail(403,'Not permitted')
   with dbconn() as c:rows=c.execute('SELECT * FROM users ORDER BY created').fetchall()
   return self.respond(200,{'items':[user_sanitized(r) for r in rows]})
  if path.startswith('/api/upload/'):
   u=self.need()
   if not u:return
   id=path.rsplit('/',1)[1]
   with dbconn() as c:row=c.execute('SELECT * FROM uploads WHERE id=?',(id,)).fetchone()
   if not row:return self.fail(404,'File not found')
   if u['role'] not in STAFF_ROLES and row['owner']!=u['id']:return self.fail(403,'Not permitted')
   file=Path(row['path']);return self.respond(200,file.read_bytes(),row['mime'] or 'application/octet-stream',{'Content-Disposition':'attachment; filename="'+re.sub(r'[^A-Za-z0-9._-]','_',row['name'])+'"'})
  if path.startswith('/api/document/'):
   u=self.need()
   if not u:return
   id=path.rsplit('/',1)[1]
   with dbconn() as c:row=c.execute('SELECT * FROM records WHERE id=?',(id,)).fetchone()
   if not row:return self.fail(404,'Record not found')
   if not can_read_record(u,row):return self.fail(403,'Not permitted')
   data=self.pdf(row,u);return self.respond(200,data,'application/pdf',{'Content-Disposition':'attachment; filename="irvinaero-'+row['kind']+'-'+id+'.pdf"'})
  if path=='/':path='/index.html'
  if path.startswith('/media/') or path in ('/index.html','/app.js','/style.css','/favicon.svg'):
   f=(STATIC/path.lstrip('/')).resolve()
   if not f.is_relative_to(STATIC.resolve()) or not f.is_file():return self.fail(404,'File not found')
   return self.respond(200,f.read_bytes(),mimetypes.guess_type(str(f))[0] or 'application/octet-stream')
  if path.startswith('/api/'):return self.fail(404,'Endpoint not found')
  f=STATIC/'index.html';return self.respond(200,f.read_bytes(),'text/html')
 def as_record(self,row):
  return dict(id=row['id'],kind=row['kind'],title=row['title'],owner=row['owner'],data=json.loads(row['data']),created=row['created'],updated=row['updated'])
 def safe_record(self,row,user):
  rec=self.as_record(row)
  if rec['kind']=='questions' and (user is None or user['role'] not in ('admin','ceo','instructor')):
   rec['data'].pop('correct',None);rec['data'].pop('explanation',None)
  return rec
 def post(self):
  path=urllib.parse.urlparse(self.path).path;body=self.jsonbody()
  if path=='/api/login':
   email=str(body.get('email','')).strip().lower();password=str(body.get('password',''))
   with dbconn() as c:
    r=c.execute('SELECT * FROM users WHERE email=?',(email,)).fetchone()
    if not r or not check_pw(password,r['passhash']):return self.fail(401,'Invalid email or password')
    token=secrets.token_urlsafe(40)
    c.execute('INSERT INTO sessions VALUES(?,?,?)',(token,r['id'],int(time.time())+SESSION_TTL))
   audit(r['id'],'login','session');return self.respond(200,{'user':user_sanitized(r)},headers={'Set-Cookie':f'irvin_session={token}; HttpOnly; SameSite=Lax; Path=/; Max-Age={SESSION_TTL}'})
  if path=='/api/logout':
   cookie=self.headers.get('Cookie','');token=None
   for p in cookie.split(';'):
    if p.strip().startswith('irvin_session='):token=p.strip().split('=',1)[1]
   if token:
    with dbconn() as c:c.execute('DELETE FROM sessions WHERE token=?',(token,))
   return self.respond(200,{'ok':True},headers={'Set-Cookie':'irvin_session=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0'})
  if path=='/api/register':
   name=str(body.get('name','')).strip();email=str(body.get('email','')).strip().lower();password=str(body.get('password',''))
   if len(name)<2 or not re.fullmatch(r'[^@\s]+@[^@\s]+\.[^@\s]+',email) or len(password)<10:return self.fail(400,'Enter your name, a valid email and a password of at least 10 characters')
   id=uid()
   try:
    with dbconn() as c:c.execute('INSERT INTO users VALUES(?,?,?,?,?,?)',(id,name,email,pw_hash(password),'student',now()))
   except sqlite3.IntegrityError:return self.fail(409,'Email already registered')
   audit(id,'register','users');return self.respond(201,{'ok':True,'message':'Account created. Sign in to continue.'})
  if path=='/api/profile':
   u=self.need()
   if not u:return
   name=str(body.get('name','')).strip();email=str(body.get('email','')).strip().lower()
   if len(name)<2 or not re.fullmatch(r'[^@\s]+@[^@\s]+\.[^@\s]+',email):return self.fail(400,'Invalid name or email')
   try:
    with dbconn() as c:c.execute('UPDATE users SET name=?,email=? WHERE id=?',(name,email,u['id']))
   except sqlite3.IntegrityError:return self.fail(409,'Email already in use')
   audit(u['id'],'profile_update','users:'+u['id'])
   return self.respond(200,{'ok':True})
  if path=='/api/users':
   u=self.need()
   if not u:return
   if u['role'] not in ('admin','ceo'):return self.fail(403,'Admin access required')
   name=str(body.get('name','')).strip();email=str(body.get('email','')).strip().lower();role_=str(body.get('role','')).strip()
   if len(name)<2 or not re.fullmatch(r'[^@\s]+@[^@\s]+\.[^@\s]+',email) or role_ not in ('student','instructor','finance','admissions','admin','ceo'):return self.fail(400,'Invalid user details')
   password=secrets.token_urlsafe(18)
   id=uid()
   try:
    with dbconn() as c:c.execute('INSERT INTO users VALUES(?,?,?,?,?,?)',(id,name,email,pw_hash(password),role_,now()))
   except sqlite3.IntegrityError:return self.fail(409,'Account already exists')
   audit(u['id'],'create_user','users:'+id,email)
   return self.respond(201,{'ok':True,'id':id,'temporaryPassword':password,'message':'Save temporary password securely and instruct user to change it on first sign-in.'})
  if path=='/api/users/role':
   u=self.need()
   if not u:return
   if u['role'] not in ('admin','ceo'):return self.fail(403,'Admin access required')
   target=str(body.get('id',''));role_=str(body.get('role',''))
   if role_ not in ('student','instructor','finance','admissions','admin','ceo'):return self.fail(400,'Invalid role')
   if target==u['id']:return self.fail(400,'Cannot change your own administrator role')
   with dbconn() as c:
    if not c.execute('SELECT 1 FROM users WHERE id=?',(target,)).fetchone():return self.fail(404,'User not found')
    c.execute('UPDATE users SET role=? WHERE id=?',(role_,target))
   audit(u['id'],'change_role','users:'+target,role_)
   return self.respond(200,{'ok':True})
  if path=='/api/users/reset':
   u=self.need()
   if not u:return
   if u['role'] not in ('admin','ceo'):return self.fail(403,'Admin access required')
   target=str(body.get('id',''))
   if target==u['id']:return self.fail(400,'Use account settings to change your own password')
   temporary=secrets.token_urlsafe(18)
   with dbconn() as c:
    if not c.execute('SELECT 1 FROM users WHERE id=?',(target,)).fetchone():return self.fail(404,'User not found')
    c.execute('UPDATE users SET passhash=? WHERE id=?',(pw_hash(temporary),target))
    c.execute('DELETE FROM sessions WHERE user_id=?',(target,))
   audit(u['id'],'reset_password','users:'+target)
   return self.respond(200,{'temporaryPassword':temporary})
  if path=='/api/password':
   u=self.need()
   if not u:return
   old=str(body.get('current',''));new=str(body.get('new',''))
   if len(new)<10:return self.fail(400,'New password must have at least 10 characters')
   with dbconn() as c:
    row=c.execute('SELECT passhash FROM users WHERE id=?',(u['id'],)).fetchone()
    if not check_pw(old,row['passhash']):return self.fail(403,'Current password incorrect')
    c.execute('UPDATE users SET passhash=? WHERE id=?',(pw_hash(new),u['id']))
   audit(u['id'],'change_password','account');return self.respond(200,{'ok':True})
  if path=='/api/forgot':
   return self.respond(200,{'message':'For this staging build, please contact an academy administrator for account recovery. Email/SMS reset delivery is not connected.'})
  if path=='/api/record':
   kind=str(body.get('kind',''));title=str(body.get('title','')).strip();data=body.get('data',{})
   if kind not in KINDS or not title or len(title)>250 or not isinstance(data,dict):return self.fail(400,'Invalid record')
   u=self.auth()
   if not u:
    if kind not in ('tickets','applications','bookings'):return self.fail(401,'Log in first')
    if not (data.get('name') and (data.get('email') or data.get('phone'))):return self.fail(400,'Name and contact information required')
   elif not can_create(u['role'],kind):return self.fail(403,'Not allowed for this role')
   if kind in ('tickets','bookings','applications') and (not u or u['role']=='student'):
    data['status']={'tickets':'Booked','bookings':'Pending','applications':'Submitted'}[kind]
   if kind in ('submissions','attendance') and (not u or u['role']=='student'):
    data['status']={'submissions':'Submitted','attendance':'Pending verification'}[kind]
    data.pop('score',None);data.pop('feedback',None)
   if kind=='payments':
    data['status']='Pending verification'
    if data.get('amount') is not None:
     try:
      if float(data['amount'])<0:return self.fail(400,'Amount cannot be negative')
     except:return self.fail(400,'Enter a valid amount')
   if kind=='certificates' and (not u or u['role'] not in ('admin','ceo')):return self.fail(403,'Certificate issuance requires admin approval')
   if kind=='flights' and (not u or u['role'] not in ('instructor','admin','ceo')):data['status']='Pending instructor review'
   if kind=='tickets':
    with dbconn() as c:
     conf=c.execute("SELECT data FROM records WHERE kind='seminars' ORDER BY created LIMIT 1").fetchone()
     limit_=int(json.loads(conf['data']).get('capacity',0)) if conf else 0
     active=c.execute("SELECT data FROM records WHERE kind='tickets'").fetchall()
     used=sum(json.loads(v['data']).get('status') not in ('Rejected','Cancelled') for v in active)
     if limit_ and used>=limit_:return self.fail(409,'Seminar registration is full. Contact admissions about a waiting list.')
   id=uid();owner=(u['id'] if u else None)
   if kind in ('tickets','bookings','applications'):
    data['verificationCode']=secrets.token_hex(5).upper()
   with dbconn() as c:c.execute('INSERT INTO records VALUES(?,?,?,?,?,?,?)',(id,kind,title,owner,json.dumps(data),now(),now()))
   audit(owner or 'public','create',kind+':'+id,title)
   return self.respond(201,{'id':id,'message':kind.capitalize()+' saved','item':dict(id=id,kind=kind,title=title,owner=owner,data=data)})
  if path=='/api/grade':
   u=self.need()
   if not u:return
   answers=body.get('answers',{});type_=body.get('type','quiz')
   if not isinstance(answers,dict):return self.fail(400,'Answers required')
   with dbconn() as c:rows=c.execute('SELECT * FROM records WHERE kind=? ORDER BY created LIMIT 30',('questions',)).fetchall()
   score=0;total=0
   for r in rows:
    d=json.loads(r['data']);total+=int(d.get('points',1));
    if str(answers.get(r['id'],'-1'))==str(d.get('correct',-2)):score+=int(d.get('points',1))
   percent=round(score/max(total,1)*100)
   rid=uid();data=dict(score=score,total=total,percent=percent,passed=percent>=70,assessmentType=type_,answers=answers,status='Graded')
   with dbconn() as c:c.execute('INSERT INTO records VALUES(?,?,?,?,?,?,?)',(rid,'grades',f'{type_.title()} result — {u["name"]}',u['id'],json.dumps(data),now(),now()))
   audit(u['id'],'grade','grades:'+rid,str(percent));return self.respond(200,{'result':data,'id':rid})
  if path=='/api/approval':
   u=self.need()
   if not u:return
   kind=body.get('kind');id=body.get('id');status=body.get('status')
   if kind not in KINDS or status not in ('Approved','Rejected','Completed','Verified','Present','Paid','Cancelled','Pending','Published','Signed-off'):return self.fail(400,'Invalid approval')
   if kind in ('payments','refunds','invoices') and u['role'] not in ('admin','ceo','finance'):return self.fail(403,'Finance approval required')
   if kind in ('applications','bookings','tickets') and u['role'] not in ('admin','ceo','admissions'):return self.fail(403,'Admissions approval required')
   if kind in ('flights','competencies','submissions','grades') and u['role'] not in ('admin','ceo','instructor'):return self.fail(403,'Instructor approval required')
   if u['role'] not in STAFF_ROLES:return self.fail(403,'Staff approval required')
   with dbconn() as c:
    row=c.execute('SELECT * FROM records WHERE id=? AND kind=?',(id,kind)).fetchone()
    if not row:return self.fail(404,'Record not found')
    data=json.loads(row['data']);data['status']=status;data['approvedBy']=u['id'];data['approvedAt']=now()
    c.execute('UPDATE records SET data=?,updated=? WHERE id=?',(json.dumps(data),now(),id))
   audit(u['id'],'approve:'+status,kind+':'+id);return self.respond(200,{'ok':True})
  if path=='/api/upload':
   u=self.need()
   if not u:return
   name=re.sub(r'[^\w. -]','_',str(body.get('name','file')))[:90]
   mime=str(body.get('mime','application/octet-stream'))[:100]
   raw=base64.b64decode(body.get('base64',''),validate=True)
   if len(raw)>3_000_000:return self.fail(413,'File exceeds 3MB limit')
   id=uid();f=UPLOADS/id;f.write_bytes(raw)
   with dbconn() as c:c.execute('INSERT INTO uploads VALUES(?,?,?,?,?,?,?)',(id,u['id'],name,mime,str(f),len(raw),now()))
   audit(u['id'],'upload','upload:'+id,name);return self.respond(201,{'id':id,'url':'/api/upload/'+id,'name':name})
  self.fail(404,'Endpoint not found')
 def patch(self):
  path=urllib.parse.urlparse(self.path).path
  if not path.startswith('/api/record/'):return self.fail(404,'Endpoint not found')
  u=self.need()
  if not u:return
  id=path.rsplit('/',1)[1];body=self.jsonbody()
  with dbconn() as c:
   row=c.execute('SELECT * FROM records WHERE id=?',(id,)).fetchone()
   if not row:return self.fail(404,'Record not found')
   if not (u['role'] in ('admin','ceo') or (can_create(u['role'],row['kind']) and (row['owner']==u['id'] or u['role'] in ('finance','admissions','instructor')))):return self.fail(403,'Not allowed to change this record')
   old=json.loads(row['data']);new=body.get('data',{})
   if not isinstance(new,dict):return self.fail(400,'Invalid data')
   if row['kind']=='payments' and u['role'] not in ('admin','ceo','finance') and any(k in new for k in ('status','amount','approvedBy')):return self.fail(403,'Only finance can verify payments')
   if row['kind'] in ('flights','submissions','attendance','competencies','grades') and u['role']=='student' and any(k in new for k in ('status','approvedBy','score','feedback','percent','passed')):return self.fail(403,'Instructor or staff review required')
   if row['kind'] in ('applications','tickets','bookings') and u['role']=='student' and any(k in new for k in ('status','approvedBy','verificationCode')):return self.fail(403,'Admissions review required')
   if row['kind']=='certificates' and u['role'] not in ('admin','ceo'):return self.fail(403,'Only administration can change certificates')
   old.update(new);title=str(body.get('title') or row['title'])[:250]
   c.execute('UPDATE records SET title=?,data=?,updated=? WHERE id=?',(title,json.dumps(old),now(),id))
  audit(u['id'],'update',row['kind']+':'+id,title);return self.respond(200,{'ok':True})
 def delete(self):
  path=urllib.parse.urlparse(self.path).path
  if not path.startswith('/api/record/'):return self.fail(404,'Endpoint not found')
  u=self.need()
  if not u:return
  id=path.rsplit('/',1)[1]
  with dbconn() as c:
   row=c.execute('SELECT * FROM records WHERE id=?',(id,)).fetchone()
   if not row:return self.fail(404,'Record not found')
   if not (u['role'] in ('admin','ceo') or (row['owner']==u['id'] and row['kind'] in ('notes','support','messages','documents','reviews'))):return self.fail(403,'Not permitted to delete')
   c.execute('DELETE FROM records WHERE id=?',(id,))
  audit(u['id'],'delete',row['kind']+':'+id);return self.respond(200,{'ok':True})
 def pdf(self,row,user):
  from reportlab.lib.pagesizes import A4,landscape
  from reportlab.pdfgen import canvas
  from reportlab.lib.colors import HexColor
  from reportlab.lib.utils import ImageReader
  import qrcode
  details=json.loads(row['data']);kind=row['kind'];is_cert=kind=='certificates'
  pagesize=landscape(A4) if is_cert else A4
  buffer=io.BytesIO();p=canvas.Canvas(buffer,pagesize=pagesize)
  w,h=pagesize;navy=HexColor('#071D3B');blue=HexColor('#0B61D5');gold=HexColor('#D9A232');mute=HexColor('#63768C')
  if is_cert:
   p.setFillColor(HexColor('#FBFCFE'));p.rect(0,0,w,h,fill=1,stroke=0)
   p.setStrokeColor(navy);p.setLineWidth(6);p.rect(25,25,w-50,h-50,stroke=1,fill=0)
   p.setStrokeColor(gold);p.setLineWidth(2);p.rect(36,36,w-72,h-72,stroke=1,fill=0)
   p.setFillColor(navy);p.setFont('Helvetica-Bold',26);p.drawCentredString(w/2,h-90,'IRVINAERO AVIATION')
   p.setFillColor(gold);p.setFont('Helvetica',13);p.drawCentredString(w/2,h-114,'ACADEMY CERTIFICATE')
   p.setFillColor(navy);p.setFont('Helvetica-Bold',28);p.drawCentredString(w/2,h-171,'Certificate of Completion')
   p.setFont('Helvetica',13);p.drawCentredString(w/2,h-207,'This certifies that')
   p.setFillColor(blue);p.setFont('Helvetica-Bold',31);p.drawCentredString(w/2,h-251,str(details.get('student') or row['title'])[:46])
   p.setFillColor(navy);p.setFont('Helvetica',13);p.drawCentredString(w/2,h-283,'has completed the following academy training:')
   p.setFont('Helvetica-Bold',19);p.drawCentredString(w/2,h-318,str(details.get('course') or 'Aviation Academy Training')[:65])
   p.setStrokeColor(gold);p.line(w/2-130,h-339,w/2+130,h-339)
   p.setFont('Helvetica',12);p.drawCentredString(w/2,h-365,'Completion date: '+str(details.get('completion') or now()[:10]))
   p.setFont('Helvetica-Bold',10);p.drawCentredString(w/2,h-398,'ACADEMY RECORD ONLY — NOT A PILOT LICENCE OR RATING')
   p.setFillColor(HexColor('#94A3B8'));p.setFont('Helvetica',11);p.drawCentredString(w/2,72,'Certificate reference: '+row['id'].upper()+'  ·  Status: '+str(details.get('status','Draft')))
   p.setFillColor(HexColor('#C1CAD6'));p.saveState();p.translate(w/2,h/2);p.rotate(27);p.setFont('Helvetica-Bold',52);p.drawCentredString(0,0,'STAGING EXAMPLE');p.restoreState()
  else:
   p.setFillColor(navy);p.rect(0,h-116,w,116,fill=1,stroke=0)
   p.setFillColor(HexColor('#FFFFFF'));p.setFont('Helvetica-Bold',23);p.drawString(45,h-59,'IRVINAERO AVIATION')
   p.setFont('Helvetica',11);p.drawString(47,h-84,'ACADEMY · TRAIN  /  LEARN  /  FLY')
   titles={'payments':'PAYMENT RECORD','invoices':'INVOICE / RECEIPT','applications':'APPLICATION RECORD','flights':'FLIGHT TRAINING RECORD','grades':'ASSESSMENT RESULT','tickets':'SEMINAR TICKET','documents':'DOCUMENT RECORD'}
   p.setFillColor(navy);p.setFont('Helvetica-Bold',19);p.drawString(45,h-157,titles.get(kind,kind.upper()+' RECORD'))
   p.setFillColor(blue);p.setFont('Helvetica-Bold',13);p.drawString(45,h-184,row['title'][:68])
   p.setStrokeColor(HexColor('#D9E4F0'));p.line(45,h-200,w-45,h-200)
   y=h-230
   for key,value in details.items():
    if y<100:p.showPage();y=h-65
    if key in ('answers','verificationCode'):continue
    p.setFillColor(mute);p.setFont('Helvetica-Bold',10);p.drawString(47,y,str(key).replace('_',' ').title()[:27])
    p.setFillColor(navy);p.setFont('Helvetica',10)
    text_value=str(value).replace('\n',' ')[:90]
    p.drawString(200,y,text_value);y-=25
   p.setFillColor(HexColor('#D0D7DF'));p.saveState();p.translate(w/2,h/2);p.rotate(27);p.setFont('Helvetica-Bold',46);p.drawCentredString(0,0,'STAGING EXAMPLE');p.restoreState()
   p.setFillColor(mute);p.setFont('Helvetica',9);p.drawString(45,68,'This is an academy staging record. Confirm validity with IrvinAero administration.')
  p.setFillColor(mute);p.setFont('Helvetica',9);p.drawString(45,48,'Document ID: '+row['id']+'  ·  Generated '+now())
  p.save();return buffer.getvalue()

if __name__=='__main__':
 init();print(f'IrvinAero local platform at http://{HOST}:{PORT} (demo={DEMO})',flush=True)
 ThreadingHTTPServer((HOST,PORT),Handler).serve_forever()