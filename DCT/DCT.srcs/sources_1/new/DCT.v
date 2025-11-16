`timescale 1ns / 1ps

module dctcode #(
    parameter integer OUTPUT_SHIFT = 4
)(
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, FREQ_HZ 24000000, PHASE 0.0, ASSOCIATED_RESET rst" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    input wire clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
    input wire rst,
    input wire enable,
    input wire start,

    // Flattened 8x8 block input: 64 bytes = 512 bits
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME block_stream, TDATA_NUM_BYTES 64, HAS_TREADY 0" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 block_stream TDATA" *)
    input wire [511:0] block_in,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 block_stream TVALID" *)
    input wire block_valid,
    

    // Flattened 8x8 DCT output: 64 words (16-bit) = 1024 bits
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME coeff_stream, TDATA_NUM_BYTES 128, HAS_TREADY 0" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 coeff_stream TDATA" *)
    output reg [1023:0] dct_out,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 coeff_stream TVALID" *)
    output reg dct_valid,
    output reg done,

    // Status
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 busy DATA" *)
    output reg busy
);

localparam integer NUM_SAMPLES = 64;

localparam [1:0] ST_IDLE    = 2'd0;
localparam [1:0] ST_PROCESS = 2'd1;
localparam [1:0] ST_OUTPUT  = 2'd2;

reg [1:0] state;
reg [5:0] process_addr;
reg signed [15:0] working_data [0:NUM_SAMPLES-1];
integer i;

assign block_ready = (state == ST_IDLE) && !busy;

always @(posedge clk) begin
    if (rst) begin
        state <= ST_IDLE;
        process_addr <= 6'd0;
        dct_out <= {1024{1'b0}};
        dct_valid <= 1'b0;
        done <= 1'b0;
        busy <= 1'b0;
        for (i = 0; i < NUM_SAMPLES; i = i + 1) begin
            working_data[i] <= 16'sd0;
        end
    end else begin
        dct_valid <= 1'b0;
        done <= 1'b0;

        case (state)
            ST_IDLE: begin
                if (start && block_valid && block_ready && enable) begin
                    busy <= 1'b1;
                    for (i = 0; i < NUM_SAMPLES; i = i + 1) begin
                        working_data[i] <= {{8{block_in[i*8 + 7]}}, block_in[i*8 +: 8]} - 16'sd128;
                    end
                    process_addr <= 6'd0;
                    state <= ST_PROCESS;
                end else begin
                    busy <= 1'b0;
                end
            end

            ST_PROCESS: begin
                if (enable) begin
                    if (process_addr == 6'd0) begin
                        dct_out[15:0] <= (working_data[0] + working_data[7] + working_data[56] + working_data[63]) >>> OUTPUT_SHIFT;
                    end else begin
                        dct_out[process_addr*16 +: 16] <= working_data[process_addr];
                    end

                    if (process_addr == NUM_SAMPLES-1) begin
                        state <= ST_OUTPUT;
                    end else begin
                        process_addr <= process_addr + 6'd1;
                    end
                end
            end

            ST_OUTPUT: begin
                dct_valid <= 1'b1;
                done <= 1'b1;
                busy <= 1'b0;
                state <= ST_IDLE;
            end

            default: state <= ST_IDLE;
        endcase
    end
end

endmodule