'use strict';
// Keep the original Yola client bundle byte-for-byte. Load the customer-specific
// enhancements after it, preserving every existing UI component and CSS file.
(function(){
 const safety=document.createElement('style');
 safety.id='sargo-nav-init-guard';
 safety.textContent='#sidebar-nav {visibility:hidden}';
 document.head.appendChild(safety);
 const original=document.createElement('script');
 original.src='/pos-original.js';
 original.async=false;
 original.onload=function(){
   const extension=document.createElement('script');
   extension.src='/sargo-enhancements.js';
   extension.async=false;
   extension.onload=function(){safety.remove()};
   extension.onerror=function(){safety.remove();console.error('Yola extension did not load')};
   document.head.appendChild(extension);
 };
 original.onerror=function(){
   safety.remove();
   const box=document.getElementById('body');
   if(box)box.textContent='Could not load Yola. Refresh to retry.';
 };
 document.head.appendChild(original);
})();