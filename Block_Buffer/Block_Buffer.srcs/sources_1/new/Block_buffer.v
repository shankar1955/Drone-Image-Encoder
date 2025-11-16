module block_buffer #(
    parameter CHANNEL_ID = 0  // 0=Y, 1=Cb, 2=Cr
)(
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, FREQ_HZ 24000000, PHASE 0.0, ASSOCIATED_RESET rst" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    input wire clk,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME rst, POLARITY ACTIVE_HIGH" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
    input wire rst,
    input wire enable,

    // Input pixel stream
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME pixel_stream_in, TDATA_NUM_BYTES 1, HAS_TREADY 0" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 pixel_stream_in TDATA" *)
    input wire [7:0] pixel_in,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 pixel_stream_in TVALID" *)
    input wire pixel_valid,

    // 8x8 block output (flattened 512-bit vector)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME block_stream, TDATA_NUM_BYTES 64, HAS_TREADY 0" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 block_stream TDATA" *)
    output reg [511:0] block_data_flat,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 block_stream TVALID" *)
    output reg block_ready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 block_stream TLAST" *)
    output reg block_valid,

    // Control signals
    input wire block_read_ack,
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 pixel_count DATA" *)
    output reg [5:0] pixel_count,
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 buffer_full DATA" *)
    output reg buffer_full
);

reg [7:0] pixel_buffer [0:63];
reg [5:0] write_addr;
reg buffer_state;

localparam FILLING = 1'b0;
localparam READY = 1'b1;

integer i;

always @(posedge clk) begin
    if (rst) begin
        write_addr <= 0;
        pixel_count <= 0;
        block_ready <= 0;
        block_valid <= 0;
        buffer_full <= 0;
        buffer_state <= FILLING;
        block_data_flat <= 0;

        // Clear internal pixel buffer
        for (i = 0; i < 64; i = i + 1) begin
            pixel_buffer[i] <= 0;
        end
    end else begin
        case (buffer_state)
            FILLING: begin
                block_ready <= 0;
                block_valid <= 0;
                buffer_full <= 0;

                if (enable && pixel_valid) begin
                    pixel_buffer[write_addr] <= pixel_in;

                    if (write_addr == 63) begin
                        // Buffer full, transfer to output
                        buffer_state <= READY;
                        block_ready <= 1;
                        block_valid <= 1;
                        buffer_full <= 1;
                        pixel_count <= 64;
                        write_addr <= 0;

                        // Pack pixel_buffer to output vector
                        for (i = 0; i < 64; i = i + 1) begin
                            block_data_flat[i*8 +: 8] <= pixel_buffer[i];
                        end
                    end else begin
                        write_addr <= write_addr + 1;
                        pixel_count <= write_addr + 1;
                    end
                end
            end

            READY: begin
                if (block_read_ack) begin
                    buffer_state <= FILLING;
                    write_addr <= 0;
                    pixel_count <= 0;
                    block_ready <= 0;
                    block_valid <= 0;
                    buffer_full <= 0;
                end
            end

            default: buffer_state <= FILLING;
        endcase
    end
end

endmodule
