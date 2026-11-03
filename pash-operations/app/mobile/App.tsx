import React, {useEffect, useRef, useState} from 'react';
import {ActivityIndicator, Alert, AppState, FlatList, KeyboardAvoidingView, Platform, BackHandler, Pressable, RefreshControl, SafeAreaView, ScrollView, StatusBar, StyleSheet, Switch, Text, TextInput, View} from 'react-native';
import * as SecureStore from 'expo-secure-store';
import * as LocalAuthentication from 'expo-local-authentication';
import {CameraView, useCameraPermissions} from 'expo-camera';
import * as ImagePicker from 'expo-image-picker';
import {cleanScan} from './scan-utils';
import {resolveBack} from './navigation';

type Json = Record<string,any>;
const API=(process.env.EXPO_PUBLIC_API_URL || '').replace(/\/$/,'');
const FIXED_ORG=(process.env.EXPO_PUBLIC_ORGANIZATION_ID || '').trim();
const ENV_OK=API.startsWith('https://') || (__DEV__ && API.startsWith('http://'));
const SYMBOLS:Record<string,string>={
  dashboard:'⌂',account:'◉',attendance:'◷',teamattendance:'✓',customers:'♙',vehicles:'▣',bookings:'▤',jobs:'⚙',inspections:'◇',worklogs:'◷',
  gearboxreports:'⚙',batteryreports:'▰',qualifications:'✦',safetypermits:'✓',equipment:'▣',parts:'▦',suppliers:'♙',purchaseorders:'▤',
  quotes:'▧',invoices:'▤',expenses:'◈',warranties:'✓',claims:'◇',reviews:'★',courses:'▣',lessons:'▤',assessments:'✓',enrollments:'♙',
  certificates:'✦',staffusers:'♙',fleets:'▣',notifications:'◉'
};
const STATUS_LABEL:Record<string,string>={received:'Received',diagnosis:'Diagnosis',awaiting_approval:'Awaiting customer approval',awaiting_parts:'Awaiting parts',repairing:'Repair in progress',quality_check:'Quality inspection',ready:'Ready for collection',delivered:'Delivered'};
const C={bg:'#F4F7FB',dark:'#08182A',muted:'#708397',teal:'#11A28B',blue:'#116EEA',paleBlue:'#EAF3FF',white:'#FFFFFF',line:'#E2EAF2',gold:'#D9AC60'};
const MENU:Record<string,string[]> = {
  staffusers:['owner','manager'],
  account:['owner','manager','service_advisor','mechanic','dsg_specialist','battery_specialist','inventory','accountant','instructor','student','customer'],
  customers:['owner','manager','service_advisor'],
  teamattendance:['owner','manager'],
  attendance:['owner','manager','service_advisor','mechanic','dsg_specialist','battery_specialist','inventory','accountant','instructor'],
  dashboard:['owner','manager','service_advisor','mechanic','dsg_specialist','battery_specialist','inventory','accountant','instructor','customer','student'],
  jobs:['owner','manager','service_advisor','mechanic','dsg_specialist','battery_specialist','accountant','inventory','customer'],
  vehicles:['owner','manager','service_advisor','mechanic','dsg_specialist','battery_specialist','accountant','inventory','customer'],
  bookings:['owner','manager','service_advisor','mechanic','dsg_specialist','battery_specialist','customer'],
  parts:['owner','manager','service_advisor','mechanic','dsg_specialist','battery_specialist','inventory'],
  quotes:['owner','manager','service_advisor','accountant','customer'],
  invoices:['owner','manager','service_advisor','accountant','customer'],
  courses:['owner','manager','instructor','student','customer'],
  suppliers:['owner','manager','inventory','accountant'],
  purchaseorders:['owner','manager','inventory','accountant'],
  equipment:['owner','manager','inventory','mechanic','dsg_specialist','battery_specialist'],
  worklogs:['owner','manager','mechanic','dsg_specialist','battery_specialist'],
  gearboxreports:['owner','manager','dsg_specialist'],
  batteryreports:['owner','manager','battery_specialist'],
  inspections:['owner','manager','service_advisor','mechanic','dsg_specialist','battery_specialist'],
  expenses:['owner','manager','accountant'],
  warranties:['owner','manager','service_advisor','customer'],
  claims:['owner','manager','service_advisor','customer'],
  fleets:['owner','manager','service_advisor','customer'],
  lessons:['owner','manager','instructor','student'],
  assessments:['owner','manager','instructor','student'],
  enrollments:['owner','manager','instructor','student'],
  certificates:['owner','manager','instructor','student'],
  qualifications:['owner','manager','mechanic','dsg_specialist','battery_specialist'],
  reviews:['owner','manager','service_advisor','customer'],
  safetypermits:['owner','manager','battery_specialist'],
  notifications:['owner','manager','service_advisor','mechanic','dsg_specialist','battery_specialist','inventory','accountant','instructor','student','customer']
};
const LABELS:Record<string,string>={staffusers:'Employees',account:'Account & security',customers:'Customers',attendance:'My attendance',teamattendance:'Team attendance approvals',dashboard:'Home',jobs:'Job cards',vehicles:'Vehicles',bookings:'Bookings',parts:'Spare parts',quotes:'Quotations',invoices:'Invoices',courses:'Academy',suppliers:'Suppliers',purchaseorders:'Purchase orders',equipment:'Equipment',worklogs:'Labor time',gearboxreports:'DSG reports',batteryreports:'Battery reports',inspections:'Inspections',expenses:'Expenses',warranties:'Warranties',claims:'Warranty claims',fleets:'Fleets',lessons:'Lessons',assessments:'Exams',enrollments:'Enrollments',certificates:'Certificates',qualifications:'Qualifications',reviews:'Reviews',notifications:'Inbox',safetypermits:'HV safety permits'};
const SHOW:Record<string,string[]>={staffusers:['id','name','email','roles','active'],attendance:['id','clock_in','clock_out','approval_status','decision_by','unpaid_break_minutes','worked_minutes','payable_minutes','overnight','missing_checkout'],teamattendance:['id','user_id','clock_in','clock_out','approval_status','decision_by','decision_at','decision_note','unpaid_break_minutes','payable_minutes','overnight','missing_checkout'],jobs:['id','vehicle_id','category','status','complaint','diagnosis'],vehicles:['id','registration','make','model','year','transmission'],bookings:['id','service','scheduled_at','status'],parts:['id','sku','name','quantity','price'],quotes:['id','job_id','total','status'],invoices:['id','quote_id','total','paid'],courses:['id','title','description','price','published'],suppliers:['id','name','phone'],purchaseorders:['id','supplier_id','status','total'],equipment:['id','name','serial','status','calibration_due'],worklogs:['id','job_id','minutes','description'],gearboxreports:['id','job_id','transmission_code','fault_codes','test_results'],batteryreports:['id','job_id','chemistry','battery_serial','voltage','high_voltage'],inspections:['id','job_id','inspector_id','notes','checklist'],expenses:['id','category','description','amount','currency'],warranties:['id','job_id','coverage','expires_at'],claims:['id','warranty_id','description','status'],fleets:['id','name','contact'],lessons:['id','title','course_id','body','published'],assessments:['id','title','course_id','published','questions'],enrollments:['id','student_id','course_id','status','progress'],certificates:['id','student_id','course_id','verification_code'],qualifications:['id','user_id','qualification','high_voltage_approved'],reviews:['id','job_id','rating','comment'],notifications:['id','message','read'],safetypermits:['id','job_id','technician_id','authorized_by','created_at']};
const PATHS:Record<string,string>={staffusers:'/admin/users',attendance:'/attendance/me',teamattendance:'/attendance',purchaseorders:'/purchase-orders',worklogs:'/work-logs',gearboxreports:'/gearbox-reports',batteryreports:'/battery-reports',inspections:'/inspections',claims:'/warranty-claims',lessons:'/academy/lessons',assessments:'/academy/assessments',certificates:'/academy/certificates',qualifications:'/staff/qualifications',safetypermits:'/battery-safety-permits'};
type InputField = [string,string,'text'|'number'|'boolean'];
type CreateSpec = {roles:string[],fields:InputField[]};
const CREATE:Record<string,CreateSpec>={
  staffusers:{roles:['owner','manager'],fields:[['name','Employee full name','text'],['email','Employee email','text'],['roles','Comma-separated roles','text'],['password','Temporary password (minimum 12 characters)','text']]},
  customers:{roles:['owner','manager','service_advisor'],fields:[['name','Customer full name','text'],['phone','Contact number','text'],['email','Email (optional)','text']]},
  vehicles:{roles:['owner','manager','service_advisor'],fields:[['customer_id','Customer ID','number'],['registration','Registration number','text'],['make','Manufacturer','text'],['model','Model','text'],['year','Year','number'],['vin','VIN (optional)','text'],['transmission','Transmission type','text'],['mileage','Mileage','number']]},
  bookings:{roles:['owner','manager','service_advisor'],fields:[['customer_id','Customer ID','number'],['vehicle_id','Vehicle ID','number'],['service','Requested service','text'],['scheduled_at','Date & time (YYYY-MM-DD HH:MM)','text'],['notes','Notes (optional)','text']]},
  jobs:{roles:['owner','manager','service_advisor'],fields:[['vehicle_id','Vehicle ID','number'],['category','Category: mechanical / dsg / battery / electrical / diagnostics','text'],['complaint','Customer complaint','text'],['assigned_to','Technician user ID (optional)','number']]},
  parts:{roles:['owner','manager','inventory'],fields:[['sku','Unique SKU','text'],['name','Part name','text'],['quantity','Opening stock quantity','number'],['reorder_level','Reorder threshold','number'],['cost','Unit purchase cost','number'],['price','Unit selling price','number']]},
  quotes:{roles:['owner','manager','service_advisor'],fields:[['job_id','Job ID','number'],['label','Quotation line description','text'],['quantity','Quantity','number'],['unit_price','Unit price','number'],['additional_lines','Additional lines: Description | Qty | Price (one per row)','text']]},
  courses:{roles:['owner','manager','instructor'],fields:[['title','Course title','text'],['description','Course description','text'],['price','Course fee','number']]},
  assessments:{roles:['owner','manager','instructor'],fields:[['course_id','Course ID','number'],['title','Exam title','text'],['prompt','Question','text'],['choice_a','Answer A','text'],['choice_b','Answer B','text'],['choice_c','Answer C','text'],['choice_d','Answer D','text'],['answer','Correct choice (0=A,1=B,2=C,3=D)','number'],['passing_percent','Passing percentage','number']]},
  certificates:{roles:['owner','manager'],fields:[['student_id','Student user ID','number'],['course_id','Completed course ID','number']]},
  enrollments:{roles:['owner','manager','instructor'],fields:[['student_id','Student user ID','number'],['course_id','Course ID','number']]},
  purchaseorders:{roles:['owner','manager','inventory'],fields:[['supplier_id','Supplier ID','number'],['part_id','Part ID','number'],['quantity','Quantity to order','number'],['unit_cost','Unit purchase cost','number']]},
  fleets:{roles:['owner','manager','service_advisor'],fields:[['customer_id','Corporate customer ID','number'],['name','Fleet name','text'],['contact','Contact person','text']]},
  warranties:{roles:['owner','manager','service_advisor'],fields:[['job_id','Delivered job ID','number'],['coverage','Warranty coverage and exclusions','text'],['duration_days','Warranty duration in days','number'],['mileage_limit','Mileage limit (optional)','number']]},
  qualifications:{roles:['owner','manager'],fields:[['user_id','Technician user ID','number'],['qualification','Verified qualification','text'],['high_voltage_approved','High-voltage qualification independently verified','boolean'],['expires_at','Expiry date (YYYY-MM-DD HH:MM, optional)','text']]},
  notifications:{roles:['owner','manager','service_advisor'],fields:[['recipient_id','Recipient user ID','number'],['message','Message','text']]},
  safetypermits:{roles:['owner','manager'],fields:[['job_id','Battery job ID','number'],['technician_id','Qualified battery specialist user ID','number'],['risk_assessed','Risk assessment documented (true)','boolean'],['isolation_verified','Isolation physically verified (true)','boolean'],['ppe_checked','Correct PPE physically inspected (true)','boolean'],['emergency_plan_confirmed','Emergency plan checked (true)','boolean']]},
  worklogs:{roles:['owner','manager','mechanic','dsg_specialist','battery_specialist'],fields:[['job_id','Assigned Job ID','number'],['minutes','Minutes worked','number'],['description','Work summary','text']]},
  inspections:{roles:['owner','manager','service_advisor','mechanic','dsg_specialist','battery_specialist'],fields:[['job_id','Job ID','number'],['notes','Inspection findings','text'],['quality_passed','FINAL QA passed (true only when physically verified)','boolean']]},
  gearboxreports:{roles:['owner','manager','dsg_specialist'],fields:[['job_id','DSG Job ID','number'],['transmission_code','Gearbox code','text'],['fault_codes','Fault codes (comma separated)','text'],['components_replaced','Components replaced (comma separated)','text'],['test_results','Diagnostics and test results','text']]},
  batteryreports:{roles:['owner','manager','battery_specialist'],fields:[['job_id','Battery Job ID','number'],['chemistry','Battery chemistry','text'],['battery_serial','Serial number','text'],['voltage','Voltage','number'],['health_percent','Health percent','number'],['notes','Test procedure / notes','text'],['high_voltage','HV battery (true ONLY with verified qualification & approved physical safety permit)','boolean']]},
  suppliers:{roles:['owner','manager','inventory'],fields:[['name','Supplier name','text'],['phone','Telephone','text'],['email','Email','text'],['notes','Notes','text']]},
  equipment:{roles:['owner','manager','inventory'],fields:[['name','Equipment','text'],['serial','Serial number','text'],['category','Category','text'],['location','Location','text']]},
  expenses:{roles:['owner','manager','accountant'],fields:[['category','Expense category','text'],['description','Description','text'],['amount','Amount','number'],['currency','Currency: USD or ZWG','text']]},
  claims:{roles:['owner','manager','service_advisor','customer'],fields:[['warranty_id','Warranty ID','number'],['description','Issue description','text']]},
  reviews:{roles:['customer'],fields:[['job_id','Delivered Job ID','number'],['rating','Rating 1-5','number'],['comment','Feedback','text']]},
  lessons:{roles:['owner','manager','instructor'],fields:[['course_id','Course ID','number'],['title','Lesson title','text'],['body','Lesson content','text']]},
};
const NEXT:Record<string,string[]>={received:['diagnosis'],diagnosis:['awaiting_approval','awaiting_parts'],awaiting_approval:['awaiting_parts','repairing'],awaiting_parts:['repairing'],repairing:['quality_check'],quality_check:['repairing','ready'],ready:['delivered']};
function Button({label,onPress,secondary=false,disabled=false}:{label:string,onPress:()=>void,secondary?:boolean,disabled?:boolean}){
  return <Pressable accessibilityRole="button" accessibilityLabel={label} disabled={disabled} onPress={onPress} style={[styles.button,secondary?styles.secondary:null,disabled?{opacity:.5}:null]}><Text style={[styles.buttonText,secondary?{color:C.dark}:null]}>{label}</Text></Pressable>;
}
function Field({label,value,set,secure=false,number=false,multiline=false}:{label:string,value:string,set:(v:string)=>void,secure?:boolean,number?:boolean,multiline?:boolean}){
  return <View style={styles.field}><Text style={styles.label}>{label}</Text><TextInput autoCapitalize="none" autoCorrect={false} secureTextEntry={secure} multiline={multiline} textAlignVertical="top" keyboardType={number?'numeric':'default'} value={value} onChangeText={set} style={[styles.input,multiline?{height:115,paddingVertical:13}:null]} placeholderTextColor="#9CA9B0" /></View>;
}
function OperationsApp(){
  const [biometricEnabled,setBiometricEnabled]=useState(false);const backgroundAt=useRef<number|null>(null);
  const [token,setToken]=useState('');const [profile,setProfile]=useState<Json|null>(null);const [loading,setLoading]=useState(true);
  const [oldPassword,setOldPassword]=useState('');const [newPassword,setNewPassword]=useState('');
  const [email,setEmail]=useState('');const [password,setPassword]=useState('');const [org,setOrg]=useState(FIXED_ORG);
  const [cameraPermission,requestCameraPermission]=useCameraPermissions();const [scanField,setScanField]=useState<string|null>(null);
  const [showMenu,setShowMenu]=useState(false);const [menuSearch,setMenuSearch]=useState('');const [action,setAction]=useState<{name:string,id:number}|null>(null);const [actionForm,setActionForm]=useState<Json>({});const [error,setError]=useState('');
  const [compose,setCompose]=useState(false);const [form,setForm]=useState<Json>({});const [tab,setTab]=useState('dashboard');const [rows,setRows]=useState<Json[]>([]);const [summary,setSummary]=useState<Json>({});const [busy,setBusy]=useState(false);const [refreshing,setRefreshing]=useState(false);
  const [unpaidBreakMinutes,setUnpaidBreakMinutes]=useState('0');
  const roles:string[]=profile?.roles || [];
  const routeTrail=useRef<Array<{tab:string,menu:boolean}>>([]);
  async function openScanner(field:string){
    try{
      const permission=cameraPermission?.granted?cameraPermission:await requestCameraPermission();
      if(!permission?.granted){Alert.alert('Camera permission','Allow camera access to scan a vehicle, part or work-order barcode.');return;}
      setScanField(field);
    }catch(e:any){Alert.alert('Camera unavailable',e.message)}
  }

  const allowed=(screen:string)=>roles.includes('owner')||(MENU[screen]||[]).some(x=>roles.includes(x));
  function rememberCurrent(){
    routeTrail.current.push({tab,menu:showMenu});
    if(routeTrail.current.length>32)routeTrail.current.shift();
  }
  function navigateTo(screen:string){
    if(!allowed(screen))return;
    if(showMenu || tab!==screen)rememberCurrent();
    setTab(screen);setShowMenu(false);setCompose(false);setAction(null);setForm({});
  }
  function openWorkspaces(){
    if(!showMenu){rememberCurrent();setShowMenu(true);setCompose(false);setAction(null);}
  }
  function navigateBack(){
    const plan=resolveBack({tab,menu:showMenu,scanner:!!scanField,action:!!action,compose},routeTrail.current);
    if(plan.kind==='scanner'){setScanField(null);return;}
    if(plan.kind==='action'){setAction(null);setActionForm({});return;}
    if(plan.kind==='compose'){setCompose(false);return;}
    if(plan.kind==='route'&&plan.route){
      routeTrail.current.pop();
      setTab(plan.route.tab);setShowMenu(plan.route.menu);
      setAction(null);setCompose(false);return;
    }
    if(plan.kind==='home'){setTab('dashboard');setShowMenu(false);}
    // plan.kind==='root': hardware back consumed, app remains open.
  }
  useEffect(()=>{
    const sub=BackHandler.addEventListener('hardwareBackPress',()=>{
      navigateBack();
      return true;
    });
    return ()=>sub.remove();
  },[scanField,action,compose,showMenu,tab,profile]);
  async function request(path:string,init:RequestInit={},t=token){
    if(!API || !ENV_OK)throw new Error('Application server is not securely configured. Ask your administrator.');
    const resp=await fetch(API+'/api'+path,{...init,headers:{'Content-Type':'application/json',...(t?{Authorization:'Bearer '+t}:{}),...(init.headers||{})}});
    const body=await resp.json().catch(()=>({detail:'Server response unavailable'}));
    if(!resp.ok)throw new Error(typeof body.detail==='string'?body.detail:`Request failed (${resp.status})`);
    return body;
  }
  useEffect(()=>{(async()=>{
    try{
      const old=await SecureStore.getItemAsync('pash_token');
      const enabled=(await SecureStore.getItemAsync('pash_biometric'))==='true';
      setBiometricEnabled(enabled);
      if(old){
        if(enabled){
          const biometrics=await LocalAuthentication.authenticateAsync({promptMessage:'Unlock PASH Auto Operations',biometricsSecurityLevel:'strong'});
          if(!biometrics.success){await SecureStore.deleteItemAsync('pash_token');return;}
        }
        const me=await request('/auth/me',{},old);setToken(old);setProfile(me);setShowMenu(false);
      }
    }catch{try{await SecureStore.deleteItemAsync('pash_token')}catch{/* token may be unreadable */}}finally{setLoading(false)}
  })()},[]);
  useEffect(()=>{
    const subscription=AppState.addEventListener('change',async state=>{
      if(state==='background'||state==='inactive')backgroundAt.current=Date.now();
      if(state==='active' && backgroundAt.current && Date.now()-backgroundAt.current>300000 && token){
        backgroundAt.current=null;
        if(biometricEnabled){
          try{const result=await LocalAuthentication.authenticateAsync({promptMessage:'Unlock PASH Auto Operations',biometricsSecurityLevel:'strong'});
            if(result.success)return;
          }catch{/* fail closed to password */}
        }
        try{await SecureStore.deleteItemAsync('pash_token')}catch{/* safe lock */}setToken('');setProfile(null);routeTrail.current=[];setShowMenu(false);
        Alert.alert('Session locked','Please sign in again to continue.');
      }
    });
    return ()=>subscription.remove();
  },[token,biometricEnabled]);
  async function enableBiometrics(){
    try{
      const supported=await LocalAuthentication.hasHardwareAsync()&&await LocalAuthentication.isEnrolledAsync();
      if(!supported){Alert.alert('Not available','Set up a device fingerprint or strong face unlock first.');return;}
      const result=await LocalAuthentication.authenticateAsync({promptMessage:'Enable device biometric unlock',biometricsSecurityLevel:'strong'});
      if(!result.success)return;
      await SecureStore.setItemAsync('pash_biometric','true');setBiometricEnabled(true);
      Alert.alert('Enabled','Biometric unlock is enabled on this device.');
    }catch(e:any){Alert.alert('Unable to enable',e.message)}
  }
  async function disableBiometrics(){await SecureStore.deleteItemAsync('pash_biometric');setBiometricEnabled(false);}

  useEffect(()=>{if(!profile||tab==='account')return;load(tab)},[tab,profile]);
  async function login(){setBusy(true);try{const d=await request('/auth/login',{method:'POST',body:JSON.stringify({email,password,organization_id:Number(org)})},'');await SecureStore.setItemAsync('pash_token',d.access_token);setToken(d.access_token);setProfile(d.user);setPassword('');routeTrail.current=[];setTab('dashboard');setShowMenu(false);}catch(e:any){Alert.alert('Unable to sign in',e.message)}finally{setBusy(false)}}
  async function logout(){if(token){try{await request('/auth/logout',{method:'POST'});}catch{/* clear device token even when offline */}}await SecureStore.deleteItemAsync('pash_token');setToken('');setProfile(null);setRows([]);setTab('dashboard');routeTrail.current=[];setShowMenu(false);setAction(null);setError('');}
  async function load(target:string){setRefreshing(true);setError('');try{if(target==='dashboard')setSummary(await request('/dashboard'));else setRows(await request(PATHS[target]||'/'+target));}catch(e:any){if(String(e.message).toLowerCase().includes('token')||String(e.message).toLowerCase().includes('not authenticated')){await logout();Alert.alert('Session expired','Sign in again to continue.');return;}setError(e.message);}finally{setRefreshing(false)}}
  function readFields(spec:CreateSpec):Json{
    const out:Json={};
    for(const [key,label,kind] of spec.fields){
      const raw=String(form[key]??'').trim();
      if(!raw)continue;
      if(kind==='number'){
        const number=Number(raw);
        if(!Number.isFinite(number))throw new Error(label+' must be a number');
        out[key]=number;
      }else if(kind==='boolean'){
        if(raw!=='true'&&raw!=='false')throw new Error(label+' must be true or false');
        out[key]=raw==='true';
      }else out[key]=raw;
    }
    return out;
  }
  function asIso(value:string,field:string){
    const trimmed=(value||'').trim().replace(' ','T');
    const dt=new Date(trimmed);
    if(!trimmed || Number.isNaN(dt.valueOf()))throw new Error(field+' needs YYYY-MM-DD HH:MM');
    return dt.toISOString();
  }
  // Offline-safe drafts: encrypted locally, never auto-replayed to avoid duplicate live jobs.
  const DRAFT_SCREENS=new Set(['jobs','vehicles','bookings','inspections','gearboxreports','batteryreports','worklogs']);
  function draftKey(screen:string){return `pash_draft_${profile?.organization_id}_${profile?.id}_${screen}`;}
  async function saveDraft(){
    if(!profile||!DRAFT_SCREENS.has(tab)){Alert.alert('Draft not supported','Sensitive financial, account or safety authorization actions cannot be queued offline.');return;}
    const payload=JSON.stringify({savedAt:new Date().toISOString(),screen:tab,form});
    if(payload.length>1700){Alert.alert('Draft too large','This draft exceeds encrypted device storage limits. Shorten the notes and retry.');return;}
    try{await SecureStore.setItemAsync(draftKey(tab),payload);
      Alert.alert('Draft secured','Saved only on this device. Review it and submit manually when connected.');}
    catch(e:any){Alert.alert('Not saved',e.message);}
  }
  async function restoreDraft(){
    if(!profile||!DRAFT_SCREENS.has(tab))return;
    try{const saved=await SecureStore.getItemAsync(draftKey(tab));
      if(!saved){Alert.alert('No draft','No saved offline draft exists for this workspace.');return;}
      const d=JSON.parse(saved);
      if(d.screen!==tab||typeof d.form!=='object'||!d.form)throw new Error('Invalid draft');
      setForm(d.form);setCompose(true);
      Alert.alert('Draft restored','Review the details before saving to the server. It has NOT been submitted yet.');
    }catch(e:any){Alert.alert('Draft not restored',e.message);}
  }
  async function createRecord(){
    const spec=CREATE[tab];if(!spec)return;setBusy(true);
    try{
      const values=readFields(spec);
      if(tab==='bookings')values.scheduled_at=asIso(values.scheduled_at,'Appointment time');
      if(tab==='warranties' && (!Number.isInteger(values.duration_days)||values.duration_days<1||values.duration_days>3650))throw new Error('Warranty duration must be 1–3650 days');
      if(tab==='inspections'){
        if(values.quality_passed===true&&!roles.some(r=>['owner','manager'].includes(r)))throw new Error('Only managers can certify final QA');
        values.checklist={quality_passed:values.quality_passed===true,observations_recorded:Boolean(values.notes)};
        delete values.quality_passed;
      }
      if(tab==='gearboxreports'){
        values.fault_codes=String(values.fault_codes||'').split(',').map(x=>x.trim()).filter(Boolean);
        values.components_replaced=String(values.components_replaced||'').split(',').map(x=>x.trim()).filter(Boolean);
      }
      if(tab==='batteryreports')values.high_voltage=values.high_voltage===true;
      if(tab==='expenses')values.currency=values.currency||'USD';
      if(tab==='lessons')values.published=false;
      if(tab==='staffusers'){
        values.roles=String(values.roles||'').split(',').map((v:string)=>v.trim()).filter(Boolean);
        if(values.roles.length===0)throw new Error('Choose an employee role');
        if(values.roles.includes('owner')&&!roles.includes('owner'))throw new Error('Only an owner can create an owner account');
      }
      if(tab==='courses')values.published=false;
      if(tab==='assessments'){
        const {prompt,choice_a,choice_b,choice_c,choice_d,answer,passing_percent}=values;
        if(!Number.isInteger(answer)||answer<0||answer>3)throw new Error('Correct choice index must be 0,1,2 or 3');
        if(![choice_a,choice_b,choice_c,choice_d].every(c=>typeof c==='string'&&c.trim()))throw new Error('All four answer options are required');
        values.questions=[{prompt,choices:[choice_a,choice_b,choice_c,choice_d],answer}];
        values.passing_percent=passing_percent??70;values.published=false;
        for(const k of ['prompt','choice_a','choice_b','choice_c','choice_d','answer'])delete values[k];
      }
      if(tab==='quotes'){
        if(!values.label || !values.quantity || values.unit_price===undefined)throw new Error('Enter quote description, quantity and unit price');
        values.items=[{label:values.label,quantity:values.quantity,unit_price:values.unit_price}];
        for(const line of String(values.additional_lines||'').split('\n')){
          if(!line.trim())continue;
          const pieces=line.split('|').map(v=>v.trim());
          if(pieces.length!==3||!pieces[0]||!Number.isInteger(Number(pieces[1]))||Number(pieces[1])<1||!Number.isFinite(Number(pieces[2]))||Number(pieces[2])<0)throw new Error('Quotation lines must use: Description | Qty | Price');
          values.items.push({label:pieces[0],quantity:Number(pieces[1]),unit_price:Number(pieces[2])});
        }
        delete values.label;delete values.quantity;delete values.unit_price;delete values.additional_lines;
      }
      if(tab==='purchaseorders'){
        if(!values.part_id||!values.quantity||values.unit_cost===undefined)throw new Error('Part, quantity and cost required');
        values.lines=[{part_id:values.part_id,quantity:values.quantity,unit_cost:values.unit_cost}];
        delete values.part_id;delete values.quantity;delete values.unit_cost;
      }
      if(tab==='qualifications'){values.high_voltage_approved=values.high_voltage_approved===true;if(values.expires_at)values.expires_at=asIso(values.expires_at,'Qualification expiry');}
      if(tab==='safetypermits'&&!['risk_assessed','isolation_verified','ppe_checked','emergency_plan_confirmed'].every(k=>values[k]===true))throw new Error('Every physical safety prerequisite must be verified by a qualified supervisor before approval.');
      await request(tab==='staffusers'?'/admin/users':PATHS[tab]||'/'+tab,{method:'POST',body:JSON.stringify(values)});
      setForm({});setCompose(false);await load(tab);Alert.alert('Saved','Record stored successfully.');
    }catch(e:any){Alert.alert('Not saved',e.message)}finally{setBusy(false)}
  }
  function openForm(screen:string,defaults:Json={}){
    if(!allowed(screen))return;
    if(showMenu||tab!==screen)rememberCurrent();
    setTab(screen);setForm(defaults);setCompose(true);setShowMenu(false);setAction(null);
  }
  async function passwordChange(){
    if(busy ||newPassword.length<12){Alert.alert('Invalid password','The new password requires at least 12 characters.');return;}
    setBusy(true);
    try{
      await request('/auth/change-password',{method:'POST',body:JSON.stringify({current_password:oldPassword,new_password:newPassword})});
      setOldPassword('');setNewPassword('');await SecureStore.deleteItemAsync('pash_token');
      setToken('');setProfile(null);setShowMenu(true);
      Alert.alert('Password changed','All previous sessions have been revoked. Sign in again using the new password.');
    }catch(e:any){Alert.alert('Password not changed',e.message)}finally{setBusy(false)}
  }
  async function attendanceAction(kind:'clock-in'|'clock-out'){
    if(busy)return;
    setBusy(true);
    try{
      const minutes=Number(unpaidBreakMinutes);
      if(kind==='clock-out'&&(!Number.isInteger(minutes)||minutes<0||minutes>1440))throw new Error('Enter valid unpaid break minutes (0 to 1440)');
      await request('/attendance/'+kind,{method:'POST',...(kind==='clock-out'?{body:JSON.stringify({unpaid_break_minutes:minutes})}:{})});
      await load('attendance');
      Alert.alert('Attendance',kind==='clock-in'?'Check-in recorded. Pending manager approval.':'Shift finished. Approved shifts will count toward working hours.');
    }
    catch(e:any){Alert.alert('Attendance not recorded',e.message)}finally{setBusy(false)}
  }
  async function performAction(){
    if(!action ||busy)return;
    const {name,id}=action;setBusy(true);
    try{
      if(name==='attendance_approve'||name==='attendance_reject'){
        const decision=name==='attendance_approve'?'approve':'reject';
        const note=String(actionForm.note||'').trim();
        if(decision==='reject'&&!note)throw new Error('Enter a reason for rejecting this check-in');
        await request(`/attendance/${id}/decision`,{method:'POST',body:JSON.stringify({decision,note})});
      }
      if(name==='publish_course')await request(`/courses/${id}/publish`,{method:'PATCH',body:JSON.stringify({published:true})});
      if(name==='publish_lesson')await request(`/academy/lessons/${id}/publish`,{method:'PATCH',body:JSON.stringify({published:true})});
      if(name==='publish_exam')await request(`/academy/assessments/${id}/publish`,{method:'PATCH',body:JSON.stringify({published:true})});
      if(name==='attempt_exam'){
        const answers=actionForm.answers||[];
        if(answers.length!==rows.find(r=>r.id===id)?.questions?.length || answers.some((a:any)=>!Number.isInteger(a)))throw new Error('Answer every question before submitting');
        const result=await request(`/academy/assessments/${id}/attempt`,{method:'POST',body:JSON.stringify({answers})});
        Alert.alert('Exam result',`${result.score}% • ${result.passed?'PASS':'Not passed'}`);
      }
      if(name==='receive_order')await request(`/purchase-orders/${id}/receive`,{method:'POST'});
      if(name==='invoice_quote')await request(`/invoices/from-quote/${id}`,{method:'POST'});
      if(name==='issue_part')await request(`/parts/${id}/issue`,{method:'POST',body:JSON.stringify({job_id:Number(actionForm.job_id),quantity:Number(actionForm.quantity)})});
      if(name==='record_payment')await request(`/invoices/${id}/payments`,{method:'POST',body:JSON.stringify({amount:Number(actionForm.amount),method:actionForm.method||'cash'})});
      if(name==='complete_enrollment')await request(`/academy/enrollments/${id}/complete`,{method:'POST'});
      if(name==='revoke_certificate')await request(`/academy/certificates/${id}/revoke`,{method:'PATCH'});
      if(name==='set_equipment')await request(`/equipment/${id}`,{method:'PATCH',body:JSON.stringify({status:actionForm.status})});
      if(name==='close_claim')await request(`/warranty-claims/${id}`,{method:'PATCH',body:JSON.stringify({status:actionForm.status,resolution:actionForm.resolution})});
      setAction(null);setActionForm({});await load(tab);Alert.alert('Completed','The server confirmed the operation.');
    }catch(e:any){Alert.alert('Action failed',e.message)}finally{setBusy(false)}
  }
  async function captureJobEvidence(job:Json,kind:'intake'|'diagnostic'|'repair'|'quality'|'handover'='repair'){
    if(busy)return;
    try{
      const permission=await ImagePicker.requestCameraPermissionsAsync();
      if(!permission.granted){Alert.alert('Permission needed','Camera access is needed for workshop evidence.');return;}
      const result=await ImagePicker.launchCameraAsync({mediaTypes:['images'],quality:0.55,allowsEditing:false});
      if(result.canceled || !result.assets.length)return;
      const photo=result.assets[0];
      if(photo.fileSize && photo.fileSize>3000000){Alert.alert('Photo too large','Use a smaller photo, 3 MB maximum.');return;}
      Alert.alert('Submit photo','Attach this image to job #'+job.id+' as '+kind+' evidence?',[
        {text:'Cancel',style:'cancel'},
        {text:'Attach',onPress:async()=>{
          setBusy(true);
          try{
            const mime=photo.mimeType||'image/jpeg';
            if(!['image/jpeg','image/png'].includes(mime))throw new Error('Only JPEG and PNG supported');
            const body=new FormData();
            body.append('photo',{uri:photo.uri,name:'pash-job-'+job.id+'.'+(mime==='image/png'?'png':'jpg'),type:mime} as any);
            if(!API||!ENV_OK)throw new Error('Secure workshop server unavailable');
            const response=await fetch(`${API}/api/jobs/${job.id}/photos?kind=${kind}`,{method:'POST',headers:{Authorization:'Bearer '+token},body});
            const json=await response.json().catch(()=>({}));
            if(!response.ok)throw new Error(json.detail||'Upload failed');
            Alert.alert('Photo recorded','Workshop photo verified and stored against job #'+job.id+'.');
          }catch(e:any){Alert.alert('Photo not stored',e.message||String(e))}
          finally{setBusy(false)}
        }}
      ]);
    }catch(e:any){Alert.alert('Camera unavailable',e.message||String(e))}
  }
  async function viewJobEvidence(job:Json){
    try{
      const result=await request(`/jobs/${job.id}/photos`);
      Alert.alert('Repair evidence',result.length?`${result.length} photo(s) attached to this job. Only authorized users can retrieve the originals.`:'No photographs attached yet.');
    }catch(e:any){Alert.alert('Evidence unavailable',e.message)}
  }
  async function updateJob(row:Json){const allowedNext=(NEXT[row.status]||[]).filter(x=>!['ready','delivered'].includes(x)||roles.some(r=>['owner','manager','service_advisor'].includes(r)));
    if(!allowedNext.length)return;Alert.alert('Update job #'+row.id,'Move to which stage?',allowedNext.map(next=>({text:next.replace(/_/g,' '),onPress:async()=>{try{await request(`/jobs/${row.id}/status`,{method:'PATCH',body:JSON.stringify({status:next})});load('jobs')}catch(e:any){Alert.alert('Update failed',e.message)}}})).concat([{text:'Cancel',onPress:async()=>{}}]));}
  async function decideQuote(row:Json,decision:'approved'|'rejected'){Alert.alert('Quotation '+row.id,`Confirm ${decision}?`,[{text:'Cancel'}, {text:'Confirm',onPress:async()=>{try{await request(`/quotes/${row.id}/decision`,{method:'POST',body:JSON.stringify({decision})});load('quotes')}catch(e:any){Alert.alert('Error',e.message)}}}]);}
  if(scanField)return <SafeAreaView style={{flex:1,backgroundColor:C.dark}}>
      <View style={{padding:22}}><Text style={styles.brandSmall}>SCAN {scanField.replace(/_/g,' ').toUpperCase()}</Text><Text style={{color:'#B5D1CF',marginTop:9}}>Point the camera at a printed QR code or barcode. Only approved identifier text is copied into the open form.</Text></View>
      <CameraView style={{flex:1}} facing="back" barcodeScannerSettings={{barcodeTypes:['qr','code128','ean13','code39']}} onBarcodeScanned={({data})=>{
        try{const value=cleanScan(scanField,data);setForm(old=>({...old,[scanField]:value}));setScanField(null)}
        catch(e:any){setScanField(null);Alert.alert('Invalid barcode',e.message)}
      }}/>
      <View style={{padding:20}}><Button label="Cancel scanning" secondary onPress={()=>setScanField(null)}/></View>
    </SafeAreaView>;
  if(loading)return <SafeAreaView style={[styles.center,{backgroundColor:C.dark}]}><ActivityIndicator color={C.teal} size="large"/></SafeAreaView>;
  if(!profile)return <SafeAreaView style={styles.login}><ScrollView contentContainerStyle={styles.loginInner}><Text style={styles.brand}>PASH<Text style={{color:C.teal}}> / </Text>AUTO</Text><Text style={styles.kicker}>EV • HYBRID • DSG • AUTOMOTIVE TRAINING</Text><Text style={styles.loginTitle}>Engineering every detail.</Text><Text style={styles.loginSub}>Sign in with your assigned company account. Your role controls access automatically.</Text><View style={styles.loginCard}>{FIXED_ORG?<View><Text style={styles.label}>Company</Text><Text style={styles.explain}>PASH Auto • Secured organization</Text></View>:<Field label="Company ID" value={org} set={setOrg} number/>}<Field label="Email address" value={email} set={setEmail}/><Field label="Password" value={password} set={setPassword} secure/><Button label={busy?'Signing in…':'Sign in securely  ↗'} onPress={login} disabled={busy||!org||!email||!password}/></View><Text style={styles.powered}>POWERED BY DOUBLE GEE TECH</Text></ScrollView></SafeAreaView>;
  const tabs=Object.keys(MENU).filter(allowed);
  const categories:Record<string,string[]>={
    'Overview & service':['dashboard','account','attendance','teamattendance','customers','vehicles','bookings','jobs','inspections','worklogs'],
    'Specialist laboratories':['gearboxreports','batteryreports','qualifications','safetypermits','equipment'],
    'Parts & purchasing':['parts','suppliers','purchaseorders'],
    'Finance & aftercare':['quotes','invoices','expenses','warranties','claims','reviews'],
    'Training academy':['courses','lessons','assessments','enrollments','certificates'],
    'Corporate & communications':['staffusers','fleets','notifications']
  };
  const navLinks=[
    {key:'dashboard',label:'Home',icon:'⌂'},
    ...(allowed('jobs')?[{key:'jobs',label:'Jobs',icon:'⚙'}]:[]),
    ...(allowed('teamattendance')?[{key:'teamattendance',label:'Approvals',icon:'✓'}]:allowed('attendance')?[{key:'attendance',label:'Attendance',icon:'◷'}]:[]),
    ...(allowed('parts')?[{key:'parts',label:'Stock',icon:'▦'}]:allowed('invoices')?[{key:'invoices',label:'Invoices',icon:'▤'}]:[]),
    {key:'more',label:'More',icon:'☰'}
  ];
  const roleLabel=roles.includes('owner')?'CEO':roles.includes('manager')?'Manager':(roles[0]||'Staff').replace(/_/g,' ');
  const initials=profile.name.split(' ').filter(Boolean).slice(0,2).map((x:string)=>x[0].toUpperCase()).join('')||'PA';
  return <SafeAreaView style={styles.root}><StatusBar barStyle="light-content" backgroundColor={C.dark}/>
    <View style={styles.header}>
      <View style={styles.brandLine}>
        <Pressable accessibilityRole="button" accessibilityLabel="Open home" onPress={()=>navigateTo('dashboard')} style={styles.brandHit}>
          <Text style={styles.brandSmall}>PASH<Text style={{color:C.blue}}> / </Text>AUTO</Text>
          <Text style={styles.brandTag}>EV & HYBRID CENTRE  •  OPERATIONS</Text>
        </Pressable>
        <View style={styles.headerActions}>
          {allowed('notifications')?<Pressable accessibilityRole="button" accessibilityLabel="Open notifications" onPress={()=>navigateTo('notifications')} style={styles.headerIcon}><Text style={styles.headerIconText}>◉</Text></Pressable>:null}
          <Pressable accessibilityRole="button" accessibilityLabel="Open account settings" onPress={()=>navigateTo('account')} style={styles.avatar}><Text style={styles.avatarText}>{initials}</Text></Pressable>
        </View>
      </View>
      <View style={styles.headerTitleLine}>
        {showMenu||tab!=='dashboard'?<Pressable accessibilityRole="button" accessibilityLabel="Back to previous screen" onPress={navigateBack} style={styles.backButton}><Text style={styles.backSymbol}>‹</Text></Pressable>:null}
        <View style={{flex:1}}>
          <Text style={styles.headerSub}>{roleLabel.toUpperCase()}  /  {profile.name}</Text>
          <Text style={styles.screenTitle}>{showMenu?'All workspaces':tab==='dashboard'?(roles.includes('owner')?'CEO Dashboard':'My Dashboard'):LABELS[tab]}</Text>
        </View>
      </View>
    </View>
    {showMenu?<ScrollView style={{flex:1}} keyboardShouldPersistTaps="handled" contentContainerStyle={styles.page}>
        <Text style={styles.heading}>Explore your workspaces</Text>
        <Text style={styles.explain}>Every module you are authorized to use, grouped for faster access.</Text>
        <Field label="Search modules" value={menuSearch} set={setMenuSearch}/>
        {Object.entries(categories).map(([group,entries])=>{
          const available=entries.filter(key=>tabs.includes(key)&&LABELS[key].toLowerCase().includes(menuSearch.toLowerCase()));
          if(!available.length)return null;
          return <View key={group} style={styles.moduleGroup}>
            <Text style={styles.sectionHeading}>{group}</Text>
            <View style={styles.workspaceList}>
              {available.map(key=><Pressable key={key} accessibilityRole="button" accessibilityLabel={'Open '+LABELS[key]} style={styles.workspaceRow} onPress={()=>navigateTo(key)}>
                <View style={styles.workspaceIcon}><Text style={styles.workspaceIconText}>{SYMBOLS[key]||'◈'}</Text></View>
                <Text style={styles.workspaceCardTitle}>{LABELS[key]}</Text>
                <Text style={styles.workspaceChevron}>›</Text>
              </Pressable>)}
            </View>
          </View>;
        })}
        <Text style={styles.powered}>POWERED BY DOUBLE GEE TECH</Text>
      </ScrollView>:
    tab==='account'?<ScrollView style={{flex:1}} contentContainerStyle={styles.page}><Text style={styles.heading}>Account & security</Text>
        <Text style={styles.explain}>{profile.name} • {roles.join(' + ')}</Text>
        <View style={styles.card}><Text style={styles.cardTitle}>Change account password</Text><Text style={styles.explain}>For your security, changing your password signs out all devices using this account.</Text>
          <Field label="Current password" secure value={oldPassword} set={setOldPassword}/>
          <Field label="New password (minimum 12 characters)" secure value={newPassword} set={setNewPassword}/>
          <Button label={busy?'Saving…':'Change password'} disabled={busy||!oldPassword||newPassword.length<12} onPress={passwordChange}/>
        </View><Button secondary label="Sign out of all devices" onPress={logout}/>
      </ScrollView>:
    tab==='dashboard'?<ScrollView style={{flex:1}} refreshControl={<RefreshControl refreshing={refreshing} onRefresh={()=>load(tab)}/>} contentContainerStyle={styles.page}>
      <View style={styles.dashboardIntro}>
        <View style={{flex:1}}>
          <Text style={styles.dashboardEyebrow}>PASH AUTO  /  {roleLabel.toUpperCase()} COMMAND CENTRE</Text>
          <Text style={styles.heading}>Welcome, {profile.name.split(' ')[0]}.</Text>
          <Text style={styles.explain}>Your verified business overview, available in one place.</Text>
        </View>
        <View style={styles.liveTag}><View style={styles.liveDot}/><Text style={styles.liveLabel}>LIVE</Text></View>
      </View>
      {error?<View style={styles.error}><Text style={styles.errorText}>{error}</Text><Button secondary label="Retry dashboard" onPress={()=>load(tab)}/></View>:null}
      <Text style={styles.sectionHeading}>LIVE OVERVIEW</Text>
      <View style={styles.grid}>{Object.entries(summary).filter(([k,v])=>typeof v==='number').map(([k,v],index)=>
        <View key={k} style={styles.metric}>
          <View style={[styles.metricIcon,{backgroundColor:index%3===1?'#E8F7F3':index%3===2?'#FFF3E6':C.paleBlue}]}>
            <Text style={[styles.metricIconText,{color:index%3===1?C.teal:index%3===2?'#DA8A29':C.blue}]}>{SYMBOLS[k]||'▣'}</Text>
          </View>
          <Text style={styles.metricValue}>{String(v)}</Text>
          <Text style={styles.metricLabel}>{k.replace(/_/g,' ')}</Text>
        </View>
      )}</View>
      <Text style={[styles.sectionHeading,{marginTop:22}]}>WORKSPACE SHORTCUTS</Text>
      <View style={styles.shortcuts}>
        {['jobs','vehicles','teamattendance','parts','quotes','invoices','staffusers','notifications'].filter(allowed).map(key=>
          <Pressable key={key} accessibilityRole="button" accessibilityLabel={'Open '+LABELS[key]} onPress={()=>navigateTo(key)} style={styles.shortcutRow}>
            <View style={styles.shortcutIcon}><Text style={styles.shortcutIconText}>{SYMBOLS[key]||'▣'}</Text></View>
            <Text style={styles.shortcutLabel}>{LABELS[key]}</Text><Text style={styles.workspaceChevron}>›</Text>
          </Pressable>
        )}
        <Pressable accessibilityRole="button" onPress={openWorkspaces} style={styles.shortcutRow}>
          <View style={styles.shortcutIcon}><Text style={styles.shortcutIconText}>☰</Text></View>
          <Text style={styles.shortcutLabel}>All workspaces</Text><Text style={styles.workspaceChevron}>›</Text>
        </Pressable>
      </View>
      <View style={styles.roleCard}>
        <Text style={styles.roleCardTitle}>SECURE BUSINESS ACCESS</Text>
        <Text style={styles.roleCardText}>Signed in as {roleLabel}. Your roles and permissions remain enforced by the ERP server.</Text>
        <Pressable onPress={()=>navigateTo('account')} accessibilityRole="button"><Text style={styles.linkText}>Account & security  ›</Text></Pressable>
      </View>
    </ScrollView>:
    <FlatList style={{flex:1}} contentContainerStyle={styles.page} data={rows} keyExtractor={(item,index)=>String(item.id||index)} refreshControl={<RefreshControl refreshing={refreshing} onRefresh={()=>load(tab)}/>}
      ListHeaderComponent={<>
        <Text style={styles.heading}>{LABELS[tab]}</Text><Text style={styles.explain}>{rows.length} authorized record(s) • Pull down to refresh.</Text>
        {error?<View style={styles.error}><Text style={styles.errorText}>{error}</Text><Button secondary label="Try again" onPress={()=>load(tab)}/></View>:null}
        {tab==='attendance'?<View style={styles.card}><Text style={styles.cardTitle}>Attendance clock</Text><Text style={styles.explain}>Actual check-in time is recorded by the server. Manager/CEO approval is required before hours count as payable. Only one shift may be open.</Text><Field label="Unpaid break minutes (used at clock-out)" number value={unpaidBreakMinutes} set={setUnpaidBreakMinutes}/><View style={styles.actionRow}><Button label="Clock in" disabled={busy} onPress={()=>attendanceAction('clock-in')}/><Button secondary label="Clock out" disabled={busy} onPress={()=>attendanceAction('clock-out')}/></View></View>:null}
        {CREATE[tab]&&roles.some(r=>r==='owner'||CREATE[tab].roles.includes(r))?<View style={styles.card}><Button secondary label={compose?'Close entry form':'＋ Add '+LABELS[tab]} onPress={()=>{setCompose(!compose);setAction(null)}}/>
          {DRAFT_SCREENS.has(tab)?<View style={styles.actionRow}><Button secondary label="Save encrypted draft" onPress={saveDraft}/><Button secondary label="Restore draft" onPress={restoreDraft}/></View>:null}
          {compose?<View style={{marginTop:13}}>{CREATE[tab].fields.map(([key,label,kind])=><View key={key}>{kind==='boolean'?<View style={styles.booleanField}><Text style={[styles.label,{flex:1}]}>{label}</Text><Switch accessibilityLabel={label} value={form[key]==='true'} onValueChange={v=>setForm(old=>({...old,[key]:v?'true':'false'}))} trackColor={{true:C.teal}}/></View>:<Field label={label} value={String(form[key]??'')} set={value=>setForm(old=>({...old,[key]:value}))} number={kind==='number'} secure={key==='password'} multiline={['additional_lines','body','description','notes','test_results','complaint'].includes(key)}/>} {['vin','sku','serial','battery_serial','job_id','vehicle_id','part_id'].includes(key)?<Button secondary label={'▣  Scan '+label} onPress={()=>openScanner(key)}/>:null}</View>)}<Button label={busy?'Saving…':'Save record'} disabled={busy} onPress={createRecord}/></View>:null}
        </View>:null}
      </>}
      ListEmptyComponent={<View style={styles.card}><Text style={styles.explain}>{error?'Unable to load records.':'No records available yet.'}</Text></View>}
      renderItem={({item})=><View style={styles.card}>
        <View style={styles.itemHeading}><Text style={styles.cardTitle}>{tab==='vehicles'?item.registration:tab==='parts'||tab==='suppliers'||tab==='equipment'?item.name:tab==='courses'||tab==='lessons'||tab==='assessments'?item.title:tab==='bookings'?item.service:`${LABELS[tab]} #${item.id}`}</Text><Text style={styles.pill}>{tab==='jobs'?STATUS_LABEL[item.status]||item.status:(tab==='attendance'||tab==='teamattendance'?item.approval_status:item.status)||''}</Text></View>
        {(SHOW[tab]||[]).filter(k=>k!=='id').map(k=><View key={k} style={styles.row}><Text style={styles.key}>{k.replace(/_/g,' ')}</Text><Text style={styles.value}>{Array.isArray(item[k])?JSON.stringify(item[k]):typeof item[k]==='object'&&item[k]!==null?JSON.stringify(item[k]):String(item[k]??'—')}</Text></View>)}
        {tab==='teamattendance'&&item.approval_status==='pending'&&roles.some(r=>['owner','manager'].includes(r))?<View style={styles.actionRow}><Button label="Approve check-in" disabled={busy} onPress={()=>{setAction({name:'attendance_approve',id:item.id});setActionForm({note:''})}}/><Button secondary label="Reject" disabled={busy} onPress={()=>{setAction({name:'attendance_reject',id:item.id});setActionForm({note:''})}}/></View>:null}
        {tab==='jobs'&&(roles.some(r=>['owner','manager','service_advisor'].includes(r))||item.assigned_to===profile.id)?<><Button secondary label="Update repair stage" onPress={()=>updateJob(item)}/><View style={styles.actionRow}><Button secondary label="Record labor" onPress={()=>openForm('worklogs',{job_id:item.id})}/><Button secondary label="Inspection" onPress={()=>openForm('inspections',{job_id:item.id})}/></View><View style={styles.actionRow}><Button secondary disabled={busy} label="📷 Photo evidence" onPress={()=>captureJobEvidence(item)}/><Button secondary label="Evidence history" onPress={()=>viewJobEvidence(item)}/></View>{item.category==='dsg'&&allowed('gearboxreports')?<Button secondary label="DSG report" onPress={()=>openForm('gearboxreports',{job_id:item.id})}/>:null}{item.category==='battery'&&allowed('batteryreports')?<Button secondary label="Battery report" onPress={()=>openForm('batteryreports',{job_id:item.id})}/>:null}</>:null}
        {tab==='courses'&&!item.published&&roles.some(r=>['owner','manager','instructor'].includes(r))?<Button secondary label="Publish course" onPress={()=>setAction({name:'publish_course',id:item.id})}/>:null}
        {tab==='lessons'&&!item.published&&roles.some(r=>['owner','manager','instructor'].includes(r))?<Button secondary label="Publish lesson" onPress={()=>setAction({name:'publish_lesson',id:item.id})}/>:null}
        {tab==='assessments'&&!item.published&&roles.some(r=>['owner','manager','instructor'].includes(r))?<Button secondary label="Publish examination" onPress={()=>setAction({name:'publish_exam',id:item.id})}/>:null}
        {tab==='assessments'&&item.published&&roles.includes('student')?<Button secondary label="Attempt examination" onPress={()=>{setAction({name:'attempt_exam',id:item.id});setActionForm({answers:[]})}}/>:null}
        {tab==='purchaseorders'&&item.status==='draft'&&roles.some(r=>['owner','manager','inventory'].includes(r))?<Button secondary label="Receive ordered stock" onPress={()=>setAction({name:'receive_order',id:item.id})}/>:null}
        {tab==='quotes'&&item.status==='approved'&&roles.some(r=>['owner','manager','accountant'].includes(r))?<Button secondary label="Generate invoice" onPress={()=>setAction({name:'invoice_quote',id:item.id})}/>:null}
        {tab==='parts'&&roles.some(r=>['owner','manager','inventory'].includes(r))?<Button secondary label="Issue parts to a job" onPress={()=>{setAction({name:'issue_part',id:item.id});setActionForm({})}}/>:null}
        {tab==='invoices'&&roles.some(r=>['owner','manager','accountant'].includes(r))&&Number(item.paid)<Number(item.total)?<Button secondary label="Record verified payment" onPress={()=>{setAction({name:'record_payment',id:item.id});setActionForm({method:'cash'})}}/>:null}
        {tab==='enrollments'&&roles.some(r=>['owner','manager','instructor'].includes(r))&&item.status!=='completed'?<Button secondary label="Mark course completed (requires passed exam)" onPress={()=>setAction({name:'complete_enrollment',id:item.id})}/>:null}
        {tab==='certificates'&&roles.some(r=>['owner','manager','instructor'].includes(r))&&!item.revoked?<Button secondary label="Revoke certificate" onPress={()=>setAction({name:'revoke_certificate',id:item.id})}/>:null}
        {tab==='equipment'&&roles.some(r=>['owner','manager','inventory'].includes(r))?<Button secondary label="Change equipment status" onPress={()=>{setAction({name:'set_equipment',id:item.id});setActionForm({status:item.status})}}/>:null}
        {tab==='notifications'&&!item.read?<Button secondary label="Mark as read" onPress={async()=>{try{await request(`/notifications/${item.id}/read`,{method:'PATCH'});load(tab);}catch(e:any){Alert.alert('Error',e.message)}}}/>:null}
        {tab==='quotes'&&item.status==='pending'&&roles.includes('customer')?<View style={styles.actionRow}><Button label="Approve quote" onPress={()=>decideQuote(item,'approved')}/><Button secondary label="Reject" onPress={()=>decideQuote(item,'rejected')}/></View>:null}
        {action && action.id===item.id?<View style={styles.actionPanel}><Text style={styles.cardTitle}>{action.name.replace(/_/g,' ').toUpperCase()}</Text><Text style={styles.explain}>Verify this action before submitting. It will update live database records.</Text>
           {action.name==='attempt_exam'?(item.questions||[]).map((q:any,index:number)=><View key={index} style={styles.card}><Text style={styles.cardTitle}>{index+1}. {q.prompt}</Text>{q.choices.map((choice:string,ix:number)=><Pressable key={ix} accessibilityRole="button" onPress={()=>{const a=[...(actionForm.answers||[])];a[index]=ix;setActionForm({...actionForm,answers:a})}} style={[styles.row,actionForm.answers?.[index]===ix?{backgroundColor:'#D8F3E8',borderRadius:6}:null]}><Text style={styles.value}>{String.fromCharCode(65+ix)}. {choice}</Text></Pressable>)}</View>):null}
           {action.name.startsWith('attendance_')?<Field label={action.name==='attendance_reject'?'Rejection reason (required)':'Approval note (optional)'} value={String(actionForm.note||'')} set={v=>setActionForm({...actionForm,note:v})} multiline/>:null}
           {action.name==='issue_part'?<><Field label="Job ID" number value={String(actionForm.job_id||'')} set={v=>setActionForm({...actionForm,job_id:v})}/><Field label="Quantity" number value={String(actionForm.quantity||'')} set={v=>setActionForm({...actionForm,quantity:v})}/></>:null}
           {action.name==='record_payment'?<><Field label="Actual amount received" number value={String(actionForm.amount||'')} set={v=>setActionForm({...actionForm,amount:v})}/><Field label="Method: cash / card / bank / mobile_money" value={String(actionForm.method||'cash')} set={v=>setActionForm({...actionForm,method:v})}/></>:null}
           {action.name==='set_equipment'?<Field label="Status: available / in_use / maintenance / quarantined / retired" value={String(actionForm.status||'')} set={v=>setActionForm({...actionForm,status:v})}/>:null}
           {action.name==='close_claim'?<><Field label="Status" value={String(actionForm.status||'')} set={v=>setActionForm({...actionForm,status:v})}/><Field label="Resolution" value={String(actionForm.resolution||'')} set={v=>setActionForm({...actionForm,resolution:v})}/></>:null}
           <View style={styles.actionRow}><Button disabled={busy} label="Confirm action" onPress={performAction}/><Button secondary label="Cancel" onPress={()=>{setAction(null);setActionForm({})}}/></View>
        </View>:null}
      </View>}
    />}
    <View style={styles.bottomNav}>
      {navLinks.map(item=>{
        const active=showMenu?item.key==='more':tab===item.key;
        return <Pressable key={item.key} accessibilityRole="button" accessibilityLabel={item.label} accessibilityState={{selected:active}} onPress={()=>item.key==='more'?openWorkspaces():navigateTo(item.key)} style={styles.bottomItem}>
          <Text style={[styles.bottomIcon,active?styles.bottomActiveText:null]}>{item.icon}</Text>
          <Text style={[styles.bottomLabel,active?styles.bottomActiveText:null]}>{item.label}</Text>
          {active?<View style={styles.bottomActiveDot}/>:null}
        </Pressable>;
      })}
    </View>
  </SafeAreaView>;
}
/**
 * Visible fallback for recoverable React rendering failures.
 * This cannot handle a native crash; the Android emulator/logcat smoke test
 * covers that separately. Never log tokens, passwords or customer data.
 */
class OperationsErrorBoundary extends React.Component<{children:React.ReactNode},{failed:boolean,reset:number}> {
  constructor(props:{children:React.ReactNode}){
    super(props);
    this.state={failed:false,reset:0};
  }
  static getDerivedStateFromError(){return {failed:true};}
  componentDidCatch(error:Error){
    console.error('PASH_OPERATIONS_RENDER_FAILURE', error.name);
  }
  render(){
    if(!this.state.failed)return this.props.children;
    return <SafeAreaView style={{flex:1,backgroundColor:'#101A25',justifyContent:'center',padding:26}}>
      <Text style={{fontSize:28,fontWeight:'900',color:'#FFFFFF'}}>PASH / AUTO</Text>
      <Text style={{fontSize:23,fontWeight:'800',color:'#FFFFFF',marginTop:32}}>We couldn't open this workspace</Text>
      <Text style={{color:'#B8C9CF',marginTop:14,lineHeight:22}}>Your server data has not been changed. Restart the workspace without clearing the app's saved data.</Text>
      <Pressable accessibilityRole="button" onPress={()=>this.setState(old=>({failed:false,reset:old.reset+1}))}
        style={{backgroundColor:'#159E86',padding:16,borderRadius:12,marginTop:28}}>
        <Text style={{color:'#FFFFFF',fontWeight:'800',textAlign:'center'}}>TRY AGAIN</Text>
      </Pressable>
      <Text style={{color:'#9DB5BE',fontSize:12,marginTop:20}}>Error code: PASH-RENDER-01. Report this screen if it repeats.</Text>
    </SafeAreaView>;
  }
}

export default function App(){
  return <OperationsErrorBoundary><OperationsApp /></OperationsErrorBoundary>;
}

const styles=StyleSheet.create({
  root:{flex:1,backgroundColor:C.bg},
  center:{flex:1,alignItems:'center',justifyContent:'center'},
  // Precision-brand header, based on approved CEO and worker dashboard references.
  header:{backgroundColor:C.dark,paddingHorizontal:19,paddingTop:12,paddingBottom:16,borderBottomWidth:2,borderBottomColor:'#164277'},
  brandLine:{flexDirection:'row',alignItems:'center',justifyContent:'space-between'},
  brandHit:{flex:1,paddingVertical:4},
  brandSmall:{fontSize:23,fontWeight:'900',color:C.white,letterSpacing:-1},
  brandTag:{fontSize:8,fontWeight:'700',color:'#90ABC0',letterSpacing:1.05,marginTop:2},
  headerActions:{flexDirection:'row',alignItems:'center',gap:11},
  headerIcon:{width:34,height:34,borderRadius:11,justifyContent:'center',alignItems:'center',backgroundColor:'#152E4B'},
  headerIconText:{fontSize:20,fontWeight:'700',color:'#D8E8FA'},
  avatar:{width:37,height:37,borderRadius:19,backgroundColor:C.blue,alignItems:'center',justifyContent:'center',borderColor:'#527FB3',borderWidth:1},
  avatarText:{fontWeight:'900',fontSize:12,color:C.white},
  headerTitleLine:{flexDirection:'row',alignItems:'center',gap:12,marginTop:15},
  headerSub:{fontSize:9,fontWeight:'700',color:'#9EB3C7',letterSpacing:1.3,marginBottom:3},
  screenTitle:{color:C.white,fontWeight:'900',fontSize:23,letterSpacing:-0.75},
  backButton:{width:37,height:39,borderRadius:11,borderWidth:1,borderColor:'#284967',alignItems:'center',justifyContent:'center'},
  backSymbol:{color:C.white,fontSize:31,lineHeight:35,fontWeight:'500'},
  page:{paddingHorizontal:17,paddingTop:20,paddingBottom:38},
  heading:{fontSize:23,color:C.dark,fontWeight:'900',letterSpacing:-0.6},
  explain:{fontSize:12.5,color:C.muted,lineHeight:19,marginTop:7,marginBottom:16},
  sectionHeading:{fontSize:10.5,letterSpacing:1.4,color:'#60768A',fontWeight:'900',marginBottom:12,marginTop:12,textTransform:'uppercase'},
  // Grouped module list replaces oversized workspace tiles.
  moduleGroup:{marginBottom:15},
  workspaceList:{backgroundColor:C.white,borderColor:C.line,borderWidth:1,borderRadius:16,overflow:'hidden'},
  workspaceRow:{minHeight:62,flexDirection:'row',alignItems:'center',gap:12,paddingHorizontal:15,paddingVertical:10,borderBottomWidth:0.65,borderBottomColor:C.line},
  workspaceIcon:{width:38,height:38,borderRadius:11,backgroundColor:C.paleBlue,alignItems:'center',justifyContent:'center'},
  workspaceIconText:{fontSize:19,fontWeight:'800',color:C.blue},
  workspaceCardTitle:{flex:1,fontSize:14,color:C.dark,fontWeight:'800',letterSpacing:-0.15},
  workspaceChevron:{fontSize:25,fontWeight:'300',color:'#8FA4B7',marginLeft:3},
  // Executive overview: actual data only, no invented KPI values.
  dashboardIntro:{flexDirection:'row',alignItems:'flex-start',gap:7,marginBottom:8},
  dashboardEyebrow:{fontSize:9,fontWeight:'800',color:C.blue,letterSpacing:1.05,marginBottom:8},
  liveTag:{flexDirection:'row',alignItems:'center',gap:5,paddingHorizontal:10,paddingVertical:7,borderColor:'#C5EADB',borderWidth:1,borderRadius:18,backgroundColor:'#E8F8F1'},
  liveDot:{width:6,height:6,borderRadius:3,backgroundColor:C.teal},
  liveLabel:{color:'#178B70',fontWeight:'900',fontSize:9,letterSpacing:.8},
  grid:{flexDirection:'row',flexWrap:'wrap',gap:11,marginBottom:10},
  metric:{width:'47.5%',minHeight:135,backgroundColor:C.white,borderColor:C.line,borderWidth:1,borderRadius:15,padding:15,justifyContent:'space-between'},
  metricIcon:{height:31,width:34,borderRadius:8,alignItems:'center',justifyContent:'center',marginBottom:10},
  metricIconText:{fontSize:18,fontWeight:'800'},
  metricValue:{fontSize:28,color:C.dark,fontWeight:'900',letterSpacing:-0.8},
  metricLabel:{fontSize:10,color:'#6C8093',fontWeight:'700',textTransform:'capitalize',marginTop:3},
  shortcuts:{borderRadius:16,borderWidth:1,borderColor:C.line,backgroundColor:C.white,overflow:'hidden'},
  shortcutRow:{minHeight:59,flexDirection:'row',alignItems:'center',gap:12,paddingHorizontal:15,borderBottomWidth:0.65,borderBottomColor:C.line},
  shortcutIcon:{width:34,height:34,borderRadius:9,backgroundColor:C.paleBlue,alignItems:'center',justifyContent:'center'},
  shortcutIconText:{fontSize:18,color:C.blue,fontWeight:'800'},
  shortcutLabel:{flex:1,fontSize:13,color:C.dark,fontWeight:'800'},
  roleCard:{marginTop:23,backgroundColor:'#0F2743',borderRadius:17,padding:19},
  roleCardTitle:{fontSize:10,color:'#6DCBF0',fontWeight:'900',letterSpacing:1.15},
  roleCardText:{fontSize:12,color:'#D0DDEC',lineHeight:20,marginTop:9,marginBottom:14},
  linkText:{fontSize:12,color:'#84B5FF',fontWeight:'800'},
  // Consistent forms and record surfaces throughout every existing ERP module.
  card:{backgroundColor:C.white,borderRadius:16,borderWidth:1,borderColor:C.line,padding:16,marginTop:12},
  cardTitle:{fontSize:15,color:C.dark,fontWeight:'900',letterSpacing:-0.25,flex:1},
  itemHeading:{flexDirection:'row',gap:8,alignItems:'flex-start',marginBottom:13},
  pill:{backgroundColor:'#E7F6F0',borderRadius:7,overflow:'hidden',color:'#12836D',fontSize:10,fontWeight:'800',paddingHorizontal:8,paddingVertical:6,maxWidth:'45%'},
  row:{flexDirection:'row',alignItems:'flex-start',justifyContent:'space-between',gap:15,paddingVertical:9,borderBottomWidth:.65,borderBottomColor:'#EDF2F6'},
  key:{color:'#778B9A',fontSize:11,textTransform:'capitalize',flex:1},
  value:{fontSize:11.2,fontWeight:'700',color:'#17314B',textAlign:'right',flex:1.15},
  field:{marginBottom:10},
  label:{fontSize:12,fontWeight:'800',color:'#1C344B',marginBottom:9},
  input:{height:48,backgroundColor:'#F9FBFE',borderColor:'#D8E3EC',borderWidth:1,borderRadius:11,paddingHorizontal:14,color:C.dark,fontSize:14},
  button:{minHeight:46,flex:1,backgroundColor:C.blue,borderRadius:11,alignItems:'center',justifyContent:'center',paddingHorizontal:12,paddingVertical:12,marginTop:8},
  secondary:{backgroundColor:C.white,borderColor:'#C8D8E8',borderWidth:1},
  buttonText:{fontWeight:'800',fontSize:12.5,color:C.white,textAlign:'center'},
  actionRow:{flexDirection:'row',flexWrap:'wrap',gap:8,marginTop:11},
  actionPanel:{backgroundColor:'#F1F7FF',borderRadius:13,padding:14,marginTop:14},
  error:{backgroundColor:'#FFF0EE',borderWidth:1,borderColor:'#F3C6C1',padding:13,borderRadius:12,marginBottom:14},
  errorText:{color:'#B43737',fontSize:12,lineHeight:19},
  booleanField:{flexDirection:'row',alignItems:'center',justifyContent:'space-between',paddingVertical:13,paddingHorizontal:8,borderBottomWidth:1,borderBottomColor:C.line},
  // Compact fixed bottom navigation, rather than a persistent Sign Out footer.
  bottomNav:{minHeight:61,backgroundColor:C.dark,flexDirection:'row',justifyContent:'space-around',alignItems:'stretch',paddingHorizontal:4,borderTopWidth:1,borderTopColor:'#26415F'},
  bottomItem:{flex:1,justifyContent:'center',alignItems:'center',paddingHorizontal:2,paddingVertical:5},
  bottomIcon:{color:'#839DB8',fontSize:21,fontWeight:'700',height:25},
  bottomLabel:{fontSize:9,color:'#91A4B8',fontWeight:'700',marginTop:2},
  bottomActiveText:{color:'#4B9BFF'},
  bottomActiveDot:{height:3,width:18,borderRadius:2,backgroundColor:C.blue,marginTop:4},
  // Login keeps the same secure login flow with refreshed typography.
  login:{flex:1,backgroundColor:C.dark},
  loginInner:{flexGrow:1,padding:25,paddingTop:64},
  brand:{color:C.white,fontSize:36,fontWeight:'900',letterSpacing:-1.6},
  kicker:{fontSize:9,color:'#90ACC2',fontWeight:'700',letterSpacing:1.4,marginTop:9},
  loginTitle:{fontSize:36,lineHeight:43,fontWeight:'900',color:C.white,marginTop:72,letterSpacing:-1.4},
  loginSub:{fontSize:14,color:'#9DADBB',lineHeight:24,marginTop:13,marginBottom:28},
  loginCard:{backgroundColor:C.white,padding:23,borderRadius:20,gap:12},
  powered:{color:'#8293A6',fontWeight:'800',fontSize:9,letterSpacing:1.7,marginTop:25,marginBottom:10,textAlign:'center'},
  // Legacy style names retained for compatibility with non-navigation screens.
  workspaceGrid:{flexDirection:'row',flexWrap:'wrap',gap:10},
  workspaceCard:{backgroundColor:C.white,borderRadius:14,padding:15},
  workspaceCaption:{color:C.blue,fontSize:10,fontWeight:'800'},
  tabs:{maxHeight:53,backgroundColor:C.white},
  tabInner:{flexDirection:'row',paddingHorizontal:13},
  tab:{padding:10},
  activeTab:{backgroundColor:C.paleBlue},
  tabText:{color:C.muted},
  activeTabText:{color:C.blue},
  menuButton:{padding:8},
  menuText:{color:C.white},
  inline:{flexDirection:'row',gap:9,marginTop:12},
  bottom:{backgroundColor:C.dark,padding:12},
  bottomText:{fontSize:9,color:'#9BB1C6'},
  logout:{color:C.gold,fontSize:10,fontWeight:'900'}
});
