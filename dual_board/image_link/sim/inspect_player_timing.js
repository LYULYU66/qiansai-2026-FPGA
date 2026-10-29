const fs=require('fs'),path=require('path');
const base=path.resolve(__dirname,'..');
for(const file of process.argv.slice(2)){
    const text=fs.readFileSync(path.resolve(base,file),'utf8');
    const groups=text.split(/(?=Path Group\s+:)/).slice(1);
    console.log(file);
    for(const group of groups){
        const title=group.match(/Path Group\s+:\s*([^\r\n]+)/)[1];
        const paths=[...group.matchAll(/Slack\s+:\s*([+-]?[\d.]+)ns\s+Begin Point\s+:\s*([^\r\n]+)\s+End Point\s+:\s*([^\r\n]+)\s+Check Type\s+:\s*(\w+)/g)]
            .map(m=>({slack:Number(m[1]),begin:m[2].split(' (')[0],end:m[3].split(' (')[0],type:m[4]}));
        for(const type of ['setup','hold','recovery','removal']){
            const rows=paths.filter(p=>p.type===type&&p.slack<0).sort((a,b)=>a.slack-b.slack).slice(0,3);
            if(rows.length)console.log(JSON.stringify({group:title,type,paths:rows}));
        }
    }
}
