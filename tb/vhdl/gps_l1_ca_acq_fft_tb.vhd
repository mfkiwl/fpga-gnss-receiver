library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.gps_l1_ca_pkg.all;

entity gps_l1_ca_acq_fft_tb is
  generic (
    G_EXPECTED_FILE : string := "sim/vectors/acq_fft_tb_expected.txt"
  );
end entity;

architecture tb of gps_l1_ca_acq_fft_tb is
  constant C_CLK_PERIOD : time := 10 ns;

  signal clk                  : std_logic := '0';
  signal rst_n                : std_logic := '0';
  signal core_en              : std_logic := '0';
  signal start_pulse          : std_logic := '0';
  signal prn_start            : unsigned(5 downto 0) := to_unsigned(1, 6);
  signal prn_stop             : unsigned(5 downto 0) := to_unsigned(1, 6);
  signal doppler_min          : signed(15 downto 0) := to_signed(-1000, 16);
  signal doppler_max          : signed(15 downto 0) := to_signed(1000, 16);
  signal doppler_step         : signed(15 downto 0) := to_signed(250, 16);
  signal detect_thresh        : unsigned(31 downto 0) := (others => '0');
  signal coh_ms_i             : unsigned(7 downto 0) := to_unsigned(1, 8);
  signal noncoh_dwells_i      : unsigned(7 downto 0) := to_unsigned(1, 8);
  signal doppler_bin_count_i  : unsigned(7 downto 0) := to_unsigned(1, 8);
  signal code_bin_count_i     : unsigned(10 downto 0) := to_unsigned(1, 11);
  signal code_bin_step_i      : unsigned(10 downto 0) := to_unsigned(1, 11);
  signal s_valid              : std_logic := '0';
  signal s_i                  : signed(15 downto 0) := (others => '0');
  signal s_q                  : signed(15 downto 0) := (others => '0');
  signal acq_done             : std_logic;
  signal acq_success          : std_logic;
  signal result_valid         : std_logic;
  signal result_prn           : unsigned(5 downto 0);
  signal result_dopp          : signed(15 downto 0);
  signal result_code          : unsigned(10 downto 0);
  signal result_metric        : unsigned(31 downto 0);
begin
  clk <= not clk after C_CLK_PERIOD / 2;

  dut : entity work.gps_l1_ca_acq_fft
    generic map (
      G_DWELL_MS => 1
    )
    port map (
      clk                 => clk,
      rst_n               => rst_n,
      core_en             => core_en,
      start_pulse         => start_pulse,
      prn_start           => prn_start,
      prn_stop            => prn_stop,
      doppler_min         => doppler_min,
      doppler_max         => doppler_max,
      doppler_step        => doppler_step,
      detect_thresh       => detect_thresh,
      coh_ms_i            => coh_ms_i,
      noncoh_dwells_i     => noncoh_dwells_i,
      doppler_bin_count_i => doppler_bin_count_i,
      code_bin_count_i    => code_bin_count_i,
      code_bin_step_i     => code_bin_step_i,
      s_valid             => s_valid,
      s_i                 => s_i,
      s_q                 => s_q,
      acq_done            => acq_done,
      acq_success         => acq_success,
      result_valid        => result_valid,
      result_prn          => result_prn,
      result_dopp         => result_dopp,
      result_code         => result_code,
      result_metric       => result_metric
    );

  stim_proc : process
    file exp_file : text;
    variable read_status_v : file_open_status;
    variable l_v : line;
    variable exp_prn_v : integer;
    variable exp_dopp_v : integer;
    variable exp_code_v : integer;
    variable exp_metric_v : integer;
    variable seen_done_v : boolean := false;
    procedure pulse_start is
    begin
      start_pulse <= '1';
      wait until rising_edge(clk);
      start_pulse <= '0';
    end procedure;

    procedure run_constant_input_until_done(
      i_samp_v : in signed(15 downto 0);
      q_samp_v : in signed(15 downto 0);
      timeout_cycles_v : in integer
    ) is
    begin
      seen_done_v := false;
      for i in 0 to timeout_cycles_v loop
        s_valid <= '1';
        s_i <= i_samp_v;
        s_q <= q_samp_v;
        wait until rising_edge(clk);
        if acq_done = '1' then
          seen_done_v := true;
          exit;
        end if;
      end loop;
      s_valid <= '0';
    end procedure;
  begin
    rst_n <= '0';
    core_en <= '0';
    wait for 3 * C_CLK_PERIOD;
    rst_n <= '1';
    wait until rising_edge(clk);

    file_open(read_status_v, exp_file, G_EXPECTED_FILE, read_mode);
    assert read_status_v = open_ok
      report "Unable to open acquisition FFT expected tuple file: " & G_EXPECTED_FILE
      severity failure;
    readline(exp_file, l_v);
    read(l_v, exp_prn_v);
    read(l_v, exp_dopp_v);
    read(l_v, exp_code_v);
    read(l_v, exp_metric_v);
    file_close(exp_file);

    core_en <= '1';
    pulse_start;
    run_constant_input_until_done(to_signed(0, 16), to_signed(0, 16), C_SAMPLES_PER_MS * 8);

    assert seen_done_v
      report "FFT block did not complete acquisition"
      severity failure;
    assert acq_success = '1'
      report "FFT block expected success with zero threshold"
      severity failure;
    assert result_valid = '1'
      report "FFT block expected valid result on success"
      severity failure;
    assert to_integer(result_prn) = exp_prn_v
      report "FFT block returned unexpected PRN"
      severity failure;
    assert to_integer(result_dopp) = exp_dopp_v
      report "FFT block returned unexpected Doppler"
      severity failure;
    assert to_integer(result_code) = exp_code_v
      report "FFT block returned unexpected code phase"
      severity failure;
    assert to_integer(result_metric) = exp_metric_v
      report "FFT block returned unexpected metric"
      severity failure;
    wait until rising_edge(clk);
    assert acq_done = '0'
      report "FFT block acq_done should pulse for one cycle"
      severity failure;

    -- Multi-bin deterministic tie case with zero input:
    -- tie-break should choose the final searched bin.
    prn_start <= to_unsigned(1, 6);
    prn_stop <= to_unsigned(1, 6);
    doppler_min <= to_signed(-250, 16);
    doppler_max <= to_signed(250, 16);
    doppler_step <= to_signed(250, 16);
    doppler_bin_count_i <= to_unsigned(3, doppler_bin_count_i'length);
    code_bin_count_i <= to_unsigned(4, code_bin_count_i'length);
    code_bin_step_i <= to_unsigned(16, code_bin_step_i'length);
    detect_thresh <= to_unsigned(0, detect_thresh'length);

    pulse_start;
    run_constant_input_until_done(to_signed(0, 16), to_signed(0, 16), C_SAMPLES_PER_MS * 12);

    assert seen_done_v
      report "FFT multi-bin case did not complete acquisition"
      severity failure;
    assert acq_success = '1'
      report "FFT multi-bin case expected success with zero threshold"
      severity failure;
    assert result_valid = '1'
      report "FFT multi-bin case expected result_valid=1"
      severity failure;
    assert to_integer(result_prn) = 1
      report "FFT multi-bin case expected PRN=1"
      severity failure;
    assert to_integer(result_dopp) = 250
      report "FFT multi-bin case expected tie-break Doppler=250"
      severity failure;
    assert to_integer(result_code) = 48
      report "FFT multi-bin case expected tie-break code=48"
      severity failure;
    assert to_integer(result_metric) = 0
      report "FFT multi-bin case expected zero metric"
      severity failure;
    wait until rising_edge(clk);
    assert acq_done = '0'
      report "FFT multi-bin case acq_done should pulse for one cycle"
      severity failure;

    -- Explicit fail path: no signal with non-zero threshold must reject.
    detect_thresh <= to_unsigned(1, detect_thresh'length);
    pulse_start;
    run_constant_input_until_done(to_signed(0, 16), to_signed(0, 16), C_SAMPLES_PER_MS * 12);

    assert seen_done_v
      report "FFT threshold-reject case did not complete acquisition"
      severity failure;
    assert acq_success = '0'
      report "FFT threshold-reject case expected acq_success=0"
      severity failure;
    assert result_valid = '0'
      report "FFT threshold-reject case expected result_valid=0"
      severity failure;
    wait until rising_edge(clk);
    assert acq_done = '0'
      report "FFT threshold-reject case acq_done should pulse for one cycle"
      severity failure;

    report "gps_l1_ca_acq_fft_tb passed";
    wait;
  end process;
end architecture;
