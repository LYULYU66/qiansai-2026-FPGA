import sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent)); sys.path.insert(0, str(HERE))
import star_sky_model_20261020 as model
from run_check import FRAMES
L=model.LAYERS
for name in ("far","near"):
    stars=[];spark=0
    for y in range(480):
        pass
    # enumerate star centres in canvas (cell grid), visible rows
    CB=L[name]["CB"]; CELL=1<<CB
    cnt=0; bris=[]; sparks=0; below=0
    for cy in range(L[name]["ROWS"]):
        for c in range(L[name]["NCELL"]):
            y = cy*CELL + (8 if L[name]["NEAR"] else 4)  # any row in the cell: job decides
            # re-derive star existence/brightness at the star's own row
            for ly in range(CELL):
                j = model.cell_job(L[name], c, cy*CELL+ly, 0, 0)
                if j["ex"]:
                    m=max(j["buf"])
                    if m and max(j["buf"])==max(j["buf"]):
                        pass
            # star row = row where dy==0 -> peak
            best=0;besty=None
            for ly in range(CELL):
                j = model.cell_job(L[name], c, cy*CELL+ly, 0, 0)
                if j["ex"] and max(j["buf"])>best: best=max(j["buf"]); besty=cy*CELL+ly
            if best>0:
                cnt+=1; bris.append(best)
                if besty>=200: below+=1
    bris.sort()
    print(f"{name}: stars in 1280-px sky = {cnt} (per screen ~{cnt/2:.0f}); peak value min/median/max = {bris[0]}/{bris[len(bris)//2]}/{bris[-1]}; stars peaking at y>=200: {below}")
# sparkle count (near)
n=0
for cy in range(L["near"]["ROWS"]):
    for c in range(L["near"]["NCELL"]):
        seed=(0xB<<12)|(cy<<7)|c
        hx1=seed^(seed>>8); p=(hx1*0xA3D3)&0xFFFFFFFF; m=p&0xFFFF
        p=((m^(m>>7))*0x4B2D)&0xFFFFFFFF; m=p&0xFFFF; h1=m^(m>>9)
        p=(((h1^0x9E37)&0xFFFF)*0x6F4B)&0xFFFFFFFF; h2=((p>>16)&0xFFFF)^(p&0xFFFF)
        sq=((h2&255)**2)&0xFFFF
        if (h1>>12)<6 and (h2>>14)==3 and (sq>>14)==3: n+=1
print("near sparkle stars in the whole sky:", n)
