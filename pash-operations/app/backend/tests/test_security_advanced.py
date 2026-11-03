"""Security regression for account lockout, human approvals and HV safety gates."""
from test_api import appctx,post,get,PASS


def test_login_lockout_after_5_incorrect_passwords(appctx):
    c,ids,h=appctx
    for _ in range(5):
        r=c.post('/api/auth/login',json={'organization_id':ids['org'],'email':'owner@example.test','password':'not-the-real-password'})
        assert r.status_code==401,r.text
    r=c.post('/api/auth/login',json={'organization_id':ids['org'],'email':'owner@example.test','password':PASS})
    assert r.status_code==429,r.text
    # Existing signed sessions remain usable; operator can investigate the lockout.
    assert get(appctx,'owner','/auth/me').status_code==200


def test_only_customer_can_approve_quote(appctx):
    c,ids,h=appctx
    job=post(appctx,'owner','/jobs',{'vehicle_id':ids['vehicle'],'category':'mechanical','complaint':'Service oil leak'}).json()
    q=post(appctx,'owner','/quotes',{'job_id':job['id'],'items':[{'label':'Sealing repair','quantity':1,'unit_price':'55'}]}).json()
    for who in ('owner','manager','service_advisor','mechanic'):
        assert post(appctx,who,f"/quotes/{q['id']}/decision",{'decision':'approved'}).status_code==403
    assert post(appctx,'customer',f"/quotes/{q['id']}/decision",{'decision':'approved'}).status_code==200


def test_repair_authorization_cannot_be_bypassed_through_parts(appctx):
    c,ids,h=appctx
    job=post(appctx,'owner','/jobs',{'vehicle_id':ids['vehicle'],'category':'mechanical','complaint':'Engine fault'}).json()
    jid=job['id']
    assert c.patch(f'/api/jobs/{jid}/status',json={'status':'diagnosis'},headers=h['owner']).status_code==200
    assert c.patch(f'/api/jobs/{jid}/status',json={'status':'awaiting_parts'},headers=h['owner']).status_code==200
    assert c.patch(f'/api/jobs/{jid}/status',json={'status':'repairing'},headers=h['owner']).status_code==409


def test_high_voltage_report_needs_credential_and_supervisor_permit(appctx):
    c,ids,h=appctx
    job=post(appctx,'owner','/jobs',{'vehicle_id':ids['vehicle'],'category':'battery','complaint':'HV battery fault',
                                  'assigned_to':ids['users']['battery_specialist']}).json()
    data={'job_id':job['id'],'chemistry':'Li-ion high voltage','battery_serial':'QABATT-002','high_voltage':True}
    assert post(appctx,'battery_specialist','/battery-reports',data).status_code==403
    cred=post(appctx,'owner','/staff/qualifications',{'user_id':ids['users']['battery_specialist'],'qualification':'Documented HV battery qualification','high_voltage_approved':True})
    assert cred.status_code==201,cred.text
    assert post(appctx,'battery_specialist','/battery-reports',data).status_code==409
    approval={'job_id':job['id'],'technician_id':ids['users']['battery_specialist'],
              'risk_assessed':True,'isolation_verified':True,'ppe_checked':False,'emergency_plan_confirmed':True}
    assert post(appctx,'owner','/battery-safety-permits',approval).status_code==422
    approval['ppe_checked']=True
    assert post(appctx,'battery_specialist','/battery-safety-permits',approval).status_code==403
    assert post(appctx,'owner','/battery-safety-permits',approval).status_code==201
    assert post(appctx,'battery_specialist','/battery-reports',data).status_code==201
    reports=get(appctx,'battery_specialist','/battery-reports').json()
    assert reports[0]['high_voltage'] is True
