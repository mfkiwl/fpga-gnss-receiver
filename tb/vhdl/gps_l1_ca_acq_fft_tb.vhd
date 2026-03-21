library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gps_l1_ca_pkg.all;

entity gps_l1_ca_acq_fft_tb is
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
    variable seen_done_v : boolean := false;
  begin
    rst_n <= '0';
    core_en <= '0';
    wait for 3 * C_CLK_PERIOD;
    rst_n <= '1';
    wait until rising_edge(clk);

    core_en <= '1';
    start_pulse <= '1';
    wait until rising_edge(clk);
    start_pulse <= '0';

    for i in 0 to C_SAMPLES_PER_MS + 1024 loop
      s_valid <= '1';
      s_i <= (others => '0');
      s_q <= (others => '0');
      wait until rising_edge(clk);
      if acq_done = '1' then
        seen_done_v := true;
        exit;
      end if;
    end loop;

    assert seen_done_v
      report "FFT block did not complete acquisition"
      severity failure;
    assert acq_success = '1'
      report "FFT block expected success with zero threshold"
      severity failure;
    assert result_valid = '1'
      report "FFT block expected valid result on success"
      severity failure;
    assert result_prn = to_unsigned(1, 6)
      report "FFT block returned unexpected PRN"
      severity failure;

    report "gps_l1_ca_acq_fft_tb passed";
    wait;
  end process;
end architecture;
