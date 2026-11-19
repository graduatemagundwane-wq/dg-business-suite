'use strict';
// Server-enforced worker sell-only scope. Existing original Yola POS remains
// untouched for owner/manager. No front-end-only protection.
const original=require('./pos-original');
module.exports=async function restrictedPos(ctx){
 const {user,path,method,body:b,db,ok,fail,active}=ctx;
 if(!user || user.role!=='worker')return original(ctx);
 if(!active(user)){
   fail(ctx.res,403,'Master Control activation required');return true;
 }
 if(path==='/api/pos/summary'&&method==='GET'){
   // The original Yola sale screen expects a summary; reveal no reports.
   ok(ctx.res,{summary:{sales_count:0,sales_total:'0'}});return true;
 }
 if(path==='/api/pos/products'&&method==='GET'){
   const result=await db.query(
     'SELECT id,name,sku,barcode,category,price_cents,tax_bps,(stock_qty>0) AS available FROM yola_pos_products WHERE installation_id=$1 AND active=true ORDER BY name LIMIT 1000',
     [user.installation_id]);
   ok(ctx.res,{products:result.rows});return true;
 }
 if(path==='/api/pos/checkout'&&method==='POST'){
   if(Number(b.discount_cents||0)!==0){
     fail(ctx.res,403,'Only the owner can grant discounts');return true;
   }
   return original(ctx);
 }
 if(path==='/api/pos/receipt'&&method==='GET'){
   // Original endpoint limits worker receipts to their own cashier_id.
   return original(ctx);
 }
 fail(ctx.res,403,'Worker can only sell products and print own receipts');
 return true;
};