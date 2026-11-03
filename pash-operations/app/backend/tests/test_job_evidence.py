"""Real workshop evidence uploads + authorization checks."""
from io import BytesIO
from PIL import Image
from test_api import appctx, post, get


def jpeg_bytes():
    b=BytesIO(); Image.new('RGB',(18,14),'white').save(b,format='JPEG');return b.getvalue()


def make_job(ctx, category='mechanical', tech='mechanic'):
    _,ids,_=ctx
    response=post(ctx,'owner','/jobs',{'vehicle_id':ids['vehicle'],'category':category,
                          'complaint':'Workshop photo security test','assigned_to':ids['users'][tech]})
    assert response.status_code==201,response.text
    return response.json()['id']


def upload(ctx, role, job, data=None, kind='intake'):
    client,_,headers=ctx
    return client.post(f'/api/jobs/{job}/photos?kind={kind}',headers=headers[role],
                       files={'photo':('evidence.jpg',jpeg_bytes() if data is None else data,'image/jpeg')})


def test_job_photo_upload_read_and_audit(appctx):
    c,ids,h=appctx
    jid=make_job(appctx)
    response=upload(appctx,'mechanic',jid)
    assert response.status_code==201,response.text
    photo=response.json()
    assert photo['sha256'] and photo['byte_size']>0
    assert len(get(appctx,'mechanic',f'/jobs/{jid}/photos').json())==1
    assert len(get(appctx,'customer',f'/jobs/{jid}/photos').json())==1
    r=c.get(f"/api/jobs/{jid}/photos/{photo['id']}",headers=h['customer'])
    assert r.status_code==200 and r.content==jpeg_bytes()
    assert r.headers['cache-control']=='private, no-store'
    assert c.get(f"/api/jobs/{jid}/photos/{photo['id']}").status_code==401
    assert get(appctx,'dsg_specialist',f'/jobs/{jid}/photos').status_code==403
    assert get(appctx,'foreign',f'/jobs/{jid}/photos').status_code==404
    assert upload(appctx,'customer',jid).status_code==403
    assert upload(appctx,'dsg_specialist',jid).status_code==403
    assert upload(appctx,'foreign',jid).status_code==404
    assert any(e['entity']=='job_photo' and e['action']=='upload' for e in get(appctx,'owner','/audit').json())


def test_job_photo_rejects_malformed_oversize_and_wrong_kind(appctx):
    jid=make_job(appctx)
    assert upload(appctx,'mechanic',jid,b'not-an-image').status_code==415
    assert upload(appctx,'mechanic',jid,b'a'*3_000_001).status_code==413
    assert upload(appctx,'mechanic',jid,kind='secret').status_code==422
    assert get(appctx,'mechanic',f'/jobs/{jid}/photos').json()==[]


def test_latest_qa_fails_closed_after_previous_pass(appctx):
    client,ids,headers=appctx
    jid=make_job(appctx)
    def move(state):
        return client.patch(f'/api/jobs/{jid}/status',json={'status':state},headers=headers['owner'])
    assert move('diagnosis').status_code==200
    assert move('awaiting_approval').status_code==200
    q=post(appctx,'owner','/quotes',{'job_id':jid,'items':[{'label':'Replace component','quantity':1,'unit_price':'55'}]}).json()
    assert post(appctx,'customer',f"/quotes/{q['id']}/decision",{'decision':'approved'}).status_code==200
    assert move('repairing').status_code==200
    assert move('quality_check').status_code==200
    assert post(appctx,'owner','/inspections',{'job_id':jid,'checklist':{'quality_passed':True}}).status_code==201
    assert post(appctx,'owner','/inspections',{'job_id':jid,'checklist':{'quality_passed':False}}).status_code==201
    assert move('ready').status_code==409
    assert post(appctx,'owner','/inspections',{'job_id':jid,'checklist':{'quality_passed':True}}).status_code==201
    assert move('ready').status_code==200


def test_dsg_requires_specialist_report_before_collection(appctx):
    client,ids,h=appctx
    jid=make_job(appctx,category='dsg',tech='dsg_specialist')
    def move(state):return client.patch(f'/api/jobs/{jid}/status',json={'status':state},headers=h['owner'])
    assert move('diagnosis').status_code==200
    assert move('awaiting_approval').status_code==200
    quote=post(appctx,'owner','/quotes',{'job_id':jid,'items':[{'label':'Clutch repair','quantity':1,'unit_price':'55'}]}).json()
    assert post(appctx,'customer',f"/quotes/{quote['id']}/decision",{'decision':'approved'}).status_code==200
    assert move('repairing').status_code==200
    assert move('quality_check').status_code==200
    assert post(appctx,'owner','/inspections',{'job_id':jid,'checklist':{'quality_passed':True}}).status_code==201
    assert move('ready').status_code==409
    assert post(appctx,'dsg_specialist','/gearbox-reports',{'job_id':jid,'transmission_code':'DQ200','test_results':'Basic settings passed'}).status_code==201
    assert move('ready').status_code==200
