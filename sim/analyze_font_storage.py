"""Measure lossless font encodings; no design or assets are modified."""
from pathlib import Path
from collections import Counter
from math import ceil

ROOT=Path(__file__).resolve().parent.parent
coverage=[]
for bank in range(16):
    words=[int(s,16) for s in (ROOT/f'assets/lyrics/font24_bank_{bank:02d}.hex').read_text().split()]
    coverage.extend((w>>(2*i))&3 for w in words for i in range(8))
coverage=coverage[:64372]
print('coverage',Counter(coverage))
for group in (2,4,8,16,22):
    words=[sum(c<<(2*i) for i,c in enumerate(coverage[start:start+group]))
           for start in range(0,len(coverage),group)]
    unique=len(set(words)); bits=(unique-1).bit_length()
    print('group',group,'entries',len(words),'patterns',unique,'index_bits',bits,
          'ideal_bits',len(words)*bits+unique*group*2)
for split in (4,8,11):
    total=unique_count=0
    for lane in range(split):
        values=[coverage[i] for i in range(lane,len(coverage),split)]
        total+=len(values)
    print('interleaved',split,'pixels',total)
bounds=[]
for gid in range(133):
    pix=coverage[gid*484:(gid+1)*484]
    active=[(i%22,i//22) for i,c in enumerate(pix) if c]
    if not active: bounds.append((0,0,0,0));continue
    x0=min(x for x,y in active);x1=max(x for x,y in active)
    y0=min(y for x,y in active);y1=max(y for x,y in active)
    bounds.append((x0,y0,x1-x0+1,y1-y0+1))
print('bounding widths',Counter(w for x,y,w,h in bounds))
print('bounding heights',Counter(h for x,y,w,h in bounds))
print('glyph crop pixels',sum(w*h for x,y,w,h in bounds))
for stride_mode in ('actual','min20','min22'):
    size=sum((w if stride_mode=='actual' else max(int(stride_mode[3:]),w))*h
             for x,y,w,h in bounds if w)
    print('crop',stride_mode,'pixels',size,'2-bit 4096 banks',ceil(size/4096))
print('nonzero glyphs',sum(bool(w) for x,y,w,h in bounds))
