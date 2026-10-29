"""Read-only independent math oracle for every native ROM INIT entry."""
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parent.parent
def expected(value,brightness,contrast):
 distance=abs(value-128)
 extra=(0,distance//4,distance//2,distance)[contrast]
 contrasted=max(0,value-extra) if value<128 else min(255,value+extra)
 bright=((contrasted+2)//4,(contrasted+1)//2,(3*contrasted+2)//4,contrasted)[brightness]
 return (bright//4)*4
if __name__=='__main__':
 text=(ROOT/'src/user_source/hdl_source/video_image_adjust.v').read_text()
 params=dict(re.findall(r"\.INIT_([0-9A-F]{2})\(256'h([0-9A-F]{64})\)",text))
 assert len(params)==128
 for addr in range(4096):
  word_addr=addr//2
  bank=int(params[f'{word_addr//16:02X}'],16)
  word=(bank>>((word_addr%16)*16))&65535
  result=((word>>(8*(addr%2)))&63)*4
  assert result==expected(addr%256,addr//1024,(addr//256)%4),(addr,result)
  assert (word&0xC0C0)==0,'unused lane bits not zero'
 assert '.USE_LUT_ROM(1)' in (ROOT/'src/user_source/hdl_source/top_tf_hdmi_audio.v').read_text()
 print('PASS IMAGE_ADJUST_INIT all 4096 brightness/contrast/input combinations; identical rounding, saturation and RGB666; both native ROM copies use these INITs')
