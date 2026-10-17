"""Yola Master Control invariants, using a stub registry (never touching live Neon)."""
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
import os, sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'cloud'))

with TemporaryDirectory(prefix='yola-master-tests-') as tmp:
    os.environ.update({
      'DG_CLOUD_DB':str(Path(tmp)/'test-cloud.db'),
      'DG_LICENSE_KEY_FILE':str(Path(tmp)/'test-signing.key'),
      'DG_CLOUD_ADMIN_KEY':'test-only-master-key',
      'DG_REQUIRE_MASTER_CONTROL':'1',
    })
    # Master-required deployments must never auto-generate ephemeral licence keys.
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives import serialization
    test_key=Ed25519PrivateKey.generate().private_bytes(
        serialization.Encoding.Raw,serialization.PrivateFormat.Raw,serialization.NoEncryption())
    (Path(tmp)/'test-signing.key').write_bytes(test_key)
    from fastapi.testclient import TestClient
    import master_registry as master
    import cloud_server as yola

    assert master.enabled(), 'Production must require Master by default'
    os.environ.pop('DG_MASTER_DATABASE_URL', None)
    assert not master.registry_ready(), 'A missing Master DB must never report release-ready'

    c=TestClient(yola.app)
    valid={'device_id':'YOLA-TEST-DEVICE-001','device_name':'QA PC',
           'business_name':'Yola QA Store','owner_name':'QA Owner','phone':'0770000000'}
    # Master unreachable: registration must fail CLOSED.
    with patch.object(master,'register_request',side_effect=master.MasterUnavailable('offline')):
        r=c.post('/api/activation/request',json=valid)
        assert r.status_code==503, r.text

    installation='ae6b5a55-f172-4a0d-90d2-7400f198c937'
    with patch.object(master,'register_request',return_value=installation):
        r=c.post('/api/activation/request',json=valid)
    assert r.status_code==200, r.text
    entry=r.json()
    code=entry['request_code']; secret=entry['claim_secret']
    assert entry['status']=='pending'

    # Old local admin route must not self-issue a production licence.
    local_admin=c.post('/api/admin/activations/'+code+'/approve',
         headers={'X-Admin-Key':'test-only-master-key'},json={})
    assert local_admin.status_code==409, local_admin.text

    body={'device_id':valid['device_id'],'claim_secret':secret}
    with patch.object(master,'entitlement',side_effect=master.MasterDenied('inactive')):
        pending=c.post('/api/activation/status',json=body)
    assert pending.status_code==200 and pending.json()['status']=='pending_master_control',pending.text
    assert 'license_token' not in pending.json()

    ent={'active':True,'max_devices':1,'offline_lease_hours':24,'expires_at':None,'business_code':code}
    with patch.object(master,'entitlement',return_value=ent):
        active=c.post('/api/activation/status',json=body)
    assert active.status_code==200 and active.json()['license_token'] and active.json().get('owner_access_token'), active.text
    license_token=active.json()['license_token']
    business_id=active.json()['business_id']
    owner_token=active.json()['owner_access_token']
    # Owners can view dashboard only while the existing Master approves business.
    with patch.object(master,'require_business_active',return_value=True):
        owner_ok=c.get('/api/mobile/summary/'+business_id,headers={'X-Owner-Token':owner_token})
        assert owner_ok.status_code==200, owner_ok.text
    with patch.object(master,'require_business_active',side_effect=master.MasterDenied('suspended')):
        owner_blocked=c.get('/api/mobile/summary/'+business_id,headers={'X-Owner-Token':owner_token})
        assert owner_blocked.status_code==403, owner_blocked.text
    with patch.object(master,'require_business_active',side_effect=master.MasterUnavailable('offline')):
        owner_unavailable=c.get('/api/mobile/summary/'+business_id,headers={'X-Owner-Token':owner_token})
        assert owner_unavailable.status_code==503, owner_unavailable.text
    # All cloud-local authority endpoints must be forbidden when Master is on.
    forbidden=[('/api/admin/activations/'+code+'/suspend',{}),
               ('/api/admin/activations/'+code+'/disable',{}),
               ('/api/admin/activations/'+code+'/transfer',{'business_id':business_id}),
               ('/api/admin/businesses/'+business_id+'/plan',{'plan':'lifetime'})]
    for path,payload in forbidden:
        denied_local=c.post(path,headers={'X-Admin-Key':'test-only-master-key'},json=payload)
        assert denied_local.status_code==409,(path,denied_local.text)
    verify={'device_id':valid['device_id'],'license_token':license_token}
    with patch.object(master,'entitlement',return_value=ent):
        ok=c.post('/api/license/verify',json=verify)
    assert ok.status_code==200 and ok.json()['active'],ok.text
    with patch.object(master,'entitlement',side_effect=master.MasterDenied('suspended')):
        denied=c.post('/api/license/verify',json=verify)
    assert denied.status_code==200 and not denied.json()['active'],denied.text
    with patch.object(master,'entitlement',side_effect=master.MasterUnavailable('offline')):
        offline=c.post('/api/license/verify',json=verify)
    assert offline.status_code==200 and not offline.json()['active'],offline.text
    blocked=c.post('/api/admin/activations/'+code+'/reactivate',headers={'X-Admin-Key':'test-only-master-key'})
    assert blocked.status_code==409, blocked.text

    class FakeCursor:
        def __init__(self): self.step=0
        def __enter__(self): return self
        def __exit__(self,*args): pass
        def execute(self,sql,args=()):
            self.step+=1
            if self.step not in (1,2,3):
                raise AssertionError('Unexpected additional device INSERT')
        def fetchone(self):
            if self.step==1: return (installation,)
            if self.step==2: return (installation,'customer-id',3,'active','YL-EXISTING')
            if self.step==3: return None  # not pre-authorized
            raise AssertionError(self.step)
    class FakeConnection:
        def __enter__(self): return self
        def __exit__(self,*args): pass
        def cursor(self): return FakeCursor()
    with patch.object(master,'_connect',return_value=FakeConnection()):
        try:
            master.register_request('YL-TEST','NEW-DEVICE','Test PC','Existing','Owner','','YL-EXISTING')
        except master.MasterDenied as exc:
            assert 'authorize' in str(exc)
        else:
            raise AssertionError('A public shop code allowed an unapproved device')

    print('MASTER CONTROL TESTS: PASS — failure closed, pending, exclusive approval, suspend, no local override, owner lockout, no device hijack')