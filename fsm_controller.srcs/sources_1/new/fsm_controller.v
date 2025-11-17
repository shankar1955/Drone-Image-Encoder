 module fsm_controller #(
         parameter integer TIMEOUT_CYCLES = 4096
     )(
         (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, FREQ_HZ 24000000, PHASE 0.0,ASSOCIATED_RESET rst" *)
         (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
         input wire clk,
         (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
         input wire rst,
         input wire enable,

         // Buffer readiness inputs
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 y_buffer_ready DATA" *)
         input wire y_buffer_ready,
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 cb_buffer_ready DATA" *)
         input wire cb_buffer_ready,
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 cr_buffer_ready DATA" *)
         input wire cr_buffer_ready,

         // Pipeline stage status
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 dct_busy DATA" *)
         input wire dct_busy,
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 dct_done DATA" *)
         input wire dct_done,
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 quant_busy DATA" *)
         input wire quant_busy,
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 quant_done DATA" *)
         input wire quant_done,
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 zigzag_busy DATA" *)
         input wire zigzag_busy,
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 zigzag_done DATA" *)
         input wire zigzag_done,
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 rle_busy DATA" *)
         input wire rle_busy,
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 rle_done DATA" *)
         input wire rle_done,

         // Buffer acknowledgements (one-hot)
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 y_block_ack DATA" *)
         output reg y_block_ack,
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 cb_block_ack DATA" *)
         output reg cb_block_ack,
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 cr_block_ack DATA" *)
         output reg cr_block_ack,

         // Pipeline control outputs
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 channel_select DATA" *)
         output reg [1:0] channel_select,
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 quant_table_select DATA" *)
         output reg [1:0] quant_table_select,
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 dct_start DATA" *)
         output reg dct_start,
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 quant_start DATA" *)
         output reg quant_start,
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 zigzag_start DATA" *)
         output reg zigzag_start,
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 rle_start DATA" *)
         output reg rle_start,

         // Status outputs
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 processing_active DATA" *)
         output reg processing_active,
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 current_channel DATA" *)
         output reg [1:0] current_channel,
         (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 stage_timeout DATA" *)
         output reg stage_timeout
     );

     function integer fsm_clog2;
         input integer value;
         integer i;
     begin
         fsm_clog2 = 0;
         for (i = value - 1; i > 0; i = i >> 1)
             fsm_clog2 = fsm_clog2 + 1;
         if (fsm_clog2 == 0)
             fsm_clog2 = 1;
     end
     endfunction

     localparam [3:0] S_IDLE           = 4'd0;
     localparam [3:0] S_SELECT_CHANNEL = 4'd1;
     localparam [3:0] S_ACK_BUFFER     = 4'd2;
     localparam [3:0] S_START_DCT      = 4'd3;
     localparam [3:0] S_WAIT_DCT       = 4'd4;
     localparam [3:0] S_START_QUANT    = 4'd5;
     localparam [3:0] S_WAIT_QUANT     = 4'd6;
     localparam [3:0] S_START_ZIGZAG   = 4'd7;
     localparam [3:0] S_WAIT_ZIGZAG    = 4'd8;
     localparam [3:0] S_START_RLE      = 4'd9;
     localparam [3:0] S_WAIT_RLE       = 4'd10;
     localparam [3:0] S_COMPLETE       = 4'd11;

     reg [3:0] state;
     reg [1:0] active_channel;
     reg [1:0] rr_pointer;

     localparam integer TIMEOUT_LIMIT = (TIMEOUT_CYCLES < 1) ? 1 : TIMEOUT_CYCLES;
     localparam integer TIMEOUT_WIDTH = fsm_clog2(TIMEOUT_LIMIT);
     reg [TIMEOUT_WIDTH-1:0] timeout_cnt;

     wire wait_state = (state == S_WAIT_DCT) ||
                       (state == S_WAIT_QUANT) ||
                       (state == S_WAIT_ZIGZAG) ||
                       (state == S_WAIT_RLE);

     wire timeout_hit = (timeout_cnt >= (TIMEOUT_LIMIT - 1));

     reg channel_available;
     reg [1:0] selected_channel;

     always @* begin
         channel_available = 1'b0;
         selected_channel = rr_pointer;
         case (rr_pointer)
             2'd0: begin
                 if (y_buffer_ready) begin
                     selected_channel = 2'd0;
                     channel_available = 1'b1;
                 end else if (cb_buffer_ready) begin
                     selected_channel = 2'd1;
                     channel_available = 1'b1;
                 end else if (cr_buffer_ready) begin
                     selected_channel = 2'd2;
                     channel_available = 1'b1;
                 end
             end
             2'd1: begin
                 if (cb_buffer_ready) begin
                     selected_channel = 2'd1;
                     channel_available = 1'b1;
                 end else if (cr_buffer_ready) begin
                     selected_channel = 2'd2;
                     channel_available = 1'b1;
                 end else if (y_buffer_ready) begin
                     selected_channel = 2'd0;
                     channel_available = 1'b1;
                 end
             end
             default: begin
                 if (cr_buffer_ready) begin
                     selected_channel = 2'd2;
                     channel_available = 1'b1;
                 end else if (y_buffer_ready) begin
                     selected_channel = 2'd0;
                     channel_available = 1'b1;
                 end else if (cb_buffer_ready) begin
                     selected_channel = 2'd1;
                     channel_available = 1'b1;
                 end
             end
         endcase
     end

     always @(posedge clk) begin
         if (rst) begin
             state <= S_IDLE;
             active_channel <= 2'd0;
             rr_pointer <= 2'd0;
             channel_select <= 2'd0;
             quant_table_select <= 2'd0;
             current_channel <= 2'd0;
             dct_start <= 1'b0;
             quant_start <= 1'b0;
             zigzag_start <= 1'b0;
             rle_start <= 1'b0;
             y_block_ack <= 1'b0;
             cb_block_ack <= 1'b0;
             cr_block_ack <= 1'b0;
             processing_active <= 1'b0;
             timeout_cnt <= {TIMEOUT_WIDTH{1'b0}};
             stage_timeout <= 1'b0;
         end else begin
             dct_start <= 1'b0;
             quant_start <= 1'b0;
             zigzag_start <= 1'b0;
             rle_start <= 1'b0;
             y_block_ack <= 1'b0;
             cb_block_ack <= 1'b0;
             cr_block_ack <= 1'b0;
             stage_timeout <= 1'b0;

             if (wait_state) begin
                 if (!timeout_hit)
                     timeout_cnt <= timeout_cnt + {{(TIMEOUT_WIDTH-1){1'b0}}, 1'b1};
                 else begin
                     stage_timeout <= 1'b1;
                     state <= S_IDLE;
                     processing_active <= 1'b0;
                     timeout_cnt <= {TIMEOUT_WIDTH{1'b0}};
                 end
             end else begin
                 timeout_cnt <= {TIMEOUT_WIDTH{1'b0}};
             end

             case (state)
                 S_IDLE: begin
                     processing_active <= 1'b0;
                     if (enable && channel_available)
                         state <= S_SELECT_CHANNEL;
                 end

                 S_SELECT_CHANNEL: begin
                     active_channel <= selected_channel;
                     channel_select <= selected_channel;
                     quant_table_select <= selected_channel;
                     current_channel <= selected_channel;
                     processing_active <= 1'b1;
                     state <= S_ACK_BUFFER;
                 end

                 S_ACK_BUFFER: begin
                     case (active_channel)
                         2'd0: y_block_ack <= 1'b1;
                         2'd1: cb_block_ack <= 1'b1;
                         default: cr_block_ack <= 1'b1;
                     endcase
                     state <= S_START_DCT;
                 end

                 S_START_DCT: begin
                     if (!dct_busy) begin
                         dct_start <= 1'b1;
                         state <= S_WAIT_DCT;
                     end
                 end

                 S_WAIT_DCT: begin
                     if (dct_done && !dct_busy)
                         state <= S_START_QUANT;
                 end

                 S_START_QUANT: begin
                     if (!quant_busy) begin
                         quant_start <= 1'b1;
                         state <= S_WAIT_QUANT;
                     end
                 end

                 S_WAIT_QUANT: begin
                     if (quant_done && !quant_busy)
                         state <= S_START_ZIGZAG;
                 end

                 S_START_ZIGZAG: begin
                     if (!zigzag_busy) begin
                         zigzag_start <= 1'b1;
                         state <= S_WAIT_ZIGZAG;
                     end
                 end

                 S_WAIT_ZIGZAG: begin
                     if (zigzag_done && !zigzag_busy)
                         state <= S_START_RLE;
                 end

                 S_START_RLE: begin
                     if (!rle_busy) begin
                         rle_start <= 1'b1;
                         state <= S_WAIT_RLE;
                     end
                 end

                 S_WAIT_RLE: begin
                     if (rle_done && !rle_busy)
                         state <= S_COMPLETE;
                 end

                 S_COMPLETE: begin
                     processing_active <= 1'b0;
                     rr_pointer <= (active_channel == 2'd2) ? 2'd0 : active_channel + 1'b1;
                     state <= S_IDLE;
                 end

                 default: state <= S_IDLE;
             endcase
         end
     end

     endmodule