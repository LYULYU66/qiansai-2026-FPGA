"""Export previews exclusively from the actual ModelSim pixel output."""
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parent.parent
out=ROOT/'sim/home_tpms_4cards_20260930'
frame=Image.open(ROOT/'sim/home_nav_app_20260930/preview.ppm').convert('RGB')
frame.save(out/'preview.png')
frame.crop((0,310,640,480)).save(out/'cards_preview.png')
frame.crop((484,310,624,410)).resize((560,400),Image.Resampling.NEAREST).save(out/'tpms_zoom.png')
print('Saved actual HDL whole-frame, four-card and TPMS zoom previews')
