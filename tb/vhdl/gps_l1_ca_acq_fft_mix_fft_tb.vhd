library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.gps_l1_ca_pkg.all;
use work.gps_l1_ca_acq_fft_pkg.all;

entity gps_l1_ca_acq_fft_mix_fft_tb is
  generic (
    G_VECTOR_FILE : string := "sim/vectors/acq_fft_mix_fft_cases.txt"
  );
end entity;

architecture tb of gps_l1_ca_acq_fft_mix_fft_tb is
  constant C_CLK_PERIOD : time := 10 ns;

  signal clk          : std_logic := '0';
  signal rst_n        : std_logic := '0';
  signal start        : std_logic := '0';
  signal cap_i_i      : sample_arr_t := (others => (others => '0'));
  signal cap_q_i      : sample_arr_t := (others => (others => '0'));
  signal dopp_hz_i    : signed(15 downto 0) := (others => '0');
  signal signal_fft_o : cpx32_vec_t;
  signal done_o       : std_logic;
begin
  clk <= not clk after C_CLK_PERIOD / 2;

  dut : entity work.gps_l1_ca_acq_fft_mix_fft
    port map (
      clk          => clk,
      rst_n        => rst_n,
      start        => start,
      cap_i_i      => cap_i_i,
      cap_q_i      => cap_q_i,
      dopp_hz_i    => dopp_hz_i,
      signal_fft_o => signal_fft_o,
      done_o       => done_o
    );

  stim_proc : process
    file vec_file : text;
    variable read_status_v : file_open_status;
    variable l_v           : line;
    variable case_count_v  : integer;
    variable dopp_v        : integer;
    variable i_v           : integer;
    variable q_v           : integer;
    variable re_v          : integer;
    variable im_v          : integer;
    variable expected_fft_v : cpx32_vec_t;
    variable cap_i_v        : sample_arr_t;
    variable cap_q_v        : sample_arr_t;
    variable hold_fft_v     : cpx32_vec_t;
    variable hold_mix_v     : cpx32_vec_t;
  begin
    rst_n <= '0';
    wait for 3 * C_CLK_PERIOD;
    assert done_o = '0'
      report "Mix FFT generator done_o should remain low during reset"
      severity failure;
    rst_n <= '1';
    wait until rising_edge(clk);

    file_open(read_status_v, vec_file, G_VECTOR_FILE, read_mode);
    assert read_status_v = open_ok
      report "Unable to open mix/FFT vector file: " & G_VECTOR_FILE
      severity failure;

    readline(vec_file, l_v);
    read(l_v, case_count_v);
    assert case_count_v > 0
      report "Expected at least one mix/FFT vector case."
      severity failure;

    for case_idx_v in 0 to case_count_v - 1 loop
      readline(vec_file, l_v);
      read(l_v, dopp_v);

      for s in 0 to C_SAMPLES_PER_MS - 1 loop
        readline(vec_file, l_v);
        read(l_v, i_v);
        read(l_v, q_v);
        cap_i_v(s) := to_signed(i_v, 16);
        cap_q_v(s) := to_signed(q_v, 16);
      end loop;

      for k in 0 to C_NFFT - 1 loop
        readline(vec_file, l_v);
        read(l_v, re_v);
        read(l_v, im_v);
        expected_fft_v(k).re := to_signed(re_v, 32);
        expected_fft_v(k).im := to_signed(im_v, 32);
      end loop;

      cap_i_i <= cap_i_v;
      cap_q_i <= cap_q_v;
      dopp_hz_i <= to_signed(dopp_v, 16);
      wait until rising_edge(clk);

      start <= '1';
      wait until rising_edge(clk);
      wait for 1 ns;
      assert done_o = '1'
        report "Mix FFT generator did not assert done"
        severity failure;
      start <= '0';
      wait until rising_edge(clk);

      for k in 0 to C_NFFT - 1 loop
        assert signal_fft_o(k).re = expected_fft_v(k).re
          report "Signal FFT real mismatch at case " & integer'image(case_idx_v) &
                 ", bin " & integer'image(k)
          severity failure;
        assert signal_fft_o(k).im = expected_fft_v(k).im
          report "Signal FFT imag mismatch at case " & integer'image(case_idx_v) &
                 ", bin " & integer'image(k)
          severity failure;
      end loop;
    end loop;

    -- Held-start behavior should keep done asserted while start is high.
    for s in 0 to C_SAMPLES_PER_MS - 1 loop
      cap_i_v(s) := to_signed(0, 16);
      cap_q_v(s) := to_signed(0, 16);
    end loop;
    cap_i_v(0) := to_signed(1000, 16);
    cap_q_v(0) := to_signed(-500, 16);
    cap_i_i <= cap_i_v;
    cap_q_i <= cap_q_v;
    dopp_hz_i <= to_signed(250, 16);
    hold_mix_v := build_mixed_fft_input(cap_i_v, cap_q_v, to_signed(250, 16));
    hold_fft_v := fft_radix2(hold_mix_v, false);
    wait until rising_edge(clk);

    start <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    assert done_o = '1'
      report "Mix FFT generator expected done_o=1 on held-start cycle A"
      severity failure;
    wait until rising_edge(clk);
    wait for 1 ns;
    assert done_o = '1'
      report "Mix FFT generator expected done_o=1 on held-start cycle B"
      severity failure;
    start <= '0';
    wait until rising_edge(clk);

    for k in 0 to C_NFFT - 1 loop
      assert signal_fft_o(k).re = hold_fft_v(k).re
        report "Held-start mix FFT real mismatch at bin " & integer'image(k)
        severity failure;
      assert signal_fft_o(k).im = hold_fft_v(k).im
        report "Held-start mix FFT imag mismatch at bin " & integer'image(k)
        severity failure;
    end loop;

    -- Reset must dominate start and clear outputs.
    start <= '1';
    rst_n <= '0';
    wait until rising_edge(clk);
    wait for 1 ns;
    assert done_o = '0'
      report "Mix FFT generator done_o must remain low during reset"
      severity failure;
    for k in 0 to C_NFFT - 1 loop
      assert signal_fft_o(k).re = to_signed(0, 32) and signal_fft_o(k).im = to_signed(0, 32)
        report "Mix FFT generator output should clear during reset"
        severity failure;
    end loop;
    start <= '0';
    rst_n <= '1';
    wait until rising_edge(clk);

    file_close(vec_file);

    report "gps_l1_ca_acq_fft_mix_fft_tb passed";
    wait;
  end process;
end architecture;
