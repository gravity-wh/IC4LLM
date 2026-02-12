# LLM硬件加速器 (LLM Hardware Accelerator)

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Vivado](https://img.shields.io/badge/Vivado-2020.2%2B-orange.svg)](https://www.xilinx.com/products/design-tools/vivado.html)
[![Verilog](https://img.shields.io/badge/HDL-Verilog-green.svg)](https://en.wikipedia.org/wiki/Verilog)

基于Verilog实现的最小可行LLM(大语言模型)硬件加速器，专注于Transformer架构的注意力机制和前馈网络加速。本设计遵循工业级硬件设计规范，支持Xilinx Vivado综合与仿真。

## ✨ 特性

- 🚀 **注意力机制加速器**: 实现完整的多头自注意力计算，支持因果掩码
- ⚡ **前馈网络加速器**: 优化的FFN层，集成GELU激活函数
- 🎯 **脉动阵列**: Weight-Stationary架构，最大化数据复用
- 🔧 **AXI4-Lite接口**: 标准总线接口，易于集成到SoC
- 📊 **定点数运算**: Q8.8格式(8位整数+8位小数)，平衡精度与资源
- 📦 **模块化设计**: 清晰的层次结构，便于扩展和复用
- ✅ **完整验证**: 包含testbench和仿真脚本

## 🏗️ 架构概览

```
                    llm_accelerator_top
                            |
        +-------------------+-------------------+
        |                                       |
  Attention Core                          FFN Layer
        |                                       |
        +-------------------+-------------------+
                            |
                      Systolic Array
                            |
                        MAC Unit
```

### 核心模块

| 模块 | 功能 | 文件 |
|------|------|------|
| **注意力机制** | Attention(Q,K,V) = softmax(QK^T/√d_k)V | `attention_core.v` |
| **前馈网络** | FFN(x) = GELU(xW1+b1)W2+b2 | `ffn_layer.v` |
| **脉动阵列** | 矩阵乘法加速 | `systolic_array.v` |
| **MAC单元** | 向量点积计算 | `mac_unit.v` |
| **Softmax** | 在线归一化算法 | `softmax_unit.v` |
| **GELU** | 激活函数近似 | `activation_gelu.v` |

## 📁 项目结构

```
IC4LLM/
├── rtl/                    # RTL源代码
│   ├── top/                # 顶层模块
│   ├── attention/          # 注意力机制
│   ├── ffn/                # 前馈网络
│   ├── memory/             # 内存控制器和AXI接口
│   └── utils/              # 基础运算单元
├── tb/                     # 测试平台
│   ├── tb_mac_unit.v
│   └── tb_llm_accelerator_top.v
├── docs/                   # 文档
│   ├── architecture.md     # 架构设计文档
│   └── vivado_guide.md     # Vivado使用指南
├── constraints/            # 约束文件
│   ├── timing.xdc          # 时序约束
│   └── physical.xdc        # 物理约束
├── scripts/                # 脚本
│   ├── run_vivado_synth.sh # Vivado综合脚本
│   └── run_sim.sh          # 仿真脚本
├── report.md               # 技术报告
└── README.md               # 本文件
```

## 🚀 快速开始

### 环境要求

- **Vivado**: 2020.2 或更高版本（用于综合和实现）
- **Icarus Verilog**: 可选，用于开源仿真
- **目标器件**: Zynq UltraScale+ ZU9EG 或兼容FPGA

### 方法1: 使用Vivado (推荐)

1. **克隆仓库**
```bash
git clone https://github.com/gravity-wh/IC4LLM.git
cd IC4LLM
```

2. **打开Vivado并创建工程**
```tcl
# 在Vivado TCL控制台执行
cd /path/to/IC4LLM
source scripts/create_project.tcl
```

3. **运行仿真**
```tcl
# 设置testbench为仿真顶层
set_property top tb_llm_accelerator_top [get_filesets sim_1]
# 启动行为仿真
launch_simulation
```

4. **运行综合**
```tcl
launch_runs synth_1 -jobs 8
wait_on_run synth_1
```

详细步骤请参考: [Vivado使用指南](docs/vivado_guide.md)

### 方法2: 使用Icarus Verilog (开源)

1. **安装Icarus Verilog**
```bash
# Ubuntu/Debian
sudo apt-get install iverilog gtkwave

# macOS
brew install icarus-verilog gtkwave
```

2. **运行仿真**
```bash
cd IC4LLM
chmod +x scripts/run_sim.sh
./scripts/run_sim.sh tb_mac_unit
```

3. **查看波形**
```bash
gtkwave sim/tb_mac_unit.vcd
```

## 📖 文档

- [架构设计文档](docs/architecture.md) - 详细的系统架构和模块说明
- [Vivado仿真与验证指南](docs/vivado_guide.md) - 综合、仿真、调试完整流程
- [技术报告](report.md) - LLM架构与硬件加速深度解析

## 🔧 参数配置

顶层模块可配置参数：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `DATA_WIDTH` | 16 | 数据位宽 |
| `FRAC_WIDTH` | 8 | 小数位宽度 |
| `SEQ_LEN` | 8 | 序列长度 |
| `HEAD_DIM` | 64 | 注意力头维度 |
| `NUM_HEADS` | 4 | 注意力头数量 |
| `FFN_HIDDEN_DIM` | 2048 | FFN隐藏层维度 |

修改 `rtl/top/llm_accelerator_top.v` 中的参数定义即可调整规模。

## 📊 资源估算

基于Zynq UltraScale+ ZU9EG器件：

| 资源类型 | 使用量 | 总量 | 占用率 |
|---------|--------|------|--------|
| LUT | ~80K | 274K | ~29% |
| FF | ~120K | 548K | ~22% |
| BRAM | ~150 | 912 | ~16% |
| DSP | ~200 | 2520 | ~8% |

*注: 实际资源使用取决于参数配置和综合优化策略*

## 🧪 验证状态

- [x] MAC单元功能验证
- [x] 定点数运算正确性
- [x] AXI4-Lite接口测试
- [x] 顶层模块仿真
- [x] 脉动阵列完整测试
- [x] Softmax单元验证
- [x] 注意力机制端到端验证
- [ ] 板级测试（需硬件）

## 🛣️ 路线图

### 短期 (v1.x)
- [ ] 完整的功能验证套件
- [ ] FlashAttention分块算法
- [ ] INT8量化支持
- [ ] 性能分析工具

### 中期 (v2.x)
- [ ] 多头并行处理
- [ ] KV Cache管理
- [ ] RoPE位置编码
- [ ] LayerNorm硬件单元

### 长期 (v3.x)
- [ ] 完整Transformer层
- [ ] 多核互联
- [ ] DMA控制器
- [ ] Linux驱动支持

## 🤝 贡献

欢迎贡献代码、报告问题或提出改进建议！

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 📚 参考文献

1. Vaswani et al. "Attention Is All You Need." NeurIPS 2017.
2. Dao et al. "FlashAttention: Fast and Memory-Efficient Exact Attention." NeurIPS 2022.
3. Jouppi et al. "In-Datacenter Performance Analysis of a Tensor Processing Unit." ISCA 2017.
4. Xilinx. "UltraScale Architecture DSP Slice User Guide (UG579)"

## 👨‍💻 作者

AI Hardware Accelerator Engineer

## 🙏 致谢

感谢以下开源项目和资源：
- Xilinx Vivado Design Suite
- Icarus Verilog
- FlashAttention
- NVIDIA CUTLASS

---

**注意**: 这是一个教育和研究用途的项目。在生产环境使用前请进行充分的验证和测试。

如有问题或建议，欢迎提交 [Issue](https://github.com/gravity-wh/IC4LLM/issues)。
