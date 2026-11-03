"""Mobile session revocation: device signout invalidates its JWT server-side."""
from test_api import appctx, get, post

def test_logout_revokes_token_and_allows_new_login(appctx):
    client, ids, headers=appctx
    assert get(appctx,'mechanic','/auth/me').status_code==200
    assert post(appctx,'mechanic','/auth/logout',{}).status_code==200
    assert get(appctx,'mechanic','/auth/me').status_code==401
    r=client.post('/api/auth/login',json={'organization_id':ids['org'],
        'email':'mechanic@example.test','password':'OnlyForTesting!2026'})
    assert r.status_code==200,r.text
    new={'Authorization':'Bearer '+r.json()['access_token']}
    assert client.get('/api/auth/me',headers=new).status_code==200
    assert client.get('/api/auth/me',headers=headers['owner']).status_code==200

def test_cannot_revoke_other_user_sessions(appctx):
    client,ids,headers=appctx
    assert post(appctx,'customer','/auth/logout',{}).status_code==200
    assert get(appctx,'owner','/auth/me').status_code==200
    assert get(appctx,'customer','/auth/me').status_code==401
