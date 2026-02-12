# LLM硬件加速器设计文档

## 1. 项目概述

本项目实现了一个基于Verilog的最小可行LLM硬件加速器，专注于Transformer架构的两个核心计算模块：
- **注意力机制加速器** (Attention Accelerator)
- **前馈网络加速器** (Feed-Forward Network Accelerator)

### 1.1 设计目标

- **工业级质量**：遵循硬件编码规范，支持Vivado综合与仿真
- **模块化设计**：清晰的层次结构，便于扩展和维护
- **资源优化**：采用权重静止(Weight-Stationary)数据流，最大化数据复用
- **可配置性**：参数化设计，支持不同规模的模型

### 1.2 技术特性

- 定点数运算 (Q8.8格式：8位整数 + 8位小数)
- 脉动阵列矩阵乘法器
- 在线Softmax算法（减少内存占用）
- GELU激活函数硬件实现
- AXI4-Lite配置接口
- 支持因果掩码（Causal Masking）用于自回归生成

## 2. 架构设计

### 2.1 系统架构图

```
┌─────────────────────────────────────────────────────────────┐
│                  llm_accelerator_top                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐         ┌──────────────┐                │
│  │  AXI4-Lite   │         │   Control    │                │
│  │   Slave      ├────────►│   Registers  │                │
│  └──────────────┘         └──────┬───────┘                │
│                                   │                         │
│         ┌─────────────────────────┴─────────────┐          │
│         │                                       │          │
│  ┌──────▼──────┐                     ┌─────────▼──────┐   │
│  │  Attention  │                     │   FFN Layer    │   │
│  │    Core     │                     │  Accelerator   │   │
│  └─────────────┘                     └────────────────┘   │
│         │                                       │          │
│         └───────────────┬───────────────────────┘          │
│                         │                                   │
│                  ┌──────▼──────┐                           │
│                  │  Systolic   │                           │
│                  │   Array     │                           │
│                  └─────────────┘                           │
│                         │                                   │
│                  ┌──────▼──────┐                           │
│                  │   MAC Unit  │                           │
│                  └─────────────┘                           │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 模块层次结构

```
rtl/
├── top/
│   └── llm_accelerator_top.v      # 顶层模块
├── attention/
│   └── attention_core.v            # 注意力机制核心
├── ffn/
│   └── ffn_layer.v                 # 前馈网络层
├── memory/
│   └── axi4_lite_slave.v          # AXI4-Lite从设备接口
└── utils/
    ├── mac_unit.v                  # 乘加累加单元
    ├── systolic_array.v           # 脉动阵列
    ├── softmax_unit.v             # Softmax计算单元
    ├── activation_gelu.v          # GELU激活函数
    ├── fixed_point_mult.v         # 定点乘法器
    └── fixed_point_add.v          # 定点加法器
```

## 3. 核心模块说明

### 3.1 注意力机制加速器 (attention_core.v)

**功能**: 实现多头自注意力计算 `Attention(Q,K,V) = softmax(QK^T/√d_k) * V`

**关键特性**:
- 支持因果掩码（自回归生成）
- 状态机控制：IDLE → CALC_QK → SCALE_QK → APPLY_MASK → CALC_SOFTMAX → CALC_ATTN_V → DONE
- 内部存储QK^T矩阵和注意力分数
- 集成MAC单元用于点积计算
- 集成Softmax单元用于归一化

**参数**:
- `SEQ_LEN`: 序列长度 (默认: 8)
- `HEAD_DIM`: 每个头的维度 (默认: 64)
- `NUM_HEADS`: 注意力头数量 (默认: 4)

### 3.2 前馈网络加速器 (ffn_layer.v)

**功能**: 实现 `FFN(x) = GELU(xW1 + b1)W2 + b2`

**关键特性**:
- 两层全连接网络
- GELU激活函数
- 权重加载接口
- 流水线处理

**参数**:
- `INPUT_DIM`: 输入维度 (默认: 512)
- `HIDDEN_DIM`: 隐藏层维度 (默认: 2048)
- `OUTPUT_DIM`: 输出维度 (默认: 512)

### 3.3 脉动阵列 (systolic_array.v)

**功能**: 权重静止型脉动阵列矩阵乘法器

**架构特点**:
- Weight-Stationary数据流
- 权重预加载到PE寄存器
- 激活值从左向右流动
- 部分和从上向下累加

**PE (Processing Element)**:
- 存储权重
- 执行乘加操作
- 传递激活值和部分和

### 3.4 MAC单元 (mac_unit.v)

**功能**: 向量点积计算

**实现**:
```verilog
result = a[0]*b[0] + a[1]*b[1] + ... + a[n-1]*b[n-1]
```

**特性**:
- 可配置向量大小
- 可选累加器清零
- 定点数自动缩放

### 3.5 Softmax单元 (softmax_unit.v)

**功能**: 在线Softmax算法

**算法步骤**:
1. 找到最大值 (数值稳定性)
2. 计算 exp(x - max)
3. 求和归一化
4. 除法得到概率分布

**近似方法**:
- 指数函数：分段线性近似
- 除法：查找表或迭代算法

## 4. 接口规范

### 4.1 AXI4-Lite寄存器映射

| 地址 | 名称 | 访问 | 描述 |
|------|------|------|------|
| 0x00 | CONTROL | R/W | 控制寄存器 |
| 0x04 | CONFIG | R/W | 配置寄存器 |
| 0x08 | STATUS | R | 状态寄存器 |

**CONTROL寄存器位定义**:
- [0]: attn_start - 启动注意力计算
- [1]: ffn_start - 启动FFN计算
- [2]: causal_mask_en - 使能因果掩码
- [3]: weight_load_mode - 权重加载模式

**STATUS寄存器位定义**:
- [0]: attn_busy - 注意力计算忙
- [1]: ffn_busy - FFN计算忙
- [2]: attn_valid - 注意力计算完成
- [3]: ffn_valid - FFN计算完成

### 4.2 顶层模块端口

```verilog
module llm_accelerator_top (
    // 时钟和复位
    input  wire         clk,
    input  wire         rst_n,
    
    // AXI4-Lite配置接口
    input  wire [31:0]  s_axi_awaddr,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,
    // ... 其他AXI信号
    
    // 状态输出
    output wire         interrupt,
    output wire         busy,
    output wire         attn_valid,
    output wire         ffn_valid
);
```

## 5. 数据格式

### 5.1 定点数表示 (Q8.8)

- 总位宽：16位
- 整数部分：8位（包含1位符号位）
- 小数部分：8位
- 表示范围：-128.0 ~ 127.996
- 精度：1/256 ≈ 0.0039

**示例**:
- `0x0100` = 1.0
- `0x0080` = 0.5
- `0xFF00` = -1.0
- `0x0001` = 0.0039

### 5.2 向量打包

向量按小端序打包到总线：
```
vector[N-1:0] → bus[(N*WIDTH-1):0]
vector[i] = bus[(i*WIDTH+WIDTH-1):(i*WIDTH)]
```

## 6. 性能分析

### 6.1 计算复杂度

**注意力机制**:
- QK^T计算: O(L²·d) FLOPS
- Softmax: O(L²) FLOPS  
- 注意力加权: O(L²·d) FLOPS
- 总计: O(2L²·d) FLOPS

**FFN层**:
- 第一层: O(d·h) FLOPS
- 第二层: O(h·d) FLOPS
- 总计: O(2d·h) FLOPS

其中 L=序列长度, d=模型维度, h=隐藏层维度

### 6.2 资源估算

基于Xilinx FPGA (以Zynq UltraScale+ ZU9EG为例):

| 资源 | 使用量估算 | 总量 | 占用率 |
|------|-----------|------|--------|
| LUT | ~80K | 274K | ~29% |
| FF | ~120K | 548K | ~22% |
| BRAM | ~150 | 912 | ~16% |
| DSP | ~200 | 2520 | ~8% |

*注：实际资源使用取决于参数配置和综合优化*

### 6.3 时序分析

**关键路径**:
- MAC单元乘法器
- Softmax指数计算
- 状态机控制逻辑

**目标频率**: 100-200 MHz

## 7. 设计考虑

### 7.1 数值稳定性

- Softmax使用减最大值技巧防止溢出
- 定点数乘法自动缩放小数位
- 累加器使用扩展位宽防止溢出

### 7.2 内存优化

- 脉动阵列复用权重，减少内存访问
- 在线Softmax算法，避免存储完整QK^T矩阵
- 权重存储可映射到片外DDR（通过AXI总线）

### 7.3 可扩展性

- 参数化设计，易于调整规模
- 模块化结构，可独立使用或组合
- 标准AXI接口，易于集成到SoC

## 8. 下一步优化方向

### 8.1 性能优化

- [ ] 实现FlashAttention分块算法
- [ ] 添加INT8/INT4量化支持
- [ ] 多头并行处理
- [ ] 流水线优化

### 8.2 功能扩展

- [ ] KV Cache管理
- [ ] 支持GQA (Grouped Query Attention)
- [ ] RoPE位置编码硬件加速
- [ ] LayerNorm/RMSNorm单元

### 8.3 系统集成

- [ ] AXI4 Stream数据接口
- [ ] DMA控制器
- [ ] 多核互联
- [ ] PS-PL协同设计（Zynq平台）

## 9. 参考文献

1. Vaswani et al. "Attention Is All You Need." NeurIPS 2017.
2. Dao et al. "FlashAttention: Fast and Memory-Efficient Exact Attention." NeurIPS 2022.
3. Jouppi et al. "In-Datacenter Performance Analysis of a Tensor Processing Unit." ISCA 2017.
4. Xilinx UltraScale Architecture DSP Slice User Guide (UG579)
5. AMBA AXI4-Lite Protocol Specification

---

**文档版本**: 1.0  
**最后更新**: 2026-02-12  
**作者**: AI Hardware Accelerator Engineer
