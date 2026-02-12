/*******************************************************************************
* Module: fixed_point_add
* Description: 定点数加法器，支持可配置位宽
* Author: AI Hardware Accelerator Engineer
* Date: 2026-02-12
*******************************************************************************/

module fixed_point_add #(
    parameter DATA_WIDTH = 16
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     en,
    input  wire [DATA_WIDTH-1:0]    a,
    input  wire [DATA_WIDTH-1:0]    b,
    output reg  [DATA_WIDTH-1:0]    result,
    output reg                      valid
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result <= 0;
            valid <= 0;
        end else if (en) begin
            result <= $signed(a) + $signed(b);
            valid <= 1'b1;
        end else begin
            valid <= 1'b0;
        end
    end

endmodule
