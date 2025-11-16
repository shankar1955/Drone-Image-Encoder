module bitstream_mux (
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, FREQ_HZ 24000000, PHASE 0.0, ASSOCIATED_RESET rst" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    input  wire clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
    input  wire rst,
    input  wire enable,

    // Input RLE blocks
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME rle_stream_in, TDATA_NUM_BYTES 128, HAS_TREADY 0" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 rle_stream_in TDATA" *)
    input  wire [1023:0] rle_block,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 rle_stream_in TVALID" *)
    input  wire rle_valid,
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 rle_pair_count DATA" *)
    input  wire [6:0]     pair_count,
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 rle_channel_id DATA" *)
    input  wire [1:0]     rle_channel_id,
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 rle_ready DATA" *)
    output wire           rle_ready,

    // Output byte stream to UART or downstream transport
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME bitstream_out, TDATA_NUM_BYTES 1, HAS_TREADY 0" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 bitstream_out TDATA" *)
    output reg  [7:0] stream_out,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 bitstream_out TVALID" *)
    output reg  stream_valid,
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 stream_channel DATA" *)
    output reg  [1:0] out_channel_id,
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 block_done DATA" *)
    output reg  block_done,
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 busy DATA" *)
    output reg  busy
);

localparam integer MAX_PAIRS = 64;

localparam [1:0] S_IDLE      = 2'd0;
localparam [1:0] S_LOAD      = 2'd1;
localparam [1:0] S_OUTPUT    = 2'd2;
localparam [1:0] S_WAIT_BYTE = 2'd3;

reg [1:0] state;

reg [15:0] pair_buffer [0:MAX_PAIRS-1];
reg [6:0]  total_pairs;
reg [6:0]  pair_index;
reg        output_low_byte;

integer i;

assign rle_ready = (state == S_IDLE);

always @(posedge clk) begin
    if (rst) begin
        state           <= S_IDLE;
        stream_out      <= 8'd0;
        stream_valid    <= 1'b0;
        out_channel_id  <= 2'd0;
        block_done      <= 1'b0;
        busy            <= 1'b0;
        total_pairs     <= 7'd0;
        pair_index      <= 7'd0;
        output_low_byte <= 1'b0;
        for (i = 0; i < MAX_PAIRS; i = i + 1) begin
            pair_buffer[i] <= 16'd0;
        end
    end else begin
        stream_valid <= 1'b0;
        block_done   <= 1'b0;

        case (state)
            S_IDLE: begin
                busy <= 1'b0;
                if (rle_valid && enable) begin
                    busy <= 1'b1;
                    for (i = 0; i < MAX_PAIRS; i = i + 1) begin
                        pair_buffer[i] <= rle_block[i*16 +: 16];
                    end
                    total_pairs     <= pair_count;
                    pair_index      <= 7'd0;
                    output_low_byte <= 1'b0;
                    out_channel_id  <= rle_channel_id;
                    state           <= S_OUTPUT;
                end
            end

            S_OUTPUT: begin
                busy <= 1'b1;
                if (pair_index < total_pairs) begin
                    if (!output_low_byte) begin
                        stream_out      <= pair_buffer[pair_index][15:8];
                        stream_valid    <= 1'b1;
                        output_low_byte <= 1'b1;
                    end else begin
                        stream_out      <= pair_buffer[pair_index][7:0];
                        stream_valid    <= 1'b1;
                        output_low_byte <= 1'b0;
                        pair_index      <= pair_index + 7'd1;
                    end
                end else begin
                    block_done <= 1'b1;
                    busy       <= 1'b0;
                    state      <= S_IDLE;
                end
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
