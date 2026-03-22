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
  begin
    rst_n <= '0';
    wait for 3 * C_CLK_PERIOD;
    rst_n <= '1';
    wait until rising_edge(clk);

    load_prn_seq(G_PRN_SEQ_FILE, prn_seq_v);
    load_fft(G_CODE_FFT_FILE, expected_fft_v);

    prn_seq_i <= prn_seq_v;
    code_start_i <= to_unsigned(17, 11);
    wait until rising_edge(clk);

    start <= '1';
    wait until rising_edge(clk);
    start <= '0';
    wait until rising_edge(clk);

    assert done_o = '1'
      report "Code FFT generator did not assert done"
      severity failure;

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
