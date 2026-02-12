# 物理约束文件
# 适用于 ZCU102 开发板或类似平台

# =========================================
# 引脚分配（Pin Assignment）
# =========================================
# 注：以下为示例引脚，实际使用时需根据目标板卡调整

# 系统时钟 - 来自板载晶振或PL时钟
# set_property PACKAGE_PIN H16 [get_ports clk]
# set_property IOSTANDARD LVCMOS33 [get_ports clk]

# 复位信号 - 来自PS或外部按钮
# set_property PACKAGE_PIN D22 [get_ports rst_n]
# set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# =========================================
# I/O 标准
# =========================================

# AXI接口使用内部连接（PS到PL），无需引脚分配
# 如果需要外部接口，取消注释并调整：

# set_property IOSTANDARD LVCMOS18 [get_ports {s_axi_*}]

# =========================================
# 布局约束（Placement Constraints）
# =========================================

# 将关键模块放置在相近位置以减少延迟
# create_pblock pblock_attention
# add_cells_to_pblock [get_pblocks pblock_attention] [get_cells -hier *attention_core*]
# resize_pblock [get_pblocks pblock_attention] -add {SLICE_X0Y0:SLICE_X50Y50}

# create_pblock pblock_ffn
# add_cells_to_pblock [get_pblocks pblock_ffn] [get_cells -hier *ffn_inst*]
# resize_pblock [get_pblocks pblock_ffn] -add {SLICE_X60Y0:SLICE_X110Y50}

# =========================================
# 时钟缓冲
# =========================================

# 使用全局时钟资源
# set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_nets clk]

# =========================================
# 电源域配置
# =========================================

# 如果使用多电压域，配置电源轨
# set_property HD.TANDEM_IP_PBLOCK Stage1_Main [current_design]

# =========================================
# 配置模式
# =========================================

# 配置Bank电压
# set_property CFGBVS VCCO [current_design]
# set_property CONFIG_VOLTAGE 3.3 [current_design]

# =========================================
# DRC 豁免（如果需要）
# =========================================

# 对某些设计规则检查进行豁免（谨慎使用）
# create_waiver -type DRC -id {REQP-1840} -description "Waive PCIe requirement"
