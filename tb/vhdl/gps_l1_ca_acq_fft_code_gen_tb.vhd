library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gps_l1_ca_acq_fft_pkg.all;

entity gps_l1_ca_acq_fft_code_gen_tb is
end entity;

architecture tb of gps_l1_ca_acq_fft_code_gen_tb is
  constant C_CLK_PERIOD : time := 10 ns;

  signal clk          : std_logic := '0';
  signal rst_n        : std_logic := '0';
  signal start        : std_logic := '0';
  signal prn_seq_i    : prn_seq_t := (others => '0');
  signal code_start_i : unsigned(10 downto 0) := (others => '0');
  signal code_fft_o   : cpx32_vec_t;
  signal done_o       : std_logic;
begin
  clk <= not clk after C_CLK_PERIOD / 2;

  dut : entity work.gps_l1_ca_acq_fft_code_gen
    port map (
      clk          => clk,
      rst_n        => rst_n,
      start        => start,
      prn_seq_i    => prn_seq_i,
      code_start_i => code_start_i,
      code_fft_o   => code_fft_o,
      done_o       => done_o
    );

  stim_proc : process
    variable expected_fft_v : cpx32_vec_t;
  begin
    rst_n <= '0';
    wait for 3 * C_CLK_PERIOD;
    rst_n <= '1';
    wait until rising_edge(clk);

    prn_seq_i <= build_prn_sequence(7);
    code_start_i <= to_unsigned(17, 11);
    wait until rising_edge(clk);

    start <= '1';
    wait until rising_edge(clk);
    start <= '0';
    wait until rising_edge(clk);

    assert done_o = '1'
      report "Code FFT generator did not assert done"
      severity failure;

    expected_fft_v := fft_radix2(
      build_code_fft_input(build_prn_sequence(7), 17),
      false
    );

    for k in 0 to C_NFFT - 1 loop
      assert code_fft_o(k).re = expected_fft_v(k).re
        report "Code FFT real mismatch at bin " & integer'image(k)
        severity failure;
      assert code_fft_o(k).im = expected_fft_v(k).im
        report "Code FFT imag mismatch at bin " & integer'image(k)
        severity failure;
    end loop;

    report "gps_l1_ca_acq_fft_code_gen_tb passed";
    wait;
  end process;
end architecture;
