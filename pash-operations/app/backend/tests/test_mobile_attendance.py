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
