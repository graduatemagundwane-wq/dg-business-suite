/** Validate captured camera barcode text. Never open scanned URLs or execute them. */
function cleanScan(field, raw) {
  if (typeof raw !== 'string') throw new Error('Scanner returned invalid data');
  const value=raw.trim();
  if (!value || value.length>160) throw new Error('Invalid barcode length');
  if (/^https?:\/\//i.test(value)) throw new Error('URLs are not accepted as part identifiers');
  const numeric = ['job_id','vehicle_id','customer_id','part_id','technician_id'];
  if (numeric.includes(field)) {
    if(!/^[1-9]\d{0,9}$/.test(value))throw new Error('Scan a positive numeric ID');
  } else if(field==='vin') {
    if(!/^[A-HJ-NPR-Z0-9]{17}$/i.test(value))throw new Error('VIN requires 17 allowed characters');
  } else if(!/^[\w.\-/ ]+$/.test(value)){
    throw new Error('Barcode contains unsupported characters');
  }
  return value;
}
module.exports={cleanScan};
