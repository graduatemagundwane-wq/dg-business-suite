"""Authoritative licence registry for Yola in DG Tech Master Control Neon.

Production ONLY: DG_MASTER_DATABASE_URL is a server-side secret; it must never be
embedded in Yola desktop distributions. The Master Control `installations`
record, rather than this backend's local row, is the source of activation truth.
"""
from __future__ import annotations
import os
from datetime import datetime, timezone
from uuid import UUID

PRODUCT_SLUG = 'yola'
SOURCE = 'yola-pos'


class MasterUnavailable(RuntimeError):
    pass


class MasterDenied(RuntimeError):
    pass


def _connect():
    dsn = os.getenv('DG_MASTER_DATABASE_URL', '').strip()
    if not dsn:
        raise MasterUnavailable('Master Control Neon database connection is not configured')
    try:
        import psycopg
        return psycopg.connect(dsn, connect_timeout=7, autocommit=False)
    except Exception as exc:
        raise MasterUnavailable('Master Control Neon is unavailable') from exc


def enabled() -> bool:
    # Default is fail-closed; test/legacy mode requires deliberate opt-out.
    return os.getenv('DG_REQUIRE_MASTER_CONTROL', '1') != '0'


def registry_ready() -> bool:
    """Only healthy when the real Neon Master Control recognizes Yola.

    Used for release gating. Never divulge DSNs, credentials or SQL failures.
    """
    if not enabled():
        return True  # disposable fixture mode only
    try:
        with _connect() as conn:
            with conn.cursor() as cur:
                cur.execute('SELECT 1 FROM products WHERE slug=%s LIMIT 1', (PRODUCT_SLUG,))
                return cur.fetchone() is not None
    except Exception:
        return False


def register_request(request_code, device_id, device_name, business_name, owner_name, phone, existing_business_code=''):
    """Create pending client registration and device in actual Master Control.

    Existing businesses can attach another device only after Master pre-authorizes it.
    A missing product row causes failure rather than a parallel licence island.
    """
    if not enabled():
        return None
    try:
        with _connect() as conn:
            with conn.cursor() as cur:
                cur.execute('SELECT id FROM products WHERE slug=%s', (PRODUCT_SLUG,))
                product = cur.fetchone()
                if not product:
                    raise MasterUnavailable('Yola product has not been provisioned in Master Control')
                if existing_business_code:
                    cur.execute('''SELECT id,customer_id,max_devices,status,business_code FROM installations
                        WHERE product_id=%s AND business_code=%s FOR UPDATE''',
                        (product[0], existing_business_code))
                    row = cur.fetchone()
                    if not row:
                        raise MasterDenied('The existing Yola registration ID was not found')
                    installation_id = row[0]
                    # A public registration ID is not authorization to add a PC.
                    # New devices must be pre-registered in DG Tech Master Control.
                    cur.execute('SELECT id FROM devices WHERE installation_id=%s AND device_uid=%s',
                                (installation_id, device_id))
                    if not cur.fetchone():
                        raise MasterDenied('Ask Double Gee Tech to authorize this Yola device in Master Control')
                else:
                    cur.execute('''SELECT id FROM installations WHERE product_id=%s
                        AND source_system=%s AND source_reference=%s FOR UPDATE''',
                        (product[0], SOURCE, request_code))
                    row = cur.fetchone()
                    if row:
                        installation_id = row[0]
                    else:
                        cur.execute('''INSERT INTO customers(name,owner_name,phone,source_system,source_reference)
                          VALUES(%s,%s,%s,%s,%s) RETURNING id''',
                          (business_name,owner_name,phone,SOURCE,request_code))
                        customer_id = cur.fetchone()[0]
                        cur.execute('''INSERT INTO installations(customer_id,product_id,business_code,status,
                          source_system,source_reference,source_status)
                          VALUES(%s,%s,%s,'inactive',%s,%s,'pending') RETURNING id''',
                          (customer_id,product[0],request_code,SOURCE,request_code))
                        installation_id = cur.fetchone()[0]
                cur.execute('SELECT max_devices,status FROM installations WHERE id=%s FOR UPDATE', (installation_id,))
                max_devices, status = cur.fetchone()
                if status == 'revoked':
                    raise MasterDenied('This registration was revoked by DG Tech Master Control')
                cur.execute('SELECT id FROM devices WHERE installation_id=%s AND device_uid=%s',
                            (installation_id,device_id))
                if not cur.fetchone():
                    cur.execute('SELECT COUNT(*) FROM devices WHERE installation_id=%s',(installation_id,))
                    if cur.fetchone()[0] >= max_devices:
                        raise MasterDenied('Master Control maximum device limit reached')
                    cur.execute('''INSERT INTO devices(installation_id,label,device_uid)
                                   VALUES(%s,%s,%s)''',(installation_id,device_name,device_id))
                return str(installation_id)
    except (MasterDenied,MasterUnavailable):
        raise
    except Exception as exc:
        raise MasterUnavailable('Yola could not register with DG Tech Master Control') from exc


def entitlement(installation_id, device_id):
    """Re-query Master for every grant and online licence verification.

    No local admin override. No cross-product or cross-installation claims.
    """
    if not enabled():
        return {'active': True, 'max_devices': 20, 'max_workers': 25, 'offline_lease_hours': 72,
                'expires_at': None, 'business_code': 'TEST-ONLY'}
    if not installation_id or not device_id:
        raise MasterDenied('Missing Master Control installation/device')
    try:
        with _connect() as conn:
            with conn.cursor() as cur:
                cur.execute('''SELECT i.status,i.max_devices,i.max_workers,i.offline_lease_hours,i.expires_at,
                    i.business_code,p.slug FROM installations i JOIN products p ON p.id=i.product_id
                    WHERE i.id=%s''',(UUID(str(installation_id)),))
                row=cur.fetchone()
                if not row or row[6] != PRODUCT_SLUG:
                    raise MasterDenied('No matching Yola installation exists in Master Control')
                status, max_devices, max_workers, grace, expiry, code, _ = row
                cur.execute('''SELECT 1 FROM devices WHERE installation_id=%s AND device_uid=%s''',
                            (UUID(str(installation_id)),device_id))
                if not cur.fetchone():
                    raise MasterDenied('This device is not registered with Master Control')
                if status != 'active':
                    raise MasterDenied('Master Control status: '+str(status))
                if expiry and expiry <= datetime.now(timezone.utc):
                    raise MasterDenied('Yola subscription expired in Master Control')
                return {'active':True,'max_devices':int(max_devices),'max_workers':int(max_workers),'offline_lease_hours':int(grace),
                        'expires_at':expiry.isoformat() if expiry else None,'business_code':code}
    except (MasterDenied,MasterUnavailable):
        raise
    except Exception as exc:
        raise MasterUnavailable('Unable to validate the DG Tech Master Control licence') from exc


def require_business_active(installation_id):
    """Deny remote owner access if Master suspends or expires this business."""
    if not enabled():
        return True
    try:
        identifier = UUID(str(installation_id))
    except (TypeError, ValueError) as exc:
        raise MasterDenied('Invalid Yola installation identifier') from exc
    try:
        with _connect() as conn:
            with conn.cursor() as cur:
                cur.execute("""SELECT i.status,i.expires_at,p.slug
                    FROM installations i JOIN products p ON p.id=i.product_id
                    WHERE i.id=%s""", (identifier,))
                row = cur.fetchone()
                if not row or row[2] != PRODUCT_SLUG:
                    raise MasterDenied('No matching Yola business in Master Control')
                if row[0] != 'active':
                    raise MasterDenied('Master Control status: '+str(row[0]))
                if row[1] and row[1] <= datetime.now(timezone.utc):
                    raise MasterDenied('Yola licence expired in Master Control')
                return True
    except (MasterDenied, MasterUnavailable):
        raise
    except Exception as exc:
        raise MasterUnavailable('Unable to verify Yola business status in Master Control') from exc