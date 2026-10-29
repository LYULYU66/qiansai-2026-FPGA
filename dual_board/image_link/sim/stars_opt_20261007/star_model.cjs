// Independent integer software model for seam witnesses/preview, not RTL state.
const bx=[43,53,40,47,56,39,50,44,54,48],by=[55,92,38,76,64,26,88,50,104,68];
const seeds=[16,107,50,185,224,141,84,12,172,61],off=[0,683,1365,2048,2731,3413];
function ease(v){v%=4096;const t=v>=2048?4095-v:v,s=t>>9,r=t&511;return [r>>2,128+((r*3)>>2),512+((r*3)>>2),896+(r>>2)][s];}
function geometry(phase){if(phase>=20480)phase=0;const fast=(phase%4096)*4;return Array.from({length:10},(_,lane)=>Array.from({length:6},(_,k)=>{
 const large=lane%3===0&&(k===0||k===3),medium=lane%3!==0&&(k===1||k===4),size=large?2:medium?1:0;
 const x=k%3===0?bx[lane]:k%3===1?120-bx[lane]:bx[lane]+25;
 const breath=ease((large?(fast%1024)*4:(fast%2048)*2)+seeds[lane]*16+off[k]);
 return {x:(x-16)*4+(ease(fast+seeds[lane]*16+k*512)>>3),y:(by[lane]+k*64-16)*4+(ease(fast/2+(seeds[lane]^147)*16+off[k])>>3),size,amp:large?80+(breath>>3):medium?32+(breath>>4):12+(breath>>5)};
}));}
function light(phase,x,y,geo=geometry(phase)){
 if(phase>=20480)phase=0;let u=x*16-3*ease(phase%4096);if(u<0)u+=20480;
 const lane=u>>11;let near=geo[lane][0],dy=Math.abs(y*4-near.y);
 for(const p of geo[lane].slice(1)){const d=Math.abs(y*4-p.y);if(d<dy){near=p;dy=d;}}
 const dx=Math.floor(Math.abs(Math.floor((u%2048)/4)-near.x)/(1<<near.size));dy=Math.floor(Math.min(dy,255)/(1<<near.size));
 const radius=Math.max(dx,dy)+Math.floor(Math.min(dx,dy)/2);
 const v=dx<64&&dy<64&&radius<32?Math.max(0,near.amp-radius*16)+Math.floor(Math.max(0,near.amp-radius*6)/8):0;
 return {value:v,warm:radius<=2};
}
module.exports={ease,geometry,light};
if(require.main===module){
 let witness;
 for(let ph=0;ph<4096&&!witness;ph+=8){const g=geometry(ph);for(let y=0;y<480;y++)if(light(ph,639,y,g).value&&light(ph,640,y,g).value){witness={phase:ph,y};break;}}
 console.log(JSON.stringify(witness));
}
