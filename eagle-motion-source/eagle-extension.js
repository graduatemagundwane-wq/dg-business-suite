
/* Eagle Construction: motion layer — menu, blueprint loader, scroll and subpage transitions only */
let eagleAnimationContext=null,eagleMotionLibrariesRequested=false,eagleMotionReady=false,eagleInitialLoaderStarted=false,eagleTransitionBusy=false,eagleSmoothScroll=null,eagleProgressInstalled=false;
const eagleReduceMotion=()=>window.matchMedia('(prefers-reduced-motion: reduce)').matches;

function eagleInitMenu(){
 const nav=document.getElementById('mobile-nav'),toggle=document.getElementById('menu-toggle');if(!nav||!toggle)return;
 nav.className='eagle-menu';
 const sub={'/':'THE WELCOME','/about':'OUR STORY','/services':'WHAT WE DO','/projects':'PROJECT AREAS','/request-a-quote':'START YOUR BUILD','/contact':'GET IN TOUCH'};
 nav.innerHTML='<button type="button" id="eagle-menu-close" class="eagle-menu-close" aria-label="Close navigation"><span aria-hidden="true">×</span> CLOSE</button>'+
 '<div class="eagle-menu-main"><span class="eagle-menu-tag">EAGLE / SITE INDEX</span><div class="eagle-menu-list">'+
 navItems.map(([path,label],i)=>'<a class="eagle-menu-link'+(page===path?' is-current':'')+'" href="'+path+'"'+(page===path?' aria-current="page"':'')+'><span class="eagle-menu-no">0'+(i+1)+'</span><span class="eagle-menu-name">'+label+'</span></a>').join('')+
 '</div><span class="eagle-menu-foot">BUILD · RENOVATE · IMPROVE</span></div>'+
 '<div class="eagle-menu-side"><div class="eagle-menu-emblem"><img src="/assets/eagle-head.png" alt="" /></div><span class="eagle-menu-side-tag" id="eagle-menu-preview">'+(sub[page]||'EXPLORE OUR WORK')+'</span><h3>Building spaces.<br>Creating futures.</h3><p>Expertise, craftsmanship and clear communication — every step of the way.</p><a class="eagle-menu-side-contact" href="tel:+'+PHONE_DIGITS+'">Talk to our team ↗</a></div>';
 toggle.innerHTML='<span class="eagle-toggle-label">Explore</span><span class="eagle-toggle-lines" aria-hidden="true"><i></i></span>';
 toggle.setAttribute('aria-label','Open site navigation');toggle.setAttribute('aria-controls','mobile-nav');
 nav.querySelector('#eagle-menu-close').addEventListener('click',e=>{e.preventDefault();eagleCloseMenu();});
 nav.addEventListener('pointerover',e=>{const link=e.target.closest('.eagle-menu-link'),preview=document.getElementById('eagle-menu-preview');if(link&&preview)preview.textContent=sub[link.getAttribute('href')]||'EXPLORE OUR WORK';});
 toggle.addEventListener('click',()=>window.setTimeout(()=>{if(menuOpen)nav.querySelector('.eagle-menu-link')?.focus({preventScroll:true});},0));
}
function eagleCloseMenu(){
 const nav=document.getElementById('mobile-nav'),toggle=document.getElementById('menu-toggle');
 menuOpen=false;nav?.classList.remove('shown');toggle?.setAttribute('aria-expanded','false');document.body.classList.remove('menu-open');toggle?.focus({preventScroll:true});
}
function eagleShouldTransition(destination){
 if(eagleReduceMotion()||eagleTransitionBusy)return false;
 const next=new URL(destination,window.location.href).pathname.replace(/\/$/,'')||'/';
 return next!=='/'&&next!==page;
}
function eagleTransition(action,destination){
 const curtain=document.getElementById('eagle-curtain');if(!curtain||eagleReduceMotion()){action();return;}
 eagleTransitionBusy=true;
 const names={'/about':'ABOUT US','/services':'OUR SERVICES','/projects':'OUR PROJECTS','/request-a-quote':'REQUEST A QUOTE','/contact':'CONTACT','/admin':'ADMINISTRATION'};
 const path=new URL(destination||window.location.href,window.location.href).pathname.replace(/\/$/,'')||'/';
 const label=curtain.querySelector('.eagle-curtain-word');if(label)label.textContent=names[path]||'EAGLE CONSTRUCTION';
 curtain.className='eagle-curtain';void curtain.offsetHeight;curtain.classList.add('is-in');
 window.setTimeout(()=>{try{action();}finally{
   curtain.classList.remove('is-in');curtain.classList.add('is-out');
   window.setTimeout(()=>{curtain.className='eagle-curtain';eagleTransitionBusy=false;},620);
 }},510);
}
function eagleProgressUpdate(){
 const bar=document.getElementById('eagle-progress');if(!bar)return;
 const limit=Math.max(1,document.documentElement.scrollHeight-window.innerHeight);
 bar.style.transform='scaleX('+Math.max(0,Math.min(1,window.scrollY/limit))+')';
}
function eagleInitProgress(){
 if(eagleProgressInstalled)return;eagleProgressInstalled=true;
 window.addEventListener('scroll',eagleProgressUpdate,{passive:true});
 window.addEventListener('resize',eagleProgressUpdate,{passive:true});
}
function eagleLoadScript(src){
 return new Promise((resolve,reject)=>{const s=document.createElement('script');s.src=src;s.async=true;s.onload=resolve;s.onerror=()=>reject(new Error('Animation CDN unavailable'));document.head.appendChild(s);});
}
function eagleLoadMotionLibraries(){
 if(eagleMotionLibrariesRequested||eagleReduceMotion())return;eagleMotionLibrariesRequested=true;
 eagleLoadScript('/assets/vendor/gsap.min.js')
 .then(()=>eagleLoadScript('/assets/vendor/ScrollTrigger.min.js'))
 .then(()=>{if(!window.gsap||!window.ScrollTrigger)return;window.gsap.registerPlugin(window.ScrollTrigger);eagleMotionReady=true;eagleAnimatePage();})
 .catch(()=>eagleFallbackReveal());
 if(window.matchMedia('(min-width: 951px) and (hover: hover) and (pointer: fine)').matches)
   eagleLoadScript('/assets/vendor/lenis.min.js').then(()=>{
     if(!window.Lenis||eagleSmoothScroll||eagleReduceMotion())return;
     eagleSmoothScroll=new window.Lenis({autoRaf:true,duration:1.12,smoothWheel:true,wheelMultiplier:.88});
     if(window.ScrollTrigger)eagleSmoothScroll.on('scroll',()=>window.ScrollTrigger.update());
   }).catch(()=>{});
}
function eagleSplitWords(element){
 if(!element||element.dataset.eagleSplit==='1')return;element.dataset.eagleSplit='1';
 const walker=document.createTreeWalker(element,NodeFilter.SHOW_TEXT),nodes=[];while(walker.nextNode())nodes.push(walker.currentNode);
 nodes.forEach(node=>{if(!node.nodeValue.trim())return;const frag=document.createDocumentFragment();
   node.nodeValue.split(/(\s+)/).forEach(token=>{if(!token)return;
     if(/^\s+$/.test(token)){frag.appendChild(document.createTextNode(token));return;}
     const el=document.createElement('span');el.className='eagle-kinetic-word';el.textContent=token;frag.appendChild(el);
   });node.replaceWith(frag);
 });
}
function eagleFallbackReveal(){
 if(eagleMotionReady||eagleReduceMotion()||!('IntersectionObserver' in window))return;
 const nodes=document.querySelectorAll('.service-card,.project-photo,.special-card,.process-step,.quote-banner,.visit-banner');
 const io=new IntersectionObserver(entries=>entries.forEach(e=>{if(e.isIntersecting){e.target.classList.add('eagle-fallback-show');io.unobserve(e.target);}}),{threshold:.06,rootMargin:'0px 0px -3% 0px'});
 nodes.forEach(n=>{n.classList.add('eagle-fallback-hide');io.observe(n);});
}
function eagleAnimatePage(){
 if(!eagleMotionReady||eagleReduceMotion()||!document.querySelector('#main'))return;
 if(eagleAnimationContext){eagleAnimationContext.revert();eagleAnimationContext=null;}
 const gsap=window.gsap,Trigger=window.ScrollTrigger;
 eagleAnimationContext=gsap.context(()=>{
   document.querySelectorAll('.hero h1,.section-heading h2,.intro-grid h2,.section-split h2,.people-copy h2,.benefits-grid h2,.heading-row h2').forEach(eagleSplitWords);
   document.querySelectorAll('.hero h1').forEach(h=>{
     gsap.from(h.querySelectorAll('.eagle-kinetic-word'),{yPercent:95,rotationX:50,opacity:0,stagger:.064,duration:.96,ease:'back.out(1.65)',clearProps:'all',delay:.13});
   });
   document.querySelectorAll('.section-heading h2,.intro-grid h2,.section-split h2,.people-copy h2,.benefits-grid h2,.heading-row h2').forEach((h,i)=>{
     const words=h.querySelectorAll('.eagle-kinetic-word');if(!words.length)return;
     gsap.from(words,{yPercent:104,rotationX:45,opacity:0,stagger:.04,duration:.78,ease:'back.out(1.5)',clearProps:'all',scrollTrigger:{trigger:h,start:'top 88%',once:true,id:'eagle-h-'+i}});
   });
   ['.service-cards','.project-gallery','.project-page-grid','.special-grid','.process-steps','.values-grid'].forEach((sel,g)=>{
     document.querySelectorAll(sel).forEach((box,i)=>{const children=[...box.children].filter(el=>!el.classList.contains('step-arrow'));if(!children.length)return;
       gsap.from(children,{y:52,opacity:.05,rotationX:8,stagger:.105,duration:.91,ease:'power3.out',clearProps:'all',scrollTrigger:{trigger:box,start:'top 89%',once:true,id:'eagle-group-'+g+'-'+i}});
     });
   });
   document.querySelectorAll('.quote-banner,.visit-banner,.people-section,.contact-information,.benefits').forEach((el,i)=>{
     gsap.from(el,{y:33,opacity:.18,duration:1.1,ease:'power2.out',clearProps:'all',scrollTrigger:{trigger:el,start:'top 90%',once:true,id:'eagle-section-'+i}});
   });
   document.querySelectorAll('.hero-image').forEach(el=>gsap.fromTo(el,{yPercent:-2},{yPercent:7,ease:'none',scrollTrigger:{trigger:el.closest('.hero'),start:'top top',end:'bottom top',scrub:.9,id:'eagle-hero-parallax'}}));
   document.querySelectorAll('.service-photo img,.project-photo img').forEach((el,i)=>gsap.fromTo(el,{scale:1.05,yPercent:-2},{scale:1.08,yPercent:2,ease:'none',scrollTrigger:{trigger:el.closest('.service-photo,.project-photo'),start:'top bottom',end:'bottom top',scrub:1.1,id:'eagle-photo-'+i}}));
   document.querySelectorAll('.eyebrow').forEach((el,i)=>gsap.from(el,{x:-12,opacity:.25,duration:.68,ease:'power2.out',clearProps:'all',scrollTrigger:{trigger:el,start:'top 94%',once:true,id:'eagle-kicker-'+i}}));
 },document.querySelector('#app'));
 window.requestAnimationFrame(()=>{Trigger.refresh();eagleProgressUpdate();});
}
function eagleAfterRender(){
 eagleInitProgress();eagleProgressUpdate();
 if(!eagleInitialLoaderStarted){
   eagleInitialLoaderStarted=true;const loader=document.getElementById('eagle-opening');
   if(loader){window.setTimeout(()=>loader.classList.add('is-done'),1350);window.setTimeout(()=>loader.remove(),2300);}
 }
 if(eagleSmoothScroll){eagleSmoothScroll.resize();if(!window.location.hash)eagleSmoothScroll.scrollTo(0,{immediate:true});}
 if(eagleMotionReady)eagleAnimatePage();else eagleLoadMotionLibraries();
}
