# 时序约束文件
# 适用于 Zynq UltraScale+ FPGA

# =========================================
# 时钟定义
# =========================================

# 主系统时钟 - 100 MHz
create_clock -period 10.000 -name clk -waveform {0.000 5.000} [get_ports clk]

# =========================================
# 输入延迟约束
# =========================================

# AXI4-Lite 输入信号延迟（相对于时钟）
set_input_delay -clock clk -max 2.0 [get_ports {s_axi_*}]
set_input_delay -clock clk -min 0.5 [get_ports {s_axi_*}]

# 排除时钟和复位信号
set_input_delay -clock clk 0.0 [get_ports clk]
set_input_delay -clock clk 0.0 [get_ports rst_n]

# =========================================
# 输出延迟约束
# =========================================

# AXI4-Lite 输出信号延迟
set_output_delay -clock clk -max 2.0 [get_ports {s_axi_*}]
set_output_delay -clock clk -min 0.5 [get_ports {s_axi_*}]

# 中断和状态输出
set_output_delay -clock clk -max 3.0 [get_ports interrupt]
set_output_delay -clock clk -max 3.0 [get_ports busy]
set_output_delay -clock clk -max 3.0 [get_ports attn_valid]
set_output_delay -clock clk -max 3.0 [get_ports ffn_valid]

# =========================================
# 伪路径（False Path）
# =========================================

# 复位信号为异步，不需要时序检查
set_false_path -from [get_ports rst_n]
set_false_path -to [get_ports rst_n]

# 状态指示信号可以有一定延迟
set_false_path -through [get_pins -hier *busy*]

# =========================================
# 多周期路径（Multi-Cycle Path）
# =========================================

# MAC单元计算可能需要2个周期
# set_multicycle_path -setup 2 -from [get_cells -hier *mac_unit*] -to [get_cells -hier *result*]
# set_multicycle_path -hold 1 -from [get_cells -hier *mac_unit*] -to [get_cells -hier *result*]

# Softmax计算路径较长，可能需要多周期
# set_multicycle_path -setup 3 -from [get_cells -hier *softmax*] -to [get_cells -hier *valid*]

# =========================================
# 物理约束
# =========================================

# 最大扇出限制
set_max_fanout 20 [current_design]

# 最大转换时间（输出负载）
set_max_transition 1.5 [current_design]

# =========================================
# 时钟不确定性
# =========================================

# 考虑时钟抖动和偏斜
set_clock_uncertainty -setup 0.5 [get_clocks clk]
set_clock_uncertainty -hold 0.3 [get_clocks clk]

# =========================================
# 时钟组（Clock Groups）
# =========================================

# 如果有多个时钟域，定义为异步
# set_clock_groups -asynchronous -group [get_clocks clk] -group [get_clocks clk2]

# =========================================
# 关键路径优化
# =========================================

# 对关键模块设置更严格的时序要求
# set_max_delay 8.0 -from [get_cells -hier *attention_core*] -to [get_cells -hier *valid*]

# =========================================
# 功耗优化
# =========================================

# 对非关键路径设置较松的时序，允许工具优化功耗
# set_max_delay 12.0 -from [get_cells -hier *config*] -to [get_cells -hier *status*]
