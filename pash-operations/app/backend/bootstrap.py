"""Create a new empty organization and owner (never seeds real customer records)."""
import getpass
from db import engine,SessionLocal
from models import Base,Organization,User
from security import password_hash
Base.metadata.create_all(engine)
with SessionLocal() as db:
    org=Organization(name=input('Organization name: ').strip())
    email=input('Owner email: ').strip().lower()
    name=input('Owner full name: ').strip()
    secret=getpass.getpass('Owner password (12+ chars): ')
    db.add(org);db.flush()
    db.add(User(organization_id=org.id,name=name,email=email,password_hash=password_hash(secret),roles=['owner']))
    db.commit()
    print('Organization ID:',org.id, '(provide this on the login screen)')
