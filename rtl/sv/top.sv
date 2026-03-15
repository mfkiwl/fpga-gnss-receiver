module top (
  input  logic       clk,
  input  logic       rst_n,
  input  logic [7:0] a,
  output logic [7:0] y
);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      y <= '0;
    end else begin
      y <= a + 8'd1;
    end
  end
endmodule
