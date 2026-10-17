'use strict';
/**
 * Yola desktop bridge, using *only* approved businesses and limits from the
 * existing DG Tech Master Control Neon installation + devices tables.
 * No separate licensing administrator, password escrow or client-side signing.
 */
const crypto = require('node:crypto');
const text = (x,n=150)=>String(x??'').trim().slice(0,n);
const hash=x=>crypto.createHash('sha256').update(String(x)).digest('hex');
const encode=buf=>Buffer.from(buf).toString('base64url');
const report=(res,code,obj)=>{res.statusCode=code;res.setHeader('Content-Type','application/json; charset=utf-8');res.setHeader('Cache-Control','no-store');res.end(JSON.stringify(obj))};
const failed=(res,code,error)=>report(res,code,{error});
const signKey=()=>{
  const value=process.env.YOLA_DESKTOP_PKCS8_B64;
  if(!value)throw Object.assign(new Error('Official Yola desktop signing is not provisioned'),{http:503});
  return crypto.createPrivateKey({key:Buffer.from(value,'base64'),format:'der',type:'pkcs8'});
};
const getPublic=()=>crypto.createPublicKey(signKey()).export({format:'der',type:'spki'}).subarray(-32).toString('base64');
const signed=(value)=>{const content=Buffer.from(JSON.stringify(value));return encode(content)+'.'+encode(crypto.sign(null,content,signKey()))};
function decoded(token){
  try{
    const [payload,signature,...more]=String(token||'').split('.');
    if(!payload||!signature||more.length)throw Error('bad token');
    const data=Buffer.from(payload,'base64url');
    const pub=crypto.createPublicKey(signKey());
    if(!crypto.verify(null,data,pub,Buffer.from(signature,'base64url')))throw Error('bad signature');
    return JSON.parse(data.toString('utf8'));
  }catch{throw Object.assign(new Error('Invalid device licence'),{http:403})}
}
const validDevice=s=>/^[a-f0-9]{40,64}$/i.test(String(s||''));
const iso=dt=>new Date(dt).toISOString();
const verifyPassword=(password,stored)=>{
 try{const [type,salt,digest]=String(stored||'').split('$');if(type!=='scrypt')return false;const expected=Buffer.from(digest,'hex');const calculated=crypto.scryptSync(password,salt,expected.length);return expected.length===calculated.length&&crypto.timingSafeEqual(expected,calculated)}catch{return false}
};
async function licenseRow(db,device){
 const query=`SELECT d.id AS registered_device,i.id AS installation_id,i.business_code,i.status,i.expires_at,
   i.max_devices,i.offline_lease_hours,c.name AS business_name
   FROM devices d JOIN installations i ON i.id=d.installation_id
   JOIN products p ON p.id=i.product_id JOIN customers c ON c.id=i.customer_id
   WHERE d.device_uid=$1 AND p.slug='yola' LIMIT 1`;
 const r=await db.query(query,[device]);return r.rows[0]||null;
}
function enforce(row){
 if(!row||row.status!=='active'||(row.expires_at&&new Date(row.expires_at)<=new Date()))
   throw Object.assign(new Error('DG Tech Master Control has not activated this Yola installation'),{http:403});
}
function issue(row,device){
 enforce(row);
 const now=Date.now(),end=row.expires_at?Math.min(now+30*86400000,new Date(row.expires_at).getTime()):now+30*86400000;
 const hours=Math.max(1,Math.min(Number(row.offline_lease_hours)||24,72));
 const until=Math.min(now+hours*3600000,end);
 const business='YOLA-'+row.installation_id;
 const base={kind:'yola-device-license',device_id:device,business_id:business,
   business_name:row.business_name,master_installation_id:String(row.installation_id),
   valid_until:iso(end),plan:'business',branch_id:'BR-MAIN',branch_name:'Main Branch',
   device_limit:Number(row.max_devices)||1};
 const lease={kind:'yola-offline-lease',device_id:device,business_id:business,
  master_installation_id:String(row.installation_id),offline_until:iso(until)};
 return {...base,status:'active',active:true,public_key:getPublic(),license_token:signed(base),lease_token:signed(lease)};
}
async function enroll(db,b,res){
 const email=text(b.email,254).toLowerCase(),password=b.password,device=text(b.device_id,85),code=text(b.existing_business_id,90).toUpperCase();
 const label=text(b.device_name,120)||'Yola Windows PC';
 if(!validDevice(device)||!code||typeof password!=='string'||password.length<12||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
   return failed(res,422,'Enter your registered Yola business code, owner email, password and valid device details.');
 await db.query('BEGIN');
 try{
   const user=await db.query(`SELECT u.password_hash,u.role,u.active,u.installation_id,
       a.status AS master_account_status,i.business_code,i.status,i.max_devices,i.expires_at,p.slug
       FROM yola_web_users u JOIN installations i ON i.id=u.installation_id
       JOIN products p ON p.id=i.product_id LEFT JOIN product_accounts a ON a.installation_id=i.id
       AND a.source_system='yola-web' AND a.source_reference=u.id::text
       WHERE lower(u.email)=$1 FOR UPDATE OF u`,[email]);
   const owner=user.rows[0];
   if(!owner||owner.role!=='owner'||!owner.active||owner.slug!=='yola'||owner.master_account_status!=='active'||!verifyPassword(password,owner.password_hash)||owner.business_code!==code)
     throw Object.assign(new Error('Owner credentials or Yola registration ID are incorrect'),{http:401});
   if(owner.status!=='active'||(owner.expires_at&&new Date(owner.expires_at)<=new Date()))
     throw Object.assign(new Error('Waiting for DG Tech Master Control activation'),{http:403});
   const locked=await db.query('SELECT max_devices,status FROM installations WHERE id=$1 FOR UPDATE',[owner.installation_id]);
   const existing=await db.query('SELECT installation_id FROM devices WHERE device_uid=$1',[device]);
   if(existing.rows.some(x=>String(x.installation_id)!==String(owner.installation_id)))
     throw Object.assign(new Error('Device already belongs to another business. Contact DG Tech.'),{http:409});
   if(!existing.rowCount){
     const count=await db.query('SELECT COUNT(*)::integer AS n FROM devices WHERE installation_id=$1',[owner.installation_id]);
     if(count.rows[0].n>=locked.rows[0].max_devices)
       throw Object.assign(new Error('Master Control device limit reached. Contact DG Tech.'),{http:403});
     await db.query('INSERT INTO devices(installation_id,label,device_uid) VALUES ($1,$2,$3)',[owner.installation_id,label,device]);
   }
   const secret=crypto.randomBytes(32).toString('hex');
   await db.query(`INSERT INTO yola_desktop_enrollments(installation_id,device_uid,claim_hash,created_at)
     VALUES($1,$2,$3,now()) ON CONFLICT (device_uid) DO UPDATE SET claim_hash=EXCLUDED.claim_hash,
     created_at=now()`,[owner.installation_id,device,hash(secret)]);
   await db.query('COMMIT');
   return report(res,200,{status:'pending',request_code:code,claim_secret:secret,
     message:'Device registered under your Master-approved Yola business. Checking its signed licence.'});
 }catch(e){await db.query('ROLLBACK');throw e}
}
async function claim(db,b,res){
 const device=text(b.device_id,85),secret=text(b.claim_secret,160);
 if(!validDevice(device)||!/^[0-9a-f]{64}$/i.test(secret))return failed(res,403,'Invalid enrolment claim');
 const q=await db.query(`SELECT e.installation_id,e.device_uid,e.claim_hash FROM yola_desktop_enrollments e
 WHERE e.device_uid=$1`,[device]);const x=q.rows[0];
 if(!x||!crypto.timingSafeEqual(Buffer.from(x.claim_hash,'hex'),Buffer.from(hash(secret),'hex')))
   return failed(res,403,'Unrecognized device enrolment claim');
 const row=await licenseRow(db,device);if(!row||String(x.installation_id)!==String(row.installation_id))return failed(res,403,'Device not registered in Master Control');
 if(row.status!=='active'||(row.expires_at&&new Date(row.expires_at)<=new Date()))return report(res,200,{status:'pending_master_control',request_code:row.business_code});
 const issued=issue(row,device);
 await db.query('UPDATE devices SET last_seen=now() WHERE device_uid=$1',[device]);
 return report(res,200,{...issued,request_code:row.business_code,owner_access_token:null});
}
async function verify(db,b,res){
 let payload;try{payload=decoded(b.license_token)}catch(e){return report(res,200,{active:false,status:'revoked'})}
 const device=text(b.device_id,85),row=await licenseRow(db,device);
 if(!row||payload.kind!=='yola-device-license'||!Number.isFinite(Date.parse(payload.valid_until))||payload.device_id!==device||payload.master_installation_id!==String(row.installation_id))
   return report(res,200,{active:false,status:'suspended'});
 if(row.status!=='active'||(row.expires_at&&new Date(row.expires_at)<=new Date()))
   return report(res,200,{active:false,status:row.status});
 if(Date.now()>new Date(payload.valid_until).getTime())return report(res,200,{active:false,status:'expired'});
 const granted=issue(row,device);
 await db.query('UPDATE devices SET last_seen=now() WHERE device_uid=$1',[device]);
 return report(res,200,{active:true,status:'active',lease_token:granted.lease_token,
   business_id:granted.business_id,valid_until:granted.valid_until,plan:granted.plan,
   branch_id:granted.branch_id,branch_name:granted.branch_name});
}
async function syncEvent(db,b,res){
 const payload=decoded(b.license_token),device=text(b.device_id,85);
 const row=await licenseRow(db,device);enforce(row);
 if(payload.kind!=='yola-device-license'||!Number.isFinite(Date.parse(payload.valid_until))||payload.device_id!==device||payload.master_installation_id!==String(row.installation_id)||Date.now()>Date.parse(payload.valid_until))
   return failed(res,403,'Yola desktop licence is not valid for this Master Control business');
 const eventKey=text(b.event_key,150),eventType=text(b.event_type,100);
 if(!eventKey||!eventType||!b.payload||typeof b.payload!=='object')return failed(res,422,'Invalid sync event');
 await db.query(`INSERT INTO yola_desktop_sync_events(installation_id,device_uid,event_key,event_type,payload,created_at)
   VALUES ($1,$2,$3,$4,$5,now()) ON CONFLICT (installation_id,device_uid,event_key) DO NOTHING`,
   [row.installation_id,device,eventKey,eventType,b.payload]);
 // Raw events are durable/idempotent, NOT silently treated as fully reconciled
 // web sales. A separate consolidation job must validate ledgers and stock.
 return report(res,200,{ok:true,stored:true,reconciled:false});
}
module.exports=async({db,res,path,method,body})=>{
 if(path==='/api/public-key'&&method==='GET')return report(res,200,{public_key:getPublic()})||true;
 if(!['/api/activation/request','/api/activation/status','/api/license/verify','/api/sync/event'].includes(path))return false;
 if(method!=='POST')return failed(res,405,'Method not allowed')||true;
 if(path==='/api/activation/request'){await enroll(db,body,res);return true}
 if(path==='/api/activation/status'){await claim(db,body,res);return true}
 if(path==='/api/license/verify'){await verify(db,body,res);return true}
 if(path==='/api/sync/event'){await syncEvent(db,body,res);return true}
 return false;
};
module.exports.__test={validDevice,verifyPassword,signed,decoded,getPublic};