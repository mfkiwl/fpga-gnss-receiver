library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gps_l1_ca_acq_fft_pkg.all;

entity gps_l1_ca_acq_fft_corr_tb is
end entity;

architecture tb of gps_l1_ca_acq_fft_corr_tb is
  constant C_CLK_PERIOD : time := 10 ns;

  signal clk        : std_logic := '0';
  signal rst_n      : std_logic := '0';
  signal start      : std_logic := '0';
  signal sig_fft_i  : cpx32_vec_t := (others => C_CPX_ZERO);
  signal code_fft_i : cpx32_vec_t := (others => C_CPX_ZERO);
  signal corr_o     : cpx32_t;
  signal done_o     : std_logic;
begin
  clk <= not clk after C_CLK_PERIOD / 2;

  dut : entity work.gps_l1_ca_acq_fft_corr
    port map (
      clk        => clk,
      rst_n      => rst_n,
      start      => start,
      sig_fft_i  => sig_fft_i,
      code_fft_i => code_fft_i,
      corr_o     => corr_o,
      done_o     => done_o
    );

  stim_proc : process
    variable sig_v  : cpx32_vec_t;
    variable code_v : cpx32_vec_t;
  begin
    rst_n <= '0';
    wait for 3 * C_CLK_PERIOD;
    rst_n <= '1';
    wait until rising_edge(clk);

    sig_v := (others => C_CPX_ZERO);
    code_v := (others => C_CPX_ZERO);

    sig_v(0).re := to_signed(4096, 32);
    sig_v(1).im := to_signed(2048, 32);
    code_v(0).re := to_signed(2, 32);
    code_v(1).im := to_signed(1, 32);

    sig_fft_i <= sig_v;
    code_fft_i <= code_v;
    wait until rising_edge(clk);

    start <= '1';
    wait until rising_edge(clk);
    start <= '0';
    wait until rising_edge(clk);

    assert done_o = '1'
      report "Correlation unit did not assert done"
      severity failure;

    assert corr_o.re = to_signed(5, 32)
      report "Correlation real part mismatch"
      severity failure;
    assert corr_o.im = to_signed(0, 32)
      report "Correlation imag part mismatch"
      severity failure;

    report "gps_l1_ca_acq_fft_corr_tb passed";
    wait;
  end process;
end architecture;
