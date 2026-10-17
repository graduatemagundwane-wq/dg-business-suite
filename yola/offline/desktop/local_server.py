from __future__ import annotations

import base64
import csv
import hashlib
import io
import json
import os
import platform
import secrets
import shutil
import smtplib
import sqlite3
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zipfile
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from email.message import EmailMessage
from pathlib import Path
from typing import Any, Callable, Optional

from cryptography.fernet import Fernet, InvalidToken
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from fastapi import Depends, FastAPI, Header, HTTPException, UploadFile, File
from fastapi.responses import FileResponse, HTMLResponse, Response, StreamingResponse
from fastapi.staticfiles import StaticFiles
from openpyxl import Workbook
from pydantic import BaseModel, Field
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle
from reportlab.lib import colors

ROOT = Path(__file__).resolve().parent
APP_ROOT = ROOT.parent
# PyInstaller one-file extracts bundled data into sys._MEIPASS. Source runs keep
# using desktop/static. Supporting both prevents blank/stuck packaged windows.
BUNDLE_ROOT = Path(getattr(sys, "_MEIPASS", ROOT))
STATIC_DIR = (BUNDLE_ROOT / "static") if (BUNDLE_ROOT / "static").exists() else (ROOT / "static")
VERSION_FILE = (BUNDLE_ROOT / "VERSION") if (BUNDLE_ROOT / "VERSION").exists() else ((ROOT / "VERSION") if (ROOT / "VERSION").exists() else (APP_ROOT / "VERSION"))
VERSION = VERSION_FILE.read_text(encoding="utf-8").strip() if VERSION_FILE.exists() else "3.0.0"

if os.getenv("DG_POS_DATA_DIR"):
    DATA_DIR = Path(os.environ["DG_POS_DATA_DIR"]).expanduser().resolve()
elif platform.system().lower() == "windows":
    DATA_DIR = (Path(os.getenv("LOCALAPPDATA", str(Path.home()))) / "Double Gee Tech" / "Yola").resolve()
else:
    DATA_DIR = (APP_ROOT / "data").resolve()
DATA_DIR.mkdir(parents=True, exist_ok=True)
MEDIA_DIR = DATA_DIR / "media"
MEDIA_DIR.mkdir(parents=True, exist_ok=True)
BACKUP_DIR = DATA_DIR / "backups"
BACKUP_DIR.mkdir(parents=True, exist_ok=True)
DB_PATH = DATA_DIR / "dgpos.db"
DEVICE_PATH = DATA_DIR / "device.json"
UPDATE_DIR = DATA_DIR / "updates"
UPDATE_DIR.mkdir(parents=True, exist_ok=True)

# Yola's API is NOT the legacy dg-pos-control-center backend. A release must
# explicitly configure its own compatible hosted endpoint and signing key.
# Invalid reserved address means a misconfigured installation fails closed.
# The immutable public cloud endpoint must be bundled into each official EXE.
# Do not ship a customer client pointing at legacy POS control servers.
BUNDLED_ENDPOINT_FILE = BUNDLE_ROOT / "cloud_url.txt"
BUNDLED_ENDPOINT = BUNDLED_ENDPOINT_FILE.read_text(encoding="utf-8").strip() if BUNDLED_ENDPOINT_FILE.exists() else ""
DG_CLOUD_URL = (BUNDLED_ENDPOINT or os.getenv("DG_CLOUD_URL", "https://yola-cloud.example.invalid")).rstrip("/")
# Every Windows release must pin the public signing key of the DG Tech master.
# Runtime environment overrides are allowed ONLY for source-level acceptance QA.
TRUSTED_PUBLIC_KEY_FILE = BUNDLE_ROOT / "license_public_key.b64"
LICENSE_GRACE_DAYS = int(os.getenv("DG_POS_LICENSE_GRACE_DAYS", "3"))

app = FastAPI(title="Yola Desktop", version=VERSION)
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")
app.mount("/media", StaticFiles(directory=str(MEDIA_DIR)), name="media")


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: Optional[datetime] = None) -> str:
    return (dt or utcnow()).isoformat()


def today_str() -> str:
    return datetime.now().strftime("%Y-%m-%d")


def money(v: Any) -> float:
    return round(float(v or 0) + 1e-9, 2)


def json_load(s: Any, default: Any = None) -> Any:
    if s in (None, ""):
        return default
    try:
        return json.loads(s)
    except Exception:
        return default


def machine_fingerprint() -> str:
    install_id = None
    device_doc: dict[str, Any] = {}
    if DEVICE_PATH.exists():
        try:
            device_doc = json.loads(DEVICE_PATH.read_text(encoding="utf-8"))
            install_id = device_doc.get("install_id")
        except Exception:
            pass
    if not install_id:
        install_id = str(uuid.uuid4())
        device_doc["install_id"] = install_id
        DEVICE_PATH.write_text(json.dumps(device_doc, indent=2), encoding="utf-8")
    machine_guid = ""
    if platform.system().lower() == "windows":
        try:
            import winreg  # type: ignore
            key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Cryptography")
            machine_guid, _ = winreg.QueryValueEx(key, "MachineGuid")
        except Exception:
            pass
    raw = "|".join([install_id, machine_guid, platform.node(), str(uuid.getnode()), platform.system(), platform.machine()])
    return hashlib.sha256(raw.encode()).hexdigest()[:48]


DEVICE_ID = machine_fingerprint()


def device_cipher() -> Fernet:
    key = hashlib.sha256(("DG-POS-LICENCE|" + DEVICE_ID).encode()).digest()
    return Fernet(base64.urlsafe_b64encode(key))


def enc_secret(value: str) -> str:
    return device_cipher().encrypt(value.encode()).decode()


def dec_secret(value: str | None) -> str:
    if not value:
        return ""
    try:
        return device_cipher().decrypt(value.encode()).decode()
    except InvalidToken:
        return ""


@contextmanager
def db():
    conn = sqlite3.connect(DB_PATH, timeout=20)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys=ON")
    conn.execute("PRAGMA journal_mode=WAL")
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def add_column(c: sqlite3.Connection, table: str, column: str, definition: str) -> None:
    cols = {r[1] for r in c.execute(f"PRAGMA table_info({table})").fetchall()}
    if column not in cols:
        c.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")


def init_db() -> None:
    with db() as c:
        c.executescript("""
        CREATE TABLE IF NOT EXISTS app_meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS license_cache(
          id INTEGER PRIMARY KEY CHECK(id=1), business_id TEXT,business_name TEXT,status TEXT NOT NULL DEFAULT 'inactive',
          token_enc TEXT, public_key TEXT, last_verified_at TEXT,valid_until TEXT,request_code TEXT,claim_secret TEXT,
          plan TEXT DEFAULT 'standard', branch_id INTEGER, branch_name TEXT, device_limit INTEGER DEFAULT 1
        );
        INSERT OR IGNORE INTO license_cache(id,status) VALUES(1,'inactive');
        CREATE TABLE IF NOT EXISTS settings(section TEXT NOT NULL,key TEXT NOT NULL,value TEXT NOT NULL,PRIMARY KEY(section,key));
        CREATE TABLE IF NOT EXISTS branches(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,location TEXT DEFAULT '',active INTEGER DEFAULT 1,cloud_branch_id TEXT,created_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,role TEXT NOT NULL,pin_hash TEXT NOT NULL,permissions TEXT DEFAULT '[]',active INTEGER DEFAULT 1,force_change INTEGER DEFAULT 0,created_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS user_sessions(id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER NOT NULL,token_hash TEXT UNIQUE NOT NULL,expires_at TEXT NOT NULL,created_at TEXT NOT NULL,FOREIGN KEY(user_id) REFERENCES users(id));
        CREATE TABLE IF NOT EXISTS products(
          id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,sku TEXT UNIQUE,barcode TEXT,category TEXT DEFAULT 'General',unit TEXT DEFAULT 'ea',
          cost_price REAL DEFAULT 0,sell_price REAL DEFAULT 0,wholesale_price REAL DEFAULT 0,quantity REAL DEFAULT 0,min_stock REAL DEFAULT 0,
          supplier TEXT,expiry_date TEXT,image_path TEXT,tax_rate REAL DEFAULT 0,track_batch INTEGER DEFAULT 0,active INTEGER DEFAULT 1,created_at TEXT NOT NULL,updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS branch_stock(branch_id INTEGER NOT NULL,product_id INTEGER NOT NULL,quantity REAL DEFAULT 0,min_stock REAL DEFAULT 0,PRIMARY KEY(branch_id,product_id),FOREIGN KEY(branch_id) REFERENCES branches(id),FOREIGN KEY(product_id) REFERENCES products(id));
        CREATE TABLE IF NOT EXISTS product_batches(id INTEGER PRIMARY KEY AUTOINCREMENT,branch_id INTEGER NOT NULL,product_id INTEGER NOT NULL,batch_no TEXT NOT NULL,expiry_date TEXT,quantity REAL DEFAULT 0,created_at TEXT NOT NULL,FOREIGN KEY(branch_id) REFERENCES branches(id),FOREIGN KEY(product_id) REFERENCES products(id));
        CREATE TABLE IF NOT EXISTS customers(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,phone TEXT,email TEXT,address TEXT,credit_limit REAL DEFAULT 0,balance REAL DEFAULT 0,loyalty_points REAL DEFAULT 0,created_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS customer_payments(id INTEGER PRIMARY KEY AUTOINCREMENT,customer_id INTEGER NOT NULL,amount REAL NOT NULL,payment_method TEXT NOT NULL,reference TEXT,branch_id INTEGER,user_id INTEGER,created_at TEXT NOT NULL,FOREIGN KEY(customer_id) REFERENCES customers(id));
        CREATE TABLE IF NOT EXISTS suppliers(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,phone TEXT,email TEXT,address TEXT,balance REAL DEFAULT 0,created_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS supplier_payments(id INTEGER PRIMARY KEY AUTOINCREMENT,supplier_id INTEGER NOT NULL,amount REAL NOT NULL,payment_method TEXT NOT NULL,reference TEXT,branch_id INTEGER,user_id INTEGER,created_at TEXT NOT NULL,FOREIGN KEY(supplier_id) REFERENCES suppliers(id));
        CREATE TABLE IF NOT EXISTS sales(
          id INTEGER PRIMARY KEY AUTOINCREMENT,receipt_no TEXT UNIQUE NOT NULL,branch_id INTEGER,user_id INTEGER,subtotal REAL NOT NULL,discount REAL DEFAULT 0,tax_total REAL DEFAULT 0,total REAL NOT NULL,cost_total REAL NOT NULL,gross_profit REAL NOT NULL,
          payment_method TEXT NOT NULL,amount_paid REAL NOT NULL,change_due REAL DEFAULT 0,customer_id INTEGER,status TEXT DEFAULT 'completed',sale_type TEXT DEFAULT 'retail',note TEXT DEFAULT '',created_at TEXT NOT NULL,
          FOREIGN KEY(customer_id) REFERENCES customers(id)
        );
        CREATE TABLE IF NOT EXISTS sale_items(id INTEGER PRIMARY KEY AUTOINCREMENT,sale_id INTEGER NOT NULL,product_id INTEGER NOT NULL,product_name TEXT NOT NULL,quantity REAL NOT NULL,unit_price REAL NOT NULL,unit_cost REAL NOT NULL,discount REAL DEFAULT 0,tax_rate REAL DEFAULT 0,tax_amount REAL DEFAULT 0,line_total REAL NOT NULL,FOREIGN KEY(sale_id) REFERENCES sales(id) ON DELETE CASCADE,FOREIGN KEY(product_id) REFERENCES products(id));
        CREATE TABLE IF NOT EXISTS sale_payments(id INTEGER PRIMARY KEY AUTOINCREMENT,sale_id INTEGER NOT NULL,method TEXT NOT NULL,amount REAL NOT NULL,reference TEXT,FOREIGN KEY(sale_id) REFERENCES sales(id) ON DELETE CASCADE);
        CREATE TABLE IF NOT EXISTS held_sales(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT,branch_id INTEGER,user_id INTEGER,payload TEXT NOT NULL,created_at TEXT NOT NULL,updated_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS expenses(id INTEGER PRIMARY KEY AUTOINCREMENT,category TEXT NOT NULL,amount REAL NOT NULL,payment_method TEXT DEFAULT 'Cash',description TEXT,supplier_id INTEGER,branch_id INTEGER,user_id INTEGER,receipt_path TEXT,recurring INTEGER DEFAULT 0,recurrence TEXT,next_due TEXT,created_at TEXT NOT NULL,FOREIGN KEY(supplier_id) REFERENCES suppliers(id));
        CREATE TABLE IF NOT EXISTS purchases(id INTEGER PRIMARY KEY AUTOINCREMENT,supplier_id INTEGER,branch_id INTEGER,user_id INTEGER,reference TEXT,invoice_no TEXT,total REAL NOT NULL,amount_paid REAL NOT NULL,status TEXT DEFAULT 'received',created_at TEXT NOT NULL,FOREIGN KEY(supplier_id) REFERENCES suppliers(id));
        CREATE TABLE IF NOT EXISTS purchase_items(id INTEGER PRIMARY KEY AUTOINCREMENT,purchase_id INTEGER NOT NULL,product_id INTEGER NOT NULL,quantity REAL NOT NULL,unit_cost REAL NOT NULL,line_total REAL NOT NULL,batch_no TEXT,expiry_date TEXT,FOREIGN KEY(purchase_id) REFERENCES purchases(id) ON DELETE CASCADE,FOREIGN KEY(product_id) REFERENCES products(id));
        CREATE TABLE IF NOT EXISTS stock_movements(id INTEGER PRIMARY KEY AUTOINCREMENT,branch_id INTEGER,product_id INTEGER NOT NULL,user_id INTEGER,movement_type TEXT NOT NULL,quantity REAL NOT NULL,batch_no TEXT,reference TEXT,reason TEXT,created_at TEXT NOT NULL,FOREIGN KEY(product_id) REFERENCES products(id));
        CREATE TABLE IF NOT EXISTS documents(id INTEGER PRIMARY KEY AUTOINCREMENT,doc_type TEXT NOT NULL,doc_no TEXT UNIQUE NOT NULL,customer_id INTEGER,branch_id INTEGER,user_id INTEGER,status TEXT DEFAULT 'draft',subtotal REAL DEFAULT 0,discount REAL DEFAULT 0,tax_total REAL DEFAULT 0,total REAL DEFAULT 0,amount_paid REAL DEFAULT 0,due_date TEXT,note TEXT,converted_sale_id INTEGER,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,FOREIGN KEY(customer_id) REFERENCES customers(id));
        CREATE TABLE IF NOT EXISTS document_items(id INTEGER PRIMARY KEY AUTOINCREMENT,document_id INTEGER NOT NULL,product_id INTEGER,description TEXT NOT NULL,quantity REAL NOT NULL,unit_price REAL NOT NULL,tax_rate REAL DEFAULT 0,line_total REAL NOT NULL,FOREIGN KEY(document_id) REFERENCES documents(id) ON DELETE CASCADE);
        CREATE TABLE IF NOT EXISTS document_payments(id INTEGER PRIMARY KEY AUTOINCREMENT,document_id INTEGER NOT NULL,amount REAL NOT NULL,payment_method TEXT NOT NULL,reference TEXT,created_at TEXT NOT NULL,FOREIGN KEY(document_id) REFERENCES documents(id) ON DELETE CASCADE);
        CREATE TABLE IF NOT EXISTS returns(id INTEGER PRIMARY KEY AUTOINCREMENT,sale_id INTEGER NOT NULL,branch_id INTEGER,user_id INTEGER,refund_total REAL NOT NULL,refund_method TEXT,reason TEXT,created_at TEXT NOT NULL,FOREIGN KEY(sale_id) REFERENCES sales(id));
        CREATE TABLE IF NOT EXISTS return_items(id INTEGER PRIMARY KEY AUTOINCREMENT,return_id INTEGER NOT NULL,sale_item_id INTEGER NOT NULL,product_id INTEGER NOT NULL,quantity REAL NOT NULL,unit_price REAL NOT NULL,unit_cost REAL NOT NULL,restock INTEGER DEFAULT 1,line_total REAL NOT NULL,FOREIGN KEY(return_id) REFERENCES returns(id) ON DELETE CASCADE);
        CREATE TABLE IF NOT EXISTS cash_shifts(id INTEGER PRIMARY KEY AUTOINCREMENT,branch_id INTEGER NOT NULL,user_id INTEGER NOT NULL,opening_cash REAL DEFAULT 0,opened_at TEXT NOT NULL,closed_at TEXT,expected_cash REAL,actual_cash REAL,difference REAL,status TEXT DEFAULT 'open');
        CREATE TABLE IF NOT EXISTS cash_movements(id INTEGER PRIMARY KEY AUTOINCREMENT,shift_id INTEGER,branch_id INTEGER,user_id INTEGER,movement_type TEXT NOT NULL,amount REAL NOT NULL,reason TEXT,created_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS audit_log(id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER,branch_id INTEGER,action TEXT NOT NULL,entity_type TEXT,entity_id TEXT,details TEXT,previous_json TEXT,new_json TEXT,created_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS notifications(id INTEGER PRIMARY KEY AUTOINCREMENT,kind TEXT,title TEXT,message TEXT,severity TEXT DEFAULT 'info',read INTEGER DEFAULT 0,cloud_id TEXT,created_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS accounts(id INTEGER PRIMARY KEY AUTOINCREMENT,code TEXT UNIQUE NOT NULL,name TEXT NOT NULL,account_type TEXT NOT NULL,active INTEGER DEFAULT 1);
        CREATE TABLE IF NOT EXISTS journal_entries(id INTEGER PRIMARY KEY AUTOINCREMENT,entry_no TEXT UNIQUE NOT NULL,branch_id INTEGER,user_id INTEGER,source_type TEXT,source_id TEXT,memo TEXT,created_at TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS journal_lines(id INTEGER PRIMARY KEY AUTOINCREMENT,entry_id INTEGER NOT NULL,account_code TEXT NOT NULL,debit REAL DEFAULT 0,credit REAL DEFAULT 0,description TEXT,FOREIGN KEY(entry_id) REFERENCES journal_entries(id) ON DELETE CASCADE);
        CREATE TABLE IF NOT EXISTS budgets(
          id INTEGER PRIMARY KEY AUTOINCREMENT,branch_id INTEGER NOT NULL,year_month TEXT NOT NULL,
          category TEXT NOT NULL,amount_cents INTEGER NOT NULL CHECK(amount_cents>=0),
          updated_by INTEGER,updated_at TEXT NOT NULL,
          UNIQUE(branch_id,year_month,category));
        CREATE TABLE IF NOT EXISTS bank_statement_lines(
          id INTEGER PRIMARY KEY AUTOINCREMENT,branch_id INTEGER NOT NULL,bank_account TEXT NOT NULL,
          source_fingerprint TEXT NOT NULL,posted_date TEXT NOT NULL,description TEXT NOT NULL,
          amount_cents INTEGER NOT NULL,reference TEXT DEFAULT '',currency TEXT NOT NULL DEFAULT 'USD',
          matched_entry_id INTEGER,imported_by INTEGER,imported_at TEXT NOT NULL,
          UNIQUE(branch_id,bank_account,source_fingerprint),
          FOREIGN KEY(matched_entry_id) REFERENCES journal_entries(id));
        CREATE TABLE IF NOT EXISTS approval_requests(id INTEGER PRIMARY KEY AUTOINCREMENT,cloud_id TEXT,request_type TEXT NOT NULL,details TEXT NOT NULL,status TEXT DEFAULT 'pending',created_at TEXT NOT NULL,resolved_at TEXT);
        CREATE TABLE IF NOT EXISTS sync_queue(id INTEGER PRIMARY KEY AUTOINCREMENT,event_key TEXT UNIQUE NOT NULL,event_type TEXT NOT NULL,payload TEXT NOT NULL,branch_id INTEGER,created_at TEXT NOT NULL,synced_at TEXT,attempts INTEGER DEFAULT 0,last_error TEXT);
        """)
        # Migrate v1 columns safely.
        for table, col, definition in [
            ("license_cache","token_enc","TEXT"),("license_cache","lease_token_enc","TEXT"),("license_cache","public_key","TEXT"),("license_cache","plan","TEXT DEFAULT 'standard'"),("license_cache","branch_id","INTEGER"),("license_cache","branch_name","TEXT"),("license_cache","device_limit","INTEGER DEFAULT 1"),
            ("products","unit","TEXT DEFAULT 'ea'"),("products","image_path","TEXT"),("products","tax_rate","REAL DEFAULT 0"),("products","track_batch","INTEGER DEFAULT 0"),
            ("customers","email","TEXT"),("customers","address","TEXT"),("customers","loyalty_points","REAL DEFAULT 0"),
            ("suppliers","email","TEXT"),("suppliers","address","TEXT"),
            ("sales","idempotency_key","TEXT"),("sales","branch_id","INTEGER"),("sales","user_id","INTEGER"),("sales","tax_total","REAL DEFAULT 0"),("sales","sale_type","TEXT DEFAULT 'retail'"),("sales","note","TEXT DEFAULT ''"),
            ("sale_items","discount","REAL DEFAULT 0"),("sale_items","tax_rate","REAL DEFAULT 0"),("sale_items","tax_amount","REAL DEFAULT 0"),
            ("expenses","branch_id","INTEGER"),("expenses","user_id","INTEGER"),("expenses","receipt_path","TEXT"),("expenses","recurring","INTEGER DEFAULT 0"),("expenses","recurrence","TEXT"),("expenses","next_due","TEXT"),
            ("purchases","branch_id","INTEGER"),("purchases","user_id","INTEGER"),("purchases","invoice_no","TEXT"),("purchases","status","TEXT DEFAULT 'received'"),
            ("purchase_items","batch_no","TEXT"),("purchase_items","expiry_date","TEXT"),
            ("stock_movements","branch_id","INTEGER"),("stock_movements","user_id","INTEGER"),("stock_movements","batch_no","TEXT"),("stock_movements","reason","TEXT"),
            ("audit_log","user_id","INTEGER"),("audit_log","branch_id","INTEGER"),("audit_log","entity_type","TEXT"),("audit_log","entity_id","TEXT"),("audit_log","previous_json","TEXT"),("audit_log","new_json","TEXT")
        ]:
            add_column(c, table, col, definition)
        c.execute("CREATE UNIQUE INDEX IF NOT EXISTS ux_sales_idempotency_key ON sales(idempotency_key) WHERE idempotency_key IS NOT NULL")
        # Convert legacy plaintext token if present.
        cols = {r[1] for r in c.execute("PRAGMA table_info(license_cache)").fetchall()}
        if "license_token" in cols:
            row = c.execute("SELECT license_token,token_enc FROM license_cache WHERE id=1").fetchone()
            if row and row[0] and not row[1]:
                c.execute("UPDATE license_cache SET token_enc=?,license_token=NULL WHERE id=1", (enc_secret(row[0]),))
        if not c.execute("SELECT 1 FROM branches LIMIT 1").fetchone():
            c.execute("INSERT INTO branches(name,location,created_at) VALUES('Main Branch','',?)", (iso(),))
        default_branch = c.execute("SELECT id FROM branches ORDER BY id LIMIT 1").fetchone()[0]
        # Bring v1 product quantity into branch stock once.
        for p in c.execute("SELECT id,quantity,min_stock FROM products").fetchall():
            c.execute("INSERT OR IGNORE INTO branch_stock(branch_id,product_id,quantity,min_stock) VALUES(?,?,?,?)", (default_branch,p["id"],p["quantity"] or 0,p["min_stock"] or 0))
        account_seed = [
            ("1000","Cash","asset"),("1010","EcoCash","asset"),("1020","Bank / Card","asset"),("1100","Accounts Receivable","asset"),("1200","Inventory","asset"),
            ("2000","Accounts Payable","liability"),("2200","Tax Payable","liability"),("3000","Owner Equity","equity"),("4000","Sales Revenue","income"),("4100","Other Income","income"),
            ("5000","Cost of Goods Sold","expense"),("6000","Operating Expenses","expense")
        ]
        c.executemany("INSERT OR IGNORE INTO accounts(code,name,account_type) VALUES(?,?,?)", account_seed)
        defaults = {
            ("business","name"):"Yola Business",("business","phone"):"",("business","address"):"",("business","email"):"",("business","logo"):"",
            ("receipt","footer"):"Thank you for your business",("receipt","paper"):"thermal",("receipt","show_qr"):"true",
            ("tax","enabled"):"false",("tax","default_rate"):"0",("tax","mode"):"exclusive",
            ("payments","cash"):"true",("payments","ecocash"):"true",("payments","card"):"true",("payments","bank"):"true",
            ("sales","cashier_discount_limit"):"5",("sales","loyalty_percent"):"0",
            ("printer","name"):"",("printer","receipt_width"):"80",("printer","cash_drawer"):"false",
            ("backup","automatic"):"true",("backup","cloud"):"true",("backup","last_auto"):"",
            ("accounting","advanced"):"false",("updates","automatic_check"):"true"
        }
        c.executemany("INSERT OR IGNORE INTO settings(section,key,value) VALUES(?,?,?)", [(s,k,v) for (s,k),v in defaults.items()])
        c.execute("INSERT OR REPLACE INTO app_meta(key,value) VALUES('schema_version','2.0.0')")


init_db()


def setting(section: str, key: str, default: str = "") -> str:
    with db() as c:
        r = c.execute("SELECT value FROM settings WHERE section=? AND key=?", (section,key)).fetchone()
    return r[0] if r else default


def set_setting(section: str, key: str, value: Any) -> None:
    with db() as c:
        c.execute("INSERT OR REPLACE INTO settings(section,key,value) VALUES(?,?,?)", (section,key,str(value)))


def cloud_json(path: str, payload: Optional[dict[str, Any]] = None, method: str = "GET", headers: Optional[dict[str, str]] = None, timeout: int = 7) -> Any:
    body = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(DG_CLOUD_URL + path, data=body, method=method, headers={"Content-Type":"application/json", **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as res:
            raw = res.read()
            if "application/json" in res.headers.get("Content-Type",""):
                return json.loads(raw.decode())
            return raw
    except urllib.error.HTTPError as e:
        if e.code == 404 and path.startswith(("/api/activation/", "/api/license/", "/api/sync/", "/api/backups", "/api/approvals", "/api/version/")):
            raise HTTPException(
                status_code=503,
                detail="The configured DG Tech Master Control server uses an incompatible POS licensing API. "
                       "A Yola Pro-compatible cloud backend must be deployed and connected before this installation can activate."
            )
        try:
            body=json.loads(e.read().decode())
            detail=body.get("error") or body.get("detail") or body.get("message") or str(e)
        except Exception: detail = str(e)
        raise HTTPException(status_code=e.code, detail=detail)
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"DG Cloud unavailable: {e}")


def read_license() -> dict[str, Any]:
    with db() as c:
        row = c.execute("SELECT * FROM license_cache WHERE id=1").fetchone()
    d = dict(row) if row else {"status":"inactive"}
    d["license_token"] = dec_secret(d.get("token_enc"))
    d["lease_token"] = dec_secret(d.get("lease_token_enc"))
    return d


def trusted_license_public_key() -> str:
    # The test override is *never* honored inside a frozen customer EXE.
    # Source-only acceptance tests need to validate disposable fixture keys.
    if not getattr(sys, "frozen", False) and os.getenv("DG_POS_TEST_TRUSTED_PUBLIC_KEY_B64"):
        text = os.getenv("DG_POS_TEST_TRUSTED_PUBLIC_KEY_B64", "").strip()
    elif TRUSTED_PUBLIC_KEY_FILE.exists():
        text = TRUSTED_PUBLIC_KEY_FILE.read_text(encoding="ascii").strip()
    else:
        text = ""
    try:
        raw = base64.b64decode(text, validate=True)
        if len(raw) == 32:
            Ed25519PublicKey.from_public_bytes(raw)
            return text
    except Exception:
        pass
    raise HTTPException(503, "Yola licence verification public key is not configured. "
                             "Double Gee Tech must provision the official master signing key before use.")


def cached_license_valid() -> bool:
    """Never trust a writable SQLite activation flag by itself.

    Offline sales require a device-bound Ed25519 token, a previously verified
    online approval, an unexpired licence, and a short offline grace window.
    """
    lic = read_license()
    token, public_key = lic.get("license_token"), lic.get("public_key")
    if lic.get("status") != "active" or not token or not public_key:
        return False
    try:
        raw_payload, raw_sig = token.split(".", 1)
        encoded_payload = base64.urlsafe_b64decode(raw_payload + "=" * (-len(raw_payload) % 4))
        signature = base64.urlsafe_b64decode(raw_sig + "=" * (-len(raw_sig) % 4))
        trusted = trusted_license_public_key()
        if not secrets.compare_digest(public_key, trusted):
            return False
        key = Ed25519PublicKey.from_public_bytes(base64.b64decode(trusted))
        key.verify(signature, encoded_payload)
        claims = json.loads(encoded_payload)
        if claims.get("device_id") != DEVICE_ID or claims.get("business_id") != lic.get("business_id"):
            return False
        valid_until = datetime.fromisoformat(claims["valid_until"])
        verified = datetime.fromisoformat(lic["last_verified_at"])
        lease_token=lic.get('lease_token')
        if not lease_token: return False
        lease_parts=lease_token.split('.',1)
        if len(lease_parts)!=2:return False
        lease_bytes=base64.urlsafe_b64decode(lease_parts[0]+"="*(-len(lease_parts[0])%4))
        lease_sig=base64.urlsafe_b64decode(lease_parts[1]+"="*(-len(lease_parts[1])%4))
        key.verify(lease_sig,lease_bytes)
        lease=json.loads(lease_bytes)
        if lease.get('kind')!='yola-offline-lease' or lease.get('device_id')!=DEVICE_ID or lease.get('business_id')!=lic['business_id']:
            return False
        if lease.get('master_installation_id')!=claims.get('master_installation_id'):
            return False
        return (utcnow() <= valid_until and
                utcnow() <= datetime.fromisoformat(lease['offline_until']) and
                utcnow() <= verified + timedelta(days=LICENSE_GRACE_DAYS))
    except Exception:
        return False


def require_license() -> dict[str, Any]:
    lic = read_license()
    if cached_license_valid(): return lic
    raise HTTPException(status_code=423, detail="Yola is not activated, suspended, revoked, or its offline verification period has ended.")

def pin_hash(pin: str, salt: Optional[str] = None) -> str:
    salt = salt or secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac("sha256", pin.encode(), bytes.fromhex(salt), 180000).hex()
    return salt + "$" + digest


def pin_ok(pin: str, stored: str) -> bool:
    try:
        salt, digest = stored.split("$",1)
        return secrets.compare_digest(pin_hash(pin,salt).split("$",1)[1],digest)
    except Exception: return False


def token_hash(s: str) -> str:
    return hashlib.sha256(s.encode()).hexdigest()


def default_permissions(role: str) -> list[str]:
    perms = {
        "owner":["*"],
        "manager":["sell","discount","refund","products","stock","customers","suppliers","purchases","expenses","reports","cash","documents","audit"],
        "cashier":["sell"],
        "accountant":["money","reports","expenses","customers","suppliers","documents","audit"],
        "stock_controller":["products","stock","suppliers","purchases","reports"]
    }
    return perms.get(role,[])


def maximum_permissions(role: str) -> list[str]:
    # Owner can explicitly delegate financial access to a manager, but new
    # managers do not inherit accounting access automatically.
    rights=default_permissions(role)
    return rights + (["money"] if role=="manager" else [])


def current_user(x_session_token: str = Header(default="")) -> dict[str, Any]:
    if not x_session_token:
        raise HTTPException(status_code=401, detail="Staff sign-in required")
    with db() as c:
        r = c.execute("""SELECT u.*,s.expires_at FROM user_sessions s JOIN users u ON u.id=s.user_id
                       WHERE s.token_hash=? AND u.active=1 ORDER BY s.id DESC LIMIT 1""", (token_hash(x_session_token),)).fetchone()
    if not r or utcnow() > datetime.fromisoformat(r["expires_at"]):
        raise HTTPException(status_code=401, detail="Session expired")
    d = dict(r)
    assigned = json_load(d.get("permissions"), []) or default_permissions(d["role"])
    allowed = maximum_permissions(d["role"])
    # Only owners get full access. Managers can never elevate to owners via DB.
    d["permissions"] = [x for x in assigned if x in allowed] if "*" not in allowed else ["*"]
    return d


def access(permission: str) -> Callable:
    def dep(lic: dict = Depends(require_license), user: dict = Depends(current_user)) -> dict[str, Any]:
        perms = user.get("permissions") or default_permissions(user["role"])
        if "*" not in perms and permission not in perms:
            raise HTTPException(status_code=403, detail=f"Permission required: {permission}")
        user["license"] = lic
        return user
    return dep


def branch_id_from(lic: Optional[dict[str,Any]] = None, requested: Optional[int] = None) -> int:
    if requested:
        return int(requested)
    lic = lic or read_license()
    if lic.get("branch_id"):
        return int(lic["branch_id"])
    with db() as c:
        r = c.execute("SELECT id FROM branches WHERE active=1 ORDER BY id LIMIT 1").fetchone()
    return int(r[0])


def audit(c: sqlite3.Connection, action: str, user: Optional[dict]=None, branch_id: Optional[int]=None, entity_type: str="", entity_id: Any="", details: Any=None, previous: Any=None, new: Any=None) -> None:
    c.execute("INSERT INTO audit_log(user_id,branch_id,action,entity_type,entity_id,details,previous_json,new_json,created_at) VALUES(?,?,?,?,?,?,?,?,?)",
              (user.get("id") if user else None, branch_id, action, entity_type, str(entity_id or ""), json.dumps(details or {},default=str), json.dumps(previous,default=str) if previous is not None else None, json.dumps(new,default=str) if new is not None else None, iso()))


def journal(c: sqlite3.Connection, source_type: str, source_id: Any, memo: str, lines: list[tuple[str,float,float,str]], branch_id: int, user_id: Optional[int]) -> int:
    debit = money(sum(x[1] for x in lines)); credit = money(sum(x[2] for x in lines))
    if abs(debit-credit) > 0.01:
        raise HTTPException(status_code=500, detail=f"Accounting entry out of balance: {debit} vs {credit}")
    entry_no = "JE-" + datetime.now().strftime("%Y%m%d") + "-" + uuid.uuid4().hex[:7].upper()
    cur = c.execute("INSERT INTO journal_entries(entry_no,branch_id,user_id,source_type,source_id,memo,created_at) VALUES(?,?,?,?,?,?,?)", (entry_no,branch_id,user_id,source_type,str(source_id),memo,iso()))
    eid = cur.lastrowid
    c.executemany("INSERT INTO journal_lines(entry_id,account_code,debit,credit,description) VALUES(?,?,?,?,?)", [(eid,code,money(dr),money(cr),desc) for code,dr,cr,desc in lines if money(dr) or money(cr)])
    return eid


def payment_account(method: str) -> str:
    m = method.lower()
    if "eco" in m: return "1010"
    if "card" in m or "bank" in m: return "1020"
    return "1000"


def queue_sync(c: sqlite3.Connection, event_type: str, payload: dict[str,Any], branch_id: Optional[int]=None, event_key: Optional[str]=None) -> None:
    key = event_key or f"{event_type}:{uuid.uuid4().hex}"
    c.execute("INSERT OR IGNORE INTO sync_queue(event_key,event_type,payload,branch_id,created_at) VALUES(?,?,?,?,?)", (key,event_type,json.dumps(payload,default=str),branch_id,iso()))


def shared_state_snapshot() -> dict[str, Any]:
    """Compact cloud state for the same Yola business account."""
    lic=read_license(); bid=branch_id_from(lic)
    with db() as c:
        products=[dict(r) for r in c.execute("""SELECT p.id,p.name,p.sku,p.barcode,p.category,p.unit,p.cost_price,p.sell_price,p.wholesale_price,
                   p.min_stock,p.active,COALESCE(bs.quantity,0) quantity
                   FROM products p LEFT JOIN branch_stock bs ON bs.product_id=p.id AND bs.branch_id=?
                   WHERE p.active=1 ORDER BY p.name""",(bid,)).fetchall()]
        customers=[dict(r) for r in c.execute("SELECT id,name,phone,email,balance,credit_limit,loyalty_points FROM customers ORDER BY id DESC LIMIT 500").fetchall()]
        suppliers=[dict(r) for r in c.execute("SELECT id,name,phone,email,balance FROM suppliers ORDER BY id DESC LIMIT 500").fetchall()]
        sales=[dict(r) for r in c.execute("SELECT id,receipt_no,total,payment_method,amount_paid,change_due,created_at,status FROM sales WHERE branch_id=? ORDER BY id DESC LIMIT 300",(bid,)).fetchall()]
        expenses=[dict(r) for r in c.execute("SELECT id,category,amount,payment_method,description,created_at FROM expenses WHERE branch_id=? ORDER BY id DESC LIMIT 300",(bid,)).fetchall()]
        branches=[dict(r) for r in c.execute("SELECT id,name,location,active FROM branches ORDER BY id").fetchall()]
    return {"schema":"dg-pos-shared-v1","business":lic.get("business_name"),"registrationId":lic.get("request_code"),
            "activeBranchId":bid,"branches":branches,"products":products,"customers":customers,"suppliers":suppliers,
            "sales":sales,"expenses":expenses,"updatedAt":iso(),"appVersion":VERSION,"platform":"windows"}


def flush_sync(limit: int = 100) -> dict[str,int]:
    lic=read_license()
    if not cached_license_valid(): return {"synced":0,"pending":0}
    synced=0
    with db() as c:
        rows=[dict(r) for r in c.execute("SELECT * FROM sync_queue WHERE synced_at IS NULL ORDER BY id LIMIT ?",(limit,)).fetchall()]
    for row in rows:
        try:
            ack=cloud_json("/api/sync/event", {"device_id":DEVICE_ID,"license_token":lic["license_token"],
                "event_key":row["event_key"],"event_type":row["event_type"],
                "branch_id":str(row["branch_id"]) if row["branch_id"] is not None else None,
                "payload":json_load(row["payload"],{}),"created_at":row["created_at"]},"POST",timeout=12)
            # A durable cloud inbox is not equivalent to cloud POS/accounting
            # reconciliation. Never mark a sale as synced before confirmed.
            if not ack.get("reconciled"):
                raise RuntimeError("Awaiting verified cloud accounting/inventory reconciliation")
            with db() as c:
                c.execute("UPDATE sync_queue SET synced_at=?,last_error=NULL WHERE id=?",(iso(),row["id"]))
            synced+=1
        except Exception as error:
            with db() as c:
                c.execute("UPDATE sync_queue SET attempts=attempts+1,last_error=? WHERE id=?",(str(error)[:500],row["id"]))
            # Preserve in-order delivery; retry later, no silent data loss.
            break
    # A snapshot is separate from the event queue. Mobile totals use the
    # latest per-branch snapshot; raw sale events alone are insufficient.
    if synced or not rows:
        try:
            bid=branch_id_from(lic)
            with db() as c:
                today=today_str()
                sale=c.execute("SELECT COALESCE(SUM(total),0) t,COALESCE(SUM(gross_profit),0) p,COUNT(*) n FROM sales WHERE branch_id=? AND substr(created_at,1,10)=?",(bid,today)).fetchone()
                ex=c.execute("SELECT COALESCE(SUM(amount),0) FROM expenses WHERE branch_id=? AND substr(created_at,1,10)=?",(bid,today)).fetchone()[0]
                stock=c.execute("SELECT COALESCE(SUM(bs.quantity*p.cost_price),0) value,SUM(CASE WHEN bs.quantity<=bs.min_stock THEN 1 ELSE 0 END) low FROM branch_stock bs JOIN products p ON p.id=bs.product_id WHERE bs.branch_id=? AND p.active=1",(bid,)).fetchone()
                ar=c.execute("SELECT COALESCE(SUM(balance),0) FROM customers").fetchone()[0]
                ap=c.execute("SELECT COALESCE(SUM(balance),0) FROM suppliers").fetchone()[0]
                cash=next((x["balance"] for x in account_balances(c,branch_id=bid) if x["code"]=="1000"),0)
                branch=c.execute("SELECT name FROM branches WHERE id=?",(bid,)).fetchone()
            snapshot={"branch":branch[0] if branch else "Main Branch", "today_sales":money(sale["t"]),
                "today_profit":money(sale["p"]-ex),"today_expenses":money(ex),"cash":money(cash),
                "stock_value":money(stock["value"]),"low_stock":int(stock["low"] or 0),
                "receivables":money(ar),"payables":money(ap),"transactions":int(sale["n"])}
            cloud_json("/api/sync/event",{"device_id":DEVICE_ID,"license_token":lic["license_token"],
                "event_key":f"dashboard:{DEVICE_ID}:{uuid.uuid4().hex}","event_type":"dashboard.snapshot",
                "branch_id":str(bid),"payload":snapshot,"created_at":iso()},"POST",timeout=12)
        except Exception:
            pass  # queued business events are still retryable
    with db() as c:
        pending=c.execute("SELECT COUNT(*) FROM sync_queue WHERE synced_at IS NULL").fetchone()[0]
    return {"synced":synced,"pending":pending}


def native_windows_notification(title: str, message: str) -> None:
    """Best-effort Windows toast. Never blocks or breaks POS operations."""
    if platform.system().lower() != "windows":
        return
    def _show():
        try:
            from winotify import Notification, audio  # type: ignore
            t = Notification(app_id="Yola by Double Gee Tech", title=title, msg=message, duration="short")
            try:
                t.set_audio(audio.Default, loop=False)
            except Exception:
                pass
            t.show()
        except Exception:
            pass
    threading.Thread(target=_show, name="DG-POS-Toast", daemon=True).start()


def notify(c: sqlite3.Connection, kind: str, title: str, message: str, severity: str="info", branch_id: Optional[int]=None) -> None:
    cur = c.execute("INSERT INTO notifications(kind,title,message,severity,created_at) VALUES(?,?,?,?,?)", (kind,title,message,severity,iso()))
    queue_sync(c,"notification.created",{"local_id":cur.lastrowid,"kind":kind,"title":title,"message":message,"severity":severity},branch_id,event_key=f"notification:{cur.lastrowid}")
    if kind == "low_stock" or severity in {"warning","error"}:
        native_windows_notification(title, message)


def product_stock(c: sqlite3.Connection, branch_id: int, product_id: int) -> sqlite3.Row:
    r = c.execute("SELECT * FROM branch_stock WHERE branch_id=? AND product_id=?", (branch_id,product_id)).fetchone()
    if not r:
        c.execute("INSERT INTO branch_stock(branch_id,product_id,quantity,min_stock) VALUES(?,?,0,0)", (branch_id,product_id))
        r = c.execute("SELECT * FROM branch_stock WHERE branch_id=? AND product_id=?", (branch_id,product_id)).fetchone()
    return r


def update_stock(c: sqlite3.Connection, branch_id: int, product_id: int, delta: float, movement: str, user: Optional[dict], reference: str="", reason: str="", batch_no: str="") -> float:
    st = product_stock(c,branch_id,product_id)
    new_qty = float(st["quantity"]) + float(delta)
    if new_qty < -1e-9:
        p = c.execute("SELECT name FROM products WHERE id=?", (product_id,)).fetchone()
        raise HTTPException(status_code=409, detail=f"Not enough stock for {p['name'] if p else product_id}")
    c.execute("UPDATE branch_stock SET quantity=? WHERE branch_id=? AND product_id=?", (new_qty,branch_id,product_id))
    # keep legacy main quantity mirrored for old tooling
    c.execute("UPDATE products SET quantity=(SELECT COALESCE(SUM(quantity),0) FROM branch_stock WHERE product_id=?),updated_at=? WHERE id=?", (product_id,iso(),product_id))
    c.execute("INSERT INTO stock_movements(branch_id,product_id,user_id,movement_type,quantity,batch_no,reference,reason,created_at) VALUES(?,?,?,?,?,?,?,?,?)", (branch_id,product_id,user.get("id") if user else None,movement,float(delta),batch_no,reference,reason,iso()))
    if batch_no:
        b = c.execute("SELECT id,quantity FROM product_batches WHERE branch_id=? AND product_id=? AND batch_no=?", (branch_id,product_id,batch_no)).fetchone()
        if b: c.execute("UPDATE product_batches SET quantity=quantity+? WHERE id=?", (delta,b["id"]))
    p = c.execute("SELECT p.name,p.sku,p.category,p.cost_price,p.sell_price,bs.min_stock FROM products p JOIN branch_stock bs ON bs.product_id=p.id AND bs.branch_id=? WHERE p.id=?",(branch_id,product_id)).fetchone()
    if p:
        queue_sync(c,"stock.changed",{"product_id":product_id,"name":p["name"],"sku":p["sku"],"category":p["category"],"quantity":new_qty,"min_stock":p["min_stock"],"cost_price":p["cost_price"],"sell_price":p["sell_price"],"movement":movement},branch_id)
        if new_qty <= float(p["min_stock"] or 0):
            notify(c,"low_stock","Low stock",f"{p['name']} has {new_qty:g} remaining.","warning",branch_id)
    return new_qty


def next_number(c: sqlite3.Connection, kind: str, table: str, col: str) -> str:
    prefix = {"receipt":"RCPT","quote":"QT","invoice":"INV","return":"RET"}.get(kind,kind.upper())
    date = datetime.now().strftime("%y%m%d")
    n = c.execute(f"SELECT COUNT(*) FROM {table} WHERE {col} LIKE ?", (f"{prefix}-{date}-%",)).fetchone()[0] + 1
    return f"{prefix}-{date}-{n:04d}"


def safe_media_from_data(data_url: str, prefix: str) -> str:
    if not data_url or "," not in data_url: return ""
    header, payload = data_url.split(",",1)
    ext = ".png" if "png" in header else ".jpg"
    raw = base64.b64decode(payload)
    if len(raw) > 4_000_000: raise HTTPException(status_code=413, detail="Image is too large")
    name = f"{prefix}-{uuid.uuid4().hex[:12]}{ext}"
    (MEDIA_DIR/name).write_bytes(raw)
    return "/media/" + name


# ---------- API models ----------
class ActivationRequest(BaseModel):
    business_name: str = Field(min_length=2,max_length=120)
    owner_name: str = Field(min_length=2,max_length=120)
    phone: str = Field(min_length=3,max_length=40)
    email: str = Field(min_length=4,max_length=254)
    password: str = Field(min_length=12,max_length=128)
    owner_pin: str = Field(min_length=4,max_length=12)
    existing_registration_id: str = ""

class ActivationCodeIn(BaseModel):
    code: str = Field(min_length=4,max_length=24)

class LoginIn(BaseModel):
    user_id: Optional[int] = None
    name: str = ""
    pin: str

class BranchIn(BaseModel):
    name: str
    location: str = ""

class UserIn(BaseModel):
    name: str
    role: str = "cashier"
    pin: str = Field(min_length=4,max_length=12)
    permissions: list[str] = []

class ProductIn(BaseModel):
    name: str = Field(min_length=1,max_length=140)
    sku: str = ""
    barcode: str = ""
    category: str = "General"
    unit: str = "ea"
    cost_price: float = Field(default=0,ge=0)
    sell_price: float = Field(default=0,ge=0)
    wholesale_price: float = Field(default=0,ge=0)
    quantity: float = Field(default=0,ge=0)
    min_stock: float = Field(default=0,ge=0)
    supplier: str = ""
    expiry_date: str = ""
    tax_rate: float = Field(default=0,ge=0,le=100)
    track_batch: bool = False
    image_data: str = ""
    branch_id: Optional[int] = None

class ProductUpdate(BaseModel):
    name: Optional[str]=None; sku: Optional[str]=None; barcode: Optional[str]=None; category: Optional[str]=None; unit: Optional[str]=None
    cost_price: Optional[float]=Field(default=None,ge=0); sell_price: Optional[float]=Field(default=None,ge=0); wholesale_price: Optional[float]=Field(default=None,ge=0)
    min_stock: Optional[float]=Field(default=None,ge=0); supplier: Optional[str]=None; expiry_date: Optional[str]=None; tax_rate: Optional[float]=Field(default=None,ge=0,le=100)
    track_batch: Optional[bool]=None; active: Optional[bool]=None; image_data: Optional[str]=None; branch_id: Optional[int]=None

class CustomerIn(BaseModel):
    name: str; phone: str=""; email: str=""; address: str=""; credit_limit: float=Field(default=0,ge=0)

class SupplierIn(BaseModel):
    name: str; phone: str=""; email: str=""; address: str=""

class PaymentIn(BaseModel):
    method: str
    amount: float = Field(gt=0)
    reference: str = ""

class SaleItemIn(BaseModel):
    product_id: int
    quantity: float = Field(gt=0)
    unit_price: Optional[float] = Field(default=None,ge=0)
    discount: float = Field(default=0,ge=0)

class SaleIn(BaseModel):
    idempotency_key: str = Field(default="",max_length=128)
    items: list[SaleItemIn]
    discount: float = Field(default=0,ge=0)
    payment_method: str = "Cash"
    amount_paid: Optional[float] = None
    payments: list[PaymentIn] = []
    customer_id: Optional[int] = None
    branch_id: Optional[int] = None
    sale_type: str = "retail"
    note: str = ""
    approval_id: Optional[str] = None

class HoldSaleIn(BaseModel):
    name: str = "Held sale"
    payload: dict[str,Any]
    branch_id: Optional[int]=None

class ExpenseIn(BaseModel):
    category: str; amount: float=Field(gt=0); payment_method: str="Cash"; description: str=""; supplier_id: Optional[int]=None
    receipt_data: str=""; recurring: bool=False; recurrence: str="monthly"; next_due: str=""; branch_id: Optional[int]=None

class PurchaseItemIn(BaseModel):
    product_id: int; quantity: float=Field(gt=0); unit_cost: float=Field(gt=0); batch_no: str=""; expiry_date: str=""

class PurchaseIn(BaseModel):
    supplier_id: Optional[int]=None; reference: str=""; invoice_no: str=""; amount_paid: float=Field(default=0,ge=0); payments: list[PaymentIn]=[]; items: list[PurchaseItemIn]; branch_id: Optional[int]=None

class StockAdjustIn(BaseModel):
    product_id: int; quantity: float; reason: str="Adjustment"; adjustment_type: str="adjustment"; branch_id: Optional[int]=None

class StockTakeItemIn(BaseModel):
    product_id: int
    counted_quantity: float = Field(ge=0)

class StockTakeIn(BaseModel):
    items: list[StockTakeItemIn]
    note: str = "Stock take"
    branch_id: Optional[int] = None

class TransferIn(BaseModel):
    product_id: int; quantity: float=Field(gt=0); from_branch_id: int; to_branch_id: int; reason: str="Branch transfer"

class DocumentItemIn(BaseModel):
    product_id: Optional[int]=None; description: str=""; quantity: float=Field(gt=0); unit_price: float=Field(ge=0); tax_rate: float=Field(default=0,ge=0,le=100)

class DocumentIn(BaseModel):
    doc_type: str = "quote"; customer_id: Optional[int]=None; items: list[DocumentItemIn]; discount: float=Field(default=0,ge=0); due_date: str=""; note: str=""; branch_id: Optional[int]=None

class DocPaymentIn(BaseModel):
    amount: float=Field(gt=0); payment_method: str="Cash"; reference: str=""

class ReturnItemIn(BaseModel):
    sale_item_id: int; quantity: float=Field(gt=0); restock: bool=True

class ReturnIn(BaseModel):
    sale_id: int; items: list[ReturnItemIn]; refund_method: str="Cash"; reason: str=""; branch_id: Optional[int]=None; approval_id: Optional[str]=None

class CashShiftOpenIn(BaseModel):
    opening_cash: float=Field(default=0,ge=0); branch_id: Optional[int]=None

class CashShiftCloseIn(BaseModel):
    actual_cash: float=Field(ge=0)

class CashMoveIn(BaseModel):
    movement_type: str; amount: float=Field(gt=0); reason: str=""

class SettingsIn(BaseModel):
    values: dict[str,dict[str,Any]]

class ApprovalIn(BaseModel):
    request_type: str; details: dict[str,Any]; branch_id: Optional[int]=None

class UpdateDownloadIn(BaseModel):
    url: str=""

# ---------- Basic / activation / staff ----------
@app.get("/")
def root(): return FileResponse(STATIC_DIR/"index.html")

@app.get("/api/health")
def health(): return {"ok":True,"version":VERSION,"device_id":DEVICE_ID}

@app.get("/api/device")
def device(): return {"device_id":DEVICE_ID,"device_name":platform.node() or "Yola Device","cloud_url":DG_CLOUD_URL,"version":VERSION}

@app.get("/api/license")
def license_status():
    lic=read_license()
    return {k:lic.get(k) for k in ["status","business_id","business_name","request_code","last_verified_at","valid_until","plan","branch_id","branch_name","device_limit"]}|{"offline_grace_valid":cached_license_valid(),"device_id":DEVICE_ID}

@app.post("/api/activation/request")
def request_activation(p: ActivationRequest):
    # Never reuse existing local sales/accounts for a different business.
    existing=read_license()
    if existing.get('business_id'):
        raise HTTPException(status_code=409, detail='This Windows data folder already belongs to an activated Yola business. Contact DG Tech to move or recover its data securely.')
    if not p.existing_registration_id.strip():
        raise HTTPException(status_code=422, detail='Register your business in Yola, wait for DG Tech Master Control approval, then link this Windows computer using that registration ID.')
    payload = {"device_id": DEVICE_ID, "device_name": platform.node() or "Yola Windows PC",
               "business_name": p.business_name, "owner_name": p.owner_name,
               "phone": p.phone, "app_version": VERSION,
               "existing_business_id":p.existing_registration_id.strip().upper(),
               "email":p.email.strip().lower(),"password":p.password}
    result = cloud_json("/api/activation/request", payload, "POST")
    registration_id = result["request_code"]
    claim_secret = result.get("claim_secret")
    if not claim_secret:
        raise HTTPException(409, "This device was already approved. Contact DG Tech for a safe reactivation.")
    with db() as c:
        c.execute("UPDATE license_cache SET status='pending',request_code=?,business_name=?,claim_secret=? WHERE id=1",
                  (registration_id,p.business_name,enc_secret(claim_secret)))
        c.execute("INSERT OR REPLACE INTO app_meta(key,value) VALUES('pending_owner_name',?)",(p.owner_name,))
        c.execute("INSERT OR REPLACE INTO app_meta(key,value) VALUES('pending_owner_pin_hash',?)",(pin_hash(p.owner_pin),))
        c.execute("INSERT OR REPLACE INTO app_meta(key,value) VALUES('pending_phone',?)",(p.phone,))
    return {"status":"pending","request_code":registration_id,"device_id":DEVICE_ID,
            "message":"Registration submitted. DG Tech must approve this device in Master Control."}


def claim_approved_license() -> dict[str, Any]:
    lic = read_license()
    if cached_license_valid():
        return {"status":"active","active":True,"business_name":lic.get("business_name")}
    if not lic.get("claim_secret"):
        return {"status":lic.get("status","pending"),"active":False,"request_code":lic.get("request_code")}
    try:
        secret = dec_secret(lic["claim_secret"])
        if not secret: raise HTTPException(403, "Activation request must be renewed")
        result = cloud_json("/api/activation/status", {"device_id":DEVICE_ID,"claim_secret":secret}, "POST")
    except HTTPException as error:
        if error.status_code in (503, 502, 504):
            return {"status":"pending","active":False,"message":"DG Cloud is currently unreachable"}
        raise
    if result.get("status") != "active" or not result.get("license_token"):
        return {"status":result.get("status","pending"),"active":False,"request_code":lic.get("request_code")}

    raw_payload, raw_sig = result["license_token"].split(".",1)
    pinned = trusted_license_public_key()
    if not secrets.compare_digest(result["public_key"], pinned):
        raise HTTPException(403, "The cloud signing key does not match the official DG Tech master")
    key = Ed25519PublicKey.from_public_bytes(base64.b64decode(pinned))
    raw = base64.urlsafe_b64decode(raw_payload + "=" * (-len(raw_payload) % 4))
    key.verify(base64.urlsafe_b64decode(raw_sig + "=" * (-len(raw_sig) % 4)), raw)
    claims = json.loads(raw)
    if claims.get("device_id") != DEVICE_ID or claims.get("business_id") != result.get("business_id"):
        # status endpoint includes business_id; never activate a mismatched licence.
        raise HTTPException(403, "The issued licence does not match this device or business")
    if utcnow() > datetime.fromisoformat(claims["valid_until"]):
        raise HTTPException(403,"Licence has expired")
    lease_token=result.get('lease_token')
    if not lease_token: raise HTTPException(403,'Official Master Control signed offline lease missing')
    try:
        lp,ls=lease_token.split('.',1)
        raw_lease=base64.urlsafe_b64decode(lp+'='*(-len(lp)%4))
        key.verify(base64.urlsafe_b64decode(ls+'='*(-len(ls)%4)),raw_lease)
        lease=json.loads(raw_lease)
        if lease.get('kind')!='yola-offline-lease' or lease['business_id']!=claims['business_id'] or lease['device_id']!=DEVICE_ID:
            raise ValueError('Lease identity mismatch')
        if lease.get('master_installation_id')!=claims.get('master_installation_id'):
            raise ValueError('Master identity mismatch')
        if utcnow()>datetime.fromisoformat(lease['offline_until']): raise ValueError('Expired lease')
    except Exception as exc:
        raise HTTPException(403,'Cannot authenticate DG Tech offline licence lease') from exc
    with db() as c:
        branch = c.execute("SELECT id FROM branches WHERE cloud_branch_id=?",(claims.get("branch_id"),)).fetchone()
        if branch: bid = branch[0]
        else:
            existing=c.execute("SELECT id FROM branches ORDER BY id LIMIT 1").fetchone()
            if existing:
                bid=existing[0]
                c.execute("UPDATE branches SET cloud_branch_id=? WHERE id=?",(claims.get("branch_id"),bid))
            else:
                cur=c.execute("INSERT INTO branches(name,location,cloud_branch_id,created_at) VALUES(?,?,?,?)",
                              (claims.get("branch_name","Main Branch"),"",claims.get("branch_id"),iso()))
                bid=cur.lastrowid
        c.execute("""UPDATE license_cache SET business_id=?,business_name=?,token_enc=?,lease_token_enc=?,public_key=?,status='active',
                     last_verified_at=?,valid_until=?,plan=?,branch_id=?,branch_name=?,device_limit=?,claim_secret=NULL WHERE id=1""",
                  (claims["business_id"],claims.get("business_name"),enc_secret(result["license_token"]),enc_secret(lease_token),result["public_key"],iso(),
                   claims["valid_until"],claims.get("plan","standard"),bid,claims.get("branch_name"),claims.get("device_limit",1)))
        if not c.execute("SELECT 1 FROM users LIMIT 1").fetchone():
            name=c.execute("SELECT value FROM app_meta WHERE key='pending_owner_name'").fetchone()
            ph=c.execute("SELECT value FROM app_meta WHERE key='pending_owner_pin_hash'").fetchone()
            if not ph: raise HTTPException(409,"Owner PIN setup missing; request activation again")
            c.execute("INSERT INTO users(name,role,pin_hash,permissions,active,created_at) VALUES(?,?,?,?,1,?)",
                      ((name[0] if name else "Owner"),"owner",ph[0],json.dumps(["*"]),iso()))
        audit(c,"license.activated",None,bid,"license",claims["business_id"],{"platform":"windows","approved_by":"DG Tech"})
    return {"status":"active","active":True,"business_name":claims.get("business_name"),
            "owner_access_token":result.get('owner_access_token')}

@app.post("/api/activation/activate")
def activate_device(p: ActivationCodeIn):
    # Legacy UI button now checks the signed cloud approval; no self-generated
    # activation code is trusted on the client.
    result = claim_approved_license()
    if not result.get("active"):
        raise HTTPException(409, "Waiting for DG Tech approval in Master Control")
    return result

@app.post("/api/activation/check")
def check_activation():
    return claim_approved_license() if not cached_license_valid() else {"status":"active","active":True}

@app.post("/api/license/verify")
def verify_license():
    lic=read_license()
    if not lic.get("license_token"):
        raise HTTPException(423,"No signed licence cached")
    # An expired *offline grace* must not trap an approved user forever:
    # the cloud can renew a properly signed, still-active entitlement online.
    result=cloud_json("/api/license/verify",{"device_id":DEVICE_ID,"license_token":lic["license_token"],"app_version":VERSION},"POST")
    status=result.get("status","suspended")
    if status=='active':
        try:
            lease_token=result['lease_token']
            raw,sig=lease_token.split('.',1)
            raw_bytes=base64.urlsafe_b64decode(raw+'='*(-len(raw)%4))
            pub=Ed25519PublicKey.from_public_bytes(base64.b64decode(trusted_license_public_key()))
            pub.verify(base64.urlsafe_b64decode(sig+'='*(-len(sig)%4)),raw_bytes)
            lease=json.loads(raw_bytes)
            if lease.get('kind')!='yola-offline-lease' or lease.get('business_id')!=lic['business_id'] or lease.get('device_id')!=DEVICE_ID:
                raise ValueError('Lease business/device mismatch')
            if utcnow()>datetime.fromisoformat(lease['offline_until']): raise ValueError('Expired signed lease')
        except Exception as exc:
            raise HTTPException(503,'DG Master Control could not renew this signed licence') from exc
    with db() as c:
        if status=="active":c.execute("UPDATE license_cache SET status='active',lease_token_enc=?,last_verified_at=? WHERE id=1",(enc_secret(lease_token),iso()))
        else:c.execute("UPDATE license_cache SET status=? WHERE id=1",(status,))
    return {"active":status=="active","status":status}

@app.get("/api/auth/users")
def auth_users(_:dict=Depends(require_license)):
    with db() as c:
        return [dict(r) for r in c.execute("SELECT id,name,role,active,force_change FROM users WHERE active=1 ORDER BY name").fetchall()]

@app.post("/api/auth/login")
def login(p: LoginIn, _:dict=Depends(require_license)):
    with db() as c:
        if p.user_id: r=c.execute("SELECT * FROM users WHERE id=? AND active=1",(p.user_id,)).fetchone()
        else: r=c.execute("SELECT * FROM users WHERE lower(name)=lower(?) AND active=1",(p.name.strip(),)).fetchone()
        if not r or not pin_ok(p.pin,r["pin_hash"]): raise HTTPException(status_code=401,detail="Incorrect staff PIN")
        token=secrets.token_urlsafe(32); exp=iso(utcnow()+timedelta(hours=12))
        c.execute("INSERT INTO user_sessions(user_id,token_hash,expires_at,created_at) VALUES(?,?,?,?)",(r["id"],token_hash(token),exp,iso()))
        audit(c,"staff.login",dict(r),branch_id_from(),"user",r["id"],{"name":r["name"],"role":r["role"]})
        queue_sync(c,"staff.activity",{"action":"login","user_id":r["id"],"name":r["name"],"role":r["role"]},branch_id_from(),f"login:{r['id']}:{int(time.time())}")
        return {"token":token,"user":{"id":r["id"],"name":r["name"],"role":r["role"],"permissions":([x for x in (json_load(r["permissions"],[]) or default_permissions(r["role"])) if x in maximum_permissions(r["role"]) ] if r["role"]!="owner" else ["*"])},"expires_at":exp}

@app.post("/api/auth/logout")
def logout(x_session_token:str=Header(default="")):
    if x_session_token:
        with db() as c: c.execute("DELETE FROM user_sessions WHERE token_hash=?",(token_hash(x_session_token),))
    return {"ok":True}

@app.get("/api/auth/me")
def me(user:dict=Depends(current_user)):
    return {"id":user["id"],"name":user["name"],"role":user["role"],"permissions":user["permissions"]}

@app.get("/api/users")
def users(user:dict=Depends(access("audit"))):
    if user["role"] != "owner": raise HTTPException(403,"Staff management is reserved for the owner")
    with db() as c: return [dict(r)|{"permissions":json_load(r["permissions"],[])} for r in c.execute("SELECT id,name,role,permissions,active,force_change,created_at FROM users ORDER BY name").fetchall()]

def master_staff_limit():
    """A signed lease refreshed by Master Control contains the worker cap."""
    lease=read_license().get('lease_token')
    if not lease or not cached_license_valid():raise HTTPException(423,'Master Control licence lease required')
    try:
        raw=lease.split('.',1)[0]
        data=json.loads(base64.urlsafe_b64decode(raw+'='*(-len(raw)%4)))
        return max(0,int(data['max_workers']))
    except Exception as e:
        raise HTTPException(423,'Master Control worker limit unavailable') from e

@app.post("/api/users")
def add_user(p:UserIn,user:dict=Depends(access("audit"))):
    if user["role"] != "owner": raise HTTPException(403, "Only the business owner may manage staff accounts")
    if p.role not in {"manager","cashier","accountant","stock_controller"}:
        raise HTTPException(422,"Unsupported staff role; owner access cannot be delegated")
    role=p.role
    allowed=maximum_permissions(role)
    perms=[x for x in p.permissions if x in allowed] if p.permissions else default_permissions(role)
    if not p.pin or len(p.pin)<4: raise HTTPException(422,"Staff PIN must have at least 4 characters")
    with db() as c:
        count=c.execute("SELECT COUNT(*) FROM users WHERE active=1 AND role!='owner'").fetchone()[0]
        if count >= master_staff_limit():
            raise HTTPException(409,'DG Tech Master Control worker-account limit reached')
        cur=c.execute("INSERT INTO users(name,role,pin_hash,permissions,active,created_at) VALUES(?,?,?,?,1,?)",(p.name.strip(),role,pin_hash(p.pin),json.dumps(perms),iso()))
        audit(c,"user.created",user,branch_id_from(),"user",cur.lastrowid,{"name":p.name,"role":role,"permissions":perms})
        return {"id":cur.lastrowid}

@app.put("/api/users/{user_id}")
def update_user(user_id:int,p:dict[str,Any],user:dict=Depends(access("audit"))):
    if user["role"] != "owner": raise HTTPException(403, "Only the business owner may manage staff accounts")
    allowed={"name","role","active","permissions"}; sets=[]; vals=[]
    with db() as c:
        old=c.execute("SELECT * FROM users WHERE id=?",(user_id,)).fetchone()
        if not old: raise HTTPException(status_code=404,detail="User not found")
        if old["role"] == "owner": raise HTTPException(403,"Owner account may not be disabled or reassigned by staff editor")
        if "role" in p and p["role"] not in {"manager","cashier","accountant","stock_controller"}:
            raise HTTPException(422,"Unsupported staff role")
        role = p.get("role",old["role"])
        if "permissions" in p:
            if not isinstance(p["permissions"],list) or any(x not in maximum_permissions(role) for x in p["permissions"]):
                raise HTTPException(422,"Permissions cannot exceed this role")
        elif "role" in p: p["permissions"] = default_permissions(role)
        if "pin" in p and len(str(p["pin"]))<4: raise HTTPException(422,"Staff PIN must have at least 4 characters")
        for k,v in p.items():
            if k in allowed:
                sets.append(k+"=?"); vals.append(json.dumps(v) if k=="permissions" else v)
            elif k=="pin": sets.append("pin_hash=?"); vals.append(pin_hash(str(v)))
        if sets: c.execute("UPDATE users SET "+",".join(sets)+" WHERE id=?",(*vals,user_id))
        new=c.execute("SELECT * FROM users WHERE id=?",(user_id,)).fetchone(); audit(c,"user.updated",user,branch_id_from(),"user",user_id,previous=dict(old),new=dict(new))
    return {"ok":True}

@app.get("/api/branches")
def branches(user:dict=Depends(current_user),_:dict=Depends(require_license)):
    with db() as c: return [dict(r) for r in c.execute("SELECT * FROM branches WHERE active=1 ORDER BY name").fetchall()]

@app.post("/api/branches")
def add_branch(p:BranchIn,user:dict=Depends(access("audit"))):
    with db() as c:
        cur=c.execute("INSERT INTO branches(name,location,created_at) VALUES(?,?,?)",(p.name.strip(),p.location.strip(),iso())); bid=cur.lastrowid
        for pr in c.execute("SELECT id,min_stock FROM products WHERE active=1").fetchall(): c.execute("INSERT OR IGNORE INTO branch_stock(branch_id,product_id,quantity,min_stock) VALUES(?,?,0,?)",(bid,pr["id"],pr["min_stock"] or 0))
        audit(c,"branch.created",user,bid,"branch",bid,{"name":p.name,"location":p.location})
        queue_sync(c,"branch.created",{"local_branch_id":bid,"name":p.name,"location":p.location},bid,f"branch:{bid}")
    flush_sync(10); return {"id":bid}

@app.get("/api/settings")
def get_settings(user:dict=Depends(access("audit"))):
    with db() as c:
        rows=c.execute("SELECT section,key,value FROM settings ORDER BY section,key").fetchall()
    out:dict[str,dict[str,str]]={}
    for r in rows: out.setdefault(r["section"],{})[r["key"]]=r["value"]
    return out

@app.put("/api/settings")
def update_settings(p:SettingsIn,user:dict=Depends(access("audit"))):
    if user["role"] != "owner" and any(k in {"accounting","tax","backup","security","license","email"} for k in p.values):
        raise HTTPException(403,"Only the owner can change financial and security configuration")
    protected={"license"}
    with db() as c:
        for section,vals in p.values.items():
            if section in protected: continue
            for k,v in vals.items(): c.execute("INSERT OR REPLACE INTO settings(section,key,value) VALUES(?,?,?)",(section,k,str(v).lower() if isinstance(v,bool) else str(v)))
        audit(c,"settings.updated",user,branch_id_from(),"settings","",{"sections":list(p.values)})
    return {"ok":True}

# ---------- Products / inventory / parties ----------
@app.get("/api/products")
def products(branch_id:Optional[int]=None,user:dict=Depends(current_user),_:dict=Depends(require_license)):
    bid=branch_id_from(user.get("license"),branch_id)
    with db() as c:
        rows=c.execute("""SELECT p.*,COALESCE(bs.quantity,0) branch_quantity,COALESCE(bs.min_stock,p.min_stock,0) branch_min_stock,
                       CASE WHEN COALESCE(bs.quantity,0)<=COALESCE(bs.min_stock,p.min_stock,0) THEN 1 ELSE 0 END low_stock
                       FROM products p LEFT JOIN branch_stock bs ON bs.product_id=p.id AND bs.branch_id=? WHERE p.active=1 ORDER BY p.name""",(bid,)).fetchall()
        out=[]
        for r in rows:
            d=dict(r); d["quantity"]=d["branch_quantity"]; d["min_stock"]=d["branch_min_stock"]
            if user["role"] == "cashier":
                for secret in ("cost_price","wholesale_price","supplier","track_batch"):
                    d.pop(secret,None)
                d.pop("batches",None)
            else:
                d["batches"]=[dict(x) for x in c.execute("SELECT id,batch_no,expiry_date,quantity FROM product_batches WHERE branch_id=? AND product_id=? AND quantity>0 ORDER BY expiry_date",(bid,r["id"])).fetchall()]
            out.append(d)
        return out

@app.get("/api/products/{product_id}")
def product_detail(product_id:int,branch_id:Optional[int]=None,user:dict=Depends(access("products"))):
    bid=branch_id_from(user.get("license"),branch_id)
    with db() as c:
        p=c.execute("SELECT * FROM products WHERE id=?",(product_id,)).fetchone()
        if not p: raise HTTPException(status_code=404,detail="Product not found")
        st=product_stock(c,bid,product_id)
        perf=c.execute("""SELECT COALESCE(SUM(si.quantity),0) units_sold,COALESCE(SUM(si.line_total),0) revenue,
                         COALESCE(SUM(si.unit_cost*si.quantity),0) cost_of_goods,
                         COALESCE(SUM((si.unit_price-si.unit_cost)*si.quantity-si.discount),0) gross_profit
                         FROM sale_items si JOIN sales s ON s.id=si.sale_id WHERE si.product_id=? AND s.branch_id=? AND s.status='completed'""",(product_id,bid)).fetchone()
        bought=c.execute("""SELECT COALESCE(SUM(pi.quantity),0) units_purchased,COALESCE(SUM(pi.line_total),0) spent
                           FROM purchase_items pi JOIN purchases p ON p.id=pi.purchase_id WHERE pi.product_id=? AND p.branch_id=?""",(product_id,bid)).fetchone()
        movements=[dict(x) for x in c.execute("SELECT * FROM stock_movements WHERE product_id=? AND branch_id=? ORDER BY created_at DESC LIMIT 100",(product_id,bid)).fetchall()]
        batches=[dict(x) for x in c.execute("SELECT id,batch_no,expiry_date,quantity FROM product_batches WHERE branch_id=? AND product_id=? AND quantity>0 ORDER BY expiry_date",(bid,product_id)).fetchall()]
        d=dict(p)|dict(perf)|dict(bought)|{"quantity":st["quantity"],"min_stock":st["min_stock"],"stock_value":money(st["quantity"]*p["cost_price"]),"profit_margin":money(((p["sell_price"]-p["cost_price"])/p["sell_price"]*100) if p["sell_price"] else 0),"movements":movements,"batches":batches}
        return d

@app.post("/api/products")
def add_product(p:ProductIn,user:dict=Depends(access("products"))):
    now=iso(); sku=p.sku.strip() or f"DG-{uuid.uuid4().hex[:8].upper()}"; bid=branch_id_from(user.get("license"),p.branch_id); image=safe_media_from_data(p.image_data,"product") if p.image_data else ""
    with db() as c:
        try:
            cur=c.execute("""INSERT INTO products(name,sku,barcode,category,unit,cost_price,sell_price,wholesale_price,quantity,min_stock,supplier,expiry_date,image_path,tax_rate,track_batch,created_at,updated_at)
                           VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",(p.name.strip(),sku,p.barcode.strip(),p.category.strip() or "General",p.unit.strip() or "ea",money(p.cost_price),money(p.sell_price),money(p.wholesale_price),p.quantity,p.min_stock,p.supplier.strip(),p.expiry_date.strip(),image,money(p.tax_rate),int(p.track_batch),now,now))
        except sqlite3.IntegrityError: raise HTTPException(status_code=409,detail="That SKU already exists")
        pid=cur.lastrowid
        for b in c.execute("SELECT id FROM branches WHERE active=1").fetchall(): c.execute("INSERT OR IGNORE INTO branch_stock(branch_id,product_id,quantity,min_stock) VALUES(?,?,?,?)",(b["id"],pid,p.quantity if b["id"]==bid else 0,p.min_stock))
        if p.quantity: c.execute("INSERT INTO stock_movements(branch_id,product_id,user_id,movement_type,quantity,reference,created_at) VALUES(?,?,?,?,?,?,?)",(bid,pid,user["id"],"opening",p.quantity,"Opening stock",now))
        audit(c,"product.created",user,bid,"product",pid,{"name":p.name,"sku":sku,"opening_stock":p.quantity})
        queue_sync(c,"product.updated",{"id":pid,"name":p.name,"sku":sku,"category":p.category,"quantity":p.quantity,"cost_price":p.cost_price,"sell_price":p.sell_price,"low_stock":p.quantity<=p.min_stock},bid,f"product:{bid}:{pid}:{int(time.time())}")
    flush_sync(10); return {"id":pid,"sku":sku}

@app.put("/api/products/{product_id}")
def update_product(product_id:int,p:ProductUpdate,user:dict=Depends(access("products"))):
    bid=branch_id_from(user.get("license"),p.branch_id)
    with db() as c:
        old=c.execute("SELECT * FROM products WHERE id=?",(product_id,)).fetchone()
        if not old: raise HTTPException(status_code=404,detail="Product not found")
        data=p.model_dump(exclude_unset=True); branch_min=data.pop("min_stock",None); image_data=data.pop("image_data",None); data.pop("branch_id",None)
        if image_data: data["image_path"]=safe_media_from_data(image_data,"product")
        if "track_batch" in data: data["track_batch"]=int(bool(data["track_batch"]))
        if "active" in data: data["active"]=int(bool(data["active"]))
        if data:
            data["updated_at"]=iso(); c.execute("UPDATE products SET "+",".join(k+"=?" for k in data)+" WHERE id=?",(*data.values(),product_id))
        if branch_min is not None:
            product_stock(c,bid,product_id); c.execute("UPDATE branch_stock SET min_stock=? WHERE branch_id=? AND product_id=?",(branch_min,bid,product_id))
        new=c.execute("SELECT * FROM products WHERE id=?",(product_id,)).fetchone(); audit(c,"product.updated",user,bid,"product",product_id,previous=dict(old),new=dict(new))
        st=product_stock(c,bid,product_id); queue_sync(c,"product.updated",{"id":product_id,"name":new["name"],"sku":new["sku"],"category":new["category"],"quantity":st["quantity"],"cost_price":new["cost_price"],"sell_price":new["sell_price"],"low_stock":st["quantity"]<=st["min_stock"]},bid)
    flush_sync(10); return {"ok":True}

@app.post("/api/stock/adjust")
def adjust_stock(p:StockAdjustIn,user:dict=Depends(access("stock"))):
    bid=branch_id_from(user.get("license"),p.branch_id)
    with db() as c:
        prod=c.execute("SELECT * FROM products WHERE id=?",(p.product_id,)).fetchone()
        if not prod: raise HTTPException(status_code=404,detail="Product not found")
        newqty=update_stock(c,bid,p.product_id,p.quantity,p.adjustment_type,user,reason=p.reason,reference="Manual adjustment")
        audit(c,"stock.adjusted",user,bid,"product",p.product_id,{"delta":p.quantity,"new_quantity":newqty,"reason":p.reason})
        if p.adjustment_type in {"damaged","missing"} and p.quantity<0:
            loss=money(abs(p.quantity)*prod["cost_price"]); journal(c,"stock_loss",f"{p.product_id}:{int(time.time())}",p.reason,[("6000",loss,0,"Stock loss"),("1200",0,loss,"Inventory reduction")],bid,user["id"])
        queue_sync(c,"stock.changed",{"product_id":p.product_id,"name":prod["name"],"quantity":newqty,"change":p.quantity,"type":p.adjustment_type,"reason":p.reason},bid)
    flush_sync(10); return {"quantity":newqty}

@app.post("/api/stock/take")
def stock_take(p:StockTakeIn,user:dict=Depends(access("stock"))):
    bid=branch_id_from(user.get("license"),p.branch_id)
    if not p.items:
        raise HTTPException(status_code=422,detail="Count at least one product")
    ref="STOCKTAKE-"+datetime.now().strftime("%Y%m%d-%H%M%S")
    changes=[]
    with db() as c:
        for item in p.items:
            prod=c.execute("SELECT id,name FROM products WHERE id=? AND active=1",(item.product_id,)).fetchone()
            if not prod:
                raise HTTPException(status_code=404,detail=f"Product {item.product_id} not found")
            st=product_stock(c,bid,item.product_id)
            expected=float(st["quantity"] or 0); counted=float(item.counted_quantity); delta=counted-expected
            if abs(delta)>1e-9:
                update_stock(c,bid,item.product_id,delta,"stocktake",user,ref,p.note or "Stock take")
            changes.append({"product_id":item.product_id,"name":prod["name"],"expected":expected,"counted":counted,"difference":delta})
        audit(c,"stock.take",user,bid,"stock_take",ref,{"items":len(changes),"note":p.note},None,changes)
        queue_sync(c,"stock.take",{"reference":ref,"items":changes,"note":p.note},bid,f"stocktake:{ref}")
    flush_sync(100)
    return {"ok":True,"reference":ref,"changes":changes,"changed":sum(1 for x in changes if abs(x["difference"])>1e-9)}


@app.post("/api/stock/transfer")
def transfer_stock(p:TransferIn,user:dict=Depends(access("stock"))):
    if p.from_branch_id==p.to_branch_id: raise HTTPException(status_code=422,detail="Choose two different branches")
    with db() as c:
        prod=c.execute("SELECT * FROM products WHERE id=?",(p.product_id,)).fetchone()
        if not prod: raise HTTPException(status_code=404,detail="Product not found")
        outq=update_stock(c,p.from_branch_id,p.product_id,-p.quantity,"transfer_out",user,reference=f"To branch {p.to_branch_id}",reason=p.reason)
        inq=update_stock(c,p.to_branch_id,p.product_id,p.quantity,"transfer_in",user,reference=f"From branch {p.from_branch_id}",reason=p.reason)
        audit(c,"stock.transferred",user,p.from_branch_id,"product",p.product_id,{"quantity":p.quantity,"from":p.from_branch_id,"to":p.to_branch_id})
        queue_sync(c,"stock.transfer",{"product_id":p.product_id,"name":prod["name"],"quantity":p.quantity,"from_branch_id":p.from_branch_id,"to_branch_id":p.to_branch_id},p.from_branch_id)
    flush_sync(10); return {"from_quantity":outq,"to_quantity":inq}

@app.get("/api/stock/movements")
def stock_movements(branch_id:Optional[int]=None,product_id:Optional[int]=None,user:dict=Depends(access("stock"))):
    bid=branch_id_from(user.get("license"),branch_id); q="SELECT sm.*,p.name product_name,u.name user_name FROM stock_movements sm JOIN products p ON p.id=sm.product_id LEFT JOIN users u ON u.id=sm.user_id WHERE sm.branch_id=?"; vals:list[Any]=[bid]
    if product_id: q+=" AND sm.product_id=?"; vals.append(product_id)
    q+=" ORDER BY sm.created_at DESC LIMIT 500"
    with db() as c: return [dict(r) for r in c.execute(q,vals).fetchall()]

@app.get("/api/inventory/summary")
def inventory_summary(branch_id:Optional[int]=None,user:dict=Depends(access("stock"))):
    bid=branch_id_from(user.get("license"),branch_id)
    with db() as c:
        r=c.execute("""SELECT COALESCE(SUM(bs.quantity*p.cost_price),0) stock_value,SUM(CASE WHEN bs.quantity<=bs.min_stock THEN 1 ELSE 0 END) low_stock,
                     SUM(CASE WHEN bs.quantity<=0 THEN 1 ELSE 0 END) out_stock,COUNT(*) products FROM branch_stock bs JOIN products p ON p.id=bs.product_id WHERE bs.branch_id=? AND p.active=1""",(bid,)).fetchone()
        exp=[dict(x) for x in c.execute("""SELECT p.id,p.name,b.batch_no,b.expiry_date,b.quantity FROM product_batches b JOIN products p ON p.id=b.product_id
              WHERE b.branch_id=? AND b.quantity>0 AND b.expiry_date!='' AND date(b.expiry_date)<=date('now','+30 day') ORDER BY b.expiry_date""",(bid,)).fetchall()]
        slow=[dict(x) for x in c.execute("""SELECT p.id,p.name,bs.quantity,MAX(s.created_at) last_sale FROM products p JOIN branch_stock bs ON bs.product_id=p.id AND bs.branch_id=?
              LEFT JOIN sale_items si ON si.product_id=p.id LEFT JOIN sales s ON s.id=si.sale_id AND s.branch_id=? GROUP BY p.id HAVING bs.quantity>0 AND (last_sale IS NULL OR date(last_sale)<date('now','-60 day')) LIMIT 30""",(bid,bid)).fetchall()]
        return dict(r)|{"expiring":exp,"slow_moving":slow}

@app.get("/api/customers")
def customers(user:dict=Depends(access("customers"))):
    with db() as c:
        rows=c.execute("""SELECT c.*,COALESCE((SELECT SUM(total) FROM sales s WHERE s.customer_id=c.id AND s.status='completed'),0) total_spent,
                         COALESCE((SELECT COUNT(*) FROM sales s WHERE s.customer_id=c.id),0) purchases FROM customers c ORDER BY c.name""").fetchall()
        return [dict(r) for r in rows]

@app.post("/api/customers")
def add_customer(p:CustomerIn,user:dict=Depends(access("customers"))):
    with db() as c:
        cur=c.execute("INSERT INTO customers(name,phone,email,address,credit_limit,created_at) VALUES(?,?,?,?,?,?)",(p.name.strip(),p.phone.strip(),p.email.strip(),p.address.strip(),money(p.credit_limit),iso()))
        audit(c,"customer.created",user,branch_id_from(user.get("license")),"customer",cur.lastrowid,{"name":p.name}); return {"id":cur.lastrowid}

@app.get("/api/customers/{customer_id}/statement")
def customer_statement(customer_id:int,user:dict=Depends(access("customers"))):
    with db() as c:
        cust=c.execute("SELECT * FROM customers WHERE id=?",(customer_id,)).fetchone()
        if not cust: raise HTTPException(status_code=404,detail="Customer not found")
        sales=[dict(x) for x in c.execute("SELECT id,receipt_no,total,amount_paid,created_at FROM sales WHERE customer_id=? ORDER BY created_at DESC",(customer_id,)).fetchall()]
        pays=[dict(x) for x in c.execute("SELECT * FROM customer_payments WHERE customer_id=? ORDER BY created_at DESC",(customer_id,)).fetchall()]
        return {"customer":dict(cust),"sales":sales,"payments":pays}

@app.post("/api/customers/{customer_id}/payments")
def customer_payment(customer_id:int,p:PaymentIn,user:dict=Depends(access("customers"))):
    bid=branch_id_from(user.get("license"))
    with db() as c:
        cust=c.execute("SELECT * FROM customers WHERE id=?",(customer_id,)).fetchone()
        if not cust: raise HTTPException(status_code=404,detail="Customer not found")
        amount=min(money(p.amount),money(cust["balance"]));
        if amount<=0: raise HTTPException(status_code=409,detail="Customer has no outstanding balance")
        cur=c.execute("INSERT INTO customer_payments(customer_id,amount,payment_method,reference,branch_id,user_id,created_at) VALUES(?,?,?,?,?,?,?)",(customer_id,amount,p.method,p.reference,bid,user["id"],iso()))
        c.execute("UPDATE customers SET balance=MAX(0,balance-?) WHERE id=?",(amount,customer_id))
        cr=c.execute("SELECT id,name,phone,balance,credit_limit,loyalty_points FROM customers WHERE id=?",(customer_id,)).fetchone()
        if cr: queue_sync(c,"customer.balance",dict(cr),bid)
        journal(c,"customer_payment",cur.lastrowid,"Customer debt payment",[(payment_account(p.method),amount,0,p.method),("1100",0,amount,"Accounts receivable")],bid,user["id"])
        audit(c,"customer.payment",user,bid,"customer",customer_id,{"amount":amount,"method":p.method}); queue_sync(c,"customer.payment",{"customer_id":customer_id,"name":cust["name"],"amount":amount,"method":p.method},bid)
    flush_sync(10); return {"id":cur.lastrowid,"amount":amount}

@app.get("/api/suppliers")
def suppliers(user:dict=Depends(access("suppliers"))):
    with db() as c:
        rows=c.execute("""SELECT s.*,COALESCE((SELECT SUM(total) FROM purchases p WHERE p.supplier_id=s.id),0) total_purchases FROM suppliers s ORDER BY s.name""").fetchall(); return [dict(r) for r in rows]

@app.post("/api/suppliers")
def add_supplier(p:SupplierIn,user:dict=Depends(access("suppliers"))):
    with db() as c:
        cur=c.execute("INSERT INTO suppliers(name,phone,email,address,created_at) VALUES(?,?,?,?,?)",(p.name.strip(),p.phone.strip(),p.email.strip(),p.address.strip(),iso())); audit(c,"supplier.created",user,branch_id_from(user.get("license")),"supplier",cur.lastrowid,{"name":p.name}); return {"id":cur.lastrowid}

@app.get("/api/suppliers/{supplier_id}/statement")
def supplier_statement(supplier_id:int,user:dict=Depends(access("suppliers"))):
    with db() as c:
        s=c.execute("SELECT * FROM suppliers WHERE id=?",(supplier_id,)).fetchone()
        if not s: raise HTTPException(status_code=404,detail="Supplier not found")
        return {"supplier":dict(s),"purchases":[dict(x) for x in c.execute("SELECT * FROM purchases WHERE supplier_id=? ORDER BY created_at DESC",(supplier_id,)).fetchall()],"payments":[dict(x) for x in c.execute("SELECT * FROM supplier_payments WHERE supplier_id=? ORDER BY created_at DESC",(supplier_id,)).fetchall()]}

@app.post("/api/suppliers/{supplier_id}/payments")
def supplier_payment(supplier_id:int,p:PaymentIn,user:dict=Depends(access("suppliers"))):
    bid=branch_id_from(user.get("license"))
    with db() as c:
        s=c.execute("SELECT * FROM suppliers WHERE id=?",(supplier_id,)).fetchone()
        if not s: raise HTTPException(status_code=404,detail="Supplier not found")
        amount=min(money(p.amount),money(s["balance"]));
        if amount<=0: raise HTTPException(status_code=409,detail="Supplier has no outstanding balance")
        cur=c.execute("INSERT INTO supplier_payments(supplier_id,amount,payment_method,reference,branch_id,user_id,created_at) VALUES(?,?,?,?,?,?,?)",(supplier_id,amount,p.method,p.reference,bid,user["id"],iso()))
        c.execute("UPDATE suppliers SET balance=MAX(0,balance-?) WHERE id=?",(amount,supplier_id))
        sr=c.execute("SELECT id,name,phone,balance FROM suppliers WHERE id=?",(supplier_id,)).fetchone()
        if sr: queue_sync(c,"supplier.balance",dict(sr),bid)
        journal(c,"supplier_payment",cur.lastrowid,"Supplier payment",[("2000",amount,0,"Accounts payable"),(payment_account(p.method),0,amount,p.method)],bid,user["id"])
        audit(c,"supplier.payment",user,bid,"supplier",supplier_id,{"amount":amount,"method":p.method}); queue_sync(c,"supplier.payment",{"supplier_id":supplier_id,"name":s["name"],"amount":amount,"method":p.method},bid)
    flush_sync(10); return {"id":cur.lastrowid,"amount":amount}

# ---------- Purchases / expenses ----------
@app.post("/api/purchases")
def create_purchase(p:PurchaseIn,user:dict=Depends(access("purchases"))):
    if not p.items: raise HTTPException(status_code=422,detail="Purchase needs at least one item")
    bid=branch_id_from(user.get("license"),p.branch_id); now=iso(); total=money(sum(x.quantity*x.unit_cost for x in p.items))
    payments=p.payments[:] if p.payments else ([PaymentIn(method="Cash",amount=p.amount_paid)] if p.amount_paid>0 else [])
    paid=min(money(sum(x.amount for x in payments)),total); outstanding=money(total-paid)
    with db() as c:
        cur=c.execute("INSERT INTO purchases(supplier_id,branch_id,user_id,reference,invoice_no,total,amount_paid,status,created_at) VALUES(?,?,?,?,?,?,?,?,?)",(p.supplier_id,bid,user["id"],p.reference,p.invoice_no,total,paid,"received",now)); purchase_id=cur.lastrowid
        for item in p.items:
            prod=c.execute("SELECT * FROM products WHERE id=?",(item.product_id,)).fetchone()
            if not prod: raise HTTPException(status_code=404,detail=f"Product {item.product_id} not found")
            line=money(item.quantity*item.unit_cost)
            c.execute("INSERT INTO purchase_items(purchase_id,product_id,quantity,unit_cost,line_total,batch_no,expiry_date) VALUES(?,?,?,?,?,?,?)",(purchase_id,item.product_id,item.quantity,money(item.unit_cost),line,item.batch_no,item.expiry_date))
            # weighted average cost
            st=product_stock(c,bid,item.product_id); old_qty=float(st["quantity"]); old_cost=float(prod["cost_price"] or 0); new_qty=old_qty+item.quantity
            new_cost=money(((old_qty*old_cost)+(item.quantity*item.unit_cost))/new_qty) if new_qty else money(item.unit_cost)
            c.execute("UPDATE products SET cost_price=?,updated_at=? WHERE id=?",(new_cost,now,item.product_id))
            update_stock(c,bid,item.product_id,item.quantity,"purchase",user,reference=p.reference or p.invoice_no or f"Purchase {purchase_id}",batch_no=item.batch_no)
            if item.batch_no:
                existing=c.execute("SELECT id FROM product_batches WHERE branch_id=? AND product_id=? AND batch_no=?",(bid,item.product_id,item.batch_no)).fetchone()
                if existing: c.execute("UPDATE product_batches SET expiry_date=?,quantity=quantity+? WHERE id=?",(item.expiry_date,item.quantity,existing["id"]))
                else: c.execute("INSERT INTO product_batches(branch_id,product_id,batch_no,expiry_date,quantity,created_at) VALUES(?,?,?,?,?,?)",(bid,item.product_id,item.batch_no,item.expiry_date,item.quantity,now))
        if p.supplier_id and outstanding>0: c.execute("UPDATE suppliers SET balance=balance+? WHERE id=?",(outstanding,p.supplier_id))
        if p.supplier_id:
            sr=c.execute("SELECT id,name,phone,balance FROM suppliers WHERE id=?",(p.supplier_id,)).fetchone()
            if sr: queue_sync(c,"supplier.balance",dict(sr),bid)
        lines=[("1200",total,0,"Inventory purchased")]
        for pay in payments:
            amt=min(money(pay.amount), max(0,total-sum(x[2] for x in lines if x[0] in {"1000","1010","1020"})))
            if amt>0: lines.append((payment_account(pay.method),0,amt,pay.method))
        if outstanding>0: lines.append(("2000",0,outstanding,"Accounts payable"))
        # protect against payment sum > total by using exact paid distribution
        cash_credit=sum(x[2] for x in lines[1:] if x[0]!="2000")
        if abs(cash_credit-paid)>0.01:
            lines=[("1200",total,0,"Inventory purchased")]; rem=paid
            for pay in payments:
                amt=min(money(pay.amount),rem)
                if amt>0: lines.append((payment_account(pay.method),0,amt,pay.method)); rem=money(rem-amt)
            if outstanding>0: lines.append(("2000",0,outstanding,"Accounts payable"))
        journal(c,"purchase",purchase_id,"Stock purchase",lines,bid,user["id"])
        audit(c,"purchase.created",user,bid,"purchase",purchase_id,{"total":total,"paid":paid,"outstanding":outstanding,"supplier_id":p.supplier_id})
        queue_sync(c,"purchase.created",{"id":purchase_id,"total":total,"paid":paid,"outstanding":outstanding,"reference":p.reference,"supplier_id":p.supplier_id},bid,f"purchase:{purchase_id}")
    flush_sync(30); return {"id":purchase_id,"total":total,"paid":paid,"outstanding":outstanding}

@app.get("/api/purchases")
def list_purchases(branch_id:Optional[int]=None,user:dict=Depends(access("purchases"))):
    bid=branch_id_from(user.get("license"),branch_id)
    with db() as c:
        return [dict(r) for r in c.execute("""SELECT p.*,s.name supplier_name,u.name user_name FROM purchases p LEFT JOIN suppliers s ON s.id=p.supplier_id LEFT JOIN users u ON u.id=p.user_id WHERE p.branch_id=? ORDER BY p.created_at DESC LIMIT 500""",(bid,)).fetchall()]

@app.post("/api/expenses")
def add_expense(p:ExpenseIn,user:dict=Depends(access("expenses"))):
    bid=branch_id_from(user.get("license"),p.branch_id); now=iso(); receipt=safe_media_from_data(p.receipt_data,"expense") if p.receipt_data else ""
    with db() as c:
        cur=c.execute("INSERT INTO expenses(category,amount,payment_method,description,supplier_id,branch_id,user_id,receipt_path,recurring,recurrence,next_due,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",(p.category.strip(),money(p.amount),p.payment_method,p.description.strip(),p.supplier_id,bid,user["id"],receipt,int(p.recurring),p.recurrence,p.next_due,now)); eid=cur.lastrowid
        journal(c,"expense",eid,p.description or p.category,[("6000",money(p.amount),0,p.category),(payment_account(p.payment_method),0,money(p.amount),p.payment_method)],bid,user["id"])
        audit(c,"expense.created",user,bid,"expense",eid,{"amount":money(p.amount),"category":p.category,"method":p.payment_method})
        queue_sync(c,"expense.created",{"id":eid,"amount":money(p.amount),"category":p.category,"method":p.payment_method,"description":p.description},bid,f"expense:{eid}")
        if money(p.amount)>=float(setting("sales","unusual_expense_threshold","500") or 500): notify(c,"unusual_expense","Large expense",f"{p.category}: ${money(p.amount):.2f}","warning",bid)
    flush_sync(20); return {"id":eid}

@app.get("/api/expenses")
def list_expenses(branch_id:Optional[int]=None,user:dict=Depends(access("expenses"))):
    bid=branch_id_from(user.get("license"),branch_id)
    with db() as c: return [dict(r) for r in c.execute("SELECT e.*,u.name user_name,s.name supplier_name FROM expenses e LEFT JOIN users u ON u.id=e.user_id LEFT JOIN suppliers s ON s.id=e.supplier_id WHERE e.branch_id=? ORDER BY e.created_at DESC LIMIT 500",(bid,)).fetchall()]

@app.post("/api/expenses/recurring/run")
def run_recurring(user:dict=Depends(access("expenses"))):
    created=[]; today=today_str()
    with db() as c:
        due=c.execute("SELECT * FROM expenses WHERE recurring=1 AND next_due!='' AND date(next_due)<=date(?)",(today,)).fetchall()
        for x in due:
            # record a new non-template expense and advance template schedule
            cur=c.execute("INSERT INTO expenses(category,amount,payment_method,description,supplier_id,branch_id,user_id,receipt_path,recurring,created_at) VALUES(?,?,?,?,?,?,?,?,0,?)",(x["category"],x["amount"],x["payment_method"],x["description"],x["supplier_id"],x["branch_id"],user["id"],x["receipt_path"],iso())); created.append(cur.lastrowid)
            journal(c,"expense",cur.lastrowid,x["description"] or x["category"],[("6000",x["amount"],0,x["category"]),(payment_account(x["payment_method"]),0,x["amount"],x["payment_method"])],x["branch_id"],user["id"])
            nd=datetime.fromisoformat(x["next_due"])
            if x["recurrence"]=="weekly": nd+=timedelta(days=7)
            elif x["recurrence"]=="yearly": nd=nd.replace(year=nd.year+1)
            else:
                month=nd.month+1; year=nd.year+(month>12); month=1 if month>12 else month; day=min(nd.day,28); nd=nd.replace(year=year,month=month,day=day)
            c.execute("UPDATE expenses SET next_due=? WHERE id=?",(nd.date().isoformat(),x["id"]))
    return {"created":created}

# ---------- Held sale / sale checkout ----------
@app.get("/api/sales/held")
def held_sales(branch_id:Optional[int]=None,user:dict=Depends(access("sell"))):
    bid=branch_id_from(user.get("license"),branch_id)
    with db() as c: return [dict(r)|{"payload":json_load(r["payload"],{})} for r in c.execute("SELECT * FROM held_sales WHERE branch_id=? ORDER BY updated_at DESC",(bid,)).fetchall()]

@app.post("/api/sales/hold")
def hold_sale(p:HoldSaleIn,user:dict=Depends(access("sell"))):
    bid=branch_id_from(user.get("license"),p.branch_id); now=iso()
    with db() as c:
        cur=c.execute("INSERT INTO held_sales(name,branch_id,user_id,payload,created_at,updated_at) VALUES(?,?,?,?,?,?)",(p.name,bid,user["id"],json.dumps(p.payload),now,now)); audit(c,"sale.held",user,bid,"held_sale",cur.lastrowid,{"name":p.name})
    return {"id":cur.lastrowid}

@app.delete("/api/sales/held/{held_id}")
def delete_held(held_id:int,user:dict=Depends(access("sell"))):
    with db() as c: c.execute("DELETE FROM held_sales WHERE id=?",(held_id,)); audit(c,"sale.held_deleted",user,branch_id_from(user.get("license")),"held_sale",held_id)
    return {"ok":True}


def approval_is_valid(cloud_id:Optional[str], request_type:str) -> bool:
    if not cloud_id: return False
    try:
        lic=read_license(); r=cloud_json(f"/api/approvals/{urllib.parse.quote(cloud_id)}/status",None,"GET",{"X-License-Token":lic.get("license_token","")})
        return r.get("status")=="approved" and r.get("request_type")==request_type
    except Exception: return False

@app.post("/api/sales")
def create_sale(p:SaleIn,user:dict=Depends(access("sell"))):
    if not p.items: raise HTTPException(status_code=422,detail="Sale needs at least one item")
    bid=branch_id_from(user.get("license"),p.branch_id); now=iso(); perms=user.get("permissions") or default_permissions(user["role"])
    key=p.idempotency_key.strip() or None
    if key and len(key)<16: raise HTTPException(422,"Invalid checkout request identifier")
    # Cashiers require approval when discount is above configured percentage of pre-discount subtotal.
    with db() as c:
        # Replaying a completed request must not deduct stock or collect payment again.
        if key:
            previous=c.execute("SELECT * FROM sales WHERE idempotency_key=?",(key,)).fetchone()
            if previous:
                if previous["user_id"]!=user["id"] or previous["branch_id"]!=bid:
                    raise HTTPException(409,"Checkout identifier belongs to another session")
                result={"id":previous["id"],"receipt_no":previous["receipt_no"],
                    "subtotal":previous["subtotal"],"discount":previous["discount"],
                    "tax_total":previous["tax_total"],"total":previous["total"],
                    "amount_paid":previous["amount_paid"],"change_due":previous["change_due"],
                    "outstanding":money(previous["total"]-previous["amount_paid"]),"replayed":True}
                if user["role"]!="cashier": result["gross_profit"]=previous["gross_profit"]
                return result
        prepared=[]; raw_subtotal=0.0; total_cost=0.0; total_item_discount=0.0; total_tax=0.0
        for item in p.items:
            prod=c.execute("SELECT * FROM products WHERE id=? AND active=1",(item.product_id,)).fetchone()
            if not prod: raise HTTPException(status_code=404,detail=f"Product {item.product_id} not found")
            st=product_stock(c,bid,item.product_id)
            if float(st["quantity"])<item.quantity: raise HTTPException(status_code=409,detail=f"Not enough stock for {prod['name']}")
            price=money(item.unit_price if item.unit_price is not None else (prod["wholesale_price"] if p.sale_type=="wholesale" and prod["wholesale_price"]>0 else prod["sell_price"]))
            line_base=money(price*item.quantity); item_disc=min(money(item.discount),line_base); taxable=max(0,line_base-item_disc); rate=float(prod["tax_rate"] or 0) if setting("tax","enabled","false")=="true" else 0
            tax=money(taxable*rate/100); line_total=money(taxable+tax)
            raw_subtotal+=line_base; total_item_discount+=item_disc; total_tax+=tax; total_cost+=money(float(prod["cost_price"])*item.quantity)
            prepared.append((item,prod,price,item_disc,rate,tax,line_total))
        sale_discount=min(money(p.discount),money(raw_subtotal-total_item_discount)); discount_pct=(sale_discount/raw_subtotal*100) if raw_subtotal else 0
        limit=float(setting("sales","cashier_discount_limit","5") or 5)
        if user["role"]=="cashier" and discount_pct>limit and "discount" not in perms and not approval_is_valid(p.approval_id,"discount"):
            raise HTTPException(status_code=409,detail=f"REMOTE_APPROVAL_REQUIRED:discount:{discount_pct:.2f}")
        taxable_before_sale_disc=max(0,raw_subtotal-total_item_discount)
        # Allocate sale discount proportionally against tax base. Recompute tax after global discount.
        if sale_discount>0 and taxable_before_sale_disc>0:
            total_tax=0.0; adjusted=[]
            for item,prod,price,item_disc,rate,tax,line_total in prepared:
                base=max(0,price*item.quantity-item_disc); alloc=sale_discount*(base/taxable_before_sale_disc); new_base=max(0,base-alloc); tax=money(new_base*rate/100); line_total=money(new_base+tax); total_tax+=tax; adjusted.append((item,prod,price,item_disc+alloc,rate,tax,line_total))
            prepared=adjusted
        subtotal=money(raw_subtotal); total_discount=money(total_item_discount+sale_discount); total=money(sum(x[6] for x in prepared)); total_cost=money(total_cost); gross_profit=money(total-total_tax-total_cost)
        payments=p.payments[:] if p.payments else []
        if not payments:
            amt=p.amount_paid if p.amount_paid is not None else total; payments=[PaymentIn(method=p.payment_method,amount=max(0,float(amt)))]
        tendered=money(sum(x.amount for x in payments)); applied=min(tendered,total); change=money(max(0,tendered-total)); outstanding=money(max(0,total-applied))
        if outstanding>0 and not p.customer_id: raise HTTPException(status_code=422,detail="Select a customer for a credit/part-paid sale")
        if p.customer_id:
            cust=c.execute("SELECT * FROM customers WHERE id=?",(p.customer_id,)).fetchone()
            if not cust: raise HTTPException(status_code=404,detail="Customer not found")
            if money(cust["balance"]+outstanding)>money(cust["credit_limit"]) and cust["credit_limit"]>0: raise HTTPException(status_code=409,detail="Customer credit limit would be exceeded")
        rec=next_number(c,"receipt","sales","receipt_no")
        method="Mixed" if len(payments)>1 else payments[0].method
        cur=c.execute("""INSERT INTO sales(receipt_no,branch_id,user_id,subtotal,discount,tax_total,total,cost_total,gross_profit,payment_method,amount_paid,change_due,customer_id,status,sale_type,note,created_at,idempotency_key)
                       VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,'completed',?,?,?,?)""",(rec,bid,user["id"],subtotal,total_discount,money(total_tax),total,total_cost,gross_profit,method,applied,change,p.customer_id,p.sale_type,p.note,now,key)); sale_id=cur.lastrowid
        for item,prod,price,item_disc,rate,tax,line_total in prepared:
            si=c.execute("INSERT INTO sale_items(sale_id,product_id,product_name,quantity,unit_price,unit_cost,discount,tax_rate,tax_amount,line_total) VALUES(?,?,?,?,?,?,?,?,?,?)",(sale_id,prod["id"],prod["name"],item.quantity,price,money(prod["cost_price"]),money(item_disc),rate,tax,line_total)).lastrowid
            update_stock(c,bid,prod["id"],-item.quantity,"sale",user,reference=rec)
        rem=applied
        for pay in payments:
            a=min(money(pay.amount),rem)
            if a<=0: continue
            c.execute("INSERT INTO sale_payments(sale_id,method,amount,reference) VALUES(?,?,?,?)",(sale_id,pay.method,a,pay.reference)); rem=money(rem-a)
        if outstanding>0:
            c.execute("UPDATE customers SET balance=balance+? WHERE id=?",(outstanding,p.customer_id)); notify(c,"credit_sale","Credit sale",f"{rec} has ${outstanding:.2f} outstanding.","info",bid)
        if p.customer_id:
            loyalty=float(setting("sales","loyalty_percent","0") or 0)
            if loyalty>0: c.execute("UPDATE customers SET loyalty_points=loyalty_points+? WHERE id=?",(money(total*loyalty/100),p.customer_id))
            cr=c.execute("SELECT id,name,phone,balance,credit_limit,loyalty_points FROM customers WHERE id=?",(p.customer_id,)).fetchone()
            if cr: queue_sync(c,"customer.balance",dict(cr),bid)
        lines=[]; rev=money(total-total_tax)
        rem=applied
        for pay in payments:
            a=min(money(pay.amount),rem)
            if a>0: lines.append((payment_account(pay.method),a,0,pay.method)); rem=money(rem-a)
        if outstanding>0: lines.append(("1100",outstanding,0,"Accounts receivable"))
        lines.append(("4000",0,rev,"Sales revenue"))
        if total_tax>0: lines.append(("2200",0,money(total_tax),"Tax payable"))
        if total_cost>0: lines.extend([("5000",total_cost,0,"Cost of goods sold"),("1200",0,total_cost,"Inventory")])
        journal(c,"sale",sale_id,rec,lines,bid,user["id"])
        audit(c,"sale.completed",user,bid,"sale",sale_id,{"receipt_no":rec,"total":total,"discount":total_discount,"tax":money(total_tax),"profit":gross_profit,"outstanding":outstanding})
        queue_sync(c,"sale.completed",{"id":sale_id,"receipt_no":rec,"total":total,"gross_profit":gross_profit,"tax":money(total_tax),"payment_method":method,"customer_id":p.customer_id,"user_name":user["name"],"items":[{"product_id":x[1]["id"],"name":x[1]["name"],"quantity":x[0].quantity,"total":x[6]} for x in prepared]},bid,f"sale:{rec}")
        if total>=float(setting("sales","large_sale_threshold","1000") or 1000): notify(c,"large_sale","Large sale",f"{rec}: ${total:.2f}","info",bid)
        if discount_pct>limit: notify(c,"large_discount","Large discount",f"{rec}: {discount_pct:.1f}% discount by {user['name']}","warning",bid)
    flush_sync(50)
    result={"id":sale_id,"receipt_no":rec,"subtotal":subtotal,"discount":total_discount,"tax_total":money(total_tax),"total":total,"amount_paid":applied,"change_due":change,"outstanding":outstanding}
    if user["role"]!="cashier": result["gross_profit"]=gross_profit
    return result

@app.get("/api/sales/recent")
def recent_sales(branch_id:Optional[int]=None,user:dict=Depends(access("sell"))):
    bid=branch_id_from(user.get("license"),branch_id)
    with db() as c:
        rows=[dict(r) for r in c.execute("SELECT s.*,c.name customer_name,u.name user_name FROM sales s LEFT JOIN customers c ON c.id=s.customer_id LEFT JOIN users u ON u.id=s.user_id WHERE s.branch_id=? ORDER BY s.created_at DESC LIMIT 200",(bid,)).fetchall()]
    if user["role"] == "cashier":
        rows=[r for r in rows if r["user_id"]==user["id"]]
        for r in rows:
            for field in ("cost_total","gross_profit"):
                r.pop(field,None)
    return rows

@app.get("/api/sales/{sale_id}")
def sale_detail(sale_id:int,user:dict=Depends(access("sell"))):
    with db() as c:
        s=c.execute("SELECT s.*,c.name customer_name,c.phone customer_phone,u.name user_name,b.name branch_name FROM sales s LEFT JOIN customers c ON c.id=s.customer_id LEFT JOIN users u ON u.id=s.user_id LEFT JOIN branches b ON b.id=s.branch_id WHERE s.id=?",(sale_id,)).fetchone()
        if not s: raise HTTPException(status_code=404,detail="Sale not found")
        if user["role"] == "cashier" and s["user_id"] != user["id"]:
            raise HTTPException(403,"Cashiers can only access their own sales")
        info=dict(s)
        items=[dict(x) for x in c.execute("SELECT * FROM sale_items WHERE sale_id=? ORDER BY id",(sale_id,)).fetchall()]
        if user["role"] == "cashier":
            for field in ("cost_total","gross_profit"):
                info.pop(field,None)
            for item in items:
                for field in ("unit_cost","profit","cost_total"):
                    item.pop(field,None)
        return {"sale":info,"items":items,"payments":[dict(x) for x in c.execute("SELECT * FROM sale_payments WHERE sale_id=?",(sale_id,)).fetchall()]}

# ---------- Returns / refunds ----------
@app.post("/api/returns")
def create_return(p:ReturnIn,user:dict=Depends(current_user),lic:dict=Depends(require_license)):
    if user["role"] == "cashier": raise HTTPException(403,"Cashiers are restricted to selling. Ask a manager to process refunds")
    if not p.items: raise HTTPException(status_code=422,detail="Select at least one returned item")
    user["license"] = lic
    bid=branch_id_from(lic,p.branch_id); now=iso(); perms=user.get("permissions") or default_permissions(user["role"])
    if "*" not in perms and "refund" not in perms and not approval_is_valid(p.approval_id,"refund"):
        raise HTTPException(status_code=409,detail="REMOTE_APPROVAL_REQUIRED:refund")
    with db() as c:
        sale=c.execute("SELECT * FROM sales WHERE id=?",(p.sale_id,)).fetchone()
        if not sale: raise HTTPException(status_code=404,detail="Original sale not found")
        prepared=[]; refund=0.0; cost=0.0; restock_cost=0.0; tax_return=0.0
        for ri in p.items:
            si=c.execute("SELECT * FROM sale_items WHERE id=? AND sale_id=?",(ri.sale_item_id,p.sale_id)).fetchone()
            if not si: raise HTTPException(status_code=404,detail=f"Sale item {ri.sale_item_id} not found")
            already=c.execute("SELECT COALESCE(SUM(quantity),0) FROM return_items WHERE sale_item_id=?",(ri.sale_item_id,)).fetchone()[0]
            if ri.quantity>float(si["quantity"])-float(already)+1e-9: raise HTTPException(status_code=409,detail=f"Return quantity exceeds sold quantity for {si['product_name']}")
            unit_ref=float(si["line_total"])/float(si["quantity"]); unit_tax=float(si["tax_amount"] or 0)/float(si["quantity"]); line=money(unit_ref*ri.quantity); tax=money(unit_tax*ri.quantity); cst=money(float(si["unit_cost"])*ri.quantity)
            refund+=line; tax_return+=tax; cost+=cst
            if ri.restock: restock_cost+=cst
            prepared.append((ri,si,line,tax,cst))
        refund=money(refund); tax_return=money(tax_return); cost=money(cost); restock_cost=money(restock_cost)
        cur=c.execute("INSERT INTO returns(sale_id,branch_id,user_id,refund_total,refund_method,reason,created_at) VALUES(?,?,?,?,?,?,?)",(p.sale_id,bid,user["id"],refund,p.refund_method,p.reason,now)); rid=cur.lastrowid
        for ri,si,line,tax,cst in prepared:
            c.execute("INSERT INTO return_items(return_id,sale_item_id,product_id,quantity,unit_price,unit_cost,restock,line_total) VALUES(?,?,?,?,?,?,?,?)",(rid,ri.sale_item_id,si["product_id"],ri.quantity,si["unit_price"],si["unit_cost"],int(ri.restock),line))
            if ri.restock: update_stock(c,bid,si["product_id"],ri.quantity,"return",user,reference=f"RET-{rid}",reason=p.reason)
        net=money(refund-tax_return); lines=[("4000",net,0,"Sales return")]
        if tax_return>0: lines.append(("2200",tax_return,0,"Tax reversal"))
        if p.refund_method.lower() in {"customer credit","credit"} and sale["customer_id"]:
            bal=c.execute("SELECT balance FROM customers WHERE id=?",(sale["customer_id"],)).fetchone()[0]; applied=min(refund,float(bal)); c.execute("UPDATE customers SET balance=MAX(0,balance-?) WHERE id=?",(applied,sale["customer_id"])); lines.append(("1100",0,applied,"Reduce receivable"))
            if refund>applied: lines.append(("1000",0,money(refund-applied),"Cash refund"))
        else: lines.append((payment_account(p.refund_method),0,refund,p.refund_method))
        if restock_cost>0: lines.extend([("1200",restock_cost,0,"Inventory returned"),("5000",0,restock_cost,"COGS reversal")])
        journal(c,"return",rid,f"Return for {sale['receipt_no']}",lines,bid,user["id"])
        fully=True
        for si in c.execute("SELECT id,quantity FROM sale_items WHERE sale_id=?",(p.sale_id,)).fetchall():
            rt=c.execute("SELECT COALESCE(SUM(quantity),0) FROM return_items WHERE sale_item_id=?",(si["id"],)).fetchone()[0]
            if float(rt)<float(si["quantity"])-1e-9: fully=False; break
        c.execute("UPDATE sales SET status=? WHERE id=?",("returned" if fully else "partially_returned",p.sale_id))
        audit(c,"return.created",user,bid,"return",rid,{"sale_id":p.sale_id,"refund":refund,"method":p.refund_method,"reason":p.reason})
        notify(c,"refund","Refund processed",f"{sale['receipt_no']}: ${refund:.2f} refunded by {user['name']}","warning",bid)
        queue_sync(c,"refund.created",{"id":rid,"sale_id":p.sale_id,"receipt_no":sale["receipt_no"],"refund":refund,"method":p.refund_method,"reason":p.reason,"user_name":user["name"]},bid,f"return:{rid}")
    flush_sync(30); return {"id":rid,"refund_total":refund,"status":"returned" if fully else "partially_returned"}

@app.get("/api/returns")
def list_returns(branch_id:Optional[int]=None,user:dict=Depends(current_user),lic:dict=Depends(require_license)):
    bid=branch_id_from(lic,branch_id)
    with db() as c: return [dict(r) for r in c.execute("SELECT r.*,s.receipt_no,u.name user_name FROM returns r JOIN sales s ON s.id=r.sale_id LEFT JOIN users u ON u.id=r.user_id WHERE r.branch_id=? ORDER BY r.created_at DESC",(bid,)).fetchall()]

# ---------- Quotations & invoices ----------
def document_totals(items:list[DocumentItemIn],discount:float) -> tuple[float,float,float,float]:
    subtotal=money(sum(x.quantity*x.unit_price for x in items)); disc=min(money(discount),subtotal); taxable=max(0,subtotal-disc); tax=0.0
    if subtotal>0:
        for x in items:
            base=x.quantity*x.unit_price; alloc=disc*(base/subtotal); tax+=max(0,base-alloc)*x.tax_rate/100
    tax=money(tax); return subtotal,disc,tax,money(taxable+tax)

@app.post("/api/documents")
def create_document(p:DocumentIn,user:dict=Depends(access("documents"))):
    kind="invoice" if p.doc_type.lower()=="invoice" else "quote"; bid=branch_id_from(user.get("license"),p.branch_id); now=iso(); subtotal,disc,tax,total=document_totals(p.items,p.discount)
    with db() as c:
        no=next_number(c,kind,"documents","doc_no")
        cur=c.execute("INSERT INTO documents(doc_type,doc_no,customer_id,branch_id,user_id,status,subtotal,discount,tax_total,total,due_date,note,created_at,updated_at) VALUES(?,?,?,?,?,'draft',?,?,?,?,?,?,?,?)",(kind,no,p.customer_id,bid,user["id"],subtotal,disc,tax,total,p.due_date,p.note,now,now)); did=cur.lastrowid
        for x in p.items:
            desc=x.description
            if x.product_id and not desc:
                pr=c.execute("SELECT name FROM products WHERE id=?",(x.product_id,)).fetchone(); desc=pr["name"] if pr else "Product"
            base=money(x.quantity*x.unit_price); line=money(base+base*x.tax_rate/100)
            c.execute("INSERT INTO document_items(document_id,product_id,description,quantity,unit_price,tax_rate,line_total) VALUES(?,?,?,?,?,?,?)",(did,x.product_id,desc,x.quantity,money(x.unit_price),money(x.tax_rate),line))
        audit(c,f"{kind}.created",user,bid,"document",did,{"doc_no":no,"total":total}); queue_sync(c,"document.created",{"id":did,"type":kind,"doc_no":no,"total":total,"status":"draft","customer_id":p.customer_id},bid,f"doc:{did}")
    flush_sync(20); return {"id":did,"doc_no":no,"subtotal":subtotal,"discount":disc,"tax_total":tax,"total":total}

@app.get("/api/documents")
def list_documents(doc_type:str="",branch_id:Optional[int]=None,user:dict=Depends(access("documents"))):
    bid=branch_id_from(user.get("license"),branch_id); q="SELECT d.*,c.name customer_name,u.name user_name FROM documents d LEFT JOIN customers c ON c.id=d.customer_id LEFT JOIN users u ON u.id=d.user_id WHERE d.branch_id=?"; vals:list[Any]=[bid]
    if doc_type: q+=" AND d.doc_type=?"; vals.append(doc_type)
    q+=" ORDER BY d.created_at DESC LIMIT 500"
    with db() as c: return [dict(r) for r in c.execute(q,vals).fetchall()]

@app.get("/api/documents/{doc_id}")
def document_detail(doc_id:int,user:dict=Depends(access("documents"))):
    with db() as c:
        d=c.execute("SELECT d.*,c.name customer_name,c.phone customer_phone,c.email customer_email FROM documents d LEFT JOIN customers c ON c.id=d.customer_id WHERE d.id=?",(doc_id,)).fetchone()
        if not d: raise HTTPException(status_code=404,detail="Document not found")
        return {"document":dict(d),"items":[dict(x) for x in c.execute("SELECT * FROM document_items WHERE document_id=?",(doc_id,)).fetchall()],"payments":[dict(x) for x in c.execute("SELECT * FROM document_payments WHERE document_id=?",(doc_id,)).fetchall()]}

@app.post("/api/documents/{doc_id}/to-invoice")
def quote_to_invoice(doc_id:int,user:dict=Depends(access("documents"))):
    with db() as c:
        q=c.execute("SELECT * FROM documents WHERE id=? AND doc_type='quote'",(doc_id,)).fetchone()
        if not q: raise HTTPException(status_code=404,detail="Quotation not found")
        items=[DocumentItemIn(product_id=x["product_id"],description=x["description"],quantity=x["quantity"],unit_price=x["unit_price"],tax_rate=x["tax_rate"]) for x in c.execute("SELECT * FROM document_items WHERE document_id=?",(doc_id,)).fetchall()]
    inv=create_document(DocumentIn(doc_type="invoice",customer_id=q["customer_id"],items=items,discount=q["discount"],due_date=q["due_date"] or "",note=f"Converted from {q['doc_no']}",branch_id=q["branch_id"]),user)
    with db() as c: c.execute("UPDATE documents SET status='converted',updated_at=? WHERE id=?",(iso(),doc_id)); audit(c,"quote.converted",user,q["branch_id"],"document",doc_id,{"invoice_id":inv["id"]})
    return inv

@app.post("/api/documents/{doc_id}/payments")
def document_payment(doc_id:int,p:DocPaymentIn,user:dict=Depends(access("documents"))):
    with db() as c:
        d=c.execute("SELECT * FROM documents WHERE id=? AND doc_type='invoice'",(doc_id,)).fetchone()
        if not d: raise HTTPException(status_code=404,detail="Invoice not found")
        remaining=money(d["total"]-d["amount_paid"]); amount=min(money(p.amount),remaining)
        cur=c.execute("INSERT INTO document_payments(document_id,amount,payment_method,reference,created_at) VALUES(?,?,?,?,?)",(doc_id,amount,p.payment_method,p.reference,iso()))
        newpaid=money(d["amount_paid"]+amount); status="paid" if newpaid>=d["total"]-0.01 else "partially_paid"; c.execute("UPDATE documents SET amount_paid=?,status=?,updated_at=? WHERE id=?",(newpaid,status,iso(),doc_id)); audit(c,"invoice.payment_recorded",user,d["branch_id"],"document",doc_id,{"amount":amount,"status":status})
        return {"id":cur.lastrowid,"amount":amount,"status":status,"amount_paid":newpaid}

@app.post("/api/documents/{doc_id}/to-sale")
def invoice_to_sale(doc_id:int,user:dict=Depends(access("documents"))):
    with db() as c:
        d=c.execute("SELECT * FROM documents WHERE id=? AND doc_type='invoice'",(doc_id,)).fetchone()
        if not d: raise HTTPException(status_code=404,detail="Invoice not found")
        if d["converted_sale_id"]: return {"sale_id":d["converted_sale_id"],"already_converted":True}
        its=c.execute("SELECT * FROM document_items WHERE document_id=?",(doc_id,)).fetchall(); pays=c.execute("SELECT * FROM document_payments WHERE document_id=?",(doc_id,)).fetchall()
    sale_items=[]
    for x in its:
        if not x["product_id"]: raise HTTPException(status_code=409,detail="Invoice contains a custom line that cannot reduce stock. Attach a product first.")
        sale_items.append(SaleItemIn(product_id=x["product_id"],quantity=x["quantity"],unit_price=x["unit_price"]))
    payments=[PaymentIn(method=x["payment_method"],amount=x["amount"],reference=x["reference"] or "") for x in pays]
    if not payments: payments=[PaymentIn(method="Cash",amount=d["total"])]
    sale=create_sale(SaleIn(items=sale_items,discount=d["discount"],payments=payments,customer_id=d["customer_id"],branch_id=d["branch_id"],note=f"From invoice {d['doc_no']}"),user)
    with db() as c: c.execute("UPDATE documents SET status='converted',converted_sale_id=?,updated_at=? WHERE id=?",(sale["id"],iso(),doc_id)); audit(c,"invoice.converted",user,d["branch_id"],"document",doc_id,{"sale_id":sale["id"]})
    return sale

# ---------- Cash register / shifts ----------
def shift_expected(c:sqlite3.Connection,shift:sqlite3.Row) -> float:
    start=shift["opened_at"]; uid=shift["user_id"]; bid=shift["branch_id"]
    sales=c.execute("""SELECT COALESCE(SUM(sp.amount),0) FROM sale_payments sp JOIN sales s ON s.id=sp.sale_id WHERE s.branch_id=? AND s.user_id=? AND s.created_at>=? AND lower(sp.method)='cash'""",(bid,uid,start)).fetchone()[0]
    cp=c.execute("SELECT COALESCE(SUM(amount),0) FROM customer_payments WHERE branch_id=? AND user_id=? AND created_at>=? AND lower(payment_method)='cash'",(bid,uid,start)).fetchone()[0]
    ex=c.execute("SELECT COALESCE(SUM(amount),0) FROM expenses WHERE branch_id=? AND user_id=? AND created_at>=? AND lower(payment_method)='cash'",(bid,uid,start)).fetchone()[0]
    spay=c.execute("SELECT COALESCE(SUM(amount),0) FROM supplier_payments WHERE branch_id=? AND user_id=? AND created_at>=? AND lower(payment_method)='cash'",(bid,uid,start)).fetchone()[0]
    refunds=c.execute("SELECT COALESCE(SUM(refund_total),0) FROM returns WHERE branch_id=? AND user_id=? AND created_at>=? AND lower(refund_method)='cash'",(bid,uid,start)).fetchone()[0]
    moves=c.execute("SELECT COALESCE(SUM(CASE WHEN movement_type='add' THEN amount ELSE -amount END),0) FROM cash_movements WHERE shift_id=?",(shift["id"],)).fetchone()[0]
    return money(shift["opening_cash"]+sales+cp-ex-spay-refunds+moves)

@app.get("/api/cash/current")
def current_shift(user:dict=Depends(access("cash"))):
    bid=branch_id_from(user.get("license"))
    with db() as c:
        s=c.execute("SELECT * FROM cash_shifts WHERE branch_id=? AND user_id=? AND status='open' ORDER BY id DESC LIMIT 1",(bid,user["id"])).fetchone()
        if not s: return {"open":False}
        return {"open":True,"shift":dict(s),"expected_cash":shift_expected(c,s),"movements":[dict(x) for x in c.execute("SELECT * FROM cash_movements WHERE shift_id=? ORDER BY created_at DESC",(s["id"],)).fetchall()]}

@app.post("/api/cash/open")
def open_shift(p:CashShiftOpenIn,user:dict=Depends(access("cash"))):
    bid=branch_id_from(user.get("license"),p.branch_id)
    with db() as c:
        if c.execute("SELECT 1 FROM cash_shifts WHERE branch_id=? AND user_id=? AND status='open'",(bid,user["id"])).fetchone(): raise HTTPException(status_code=409,detail="You already have an open shift")
        cur=c.execute("INSERT INTO cash_shifts(branch_id,user_id,opening_cash,opened_at,status) VALUES(?,?,?,?,'open')",(bid,user["id"],money(p.opening_cash),iso())); audit(c,"shift.opened",user,bid,"shift",cur.lastrowid,{"opening_cash":money(p.opening_cash)}); queue_sync(c,"shift.opened",{"shift_id":cur.lastrowid,"user_name":user["name"],"opening_cash":money(p.opening_cash)},bid)
    flush_sync(10); return {"id":cur.lastrowid}

@app.post("/api/cash/move")
def cash_move(p:CashMoveIn,user:dict=Depends(access("cash"))):
    bid=branch_id_from(user.get("license"))
    if p.movement_type not in {"add","remove"}: raise HTTPException(status_code=422,detail="movement_type must be add or remove")
    with db() as c:
        s=c.execute("SELECT * FROM cash_shifts WHERE branch_id=? AND user_id=? AND status='open' ORDER BY id DESC LIMIT 1",(bid,user["id"])).fetchone()
        if not s: raise HTTPException(status_code=409,detail="Open a cash shift first")
        cur=c.execute("INSERT INTO cash_movements(shift_id,branch_id,user_id,movement_type,amount,reason,created_at) VALUES(?,?,?,?,?,?,?)",(s["id"],bid,user["id"],p.movement_type,money(p.amount),p.reason,iso())); audit(c,"cash."+p.movement_type,user,bid,"shift",s["id"],{"amount":money(p.amount),"reason":p.reason})
        return {"id":cur.lastrowid,"expected_cash":shift_expected(c,s)}

@app.post("/api/cash/close")
def close_shift(p:CashShiftCloseIn,user:dict=Depends(access("cash"))):
    bid=branch_id_from(user.get("license"))
    with db() as c:
        s=c.execute("SELECT * FROM cash_shifts WHERE branch_id=? AND user_id=? AND status='open' ORDER BY id DESC LIMIT 1",(bid,user["id"])).fetchone()
        if not s: raise HTTPException(status_code=409,detail="No open shift")
        exp=shift_expected(c,s); diff=money(p.actual_cash-exp); c.execute("UPDATE cash_shifts SET expected_cash=?,actual_cash=?,difference=?,closed_at=?,status='closed' WHERE id=?",(exp,money(p.actual_cash),diff,iso(),s["id"])); audit(c,"shift.closed",user,bid,"shift",s["id"],{"expected":exp,"actual":money(p.actual_cash),"difference":diff}); queue_sync(c,"shift.closed",{"shift_id":s["id"],"user_name":user["name"],"expected":exp,"actual":money(p.actual_cash),"difference":diff},bid)
        if abs(diff)>0.01: notify(c,"cash_shortage" if diff<0 else "cash_overage","Cash difference",f"{user['name']} closed with ${diff:.2f} difference.","warning",bid)
    flush_sync(20); return {"expected_cash":exp,"actual_cash":money(p.actual_cash),"difference":diff}

@app.get("/api/cash/shifts")
def shift_history(branch_id:Optional[int]=None,user:dict=Depends(access("cash"))):
    bid=branch_id_from(user.get("license"),branch_id)
    with db() as c: return [dict(r) for r in c.execute("SELECT cs.*,u.name user_name FROM cash_shifts cs JOIN users u ON u.id=cs.user_id WHERE cs.branch_id=? ORDER BY opened_at DESC LIMIT 300",(bid,)).fetchall()]

# ---------- Remote approvals ----------
@app.post("/api/approvals/request")
def request_approval(p:ApprovalIn,user:dict=Depends(current_user),lic:dict=Depends(require_license)):
    bid=branch_id_from(lic,p.branch_id)
    result=cloud_json("/api/approvals",{"device_id":DEVICE_ID,"license_token":lic["license_token"],"request_type":p.request_type,"branch_id":bid,"requested_by":user["name"],"details":p.details},"POST")
    with db() as c:
        cur=c.execute("INSERT INTO approval_requests(cloud_id,request_type,details,status,created_at) VALUES(?,?,?,'pending',?)",(result["id"],p.request_type,json.dumps(p.details),iso())); audit(c,"approval.requested",user,bid,"approval",result["id"],p.details)
    return {"id":result["id"],"local_id":cur.lastrowid,"status":"pending"}

@app.get("/api/approvals/{cloud_id}")
def check_approval(cloud_id:str,user:dict=Depends(current_user),lic:dict=Depends(require_license)):
    result=cloud_json(f"/api/approvals/{urllib.parse.quote(cloud_id)}/status",None,"GET",{"X-License-Token":lic["license_token"]})
    with db() as c: c.execute("UPDATE approval_requests SET status=?,resolved_at=? WHERE cloud_id=?",(result.get("status"),iso() if result.get("status")!="pending" else None,cloud_id))
    return result

# ---------- Accounting / dashboard / reports ----------
def account_balances(c:sqlite3.Connection,start:str="",end:str="",branch_id:Optional[int]=None) -> list[dict[str,Any]]:
    where=[]; vals:list[Any]=[]
    if start: where.append("substr(je.created_at,1,10)>=?"); vals.append(start)
    if end: where.append("substr(je.created_at,1,10)<=?"); vals.append(end)
    if branch_id: where.append("je.branch_id=?"); vals.append(branch_id)
    ws=(" WHERE "+" AND ".join(where)) if where else ""
    rows=c.execute(f"""SELECT a.code,a.name,a.account_type,COALESCE(SUM(jl.debit),0) debit,COALESCE(SUM(jl.credit),0) credit
                    FROM accounts a LEFT JOIN journal_lines jl ON jl.account_code=a.code LEFT JOIN journal_entries je ON je.id=jl.entry_id{ws}
                    GROUP BY a.code,a.name,a.account_type ORDER BY a.code""",vals).fetchall()
    out=[]
    for r in rows:
        d=dict(r); d["debit"]=money(d["debit"]); d["credit"]=money(d["credit"]); d["balance"]=money((d["debit"]-d["credit"]) if d["account_type"] in {"asset","expense"} else (d["credit"]-d["debit"])); out.append(d)
    return out

@app.get("/api/money")
def money_overview(branch_id:Optional[int]=None,user:dict=Depends(access("money"))):
    bid=branch_id_from(user.get("license"),branch_id)
    with db() as c:
        income=c.execute("SELECT COALESCE(SUM(total),0) FROM sales WHERE branch_id=? AND status!='voided'",(bid,)).fetchone()[0]
        refunds=c.execute("SELECT COALESCE(SUM(refund_total),0) FROM returns WHERE branch_id=?",(bid,)).fetchone()[0]
        costs=c.execute("SELECT COALESCE(SUM(cost_total),0) FROM sales WHERE branch_id=?",(bid,)).fetchone()[0]
        returned_cost=c.execute("SELECT COALESCE(SUM(ri.unit_cost*ri.quantity),0) FROM return_items ri JOIN returns r ON r.id=ri.return_id WHERE r.branch_id=? AND ri.restock=1",(bid,)).fetchone()[0]
        expenses=c.execute("SELECT COALESCE(SUM(amount),0) FROM expenses WHERE branch_id=?",(bid,)).fetchone()[0]
        purchases=c.execute("SELECT COALESCE(SUM(total),0) FROM purchases WHERE branch_id=?",(bid,)).fetchone()[0]
        rec=c.execute("SELECT COALESCE(SUM(balance),0) FROM customers").fetchone()[0]; pay=c.execute("SELECT COALESCE(SUM(balance),0) FROM suppliers").fetchone()[0]
        cash=next((x["balance"] for x in account_balances(c,branch_id=bid) if x["code"]=="1000"),0)
        gross=money(income-refunds-(costs-returned_cost)); net=money(gross-expenses)
        return {"money_in":money(income-refunds),"money_out":money(expenses),"purchases":money(purchases),"gross_profit":gross,"net_profit":net,"customers_owe":money(rec),"owe_suppliers":money(pay),"cash_available":money(cash)}

@app.get("/api/accounting/trial-balance")
def trial_balance(start:str="",end:str="",branch_id:Optional[int]=None,user:dict=Depends(access("money"))):
    bid=branch_id_from(user.get("license"),branch_id)
    with db() as c: rows=account_balances(c,start,end,bid)
    return {"rows":rows,"total_debit":money(sum(x["debit"] for x in rows)),"total_credit":money(sum(x["credit"] for x in rows))}

@app.get("/api/accounting/profit-loss")
def profit_loss(start:str="",end:str="",branch_id:Optional[int]=None,user:dict=Depends(access("money"))):
    bid=branch_id_from(user.get("license"),branch_id); start=start or datetime.now().replace(day=1).strftime("%Y-%m-%d"); end=end or today_str()
    with db() as c:
        rows=account_balances(c,start,end,bid); income=sum(x["balance"] for x in rows if x["account_type"]=="income"); expenses=sum(x["balance"] for x in rows if x["account_type"]=="expense")
        return {"start":start,"end":end,"income":money(income),"expenses":money(expenses),"net_profit":money(income-expenses),"accounts":[x for x in rows if x["account_type"] in {"income","expense"}]}

@app.get("/api/accounting/balance-sheet")
def balance_sheet(branch_id:Optional[int]=None,user:dict=Depends(access("money"))):
    bid=branch_id_from(user.get("license"),branch_id)
    with db() as c:
        rows=account_balances(c,branch_id=bid); assets=[x for x in rows if x["account_type"]=="asset"]; liabilities=[x for x in rows if x["account_type"]=="liability"]; equity=[x for x in rows if x["account_type"]=="equity"]
        income=sum(x["balance"] for x in rows if x["account_type"]=="income"); exp=sum(x["balance"] for x in rows if x["account_type"]=="expense"); retained=money(income-exp)
        return {"assets":assets,"liabilities":liabilities,"equity":equity,"retained_earnings":retained,"total_assets":money(sum(x["balance"] for x in assets)),"total_liabilities_equity":money(sum(x["balance"] for x in liabilities)+sum(x["balance"] for x in equity)+retained)}

@app.get("/api/accounting/cash-flow")
def cash_flow(start:str="",end:str="",branch_id:Optional[int]=None,user:dict=Depends(access("money"))):
    bid=branch_id_from(user.get("license"),branch_id); start=start or datetime.now().replace(day=1).strftime("%Y-%m-%d"); end=end or today_str()
    with db() as c:
        rows=c.execute("""SELECT je.created_at,je.source_type,je.memo,jl.account_code,jl.debit,jl.credit FROM journal_lines jl JOIN journal_entries je ON je.id=jl.entry_id
                          WHERE je.branch_id=? AND substr(je.created_at,1,10) BETWEEN ? AND ? AND jl.account_code IN ('1000','1010','1020') ORDER BY je.created_at""",(bid,start,end)).fetchall()
        detail=[dict(x)|{"net":money(x["debit"]-x["credit"])} for x in rows]; net=money(sum(x["net"] for x in detail)); inflow=money(sum(max(0,x["net"]) for x in detail)); outflow=money(sum(max(0,-x["net"]) for x in detail))
        return {"start":start,"end":end,"cash_in":inflow,"cash_out":outflow,"net_cash_flow":net,"rows":detail}

# ---------- Yola budgeting and bank statement reconciliation ----------
# Imported statement lines are not posted to the ledger automatically. They
# must be matched to actual journal entries, preventing fabricated balances.
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP

class BudgetInput(BaseModel):
    year_month: str
    category: str
    amount: str
    branch_id: Optional[int] = None

class BankImportInput(BaseModel):
    csv_text: str = Field(max_length=500000)
    bank_account: str = "1020"
    currency: str = "USD"
    branch_id: Optional[int] = None

class BankMatchInput(BaseModel):
    journal_entry_id: int


def currency_cents(value) -> int:
    try:
        x = Decimal(str(value))
        if not x.is_finite() or abs(x) > 1_000_000_000:
            raise ValueError()
        rounded = x.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
        if x != rounded:
            raise ValueError()
        return int(rounded * 100)
    except (InvalidOperation, ValueError, TypeError):
        raise HTTPException(422,'Amount must be a finite number with at most two decimal places')


def validate_month(value: str) -> str:
    try:
        dt = datetime.strptime(value,'%Y-%m')
        if dt.strftime('%Y-%m') == value: return value
    except ValueError: pass
    raise HTTPException(422,'Budget month must be YYYY-MM')

@app.get('/api/accounting/budgets')
def list_budgets(year_month: str='',branch_id:Optional[int]=None,user:dict=Depends(access('money'))):
    bid=branch_id_from(user.get('license'),branch_id)
    month=validate_month(year_month or datetime.now().strftime('%Y-%m'))
    with db() as c:
        items=[dict(x) for x in c.execute('SELECT category,amount_cents FROM budgets WHERE branch_id=? AND year_month=? ORDER BY category',(bid,month))]
        actual={x['category']:currency_cents(x['total'] or 0) for x in c.execute('''
          SELECT category,SUM(amount) total FROM expenses WHERE branch_id=? AND substr(created_at,1,7)=?
          GROUP BY category''',(bid,month))}
    return {'year_month':month,'branch_id':bid,'rows':[
      {'category':x['category'],'budget':x['amount_cents']/100,'actual':actual.get(x['category'],0)/100,
       'variance':(x['amount_cents']-actual.get(x['category'],0))/100} for x in items]}

@app.put('/api/accounting/budgets')
def upsert_budget(p:BudgetInput,user:dict=Depends(access('money'))):
    month=validate_month(p.year_month);category=p.category.strip()
    if not category or len(category)>90: raise HTTPException(422,'Budget category must be between 1 and 90 characters')
    amount=currency_cents(p.amount)
    if amount<0: raise HTTPException(422,'Budget cannot be negative')
    bid=branch_id_from(user.get('license'),p.branch_id)
    with db() as c:
        c.execute('''INSERT INTO budgets(branch_id,year_month,category,amount_cents,updated_by,updated_at)
          VALUES(?,?,?,?,?,?) ON CONFLICT(branch_id,year_month,category) DO UPDATE SET
          amount_cents=excluded.amount_cents,updated_by=excluded.updated_by,updated_at=excluded.updated_at''',
          (bid,month,category,amount,user['id'],iso()))
        audit(c,'budget.updated',user,bid,'budget',category,{'month':month,'amount_cents':amount})
    return {'ok':True,'year_month':month,'category':category,'amount':amount/100}

@app.post('/api/accounting/bank/import')
def import_bank_statement(p:BankImportInput,user:dict=Depends(access('money'))):
    if p.bank_account!='1020':
        raise HTTPException(422,'Bank reconciliation currently supports ledger account 1020 (Bank / Card) only')
    if p.currency.upper()!='USD':
        raise HTTPException(422,'Only USD statements are supported until currency journals are implemented')
    reader=csv.DictReader(io.StringIO(p.csv_text))
    if not reader.fieldnames or not {'date','description','amount','reference'}.issubset(set(reader.fieldnames)):
        raise HTTPException(422,'CSV must contain date,description,amount,reference headers')
    rows=[]
    for n,row in enumerate(reader,1):
        if n>5000: raise HTTPException(413,'Maximum 5000 bank statement rows per import')
        date=(row.get('date') or '').strip();desc=(row.get('description') or '').strip();ref=(row.get('reference') or '').strip()
        try:
            d=datetime.strptime(date,'%Y-%m-%d')
            if d.strftime('%Y-%m-%d')!=date:raise ValueError()
        except ValueError: raise HTTPException(422,f'Invalid date on CSV row {n}')
        if not desc or len(desc)>400 or len(ref)>150:
            raise HTTPException(422,f'Invalid description or reference on CSV row {n}')
        cents=currency_cents(row.get('amount'))
        if cents==0: raise HTTPException(422,f'Zero amount on CSV row {n}')
        # Reference is the bank-provided transaction ID. Require it to avoid
        # silently collapsing real same-day same-amount transactions.
        if not ref: raise HTTPException(422,f'Bank reference required on CSV row {n}')
        fingerprint=hashlib.sha256((p.bank_account+'|'+ref+'|'+date+'|'+str(cents)).encode()).hexdigest()
        rows.append((date,desc,cents,ref,fingerprint))
    bid=branch_id_from(user.get('license'),p.branch_id)
    added=0
    with db() as c:
        for date,desc,cents,ref,fingerprint in rows:
            cur=c.execute('''INSERT OR IGNORE INTO bank_statement_lines(
              branch_id,bank_account,source_fingerprint,posted_date,description,amount_cents,reference,currency,imported_by,imported_at)
              VALUES(?,?,?,?,?,?,?,'USD',?,?)''',(bid,p.bank_account,fingerprint,date,desc,cents,ref,user['id'],iso()))
            added+=cur.rowcount
        audit(c,'bank.statement_imported',user,bid,'bank_statement',None,
              {'rows':len(rows),'added':added,'duplicates':len(rows)-added,'account':p.bank_account})
    return {'ok':True,'rows':len(rows),'added':added,'duplicates':len(rows)-added}

@app.get('/api/accounting/bank/lines')
def bank_lines(branch_id:Optional[int]=None,user:dict=Depends(access('money'))):
    bid=branch_id_from(user.get('license'),branch_id)
    with db() as c: rows=[dict(x) for x in c.execute('''SELECT id,posted_date,description,reference,currency,
       amount_cents,matched_entry_id FROM bank_statement_lines WHERE branch_id=? ORDER BY posted_date DESC,id DESC LIMIT 500''',(bid,))]
    return [{'id':x['id'],'date':x['posted_date'],'description':x['description'],
       'amount':x['amount_cents']/100,'reference':x['reference'],'currency':x['currency'],
       'matched_entry_id':x['matched_entry_id']} for x in rows]

@app.post('/api/accounting/bank/lines/{line_id}/match')
def match_bank_line(line_id:int,p:BankMatchInput,user:dict=Depends(access('money'))):
    bid=branch_id_from(user.get('license'))
    with db() as c:
        line=c.execute('SELECT * FROM bank_statement_lines WHERE id=? AND branch_id=?',(line_id,bid)).fetchone()
        if not line: raise HTTPException(404,'Bank statement line not found')
        if line['matched_entry_id'] is not None: raise HTTPException(409,'This bank statement line is already matched')
        # Require same branch and exact bank-account journal net (cent precision).
        journal=c.execute('''SELECT je.id,SUM(jl.debit-jl.credit) net FROM journal_entries je
           JOIN journal_lines jl ON jl.entry_id=je.id AND jl.account_code=?
           WHERE je.id=? AND je.branch_id=? GROUP BY je.id''',
           (line['bank_account'],p.journal_entry_id,bid)).fetchone()
        if not journal or currency_cents(journal['net']) != line['amount_cents']:
            raise HTTPException(409,'Journal entry does not match this bank transaction amount or branch')
        if c.execute('SELECT 1 FROM bank_statement_lines WHERE matched_entry_id=?',(p.journal_entry_id,)).fetchone():
            raise HTTPException(409,'Journal entry is already reconciled to another statement line')
        c.execute('UPDATE bank_statement_lines SET matched_entry_id=? WHERE id=?',(p.journal_entry_id,line_id))
        audit(c,'bank.reconciled',user,bid,'bank_statement',line_id,
              {'journal_entry_id':p.journal_entry_id,'amount_cents':line['amount_cents']})
    return {'ok':True,'line_id':line_id,'journal_entry_id':p.journal_entry_id}

@app.get("/api/dashboard")
def dashboard(branch_id:Optional[int]=None,user:dict=Depends(access("reports")),lic:dict=Depends(require_license)):
    bid=branch_id_from(lic,branch_id); today=today_str()
    with db() as c:
        sales=c.execute("SELECT COALESCE(SUM(total),0) total,COALESCE(SUM(gross_profit),0) gp,COUNT(*) cnt FROM sales WHERE branch_id=? AND substr(created_at,1,10)=? AND status!='voided'",(bid,today)).fetchone()
        ret=c.execute("""SELECT COALESCE(SUM(ri.line_total),0) refund_total,
                    COALESCE(SUM((si.tax_amount/NULLIF(si.quantity,0))*ri.quantity),0) tax_return,
                    COALESCE(SUM(CASE WHEN ri.restock=1 THEN ri.unit_cost*ri.quantity ELSE 0 END),0) restock_cost
                    FROM return_items ri JOIN returns r ON r.id=ri.return_id JOIN sale_items si ON si.id=ri.sale_item_id
                    WHERE r.branch_id=? AND substr(r.created_at,1,10)=?""",(bid,today)).fetchone()
        refunds=money(ret["refund_total"]); refund_gp_effect=money((ret["refund_total"]-ret["tax_return"])-ret["restock_cost"])
        exp=c.execute("SELECT COALESCE(SUM(amount),0) FROM expenses WHERE branch_id=? AND substr(created_at,1,10)=?",(bid,today)).fetchone()[0]
        stock=c.execute("SELECT COALESCE(SUM(bs.quantity*p.cost_price),0) value,SUM(CASE WHEN bs.quantity<=bs.min_stock THEN 1 ELSE 0 END) low FROM branch_stock bs JOIN products p ON p.id=bs.product_id WHERE bs.branch_id=? AND p.active=1",(bid,)).fetchone()
        rec=c.execute("SELECT COALESCE(SUM(balance),0) FROM customers").fetchone()[0]; pay=c.execute("SELECT COALESCE(SUM(balance),0) FROM suppliers").fetchone()[0]
        cash=next((x["balance"] for x in account_balances(c,branch_id=bid) if x["code"]=="1000"),0)
        series=c.execute("""WITH RECURSIVE days(d) AS (SELECT date('now','-6 day') UNION ALL SELECT date(d,'+1 day') FROM days WHERE d<date('now'))
                            SELECT d,COALESCE((SELECT SUM(total) FROM sales WHERE branch_id=? AND substr(created_at,1,10)=d),0) total FROM days""",(bid,)).fetchall()
        recent=c.execute("SELECT s.id,s.receipt_no,s.total,s.payment_method,s.created_at,u.name user_name FROM sales s LEFT JOIN users u ON u.id=s.user_id WHERE s.branch_id=? ORDER BY s.created_at DESC LIMIT 8",(bid,)).fetchall()
        b=c.execute("SELECT name FROM branches WHERE id=?",(bid,)).fetchone()
        return {"business_name":lic.get("business_name"),"branch_name":b[0] if b else "Branch","today_sales":money(sales["total"]-refunds),"today_gross_profit":money(sales["gp"]-refund_gp_effect),"today_expenses":money(exp),"today_net":money(sales["gp"]-refund_gp_effect-exp),"cash_available":money(cash),"transactions":int(sales["cnt"]),"stock_value":money(stock["value"]),"low_stock_count":int(stock["low"] or 0),"receivables":money(rec),"payables":money(pay),"sales_series":[{"date":x["d"],"total":money(x["total"])} for x in series],"recent_sales":[dict(x) for x in recent]}

@app.get("/api/reports/summary")
def report_summary(start:str="",end:str="",branch_id:Optional[int]=None,user:dict=Depends(access("reports"))):
    bid=branch_id_from(user.get("license"),branch_id); start=start or datetime.now().replace(day=1).strftime("%Y-%m-%d"); end=end or today_str()
    with db() as c:
        s=c.execute("SELECT COALESCE(SUM(total),0) revenue,COALESCE(SUM(cost_total),0) cost,COALESCE(SUM(gross_profit),0) gp,COALESCE(SUM(tax_total),0) tax,COUNT(*) cnt FROM sales WHERE branch_id=? AND substr(created_at,1,10) BETWEEN ? AND ?",(bid,start,end)).fetchone()
        ret=c.execute("""SELECT COALESCE(SUM(ri.line_total),0) refund_total,
                    COALESCE(SUM((si.tax_amount/NULLIF(si.quantity,0))*ri.quantity),0) tax_return,
                    COALESCE(SUM(CASE WHEN ri.restock=1 THEN ri.unit_cost*ri.quantity ELSE 0 END),0) restock_cost
                    FROM return_items ri JOIN returns r ON r.id=ri.return_id JOIN sale_items si ON si.id=ri.sale_item_id
                    WHERE r.branch_id=? AND substr(r.created_at,1,10) BETWEEN ? AND ?""",(bid,start,end)).fetchone()
        refunds=money(ret["refund_total"]); refund_gp_effect=money((ret["refund_total"]-ret["tax_return"])-ret["restock_cost"])
        ex=c.execute("SELECT COALESCE(SUM(amount),0) FROM expenses WHERE branch_id=? AND substr(created_at,1,10) BETWEEN ? AND ?",(bid,start,end)).fetchone()[0]
        top=c.execute("""SELECT si.product_id,si.product_name,SUM(si.quantity) qty,SUM(si.line_total) revenue,SUM(si.unit_cost*si.quantity) cost,SUM((si.unit_price-si.unit_cost)*si.quantity-si.discount) profit
                        FROM sale_items si JOIN sales s ON s.id=si.sale_id WHERE s.branch_id=? AND substr(s.created_at,1,10) BETWEEN ? AND ? GROUP BY si.product_id,si.product_name ORDER BY revenue DESC LIMIT 20""",(bid,start,end)).fetchall()
        series=c.execute("SELECT substr(created_at,1,10) day,SUM(total) total FROM sales WHERE branch_id=? AND substr(created_at,1,10) BETWEEN ? AND ? GROUP BY day ORDER BY day",(bid,start,end)).fetchall()
        bycat=c.execute("""SELECT p.category,SUM(si.line_total) total FROM sale_items si JOIN products p ON p.id=si.product_id JOIN sales s ON s.id=si.sale_id WHERE s.branch_id=? AND substr(s.created_at,1,10) BETWEEN ? AND ? GROUP BY p.category ORDER BY total DESC""",(bid,start,end)).fetchall()
        bypay=c.execute("""SELECT sp.method,SUM(sp.amount) total FROM sale_payments sp JOIN sales s ON s.id=sp.sale_id WHERE s.branch_id=? AND substr(s.created_at,1,10) BETWEEN ? AND ? GROUP BY sp.method ORDER BY total DESC""",(bid,start,end)).fetchall()
        hourly=c.execute("SELECT substr(created_at,12,2) hour,SUM(total) total FROM sales WHERE branch_id=? AND substr(created_at,1,10) BETWEEN ? AND ? GROUP BY hour ORDER BY hour",(bid,start,end)).fetchall()
        users=c.execute("SELECT u.name cashier,COUNT(s.id) transactions,SUM(s.total) sales FROM sales s LEFT JOIN users u ON u.id=s.user_id WHERE s.branch_id=? AND substr(s.created_at,1,10) BETWEEN ? AND ? GROUP BY s.user_id,u.name ORDER BY sales DESC",(bid,start,end)).fetchall()
        revenue=money(s["revenue"]-refunds); gp=money(s["gp"]-refund_gp_effect); net=money(gp-ex)
        return {"start":start,"end":end,"revenue":revenue,"refunds":money(refunds),"cost_of_goods":money(s["cost"]),"gross_profit":gp,"expenses":money(ex),"net_profit":net,"tax":money(s["tax"]),"transactions":int(s["cnt"]),"top_products":[dict(x) for x in top],"series":[{"date":x["day"],"total":money(x["total"])} for x in series],"by_category":[dict(x) for x in bycat],"by_payment":[dict(x) for x in bypay],"hourly":[dict(x) for x in hourly],"cashiers":[dict(x) for x in users]}

@app.get("/api/reports/product-accounting")
def product_accounting(start:str="",end:str="",branch_id:Optional[int]=None,user:dict=Depends(access("reports"))):
    bid=branch_id_from(user.get("license"),branch_id); start=start or "1900-01-01"; end=end or "2999-12-31"
    with db() as c:
        rows=c.execute("""SELECT p.id,p.name,p.sku,p.category,p.cost_price,p.sell_price,bs.quantity units_remaining,bs.quantity*p.cost_price stock_value,
          COALESCE((SELECT SUM(pi.quantity) FROM purchase_items pi JOIN purchases pu ON pu.id=pi.purchase_id WHERE pi.product_id=p.id AND pu.branch_id=? AND substr(pu.created_at,1,10) BETWEEN ? AND ?),0) units_purchased,
          COALESCE((SELECT SUM(pi.line_total) FROM purchase_items pi JOIN purchases pu ON pu.id=pi.purchase_id WHERE pi.product_id=p.id AND pu.branch_id=? AND substr(pu.created_at,1,10) BETWEEN ? AND ?),0) spent,
          COALESCE((SELECT SUM(si.quantity) FROM sale_items si JOIN sales s ON s.id=si.sale_id WHERE si.product_id=p.id AND s.branch_id=? AND substr(s.created_at,1,10) BETWEEN ? AND ?),0) units_sold,
          COALESCE((SELECT SUM(si.line_total) FROM sale_items si JOIN sales s ON s.id=si.sale_id WHERE si.product_id=p.id AND s.branch_id=? AND substr(s.created_at,1,10) BETWEEN ? AND ?),0) revenue,
          COALESCE((SELECT SUM(si.unit_cost*si.quantity) FROM sale_items si JOIN sales s ON s.id=si.sale_id WHERE si.product_id=p.id AND s.branch_id=? AND substr(s.created_at,1,10) BETWEEN ? AND ?),0) cost_of_goods
          FROM products p JOIN branch_stock bs ON bs.product_id=p.id AND bs.branch_id=? WHERE p.active=1 ORDER BY revenue DESC""",
          (bid,start,end,bid,start,end,bid,start,end,bid,start,end,bid,start,end,bid)).fetchall()
        out=[]
        for r in rows:
            d=dict(r)
            ret=c.execute("""SELECT COALESCE(SUM(ri.quantity),0) qty,COALESCE(SUM(ri.line_total),0) refund,
                              COALESCE(SUM(CASE WHEN ri.restock=1 THEN ri.unit_cost*ri.quantity ELSE 0 END),0) restock_cost
                              FROM return_items ri JOIN returns rr ON rr.id=ri.return_id
                              WHERE ri.product_id=? AND rr.branch_id=? AND substr(rr.created_at,1,10) BETWEEN ? AND ?""",(d["id"],bid,start,end)).fetchone()
            d["units_sold"]=max(0,money(d["units_sold"]-ret["qty"])); d["revenue"]=money(d["revenue"]-ret["refund"]); d["cost_of_goods"]=money(d["cost_of_goods"]-ret["restock_cost"])
            d["gross_profit"]=money(d["revenue"]-d["cost_of_goods"]); d["profit_margin"]=money((d["gross_profit"]/d["revenue"]*100) if d["revenue"] else 0); d["dead_stock"]=bool(d["units_remaining"]>0 and d["units_sold"]==0); out.append(d)
        return out

@app.get("/api/reports/export.xlsx")
def export_xlsx(start:str="",end:str="",branch_id:Optional[int]=None,user:dict=Depends(access("reports"))):
    data=report_summary(start,end,branch_id,user); wb=Workbook(); ws=wb.active; ws.title="Summary"
    for row in [("Yola Report",),("Period",f"{data['start']} to {data['end']}"),("Revenue",data["revenue"]),("Gross Profit",data["gross_profit"]),("Expenses",data["expenses"]),("Net Profit",data["net_profit"]),("Tax",data["tax"]),("Transactions",data["transactions"])]: ws.append(row)
    wp=wb.create_sheet("Products"); wp.append(["Product","Qty","Revenue","Cost","Profit"])
    for x in data["top_products"]: wp.append([x["product_name"],x["qty"],x["revenue"],x["cost"],x["profit"]])
    buf=io.BytesIO(); wb.save(buf); buf.seek(0); return StreamingResponse(buf,media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",headers={"Content-Disposition":f"attachment; filename=Yola-Report-{data['start']}-{data['end']}.xlsx"})

@app.get("/api/reports/export.pdf")
def export_report_pdf(start:str="",end:str="",branch_id:Optional[int]=None,user:dict=Depends(access("reports"))):
    data=report_summary(start,end,branch_id,user); buf=io.BytesIO(); doc=SimpleDocTemplate(buf,pagesize=A4,rightMargin=16*mm,leftMargin=16*mm,topMargin=18*mm,bottomMargin=18*mm); styles=getSampleStyleSheet(); story=[Paragraph("Yola Business Report",styles["Title"]),Paragraph(f"{data['start']} to {data['end']}",styles["Normal"]),Spacer(1,8)]
    table=Table([["Revenue","Gross Profit","Expenses","Net Profit","Tax"],[f"${data['revenue']:.2f}",f"${data['gross_profit']:.2f}",f"${data['expenses']:.2f}",f"${data['net_profit']:.2f}",f"${data['tax']:.2f}"]],repeatRows=1); table.setStyle(TableStyle([("BACKGROUND",(0,0),(-1,0),colors.HexColor("#111827")),("TEXTCOLOR",(0,0),(-1,0),colors.white),("GRID",(0,0),(-1,-1),.25,colors.HexColor("#D1D5DB")),("PADDING",(0,0),(-1,-1),7)])); story+=[table,Spacer(1,14),Paragraph("Top Products",styles["Heading2"])]
    rows=[["Product","Qty","Revenue","Profit"]]+[[x["product_name"],f"{x['qty']:g}",f"${x['revenue']:.2f}",f"${x['profit']:.2f}"] for x in data["top_products"]]; t=Table(rows,repeatRows=1,colWidths=[80*mm,20*mm,30*mm,30*mm]); t.setStyle(TableStyle([("BACKGROUND",(0,0),(-1,0),colors.HexColor("#E5E7EB")),("GRID",(0,0),(-1,-1),.25,colors.HexColor("#D1D5DB")),("PADDING",(0,0),(-1,-1),5)])); story.append(t); doc.build(story); buf.seek(0); return StreamingResponse(buf,media_type="application/pdf",headers={"Content-Disposition":f"attachment; filename=Yola-Report-{data['start']}-{data['end']}.pdf"})

# ---------- Audit / notifications / sync ----------
@app.get("/api/audit")
def audit_list(branch_id:Optional[int]=None,user:dict=Depends(access("audit"))):
    bid=branch_id_from(user.get("license"),branch_id)
    with db() as c:
        return [dict(r) for r in c.execute("SELECT a.*,u.name user_name FROM audit_log a LEFT JOIN users u ON u.id=a.user_id WHERE a.branch_id=? OR a.branch_id IS NULL ORDER BY a.created_at DESC LIMIT 700",(bid,)).fetchall()]

@app.get("/api/notifications")
def notifications(user:dict=Depends(current_user),_:dict=Depends(require_license)):
    if user["role"] == "cashier": raise HTTPException(403,"Notifications are for managers and owners")
    with db() as c: return [dict(r) for r in c.execute("SELECT * FROM notifications ORDER BY read ASC,created_at DESC LIMIT 200").fetchall()]

@app.post("/api/notifications/{notification_id}/read")
def notification_read(notification_id:int,user:dict=Depends(current_user),_:dict=Depends(require_license)):
    with db() as c: c.execute("UPDATE notifications SET read=1 WHERE id=?",(notification_id,))
    return {"ok":True}

@app.post("/api/sync/flush")
def api_flush(user:dict=Depends(current_user),_:dict=Depends(require_license)): return flush_sync(250)

# ---------- Backup / restore ----------
def backup_key() -> bytes:
    """Device-bound encryption key for reliable encrypted backup/restore."""
    lic=read_license(); token=lic.get("license_token","")
    if not token:
        raise HTTPException(status_code=423,detail="Activation required before backup")
    try:
        payload=token.split(".",1)[0]
        claims=json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
        stable_key=str(claims["backup_key"])
        if claims.get("device_id")!=DEVICE_ID: raise ValueError("Device mismatch")
    except Exception:
        raise HTTPException(423,"Signed business backup key is not available")
    raw=("DG-POS-BACKUP-v4|"+DEVICE_ID+"|"+stable_key).encode()
    return base64.urlsafe_b64encode(hashlib.sha256(raw).digest())


def create_backup_file(label:str="manual") -> Path:
    ts=datetime.now().strftime("%Y%m%d-%H%M%S"); temp=BACKUP_DIR/f"DG-POS-{label}-{ts}.zip"; dest=BACKUP_DIR/f"DG-POS-{label}-{ts}.dgbackup"
    # sqlite online backup for consistency
    snap=BACKUP_DIR/f"snapshot-{uuid.uuid4().hex}.db"
    src=sqlite3.connect(DB_PATH); dst=sqlite3.connect(snap); src.backup(dst); dst.close(); src.close()
    try:
        with zipfile.ZipFile(temp,"w",zipfile.ZIP_DEFLATED) as z:
            z.write(snap,"dgpos.db")
            if MEDIA_DIR.exists():
                for f in MEDIA_DIR.rglob("*"):
                    if f.is_file(): z.write(f,"media/"+f.name)
            z.writestr("manifest.json",json.dumps({"version":VERSION,"created_at":iso(),"device_id":DEVICE_ID,"business_id":read_license().get("business_id")}))
        encrypted=Fernet(backup_key()).encrypt(temp.read_bytes()); dest.write_bytes(encrypted)
    finally:
        snap.unlink(missing_ok=True); temp.unlink(missing_ok=True)
    return dest

@app.get("/api/backups")
def backups(user:dict=Depends(access("audit"))):
    return [{"name":p.name,"size":p.stat().st_size,"modified":datetime.fromtimestamp(p.stat().st_mtime).isoformat()} for p in sorted(BACKUP_DIR.glob("*.dgbackup"),key=lambda x:x.stat().st_mtime,reverse=True)]

@app.post("/api/backups/create")
def backup_create(user:dict=Depends(access("audit"))):
    p=create_backup_file("manual"); set_setting("backup","last_auto",iso())
    with db() as c: audit(c,"backup.created",user,branch_id_from(user.get("license")),"backup",p.name,{"size":p.stat().st_size})
    return {"name":p.name,"size":p.stat().st_size}

@app.post("/api/backups/cloud")
def backup_cloud(user:dict=Depends(access("audit"))):
    p=create_backup_file("cloud"); lic=read_license(); raw=base64.b64encode(p.read_bytes()).decode()
    result=cloud_json("/api/backups",{"device_id":DEVICE_ID,"license_token":lic["license_token"],"name":p.name,"data_b64":raw,"created_at":iso()},"POST",timeout=25)
    with db() as c: audit(c,"backup.cloud_uploaded",user,branch_id_from(user.get("license")),"backup",p.name,{"cloud_id":result.get("id")})
    return result.get("backup",result)

@app.get("/api/backups/cloud")
def backup_cloud_list(user:dict=Depends(access("audit"))):
    lic=read_license(); result=cloud_json("/api/backups",None,"GET",{"X-Device-Id":DEVICE_ID,"X-License-Token":lic["license_token"]},timeout=20); return result

@app.post("/api/backups/restore/{name}")
def backup_restore(name:str,user:dict=Depends(access("audit"))):
    if any(x in name for x in ["/","\\",".."]): raise HTTPException(status_code=400,detail="Invalid backup name")
    p=BACKUP_DIR/name
    if not p.exists(): raise HTTPException(status_code=404,detail="Backup not found")
    try: raw=Fernet(backup_key()).decrypt(p.read_bytes())
    except Exception: raise HTTPException(status_code=409,detail="Backup cannot be decrypted for this business")
    temp=BACKUP_DIR/f"restore-{uuid.uuid4().hex}.zip"; temp.write_bytes(raw); work=BACKUP_DIR/f"restore-{uuid.uuid4().hex}"; work.mkdir()
    try:
        with zipfile.ZipFile(temp) as z: z.extractall(work)
        restored=work/"dgpos.db"
        if not restored.exists(): raise HTTPException(status_code=409,detail="Backup database missing")
        pre=create_backup_file("before-restore")
        shutil.copy2(restored,DB_PATH)
        media=work/"media"
        if media.exists():
            for f in media.iterdir():
                if f.is_file(): shutil.copy2(f,MEDIA_DIR/f.name)
        init_db()
        return {"ok":True,"restored":name,"safety_backup":pre.name}
    finally:
        temp.unlink(missing_ok=True); shutil.rmtree(work,ignore_errors=True)

@app.post("/api/backups/cloud/{backup_id}/restore")
def restore_cloud(backup_id:int,user:dict=Depends(access("audit"))):
    lic=read_license(); result=cloud_json(f"/api/backups/{backup_id}",None,"GET",{"X-Device-Id":DEVICE_ID,"X-License-Token":lic["license_token"]},timeout=25)
    raw=result.get("backup",result); name=raw.get("name",f"cloud-{backup_id}.dgbackup"); p=BACKUP_DIR/name; p.write_bytes(base64.b64decode(raw["data_b64"])); return backup_restore(name,user)

# ---------- Hardware ----------
def windows_printers() -> list[str]:
    if platform.system().lower()!="windows": return []
    try:
        import win32print  # type: ignore
        return [x[2] for x in win32print.EnumPrinters(win32print.PRINTER_ENUM_LOCAL|win32print.PRINTER_ENUM_CONNECTIONS)]
    except Exception: return []

@app.get("/api/hardware/printers")
def printers(user:dict=Depends(current_user),_:dict=Depends(require_license)):
    return {"printers":windows_printers(),"selected":setting("printer","name","")}


def raw_print(printer_name:str,data:bytes) -> None:
    if platform.system().lower()!="windows": raise HTTPException(status_code=501,detail="Direct printer output is available on Windows builds")
    try:
        import win32print  # type: ignore
        h=win32print.OpenPrinter(printer_name)
        try:
            job=win32print.StartDocPrinter(h,1,("Yola","", "RAW")); win32print.StartPagePrinter(h); win32print.WritePrinter(h,data); win32print.EndPagePrinter(h); win32print.EndDocPrinter(h)
        finally: win32print.ClosePrinter(h)
    except Exception as e: raise HTTPException(status_code=500,detail=f"Printer error: {e}")


def receipt_text(sale_id:int) -> str:
    with db() as c:
        s=c.execute("SELECT s.*,c.name customer_name FROM sales s LEFT JOIN customers c ON c.id=s.customer_id WHERE s.id=?",(sale_id,)).fetchone()
        if not s: raise HTTPException(status_code=404,detail="Sale not found")
        items=c.execute("SELECT * FROM sale_items WHERE sale_id=?",(sale_id,)).fetchall()
    name=read_license().get("business_name") or setting("business","name","Yola Business"); lines=[name,setting("business","phone",""),setting("business","address",""),"",f"Receipt {s['receipt_no']}",s["created_at"],"-"*32]
    for i in items: lines += [f"{i['product_name']}  x{i['quantity']:g}",f"  ${i['line_total']:.2f}"]
    lines += ["-"*32,f"Subtotal: ${s['subtotal']:.2f}",f"Discount: ${s['discount']:.2f}",f"Tax: ${s['tax_total']:.2f}",f"TOTAL: ${s['total']:.2f}",f"Paid: ${s['amount_paid']:.2f}",f"Change: ${s['change_due']:.2f}",f"Payment: {s['payment_method']}",setting("receipt","footer","Thank you"),"Powered by Double Gee Tech"]
    return "\n".join(x for x in lines if x is not None)

def receipt_pdf_bytes(sale_id:int, page_size:str="thermal") -> tuple[bytes,str]:
    with db() as c:
        sale=c.execute("SELECT s.*,c.name customer_name,c.phone customer_phone,b.name branch_name FROM sales s LEFT JOIN customers c ON c.id=s.customer_id LEFT JOIN branches b ON b.id=s.branch_id WHERE s.id=?",(sale_id,)).fetchone()
        if not sale: raise HTTPException(status_code=404,detail="Sale not found")
        items=c.execute("SELECT * FROM sale_items WHERE sale_id=? ORDER BY id",(sale_id,)).fetchall()
        pays=c.execute("SELECT * FROM sale_payments WHERE sale_id=?",(sale_id,)).fetchall()
    buf=io.BytesIO(); a4=page_size.lower()=="a4"; ps=A4 if a4 else (80*mm,max(145*mm,(92+len(items)*10)*mm))
    margin=14*mm if a4 else 5*mm; doc=SimpleDocTemplate(buf,pagesize=ps,rightMargin=margin,leftMargin=margin,topMargin=margin,bottomMargin=margin)
    styles=getSampleStyleSheet(); story=[Paragraph(escape_html(read_license().get("business_name") or setting("business","name","Yola Business")),styles["Heading2"]),Paragraph(escape_html(setting("business","address","")+" "+setting("business","phone","")),styles["Normal"]),Spacer(1,6),Paragraph(f"<b>Receipt {escape_html(sale['receipt_no'])}</b>",styles["Normal"]),Paragraph(escape_html(str(sale["created_at"])),styles["Normal"]),Spacer(1,8)]
    data=[["Item","Qty","Amount"]]+[[str(i["product_name"]),f"{i['quantity']:g}",f"${i['line_total']:.2f}"] for i in items]
    t=Table(data,colWidths=([90*mm,25*mm,35*mm] if a4 else [43*mm,10*mm,17*mm]),repeatRows=1); t.setStyle(TableStyle([("BACKGROUND",(0,0),(-1,0),colors.HexColor("#F2F4F7")),("GRID",(0,0),(-1,-1),.25,colors.HexColor("#D0D5DD")),("FONTSIZE",(0,0),(-1,-1),8),("PADDING",(0,0),(-1,-1),4),("ALIGN",(1,1),(-1,-1),"RIGHT")]))
    story += [t,Spacer(1,8)]
    totals=[["Subtotal",f"${sale['subtotal']:.2f}"],["Discount",f"${sale['discount']:.2f}"],["Tax",f"${sale['tax_total']:.2f}"],["TOTAL",f"${sale['total']:.2f}"],["Paid",f"${sale['amount_paid']:.2f}"],["Change",f"${sale['change_due']:.2f}"]]
    tt=Table(totals,colWidths=([70*mm,40*mm] if a4 else [42*mm,28*mm])); tt.setStyle(TableStyle([("ALIGN",(1,0),(-1,-1),"RIGHT"),("FONTNAME",(0,3),(-1,3),"Helvetica-Bold"),("FONTSIZE",(0,0),(-1,-1),8),("LINEABOVE",(0,3),(-1,3),.5,colors.HexColor("#667085"))])); story.append(tt)
    ptxt=" + ".join(f"{x['method']} ${x['amount']:.2f}" for x in pays) or sale["payment_method"]; story += [Spacer(1,8),Paragraph("Payment: "+escape_html(ptxt),styles["Normal"]),Paragraph("Customer: "+escape_html(sale["customer_name"] or "Walk-in"),styles["Normal"]),Spacer(1,7),Paragraph(escape_html(setting("receipt","footer","Thank you")),styles["Normal"]),Paragraph("Powered by Double Gee Tech",styles["Normal"])]
    doc.build(story); return buf.getvalue(),str(sale["receipt_no"])

@app.get("/api/receipts/{sale_id}/pdf")
def receipt_pdf(sale_id:int,size:str="thermal",user:dict=Depends(access("sell"))):
    raw,no=receipt_pdf_bytes(sale_id,size); return Response(raw,media_type="application/pdf",headers={"Content-Disposition":f'attachment; filename="{no}.pdf"'})

@app.post("/api/hardware/receipt/{sale_id}/print")
def print_receipt(sale_id:int,user:dict=Depends(access("sell"))):
    name=setting("printer","name","")
    if not name: raise HTTPException(status_code=409,detail="Choose a printer in Settings first")
    raw_print(name,(receipt_text(sale_id)+"\n\n\n\x1dV\x00").encode("cp437",errors="replace")); return {"ok":True}

@app.post("/api/hardware/cash-drawer")
def open_drawer(user:dict=Depends(access("cash"))):
    name=setting("printer","name","")
    if not name: raise HTTPException(status_code=409,detail="Choose the receipt printer first")
    raw_print(name,b"\x1b\x70\x00\x19\xfa"); return {"ok":True}

# ---------- Version / signed update ----------
@app.get("/api/updates/check")
def update_check(user:dict=Depends(current_user),_:dict=Depends(require_license)):
    lic=read_license()
    try:
        latest=cloud_json("/api/version/latest",None,"GET",{"X-License-Token":lic["license_token"]},timeout=8)
        def version_tuple(x):
            try: return tuple(int(a) for a in str(x).lstrip("v").split(".")[:3])
            except Exception: return (0,0,0)
        latest["current_version"]=VERSION
        latest["update_available"]=version_tuple(latest.get("version"))>version_tuple(VERSION)
        return latest
    except HTTPException as e: return {"current_version":VERSION,"update_available":False,"error":e.detail}

@app.post("/api/updates/download")
def update_download(user:dict=Depends(access("audit")),_:dict=Depends(require_license)):
    lic=read_license(); meta=cloud_json("/api/version/latest",None,"GET",{"X-License-Token":lic["license_token"]},timeout=8)
    check=update_check(user)
    if not check.get("update_available"):
        raise HTTPException(status_code=409,detail="No newer signed update is published")
    if not meta.get("url") or not meta.get("sha256") or not meta.get("signature"):
        raise HTTPException(status_code=409,detail="No signed update is published")
    try:
        pinned=trusted_license_public_key()
        if not secrets.compare_digest(lic["public_key"],pinned): raise HTTPException(403,"Untrusted update signing key")
        pub=Ed25519PublicKey.from_public_bytes(base64.b64decode(pinned)); pub.verify(base64.b64decode(meta["signature"]),meta["sha256"].encode())
    except Exception: raise HTTPException(status_code=409,detail="Update signature validation failed")
    target=UPDATE_DIR/Path(urllib.parse.urlparse(meta["url"]).path).name
    try:
        with urllib.request.urlopen(meta["url"],timeout=60) as res: target.write_bytes(res.read())
    except Exception as e: raise HTTPException(status_code=503,detail=f"Update download failed: {e}")
    digest=hashlib.sha256(target.read_bytes()).hexdigest()
    if not secrets.compare_digest(digest,meta["sha256"]): target.unlink(missing_ok=True); raise HTTPException(status_code=409,detail="Downloaded update hash is invalid")
    return {"ok":True,"path":str(target),"version":meta.get("version"),"ready_to_install":True}

@app.post("/api/updates/install")
def update_install(payload:dict[str,Any],user:dict=Depends(access("audit"))):
    path=Path(str(payload.get("path","")))
    if not path.exists() or UPDATE_DIR not in path.parents: raise HTTPException(status_code=400,detail="Staged update not found")
    if platform.system().lower()!="windows": return {"ok":False,"message":"Installer staging is complete. Installation executes only in the Windows build."}
    subprocess.Popen([str(path)],close_fds=True); return {"ok":True,"message":"Signed installer launched"}

# ---------- Receipts / documents / communication ----------
def escape_html(v:Any) -> str:
    import html
    return html.escape(str(v if v is not None else ""))

@app.get("/receipt/{sale_id}",response_class=HTMLResponse)
def receipt_page(sale_id:int):
    lic=require_license()
    with db() as c:
        sale=c.execute("SELECT s.*,c.name customer_name,c.phone customer_phone,b.name branch_name FROM sales s LEFT JOIN customers c ON c.id=s.customer_id LEFT JOIN branches b ON b.id=s.branch_id WHERE s.id=?",(sale_id,)).fetchone()
        if not sale: raise HTTPException(status_code=404,detail="Sale not found")
        items=c.execute("SELECT * FROM sale_items WHERE sale_id=? ORDER BY id",(sale_id,)).fetchall(); pays=c.execute("SELECT * FROM sale_payments WHERE sale_id=?",(sale_id,)).fetchall()
    rows="".join(f"<tr><td>{escape_html(i['product_name'])}<small>x{i['quantity']:g}</small></td><td>${i['line_total']:.2f}</td></tr>" for i in items); ptxt=" + ".join(f"{x['method']} ${x['amount']:.2f}" for x in pays)
    logo=setting("business","logo",""); logo_html=f"<img class='logo' src='{escape_html(logo)}'>" if logo else ""
    return f"""<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width'><title>{escape_html(sale['receipt_no'])}</title><style>
    body{{font-family:'Segoe UI',Arial,sans-serif;max-width:360px;margin:28px auto;color:#111;padding:0 16px}}.logo{{max-height:54px;max-width:130px}}h1{{font-size:21px;margin:8px 0 2px}}.muted{{color:#667085;font-size:11px;line-height:1.55}}table{{width:100%;border-collapse:collapse;margin:18px 0}}td{{padding:9px 0;border-bottom:1px solid #e5e7eb;font-size:12px;text-align:right}}td:first-child{{text-align:left}}small{{display:block;color:#98a2b3}}.total{{display:flex;justify-content:space-between;font-size:20px;font-weight:800;padding:12px 0}}.actions{{display:flex;gap:8px}}button{{padding:10px 14px;border:0;border-radius:10px;background:#111827;color:white}}@media print{{.actions{{display:none}}body{{margin:0}}}}</style></head><body>{logo_html}<h1>{escape_html(lic.get('business_name') or setting('business','name'))}</h1><div class='muted'>{escape_html(setting('business','address',''))}<br>{escape_html(setting('business','phone',''))}<br>{escape_html(sale['branch_name'] or '')}<br>Receipt {escape_html(sale['receipt_no'])} · {escape_html(sale['created_at'])}</div><table>{rows}</table><div class='muted'>Subtotal ${sale['subtotal']:.2f}<br>Discount ${sale['discount']:.2f}<br>Tax ${sale['tax_total']:.2f}</div><div class='total'><span>Total</span><span>${sale['total']:.2f}</span></div><p class='muted'>Payment: {escape_html(ptxt or sale['payment_method'])}<br>Paid: ${sale['amount_paid']:.2f} · Change: ${sale['change_due']:.2f}<br>Customer: {escape_html(sale['customer_name'] or 'Walk-in')}</p><p class='muted'>{escape_html(setting('receipt','footer','Thank you'))}<br>Powered by Double Gee Tech</p><div class='actions'><button onclick='window.print()'>Print / Save PDF</button></div></body></html>"""

@app.get("/document/{doc_id}",response_class=HTMLResponse)
def document_page(doc_id:int):
    require_license()
    with db() as c:
        d=c.execute("SELECT d.*,c.name customer_name,c.phone customer_phone,c.email customer_email,b.name branch_name FROM documents d LEFT JOIN customers c ON c.id=d.customer_id LEFT JOIN branches b ON b.id=d.branch_id WHERE d.id=?",(doc_id,)).fetchone()
        if not d: raise HTTPException(status_code=404,detail="Document not found")
        items=c.execute("SELECT * FROM document_items WHERE document_id=?",(doc_id,)).fetchall()
    rows="".join(f"<tr><td>{escape_html(x['description'])}</td><td>{x['quantity']:g}</td><td>${x['unit_price']:.2f}</td><td>${x['line_total']:.2f}</td></tr>" for x in items); title="QUOTATION" if d["doc_type"]=="quote" else "INVOICE"
    return f"""<!doctype html><html><head><meta charset='utf-8'><title>{escape_html(d['doc_no'])}</title><style>body{{font-family:'Segoe UI',Arial;max-width:780px;margin:40px auto;padding:0 28px;color:#101828}}header{{display:flex;justify-content:space-between;align-items:start}}h1{{font-size:34px}}.muted{{color:#667085}}table{{width:100%;border-collapse:collapse;margin:34px 0}}th,td{{padding:12px;border-bottom:1px solid #e5e7eb;text-align:right}}th:first-child,td:first-child{{text-align:left}}.summary{{margin-left:auto;width:300px}}.summary div{{display:flex;justify-content:space-between;padding:6px 0}}.grand{{font-size:22px;font-weight:800}}button{{padding:11px 16px;border:0;border-radius:10px;background:#111827;color:#fff}}@media print{{button{{display:none}}}}</style></head><body><header><div><b>{escape_html(read_license().get('business_name') or setting('business','name'))}</b><div class='muted'>{escape_html(setting('business','address',''))}<br>{escape_html(setting('business','phone',''))}</div></div><div style='text-align:right'><h1>{title}</h1><b>{escape_html(d['doc_no'])}</b><div class='muted'>{escape_html(d['created_at'])}<br>Due {escape_html(d['due_date'] or '-')}</div></div></header><h3>For</h3><p>{escape_html(d['customer_name'] or 'Customer')}<br><span class='muted'>{escape_html(d['customer_phone'] or '')} {escape_html(d['customer_email'] or '')}</span></p><table><thead><tr><th>Item</th><th>Qty</th><th>Price</th><th>Total</th></tr></thead><tbody>{rows}</tbody></table><div class='summary'><div><span>Subtotal</span><span>${d['subtotal']:.2f}</span></div><div><span>Discount</span><span>${d['discount']:.2f}</span></div><div><span>Tax</span><span>${d['tax_total']:.2f}</span></div><div class='grand'><span>Total</span><span>${d['total']:.2f}</span></div><div><span>Paid</span><span>${d['amount_paid']:.2f}</span></div></div><p>{escape_html(d['note'] or '')}</p><button onclick='window.print()'>Print / Save PDF</button></body></html>"""

@app.post("/api/receipts/{sale_id}/email")
def email_receipt(sale_id:int,payload:dict[str,Any],user:dict=Depends(access("sell"))):
    to=str(payload.get("to","")).strip()
    if not to: raise HTTPException(status_code=422,detail="Recipient email is required")
    host=setting("email","smtp_host",""); port=int(setting("email","smtp_port","587") or 587); username=setting("email","username",""); password=setting("email","password",""); sender=setting("email","from",username)
    if not host or not sender: raise HTTPException(status_code=409,detail="Configure SMTP in Settings before sending email receipts")
    text=receipt_text(sale_id); pdf_raw,receipt_no=receipt_pdf_bytes(sale_id,"a4"); msg=EmailMessage(); msg["Subject"]="Your receipt from "+(read_license().get("business_name") or "our business"); msg["From"]=sender; msg["To"]=to; msg.set_content(text); msg.add_attachment(pdf_raw,maintype="application",subtype="pdf",filename=f"{receipt_no}.pdf")
    try:
        with smtplib.SMTP(host,port,timeout=15) as s:
            s.starttls()
            if username: s.login(username,password)
            s.send_message(msg)
    except Exception as e: raise HTTPException(status_code=502,detail=f"Email could not be sent: {e}")
    return {"ok":True}

# ---------- Automatic maintenance ----------
_MAINTENANCE_STARTED = False

def maintenance_once():
    # Verify with DG Cloud whenever internet is available. Cloud failure never stops offline sales
    # inside the signed grace window, while a server-side suspension is cached immediately.
    try:
        lic=read_license()
        if lic.get("license_token"):
            result=cloud_json("/api/license/verify",{"device_id":DEVICE_ID,"license_token":lic["license_token"],"app_version":VERSION},"POST",timeout=4)
            with db() as c:
                if result.get("status")=="active":
                    c.execute("UPDATE license_cache SET status='active',last_verified_at=?,valid_until=?,plan=? WHERE id=1",(iso(),result.get("valid_until"),result.get("plan","standard")))
                else:
                    c.execute("UPDATE license_cache SET status=? WHERE id=1",(result.get("status","suspended"),))
    except Exception:
        pass
    try:
        if setting("backup","automatic","true")=="true" and cached_license_valid():
            last=setting("backup","last_auto",""); due=True
            if last:
                try: due=utcnow()>datetime.fromisoformat(last)+timedelta(hours=24)
                except Exception: pass
            if due:
                p=create_backup_file("auto"); set_setting("backup","last_auto",iso())
                if setting("backup","cloud","true")=="true":
                    try:
                        lic=read_license(); cloud_json("/api/backups",{"device_id":DEVICE_ID,"license_token":lic["license_token"],"name":p.name,"data_b64":base64.b64encode(p.read_bytes()).decode(),"created_at":iso()},"POST",timeout=20)
                    except Exception: pass
    except Exception:
        pass
    try: flush_sync(250)
    except Exception: pass

def maintenance_worker():
    while True:
        time.sleep(300)
        maintenance_once()

@app.on_event("startup")
def startup_maintenance():
    global _MAINTENANCE_STARTED
    maintenance_once()
    if not _MAINTENANCE_STARTED:
        _MAINTENANCE_STARTED=True
        threading.Thread(target=maintenance_worker,name="DG-POS-Maintenance",daemon=True).start()

@app.get("/{path:path}")
def spa(path:str):
    if path.startswith("api/") or path.startswith("receipt/") or path.startswith("document/"): raise HTTPException(status_code=404)
    return FileResponse(STATIC_DIR/"index.html")

if __name__=="__main__":
    import uvicorn
    uvicorn.run(app,host="127.0.0.1",port=int(os.getenv("DG_POS_PORT","8787")))