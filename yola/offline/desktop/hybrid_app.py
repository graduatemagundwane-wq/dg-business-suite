"""Host the exact Yola online interface using a local SQLite API.

Legacy device enrolment is isolated under /legacy. It is the ONLY component
allowed to accept and verify Ed25519 Master Control signed device licences.
"""
from fastapi import FastAPI, Request
from fastapi.responses import RedirectResponse, FileResponse, JSONResponse
from offline_web import app as online_ui, STATIC_DIR
from local_server import app as licensed_device_api, cached_license_valid

app=FastAPI(title='Yola Premium Offline — Powered by Double Gee Tech')

@app.middleware('http')
async def restrict_loopback(request:Request,call_next):
    # A local desktop service must not be exposed by DNS rebinding or CSRF.
    host=request.url.hostname
    if host not in ('localhost','127.0.0.1'):
        return JSONResponse({'error':'Local connection only'},status_code=403)
    if request.method in ('POST','PUT','PATCH','DELETE'):
        origin=request.headers.get('origin')
        if origin:
            from urllib.parse import urlsplit
            v=urlsplit(origin)
            if v.hostname not in ('localhost','127.0.0.1') or v.port!=request.url.port:
                return JSONResponse({'error':'Invalid browser origin'},status_code=403)
    return await call_next(request)

@app.get('/device-activation.html')
def activation_page():
    if cached_license_valid():return RedirectResponse('/',status_code=302)
    return FileResponse(STATIC_DIR/'device-activation.html')

@app.get('/')
def root():
    return FileResponse(STATIC_DIR/'index.html')

# Root-level workspace and assets are served unchanged by online_ui.
app.mount('/legacy',licensed_device_api)
app.mount('/',online_ui)