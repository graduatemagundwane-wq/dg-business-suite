"""PASH job photo evidence: authenticated, scoped and audited."""
import hashlib
import io
from PIL import Image, UnidentifiedImageError
from fastapi import APIRouter, Depends, UploadFile, File, HTTPException, Response
from sqlalchemy import select
from sqlalchemy.orm import Session
from db import get_db
from security import current_user, permit
from models import Job, Vehicle, Customer, JobPhoto, AuditEvent, User

router = APIRouter(prefix='/api/jobs', tags=['Workshop evidence'])
MAX_SIZE = 3_000_000
ALLOWED_KINDS = {'intake','diagnostic','repair','quality','handover'}
MIME = {'JPEG':'image/jpeg','PNG':'image/png'}

def check_access(db, u, job_id, upload=False):
    j = db.scalar(select(Job).where(Job.id == job_id, Job.organization_id == u.organization_id))
    if not j: raise HTTPException(404, 'Job not found')
    roles = set(u.roles or [])
    supervisors = {'owner','manager','service_advisor'}
    technicians = {'mechanic','dsg_specialist','battery_specialist'}
    if roles.intersection(supervisors): return j
    if roles.intersection(technicians) and j.assigned_to == u.id: return j
    if not upload and 'customer' in roles:
        vehicle = db.scalar(select(Vehicle).where(Vehicle.id == j.vehicle_id, Vehicle.organization_id == u.organization_id))
        customer = db.scalar(select(Customer).where(Customer.id == vehicle.customer_id, Customer.organization_id == u.organization_id)) if vehicle else None
        if customer and customer.user_id == u.id: return j
    raise HTTPException(403, 'No access to this job evidence')

@router.post('/{job_id}/photos',status_code=201)
async def upload_photo(job_id:int, kind:str, photo:UploadFile=File(...), u:User=Depends(current_user), db:Session=Depends(get_db)):
    job = check_access(db, u, job_id, upload=True)
    if kind not in ALLOWED_KINDS: raise HTTPException(422, 'Unsupported evidence category')
    try:
        content = await photo.read(MAX_SIZE+1)
    finally:
        await photo.close()
    if not content or len(content)>MAX_SIZE: raise HTTPException(413,'Image must be non-empty and 3 MB maximum')
    try:
        with Image.open(io.BytesIO(content)) as img:
            if img.format not in MIME: raise HTTPException(415,'JPEG or PNG required')
            if img.width*img.height > 20_000_000: raise HTTPException(413,'Image dimensions too large')
            img.verify()
            content_type=MIME[img.format]
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError):
        raise HTTPException(415,'Invalid image')
    digest=hashlib.sha256(content).hexdigest()
    p=JobPhoto(organization_id=u.organization_id,job_id=job.id,uploaded_by=u.id,
               kind=kind,content_type=content_type,sha256=digest,byte_size=len(content),content=content)
    db.add(p);db.flush()
    db.add(AuditEvent(organization_id=u.organization_id,actor_id=u.id,action='upload',entity='job_photo',entity_id=p.id,
                      data={'job_id':job.id,'kind':kind,'digest':digest}))
    db.commit()
    return {'id':p.id,'job_id':job_id,'kind':kind,'sha256':digest,'byte_size':len(content)}

@router.get('/{job_id}/photos')
def list_photos(job_id:int,u:User=Depends(current_user),db:Session=Depends(get_db)):
    check_access(db,u,job_id)
    q=select(JobPhoto).where(JobPhoto.organization_id==u.organization_id,JobPhoto.job_id==job_id).order_by(JobPhoto.id.desc()).limit(100)
    return [{'id':p.id,'job_id':p.job_id,'kind':p.kind,'byte_size':p.byte_size,
             'created_at':p.created_at.isoformat(),'uploaded_by':p.uploaded_by,'sha256':p.sha256} for p in db.scalars(q).all()]

@router.get('/{job_id}/photos/{photo_id}')
def download_photo(job_id:int,photo_id:int,u:User=Depends(current_user),db:Session=Depends(get_db)):
    check_access(db,u,job_id)
    p=db.scalar(select(JobPhoto).where(JobPhoto.id==photo_id,JobPhoto.job_id==job_id,JobPhoto.organization_id==u.organization_id))
    if not p:raise HTTPException(404,'Photo not found')
    return Response(content=p.content,media_type=p.content_type,headers={'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff'})
