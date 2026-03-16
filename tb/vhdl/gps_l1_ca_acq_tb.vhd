library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gps_l1_ca_log_pkg.all;

entity gps_l1_ca_acq_tb is
  generic (
    G_USE_FILE_INPUT      : boolean := false;
    G_INPUT_FILE          : string  := "2013_04_04_GNSS_SIGNAL_at_CTTC_SPAIN/2013_04_04_GNSS_SIGNAL_at_CTTC_SPAIN.dat";
    G_FILE_SAMPLE_RATE_SPS: integer := 4000000;
    G_DUT_SAMPLE_RATE_SPS : integer := 2000000;
    G_MAX_FILE_SAMPLES    : integer := 50000
  );
end entity;

architecture tb of gps_l1_ca_acq_tb is
  constant C_CLK_PERIOD : time := 10 ns;

  signal clk            : std_logic := '0';
  signal rst_n          : std_logic := '0';
  signal core_en        : std_logic := '0';
  signal start_pulse    : std_logic := '0';
  signal prn_start      : unsigned(5 downto 0) := to_unsigned(1, 6);
  signal prn_stop       : unsigned(5 downto 0) := to_unsigned(1, 6);
  signal doppler_min    : signed(15 downto 0) := to_signed(-2000, 16);
  signal doppler_max    : signed(15 downto 0) := to_signed(2000, 16);
  signal doppler_step   : signed(15 downto 0) := to_signed(250, 16);
  signal detect_thresh  : unsigned(31 downto 0) := (others => '0');
  signal s_valid        : std_logic := '0';
  signal s_i            : signed(15 downto 0) := (others => '0');
  signal s_q            : signed(15 downto 0) := (others => '0');

  signal acq_done       : std_logic;
  signal acq_success    : std_logic;
  signal result_valid   : std_logic;
  signal result_prn     : unsigned(5 downto 0);
  signal result_dopp    : signed(15 downto 0);
  signal result_code    : unsigned(10 downto 0);
  signal result_metric  : unsigned(31 downto 0);
begin
  clk <= not clk after C_CLK_PERIOD / 2;

  dut : entity work.gps_l1_ca_acq
    generic map (
      G_DWELL_MS => 1
    )
    port map (
      clk           => clk,
      rst_n         => rst_n,
      core_en       => core_en,
      start_pulse   => start_pulse,
      prn_start     => prn_start,
      prn_stop      => prn_stop,
      doppler_min   => doppler_min,
      doppler_max   => doppler_max,
      doppler_step  => doppler_step,
      detect_thresh => detect_thresh,
      s_valid       => s_valid,
      s_i           => s_i,
      s_q           => s_q,
      acq_done      => acq_done,
      acq_success   => acq_success,
      result_valid  => result_valid,
      result_prn    => result_prn,
      result_dopp   => result_dopp,
      result_code   => result_code,
      result_metric => result_metric
    );

  stim_proc : process
    type iq_file_t is file of character;
    file iq_file : iq_file_t;

    function s16_from_le(lo_b : character; hi_b : character) return signed is
      variable v_u16 : integer;
      variable v_s16 : integer;
    begin
      v_u16 := character'pos(lo_b) + 256 * character'pos(hi_b);
      if v_u16 >= 32768 then
        v_s16 := v_u16 - 65536;
      else
        v_s16 := v_u16;
      end if;
      return to_signed(v_s16, 16);
    end function;

    procedure pulse_start is
    begin
      start_pulse <= '1';
      wait until rising_edge(clk);
      start_pulse <= '0';
    end procedure;

    procedure drive_file_sample(i_v : in signed(15 downto 0); q_v : in signed(15 downto 0)) is
    begin
      s_valid <= '1';
      s_i <= i_v;
      s_q <= q_v;
      wait until rising_edge(clk);
      s_valid <= '0';
    end procedure;

    variable seen_done : boolean;
    variable read_status : file_open_status;
    variable b0          : character;
    variable b1          : character;
    variable b2          : character;
    variable b3          : character;
    variable in_file_cnt : integer := 0;
    variable out_samp_cnt: integer := 0;
    variable decim       : integer := 1;
    variable run1_metric_v      : unsigned(31 downto 0) := (others => '0');
    variable realistic_thresh_v : unsigned(31 downto 0) := (others => '0');
  begin
    rst_n <= '0';
    for i in 0 to 3 loop
      wait until rising_edge(clk);
    end loop;
    rst_n <= '1';
    core_en <= '1';
    if G_USE_FILE_INPUT then
      assert G_FILE_SAMPLE_RATE_SPS mod G_DUT_SAMPLE_RATE_SPS = 0
        report "File sample rate must be integer multiple of DUT sample rate."
        severity failure;
      decim := G_FILE_SAMPLE_RATE_SPS / G_DUT_SAMPLE_RATE_SPS;
      s_valid <= '0';
    else
      s_valid <= '1';
      s_i <= to_signed(300, 16);
      s_q <= to_signed(50, 16);
    end if;

    -- First run: threshold 0 should pass.
    detect_thresh <= (others => '0');
    pulse_start;

    seen_done := false;
    if G_USE_FILE_INPUT then
      in_file_cnt := 0;
      out_samp_cnt := 0;
      file_open(read_status, iq_file, G_INPUT_FILE, read_mode);
      assert read_status = open_ok
        report "Unable to open input file: " & G_INPUT_FILE
        severity failure;

      log_msg("gps_l1_ca_acq_tb replay input: " & G_INPUT_FILE);
      log_msg("Input Fs=" & integer'image(G_FILE_SAMPLE_RATE_SPS) &
              " -> DUT Fs=" & integer'image(G_DUT_SAMPLE_RATE_SPS) &
              ", decimation=" & integer'image(decim));

      while not endfile(iq_file) loop
        exit when seen_done;
        if G_MAX_FILE_SAMPLES > 0 and out_samp_cnt >= G_MAX_FILE_SAMPLES then
          exit;
        end if;

        if endfile(iq_file) then exit; end if;
        read(iq_file, b0);
        if endfile(iq_file) then exit; end if;
        read(iq_file, b1);
        if endfile(iq_file) then exit; end if;
        read(iq_file, b2);
        if endfile(iq_file) then exit; end if;
        read(iq_file, b3);

        if (in_file_cnt mod decim) = 0 then
          drive_file_sample(s16_from_le(b0, b1), s16_from_le(b2, b3));
          out_samp_cnt := out_samp_cnt + 1;
          if acq_done = '1' then
            seen_done := true;
          end if;
        end if;
        in_file_cnt := in_file_cnt + 1;
      end loop;

      file_close(iq_file);
      log_msg("Run1 file replay done. input_samples=" & integer'image(in_file_cnt) &
              ", injected_samples=" & integer'image(out_samp_cnt));

      if not seen_done then
        for i in 0 to 5000 loop
          drive_file_sample(to_signed(0, 16), to_signed(0, 16));
          if acq_done = '1' then
            seen_done := true;
            exit;
          end if;
        end loop;
      end if;
    else
      for i in 0 to 5000 loop
        wait until rising_edge(clk);
        if acq_done = '1' then
          seen_done := true;
          exit;
        end if;
      end loop;
    end if;

    assert seen_done report "Acquisition did not finish in first run." severity failure;
    assert acq_success = '1' report "Expected acquisition success with zero threshold." severity failure;
    assert result_valid = '1' report "Expected result_valid on successful acquisition." severity failure;
    assert to_integer(result_prn) = 1 report "Expected detected PRN to match configured PRN." severity failure;
    run1_metric_v := result_metric;
    realistic_thresh_v := shift_right(run1_metric_v, 1);
    if realistic_thresh_v = to_unsigned(0, realistic_thresh_v'length) then
      realistic_thresh_v := to_unsigned(1, realistic_thresh_v'length);
    end if;

    -- Second run: very high threshold should fail.
    detect_thresh <= (others => '1');
    pulse_start;

    seen_done := false;
    if G_USE_FILE_INPUT then
      in_file_cnt := 0;
      out_samp_cnt := 0;
      file_open(read_status, iq_file, G_INPUT_FILE, read_mode);
      assert read_status = open_ok
        report "Unable to open input file: " & G_INPUT_FILE
        severity failure;

      while not endfile(iq_file) loop
        exit when seen_done;
        if G_MAX_FILE_SAMPLES > 0 and out_samp_cnt >= G_MAX_FILE_SAMPLES then
          exit;
        end if;

        if endfile(iq_file) then exit; end if;
        read(iq_file, b0);
        if endfile(iq_file) then exit; end if;
        read(iq_file, b1);
        if endfile(iq_file) then exit; end if;
        read(iq_file, b2);
        if endfile(iq_file) then exit; end if;
        read(iq_file, b3);

        if (in_file_cnt mod decim) = 0 then
          drive_file_sample(s16_from_le(b0, b1), s16_from_le(b2, b3));
          out_samp_cnt := out_samp_cnt + 1;
          if acq_done = '1' then
            seen_done := true;
          end if;
        end if;
        in_file_cnt := in_file_cnt + 1;
      end loop;

      file_close(iq_file);
      log_msg("Run2 file replay done. input_samples=" & integer'image(in_file_cnt) &
              ", injected_samples=" & integer'image(out_samp_cnt));

      if not seen_done then
        for i in 0 to 5000 loop
          drive_file_sample(to_signed(0, 16), to_signed(0, 16));
          if acq_done = '1' then
            seen_done := true;
            exit;
          end if;
        end loop;
      end if;
    else
      for i in 0 to 5000 loop
        wait until rising_edge(clk);
        if acq_done = '1' then
          seen_done := true;
          exit;
        end if;
      end loop;
    end if;

    assert seen_done report "Acquisition did not finish in second run." severity failure;
    assert acq_success = '0' report "Expected acquisition failure with max threshold." severity failure;
    assert result_valid = '0' report "Did not expect result_valid on failed acquisition." severity failure;
    assert result_metric /= to_unsigned(0, result_metric'length)
      report "Expected non-zero metric for exercised acquisition path." severity failure;
    assert result_dopp >= doppler_min and result_dopp <= doppler_max
      report "Estimated Doppler should stay within configured range." severity failure;

    -- Third run: realistic non-zero threshold should pass.
    detect_thresh <= realistic_thresh_v;
    pulse_start;

    seen_done := false;
    if G_USE_FILE_INPUT then
      in_file_cnt := 0;
      out_samp_cnt := 0;
      file_open(read_status, iq_file, G_INPUT_FILE, read_mode);
      assert read_status = open_ok
        report "Unable to open input file: " & G_INPUT_FILE
        severity failure;

      while not endfile(iq_file) loop
        exit when seen_done;
        if G_MAX_FILE_SAMPLES > 0 and out_samp_cnt >= G_MAX_FILE_SAMPLES then
          exit;
        end if;

        if endfile(iq_file) then exit; end if;
        read(iq_file, b0);
        if endfile(iq_file) then exit; end if;
        read(iq_file, b1);
        if endfile(iq_file) then exit; end if;
        read(iq_file, b2);
        if endfile(iq_file) then exit; end if;
        read(iq_file, b3);

        if (in_file_cnt mod decim) = 0 then
          drive_file_sample(s16_from_le(b0, b1), s16_from_le(b2, b3));
          out_samp_cnt := out_samp_cnt + 1;
          if acq_done = '1' then
            seen_done := true;
          end if;
        end if;
        in_file_cnt := in_file_cnt + 1;
      end loop;

      file_close(iq_file);
      log_msg("Run3 file replay done. input_samples=" & integer'image(in_file_cnt) &
              ", injected_samples=" & integer'image(out_samp_cnt));

      if not seen_done then
        for i in 0 to 5000 loop
          drive_file_sample(to_signed(0, 16), to_signed(0, 16));
          if acq_done = '1' then
            seen_done := true;
            exit;
          end if;
        end loop;
      end if;
    else
      for i in 0 to 5000 loop
        wait until rising_edge(clk);
        if acq_done = '1' then
          seen_done := true;
          exit;
        end if;
      end loop;
    end if;

    assert seen_done report "Acquisition did not finish in third run." severity failure;
    assert realistic_thresh_v > to_unsigned(0, realistic_thresh_v'length)
      report "Expected realistic threshold to be non-zero." severity failure;
    assert acq_success = '1'
      report "Expected acquisition success with realistic threshold." severity failure;
    assert result_valid = '1'
      report "Expected result_valid with realistic threshold." severity failure;
    assert result_metric >= realistic_thresh_v
      report "Expected acquisition metric to clear realistic threshold." severity failure;
    assert result_dopp >= doppler_min and result_dopp <= doppler_max
      report "Estimated Doppler should stay within configured range in third run." severity failure;

    log_msg("gps_l1_ca_acq_tb completed");
    wait;
  end process;
end architecture;
