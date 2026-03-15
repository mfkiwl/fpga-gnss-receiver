module top_tb;
  logic       clk = 1'b0;
  logic       rst_n = 1'b0;
  logic [7:0] a = '0;
  logic [7:0] y;

  top uut (
    .clk  (clk),
    .rst_n(rst_n),
    .a    (a),
    .y    (y)
  );

  always #5 clk = ~clk;

  initial begin
    #20;
    rst_n = 1'b1;
    a = 8'h10;
    #10;
    a = 8'h20;
    #10;
    $display("top_tb done y=%0h", y);
    #10;
    $finish;
  end
endmodule
