// Exhaustively prove the RX-only equality predicate over EVERY 20-bit sum.
// Separate carry folding oracle; does not assume a correct IPv4 header.
let accepted=0;
for(let sum=0;sum<0x100000;sum++){
    const first=(sum&0xffff)+(sum>>>16);
    const folded=((first&0xffff)+(first>>>16))&0xffff;
    const equality=((sum>>>4)&0xfff)===0xfff && (sum&15)===(15-(sum>>>16));
    if((folded===0xffff)!==equality)throw Error('Checksum predicate mismatch '+sum.toString(16));
    if(equality)accepted++;
}
console.log('PASS IPv4 checksum predicate: all 1048576 sums, '+accepted+' valid folded-FFFF values');
