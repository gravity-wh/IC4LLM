/*******************************************************************************
* Module: tb_mac_unit
* Description: MAC单元的测试平台
* Author: AI Hardware Accelerator Engineer
* Date: 2026-02-12
*******************************************************************************/

`timescale 1ns / 1ps

module tb_mac_unit;

    parameter CLK_PERIOD = 10;
    parameter DATA_WIDTH = 16;
    parameter FRAC_WIDTH = 8;
    parameter VEC_SIZE = 4;
    
    reg                             clk;
    reg                             rst_n;
    reg                             en;
    reg                             clear_acc;
    reg  [VEC_SIZE*DATA_WIDTH-1:0]  a_vec;
    reg  [VEC_SIZE*DATA_WIDTH-1:0]  b_vec;
    wire [DATA_WIDTH-1:0]           result;
    wire                            valid;
    
    // 实例化DUT
    mac_unit #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),
        .VEC_SIZE(VEC_SIZE)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .clear_acc(clear_acc),
        .a_vec(a_vec),
        .b_vec(b_vec),
        .result(result),
        .valid(valid)
    );
    
    // 时钟生成
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // 测试向量
    integer i;
    reg signed [DATA_WIDTH-1:0] a_array [0:VEC_SIZE-1];
    reg signed [DATA_WIDTH-1:0] b_array [0:VEC_SIZE-1];
    real expected_result;
    
    initial begin
        // 初始化
        rst_n = 0;
        en = 0;
        clear_acc = 1;
        a_vec = 0;
        b_vec = 0;
        
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 5);
        
        $display("========================================");
        $display("MAC Unit Testbench Started");
        $display("========================================");
        
        // 测试1: 简单点积
        $display("\nTest 1: Simple dot product");
        // a = [1.0, 2.0, 3.0, 4.0]
        // b = [0.5, 0.5, 0.5, 0.5]
        // 期望结果 = 1*0.5 + 2*0.5 + 3*0.5 + 4*0.5 = 5.0
        a_array[0] = 16'h0100; // 1.0 in Q8.8
        a_array[1] = 16'h0200; // 2.0
        a_array[2] = 16'h0300; // 3.0
        a_array[3] = 16'h0400; // 4.0
        
        b_array[0] = 16'h0080; // 0.5 in Q8.8
        b_array[1] = 16'h0080; // 0.5
        b_array[2] = 16'h0080; // 0.5
        b_array[3] = 16'h0080; // 0.5
        
        for (i = 0; i < VEC_SIZE; i = i + 1) begin
            a_vec[i*DATA_WIDTH +: DATA_WIDTH] = a_array[i];
            b_vec[i*DATA_WIDTH +: DATA_WIDTH] = b_array[i];
        end
        
        clear_acc = 1;
        en = 1;
        #CLK_PERIOD;
        
        wait(valid);
        $display("Result = 0x%04h (%.2f)", result, $signed(result) / 256.0);
        $display("Expected ≈ 5.0");
        
        // 测试2: 负数计算
        $display("\nTest 2: Negative numbers");
        a_array[0] = 16'hFF00; // -1.0
        a_array[1] = 16'h0100; //  1.0
        a_array[2] = 16'hFF00; // -1.0
        a_array[3] = 16'h0100; //  1.0
        
        b_array[0] = 16'h0100; //  1.0
        b_array[1] = 16'h0100; //  1.0
        b_array[2] = 16'h0100; //  1.0
        b_array[3] = 16'h0100; //  1.0
        
        for (i = 0; i < VEC_SIZE; i = i + 1) begin
            a_vec[i*DATA_WIDTH +: DATA_WIDTH] = a_array[i];
            b_vec[i*DATA_WIDTH +: DATA_WIDTH] = b_array[i];
        end
        
        clear_acc = 1;
        en = 1;
        #CLK_PERIOD;
        
        wait(valid);
        $display("Result = 0x%04h (%.2f)", result, $signed(result) / 256.0);
        $display("Expected = 0.0");
        
        #(CLK_PERIOD * 10);
        
        $display("\n========================================");
        $display("MAC Unit Test Completed");
        $display("========================================");
        
        $finish;
    end
    
    // 波形记录
    initial begin
        $dumpfile("tb_mac_unit.vcd");
        $dumpvars(0, tb_mac_unit);
    end

endmodule
