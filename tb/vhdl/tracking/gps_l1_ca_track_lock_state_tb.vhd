library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;
use work.gps_l1_ca_pkg.all;
use work.gps_l1_ca_track_pkg.all;

entity gps_l1_ca_track_lock_state_tb is
  generic (
    G_VECTOR_FILE : string := "sim/vectors/track_lock_state_vectors.txt"
  );
end entity;

architecture tb of gps_l1_ca_track_lock_state_tb is
  signal state_s           : track_state_t := TRACK_PULLIN;
  signal prompt_mag_s      : integer := 0;
  signal cn0_dbhz_s        : integer := 0;
  signal min_cn0_dbhz_s    : unsigned(7 downto 0) := (others => '0');
  signal dll_err_q15_s     : integer := 0;
  signal carrier_metric_s  : integer := 0;
  signal carrier_err_q15_s : integer := 0;
  signal carrier_lock_th_s : signed(15 downto 0) := (others => '0');
  signal max_lock_fail_s   : unsigned(7 downto 0) := (others => '0');
  signal lock_score_s      : integer := 0;

  signal state_o_s         : track_state_t;
  signal code_lock_o_s     : std_logic;
  signal carrier_lock_o_s  : std_logic;
  signal lock_score_o_s    : integer;
begin
  dut : entity work.gps_l1_ca_track_lock_state
    port map (
      state_i           => state_s,
      prompt_mag_i      => prompt_mag_s,
      cn0_dbhz_i        => cn0_dbhz_s,
      min_cn0_dbhz_i    => min_cn0_dbhz_s,
      dll_err_q15_i     => dll_err_q15_s,
      carrier_metric_i  => carrier_metric_s,
      carrier_err_q15_i => carrier_err_q15_s,
      carrier_lock_th_i => carrier_lock_th_s,
      max_lock_fail_i   => max_lock_fail_s,
      lock_score_i      => lock_score_s,
      state_o           => state_o_s,
      code_lock_o       => code_lock_o_s,
      carrier_lock_o    => carrier_lock_o_s,
      lock_score_o      => lock_score_o_s
    );

  stim : process
    file vec_file              : text;
    variable read_status_v     : file_open_status;
    variable l_v               : line;
    variable case_count_v      : integer;
    variable state_v           : integer;
    variable prompt_mag_v      : integer;
    variable cn0_v             : integer;
    variable min_cn0_v         : integer;
    variable dll_err_v         : integer;
    variable carrier_metric_v  : integer;
    variable carrier_err_v     : integer;
    variable carrier_lock_th_v : integer;
    variable max_lock_fail_v   : integer;
    variable lock_score_v      : integer;
    variable exp_state_v       : integer;
    variable exp_code_lock_v   : integer;
    variable exp_carrier_lock_v: integer;
    variable exp_lock_score_v  : integer;
  begin
    file_open(read_status_v, vec_file, G_VECTOR_FILE, read_mode);
    assert read_status_v = open_ok
      report "Unable to open lock-state vector file: " & G_VECTOR_FILE
      severity failure;

    readline(vec_file, l_v);
    read(l_v, case_count_v);
    assert case_count_v > 0
      report "Expected at least one lock-state vector row."
      severity failure;

    for case_idx_v in 0 to case_count_v - 1 loop
      readline(vec_file, l_v);
      read(l_v, state_v);
      read(l_v, prompt_mag_v);
      read(l_v, cn0_v);
      read(l_v, min_cn0_v);
      read(l_v, dll_err_v);
      read(l_v, carrier_metric_v);
      read(l_v, carrier_err_v);
      read(l_v, carrier_lock_th_v);
      read(l_v, max_lock_fail_v);
      read(l_v, lock_score_v);
      read(l_v, exp_state_v);
      read(l_v, exp_code_lock_v);
      read(l_v, exp_carrier_lock_v);
      read(l_v, exp_lock_score_v);

      if state_v = 2 then
        state_s <= TRACK_LOCKED;
      elsif state_v = 0 then
        state_s <= TRACK_IDLE;
      else
        state_s <= TRACK_PULLIN;
      end if;

      prompt_mag_s <= prompt_mag_v;
      cn0_dbhz_s <= cn0_v;
      min_cn0_dbhz_s <= to_unsigned(min_cn0_v, min_cn0_dbhz_s'length);
      dll_err_q15_s <= dll_err_v;
      carrier_metric_s <= carrier_metric_v;
      carrier_err_q15_s <= carrier_err_v;
      carrier_lock_th_s <= to_signed(carrier_lock_th_v, carrier_lock_th_s'length);
      max_lock_fail_s <= to_unsigned(max_lock_fail_v, max_lock_fail_s'length);
      lock_score_s <= lock_score_v;
      wait for 1 ns;

      if exp_state_v = 2 then
        assert state_o_s = TRACK_LOCKED
          report "state mismatch at lock-state case " & integer'image(case_idx_v)
          severity failure;
      elsif exp_state_v = 0 then
        assert state_o_s = TRACK_IDLE
          report "state mismatch at lock-state case " & integer'image(case_idx_v)
          severity failure;
      else
        assert state_o_s = TRACK_PULLIN
          report "state mismatch at lock-state case " & integer'image(case_idx_v)
          severity failure;
      end if;

      if exp_code_lock_v /= 0 then
        assert code_lock_o_s = '1'
          report "code_lock mismatch at lock-state case " & integer'image(case_idx_v)
          severity failure;
      else
        assert code_lock_o_s = '0'
          report "code_lock mismatch at lock-state case " & integer'image(case_idx_v)
          severity failure;
      end if;

      if exp_carrier_lock_v /= 0 then
        assert carrier_lock_o_s = '1'
          report "carrier_lock mismatch at lock-state case " & integer'image(case_idx_v)
          severity failure;
      else
        assert carrier_lock_o_s = '0'
          report "carrier_lock mismatch at lock-state case " & integer'image(case_idx_v)
          severity failure;
      end if;
      assert lock_score_o_s = exp_lock_score_v
        report "lock_score mismatch at lock-state case " & integer'image(case_idx_v)
        severity failure;
    end loop;

    file_close(vec_file);

    finish;
  end process;
end architecture;
