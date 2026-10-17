"""Contact sheet of sprites: python3 sheet.py out.png file1 file2 ..."""
import sys
from PIL import Image, ImageDraw
out=sys.argv[1]; files=sys.argv[2:]
cw=300; ch=300; cols=min(8,len(files)); rows=(len(files)+cols-1)//cols
s=Image.new('RGB',(cw*cols,ch*rows),(185,185,185)); d=ImageDraw.Draw(s)
for i,f in enumerate(files):
    im=Image.open(f).convert('RGBA'); im.thumbnail((cw-20,ch-40))
    x=(i%cols)*cw; y=(i//cols)*ch
    s.paste(im,(x+10+(cw-20-im.width)//2,y+30+(ch-40-im.height)//2),im)
    d.text((x+8,y+6),f.split('/')[-1].replace('furn_','').replace('.png',''),fill=(20,20,20))
s.save(out)
