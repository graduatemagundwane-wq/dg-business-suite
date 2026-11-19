'use strict';
// SAGRO customer extension. This preserves Yola's original styles and screens.
// All privileged data is protected again on the server; UI hiding alone is not authorization.
(function(){
 const escape=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const isWorker=()=>user&&user.role==='worker';
 const originalAllow=roleAllow;
 roleAllow=function(page){return isWorker()?page==='sell':originalAllow(page)};
 const originalProduct=productButton;
 productButton=function(p){
  if(!isWorker())return originalProduct(p);
  const available=p.available===true;
  return '<button class="product" data-add="'+escape(p.id)+'" '+(available?'':'disabled')+'>'+
    '<span class="product-avatar" aria-hidden="true">▣</span>'+
    '<span class="product-details"><strong>'+escape(p.name)+'</strong>'+
    '<small>SKU: '+escape(p.sku)+'</small>'+
    '<span class="product-price-inline">'+fmt(p.price_cents)+'</span>'+
    '<small class="'+(available?'stock-good':'stock-low')+'">'+
    (available?'Available to sell':'Unavailable')+'</small></span>'+
    '<span class="addglyph" aria-hidden="true">+</span></button>';
 };
 const originalSell=sell;
 sell=async function(){
   await originalSell();
   if(!isWorker())return;
   // Keep exactly the same Yola checkout but remove business metrics/discount.
   const metrics=document.querySelector('#body>.cards');
   if(metrics)metrics.remove();
   const discount=document.getElementById('discount');
   if(discount){
     discount.value='0';
     const row=discount.closest('label');
     if(row)row.style.display='none';
   }
   const navBox=document.getElementById('sidebar-nav');
   if(navBox){
     navBox.querySelectorAll('[data-page]').forEach(btn=>{
       if(btn.dataset.page!=='sell')btn.remove();
     });
   }
 };
 const oldTeam=team;
 team=async function(){
  if(!user||user.role!=='owner')return flash('Administrator access required.',true);
  const [members,progress]=await Promise.all([api('staff'),api('staff/performance')]);
  const list=members.staff||[],stats=progress.staff||[];
  const rows=list.map(p=>'<tr><td><strong>'+escape(p.name)+'</strong>'+
    '<div class="muted small">'+escape(p.email)+'</div></td>'+
    '<td>'+escape(p.phone||'—')+'</td><td>'+escape(p.role)+'</td>'+
    '<td><span class="tag '+(p.active?'':'low')+'">'+
      (p.active?'Active':'Paused')+'</span></td><td>'+
    (p.role==='worker'?'<button class="btn" type="button" data-worker-id="'+
      escape(p.id)+'" data-worker-next="'+(p.active?'off':'on')+'">'+
      (p.active?'Pause':'Activate')+'</button>':'Owner')+
    '</td></tr>').join('');
  const numbers=stats.map(p=>'<tr><td><strong>'+escape(p.name)+'</strong>'+
    '<div class="muted small">'+escape(p.today_count)+' sales today · '+
      escape(p.lifetime_count)+' total</div></td>'+
    '<td>'+fmt(p.today_cents)+'</td>'+
    '<td>'+fmt(p.week_cents)+'</td>'+
    '<td>'+fmt(p.month_cents)+'</td>'+
    '<td>'+fmt(p.lifetime_cents)+'</td>'+
    '<td>'+(p.last_sale?new Date(p.last_sale).toLocaleDateString('en-ZW'):'—')+
    '</td></tr>').join('');
  body([
   '<section class="card">',
   '<h2>People & permissions</h2>',
   '<p class="intro">Create employee login details here. Workers sign in to regular Yola or the Worker app with the SAME email and password. Only Sell is available.</p>',
   '<div class="tablewrap"><table><thead><tr>',
   '<th>Employee</th><th>Phone</th><th>Role</th><th>Status</th><th>Control</th>',
   '</tr></thead><tbody>',rows,'</tbody></table></div>',
   '<h3 style="margin-top:26px">Create employee credentials</h3>',
   '<form id="sargo-create-worker"><div class="formgrid">',
   '<label class="field">Full name<input name="name" required minlength="2" maxlength="120" autocomplete="name"></label>',
   '<label class="field">Email / username<input type="email" name="email" required autocomplete="off"></label>',
   '<label class="field">Phone number<input name="phone" type="tel" maxlength="42"></label>',
   '<label class="field">Password (12+ characters)<input name="password" type="password" required minlength="12" maxlength="128" autocomplete="new-password"></label>',
   '</div><div class="row"><button class="btn primary" type="submit">Create worker account</button>',
   '<span class="muted small">Role: Worker · Sales only</span></div></form>',
   '<p class="small muted">Employees cannot open stock management, accounting, quotations, reports, team accounts or business settings. Only the owner can pause/reactivate employees.</p>',
   '<h3 style="margin-top:32px">Worker sales progress</h3>',
   '<p class="intro">Real paid-sale records by cashier (refunds excluded). Today uses Zimbabwe time.</p>',
   '<div class="tablewrap"><table><thead><tr><th>Worker</th><th>Today</th><th>7 days</th><th>30 days</th><th>All time</th><th>Last sale</th>',
   '</tr></thead><tbody>',numbers||'<tr><td colspan="6">No worker sales yet.</td></tr>',
   '</tbody></table></div>',
   '<h3 style="margin-top:30px">Optional secure invitation</h3>',
   '<p class="intro">Alternatively, generate a one-time link so a worker sets their own password.</p>',
   '<div class="row"><button class="btn" id="sargo-invite">Generate Worker invitation</button></div>',
   '<div id="sargo-invite-result"></div>',
   '</section>'
  ].join(''));
  document.getElementById('sargo-create-worker').onsubmit=async e=>{
   e.preventDefault();
   const button=e.target.querySelector('button[type=submit]');
   button.disabled=true;
   try{
     const data=Object.fromEntries(new FormData(e.target));
     await api('staff/create','POST',{name:data.name,email:data.email,phone:data.phone,password:data.password,role:'worker'});
     flash('Worker created. Use this same email and password in Yola Worker.');
     await team();
   }catch(err){flash(err.message,true)}
   finally{button.disabled=false}
  };
  document.querySelectorAll('[data-worker-id]').forEach(btn=>{
   btn.onclick=async()=>{
     const enabled=btn.dataset.workerNext==='on';
     if(!confirm((enabled?'Activate':'Pause')+' this employee?'))return;
     try{
       await api('staff/status','POST',{id:btn.dataset.workerId,active:enabled});
       flash('Employee '+(enabled?'activated':'paused'));
       await team();
     }catch(err){flash(err.message,true)}
   };
  });
  document.getElementById('sargo-invite').onclick=async()=>{
   try{
     const r=await api('invites','POST',{role:'worker'});
     const target=document.getElementById('sargo-invite-result');
     target.replaceChildren();
     const description=document.createElement('p');
     description.className='muted small';
     description.textContent='Private invitation, expires after 48 hours';
     const input=document.createElement('input');
     input.className='field';input.style.width='100%';input.readOnly=true;
     input.value=r.inviteUrl;
     const copy=document.createElement('button');
     copy.className='btn';copy.textContent='Copy invitation';copy.type='button';
     copy.onclick=()=>navigator.clipboard.writeText(r.inviteUrl).then(()=>flash('Invitation copied'));
     target.append(description,input,copy);
   }catch(err){flash(err.message,true)}
  };
 };
 const originalPrint=printDocument;
 printDocument=function(opts){
   if(!user||user.businessCode!=='YOLA-D8C868892683ECCE')
     return originalPrint(opts);
   return sargoPrint(opts);
 };
 const sargoLogo='https://raw.githubusercontent.com/graduatemagundwane-wq/dg-business-suite/client/sagro-android-20261119/assets/sagro/sagro_logo.jpg';
 function sargoPrint(opts){
  const kind=opts.kind||'receipt',doc=opts.doc,sale=opts.sale,lines=opts.items||[];
  const quote=kind==='quotation',invoice=kind==='invoice';
  const label=quote?'QUOTATION':invoice?'INVOICE':'RECEIPT';
  const ref=(quote?'Q-':invoice?'INV-':'RC-')+
    String(doc?.document_no||sale?.sale_number||'TEST');
  const dt=new Date(doc?.created_at||sale?.created_at||Date.now());
  const date=dt.toLocaleDateString('en-ZW');
  const customer=doc?.customer_name||sale?.customer_name||'Walk-in customer';
  const contact=doc?.customer_contact||'';
  const subtotal=Number(doc?.subtotal_cents||sale?.subtotal_cents||0);
  const tax=Number(doc?.tax_cents||sale?.tax_cents||0);
  const discount=Number(sale?.discount_cents||0);
  const total=Number(doc?.total_cents||sale?.total_cents||0);
  const items=lines.map((item,i)=>{
   const count=Number(item.qty)||1;
   return '<tr><td>'+escape(item.sku||String(i+1).padStart(3,'0'))+'</td>'+
    '<td>'+escape(item.name)+'</td><td class="num">'+count.toFixed(2)+'</td>'+
    '<td>EA</td><td class="num">'+fmt(item.unit_cents||item.unit_price_cents)+'</td>'+
    '<td class="num">'+fmt(item.tax_cents||0)+'</td>'+
    '<td class="num">'+fmt(item.total_cents||0)+'</td></tr>';
  }).join('');
  const note=doc?.notes||'';
  const printable=[
   '<div class="row between no-print" style="margin-bottom:18px"><div><span class="eyebrow">SARGO DOCUMENTS</span><h2>',
   escape(label+' · '+ref),
   '</h2></div><div class="row"><button class="btn" id="backdoc">Back</button>',
   '<button class="btn primary" id="printdoc">Print / Save PDF</button></div></div>',
   '<article id="sargo-paper" class="sargo-paper '+(quote||invoice?'a4':'thermal')+'">',
   '<header class="sargo-header"><div class="sargo-left">',
   '<img class="sargo-logo" src="'+escape(sargoLogo)+'" alt="SAGRO logo">',
   '<div class="sargo-business"><strong>SARGO Supply & Support</strong>',
   '<span>Plot 9 Sub division 18, Welston, Glen Forest, Harare</span>',
   '<span>+44 7419 339101</span></div></div>',
   '<div class="sargo-head-right"><h3>'+label+'</h3><span>'+escape(ref)+'</span>',
   '<span>'+escape(date)+'</span></div></header>',
   '<div class="sargo-separator"></div>',
   '<div class="sargo-details"><div><b>TO</b><p>'+escape(customer)+'</p>',
   (contact?'<p>'+escape(contact)+'</p>':''),
   '</div><div><b>REFERENCE</b><p>'+escape(ref)+'</p>',
   (quote?'<p>Valid for seven days</p>':''),
   '</div></div>',
   '<div class="sargo-reference"><b>Account</b><b>Date</b><b>Order No.</b><b>Delivery Note</b><b>'+label+' #</b>',
   '<span>'+escape(customer)+'</span><span>'+escape(date)+'</span>',
   '<span>—</span><span>—</span><span>'+escape(ref)+'</span></div>',
   '<table class="sargo-lines"><thead><tr><th>Item code</th><th>Item description</th>',
   '<th>Quantity</th><th>Unit</th><th>Price (excl.)</th><th>VAT</th><th>Total (incl.)</th>',
   '</tr></thead><tbody>',items,'</tbody></table>',
   '<div class="sargo-note">',escape(note||(quote?'* Quotation valid for seven days.':'Thank you for your business.')),'</div>',
   '<footer class="sargo-bottom"><div class="sargo-signature">',
   '<div>Received by ________________________</div>',
   '<div>Date ______________________________</div>',
   '<div>Signed _____________________________</div>',
   '<div class="sargo-banking"><b>Banking details</b><p>To be provided.</p></div>',
   '</div><div class="sargo-prices">',
   '<div><span>Subtotal (USD)</span><span>'+fmt(subtotal)+'</span></div>',
   '<div><span>VAT</span><span>'+fmt(tax)+'</span></div>',
   (discount?'<div><span>Discount</span><span>-'+fmt(discount)+'</span></div>':''),
   '<div class="sargo-grand"><b>Grand total (USD)</b><b>'+fmt(total)+'</b></div>',
   '</div></footer>',
   '<p class="sargo-powered">YOLA · POWERED BY DOUBLE GEE TECH</p>',
   '</article>'
  ].join('');
  body(printable);
  ensureSargoStyles();
  document.getElementById('printdoc').onclick=()=>window.print();
  document.getElementById('backdoc').onclick=()=>go(doc?'documents':isWorker()?'sell':'sales');
 }
 function ensureSargoStyles(){
  if(document.getElementById('sargo-premium-styles'))return;
  const style=document.createElement('style');style.id='sargo-premium-styles';
  style.textContent=[
   '.sargo-paper{box-sizing:border-box;background:#fff;color:#18202a;font-family:Arial,sans-serif;font-size:11px;border:1px solid #e0e4e9;margin:0 auto;max-width:850px;padding:34px 42px;min-height:1100px;box-shadow:0 10px 38px #0001}',
   '.sargo-header{display:flex;justify-content:space-between;align-items:flex-start;gap:22px}.sargo-left{width:64%}.sargo-logo{display:block;object-fit:contain;object-position:left center;max-width:240px;max-height:85px}.sargo-business{display:flex;flex-direction:column;gap:4px;margin-top:14px}.sargo-business strong{font-size:14px}.sargo-business span{font-size:11px}.sargo-head-right{text-align:right;display:flex;flex-direction:column;gap:7px}.sargo-head-right h3{margin:0;color:#22244a;font-size:15px}.sargo-separator{border-bottom:1px solid #d0d5da;margin:23px 0}.sargo-details{display:grid;grid-template-columns:1fr 1fr;gap:30px;min-height:115px}.sargo-details p{margin:6px 0}.sargo-reference{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));margin:16px 0 11px;text-align:center}.sargo-reference b{padding:5px 2px}.sargo-reference span{border:1px solid #4a4f59;padding:4px 2px;min-height:23px;overflow-wrap:anywhere}.sargo-lines{width:100%;border-collapse:collapse;font-size:10px}.sargo-lines th{text-align:left;text-decoration:underline;border-bottom:1px solid #666;padding:7px 4px}.sargo-lines th:nth-child(n+3),.sargo-lines .num{text-align:right}.sargo-lines td{padding:5px 4px;vertical-align:top}.sargo-lines tbody tr:nth-child(even){background:#fafafa}.sargo-note{margin-top:22px;font-size:11px;font-weight:600}.sargo-bottom{display:flex;justify-content:space-between;gap:35px;align-items:flex-end;margin-top:155px}.sargo-signature{width:50%;display:grid;gap:12px}.sargo-banking{margin-top:12px}.sargo-banking p{margin:6px 0}.sargo-prices{width:42%;display:grid;gap:9px}.sargo-prices>div{display:flex;justify-content:space-between;gap:12px}.sargo-grand{padding:8px 0;border-top:1px solid #222;border-bottom:2px solid #222}.sargo-powered{text-align:center;color:#777;font-size:9px;margin-top:35px}',
   '.sargo-paper.thermal{max-width:300px;min-height:0;padding:17px 12px;box-shadow:none}.thermal .sargo-header{display:block}.thermal .sargo-left{width:100%;text-align:center}.thermal .sargo-logo{max-width:170px;max-height:60px;margin:auto}.thermal .sargo-head-right{text-align:center;margin-top:14px}.thermal .sargo-details{min-height:0;grid-template-columns:1fr;gap:8px}.thermal .sargo-details>div:nth-child(2),.thermal .sargo-reference,.thermal .sargo-signature{display:none}.thermal .sargo-lines{font-size:9px}.thermal .sargo-lines td,.thermal .sargo-lines th{padding:4px 2px}.thermal .sargo-lines th:nth-child(1),.thermal .sargo-lines th:nth-child(4),.thermal .sargo-lines th:nth-child(6),.thermal .sargo-lines td:nth-child(1),.thermal .sargo-lines td:nth-child(4),.thermal .sargo-lines td:nth-child(6){display:none}.thermal .sargo-bottom{margin-top:22px;display:block}.thermal .sargo-prices{width:100%}',
   '@media print{@page{size:A4;margin:9mm}html,body{background:#fff!important}#shell .sidebar,#shell .topbar,.no-print{display:none!important}#shell .main{margin:0!important;padding:0!important}.sargo-paper{box-shadow:none;border:0;margin:0;min-height:0;max-width:none;padding:0}.sargo-paper.thermal{width:76mm;max-width:76mm;padding:0}.sargo-lines{break-inside:avoid}}'
  ].join('\n');
  document.head.appendChild(style);
 }
 // If the core has already created its nav, immediately re-render permissions.
 if(user?.role==='worker'){
  try { nav(); if(screen!=='sell')go('sell'); }catch(e){}
 }
})();