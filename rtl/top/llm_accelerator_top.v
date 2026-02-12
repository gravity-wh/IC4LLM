/*******************************************************************************
* Module: llm_accelerator_top
* Description: LLM硬件加速器顶层模块
*              集成注意力机制加速器和前馈网络加速器
*              提供AXI4-Lite配置接口
* Author: AI Hardware Accelerator Engineer
* Date: 2026-02-12
* Version: 1.0
*******************************************************************************/

module llm_accelerator_top #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_WIDTH = 8,
    parameter SEQ_LEN = 8,
    parameter HEAD_DIM = 64,
    parameter NUM_HEADS = 4,
    parameter FFN_INPUT_DIM = 512,
    parameter FFN_HIDDEN_DIM = 2048,
    parameter FFN_OUTPUT_DIM = 512
)(
    // 时钟和复位
    input  wire         clk,
    input  wire         rst_n,
    
    // AXI4-Lite 从设备接口（配置和控制）
    input  wire [31:0]  s_axi_awaddr,
    input  wire [2:0]   s_axi_awprot,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,
    input  wire [31:0]  s_axi_wdata,
    input  wire [3:0]   s_axi_wstrb,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,
    output wire [1:0]   s_axi_bresp,
    output wire         s_axi_bvalid,
    input  wire         s_axi_bready,
    input  wire [31:0]  s_axi_araddr,
    input  wire [2:0]   s_axi_arprot,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,
    output wire [31:0]  s_axi_rdata,
    output wire [1:0]   s_axi_rresp,
    output wire         s_axi_rvalid,
    input  wire         s_axi_rready,
    
    // 中断输出
    output wire         interrupt,
    
    // 状态指示
    output wire         busy,
    output wire         attn_valid,
    output wire         ffn_valid
);

    // 控制和状态寄存器
    wire [31:0] reg_control;
    wire [31:0] reg_config;
    wire [31:0] reg_status;
    wire        reg_write_pulse;
    
    // 控制位定义
    wire        attn_start;
    wire        ffn_start;
    wire        causal_mask_en;
    wire        weight_load_mode;
    
    assign attn_start = reg_control[0];
    assign ffn_start = reg_control[1];
    assign causal_mask_en = reg_control[2];
    assign weight_load_mode = reg_control[3];
    
    // 状态位定义
    wire        attn_busy;
    wire        ffn_busy;
    
    assign reg_status = {
        28'b0,
        ffn_valid,      // bit 3
        attn_valid,     // bit 2
        ffn_busy,       // bit 1
        attn_busy       // bit 0
    };
    
    assign busy = attn_busy | ffn_busy;
    assign interrupt = attn_valid | ffn_valid;
    
    // AXI4-Lite 从设备实例化
    axi4_lite_slave #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32)
    ) axi_slave_inst (
        .aclk(clk),
        .aresetn(rst_n),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awprot(s_axi_awprot),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arprot(s_axi_arprot),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .reg_control(reg_control),
        .reg_config(reg_config),
        .reg_status(reg_status),
        .reg_write_pulse(reg_write_pulse)
    );
    
    // 注意力机制加速器数据接口（简化：使用0输入进行功能验证）
    wire [SEQ_LEN*HEAD_DIM*DATA_WIDTH-1:0] attn_q_in;
    wire [SEQ_LEN*HEAD_DIM*DATA_WIDTH-1:0] attn_k_in;
    wire [SEQ_LEN*HEAD_DIM*DATA_WIDTH-1:0] attn_v_in;
    wire [SEQ_LEN*HEAD_DIM*DATA_WIDTH-1:0] attn_out;
    
    // 注意力机制加速器实例化
    attention_core #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),
        .SEQ_LEN(SEQ_LEN),
        .HEAD_DIM(HEAD_DIM),
        .NUM_HEADS(NUM_HEADS)
    ) attention_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(attn_start),
        .causal_mask_en(causal_mask_en),
        .q_in(attn_q_in),
        .k_in(attn_k_in),
        .v_in(attn_v_in),
        .attn_out(attn_out),
        .valid(attn_valid),
        .busy(attn_busy)
    );
    
    // FFN加速器数据接口
    wire [FFN_INPUT_DIM*DATA_WIDTH-1:0] ffn_x_in;
    wire [FFN_OUTPUT_DIM*DATA_WIDTH-1:0] ffn_y_out;
    wire ffn_weight_load_en;
    wire [1:0] ffn_weight_select;
    wire [DATA_WIDTH-1:0] ffn_weight_data;
    
    // FFN加速器实例化
    ffn_layer #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),
        .INPUT_DIM(FFN_INPUT_DIM),
        .HIDDEN_DIM(FFN_HIDDEN_DIM),
        .OUTPUT_DIM(FFN_OUTPUT_DIM)
    ) ffn_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(ffn_start),
        .weight_load_en(ffn_weight_load_en),
        .weight_select(ffn_weight_select),
        .weight_data(ffn_weight_data),
        .x_in(ffn_x_in),
        .y_out(ffn_y_out),
        .valid(ffn_valid),
        .busy(ffn_busy)
    );
    
    // 数据接口连接（简化版本，实际应连接到内存控制器或DMA）
    assign attn_q_in = {(SEQ_LEN*HEAD_DIM*DATA_WIDTH){1'b0}};
    assign attn_k_in = {(SEQ_LEN*HEAD_DIM*DATA_WIDTH){1'b0}};
    assign attn_v_in = {(SEQ_LEN*HEAD_DIM*DATA_WIDTH){1'b0}};
    assign ffn_x_in = {(FFN_INPUT_DIM*DATA_WIDTH){1'b0}};
    assign ffn_weight_load_en = weight_load_mode;
    assign ffn_weight_select = reg_config[1:0];
    assign ffn_weight_data = reg_config[DATA_WIDTH+15:16];

endmodule
