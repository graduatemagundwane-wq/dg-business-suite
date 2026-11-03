from test_api import appctx,post,get,PASS

def test_password_change_revokes_existing_staff_sessions(appctx):
    c,ids,h=appctx
    assert post(appctx,'mechanic','/auth/change-password',{'current_password':'WRONG','new_password':'NewTestPassword!2026'}).status_code==403
    assert post(appctx,'mechanic','/auth/change-password',{'current_password':PASS,'new_password':PASS}).status_code==422
    r=post(appctx,'mechanic','/auth/change-password',{'current_password':PASS,'new_password':'NewTestPassword!2026'})
    assert r.status_code==200,r.text
    assert get(appctx,'mechanic','/auth/me').status_code==401
    assert c.post('/api/auth/login',json={'organization_id':ids['org'],'email':'mechanic@example.test','password':PASS}).status_code==401
    assert c.post('/api/auth/login',json={'organization_id':ids['org'],'email':'mechanic@example.test','password':'NewTestPassword!2026'}).status_code==200
    assert get(appctx,'owner','/auth/me').status_code==200
