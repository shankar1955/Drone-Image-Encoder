module rle_encoder (
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, FREQ_HZ 24000000, PHASE 0.0, ASSOCIATED_RESET rst" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    input  wire clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
    input  wire rst,
    input  wire enable,
    input  wire start,

    // Input zigzag block
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME zigzag_stream_in, TDATA_NUM_BYTES 128, HAS_TREADY 0" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 zigzag_stream_in TDATA" *)
    input  wire [1023:0] block_in,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 zigzag_stream_in TVALID" *)
    input  wire block_valid,
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 block_ready DATA" *)
    output wire block_ready,

    // Output RLE pairs (run-length/value packed into 16-bit entries)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME rle_stream_out, TDATA_NUM_BYTES 128, HAS_TREADY 0" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 rle_stream_out TDATA" *)
    output reg  [1023:0] rle_out,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 rle_stream_out TVALID" *)
    output reg  rle_valid,
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 pair_count DATA" *)
    output reg  [6:0]     pair_count,
    output reg  done,

    // Status
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 busy DATA" *)
    output reg  busy
);

localparam integer NUM_SAMPLES = 64;
localparam integer MAX_PAIRS   = NUM_SAMPLES;

localparam [2:0] S_IDLE   = 3'd0;
localparam [2:0] S_WAIT   = 3'd1;
localparam [2:0] S_ENCODE = 3'd2;
localparam [2:0] S_FLUSH  = 3'd3;
localparam [2:0] S_OUTPUT = 3'd4;

reg [2:0] state;
reg [6:0] read_idx;
reg [6:0] write_idx;
reg [7:0] zero_run;
reg       flush_run_pending;

reg signed [15:0] coeff_array [0:NUM_SAMPLES-1];
reg       [15:0] pair_buffer [0:MAX_PAIRS-1];

integer i;

assign block_ready = (state == S_IDLE) && !busy;

function [7:0] saturate_to_int8;
    input signed [15:0] value;
begin
    if (value > 16'sd127)
        saturate_to_int8 = 8'h7F;
    else if (value < -16'sd128)
        saturate_to_int8 = 8'h80;
    else
        saturate_to_int8 = value[7:0];
end
endfunction

always @(posedge clk) begin
    if (rst) begin
        state             <= S_IDLE;
        read_idx          <= 7'd0;
        write_idx         <= 7'd0;
        zero_run          <= 8'd0;
        flush_run_pending <= 1'b0;
        pair_count        <= 7'd0;
        rle_out           <= {1024{1'b0}};
        rle_valid         <= 1'b0;
        done              <= 1'b0;
        busy              <= 1'b0;
        for (i = 0; i < NUM_SAMPLES; i = i + 1) begin
            coeff_array[i] <= 16'sd0;
        end
        for (i = 0; i < MAX_PAIRS; i = i + 1) begin
            pair_buffer[i] <= 16'd0;
        end
    end else begin
        rle_valid <= 1'b0;
        done      <= 1'b0;

        case (state)
            S_IDLE: begin
                busy <= 1'b0;
                if (start && enable) begin
                    busy <= 1'b1;
                    if (block_valid) begin
                        for (i = 0; i < NUM_SAMPLES; i = i + 1) begin
                            coeff_array[i] <= $signed(block_in[i*16 +: 16]);
                        end
                        for (i = 0; i < MAX_PAIRS; i = i + 1) begin
                            pair_buffer[i] <= 16'd0;
                        end
                        read_idx          <= 7'd0;
                        write_idx         <= 7'd0;
                        zero_run          <= 8'd0;
                        flush_run_pending <= 1'b0;
                        pair_count        <= 7'd0;
                        state             <= S_ENCODE;
                    end else begin
                        state <= S_WAIT;
                    end
                end
            end

            S_WAIT: begin
                busy <= 1'b1;
                if (block_valid) begin
                    for (i = 0; i < NUM_SAMPLES; i = i + 1) begin
                        coeff_array[i] <= $signed(block_in[i*16 +: 16]);
                    end
                    for (i = 0; i < MAX_PAIRS; i = i + 1) begin
                        pair_buffer[i] <= 16'd0;
                    end
                    read_idx          <= 7'd0;
                    write_idx         <= 7'd0;
                    zero_run          <= 8'd0;
                    flush_run_pending <= 1'b0;
                    pair_count        <= 7'd0;
                    state             <= S_ENCODE;
                end
            end

            S_ENCODE: begin
                busy <= 1'b1;
                if (enable) begin
                    if (read_idx < NUM_SAMPLES) begin
                        if (coeff_array[read_idx] == 16'sd0) begin
                            if (zero_run == 8'hFF) begin
                                pair_buffer[write_idx] <= {8'hFF, 8'h00};
                                write_idx              <= write_idx + 7'd1;
                                zero_run               <= 8'd1;
                            end else begin
                                zero_run <= zero_run + 8'd1;
                            end
                            read_idx <= read_idx + 7'd1;
                        end else begin
                            pair_buffer[write_idx] <= {zero_run, saturate_to_int8(coeff_array[read_idx])};
                            write_idx              <= write_idx + 7'd1;
                            zero_run               <= 8'd0;
                            read_idx               <= read_idx + 7'd1;
                        end
                    end else begin
                        flush_run_pending <= (zero_run != 8'd0);
                        state             <= S_FLUSH;
                    end
                end
            end

            S_FLUSH: begin
                busy <= 1'b1;
                if (flush_run_pending) begin
                    pair_buffer[write_idx] <= {zero_run, 8'h00};
                    write_idx              <= write_idx + 7'd1;
                    zero_run               <= 8'd0;
                    flush_run_pending      <= 1'b0;
                end else begin
                    pair_count             <= write_idx;
                    state                  <= S_OUTPUT;
                end
            end

            S_OUTPUT: begin
                busy <= 1'b0;
                for (i = 0; i < MAX_PAIRS; i = i + 1) begin
                    rle_out[i*16 +: 16] <= pair_buffer[i];
                end
                rle_valid <= 1'b1;
                done      <= 1'b1;
                state     <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
