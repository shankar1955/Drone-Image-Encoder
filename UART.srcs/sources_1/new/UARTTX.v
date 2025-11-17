module uarttx #(
    parameter integer BAUD_RATE = 115200,
    parameter integer CLK_FREQ  = 100000000
)(
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, FREQ_HZ 100000000, PHASE 0.0, ASSOCIATED_RESET rst" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    input  wire clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
    input  wire rst,
    input  wire enable,

    // Byte stream input
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME bitstream_in, TDATA_NUM_BYTES 1, HAS_TREADY 0" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 bitstream_in TDATA" *)
    input  wire [7:0] data_in,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 bitstream_in TVALID" *)
    input  wire data_valid,
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 tx_ready DATA" *)
    output wire data_ready,

    // UART serial output
    output reg  uart_tx,

    // Status
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 busy DATA" *)
    output reg  busy,
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 tx_done DATA" *)
    output reg  tx_done
);

localparam integer BAUD_DIVIDER = (CLK_FREQ / BAUD_RATE);
localparam [2:0] S_IDLE      = 3'd0;
localparam [2:0] S_START_BIT = 3'd1;
localparam [2:0] S_DATA_BIT  = 3'd2;
localparam [2:0] S_STOP_BIT  = 3'd3;

reg [2:0]  state;
reg [15:0] baud_cnt;
reg [2:0]  bit_idx;
reg [7:0]  tx_shift;
reg        baud_tick;

assign data_ready = (state == S_IDLE) && !busy;

always @(posedge clk) begin
    if (rst) begin
        baud_cnt  <= 16'd0;
        baud_tick <= 1'b0;
    end else begin
        if (baud_cnt >= (BAUD_DIVIDER - 1)) begin
            baud_cnt  <= 16'd0;
            baud_tick <= 1'b1;
        end else begin
            baud_cnt  <= baud_cnt + 16'd1;
            baud_tick <= 1'b0;
        end
    end
end

always @(posedge clk) begin
    if (rst) begin
        state    <= S_IDLE;
        uart_tx  <= 1'b1;
        busy     <= 1'b0;
        tx_done  <= 1'b0;
        bit_idx  <= 3'd0;
        tx_shift <= 8'd0;
    end else begin
        tx_done <= 1'b0;

        case (state)
            S_IDLE: begin
                uart_tx <= 1'b1;
                busy    <= 1'b0;
                if (enable && data_valid) begin
                    busy     <= 1'b1;
                    tx_shift <= data_in;
                    bit_idx  <= 3'd0;
                    state    <= S_START_BIT;
                end
            end

            S_START_BIT: begin
                if (baud_tick) begin
                    uart_tx <= 1'b0;
                    state   <= S_DATA_BIT;
                end
            end

            S_DATA_BIT: begin
                if (baud_tick) begin
                    uart_tx <= tx_shift[bit_idx];
                    if (bit_idx == 3'd7) begin
                        state <= S_STOP_BIT;
                    end else begin
                        bit_idx <= bit_idx + 3'd1;
                    end
                end
            end

            S_STOP_BIT: begin
                if (baud_tick) begin
                    uart_tx <= 1'b1;
                    tx_done <= 1'b1;
                    state   <= S_IDLE;
                end
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
