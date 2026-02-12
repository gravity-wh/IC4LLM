/*******************************************************************************
* Module: activation_gelu
* Description: GELU激活函数近似实现 (基于tanh近似)
*              GELU(x) ≈ 0.5 * x * (1 + tanh(√(2/π) * (x + 0.044715 * x³)))
* Author: AI Hardware Accelerator Engineer
* Date: 2026-02-12
*******************************************************************************/

module activation_gelu #(
    parameter DATA_WIDTH = 16,
    parameter FRAC_WIDTH = 8
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     en,
    input  wire [DATA_WIDTH-1:0]    x_in,
    output reg  [DATA_WIDTH-1:0]    y_out,
    output reg                      valid
);

    // 使用分段线性近似(PLU)实现GELU
    // 将输入分为多个区间，每个区间用线性函数近似
    
    reg signed [DATA_WIDTH-1:0] x_abs;
    reg signed [DATA_WIDTH-1:0] y_temp;
    wire sign_bit;
    
    assign sign_bit = x_in[DATA_WIDTH-1];
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_abs <= 0;
            y_temp <= 0;
            y_out <= 0;
            valid <= 0;
        end else if (en) begin
            // 取绝对值
            x_abs <= sign_bit ? -$signed(x_in) : $signed(x_in);
            
            // 分段线性近似
            // x < -3: y ≈ 0
            // -3 < x < -1: y ≈ 0.05x
            // -1 < x < 1: y ≈ 0.5x
            // 1 < x < 3: y ≈ 0.95x
            // x > 3: y ≈ x
            
            if (x_abs > (3 << FRAC_WIDTH)) begin
                y_temp <= x_in; // y = x
            end else if (x_abs > (1 << FRAC_WIDTH)) begin
                y_temp <= ($signed(x_in) * $signed(16'h00F3)) >>> 8; // y ≈ 0.95x
            end else begin
                y_temp <= ($signed(x_in) * $signed(16'h0080)) >>> 8; // y ≈ 0.5x
            end
            
            y_out <= y_temp;
            valid <= 1'b1;
        end else begin
            valid <= 1'b0;
        end
    end

endmodule
