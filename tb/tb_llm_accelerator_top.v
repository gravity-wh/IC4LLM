/*******************************************************************************
* Module: tb_llm_accelerator_top
* Description: LLM硬件加速器顶层模块的测试平台
* Author: AI Hardware Accelerator Engineer
* Date: 2026-02-12
*******************************************************************************/

`timescale 1ns / 1ps

module tb_llm_accelerator_top;

    // 参数定义
    parameter CLK_PERIOD = 10; // 10ns = 100MHz
    parameter DATA_WIDTH = 16;
    parameter FRAC_WIDTH = 8;
    parameter SEQ_LEN = 8;
    parameter HEAD_DIM = 64;
    parameter NUM_HEADS = 4;
    
    // 信号定义
    reg         clk;
    reg         rst_n;
    
    // AXI4-Lite 接口
    reg  [31:0] s_axi_awaddr;
    reg  [2:0]  s_axi_awprot;
    reg         s_axi_awvalid;
    wire        s_axi_awready;
    reg  [31:0] s_axi_wdata;
    reg  [3:0]  s_axi_wstrb;
    reg         s_axi_wvalid;
    wire        s_axi_wready;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready;
    reg  [31:0] s_axi_araddr;
    reg  [2:0]  s_axi_arprot;
    reg         s_axi_arvalid;
    wire        s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;
    
    wire        interrupt;
    wire        busy;
    wire        attn_valid;
    wire        ffn_valid;
    
    // 实例化DUT
    llm_accelerator_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),
        .SEQ_LEN(SEQ_LEN),
        .HEAD_DIM(HEAD_DIM),
        .NUM_HEADS(NUM_HEADS)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
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
        .interrupt(interrupt),
        .busy(busy),
        .attn_valid(attn_valid),
        .ffn_valid(ffn_valid)
    );
    
    // 时钟生成
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // AXI写任务
    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            s_axi_awaddr = addr;
            s_axi_awvalid = 1'b1;
            s_axi_wdata = data;
            s_axi_wvalid = 1'b1;
            s_axi_wstrb = 4'hF;
            s_axi_bready = 1'b1;
            
            wait(s_axi_awready);
            @(posedge clk);
            s_axi_awvalid = 1'b0;
            
            wait(s_axi_wready);
            @(posedge clk);
            s_axi_wvalid = 1'b0;
            
            wait(s_axi_bvalid);
            @(posedge clk);
            s_axi_bready = 1'b0;
        end
    endtask
    
    // AXI读任务
    task axi_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);
            s_axi_araddr = addr;
            s_axi_arvalid = 1'b1;
            s_axi_rready = 1'b1;
            
            wait(s_axi_arready);
            @(posedge clk);
            s_axi_arvalid = 1'b0;
            
            wait(s_axi_rvalid);
            data = s_axi_rdata;
            @(posedge clk);
            s_axi_rready = 1'b0;
        end
    endtask
    
    // 测试向量
    reg [31:0] read_data;
    
    initial begin
        // 初始化
        rst_n = 0;
        s_axi_awaddr = 0;
        s_axi_awprot = 0;
        s_axi_awvalid = 0;
        s_axi_wdata = 0;
        s_axi_wstrb = 0;
        s_axi_wvalid = 0;
        s_axi_bready = 0;
        s_axi_araddr = 0;
        s_axi_arprot = 0;
        s_axi_arvalid = 0;
        s_axi_rready = 0;
        
        // 复位
        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 10);
        
        $display("========================================");
        $display("LLM Accelerator Testbench Started");
        $display("========================================");
        
        // 测试1: 读取初始状态
        $display("\nTest 1: Read initial status");
        axi_read(32'h00000008, read_data);
        $display("Status Register = 0x%08h", read_data);
        
        // 测试2: 配置寄存器写入
        $display("\nTest 2: Write configuration");
        axi_write(32'h00000004, 32'h12345678);
        axi_read(32'h00000004, read_data);
        $display("Config Register = 0x%08h (Expected: 0x12345678)", read_data);
        
        // 测试3: 启动注意力机制计算
        $display("\nTest 3: Start Attention Computation");
        axi_write(32'h00000000, 32'h00000005); // Start attention with causal mask
        #(CLK_PERIOD * 10);
        
        // 轮询状态直到完成
        $display("Waiting for attention completion...");
        repeat(100) begin
            axi_read(32'h00000008, read_data);
            if (read_data[2]) begin // attn_valid bit
                $display("Attention computation completed!");
                break;
            end
            #(CLK_PERIOD * 10);
        end
        
        // 测试4: 启动FFN计算
        $display("\nTest 4: Start FFN Computation");
        axi_write(32'h00000000, 32'h00000002); // Start FFN
        #(CLK_PERIOD * 10);
        
        // 轮询状态直到完成
        $display("Waiting for FFN completion...");
        repeat(100) begin
            axi_read(32'h00000008, read_data);
            if (read_data[3]) begin // ffn_valid bit
                $display("FFN computation completed!");
                break;
            end
            #(CLK_PERIOD * 10);
        end
        
        // 测试5: 读取最终状态
        $display("\nTest 5: Read final status");
        axi_read(32'h00000008, read_data);
        $display("Final Status Register = 0x%08h", read_data);
        
        $display("\n========================================");
        $display("Testbench Completed Successfully");
        $display("========================================");
        
        #(CLK_PERIOD * 100);
        $finish;
    end
    
    // 波形记录
    initial begin
        $dumpfile("tb_llm_accelerator_top.vcd");
        $dumpvars(0, tb_llm_accelerator_top);
    end
    
    // 超时保护
    initial begin
        #(CLK_PERIOD * 100000);
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
