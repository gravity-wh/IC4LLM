# LLM硬件加速器 - Vivado仿真与验证指南

## 1. 环境准备

### 1.1 所需工具

- Vivado Design Suite 2020.2 或更高版本
- 推荐：Vivado 2023.1 (支持最新的UltraScale+ FPGA)
- 操作系统：Linux或Windows

### 1.2 文件组织

```
IC4LLM/
├── rtl/                    # RTL源代码
│   ├── top/
│   ├── attention/
│   ├── ffn/
│   ├── memory/
│   └── utils/
├── tb/                     # 测试平台
├── docs/                   # 文档
├── constraints/           # 约束文件
└── scripts/               # 综合脚本
```

## 2. Vivado工程创建

### 2.1 方法1：使用TCL脚本（推荐）

在Vivado TCL控制台中执行：

```tcl
# 设置工程目录
cd /path/to/IC4LLM

# 创建工程
create_project llm_accelerator ./vivado_project -part xczu9eg-ffvb1156-2-e

# 添加RTL源文件
add_files -norecurse {
    rtl/utils/fixed_point_mult.v
    rtl/utils/fixed_point_add.v
    rtl/utils/activation_gelu.v
    rtl/utils/mac_unit.v
    rtl/utils/systolic_array.v
    rtl/utils/softmax_unit.v
    rtl/attention/attention_core.v
    rtl/ffn/ffn_layer.v
    rtl/memory/axi4_lite_slave.v
    rtl/top/llm_accelerator_top.v
}

# 添加测试文件
add_files -fileset sim_1 -norecurse {
    tb/tb_mac_unit.v
    tb/tb_llm_accelerator_top.v
}

# 设置顶层模块
set_property top llm_accelerator_top [current_fileset]
set_property top tb_llm_accelerator_top [get_filesets sim_1]

# 更新编译顺序
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
```

### 2.2 方法2：GUI手动创建

1. 启动Vivado
2. File → New Project
3. 选择工程名称和位置
4. 选择RTL Project
5. 添加源文件（从rtl/目录）
6. 添加约束文件（可选）
7. 选择目标器件：Zynq UltraScale+ ZU9EG 或其他
8. 完成工程创建

## 3. 行为仿真

### 3.1 MAC单元仿真

**测试目的**: 验证乘加累加单元的定点数运算正确性

**步骤**:
1. 在Flow Navigator中选择 `Run Simulation → Run Behavioral Simulation`
2. 在Simulation Sources中设置 `tb_mac_unit` 为顶层
3. 点击运行
4. 观察波形窗口中的信号

**预期结果**:
```
Test 1: Simple dot product
Result = 0x0500 (5.00)
Expected ≈ 5.0

Test 2: Negative numbers
Result = 0x0000 (0.00)
Expected = 0.0
```

### 3.2 顶层模块仿真

**测试目的**: 验证整个加速器系统的功能

**步骤**:
1. 设置 `tb_llm_accelerator_top` 为仿真顶层
2. 运行仿真时间：100 us
3. 检查AXI4-Lite总线事务
4. 验证状态寄存器变化

**关键信号监控**:
- `clk`, `rst_n`: 时钟和复位
- `s_axi_*`: AXI4-Lite总线信号
- `busy`, `attn_valid`, `ffn_valid`: 状态指示
- `interrupt`: 中断输出

### 3.3 波形分析

**重点观察**:
1. **AXI写事务**:
   - awvalid/awready握手
   - wvalid/wready握手
   - bvalid/bready响应

2. **状态转换**:
   - IDLE → BUSY → VALID
   - 计算延迟时间

3. **数据流动**:
   - MAC单元输入输出
   - Softmax计算过程

## 4. 综合与实现

### 4.1 RTL分析

在综合前进行RTL检查：

```tcl
# 检查语法
check_syntax

# 详细检查
synth_design -rtl -rtl_skip_constraints
```

### 4.2 综合设置

```tcl
# 设置综合策略
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]

# 运行综合
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# 打开综合后设计
open_run synth_1

# 查看资源使用
report_utilization -file utilization_post_synth.rpt
report_timing_summary -file timing_post_synth.rpt
```

### 4.3 布局布线

```tcl
# 设置实现策略
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]

# 运行实现
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# 打开实现后设计
open_run impl_1

# 生成报告
report_utilization -file utilization_post_route.rpt
report_timing_summary -file timing_post_route.rpt
report_power -file power_post_route.rpt
```

## 5. 时序约束

### 5.1 基本时钟约束

创建文件 `constraints/timing.xdc`:

```tcl
# 主时钟：100 MHz
create_clock -period 10.000 -name clk [get_ports clk]

# 输入延迟
set_input_delay -clock clk 2.0 [all_inputs]
set_input_delay -clock clk 0.0 [get_ports clk]
set_input_delay -clock clk 0.0 [get_ports rst_n]

# 输出延迟
set_output_delay -clock clk 2.0 [all_outputs]

# 伪路径（复位信号）
set_false_path -from [get_ports rst_n]

# 最大扇出
set_max_fanout 20 [current_design]
```

### 5.2 多周期路径（如果需要）

```tcl
# 某些计算路径可能需要多个周期
set_multicycle_path -setup 2 -from [get_pins -hier *mac_unit*] -to [get_pins -hier *result*]
set_multicycle_path -hold 1 -from [get_pins -hier *mac_unit*] -to [get_pins -hier *result*]
```

## 6. 功能验证清单

### 6.1 模块级验证

- [x] fixed_point_mult: 定点乘法正确性
- [x] fixed_point_add: 定点加法正确性
- [x] mac_unit: 向量点积计算
- [ ] systolic_array: 矩阵乘法
- [ ] softmax_unit: Softmax归一化
- [ ] activation_gelu: GELU激活函数
- [ ] attention_core: 注意力机制
- [ ] ffn_layer: 前馈网络

### 6.2 系统级验证

- [ ] AXI4-Lite读写操作
- [ ] 控制流程正确性
- [ ] 状态机转换
- [ ] 中断生成
- [ ] 数据通路端到端

### 6.3 边界条件测试

- [ ] 全零输入
- [ ] 最大值输入
- [ ] 最小值输入
- [ ] 随机数据
- [ ] 连续启动测试

## 7. 常见问题排查

### 7.1 综合警告

**警告**: "Latch inferred"
- **原因**: 组合逻辑中存在未完全定义的情况
- **解决**: 检查always块，确保所有分支都有赋值

**警告**: "Multi-driven net"
- **原因**: 同一信号被多个模块驱动
- **解决**: 检查模块连接，使用三态缓冲器或多路复用器

### 7.2 时序违例

**Setup Violation**:
- 增加流水线级数
- 降低时钟频率
- 优化关键路径逻辑

**Hold Violation**:
- 添加延迟单元
- 调整布局约束

### 7.3 仿真不收敛

**问题**: 仿真运行超时
- 检查状态机是否有死锁
- 添加超时保护机制
- 减小测试数据规模

## 8. 性能评估

### 8.1 资源使用报告解读

打开 `utilization_post_route.rpt`:

```
+----------------------------+--------+-------+------------+
|         Site Type          |  Used  | Avail | Utilization|
+----------------------------+--------+-------+------------+
| Slice LUTs                 | 78543  | 274080|    28.65%  |
| Slice Registers            | 116234 | 548160|    21.20%  |
| Block RAM Tile             | 148    | 912   |    16.23%  |
| DSPs                       | 196    | 2520  |     7.78%  |
+----------------------------+--------+-------+------------+
```

### 8.2 时序报告分析

关键指标：
- **WNS (Worst Negative Slack)**: 应 ≥ 0
- **TNS (Total Negative Slack)**: 应 = 0
- **WHS (Worst Hold Slack)**: 应 ≥ 0

### 8.3 功耗估算

从 `power_post_route.rpt` 中查看：
- 动态功耗
- 静态功耗
- 总功耗

## 9. 调试技巧

### 9.1 使用ILA (Integrated Logic Analyzer)

在RTL中插入调试核：

```tcl
# 创建ILA IP
create_ip -name ila -vendor xilinx.com -library ip -module_name ila_0

# 配置探针数量和深度
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {8} \
    CONFIG.C_DATA_DEPTH {4096} \
] [get_ips ila_0]
```

### 9.2 使用VIO (Virtual I/O)

运行时控制和观察：

```tcl
create_ip -name vio -vendor xilinx.com -library ip -module_name vio_0
```

### 9.3 打印调试信息

在testbench中使用 `$display`:

```verilog
$display("Time=%0t: State=%d, Result=%h", $time, state, result);
```

## 10. 量产验证流程

1. **功能验证**: 所有testbench通过
2. **时序收敛**: 无时序违例
3. **资源检查**: 利用率 < 80%
4. **功耗评估**: 满足散热要求
5. **板级测试**: 在目标硬件上验证
6. **压力测试**: 长时间运行稳定性
7. **温度测试**: 不同温度下性能
8. **批量测试**: 多块板卡一致性

---

**注意事项**:
- 仿真和综合结果可能存在差异
- 建议使用门级仿真验证时序
- 关键路径需要特别关注
- 定期备份工程文件

**技术支持**:
- 参考Xilinx UG文档
- 访问Xilinx社区论坛
- 查阅本项目GitHub Issues

---

**文档版本**: 1.0  
**最后更新**: 2026-02-12  
**适用Vivado版本**: 2020.2 ~ 2023.2
