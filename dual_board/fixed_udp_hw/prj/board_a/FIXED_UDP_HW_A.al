<?xml version="1.0" encoding="UTF-8"?>
<Project Version="3" Minor="2" Path="C:/FPGA2026/HX4S20_Contest_2026/7_lab_ex_2026_nosoft/qiansai/lab_ex4_tf/dual_board/fixed_udp_hw/prj/board_a">
    <TD_Version>6.2.168116</TD_Version>
    <Name>FIXED_UDP_HW_A</Name>
    <HardWare><Family>EG4</Family><Device>EG4S20BG256</Device><Speed></Speed></HardWare>
    <Source_Files>
        <Verilog>
            <File Path="../../../ethernet_smoke/source_code/rtl/BUFGMUX.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="1"/></FileInfo></File>
            <File Path="../../../ethernet_smoke/source_code/rtl/clk_gen_rst_gen.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="2"/></FileInfo></File>
            <File Path="../../../ethernet_smoke/source_code/rtl/div_clk_gen.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="3"/></FileInfo></File>
            <File Path="../../../ethernet_smoke/source_code/rtl/IDDR.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="4"/></FileInfo></File>
            <File Path="../../../ethernet_smoke/source_code/rtl/ODDR.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="5"/></FileInfo></File>
            <File Path="../../../ethernet_smoke/source_code/rtl/RAMB16_S9_S9.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="6"/></FileInfo></File>
            <File Path="../../../ethernet_smoke/source_code/rtl/rgmii_interface.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="7"/></FileInfo></File>
            <File Path="../../../ethernet_smoke/source_code/rtl/rx_client_fifo.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="8"/></FileInfo></File>
            <File Path="../../../ethernet_smoke/source_code/rtl/temac_block.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="9"/></FileInfo></File>
            <File Path="../../../ethernet_smoke/source_code/rtl/temac_clk_gen.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="10"/></FileInfo></File>
            <File Path="../../../ethernet_smoke/source_code/rtl/tx_client_fifo.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="11"/></FileInfo></File>
            <File Path="../../../ethernet_smoke/source_code/rtl/tx_clk_en_gen.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="12"/></FileInfo></File>
            <File Path="../../../ethernet_smoke/source_code/rtl/udp_ip_protocol_stack_merge.enc.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="13"/></FileInfo></File>
            <File Path="../../../image_link/rtl/dual_board_eth_transport.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="14"/></FileInfo></File>
            <File Path="../../../image_link/rtl/image_packet_rx.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="15"/></FileInfo></File>
            <File Path="../../rtl/fixed_udp_hw_a.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="16"/></FileInfo></File>
            <File Path="../../../image_link/rtl/fixed_peer_udp.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="21"/></FileInfo></File>
            <File Path="../../../image_link/rtl/image_receipt.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="22"/></FileInfo></File>
        </Verilog>
        <ADC_FILE><File Path="../../constraints/board_a.adc"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="constraint_1"/><Attr Name="CompileOrder" Val="1"/></FileInfo></File></ADC_FILE>
        <SDC_FILE><File Path="../../../ethernet_smoke/source_code/constraints/smoke.sdc"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="constraint_1"/><Attr Name="CompileOrder" Val="2"/></FileInfo></File></SDC_FILE>
        <IP_FILE>
            <File Path="../../../ethernet_smoke/prj/board_a/al_ip/pll_gen.ipc"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="17"/></FileInfo></File>
            <File Path="../../../ethernet_smoke/prj/board_a/al_ip/rx_pll.ipc"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="18"/></FileInfo></File>
            <File Path="../../../ethernet_smoke/prj/board_a/al_ip/TEMAC_CORE/TEMAC_CORE.xml"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="19"/></FileInfo></File>
        </IP_FILE>
    </Source_Files>
    <FileSets><FileSet Name="design_1" Type="DesignFiles"/><FileSet Name="constraint_1" Type="ConstrainFiles"/></FileSets>
    <TOP_MODULE><LABEL>fixed_udp_hw_a</LABEL><MODULE>fixed_udp_hw_a</MODULE><CREATEINDEX>user</CREATEINDEX></TOP_MODULE>
    <Runs>
        <Run Name="syn_1" Type="Synthesis" ConstraintSet="constraint_1" Description="" Active="true"><Strategy Name="Default_Synthesis_Strategy"/><UserParams/></Run>
        <Run Name="phy_1" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_1" Active="true"><Strategy Name="Default_PhysicalDesign_Strategy"/><UserParams/></Run>
    </Runs>
</Project>
