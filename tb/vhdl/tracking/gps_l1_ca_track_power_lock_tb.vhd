library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;
use work.gps_l1_ca_track_pkg.all;

entity gps_l1_ca_track_power_lock_tb is
  generic (
    G_VECTOR_FILE : string := "sim/vectors/track_power_lock_vectors.txt"
  );
end entity;

architecture tb of gps_l1_ca_track_power_lock_tb is
  signal prompt_i_s     : integer := 0;
  signal prompt_q_s     : integer := 0;
  signal early_i_s      : integer := 0;
  signal early_q_s      : integer := 0;
  signal late_i_s       : integer := 0;
  signal late_q_s       : integer := 0;
  signal cn0_sig_avg_s  : integer := 1;
  signal cn0_noise_avg_s: integer := 1;
  signal nbd_avg_s      : integer := 0;
  signal nbp_avg_s      : integer := 1;

  signal cn0_sig_avg_o_s   : integer;
  signal cn0_noise_avg_o_s : integer;
  signal nbd_avg_o_s       : integer;
  signal nbp_avg_o_s       : integer;
  signal cn0_dbhz_o_s      : integer;
  signal carrier_metric_o_s: integer;

begin
  dut : entity work.gps_l1_ca_track_power_lock
    port map (
      prompt_i_s_i     => prompt_i_s,
      prompt_q_s_i     => prompt_q_s,
      early_i_s_i      => early_i_s,
      early_q_s_i      => early_q_s,
      late_i_s_i       => late_i_s,
      late_q_s_i       => late_q_s,
      cn0_sig_avg_i    => cn0_sig_avg_s,
      cn0_noise_avg_i  => cn0_noise_avg_s,
      nbd_avg_i        => nbd_avg_s,
      nbp_avg_i        => nbp_avg_s,
      cn0_sig_avg_o    => cn0_sig_avg_o_s,
      cn0_noise_avg_o  => cn0_noise_avg_o_s,
      nbd_avg_o        => nbd_avg_o_s,
      nbp_avg_o        => nbp_avg_o_s,
      cn0_dbhz_o       => cn0_dbhz_o_s,
      carrier_metric_o => carrier_metric_o_s
    );

  stim : process
    file vec_file            : text;
    variable read_status_v   : file_open_status;
    variable l_v             : line;
    variable case_count_v    : integer;
    variable prompt_i_v      : integer;
    variable prompt_q_v      : integer;
    variable early_i_v       : integer;
    variable early_q_v       : integer;
    variable late_i_v        : integer;
    variable late_q_v        : integer;
    variable cn0_sig_i_v     : integer;
    variable cn0_noise_i_v   : integer;
    variable nbd_i_v         : integer;
    variable nbp_i_v         : integer;
    variable exp_sig_avg_v   : integer;
    variable exp_noise_avg_v : integer;
    variable exp_nbd_avg_v   : integer;
    variable exp_nbp_avg_v   : integer;
    variable exp_cn0_v       : integer;
    variable exp_metric_v    : integer;
  begin
    file_open(read_status_v, vec_file, G_VECTOR_FILE, read_mode);
    assert read_status_v = open_ok
      report "Unable to open power/lock vector file: " & G_VECTOR_FILE
      severity failure;

    readline(vec_file, l_v);
    read(l_v, case_count_v);
    assert case_count_v > 0
      report "Expected at least one power/lock vector row."
      severity failure;

    for case_idx_v in 0 to case_count_v - 1 loop
      readline(vec_file, l_v);
      read(l_v, prompt_i_v);
      read(l_v, prompt_q_v);
      read(l_v, early_i_v);
      read(l_v, early_q_v);
      read(l_v, late_i_v);
      read(l_v, late_q_v);
      read(l_v, cn0_sig_i_v);
      read(l_v, cn0_noise_i_v);
      read(l_v, nbd_i_v);
      read(l_v, nbp_i_v);
      read(l_v, exp_sig_avg_v);
      read(l_v, exp_noise_avg_v);
      read(l_v, exp_nbd_avg_v);
      read(l_v, exp_nbp_avg_v);
      read(l_v, exp_cn0_v);
      read(l_v, exp_metric_v);

      prompt_i_s <= prompt_i_v;
      prompt_q_s <= prompt_q_v;
      early_i_s <= early_i_v;
      early_q_s <= early_q_v;
      late_i_s <= late_i_v;
      late_q_s <= late_q_v;
      cn0_sig_avg_s <= cn0_sig_i_v;
      cn0_noise_avg_s <= cn0_noise_i_v;
      nbd_avg_s <= nbd_i_v;
      nbp_avg_s <= nbp_i_v;
      wait for 1 ns;

      assert cn0_sig_avg_o_s = exp_sig_avg_v
        report "cn0_sig_avg mismatch at power/lock case " & integer'image(case_idx_v)
        severity failure;
      assert cn0_noise_avg_o_s = exp_noise_avg_v
        report "cn0_noise_avg mismatch at power/lock case " & integer'image(case_idx_v)
        severity failure;
      assert nbd_avg_o_s = exp_nbd_avg_v
        report "nbd_avg mismatch at power/lock case " & integer'image(case_idx_v)
        severity failure;
      assert nbp_avg_o_s = exp_nbp_avg_v
        report "nbp_avg mismatch at power/lock case " & integer'image(case_idx_v)
        severity failure;
      assert cn0_dbhz_o_s = exp_cn0_v
        report "cn0_dbhz mismatch at power/lock case " & integer'image(case_idx_v)
        severity failure;
      assert carrier_metric_o_s = exp_metric_v
        report "carrier_metric mismatch at power/lock case " & integer'image(case_idx_v)
        severity failure;
    end loop;

    file_close(vec_file);

    finish;
  end process;
end architecture;
