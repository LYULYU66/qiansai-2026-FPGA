#!/bin/bash
# usage: run_sweep_20261022.sh JOB... (job = a<seed> or b<seed>), 3 concurrent; round 13 photo switch.
P=C:/FPGA2026/HX4S20_Contest_2026/7_lab_ex_2026_nosoft/qiansai/lab_ex4_tf/dual_board/image_link/prj
TDC=C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe
one(){
    j=$1; s=${j:1}; D=$P/_s24_$j; rm -rf $D; mkdir -p $D
    if [ ${j:0:1} = a ]; then
        cp -p $P/dualsong_a_20261011_song3/MEDIA_SRAM_TEST_A_SONG3_20261011.al $D/
        sed "s/set_param place seed [0-9]*/set_param place seed $s/" $P/dualsong_a_20261011_song3/build_song3.tcl > $D/build.tcl
    else
        cp -p $P/b_hdmi_image3_20261006/MEDIA_B_HDMI_IMAGE3_20261006.al $D/
        sed "s/set_param place seed [0-9]*/set_param place seed $s/" $P/b_hdmi_image3_20261006/build_b_hdmi.tcl > $D/build.tcl
    fi
    # Full violation list + routed database for later path queries.
    sed -i -e '/_pr\.timing$/a export_db route.db' -e '/_pr\.timing$/a report_timing_summary -ep_num 3000 -viol_only -file viol.timing' $D/build.tcl
    (cd $D && $TDC build.tcl > build.log 2>&1)
    {
    echo "== $j bit=$(ls $D/*.bit 2>/dev/null | wc -l) errors=$(grep -c ' ERROR' $D/build.log)"
    grep -E "^#(lut|reg|bram|bram32k|dsp) " $D/*_phy.area 2>/dev/null | tr -s ' ' | tr '\n' ';'; echo
    C:/FPGA2026/HX4S20_Contest_2026/7_lab_ex_2026_nosoft/qiansai/lab_ex4_tf/dual_board/image_link/prj/tsum_20261021.sh $D/*_pr.timing 2>/dev/null
    } >> $P/sweep_20261022b.txt
}
running=0
for j in "$@"; do
    one $j &
    running=$((running+1))
    if [ $running -ge 3 ]; then wait -n; running=$((running-1)); fi
done
wait
echo ALL DONE >> $P/sweep_20261022b.txt
