<?xml version="1.0" encoding="UTF-8"?>
<Project Version="3" Minor="2" Path="C:/FPGA2026/HX4S20_Contest_2026/7_lab_ex_2026_nosoft/qiansai/lab_ex4_tf/dual_board/image_link/prj/ingress_area">
    <TD_Version>6.2.168116</TD_Version>
    <Name>ingress_area</Name>
    <HardWare><Family>EG4</Family><Device>EG4S20BG256</Device><Speed></Speed></HardWare>
    <Source_Files>
        <Verilog>
            <File Path="../../rtl/image_main_ingress.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="1"/></FileInfo></File>
            <File Path="../../rtl/image_sdram_sink.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="2"/></FileInfo></File>
            <File Path="../../rtl/image_packet_rx.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="3"/></FileInfo></File>
            <File Path="../../rtl/image_receipt.v"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="4"/></FileInfo></File>
        </Verilog>
    </Source_Files>
    <FileSets>
        <FileSet Name="design_1" Type="DesignFiles"/>
        <FileSet Name="constraint_1" Type="ConstrainFiles"/>
    </FileSets>
    <TOP_MODULE><LABEL>image_main_ingress</LABEL><MODULE>image_main_ingress</MODULE><CREATEINDEX>user</CREATEINDEX></TOP_MODULE>
    <Runs>
        <Run Name="syn_1" Type="Synthesis" ConstraintSet="constraint_1" Description="" Active="true">
            <Strategy Name="Default_Synthesis_Strategy"/><UserParams/>
        </Run>
        <Run Name="phy_1" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_1" Active="true">
            <Strategy Name="Default_PhysicalDesign_Strategy"/><UserParams/>
        </Run>
    </Runs>
</Project>
