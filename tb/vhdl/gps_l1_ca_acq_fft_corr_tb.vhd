library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.gps_l1_ca_acq_fft_pkg.all;

entity gps_l1_ca_acq_fft_corr_tb is
  generic (
    G_VECTOR_FILE : string := "sim/vectors/acq_fft_corr_cases.txt"
  );
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
    file vec_file : text;
    variable read_status_v : file_open_status;
    variable l_v           : line;
    variable case_count_v  : integer;
    variable s0_re_v       : integer;
    variable s0_im_v       : integer;
    variable s1_re_v       : integer;
    variable s1_im_v       : integer;
    variable c0_re_v       : integer;
    variable c0_im_v       : integer;
    variable c1_re_v       : integer;
    variable c1_im_v       : integer;
    variable exp_re_v      : integer;
    variable exp_im_v      : integer;
    variable sig_v  : cpx32_vec_t;
    variable code_v : cpx32_vec_t;
  begin
    rst_n <= '0';
    wait for 3 * C_CLK_PERIOD;
    rst_n <= '1';
    wait until rising_edge(clk);

    file_open(read_status_v, vec_file, G_VECTOR_FILE, read_mode);
    assert read_status_v = open_ok
      report "Unable to open correlation vector file: " & G_VECTOR_FILE
      severity failure;

    readline(vec_file, l_v);
    read(l_v, case_count_v);
    assert case_count_v > 0
      report "Expected at least one correlation vector case."
      severity failure;

    for case_idx_v in 0 to case_count_v - 1 loop
      readline(vec_file, l_v);
      read(l_v, s0_re_v);
      read(l_v, s0_im_v);
      read(l_v, s1_re_v);
      read(l_v, s1_im_v);
      read(l_v, c0_re_v);
      read(l_v, c0_im_v);
      read(l_v, c1_re_v);
      read(l_v, c1_im_v);
      read(l_v, exp_re_v);
      read(l_v, exp_im_v);

      sig_v := (others => C_CPX_ZERO);
      code_v := (others => C_CPX_ZERO);
      sig_v(0).re := to_signed(s0_re_v, 32);
      sig_v(0).im := to_signed(s0_im_v, 32);
      sig_v(1).re := to_signed(s1_re_v, 32);
      sig_v(1).im := to_signed(s1_im_v, 32);
      code_v(0).re := to_signed(c0_re_v, 32);
      code_v(0).im := to_signed(c0_im_v, 32);
      code_v(1).re := to_signed(c1_re_v, 32);
      code_v(1).im := to_signed(c1_im_v, 32);

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

      assert corr_o.re = to_signed(exp_re_v, 32)
        report "Correlation real mismatch at case " & integer'image(case_idx_v)
        severity failure;
      assert corr_o.im = to_signed(exp_im_v, 32)
        report "Correlation imag mismatch at case " & integer'image(case_idx_v)
        severity failure;
    end loop;

    file_close(vec_file);

    report "gps_l1_ca_acq_fft_corr_tb passed";
    wait;
  end process;
end architecture;
