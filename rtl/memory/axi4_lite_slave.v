/*******************************************************************************
* Module: axi4_lite_slave
* Description: AXI4-Lite从设备接口，用于配置寄存器访问
*              支持32位数据和地址总线
* Author: AI Hardware Accelerator Engineer
* Date: 2026-02-12
*******************************************************************************/

module axi4_lite_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    // 全局信号
    input  wire                     aclk,
    input  wire                     aresetn,
    
    // 写地址通道
    input  wire [ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire [2:0]               s_axi_awprot,
    input  wire                     s_axi_awvalid,
    output reg                      s_axi_awready,
    
    // 写数据通道
    input  wire [DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0]  s_axi_wstrb,
    input  wire                     s_axi_wvalid,
    output reg                      s_axi_wready,
    
    // 写响应通道
    output reg  [1:0]               s_axi_bresp,
    output reg                      s_axi_bvalid,
    input  wire                     s_axi_bready,
    
    // 读地址通道
    input  wire [ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire [2:0]               s_axi_arprot,
    input  wire                     s_axi_arvalid,
    output reg                      s_axi_arready,
    
    // 读数据通道
    output reg  [DATA_WIDTH-1:0]    s_axi_rdata,
    output reg  [1:0]               s_axi_rresp,
    output reg                      s_axi_rvalid,
    input  wire                     s_axi_rready,
    
    // 用户接口 - 寄存器
    output reg  [DATA_WIDTH-1:0]    reg_control,
    output reg  [DATA_WIDTH-1:0]    reg_config,
    input  wire [DATA_WIDTH-1:0]    reg_status,
    output reg                      reg_write_pulse
);

    // AXI4-Lite 响应类型
    localparam RESP_OKAY   = 2'b00;
    localparam RESP_EXOKAY = 2'b01;
    localparam RESP_SLVERR = 2'b10;
    localparam RESP_DECERR = 2'b11;
    
    // 寄存器地址映射
    localparam ADDR_CONTROL = 32'h00000000;
    localparam ADDR_CONFIG  = 32'h00000004;
    localparam ADDR_STATUS  = 32'h00000008;
    
    // 内部寄存器
    reg [ADDR_WIDTH-1:0] write_addr;
    reg [ADDR_WIDTH-1:0] read_addr;
    
    // 写事务处理
    always @(posedge aclk) begin
        if (!aresetn) begin
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp <= RESP_OKAY;
            write_addr <= 0;
            reg_control <= 0;
            reg_config <= 0;
            reg_write_pulse <= 1'b0;
        end else begin
            reg_write_pulse <= 1'b0;
            
            // 写地址握手
            if (s_axi_awvalid && !s_axi_awready) begin
                s_axi_awready <= 1'b1;
                write_addr <= s_axi_awaddr;
            end else begin
                s_axi_awready <= 1'b0;
            end
            
            // 写数据握手
            if (s_axi_wvalid && !s_axi_wready) begin
                s_axi_wready <= 1'b1;
                
                // 写入寄存器
                case (write_addr)
                    ADDR_CONTROL: reg_control <= s_axi_wdata;
                    ADDR_CONFIG:  reg_config <= s_axi_wdata;
                    default: ; // 未定义地址
                endcase
                
                reg_write_pulse <= 1'b1;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp <= RESP_OKAY;
            end else begin
                s_axi_wready <= 1'b0;
            end
            
            // 写响应握手
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end
    
    // 读事务处理
    always @(posedge aclk) begin
        if (!aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid <= 1'b0;
            s_axi_rdata <= 0;
            s_axi_rresp <= RESP_OKAY;
            read_addr <= 0;
        end else begin
            // 读地址握手
            if (s_axi_arvalid && !s_axi_arready) begin
                s_axi_arready <= 1'b1;
                read_addr <= s_axi_araddr;
                
                // 读取寄存器
                case (s_axi_araddr)
                    ADDR_CONTROL: s_axi_rdata <= reg_control;
                    ADDR_CONFIG:  s_axi_rdata <= reg_config;
                    ADDR_STATUS:  s_axi_rdata <= reg_status;
                    default:      s_axi_rdata <= 32'hDEADBEEF;
                endcase
                
                s_axi_rvalid <= 1'b1;
                s_axi_rresp <= RESP_OKAY;
            end else begin
                s_axi_arready <= 1'b0;
            end
            
            // 读数据握手
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
