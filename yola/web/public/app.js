const app=document.getElementById('app');let current=null,interval=null,formMode='register',inviteToken=new URLSearchParams(location.search).get('invite');let refreshing=false,activationTransitioning=false;
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
async function api(path,method='GET',data){let opts={method,credentials:'same-origin',cache:'no-store',headers:{}};if(data){opts.headers['Content-Type']='application/json';opts.body=JSON.stringify(data)}let r=await fetch(path,opts);let p=await r.json().catch(()=>({}));if(!r.ok)throw new Error(p.error||'Request failed');return p}
function flash(msg,bad=true){let n=document.getElementById('msg');if(!n){n=document.createElement('div');n.id='msg';app.prepend(n)}n.className='notice '+(bad?'bad':'good');n.hidden=false;n.textContent=msg}
function stopPoll(){if(interval){clearInterval(interval);interval=null}}
function fields(r){return Object.entries(r).map(([name,[title,type,required,other]])=>`<label class="field">${esc(title)}<input name="${name}" type="${type}" ${required?'required':''} ${other||''}></label>`).join('')}
function getFormData(ev){return Object.fromEntries(new FormData(ev.target).entries())}
function setBusy(ev,busy){const btn=ev.target.querySelector('button[type=submit]');if(btn){btn.disabled=busy;btn.textContent=busy?'Please wait…':btn.dataset.label}}
function authPage(){
 stopPoll();
 const join=!!inviteToken;
 const activated=new URLSearchParams(location.search).get('activated')==='1';
 if(activated && !join)formMode='login';
 app.innerHTML=`<div class="grid"><section class="hero"><span class="pill">YOLA BUSINESS PLATFORM</span><h1>A better way<br>to <span class="gold">run business.</span></h1><p>Simple sales and accounting access with secure activation from the Double Gee Tech Master Control Center.</p><p class="muted small">Create your account with your own name and password. Double Gee Tech activates it. Then sign in to your workspace.</p></section><section class="card"><h2>${join?'Join your business':formMode==='register'?'Create your Yola account':'Welcome back'}</h2><p class="sub">${join?'Set your own secure login.':formMode==='register'?'No activation code to guess. Approval is managed centrally.':'Use the email and password you chose.'}</p><div id="msg" hidden></div><form id="authform">${(join?fields({name:['Your full name','text',true,'minlength="2" maxlength="120"'],email:['Email address','email',true,'autocomplete="username"'],password:['Create password (12+ characters)','password',true,'minlength="12" autocomplete="new-password"']}):formMode==='register'?fields({business:['Business name','text',true,'minlength="2" maxlength="140"'],name:['Your full name','text',true,'minlength="2" maxlength="120"'],phone:['Phone number','tel',false,'maxlength="40"'],email:['Email address','email',true,'autocomplete="username"'],password:['Create password (12+ characters)','password',true,'minlength="12" autocomplete="new-password"']}):fields({email:['Email address','email',true,'autocomplete="username"'],password:['Password','password',true,'autocomplete="current-password"']}))}<button class="btn primary block" type="submit" data-label="${join?'Join business':formMode==='register'?'Create account':'Sign in'}">${join?'Join business':formMode==='register'?'Create account':'Sign in'}</button></form>${join?'':`<div class="row" style="margin-top:15px"><span class="muted small">${formMode==='register'?'Already registered?':'New to Yola?'}</span><button id="switch" class="switch">${formMode==='register'?'Sign in':'Create account'}</button></div>`}</section></div>`;
 if(activated && !join)flash('✓ Double Gee Tech has activated your Yola business. Sign in using the email and password you created.',false);
 if(!join)document.getElementById('switch').onclick=()=>{history.replaceState({},'',location.pathname);formMode=formMode==='register'?'login':'register';authPage()};
 document.getElementById('authform').onsubmit=async ev=>{
  ev.preventDefault();setBusy(ev,true);
  const b=getFormData(ev),action=join?'invite':formMode;
  try{
   const result=await api(action==='invite'?'/api/invites/accept':action==='register'?'/api/register':'/api/login','POST',action==='invite'?{...b,token:inviteToken}:b);
   inviteToken=null;
   if(action==='register'){
    // The backend committed the new client, inactive installation and owner
    // account in a single Master Control database transaction before replying.
    history.replaceState({},'',location.pathname+'?activation=waiting');
    const registered={id:'new-registration',name:b.name,business:b.business,role:'owner',businessCode:result.businessCode,license:{status:'inactive',active:false}};
    current='new-registration|inactive|owner';
    waitPage(registered);
    return;
   }
   history.replaceState({},'',location.pathname);
   current=null;
   await refresh();
  }catch(e){flash(e.message)}finally{setBusy(ev,false)}
 };
}
function header(u){return `<div class="split"><div><span class="eyebrow">${esc(u.business)}</span><h1>${esc(u.name)} <span class="muted" style="font-size:19px">${u.role==='owner'?'Owner':u.role==='manager'?'Manager':'Worker'}</span></h1></div><div class="topright"><button id="signout" class="btn">Sign out</button></div></div>`}
function bindSignout(){document.getElementById('signout').onclick=async()=>{try{await api('/api/logout','POST',{})}catch{}stopPoll();current=null;formMode='login';authPage()}}
function waitPage(u){
 stopPoll();
 const status=u.license.status;
 const pending=status==='inactive'||status==='pending';
 const heading=pending?'Waiting for DG Tech activation':status==='frozen'?'Activation temporarily frozen':status==='suspended'?'Activation suspended':status==='revoked'?'Activation revoked':'Activation currently unavailable';
 app.innerHTML=`<div class="dash"><div class="activation-wrap"><section class="activation-card"><div class="activation-mark" aria-hidden="true">Y</div><span class="eyebrow">YOLA — POWERED BY DOUBLE GEE TECH</span><div class="activation-progress" aria-label="Registration status"><span class="step done">1. Account created</span><span class="step current">2. DG Tech approval</span><span class="step">3. Sign in</span></div><div class="activation-badge"><span class="pulse" aria-hidden="true"></span>${esc(pending?'Awaiting approval':status.toUpperCase())}</div><h1>${esc(heading)}</h1><p class="activation-description">${pending?'Your business is registered. Double Gee Tech will review it in Master Control. You do not need an activation code.':'Your business is not currently approved for access. Contact Double Gee Tech if you need assistance.'}</p><div class="activation-business"><span>Business</span><strong>${esc(u.business)}</strong><span>Registration ID</span><strong class="code">${esc(u.businessCode)}</strong></div><div class="activation-check"><span class="spinner small-spinner" aria-hidden="true"></span><span>Checking Master Control automatically every 7 seconds.</span></div><p class="hint">After DG Tech activates your business, Yola will take you to the <strong>Sign in</strong> screen. Enter the email and password you created to open your workspace.</p><div class="row activation-actions"><button class="btn primary" id="check" type="button">Check status now</button><button class="btn" id="signout" type="button">Sign in with another account</button></div><p id="activation-error" role="status" class="hint"></p></section></div></div>`;
 bindSignout();
 document.getElementById('check').onclick=refresh;
 interval=setInterval(refresh,7000);
}
function activePage(u){stopPoll();app.innerHTML=`<div class="dash">${header(u)}<div class="notice good">✓ Your Yola business is active in DG Tech Master Control. <span class="code">${esc(u.businessCode)}</span></div><section class="cards"><div class="card"><h3>Account access</h3><p>${u.role==='worker'?'Worker account: sales role only. You cannot access accounting, stock administration or staff management.':u.role==='manager'?'Manager account: operational access only; accounting remains reserved for the owner.':'Owner account: manage business staff and licensed access.'}</p></div>${u.role==='owner'?`<div class="card"><h3>Your team</h3><p>Create secure invitations. Managers and workers set their own names and passwords.</p><button class="btn primary" id="team" style="margin-top:19px">Manage team</button></div>`:''}<div class="card"><h3>Yola POS desktop</h3><p>Windows devices require their own Master-approved Yola licence. This account portal does not automatically authorize a new device or replace the POS program.</p></div></section><section id="teamview"></section></div>`;bindSignout();if(u.role==='owner')document.getElementById('team').onclick=teamPage;interval=setInterval(refresh,15000)}
async function teamPage(){const box=document.getElementById('teamview');if(!box)return;box.innerHTML='<div class="card" style="margin-top:20px"><div class="spinner"></div></div>';try{let r=await api('/api/staff');box.innerHTML=`<div class="card" style="margin-top:20px"><h2>Team accounts</h2><p class="sub">Worker access is limited to sales. Owners retain financial controls.</p><ul class="list">${r.staff.map(s=>`<li><span>${esc(s.name)} <span class="muted small">${esc(s.email)}</span></span><b>${esc(s.role)}</b></li>`).join('')}</ul><form id="inviteform" style="margin-top:28px"><label class="field">Invite staff member as<select name="role"><option value="worker">Worker — sell only</option><option value="manager">Manager — no accounting by default</option></select></label><button type="submit" class="btn primary" data-label="Create invitation link">Create invitation link</button></form><div id="inviteout"></div></div>`;document.getElementById('inviteform').onsubmit=async ev=>{ev.preventDefault();setBusy(ev,true);try{const d=await api('/api/invites','POST',getFormData(ev));const n=document.getElementById('inviteout');n.replaceChildren();let div=document.createElement('div');div.className='notice good';div.textContent='Invitation created. Copy and send this private link to your staff member (valid 48 hours).';const input=document.createElement('input');input.value=d.inviteUrl;input.readOnly=true;input.style='width:100%;padding:12px;background:#0c1a2c;color:#fff;border:1px solid #4a6a87;border-radius:10px';n.append(div,input)}catch(e){const n=document.getElementById('inviteout');n.textContent=e.message;n.className='notice bad'}finally{setBusy(ev,false)}}}catch(e){box.textContent=e.message;box.className='notice bad'}}
async function approvedToSignIn(){
 if(activationTransitioning)return;
 activationTransitioning=true;
 stopPoll();
 try{
  // Require a fresh login after Master Control's approval. Never retain a
  // registration-only session as an automatic authorization into the POS.
  await api('/api/logout','POST',{});
  current=null;
  formMode='login';
  history.replaceState({},'',location.pathname+'?activated=1');
  activationTransitioning=false;
  authPage();
 }catch(e){
  activationTransitioning=false;
  const note=document.getElementById('activation-error');
  if(note)note.textContent='Approved, but we could not finish the secure sign-out. Check your connection and retry.';
  interval=setInterval(refresh,7000);
 }
}
async function refresh(){
 if(refreshing||activationTransitioning)return;
 refreshing=true;
 try{
  const r=await api('/api/me');
  if(!r.authenticated){
   current=null;
   if(!document.getElementById('authform')){if(new URLSearchParams(location.search).has('activation')||new URLSearchParams(location.search).has('activated'))formMode='login';if(new URLSearchParams(location.search).has('activation'))history.replaceState({},'',location.pathname);authPage()}
   return;
  }
  const u=r.user;
  if(u.license.active){
   if(new URLSearchParams(location.search).get('activation')==='waiting'){
    await approvedToSignIn();
    return;
   }
   if(!new URLSearchParams(location.search).has('portal')){
    stopPoll();
    location.replace('/workspace.html');
    return;
   }
  }else if(new URLSearchParams(location.search).get('activation')!=='waiting'){
   // A person who signs in while their business is pending should also
   // continue to the dedicated waiting view instead of being stuck at login.
   history.replaceState({},'',location.pathname+'?activation=waiting');
  }
  const stamp=u.id+'|'+u.license.status+'|'+u.role;
  if(current!==stamp){current=stamp;if(u.license.active)activePage(u);else waitPage(u)}
 }catch(e){
  const note=document.getElementById('activation-error');
  if(note)note.textContent='Connection interrupted. We will retry automatically.';
  else if(current!==null)flash('Connection interrupted. Retrying shortly.');
  else if(!document.getElementById('authform'))authPage();
 }finally{refreshing=false}
}
refresh();