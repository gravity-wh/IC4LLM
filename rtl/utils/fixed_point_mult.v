/*******************************************************************************
* Module: fixed_point_mult
* Description: 定点数乘法器，支持可配置位宽和小数位
* Author: AI Hardware Accelerator Engineer
* Date: 2026-02-12
*******************************************************************************/

module fixed_point_mult #(
    parameter DATA_WIDTH = 16,      // 数据位宽
    parameter FRAC_WIDTH = 8        // 小数位宽度
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     en,
    input  wire [DATA_WIDTH-1:0]    a,
    input  wire [DATA_WIDTH-1:0]    b,
    output reg  [DATA_WIDTH-1:0]    result,
    output reg                      valid
);

    // 内部信号
    reg [2*DATA_WIDTH-1:0] mult_result;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mult_result <= 0;
            result <= 0;
            valid <= 0;
        end else if (en) begin
            // 有符号乘法
            mult_result <= $signed(a) * $signed(b);
            // 右移小数位，保留有效位
            result <= mult_result[DATA_WIDTH+FRAC_WIDTH-1:FRAC_WIDTH];
            valid <= 1'b1;
        end else begin
            valid <= 1'b0;
        end
    end

endmodule
