`timescale 1ns/1ps

module camera_interface_tb;

localparam integer PIX_CLK_PERIOD      = 20;
localparam integer CAM_CLK_PERIOD      = 40;
localparam integer NUM_LINES           = 2;
localparam integer PIXELS_PER_LINE     = 4;
localparam integer TOTAL_PIXELS        = NUM_LINES * PIXELS_PER_LINE;

reg pix_clk;
reg cam_pclk;
reg rst;
reg enable;
reg cam_vsync;
reg cam_href;
reg [7:0] cam_data;

wire [7:0] pixel_out;
wire pixel_valid;
wire frame_start;
wire line_start;
wire capturing;

camera_interface dut (
    .pix_clk(pix_clk),
    .rst(rst),
    .enable(enable),
    .cam_pclk(cam_pclk),
    .cam_vsync(cam_vsync),
    .cam_href(cam_href),
    .cam_data(cam_data),
    .pixel_out(pixel_out),
    .pixel_valid(pixel_valid),
    .frame_start(frame_start),
    .line_start(line_start),
    .capturing(capturing)
);

reg [7:0] expected [0:TOTAL_PIXELS-1];
integer wr_idx;
integer rd_idx;
integer frame_start_count;
integer line_start_count;
reg capturing_seen;

initial begin
    pix_clk = 1'b0;
    forever #(PIX_CLK_PERIOD/2) pix_clk = ~pix_clk;
end

initial begin
    cam_pclk = 1'b0;
    forever #(CAM_CLK_PERIOD/2) cam_pclk = ~cam_pclk;
end

integer init_idx;
initial begin
    for (init_idx = 0; init_idx < TOTAL_PIXELS; init_idx = init_idx + 1) begin
        expected[init_idx] = 8'h00;
    end
end

always @(posedge pix_clk) begin
    if (rst) begin
        rd_idx <= 0;
        frame_start_count <= 0;
        line_start_count <= 0;
        capturing_seen <= 1'b0;
    end else begin
        if (frame_start)
            frame_start_count <= frame_start_count + 1;
        if (line_start)
            line_start_count <= line_start_count + 1;
        if (capturing)
            capturing_seen <= 1'b1;
        if (pixel_valid) begin
            if (rd_idx >= TOTAL_PIXELS) begin
                $display("[%0t] ERROR: Received unexpected pixel %0d (value %0h)", $time, rd_idx, pixel_out);
                $fatal;
            end else if (pixel_out !== expected[rd_idx]) begin
                $display("[%0t] ERROR: Pixel %0d mismatch. Expected %0h, got %0h", $time, rd_idx, expected[rd_idx], pixel_out);
                $fatal;
            end
            rd_idx <= rd_idx + 1;
        end
    end
end

initial begin
    rst = 1'b1;
    enable = 1'b0;
    cam_vsync = 1'b0;
    cam_href = 1'b0;
    cam_data = 8'h00;
    wr_idx = 0;

    repeat (4) @(posedge pix_clk);
    rst = 1'b0;

    repeat (2) @(posedge pix_clk);
    enable = 1'b1;

    repeat (4) @(posedge pix_clk);

    send_frame();

    repeat ((TOTAL_PIXELS * 4) + 20) @(posedge pix_clk);

    if (rd_idx !== TOTAL_PIXELS) begin
        $display("[%0t] ERROR: Expected %0d pixels, received %0d", $time, TOTAL_PIXELS, rd_idx);
        $fatal;
    end

    if (frame_start_count !== 1) begin
        $display("[%0t] ERROR: frame_start asserted %0d times", $time, frame_start_count);
        $fatal;
    end

    if (line_start_count !== NUM_LINES) begin
        $display("[%0t] ERROR: line_start asserted %0d times (expected %0d)", $time, line_start_count, NUM_LINES);
        $fatal;
    end

    if (!capturing_seen) begin
        $display("[%0t] ERROR: capturing never asserted", $time);
        $fatal;
    end

    if (capturing !== 1'b0) begin
        $display("[%0t] ERROR: capturing remained high at end of test", $time);
        $fatal;
    end

    $display("[%0t] INFO: camera_interface testbench PASSED", $time);
    $finish;
end

task automatic send_frame;
integer line;
begin
    start_frame();
    for (line = 0; line < NUM_LINES; line = line + 1) begin
        send_line(line);
    end
    end_frame();
end
endtask

task automatic start_frame;
begin
    @(negedge cam_pclk);
    cam_vsync <= 1'b1;
    cam_href <= 1'b0;
    cam_data <= 8'h00;
    repeat (3) @(posedge pix_clk);
end
endtask

task automatic end_frame;
begin
    @(negedge cam_pclk);
    cam_href <= 1'b0;
    cam_data <= 8'h00;
    cam_vsync <= 1'b0;
    repeat (2) @(posedge pix_clk);
end
endtask

task automatic send_line(input integer line_idx);
integer pix;
reg [7:0] pixel_value;
begin
    @(negedge cam_pclk);
    cam_href <= 1'b1;
    repeat (2) @(posedge pix_clk);
    for (pix = 0; pix < PIXELS_PER_LINE; pix = pix + 1) begin
        pixel_value = {line_idx[3:0], pix[3:0]};
        send_pixel(pixel_value);
    end
    @(negedge cam_pclk);
    cam_href <= 1'b0;
    cam_data <= 8'h00;
    repeat (2) @(negedge cam_pclk);
end
endtask

task automatic send_pixel(input [7:0] value);
begin
    @(negedge cam_pclk);
    cam_data <= value;
    @(posedge cam_pclk);
    if (wr_idx >= TOTAL_PIXELS) begin
        $display("[%0t] ERROR: Stimulus exceeded TOTAL_PIXELS (%0d)", $time, TOTAL_PIXELS);
        $fatal;
    end
    expected[wr_idx] = value;
    wr_idx = wr_idx + 1;
end
endtask

endmodule
