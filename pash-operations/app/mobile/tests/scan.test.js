const test=require('node:test');const assert=require('node:assert/strict');const {cleanScan}=require('../scan-utils');
test('numeric job QR accepts only positive ID',()=>{
 assert.equal(cleanScan('job_id',' 123 '),'123');
 assert.throws(()=>cleanScan('job_id','JOB-12'));
 assert.throws(()=>cleanScan('job_id','0'));
});
test('VIN barcode accepts valid VIN and rejects forbidden characters',()=>{
 assert.equal(cleanScan('vin','1HGCM82633A004352'),'1HGCM82633A004352');
 assert.throws(()=>cleanScan('vin','1HGIM82633A004352'));
 assert.throws(()=>cleanScan('vin','short'));
});
test('scanner will never activate arbitrary links or overly long strings',()=>{
 assert.throws(()=>cleanScan('sku','https://evil.example/part'));
 assert.throws(()=>cleanScan('serial','x'.repeat(161)));
 assert.equal(cleanScan('sku',' DSG-200/A '),'DSG-200/A');
});
