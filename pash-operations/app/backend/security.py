import os
from datetime import datetime, timedelta, timezone
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError, VerificationError
import jwt
from fastapi import HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from db import get_db
from models import User

hasher = PasswordHasher()
bearer = HTTPBearer(auto_error=False)

def password_hash(plain: str):
    if len(plain) < 12: raise ValueError('Password must be at least 12 characters')
    return hasher.hash(plain)

def password_verify(stored, plain):
    try: return hasher.verify(stored, plain)
    except (VerifyMismatchError, VerificationError): return False

def secret():
    key = os.environ.get('PASH_JWT_SECRET', '')
    if len(key) < 48: raise RuntimeError('PASH_JWT_SECRET must be set to a random value of at least 48 characters')
    return key

def issue_token(user):
    now=datetime.now(timezone.utc)
    return jwt.encode({'sub':str(user.id),'org':user.organization_id,'ver':user.token_version,'iat':now,'exp':now+timedelta(hours=8)},secret(),algorithm='HS256')

def current_user(auth: HTTPAuthorizationCredentials | None = Depends(bearer), db:Session=Depends(get_db)):
    if not auth: raise HTTPException(401,'Authentication required')
    try:
        data=jwt.decode(auth.credentials,secret(),algorithms=['HS256'])
        uid=int(data['sub']); org=int(data['org'])
    except (jwt.PyJWTError, KeyError, ValueError): raise HTTPException(401,'Invalid or expired token')
    u=db.get(User,uid)
    if not u or not u.active or u.organization_id!=org or int(data.get('ver',-1))!=int(u.token_version): raise HTTPException(401,'Account unavailable or session revoked')
    return u

def permit(user, *roles):
    if not set(user.roles or []).intersection(set(roles)|{'owner'}): raise HTTPException(403,'Insufficient permission')

def staff(user):
    permit(user,'manager','service_advisor','mechanic','dsg_specialist','battery_specialist','inventory','accountant','instructor')
