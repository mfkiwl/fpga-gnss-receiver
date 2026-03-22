library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.gps_l1_ca_acq_fft_pkg.all;

entity gps_l1_ca_acq_fft_code_gen_tb is
  generic (
    G_PRN_SEQ_FILE  : string := "sim/vectors/acq_fft_prn_prn7.txt";
    G_CODE_FFT_FILE : string := "sim/vectors/acq_fft_code_gen_expected_prn7_code17.txt"
  );
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
    procedure load_prn_seq(path_v : in string; variable seq_v : out prn_seq_t) is
      file seq_file : text;
      variable read_status_v : file_open_status;
      variable l_v : line;
      variable bit_v : integer;
      variable idx_v : integer := 0;
    begin
      file_open(read_status_v, seq_file, path_v, read_mode);
      assert read_status_v = open_ok
        report "Unable to open PRN vector file: " & path_v
        severity failure;

      while not endfile(seq_file) loop
        readline(seq_file, l_v);
        read(l_v, bit_v);
        assert idx_v <= 1022
          report "Too many PRN chips in vector file: " & path_v
          severity failure;
        if bit_v = 0 then
          seq_v(idx_v) := '0';
        else
          seq_v(idx_v) := '1';
        end if;
        idx_v := idx_v + 1;
      end loop;
      file_close(seq_file);

      assert idx_v = 1023
        report "Expected 1023 chips in PRN vector file: " & path_v
        severity failure;
    end procedure;

    procedure load_fft(path_v : in string; variable fft_v : out cpx32_vec_t) is
      file fft_file : text;
      variable read_status_v : file_open_status;
      variable l_v : line;
      variable re_v : integer;
      variable im_v : integer;
      variable idx_v : integer := 0;
    begin
      file_open(read_status_v, fft_file, path_v, read_mode);
      assert read_status_v = open_ok
        report "Unable to open code FFT vector file: " & path_v
        severity failure;

      while not endfile(fft_file) loop
        readline(fft_file, l_v);
        read(l_v, re_v);
        read(l_v, im_v);
        assert idx_v <= C_NFFT - 1
          report "Too many FFT bins in vector file: " & path_v
          severity failure;
        fft_v(idx_v).re := to_signed(re_v, 32);
        fft_v(idx_v).im := to_signed(im_v, 32);
        idx_v := idx_v + 1;
      end loop;
      file_close(fft_file);

      assert idx_v = C_NFFT
        report "Expected " & integer'image(C_NFFT) & " FFT bins in vector file: " & path_v
        severity failure;
    end procedure;

    variable prn_seq_v      : prn_seq_t;
    variable expected_fft_v : cpx32_vec_t;
    variable wrap_fft_v     : cpx32_vec_t;
    variable edge_fft_v     : cpx32_vec_t;
    variable edge_wrap_fft_v: cpx32_vec_t;
  begin
    rst_n <= '0';
    wait for 3 * C_CLK_PERIOD;
    assert done_o = '0'
      report "Code FFT generator done_o should remain low during reset"
      severity failure;
    rst_n <= '1';
    wait until rising_edge(clk);

    load_prn_seq(G_PRN_SEQ_FILE, prn_seq_v);
    load_fft(G_CODE_FFT_FILE, expected_fft_v);

    prn_seq_i <= prn_seq_v;
    code_start_i <= to_unsigned(17, 11);
    wait until rising_edge(clk);

    start <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    assert done_o = '1'
      report "Code FFT generator did not assert done"
      severity failure;
    start <= '0';
    wait until rising_edge(clk);

    for k in 0 to C_NFFT - 1 loop
      assert code_fft_o(k).re = expected_fft_v(k).re
        report "Code FFT real mismatch at bin " & integer'image(k)
        severity failure;
      assert code_fft_o(k).im = expected_fft_v(k).im
        report "Code FFT imag mismatch at bin " & integer'image(k)
        severity failure;
    end loop;

    -- Boundary checks for code_start wrap behavior.
    wrap_fft_v := fft_radix2(build_code_fft_input(prn_seq_v, 0), false);
    edge_fft_v := fft_radix2(build_code_fft_input(prn_seq_v, 1022), false);
    edge_wrap_fft_v := fft_radix2(build_code_fft_input(prn_seq_v, 1023), false);

    code_start_i <= to_unsigned(0, code_start_i'length);
    start <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    assert done_o = '1'
      report "Code FFT generator did not assert done for code_start=0"
      severity failure;
    start <= '0';
    wait until rising_edge(clk);
    for k in 0 to C_NFFT - 1 loop
      assert code_fft_o(k).re = wrap_fft_v(k).re
        report "Code FFT mismatch for code_start=0 at bin " & integer'image(k)
        severity failure;
      assert code_fft_o(k).im = wrap_fft_v(k).im
        report "Code FFT mismatch for code_start=0 at bin " & integer'image(k)
        severity failure;
    end loop;

    code_start_i <= to_unsigned(1022, code_start_i'length);
    start <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    assert done_o = '1'
      report "Code FFT generator did not assert done for code_start=1022"
      severity failure;
    start <= '0';
    wait until rising_edge(clk);
    for k in 0 to C_NFFT - 1 loop
      assert code_fft_o(k).re = edge_fft_v(k).re
        report "Code FFT mismatch for code_start=1022 at bin " & integer'image(k)
        severity failure;
      assert code_fft_o(k).im = edge_fft_v(k).im
        report "Code FFT mismatch for code_start=1022 at bin " & integer'image(k)
        severity failure;
    end loop;

    code_start_i <= to_unsigned(1023, code_start_i'length);
    start <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    assert done_o = '1'
      report "Code FFT generator did not assert done for code_start=1023"
      severity failure;
    start <= '0';
    wait until rising_edge(clk);
    for k in 0 to C_NFFT - 1 loop
      assert code_fft_o(k).re = edge_wrap_fft_v(k).re
        report "Code FFT mismatch for code_start=1023 at bin " & integer'image(k)
        severity failure;
      assert code_fft_o(k).im = edge_wrap_fft_v(k).im
        report "Code FFT mismatch for code_start=1023 at bin " & integer'image(k)
        severity failure;
    end loop;

    for k in 0 to C_NFFT - 1 loop
      assert edge_wrap_fft_v(k).re = wrap_fft_v(k).re and
             edge_wrap_fft_v(k).im = wrap_fft_v(k).im
        report "Expected code_start 1023 to wrap to code_start 0"
        severity failure;
    end loop;

    -- Held start should keep done asserted while start is asserted.
    code_start_i <= to_unsigned(17, code_start_i'length);
    start <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    assert done_o = '1'
      report "Code FFT generator expected done_o=1 on held-start cycle A"
      severity failure;
    wait until rising_edge(clk);
    wait for 1 ns;
    assert done_o = '1'
      report "Code FFT generator expected done_o=1 on held-start cycle B"
      severity failure;
    start <= '0';
    wait until rising_edge(clk);

    -- Reset must dominate start and clear outputs.
    start <= '1';
    rst_n <= '0';
    wait until rising_edge(clk);
    wait for 1 ns;
    assert done_o = '0'
      report "Code FFT generator done_o must remain low during reset"
      severity failure;
    for k in 0 to C_NFFT - 1 loop
      assert code_fft_o(k).re = to_signed(0, 32) and code_fft_o(k).im = to_signed(0, 32)
        report "Code FFT generator output should clear during reset"
        severity failure;
    end loop;
    start <= '0';
    rst_n <= '1';
    wait until rising_edge(clk);

    report "gps_l1_ca_acq_fft_code_gen_tb passed";
    wait;
  end process;
end architecture;
