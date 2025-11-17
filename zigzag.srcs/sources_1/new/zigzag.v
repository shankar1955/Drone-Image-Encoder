module zigzag (
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, FREQ_HZ 24000000, PHASE 0.0, ASSOCIATED_RESET rst" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    input  wire clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
    input  wire rst,
    input  wire enable,
    input  wire start,

    // 8x8 DCT block input (64 samples × 16 bits)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME coeff_stream_in, TDATA_NUM_BYTES 128, HAS_TREADY 0" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 coeff_stream_in TDATA" *)
    input  wire [1023:0] block_in,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 coeff_stream_in TVALID" *)
    input  wire block_valid,
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 block_ready DATA" *)
    output wire block_ready,

    // Zig-zag ordered output block
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME zigzag_stream_out, TDATA_NUM_BYTES 128, HAS_TREADY 0" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 zigzag_stream_out TDATA" *)
    output reg  [1023:0] zigzag_out,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 zigzag_stream_out TVALID" *)
    output reg  zigzag_valid,
    output reg  done,
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 busy DATA" *)
    output reg  busy
);

localparam integer NUM_SAMPLES = 64;

reg [5:0] zigzag_order [0:NUM_SAMPLES-1];
integer init_idx;

initial begin
    zigzag_order[0]  = 6'd0;   zigzag_order[1]  = 6'd1;   zigzag_order[2]  = 6'd8;   zigzag_order[3]  = 6'd16;
    zigzag_order[4]  = 6'd9;   zigzag_order[5]  = 6'd2;   zigzag_order[6]  = 6'd3;   zigzag_order[7]  = 6'd10;
    zigzag_order[8]  = 6'd17;  zigzag_order[9]  = 6'd24;  zigzag_order[10] = 6'd32;  zigzag_order[11] = 6'd25;
    zigzag_order[12] = 6'd18;  zigzag_order[13] = 6'd11;  zigzag_order[14] = 6'd4;   zigzag_order[15] = 6'd5;
    zigzag_order[16] = 6'd12;  zigzag_order[17] = 6'd19;  zigzag_order[18] = 6'd26;  zigzag_order[19] = 6'd33;
    zigzag_order[20] = 6'd40;  zigzag_order[21] = 6'd48;  zigzag_order[22] = 6'd41;  zigzag_order[23] = 6'd34;
    zigzag_order[24] = 6'd27;  zigzag_order[25] = 6'd20;  zigzag_order[26] = 6'd13;  zigzag_order[27] = 6'd6;
    zigzag_order[28] = 6'd7;   zigzag_order[29] = 6'd14;  zigzag_order[30] = 6'd21;  zigzag_order[31] = 6'd28;
    zigzag_order[32] = 6'd35;  zigzag_order[33] = 6'd42;  zigzag_order[34] = 6'd49;  zigzag_order[35] = 6'd56;
    zigzag_order[36] = 6'd57;  zigzag_order[37] = 6'd50;  zigzag_order[38] = 6'd43;  zigzag_order[39] = 6'd36;
    zigzag_order[40] = 6'd29;  zigzag_order[41] = 6'd22;  zigzag_order[42] = 6'd15;  zigzag_order[43] = 6'd23;
    zigzag_order[44] = 6'd30;  zigzag_order[45] = 6'd37;  zigzag_order[46] = 6'd44;  zigzag_order[47] = 6'd51;
    zigzag_order[48] = 6'd58;  zigzag_order[49] = 6'd59;  zigzag_order[50] = 6'd52;  zigzag_order[51] = 6'd45;
    zigzag_order[52] = 6'd38;  zigzag_order[53] = 6'd31;  zigzag_order[54] = 6'd39;  zigzag_order[55] = 6'd46;
    zigzag_order[56] = 6'd53;  zigzag_order[57] = 6'd60;  zigzag_order[58] = 6'd61;  zigzag_order[59] = 6'd54;
    zigzag_order[60] = 6'd47;  zigzag_order[61] = 6'd55;  zigzag_order[62] = 6'd62;  zigzag_order[63] = 6'd63;
end

reg [1023:0] coeff_block;
reg [6:0]    scan_index;

localparam [1:0] S_IDLE    = 2'd0;
localparam [1:0] S_WAIT    = 2'd1;
localparam [1:0] S_PROCESS = 2'd2;
localparam [1:0] S_OUTPUT  = 2'd3;

reg [1:0] state;

assign block_ready = (state == S_IDLE) && !busy;

always @(posedge clk) begin
    if (rst) begin
        coeff_block   <= {1024{1'b0}};
        scan_index    <= 7'd0;
        zigzag_out    <= {1024{1'b0}};
        zigzag_valid  <= 1'b0;
        done          <= 1'b0;
        busy          <= 1'b0;
        state         <= S_IDLE;
    end else begin
        zigzag_valid <= 1'b0;
        done         <= 1'b0;

        case (state)
            S_IDLE: begin
                busy <= 1'b0;
                if (start && enable) begin
                    busy <= 1'b1;
                    if (block_valid) begin
                        coeff_block <= block_in;
                        scan_index  <= 7'd0;
                        state       <= S_PROCESS;
                    end else begin
                        state <= S_WAIT;
                    end
                end
            end

            S_WAIT: begin
                busy <= 1'b1;
                if (block_valid) begin
                    coeff_block <= block_in;
                    scan_index  <= 7'd0;
                    state       <= S_PROCESS;
                end
            end

            S_PROCESS: begin
                busy <= 1'b1;
                zigzag_out[scan_index*16 +: 16] <= coeff_block[zigzag_order[scan_index[5:0]]*16 +: 16];
                if (scan_index == NUM_SAMPLES-1) begin
                    state <= S_OUTPUT;
                end else begin
                    scan_index <= scan_index + 7'd1;
                end
            end

            S_OUTPUT: begin
                busy         <= 1'b0;
                zigzag_valid <= 1'b1;
                done         <= 1'b1;
                state        <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
