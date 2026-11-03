from test_api import appctx,post,get

def test_clockin_clockout_and_company_scope(appctx):
    c,ids,h=appctx
    assert get(appctx,'customer','/attendance/me').status_code==403
    assert post(appctx,'customer','/attendance/clock-in',{}).status_code==403
    assert get(appctx,'mechanic','/attendance/me').json()==[]
    assert post(appctx,'mechanic','/attendance/clock-out',{}).status_code==409
    assert post(appctx,'mechanic','/attendance/clock-in',{}).status_code==200
    assert post(appctx,'mechanic','/attendance/clock-in',{}).status_code==409
    assert len(get(appctx,'mechanic','/attendance/me').json())==1
    assert get(appctx,'inventory','/attendance/me').json()==[]
    assert len(get(appctx,'owner','/attendance').json())==1
    assert get(appctx,'foreign','/attendance').json()==[]
    assert post(appctx,'mechanic','/attendance/clock-out',{}).status_code==200
    assert post(appctx,'mechanic','/attendance/clock-out',{}).status_code==409
    assert post(appctx,'mechanic','/attendance/clock-in',{}).status_code==200
    assert get(appctx,'mechanic','/attendance/me').json()[0]['clock_out'] is None

def test_attendance_approval_rejection_breaks_and_notifications(appctx):
    c,ids,h=appctx
    item=post(appctx,'mechanic','/attendance/clock-in',{})
    assert item.status_code==200,item.text
    row=item.json()
    assert row['approval_status']=='pending'
    assert row['payable_minutes']==0
    assert row['decision_at'] is None
    assert get(appctx,'customer','/attendance').status_code==403
    assert get(appctx,'owner','/attendance').json()[0]['id']==row['id']
    assert get(appctx,'owner','/notifications').status_code==200

    assert post(appctx,'manager',f"/attendance/{row['id']}/decision",{'decision':'approve'}).status_code==200
    approved=get(appctx,'mechanic','/attendance/me').json()[0]
    assert approved['approval_status']=='approved'
    assert approved['decision_by']==ids['users']['manager']
    assert approved['clock_in']==row['clock_in'] # approval MUST NOT move the start time
    assert post(appctx,'manager',f"/attendance/{row['id']}/decision",{'decision':'reject','note':'Repeat'}).status_code==409
    assert post(appctx,'mechanic','/attendance/clock-out',{'unpaid_break_minutes':0}).status_code==200
    summary=get(appctx,'owner','/attendance/summary')
    assert summary.status_code==200,summary.text
    assert summary.json()['overtime_minutes'] is None
    assert summary.json()['pending_count']==0

    other=post(appctx,'inventory','/attendance/clock-in',{}).json()
    assert post(appctx,'manager',f"/attendance/{other['id']}/decision",{'decision':'reject','note':''}).status_code==422
    rejected=post(appctx,'manager',f"/attendance/{other['id']}/decision",{'decision':'reject','note':'Not scheduled'})
    assert rejected.status_code==200,rejected.text
    assert rejected.json()['approval_status']=='rejected'
    assert post(appctx,'foreign',f"/attendance/{other['id']}/decision",{'decision':'approve'}).status_code==404
    assert post(appctx,'inventory','/attendance/clock-out',{'unpaid_break_minutes':1440}).status_code==422

def test_manager_cannot_approve_own_shift(appctx):
    item=post(appctx,'manager','/attendance/clock-in',{}).json()
    assert post(appctx,'manager',f"/attendance/{item['id']}/decision",{'decision':'approve'}).status_code==403
    assert post(appctx,'owner',f"/attendance/{item['id']}/decision",{'decision':'approve'}).status_code==200
