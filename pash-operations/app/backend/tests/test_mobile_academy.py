"""API integration proof for instructor content -> enrolled student exam -> certificate."""
from test_api import appctx, post, get

def test_academy_end_to_end_for_staff_app(appctx):
    client,ids,h=appctx
    student=client.post('/api/auth/student-signup',json={
        'organization_id':ids['org'],'name':'Synthetic Apprentice',
        'email':'student-v040@example.test','password':'OnlyForTesting!2026'
    })
    assert student.status_code==201,student.text
    sid=student.json()['student_id']
    logged=client.post('/api/auth/login',json={'organization_id':ids['org'],
        'email':'student-v040@example.test','password':'OnlyForTesting!2026'})
    sh={'Authorization':'Bearer '+logged.json()['access_token']}
    course=post(appctx,'instructor','/courses',{'title':'DSG Repair Foundation','description':'Professional diagnostics','price':'120','published':False}).json()
    cid=course['id']
    assert client.patch(f'/api/courses/{cid}/publish',json={'published':True},headers=h['customer']).status_code==403
    assert client.patch(f'/api/courses/{cid}/publish',json={'published':True},headers=h['instructor']).status_code==200
    assert post(appctx,'owner','/enrollments',{'student_id':sid,'course_id':cid}).status_code==201
    lesson=post(appctx,'instructor','/academy/lessons',{'course_id':cid,'title':'Dual clutch fundamentals',
        'body':'A transmission that shifts with two clutch assemblies.','published':False}).json()
    assert lesson['published'] is False
    assert client.get('/api/academy/lessons',headers=sh).json()==[]
    assert client.patch(f"/api/academy/lessons/{lesson['id']}/publish",json={'published':True},headers=h['instructor']).status_code==200
    assert len(client.get('/api/academy/lessons',headers=sh).json())==1
    exam=post(appctx,'instructor','/academy/assessments',{'course_id':cid,'title':'DSG skills',
        'questions':[{'prompt':'How many clutch assemblies are used?','choices':['One','Two','Three','Four'],'answer':1}],
        'published':False}).json()
    assert client.get('/api/academy/assessments',headers=sh).json()==[]
    assert client.patch(f"/api/academy/assessments/{exam['id']}/publish",json={'published':True},headers=h['instructor']).status_code==200
    shown=client.get('/api/academy/assessments',headers=sh).json()
    assert len(shown)==1 and 'answer' not in shown[0]['questions'][0]
    attempt=client.post(f"/api/academy/assessments/{exam['id']}/attempt",json={'answers':[1]},headers=sh)
    assert attempt.status_code==201 and attempt.json()['passed']
    enrollment=get(appctx,'owner','/enrollments').json()[0]
    assert post(appctx,'instructor',f"/academy/enrollments/{enrollment['id']}/complete",{}).status_code==200
    issue=post(appctx,'owner','/academy/certificates',{'student_id':sid,'course_id':cid})
    assert issue.status_code==201,issue.text
    assert client.get('/api/academy/certificates',headers=sh).json()[0]['verification_code']==issue.json()['verification_code']
