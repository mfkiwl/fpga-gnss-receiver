library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gps_l1_ca_pkg.all;
use work.gps_l1_ca_acq_fft_pkg.all;

entity gps_l1_ca_acq_fft_mix_fft_tb is
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
    variable expected_fft_v : cpx32_vec_t;
    variable cap_i_v        : sample_arr_t;
    variable cap_q_v        : sample_arr_t;
  begin
    rst_n <= '0';
    wait for 3 * C_CLK_PERIOD;
    rst_n <= '1';
    wait until rising_edge(clk);

    cap_i_v := (others => (others => '0'));
    cap_q_v := (others => (others => '0'));
    cap_i_v(0) := to_signed(1200, 16);
    cap_i_v(1) := to_signed(-700, 16);
    cap_q_v(0) := to_signed(300, 16);
    cap_q_v(1) := to_signed(500, 16);

    cap_i_i <= cap_i_v;
    cap_q_i <= cap_q_v;
    dopp_hz_i <= to_signed(1250, 16);
    wait until rising_edge(clk);

    start <= '1';
    wait until rising_edge(clk);
    start <= '0';
    wait until rising_edge(clk);

    assert done_o = '1'
      report "Mix FFT generator did not assert done"
      severity failure;

    expected_fft_v := fft_radix2(
      build_mixed_fft_input(cap_i_v, cap_q_v, to_signed(1250, 16)),
      false
    );

    for k in 0 to C_NFFT - 1 loop
      assert signal_fft_o(k).re = expected_fft_v(k).re
        report "Signal FFT real mismatch at bin " & integer'image(k)
        severity failure;
      assert signal_fft_o(k).im = expected_fft_v(k).im
        report "Signal FFT imag mismatch at bin " & integer'image(k)
        severity failure;
    end loop;

    report "gps_l1_ca_acq_fft_mix_fft_tb passed";
    wait;
  end process;
end architecture;
