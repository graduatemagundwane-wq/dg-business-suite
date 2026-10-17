'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const script=fs.readFileSync(path.join(__dirname,'../public/app.js'),'utf8');
async function settle(){for(let i=0;i<50;i++)await Promise.resolve()}
function browserStub(){
  const requests=[],changes=[],timers=new Map();let timerId=0,status='inactive',registered=false,signedIn=false,redirect=null;
  const location={pathname:'/',search:'',replace(url){redirect=url}};
  const history={replaceState(_a,_b,url){const p=new URL(url,'https://yola.test');location.pathname=p.pathname;location.search=p.search;changes.push(url)}};
  const app={innerHTML:'',prepend(){}};
  const elements={app};
  function element(id){if(id!=='app' && !app.innerHTML.includes('id="'+id+'"'))return null;return elements[id]||(elements[id]={id,innerHTML:'',textContent:'',value:'',hidden:false,disabled:false,onclick:null,onsubmit:null,querySelector(){return {disabled:false,textContent:'',dataset:{label:'Create account'}}},prepend(){},append(){}})}
  const fetch=async(url,opts={})=>{
   requests.push({url,method:opts.method||'GET'});
   const send=(payload,ok=true)=>({ok,status:ok?200:401,json:async()=>payload});
   if(url==='/api/register'){
     assert.equal(opts.method,'POST');const values=JSON.parse(opts.body);
     assert.equal(values.business,'Myrhh Boutique');registered=true;signedIn=true;status='inactive';
     return send({success:true,businessCode:'YOLA-TEST-PENDING',license:{status:'inactive',active:false}});
   }
   if(url==='/api/me')return send({authenticated:signedIn,user:signedIn?{id:'owner01',name:'Myrhh',business:'Myrhh Boutique',role:'owner',businessCode:'YOLA-TEST-PENDING',license:{status,active:status==='active'}}:null});
   if(url==='/api/logout'){assert.equal(opts.method,'POST');signedIn=false;return send({success:true})}
   if(url==='/api/login'){const b=JSON.parse(opts.body);assert.equal(b.email,'owner@myrhh.example');signedIn=true;return send({success:true})}
   throw Error('Unexpected request '+url);
  };
  const context={document:{getElementById:element,createElement(){return element('dynamic')}},history,location,URLSearchParams,FormData:class{constructor(ev){this.data=ev.data||{}}entries(){return Object.entries(this.data)}},fetch,console,Promise,setInterval(fn,ms){assert.ok(ms>=7000);let id=++timerId;timers.set(id,fn);return id},clearInterval(id){timers.delete(id)}};
  vm.createContext(context);vm.runInContext(script,context);return {context,app,elements,requests,changes,timers,location,get redirected(){return redirect},setStatus(s){status=s}};
}
test('new business appears immediately pending, then approval sends owner to sign-in, not POS',async()=>{
 const b=browserStub();await settle();
 assert.match(b.app.innerHTML,/Create your Yola account/);
 const f=b.elements.authform;
 await f.onsubmit({preventDefault(){},target:{querySelector(){return {disabled:false,textContent:'',dataset:{label:'Create account'}}},data:{business:'Myrhh Boutique',name:'Myrhh',phone:'0785124463',email:'owner@myrhh.example',password:'long-password-for-test'}}});
 await settle();
 assert.equal(b.location.search,'?activation=waiting');
 assert.match(b.app.innerHTML,/Waiting for DG Tech activation/);
 assert.match(b.app.innerHTML,/YOLA-TEST-PENDING/);
 assert.equal(b.redirected,null,'Must not bypass sign-in before approval');
 b.setStatus('active');
 assert.ok(b.timers.size>0,'Waiting page must poll Master Control');
 await [...b.timers.values()][0]();await settle();
 assert.equal(b.location.search,'?activated=1');
 assert.match(b.app.innerHTML,/Welcome back/);
 assert.match(b.elements.msg.textContent,/Sign in using the email and password you created/);
 assert.equal(b.elements.msg.hidden,false,'Activation message must be visible');
 assert.equal(b.redirected,null,'Approval must not directly open workspace');
 assert.ok(b.requests.some(x=>x.url==='/api/logout'),'Approval requires logout');
 await b.elements.authform.onsubmit({preventDefault(){},target:{querySelector(){return {disabled:false,textContent:'',dataset:{label:'Sign in'}}},data:{email:'owner@myrhh.example',password:'long-password-for-test'}}});await settle();
 assert.equal(b.redirected,'/workspace.html','Valid approved sign-in should open workspace');
});
test('registration persists new owner, installation, product account transaction before replying',()=>{
 const api=fs.readFileSync(path.join(__dirname,'../api/index.js'),'utf8');
 const body=api.slice(api.indexOf('async function register('),api.indexOf('async function login('));
 for(const x of ["await db.query('BEGIN')",'INSERT INTO customers','INSERT INTO installations','INSERT INTO yola_web_users','INSERT INTO product_accounts',"await db.query('COMMIT')","await db.query('ROLLBACK')"]){assert.ok(body.includes(x),'Missing atomic master record '+x)}
 assert.ok(body.indexOf("await db.query('COMMIT')") < body.indexOf('return ok(res,'),'Respond only after commit');
 assert.match(body, /'inactive'.*?RETURNING id/);
});