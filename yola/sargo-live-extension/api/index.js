'use strict';
// Preserves current Yola API by delegating all unchanged endpoints.
const original=require('./index-original');
const crypto=require('node:crypto');
const {Pool}=require('pg');
const pool=new Pool({connectionString:process.env.DG_MASTER_DATABASE_URL,max:3,connectionTimeoutMillis:6000,ssl:{rejectUnauthorized:true}});
const safe=(x,n=120)=>String(x??'').trim().slice(0,n);
const email=x=>String(x||'').trim().toLowerCase();
const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const ok=(res,code,data)=>{res.statusCode=code;res.setHeader('Content-Type','application/json; charset=utf-8');res.setHeader('Cache-Control','no-store');res.end(JSON.stringify(data))};
const fail=(res,code,message)=>ok(res,code,{error:message});
const active=x=>x&&x.status==='active'&&(!x.expires_at||new Date(x.expires_at)>new Date());
const queryPath=req=>{const u=new URL(req.url,'https://'+(req.headers.host||'yola-onboarding.vercel.app'));return u.pathname==='/api/index'&&u.searchParams.has('path')?'/api/'+u.searchParams.get('path'):u.pathname};
async function body(req){if(req.body&&typeof req.body==='object'&&!Array.isArray(req.body))return req.body;return await new Promise((resolve,reject)=>{let s='',size=0;req.on('data',c=>{size+=c.length;if(size>60000){reject(Object.assign(new Error('Large request'),{status:413}));req.destroy();return}s+=c});req.on('end',()=>{try{resolve(JSON.parse(s||'{}'))}catch{reject(Object.assign(new Error('Invalid JSON'),{status:400}))}});req.on('error',reject)})}
async function admin(db,req){
 const m=String(req.headers.cookie||'').match(/(?:^|;\s*)yola_session=([a-f0-9]{64})(?:;|$)/);if(!m)return null;
 const hash=crypto.createHash('sha256').update(m[1]).digest('hex');
 const sql=[
  'SELECT u.id,u.installation_id,u.role,u.active,i.status,i.expires_at,i.max_workers,p.slug',
  'FROM yola_web_sessions s JOIN yola_web_users u ON u.id=s.user_id',
  'JOIN installations i ON i.id=u.installation_id JOIN products p ON p.id=i.product_id',
  "JOIN product_accounts a ON a.installation_id=u.installation_id AND a.source_system='yola-web'",
  "AND a.source_reference=u.id::text AND a.status='active'",
  'WHERE s.token_hash=$1 AND s.expires_at>now() LIMIT 1'
 ].join(' ');
 const r=await db.query(sql,[hash]),u=r.rows[0];
 return u&&u.role==='owner'&&u.active&&u.slug==='yola'&&active(u)?u:null;
}
async function create(db,res,u,b){
 const name=safe(b.name),mail=email(b.email),phone=safe(b.phone,42),pwd=b.password;
 if(name.length<2||mail.length>254||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(mail)||typeof pwd!=='string'||pwd.length<12||pwd.length>128)return fail(res,422,'Valid worker name, email and password (12-128 characters) required.');
 if(b.role && b.role!=='worker')return fail(res,403,'Worker accounts only.');
 await db.query('BEGIN');
 try{
  const inst=await db.query('SELECT status,expires_at,max_workers FROM installations WHERE id=$1 FOR UPDATE',[u.installation_id]);
  if(!active(inst.rows[0]))throw Object.assign(new Error('Business not active'),{status:403});
  const count=await db.query(["SELECT",
   "(SELECT count(*)::int FROM yola_web_users WHERE installation_id=$1 AND role<>'owner' AND active) AS staff,",
   "(SELECT count(*)::int FROM yola_web_invites WHERE installation_id=$1 AND used_by IS NULL AND expires_at>now()) AS pending"
  ].join(' '),[u.installation_id]);
  if(count.rows[0].staff+count.rows[0].pending>=inst.rows[0].max_workers)throw Object.assign(new Error('Master Control employee limit reached'),{status:403});
  const salt=crypto.randomBytes(16).toString('hex'),hash=crypto.scryptSync(pwd,salt,64).toString('hex');
  const result=await db.query(["INSERT INTO yola_web_users(installation_id,name,email,phone,password_hash,role,active)",
    "VALUES($1,$2,$3,$4,$5,'worker',true) RETURNING id,name,email,phone,role,active,created_at"
   ].join(' '),[u.installation_id,name,mail,phone,'scrypt$'+salt+'$'+hash]);
  await db.query(["INSERT INTO product_accounts(installation_id,full_name,email,role,status,source_system,source_reference)",
    "VALUES($1,$2,$3,'worker','active','yola-web',$4)"
   ].join(' '),[u.installation_id,name,mail,result.rows[0].id]);
  await db.query('COMMIT');return ok(res,201,{success:true,worker:result.rows[0]});
 }catch(e){await db.query('ROLLBACK');if(e.code==='23505')return fail(res,409,'Email already registered');throw e}
}
async function setStatus(db,res,u,b){
 if(!uuid.test(String(b.id||''))||typeof b.active!=='boolean')return fail(res,422,'Valid worker id and status required.');
 await db.query('BEGIN');try{
  const row=await db.query('SELECT id FROM yola_web_users WHERE id=$1 AND installation_id=$2 AND role=$3 FOR UPDATE',[b.id,u.installation_id,'worker']);
  if(!row.rowCount)throw Object.assign(new Error('Worker not found'),{status:404});
  await db.query('UPDATE yola_web_users SET active=$1 WHERE id=$2 AND installation_id=$3',[b.active,b.id,u.installation_id]);
  await db.query(["UPDATE product_accounts SET status=$1 WHERE installation_id=$2",
    "AND source_system='yola-web' AND source_reference=$3"].join(' '),[b.active?'active':'suspended',u.installation_id,b.id]);
  if(!b.active)await db.query('DELETE FROM yola_web_sessions WHERE user_id=$1',[b.id]);
  await db.query('COMMIT');return ok(res,200,{success:true,active:b.active});
 }catch(e){await db.query('ROLLBACK');throw e}
}
async function list(db,res,u){
 const sql=["SELECT u.id,u.name,u.email,u.phone,u.role,u.created_at,",
  "(u.active AND COALESCE(a.status='active',false)) AS active",
  "FROM yola_web_users u LEFT JOIN product_accounts a ON",
  "a.installation_id=u.installation_id AND a.source_system='yola-web' AND a.source_reference=u.id::text",
  "WHERE u.installation_id=$1 ORDER BY u.created_at"].join(' ');
 const r=await db.query(sql,[u.installation_id]);return ok(res,200,{staff:r.rows,maxWorkers:u.max_workers});
}
async function performance(db,res,u){
 const sql=[
  'SELECT u.id,u.name,u.email,u.phone,u.active,',
  'count(s.id) FILTER (WHERE f.id IS NULL)::int AS lifetime_count,',
  'coalesce(sum(s.total_cents) FILTER (WHERE f.id IS NULL),0)::text AS lifetime_cents,',
  "count(s.id) FILTER (WHERE f.id IS NULL AND (s.created_at AT TIME ZONE 'Africa/Harare')::date=(now() AT TIME ZONE 'Africa/Harare')::date)::int AS today_count,",
  "coalesce(sum(s.total_cents) FILTER (WHERE f.id IS NULL AND (s.created_at AT TIME ZONE 'Africa/Harare')::date=(now() AT TIME ZONE 'Africa/Harare')::date),0)::text AS today_cents,",
  "count(s.id) FILTER (WHERE f.id IS NULL AND s.created_at>=now()-interval '7 days')::int AS week_count,",
  "coalesce(sum(s.total_cents) FILTER (WHERE f.id IS NULL AND s.created_at>=now()-interval '7 days'),0)::text AS week_cents,",
  "count(s.id) FILTER (WHERE f.id IS NULL AND s.created_at>=now()-interval '30 days')::int AS month_count,",
  "coalesce(sum(s.total_cents) FILTER (WHERE f.id IS NULL AND s.created_at>=now()-interval '30 days'),0)::text AS month_cents,",
  'max(s.created_at) AS last_sale FROM yola_web_users u',
  'LEFT JOIN yola_pos_sales s ON s.cashier_id=u.id AND s.installation_id=u.installation_id',
  'LEFT JOIN yola_pos_refunds f ON f.sale_id=s.id AND f.installation_id=u.installation_id',
  "WHERE u.installation_id=$1 AND u.role='worker' GROUP BY u.id,u.name,u.email,u.phone,u.active ORDER BY today_cents DESC,u.name"
 ].join(' ');
 const r=await db.query(sql,[u.installation_id]);return ok(res,200,{staff:r.rows,timezone:'Africa/Harare',refundedSalesExcluded:true});
}
const extensions={'/api/staff':['GET'],'/api/staff/create':['POST'],'/api/staff/status':['POST'],'/api/staff/performance':['GET']};
module.exports=async(req,res)=>{
 const path=queryPath(req);
 if(!Object.hasOwn(extensions,path))return original(req,res);
 if(!extensions[path].includes(req.method))return fail(res,405,'Method not allowed');
 if(req.method==='POST'){
  const origin=req.headers.origin;
  if(origin){try{let u=new URL(origin);if(u.protocol!=='https:'||u.host!==req.headers.host)return fail(res,403,'Invalid request origin')}catch{return fail(res,403,'Invalid request origin')}}
  if(!String(req.headers['content-type']||'').startsWith('application/json'))return fail(res,415,'Use application/json');
 }
 let db;try{
  if(!process.env.DG_MASTER_DATABASE_URL)return fail(res,503,'Master Control not configured');
  db=await pool.connect();
  const u=await admin(db,req);if(!u)return fail(res,403,'Active Yola business owner required');
  if(path==='/api/staff')return list(db,res,u);
  if(path==='/api/staff/performance')return performance(db,res,u);
  const b=await body(req);
  if(path==='/api/staff/create')return create(db,res,u,b);
  if(path==='/api/staff/status')return setStatus(db,res,u,b);
 }catch(e){
  if(!res.writableEnded){if(e.status&&e.status<500)return fail(res,e.status,e.message);console.error('SARGO staff extension:',e.code||e.name);return fail(res,503,'Employee management unavailable')}
 }finally{if(db)db.release()}
};