"""Yola authenticated cloud identity verification. Never grants a device licence."""
import http.cookiejar
import json
import urllib.request
import urllib.error
from fastapi import HTTPException

CLOUD_ORIGIN='https://yola-onboarding.vercel.app'

def verify_online_password(email,password):
    jar=http.cookiejar.CookieJar()
    client=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    req=urllib.request.Request(CLOUD_ORIGIN+'/api/login',data=json.dumps({'email':email,'password':password}).encode(),headers={'Content-Type':'application/json'},method='POST')
    try:
        with client.open(req,timeout=9) as res:
            if res.status!=200:raise HTTPException(401,'Yola cloud login failed')
        with client.open(CLOUD_ORIGIN+'/api/me',timeout=9) as res:
            data=json.loads(res.read(30000))
    except urllib.error.HTTPError as e:
        if e.code in (400,401,403,429):raise HTTPException(e.code,'Online Yola login declined. Check the email/password.') from e
        raise HTTPException(503,'Yola online service is unavailable') from e
    except (OSError,ValueError,TimeoutError) as e:
        raise HTTPException(503,'Internet is required for your first login on this device') from e
    user=data.get('user')
    if not data.get('authenticated') or not isinstance(user,dict):
        raise HTTPException(401,'Yola account could not be verified')
    return user

def begin_session(route,details):
    """Register / login using real hosted Yola, retaining only a volatile cookie jar."""
    if route not in ('register','login','invites/accept'):
        raise HTTPException(400,'Unsupported online action')
    jar=http.cookiejar.CookieJar()
    client=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    req=urllib.request.Request(CLOUD_ORIGIN+'/api/'+route,
       data=json.dumps(details).encode(),headers={'Content-Type':'application/json'},method='POST')
    try:
        with client.open(req,timeout=12) as res:
            payload=json.loads(res.read(32768))
    except urllib.error.HTTPError as e:
        text=e.read(4096).decode(errors='replace')
        try:message=json.loads(text).get('error','Online Yola request declined')
        except Exception:message='Online Yola request declined'
        raise HTTPException(e.code,message) from e
    except (OSError,ValueError,TimeoutError) as e:
        raise HTTPException(503,'Connect to the internet to register or verify your Yola account') from e
    return payload,client

def session_status(client):
    try:
        with client.open(CLOUD_ORIGIN+'/api/me',timeout=9) as res:
            response=json.loads(res.read(32768))
        return response.get('user') if response.get('authenticated') else None
    except (urllib.error.URLError,OSError,ValueError,TimeoutError):
        return None