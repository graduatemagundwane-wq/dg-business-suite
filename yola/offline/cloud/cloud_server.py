from __future__ import annotations

import base64
import hashlib
import json
import os
import secrets
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Optional

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
import master_registry as master

ROOT=Path(__file__).resolve().parent
DB_PATH=Path(os.getenv("DG_CLOUD_DB",str(ROOT/"dg_cloud.db")))
ADMIN_KEY=os.getenv("DG_CLOUD_ADMIN_KEY","")
LICENSE_DAYS=int(os.getenv("DG_CLOUD_LICENSE_DAYS","365"))
KEY_PATH=Path(os.getenv("DG_LICENSE_KEY_FILE",str(ROOT/"license_signing.key")))
STATIC_DIR=ROOT/"static"; STATIC_DIR.mkdir(exist_ok=True)

app=FastAPI(title="Yola Cloud — Powered by Double Gee Tech",version="3.2.1")
app.mount("/static",StaticFiles(directory=str(STATIC_DIR)),name="static")

def utcnow(): return datetime.now(timezone.utc)
def iso(dt=None): return (dt or utcnow()).isoformat()
def token_hash(v:str): return hashlib.sha256(v.encode()).hexdigest()
def b64u(b:bytes): return base64.urlsafe_b64encode(b).decode().rstrip("=")
def b64u_decode(s:str): return base64.urlsafe_b64decode(s+"="*(-len(s)%4))
def money(v:Any): return round(float(v or 0)+1e-9,2)

def load_private_key() -> Ed25519PrivateKey:
    env=os.getenv("DG_LICENSE_PRIVATE_KEY_B64","")
    if env:
        return Ed25519PrivateKey.from_private_bytes(base64.b64decode(env))
    if KEY_PATH.exists():
        return Ed25519PrivateKey.from_private_bytes(KEY_PATH.read_bytes())
    if master.enabled():
        # A fresh signing key on each restart would invalidate every device.
        # Production must provision a persistent protected key explicitly.
        raise RuntimeError('Yola Cloud requires a persistent, protected Ed25519 signing key when Master Control is enabled')
    key=Ed25519PrivateKey.generate()
    raw=key.private_bytes(serialization.Encoding.Raw,serialization.PrivateFormat.Raw,serialization.NoEncryption())
    KEY_PATH.write_bytes(raw)
    try: os.chmod(KEY_PATH,0o600)
    except Exception: pass
    return key

PRIVATE_KEY=load_private_key()
PUBLIC_KEY=PRIVATE_KEY.public_key()
PUBLIC_KEY_B64=base64.b64encode(PUBLIC_KEY.public_bytes(serialization.Encoding.Raw,serialization.PublicFormat.Raw)).decode()

def sign_payload(payload:dict[str,Any]) -> str:
    raw=json.dumps(payload,separators=(",",":"),sort_keys=True).encode(); return b64u(raw)+"."+b64u(PRIVATE_KEY.sign(raw))

def verify_signed_token(token:str) -> dict[str,Any]:
    try:
        p,s=token.split(".",1); raw=b64u_decode(p); PUBLIC_KEY.verify(b64u_decode(s),raw); return json.loads(raw.decode())
    except Exception: raise HTTPException(status_code=403,detail="Invalid signed licence token")

def admin_guard(key:str):
    if not ADMIN_KEY or not secrets.compare_digest(key,ADMIN_KEY): raise HTTPException(status_code=403,detail="Invalid Double Gee Tech admin key")

@contextmanager
def db():
    c=sqlite3.connect(DB_PATH,timeout=20); c.row_factory=sqlite3.Row; c.execute("PRAGMA journal_mode=WAL")
    try:
        yield c; c.commit()
    except Exception:
        c.rollback(); raise
    finally: c.close()

def add_column(c:sqlite3.Connection,table:str,column:str,definition:str):
    cols={r[1] for r in c.execute(f"PRAGMA table_info({table})").fetchall()}
    if column not in cols: c.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")

with db() as c:
    c.executescript("""
    CREATE TABLE IF NOT EXISTS businesses(
      id TEXT PRIMARY KEY,name TEXT NOT NULL,owner_name TEXT,phone TEXT,plan TEXT DEFAULT 'standard',device_limit INTEGER DEFAULT 1,status TEXT DEFAULT 'active',
      owner_token_hash TEXT,backup_key TEXT NOT NULL,created_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS branches(id TEXT PRIMARY KEY,business_id TEXT NOT NULL,name TEXT NOT NULL,location TEXT DEFAULT '',active INTEGER DEFAULT 1,created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS activations(
      id INTEGER PRIMARY KEY AUTOINCREMENT,request_code TEXT UNIQUE NOT NULL,device_id TEXT UNIQUE NOT NULL,device_name TEXT,business_id TEXT,business_name TEXT NOT NULL,owner_name TEXT,phone TEXT,
      branch_id TEXT,status TEXT NOT NULL DEFAULT 'pending',token_hash TEXT,pending_token TEXT,claim_hash TEXT,created_at TEXT NOT NULL,approved_at TEXT,valid_until TEXT,last_seen TEXT,plan TEXT DEFAULT 'standard',device_limit INTEGER DEFAULT 1,app_version TEXT
    );
    CREATE TABLE IF NOT EXISTS sync_events(
      id INTEGER PRIMARY KEY AUTOINCREMENT,business_id TEXT NOT NULL,device_id TEXT NOT NULL,branch_id TEXT,event_key TEXT UNIQUE NOT NULL,event_type TEXT NOT NULL,payload TEXT NOT NULL,created_at TEXT NOT NULL,synced_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS notifications(id INTEGER PRIMARY KEY AUTOINCREMENT,business_id TEXT NOT NULL,branch_id TEXT,kind TEXT,title TEXT,message TEXT,severity TEXT DEFAULT 'info',read INTEGER DEFAULT 0,created_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS approvals(id TEXT PRIMARY KEY,business_id TEXT NOT NULL,device_id TEXT NOT NULL,branch_id TEXT,request_type TEXT NOT NULL,requested_by TEXT,details TEXT NOT NULL,status TEXT DEFAULT 'pending',created_at TEXT NOT NULL,resolved_at TEXT,resolved_by TEXT);
    CREATE TABLE IF NOT EXISTS backups(id INTEGER PRIMARY KEY AUTOINCREMENT,business_id TEXT NOT NULL,device_id TEXT NOT NULL,name TEXT NOT NULL,data BLOB NOT NULL,created_at TEXT NOT NULL,uploaded_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS releases(id INTEGER PRIMARY KEY AUTOINCREMENT,version TEXT UNIQUE NOT NULL,url TEXT NOT NULL,sha256 TEXT NOT NULL,signature TEXT NOT NULL,critical INTEGER DEFAULT 0,notes TEXT,created_at TEXT NOT NULL);
    """)
    # v1 migration
    for table,col,definition in [
      ("activations","branch_id","TEXT"), ("activations","master_installation_id","TEXT"), ("activations","owner_claim_token","TEXT"),("activations","plan","TEXT DEFAULT 'standard'"),("activations","device_limit","INTEGER DEFAULT 1"),("activations","app_version","TEXT"), ("activations","existing_business_id_requested","TEXT")
    ]: add_column(c,table,col,definition)

class ActivationReq(BaseModel):
    device_id:str=Field(min_length=10,max_length=180)
    device_name:str=Field(default='',max_length=100)
    business_name:str=Field(min_length=2,max_length=140)
    owner_name:str=Field(min_length=2,max_length=120)
    phone:str=Field(default='',max_length=40)
    app_version:str=Field(default='',max_length=30)
    existing_business_id:str=Field(default='',max_length=100)
class ActivationStatusReq(BaseModel): device_id:str; claim_secret:str
class VerifyReq(BaseModel): device_id:str; license_token:str; app_version:str=""
class SyncEventIn(BaseModel): device_id:str; license_token:str; event_key:str; event_type:str; branch_id:Optional[int|str]=None; payload:dict[str,Any]; created_at:str
class ApprovalIn(BaseModel): device_id:str; license_token:str; request_type:str; branch_id:Optional[int|str]=None; requested_by:str=""; details:dict[str,Any]
class BackupIn(BaseModel): device_id:str; license_token:str; name:str; data_b64:str; created_at:str
class ReleaseIn(BaseModel): version:str; url:str; sha256:str; critical:bool=False; notes:str=""


def business_row(c:sqlite3.Connection,business_id:str):
    return c.execute("SELECT * FROM businesses WHERE id=?",(business_id,)).fetchone()

def branch_name(c:sqlite3.Connection,branch_id:Optional[str]) -> str:
    if not branch_id: return "Main Branch"
    r=c.execute("SELECT name FROM branches WHERE id=?",(branch_id,)).fetchone(); return r[0] if r else "Main Branch"

def issue_license(c:sqlite3.Connection,a:sqlite3.Row,b:sqlite3.Row,branch_id:str,entitlement=None) -> tuple[str,str]:
    valid_at=utcnow()+timedelta(days=LICENSE_DAYS)
    if entitlement and entitlement.get('expires_at'):
        valid_at=min(valid_at,datetime.fromisoformat(entitlement['expires_at']))
    valid=iso(valid_at)
    payload={"business_id":b["id"],"business_name":b["name"],"device_id":a["device_id"],"branch_id":branch_id,
             "branch_name":branch_name(c,branch_id),"plan":b["plan"],"device_limit":b["device_limit"],
             "max_workers":(entitlement or {}).get('max_workers',25),
             "offline_lease_hours":(entitlement or {}).get('offline_lease_hours',72),
             "master_installation_id":a['master_installation_id'],
             "backup_key":b["backup_key"],"valid_until":valid,"issued_at":iso()}
    token=sign_payload(payload)
    c.execute("UPDATE activations SET business_id=?,business_name=?,branch_id=?,status='active',token_hash=?,pending_token=?,approved_at=COALESCE(approved_at,?),valid_until=?,plan=?,device_limit=? WHERE id=?",(b["id"],b["name"],branch_id,token_hash(token),token,iso(),valid,b["plan"],b["device_limit"],a["id"]))
    return token,valid

def offline_lease(a,entitlement=None) -> str:
    """Short server-signed offline lease, renewed after each Master-approved check."""
    policy=int((entitlement or {}).get('offline_lease_hours',72))
    policy=max(0,min(policy,168))
    until=utcnow()+timedelta(hours=policy)
    if entitlement and entitlement.get('expires_at'):
        until=min(until,datetime.fromisoformat(entitlement['expires_at']))
    if a['valid_until']:
        until=min(until,datetime.fromisoformat(a['valid_until']))
    return sign_payload({'kind':'yola-offline-lease',
                         'max_workers':int((entitlement or {}).get('max_workers',25)),
                         'device_id':a['device_id'],
                         'business_id':a['business_id'],
                         'master_installation_id':a['master_installation_id'],
                         'offline_until':iso(until), 'issued_at':iso()})


def auth_license(c:sqlite3.Connection,device_id:str,token:str) -> tuple[sqlite3.Row,dict[str,Any]]:
    payload=verify_signed_token(token)
    if payload.get("device_id")!=device_id: raise HTTPException(status_code=403,detail="Licence is bound to another device")
    a=c.execute("SELECT * FROM activations WHERE device_id=?",(device_id,)).fetchone()
    if not a or a["status"]!="active" or not a["token_hash"] or not secrets.compare_digest(a["token_hash"],token_hash(token)): raise HTTPException(status_code=403,detail="Inactive or revoked licence")
    if a["valid_until"] and utcnow()>datetime.fromisoformat(a["valid_until"]): raise HTTPException(status_code=403,detail="Licence expired")
    b=business_row(c,a["business_id"])
    if not b or b["status"]!="active": raise HTTPException(status_code=403,detail="Business account inactive")
    if master.enabled():
        try: master.entitlement(a['master_installation_id'], device_id)
        except master.MasterDenied as e: raise HTTPException(403,str(e))
        except master.MasterUnavailable as e: raise HTTPException(503,str(e))
    return a,payload

def owner_auth(c:sqlite3.Connection,business_id:str,owner_token:str):
    b=business_row(c,business_id)
    if not b or not b["owner_token_hash"] or not owner_token or not secrets.compare_digest(b["owner_token_hash"],token_hash(owner_token)): raise HTTPException(status_code=403,detail="Invalid owner access")
    if master.enabled():
        if not business_id.startswith('YOLA-'):
            raise HTTPException(status_code=403, detail='Not a Master-managed Yola business')
        try:
            master.require_business_active(business_id.removeprefix('YOLA-'))
        except master.MasterDenied as exc:
            raise HTTPException(status_code=403,detail=str(exc)) from exc
        except master.MasterUnavailable as exc:
            raise HTTPException(status_code=503,detail=str(exc)) from exc
    return b

@app.get("/api/health")
def health():
    ready = master.registry_ready()
    return {"ok":ready,"service":"Yola Cloud — Powered by Double Gee Tech","version":"3.2.1",
            "master_control_required":master.enabled(),"master_registry_ready":ready}

@app.get("/api/public-key")
def public_key(): return {"algorithm":"Ed25519","public_key":PUBLIC_KEY_B64}

@app.post("/api/activation/request")
def activation_request(p:ActivationReq):
    claim_secret=secrets.token_urlsafe(28); ch=token_hash(claim_secret)
    with db() as c:
        existing=c.execute("SELECT * FROM activations WHERE device_id=?",(p.device_id,)).fetchone()
        request_code=existing['request_code'] if existing else 'YL-'+secrets.token_hex(6).upper()
        try:
            installation_id=master.register_request(
                request_code, p.device_id, p.device_name, p.business_name,
                p.owner_name, p.phone, p.existing_business_id,
            )
        except master.MasterDenied as e:
            raise HTTPException(403,str(e))
        except master.MasterUnavailable as e:
            raise HTTPException(503,str(e))
        if existing:
            if existing["status"]=="active": return {"status":"active","request_code":existing["request_code"],"message":"This device is already registered. Double Gee Tech can reactivate or transfer it if required."}
            c.execute("UPDATE activations SET device_name=?,business_name=?,owner_name=?,phone=?,claim_hash=?,app_version=?,existing_business_id_requested=?,master_installation_id=? WHERE device_id=?",(p.device_name,p.business_name,p.owner_name,p.phone,ch,p.app_version,p.existing_business_id,installation_id,p.device_id))
            return {"status":existing["status"],"request_code":existing["request_code"],"claim_secret":claim_secret}
        code=request_code
        c.execute("INSERT INTO activations(request_code,device_id,device_name,business_name,owner_name,phone,claim_hash,created_at,app_version,existing_business_id_requested,master_installation_id) VALUES(?,?,?,?,?,?,?,?,?,?,?)",(code,p.device_id,p.device_name,p.business_name,p.owner_name,p.phone,ch,iso(),p.app_version,p.existing_business_id,installation_id))
        return {"status":"pending","request_code":code,"claim_secret":claim_secret,"message":"Yola registration is awaiting approval in DG Tech Master Control."}

def _activate_from_master(c,a,entitlement):
    # No admin approval bypass: the Master installation is already active.
    business_id='YOLA-'+str(a['master_installation_id']) if a['master_installation_id'] else ''
    if not business_id: raise HTTPException(403,'Missing Master Control installation')
    b=business_row(c,business_id)
    if not b:
        owner_token=secrets.token_urlsafe(28)
        c.execute('UPDATE activations SET owner_claim_token=? WHERE id=?',(owner_token,a['id']))
        c.execute('''INSERT INTO businesses(id,name,owner_name,phone,plan,device_limit,status,
            owner_token_hash,backup_key,created_at) VALUES(?,?,?,?,?,?,'active',?,?,?)''',
            (business_id,a['business_name'],a['owner_name'],a['phone'],'yola',entitlement['max_devices'],
             token_hash(owner_token),secrets.token_urlsafe(32),iso()))
        b=business_row(c,business_id)
    branch=c.execute('SELECT id FROM branches WHERE business_id=? ORDER BY created_at LIMIT 1',(business_id,)).fetchone()
    if branch: branch_id=branch['id']
    else:
        branch_id='BR-'+uuid.uuid4().hex[:8].upper()
        c.execute('INSERT INTO branches(id,business_id,name,location,created_at) VALUES(?,?,?,?,?)',
                  (branch_id,business_id,'Main Branch','',iso()))
    issue_license(c,a,b,branch_id,entitlement)


@app.post("/api/activation/status")
def activation_status(p:ActivationStatusReq):
    with db() as c:
        r=c.execute("SELECT * FROM activations WHERE device_id=?",(p.device_id,)).fetchone()
        if not r: return {"status":"not_requested"}
        if not r["claim_hash"] or not secrets.compare_digest(r["claim_hash"],token_hash(p.claim_secret)): raise HTTPException(status_code=403,detail="Invalid activation claim")
        if master.enabled() and r['status'] in {'pending','suspended','active'}:
            try: entitlement=master.entitlement(r['master_installation_id'],p.device_id)
            except master.MasterDenied as e:
                return {'status':'pending_master_control','request_code':r['request_code'],'message':str(e)}
            except master.MasterUnavailable as e: raise HTTPException(503,detail=str(e))
            if r['status'] != 'active':
                _activate_from_master(c,r,entitlement)
                r=c.execute('SELECT * FROM activations WHERE id=?',(r['id'],)).fetchone()
        out={"status":r["status"],"request_code":r["request_code"],"business_id":r["business_id"],"business_name":r["business_name"],"valid_until":r["valid_until"]}
        if r["status"]=="active" and r["pending_token"]:
            out.update({"license_token":r["pending_token"],"public_key":PUBLIC_KEY_B64,
                        "lease_token":offline_lease(r,entitlement if master.enabled() else None)})
            if r['owner_claim_token']:
                out['owner_access_token']=r['owner_claim_token']
            c.execute("UPDATE activations SET pending_token=NULL,claim_hash=NULL,owner_claim_token=NULL WHERE device_id=?",(p.device_id,))
        return out

@app.post("/api/license/verify")
def verify(p:VerifyReq):
    with db() as c:
        try:
            a,payload=auth_license(c,p.device_id,p.license_token)
            ent=master.entitlement(a['master_installation_id'],p.device_id) if master.enabled() else None
            c.execute("UPDATE activations SET last_seen=?,app_version=? WHERE device_id=?",(iso(),p.app_version,a["device_id"]))
            return {"active":True,"status":"active","lease_token":offline_lease(a,ent),
                    "business_id":a["business_id"],"business_name":a["business_name"],"valid_until":a["valid_until"],
                    "plan":a["plan"],"branch_id":a["branch_id"],"branch_name":branch_name(c,a["branch_id"])}
        except HTTPException:
            a=c.execute("SELECT * FROM activations WHERE device_id=?",(p.device_id,)).fetchone(); return {"active":False,"status":a["status"] if a else "unknown"}

# ---------- Double Gee Tech admin ----------
@app.get("/api/admin/activations")
def admin_activations(x_admin_key:str=Header(default="")):
    admin_guard(x_admin_key)
    with db() as c:
        rows=c.execute("""SELECT a.*,b.plan business_plan,b.device_limit business_device_limit,br.name branch_name,
              (SELECT COUNT(*) FROM activations ax WHERE ax.business_id=a.business_id AND ax.status='active') active_devices
              FROM activations a LEFT JOIN businesses b ON b.id=a.business_id LEFT JOIN branches br ON br.id=a.branch_id ORDER BY a.created_at DESC""").fetchall(); return [dict(r) for r in rows]

@app.get("/api/admin/businesses")
def admin_businesses(x_admin_key:str=Header(default="")):
    admin_guard(x_admin_key)
    with db() as c:
        out=[]
        for b in c.execute("SELECT * FROM businesses ORDER BY created_at DESC").fetchall():
            d=dict(b); d.pop("owner_token_hash",None); d.pop("backup_key",None); d["active_devices"]=c.execute("SELECT COUNT(*) FROM activations WHERE business_id=? AND status='active'",(b["id"],)).fetchone()[0]; d["branches"]=[dict(x) for x in c.execute("SELECT * FROM branches WHERE business_id=? ORDER BY name",(b["id"],)).fetchall()]; out.append(d)
        return out

@app.post("/api/admin/activations/{request_code}/approve")
def approve(request_code:str,payload:dict[str,Any]={},x_admin_key:str=Header(default="")):
    admin_guard(x_admin_key)
    if master.enabled():
        raise HTTPException(409,"Activate Yola exclusively in DG Tech Master Control")
    with db() as c:
        a=c.execute("SELECT * FROM activations WHERE request_code=?",(request_code,)).fetchone()
        if not a: raise HTTPException(status_code=404,detail="Activation request not found")
        business_id=str(payload.get("business_id") or "")
        owner_token=None
        if business_id:
            b=business_row(c,business_id)
            if not b: raise HTTPException(status_code=404,detail="Business not found")
        else:
            business_id="BIZ-"+uuid.uuid4().hex[:10].upper(); owner_token=secrets.token_urlsafe(28); plan=str(payload.get("plan") or "standard"); limit=max(1,int(payload.get("device_limit") or 1)); backup_key=secrets.token_urlsafe(32)
            c.execute("INSERT INTO businesses(id,name,owner_name,phone,plan,device_limit,status,owner_token_hash,backup_key,created_at) VALUES(?,?,?,?,?,?,'active',?,?,?)",(business_id,a["business_name"],a["owner_name"],a["phone"],plan,limit,token_hash(owner_token),backup_key,iso())); b=business_row(c,business_id)
        active=c.execute("SELECT COUNT(*) FROM activations WHERE business_id=? AND status='active' AND device_id<>?",(business_id,a["device_id"])).fetchone()[0]
        if active>=int(b["device_limit"]): raise HTTPException(status_code=409,detail=f"Device limit reached for {b['name']}")
        branch_id=str(payload.get("branch_id") or "")
        if not branch_id:
            branch_name_req=str(payload.get("branch_name") or "Main Branch"); br=c.execute("SELECT * FROM branches WHERE business_id=? AND lower(name)=lower(?)",(business_id,branch_name_req)).fetchone()
            if not br:
                branch_id="BR-"+uuid.uuid4().hex[:8].upper(); c.execute("INSERT INTO branches(id,business_id,name,location,created_at) VALUES(?,?,?,?,?)",(branch_id,business_id,branch_name_req,str(payload.get("location") or ""),iso()))
            else: branch_id=br["id"]
        token,valid=issue_license(c,a,b,branch_id)
        out={"status":"active","business_id":business_id,"business_name":b["name"],"device_id":a["device_id"],"branch_id":branch_id,"branch_name":branch_name(c,branch_id),"valid_until":valid,"plan":b["plan"],"device_limit":b["device_limit"]}
        if owner_token: out["owner_access_token"]=owner_token
        return out

@app.post("/api/admin/activations/{request_code}/suspend")
def suspend(request_code:str,x_admin_key:str=Header(default="")):
    admin_guard(x_admin_key)
    if master.enabled(): raise HTTPException(409,"Manage Yola licensing only in DG Tech Master Control")
    with db() as c: c.execute("UPDATE activations SET status='suspended' WHERE request_code=?",(request_code,))
    return {"status":"suspended"}

@app.post("/api/admin/activations/{request_code}/disable")
def disable(request_code:str,x_admin_key:str=Header(default="")):
    admin_guard(x_admin_key)
    if master.enabled(): raise HTTPException(409,"Manage Yola licensing only in DG Tech Master Control")
    with db() as c: c.execute("UPDATE activations SET status='disabled',token_hash=NULL,pending_token=NULL WHERE request_code=?",(request_code,))
    return {"status":"disabled"}

@app.post("/api/admin/activations/{request_code}/reactivate")
def reactivate(request_code:str,x_admin_key:str=Header(default="")):
    admin_guard(x_admin_key)
    if master.enabled():
        raise HTTPException(409,"Reactivate Yola exclusively in DG Tech Master Control")
    with db() as c:
        a=c.execute("SELECT * FROM activations WHERE request_code=?",(request_code,)).fetchone()
        if not a or not a["business_id"]: raise HTTPException(status_code=404,detail="Activation/business not found")
        b=business_row(c,a["business_id"]); branch_id=a["branch_id"] or c.execute("SELECT id FROM branches WHERE business_id=? LIMIT 1",(b["id"],)).fetchone()[0]
        # Re-activate the existing signed device entitlement without silently
        # invalidating the token already installed on the customer desktop.
        if a['token_hash'] and a['valid_until'] and utcnow()<=datetime.fromisoformat(a['valid_until']):
            c.execute("UPDATE activations SET status='active' WHERE id=?",(a['id'],))
            valid=a['valid_until']
        else:
            token,valid=issue_license(c,a,b,branch_id)
        # Keep the current claim hash so a POS that re-requested activation while suspended
        # can claim the newly-issued signed token with the secret it already holds.
        return {"status":"active","request_code":request_code,"valid_until":valid}

@app.post("/api/admin/activations/{request_code}/transfer")
def transfer(request_code:str,payload:dict[str,Any],x_admin_key:str=Header(default="")):
    admin_guard(x_admin_key); business_id=str(payload.get("business_id") or ""); branch_id=str(payload.get("branch_id") or "")
    if master.enabled(): raise HTTPException(409,"Manage Yola licensing only in DG Tech Master Control")
    with db() as c:
        a=c.execute("SELECT * FROM activations WHERE request_code=?",(request_code,)).fetchone(); b=business_row(c,business_id)
        if not a or not b: raise HTTPException(status_code=404,detail="Activation or business not found")
        if not branch_id:
            br=c.execute("SELECT id FROM branches WHERE business_id=? ORDER BY created_at LIMIT 1",(business_id,)).fetchone(); branch_id=br[0] if br else ""
        c.execute("UPDATE activations SET business_id=?,business_name=?,branch_id=?,status='pending',token_hash=NULL,pending_token=NULL WHERE id=?",(b["id"],b["name"],branch_id,a["id"])); return {"status":"pending","business_id":business_id,"branch_id":branch_id}

@app.post("/api/admin/businesses/{business_id}/branches")
def add_cloud_branch(business_id:str,payload:dict[str,Any],x_admin_key:str=Header(default="")):
    admin_guard(x_admin_key); name=str(payload.get("name") or "").strip()
    if not name: raise HTTPException(status_code=422,detail="Branch name required")
    with db() as c:
        if not business_row(c,business_id): raise HTTPException(status_code=404,detail="Business not found")
        bid="BR-"+uuid.uuid4().hex[:8].upper(); c.execute("INSERT INTO branches(id,business_id,name,location,created_at) VALUES(?,?,?,?,?)",(bid,business_id,name,str(payload.get("location") or ""),iso())); return {"id":bid,"name":name}

@app.post("/api/admin/businesses/{business_id}/owner-token")
def reset_owner_token(business_id:str,x_admin_key:str=Header(default="")):
    admin_guard(x_admin_key); token=secrets.token_urlsafe(28)
    with db() as c:
        if not business_row(c,business_id): raise HTTPException(status_code=404,detail="Business not found")
        c.execute("UPDATE businesses SET owner_token_hash=? WHERE id=?",(token_hash(token),business_id))
    return {"business_id":business_id,"owner_access_token":token}

@app.post("/api/admin/businesses/{business_id}/plan")
def update_plan(business_id:str,payload:dict[str,Any],x_admin_key:str=Header(default="")):
    admin_guard(x_admin_key); plan=str(payload.get("plan") or "standard"); limit=max(1,int(payload.get("device_limit") or 1))
    if master.enabled(): raise HTTPException(409,"Manage Yola licensing only in DG Tech Master Control")
    with db() as c:
        c.execute("UPDATE businesses SET plan=?,device_limit=? WHERE id=?",(plan,limit,business_id)); c.execute("UPDATE activations SET plan=?,device_limit=? WHERE business_id=?",(plan,limit,business_id))
    return {"ok":True,"plan":plan,"device_limit":limit}

# ---------- Sync / remote mobile ----------
@app.post("/api/sync/event")
def sync_event(p:SyncEventIn):
    with db() as c:
        a,token=auth_license(c,p.device_id,p.license_token); branch=str(a["branch_id"] or p.branch_id or "")
        c.execute("INSERT OR IGNORE INTO sync_events(business_id,device_id,branch_id,event_key,event_type,payload,created_at,synced_at) VALUES(?,?,?,?,?,?,?,?)",(a["business_id"],p.device_id,branch,p.event_key,p.event_type,json.dumps(p.payload,default=str),p.created_at,iso()))
        if p.event_type=="notification.created":
            c.execute("INSERT INTO notifications(business_id,branch_id,kind,title,message,severity,created_at) VALUES(?,?,?,?,?,?,?)",(a["business_id"],branch,p.payload.get("kind","info"),p.payload.get("title","Notification"),p.payload.get("message",""),p.payload.get("severity","info"),p.created_at))
        c.execute("UPDATE activations SET last_seen=? WHERE device_id=?",(iso(),p.device_id))
    # Only the disposable acceptance fixture can claim immediate reconciliation.
    # The production Master-owned Yola web bridge persists inbox events but
    # must not call them reconciled until stock/journals actually converge.
    return {"ok":True,"reconciled":not master.enabled()}

@app.get("/mobile")
def mobile_page(): return FileResponse(ROOT/"mobile.html")
@app.get("/admin")
def admin_page():
    if master.enabled():
        from fastapi.responses import HTMLResponse
        return HTMLResponse('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Yola · DG Tech Master Control</title><body style="font:16px system-ui;background:#07182b;color:white;padding:9vh 7vw"><h1>Yola</h1><p>Powered by Double Gee Tech</p><h2>Master Control is the only activation authority.</h2><p>Approve or suspend Yola business accounts in your existing DG Tech Master Control portal.</p><a style="color:#92d7ff" href="https://dg-tech-master-control.vercel.app/">Open DG Tech Master Control →</a></body></html>')
    return FileResponse(ROOT/"admin.html")


def mobile_events(c:sqlite3.Connection,business_id:str,event_type:str,limit:int=200):
    return c.execute("SELECT * FROM sync_events WHERE business_id=? AND event_type=? ORDER BY id DESC LIMIT ?",(business_id,event_type,limit)).fetchall()

def fold_latest(events,key_fn):
    out={}
    for e in events:
        p=json.loads(e["payload"]); key=key_fn(e,p)
        if key not in out: out[key]=p|{"branch_id":e["branch_id"],"created_at":e["created_at"]}
    return list(out.values())

@app.get("/api/mobile/summary/{business_id}")
def mobile_summary(business_id:str,x_owner_token:str=Header(default="")):
    with db() as c:
        b=owner_auth(c,business_id,x_owner_token); snaps=fold_latest(mobile_events(c,business_id,"dashboard.snapshot",100),lambda e,p:e["branch_id"])
        recent=[]
        for e in mobile_events(c,business_id,"sale.completed",100):
            p=json.loads(e["payload"]); recent.append(p|{"branch_id":e["branch_id"],"created_at":e["created_at"]})
        today=datetime.now().strftime("%Y-%m-%d"); recent_today=[x for x in recent if str(x["created_at"]).startswith(today)]
        # Snapshot values are authoritative per active branch/device; de-duplicate branch by latest snapshot.
        return {"business_name":b["name"],"business_id":business_id,"plan":b["plan"],"today_sales":money(sum(x.get("today_sales",0) for x in snaps)),"today_profit":money(sum(x.get("today_profit",0) for x in snaps)),"today_expenses":money(sum(x.get("today_expenses",0) for x in snaps)),"cash":money(sum(x.get("cash",0) for x in snaps)),"stock_value":money(sum(x.get("stock_value",0) for x in snaps)),"low_stock":sum(int(x.get("low_stock",0)) for x in snaps),"receivables":max([money(x.get("receivables",0)) for x in snaps] or [0]),"payables":max([money(x.get("payables",0)) for x in snaps] or [0]),"transactions":sum(int(x.get("transactions",0)) for x in snaps),"branches":snaps,"recent_sales":recent[:30],"today_event_sales":money(sum(x.get("total",0) for x in recent_today))}

@app.get("/api/mobile/data/{business_id}")
def mobile_data(business_id:str,x_owner_token:str=Header(default="")):
    with db() as c:
        owner_auth(c,business_id,x_owner_token)
        products=fold_latest(mobile_events(c,business_id,"stock.changed",600),lambda e,p:f"{e['branch_id']}:{p.get('product_id')}")
        staff=[json.loads(e["payload"])|{"branch_id":e["branch_id"],"created_at":e["created_at"]} for e in mobile_events(c,business_id,"staff.activity",100)]
        expenses=[json.loads(e["payload"])|{"branch_id":e["branch_id"],"created_at":e["created_at"]} for e in mobile_events(c,business_id,"expense.created",100)]
        refunds=[json.loads(e["payload"])|{"branch_id":e["branch_id"],"created_at":e["created_at"]} for e in mobile_events(c,business_id,"refund.created",100)]
        customers=fold_latest(mobile_events(c,business_id,"customer.balance",300),lambda e,p:p.get("customer_id"))
        suppliers=fold_latest(mobile_events(c,business_id,"supplier.balance",300),lambda e,p:p.get("supplier_id"))
        shifts=[json.loads(e["payload"])|{"branch_id":e["branch_id"],"created_at":e["created_at"]} for e in c.execute("SELECT * FROM sync_events WHERE business_id=? AND event_type IN ('shift.opened','shift.closed') ORDER BY id DESC LIMIT 100",(business_id,)).fetchall()]
        notifications=[dict(x) for x in c.execute("SELECT * FROM notifications WHERE business_id=? ORDER BY read,created_at DESC LIMIT 100",(business_id,)).fetchall()]
        return {"products":products,"staff":staff,"expenses":expenses,"refunds":refunds,"customers":customers,"suppliers":suppliers,"shifts":shifts,"notifications":notifications}

# ---------- Remote approvals ----------
@app.post("/api/approvals")
def create_approval(p:ApprovalIn):
    with db() as c:
        a,_=auth_license(c,p.device_id,p.license_token); aid="APR-"+uuid.uuid4().hex[:12].upper(); branch=str(a["branch_id"] or p.branch_id or ""); c.execute("INSERT INTO approvals(id,business_id,device_id,branch_id,request_type,requested_by,details,status,created_at) VALUES(?,?,?,?,?,?,?,'pending',?)",(aid,a["business_id"],p.device_id,branch,p.request_type,p.requested_by,json.dumps(p.details),iso())); c.execute("INSERT INTO notifications(business_id,branch_id,kind,title,message,severity,created_at) VALUES(?,?,?,?,?,?,?)",(a["business_id"],branch,"approval",f"{p.request_type.title()} approval",f"{p.requested_by} requested approval.","warning",iso())); return {"id":aid,"status":"pending"}

@app.get("/api/approvals/{approval_id}/status")
def approval_status(approval_id:str,x_license_token:str=Header(default="")):
    payload=verify_signed_token(x_license_token)
    with db() as c:
        activation,_=auth_license(c,str(payload.get('device_id') or ''),x_license_token)
        business_id=activation['business_id']
        a=c.execute("SELECT * FROM approvals WHERE id=? AND business_id=?",(approval_id,business_id)).fetchone()
        if not a: raise HTTPException(status_code=404,detail="Approval request not found")
        return {"id":a["id"],"request_type":a["request_type"],"status":a["status"],"resolved_at":a["resolved_at"]}

@app.get("/api/mobile/approvals/{business_id}")
def mobile_approvals(business_id:str,x_owner_token:str=Header(default="")):
    with db() as c:
        owner_auth(c,business_id,x_owner_token); return [dict(r)|{"details":json.loads(r["details"])} for r in c.execute("SELECT * FROM approvals WHERE business_id=? ORDER BY CASE status WHEN 'pending' THEN 0 ELSE 1 END,created_at DESC LIMIT 100",(business_id,)).fetchall()]

@app.post("/api/mobile/approvals/{business_id}/{approval_id}/{decision}")
def resolve_approval(business_id:str,approval_id:str,decision:str,x_owner_token:str=Header(default="")):
    if decision not in {"approve","deny"}: raise HTTPException(status_code=422,detail="Decision must be approve or deny")
    with db() as c:
        owner_auth(c,business_id,x_owner_token); a=c.execute("SELECT * FROM approvals WHERE id=? AND business_id=?",(approval_id,business_id)).fetchone()
        if not a: raise HTTPException(status_code=404,detail="Approval request not found")
        status="approved" if decision=="approve" else "denied"; c.execute("UPDATE approvals SET status=?,resolved_at=?,resolved_by='Owner' WHERE id=?",(status,iso(),approval_id)); return {"id":approval_id,"status":status}

# ---------- Encrypted backup store ----------
@app.post("/api/backups")
def upload_backup(p:BackupIn):
    raw=base64.b64decode(p.data_b64)
    if len(raw)>80*1024*1024: raise HTTPException(status_code=413,detail="Backup too large")
    with db() as c:
        a,_=auth_license(c,p.device_id,p.license_token); cur=c.execute("INSERT INTO backups(business_id,device_id,name,data,created_at,uploaded_at) VALUES(?,?,?,?,?,?)",(a["business_id"],p.device_id,p.name,raw,p.created_at,iso())); return {"id":cur.lastrowid,"name":p.name,"size":len(raw)}

@app.get("/api/backups")
def list_backups(x_device_id:str=Header(default=""),x_license_token:str=Header(default="")):
    with db() as c:
        a,_=auth_license(c,x_device_id,x_license_token); return [{"id":r["id"],"name":r["name"],"created_at":r["created_at"],"uploaded_at":r["uploaded_at"],"size":len(r["data"])} for r in c.execute("SELECT * FROM backups WHERE business_id=? ORDER BY id DESC LIMIT 50",(a["business_id"],)).fetchall()]

@app.get("/api/backups/{backup_id}")
def get_backup(backup_id:int,x_device_id:str=Header(default=""),x_license_token:str=Header(default="")):
    with db() as c:
        a,_=auth_license(c,x_device_id,x_license_token); r=c.execute("SELECT * FROM backups WHERE id=? AND business_id=?",(backup_id,a["business_id"])).fetchone()
        if not r: raise HTTPException(status_code=404,detail="Backup not found")
        return {"id":r["id"],"name":r["name"],"data_b64":base64.b64encode(r["data"]).decode(),"created_at":r["created_at"]}

# ---------- Signed release metadata ----------
@app.get("/api/version/latest")
def latest_release(x_license_token:str=Header(default="")):
    if x_license_token: verify_signed_token(x_license_token)
    with db() as c:
        r=c.execute("SELECT * FROM releases ORDER BY id DESC LIMIT 1").fetchone(); return dict(r) if r else {"version":"","url":"","sha256":"","signature":"","critical":0,"notes":""}

@app.post("/api/admin/releases")
def add_release(p:ReleaseIn,x_admin_key:str=Header(default="")):
    admin_guard(x_admin_key)
    if len(p.sha256)!=64: raise HTTPException(status_code=422,detail="A SHA-256 hex digest is required")
    sig=base64.b64encode(PRIVATE_KEY.sign(p.sha256.encode())).decode()
    with db() as c:
        c.execute("INSERT OR REPLACE INTO releases(version,url,sha256,signature,critical,notes,created_at) VALUES(?,?,?,?,?,?,?)",(p.version,p.url,p.sha256,sig,int(p.critical),p.notes,iso()))
    return {"version":p.version,"signature":sig}

if __name__=="__main__":
    import uvicorn
    uvicorn.run(app,host="0.0.0.0",port=int(os.getenv("DG_CLOUD_PORT","8790")))