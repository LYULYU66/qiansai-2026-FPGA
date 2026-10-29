// Emit an apply_patch; never modify previous releases/build inputs in place.
const fs=require('fs'),p=require('path'),base=__dirname,jobs=[];
const rd=f=>fs.readFileSync(p.join(base,f),'utf8');
const branch='rtl/startup_fix_20261008';
function replace(s,a,b){if(!s.includes(a))throw Error('Missing anchor '+a);return s.replace(a,b);}
let s=rd('rtl/media_udp_arbiter.v');
const split=s.indexOf('module media_udp_scheduler #(');
let a=s.slice(0,split),b=s.slice(split);
b=replace(b,'reg [7:0] source_data;','reg [7:0] source_data;\nreg [7:0] source_data_q;\nreg source_valid_q;');
b=replace(b,'wire [CHANNELS-1:0] selected=busy ? owner : choice;','// Only the registered owner reaches the network/producer ACK boundary.\n// Capture idle arbitration one cycle before requesting UDP; never let an\n// unrelated producer state propagate through length/choice into another ACK.\nwire [CHANNELS-1:0] selected=owner;');
b=replace(b,'assign net_request=busy ? !acknowledged : |choice;','assign net_request=busy && !acknowledged;');
b=replace(b,'assign c_ack=selected & {CHANNELS{net_ack && (busy || |choice)}};','assign c_ack=owner & {CHANNELS{net_ack && busy}};');
b=replace(b,"assign net_length=busy ? {{(16-COUNT_BITS){1'b0}},length} : choice_length;","assign net_length={{(16-COUNT_BITS){1'b0}},length};");
b=replace(b,'(source_valid || remaining!=length || prime_wait==7);','(source_valid_q || remaining!=length ||\n                  (prime_wait==7 && !source_valid));');
b=replace(b,'wire padding=aborting || !source_valid;','wire padding=aborting || !source_valid_q;');
b=replace(b,": 8'd0) : source_data;",": 8'd0) : source_data_q;");
b=replace(b,"length<=0; remaining<=0; prime_wait<=0; crc<=16'hffff;","length<=0; remaining<=0; prime_wait<=0; crc<=16'hffff;\n        source_data_q<=0; source_valid_q<=0;");
b=replace(b,'if(net_request) begin\n            busy<=1; owner<=choice; acknowledged<=net_ack;',"source_data_q<=0; source_valid_q<=0;\n        if(|choice) begin\n            busy<=1; owner<=choice; acknowledged<=0;");
b=replace(b,'end else begin\n        if(net_ack) acknowledged<=1;\n        if(acknowledged && !source_valid && prime_wait!=7)',"end else begin\n        // One byte of pipelining, no packet RAM or byte backpressure. The\n        // contiguous producer stream shifts as a whole, including its CRC.\n        source_data_q<=source_data; source_valid_q<=source_valid;\n        if(net_ack) acknowledged<=1;\n        // The input byte register adds one clock, but must not steal a clock\n        // from the producer's original seven-clock startup allowance. A raw\n        // first byte that arrived on time is captured before output starts.\n        if(acknowledged && !source_valid && prime_wait!=7)");
b=replace(b,'if(!source_valid) aborting<=1;','if(!source_valid_q) aborting<=1;');
jobs.push([branch+'/media_udp_arbiter.v',a+b]);
const olddir='prj/car_intro_b_20261007',dir='prj/startup_fix_b_20261008',oldstem='MEDIA_B_CAR_INTRO_20261007',stem='MEDIA_B_STARTUP_FIX_20261008';
jobs.push([dir+'/'+stem+'.al',rd(olddir+'/'+oldstem+'.al').replaceAll(olddir,dir).replaceAll(oldstem,stem).replaceAll('/rtl/media_udp_arbiter.v','/'+branch+'/media_udp_arbiter.v')]);
jobs.push([dir+'/build_flow.tcl',rd(olddir+'/build_flow.tcl').replaceAll(oldstem,stem)]);
s=rd('sim/tb_media_scheduler.v');
s=replace(s,'if(!dut.busy && request)begin','if(!dut.busy && |dut.choice)begin');
s=replace(s,'// Selection is locked when requesting UDP, NOT at its later ACK.','// Selection is locked one clock BEFORE requesting UDP, not at later ACK.');
s=replace(s,'// A late high-priority request must not interrupt a locked long packet.',`// Pipeline must preserve the original seven-clock producer prime budget.
    for(round=0;round<7;round=round+1)begin
        prepare(0,MAX_LENGTH,-1,round);target=target+1;settle(target);
    end
    // A late high-priority request must not interrupt a locked long packet.`);
jobs.push(['sim/startup_fix_20261008/tb_media_scheduler.v',s]);
s=rd('sim/run_scheduler_modelsim.do').replaceAll('work_image_link','work_startup_fix_scheduler').replaceAll('../rtl/media_udp_arbiter.v','../'+branch+'/media_udp_arbiter.v').replaceAll('tb_media_scheduler.v','startup_fix_20261008/tb_media_scheduler.v').replaceAll('-wlf flat_scheduler','-wlf startup_fix_20261008/flat_scheduler');
s+='\nquit -code 0\n';jobs.push(['sim/startup_fix_20261008/run_scheduler.do',s]);
s=rd('sim/car_intro_20261007/run_boundary.do').replaceAll('work_car_intro_boundary','work_startup_fix_boundary').replaceAll('../rtl/media_udp_arbiter.v','../'+branch+'/media_udp_arbiter.v').replaceAll('car_intro_20261007/b_boundary.wlf','startup_fix_20261008/b_boundary.wlf');
jobs.push(['sim/startup_fix_20261008/run_boundary.do',s]);
console.log('*** Begin Patch');
for(const [f,t] of jobs){if(fs.existsSync(p.join(base,f)))throw Error('Exists '+f);console.log('*** Add File: dual_board/image_link/'+f);for(const l of t.split(/\r?\n/))console.log('+'+l);}
console.log('*** End Patch');
