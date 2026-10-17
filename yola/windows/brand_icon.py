"""Generate a branded Windows icon for Yola (no external asset dependencies)."""
from pathlib import Path
from PIL import Image,ImageDraw
out=Path(__file__).resolve().parent
# Prefer the official Yola icon provided by the product owner.
brand_file=out/"brand.webp.b64"
if brand_file.exists():
    import base64
    from io import BytesIO
    actual=Image.open(BytesIO(base64.b64decode(brand_file.read_text().strip()))).convert("RGBA")
    actual=actual.resize((256,256),Image.Resampling.LANCZOS)
    actual.save(out/"yola.png")
    actual.save(out/"yola.ico",sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])
    print("Branded Windows icon generated from official Yola artwork")
    raise SystemExit(0)
im=Image.new("RGBA",(256,256),(0,0,0,0))
d=ImageDraw.Draw(im)
for y in range(16,240):
    t=(y-16)/224
    color=(int(255-36*t),int(216-62*t),int(135-52*t),255)
    d.line((18,y,237,y),fill=color,width=1)
# Rounded mask for gradient card
mask=Image.new("L",(256,256),0)
ImageDraw.Draw(mask).rounded_rectangle((15,15,241,241),radius=46,fill=255)
im.putalpha(mask)
d=ImageDraw.Draw(im)
# Abstract Y, deep-navy double swoosh. The geometry matches Yola's gold/navy identity.
d.polygon([(63,79),(102,79),(130,125),(148,83),(195,83),(145,176),(117,205),(91,205),(115,158)],fill=(15,36,59))
d.polygon([(104,86),(121,86),(131,116),(142,91),(166,91),(133,164)],fill=(25,48,76))
im.save(out/"yola.png")
im.save(out/"yola.ico",sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])
print("Created Yola PNG and ICO", (out/"yola.ico").stat().st_size)
