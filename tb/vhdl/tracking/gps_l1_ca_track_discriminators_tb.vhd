library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;
use work.gps_l1_ca_pkg.all;
use work.gps_l1_ca_track_pkg.all;

entity gps_l1_ca_track_discriminators_tb is
  generic (
    G_VECTOR_FILE : string := "sim/vectors/track_discriminators_vectors.txt"
  );
end entity;

architecture tb of gps_l1_ca_track_discriminators_tb is
  signal state_s            : track_state_t := TRACK_PULLIN;
  signal prompt_i_acc_s     : signed(31 downto 0) := (others => '0');
  signal prompt_q_acc_s     : signed(31 downto 0) := (others => '0');
  signal early_i_acc_s      : signed(31 downto 0) := (others => '0');
  signal early_q_acc_s      : signed(31 downto 0) := (others => '0');
  signal late_i_acc_s       : signed(31 downto 0) := (others => '0');
  signal late_q_acc_s       : signed(31 downto 0) := (others => '0');
  signal prev_prompt_i_s    : signed(31 downto 0) := (others => '0');
  signal prev_prompt_q_s    : signed(31 downto 0) := (others => '0');
  signal prev_prompt_valid_s: std_logic := '0';

  signal prompt_mag_s       : integer;
  signal early_mag_s        : integer;
  signal late_mag_s         : integer;
  signal dll_err_q15_s      : integer;
  signal carrier_err_pll_q15_s : integer;
  signal carrier_err_fll_q15_s : integer;
  signal carrier_err_sel_q15_s : integer;
  signal prompt_i_s         : integer;
  signal prompt_q_s         : integer;
  signal early_i_s          : integer;
  signal early_q_s          : integer;
  signal late_i_s           : integer;
  signal late_q_s           : integer;
begin
  dut : entity work.gps_l1_ca_track_discriminators
    port map (
      state_i               => state_s,
      prompt_i_acc_i        => prompt_i_acc_s,
      prompt_q_acc_i        => prompt_q_acc_s,
      early_i_acc_i         => early_i_acc_s,
      early_q_acc_i         => early_q_acc_s,
      late_i_acc_i          => late_i_acc_s,
      late_q_acc_i          => late_q_acc_s,
      prev_prompt_i_i       => prev_prompt_i_s,
      prev_prompt_q_i       => prev_prompt_q_s,
      prev_prompt_valid_i   => prev_prompt_valid_s,
      prompt_mag_o          => prompt_mag_s,
      early_mag_o           => early_mag_s,
      late_mag_o            => late_mag_s,
      dll_err_q15_o         => dll_err_q15_s,
      carrier_err_pll_q15_o => carrier_err_pll_q15_s,
      carrier_err_fll_q15_o => carrier_err_fll_q15_s,
      carrier_err_sel_q15_o => carrier_err_sel_q15_s,
      prompt_i_s_o          => prompt_i_s,
      prompt_q_s_o          => prompt_q_s,
      early_i_s_o           => early_i_s,
      early_q_s_o           => early_q_s,
      late_i_s_o            => late_i_s,
      late_q_s_o            => late_q_s
    );

  stim : process
    file vec_file            : text;
    variable read_status_v   : file_open_status;
    variable l_v             : line;
    variable case_count_v    : integer;
    variable state_v         : integer;
    variable prev_valid_v    : integer;
    variable prompt_i_acc_v  : integer;
    variable prompt_q_acc_v  : integer;
    variable early_i_acc_v   : integer;
    variable early_q_acc_v   : integer;
    variable late_i_acc_v    : integer;
    variable late_q_acc_v    : integer;
    variable prev_i_acc_v    : integer;
    variable prev_q_acc_v    : integer;
    variable exp_prompt_mag_v: integer;
    variable exp_early_mag_v : integer;
    variable exp_late_mag_v  : integer;
    variable exp_dll_v       : integer;
    variable exp_pll_v       : integer;
    variable exp_fll_v       : integer;
    variable exp_sel_v       : integer;
    variable exp_prompt_i_v  : integer;
    variable exp_prompt_q_v  : integer;
    variable exp_early_i_v   : integer;
    variable exp_early_q_v   : integer;
    variable exp_late_i_v    : integer;
    variable exp_late_q_v    : integer;
  begin
    file_open(read_status_v, vec_file, G_VECTOR_FILE, read_mode);
    assert read_status_v = open_ok
      report "Unable to open discriminator vector file: " & G_VECTOR_FILE
      severity failure;

    readline(vec_file, l_v);
    read(l_v, case_count_v);
    assert case_count_v > 0
      report "Expected at least one discriminator vector row."
      severity failure;

    for case_idx_v in 0 to case_count_v - 1 loop
      readline(vec_file, l_v);
      read(l_v, state_v);
      read(l_v, prev_valid_v);
      read(l_v, prompt_i_acc_v);
      read(l_v, prompt_q_acc_v);
      read(l_v, early_i_acc_v);
      read(l_v, early_q_acc_v);
      read(l_v, late_i_acc_v);
      read(l_v, late_q_acc_v);
      read(l_v, prev_i_acc_v);
      read(l_v, prev_q_acc_v);
      read(l_v, exp_prompt_mag_v);
      read(l_v, exp_early_mag_v);
      read(l_v, exp_late_mag_v);
      read(l_v, exp_dll_v);
      read(l_v, exp_pll_v);
      read(l_v, exp_fll_v);
      read(l_v, exp_sel_v);
      read(l_v, exp_prompt_i_v);
      read(l_v, exp_prompt_q_v);
      read(l_v, exp_early_i_v);
      read(l_v, exp_early_q_v);
      read(l_v, exp_late_i_v);
      read(l_v, exp_late_q_v);

      if state_v = 2 then
        state_s <= TRACK_LOCKED;
      else
        state_s <= TRACK_PULLIN;
      end if;
      prev_prompt_valid_s <= '1' when prev_valid_v /= 0 else '0';
      prompt_i_acc_s <= to_signed(prompt_i_acc_v, 32);
      prompt_q_acc_s <= to_signed(prompt_q_acc_v, 32);
      early_i_acc_s <= to_signed(early_i_acc_v, 32);
      early_q_acc_s <= to_signed(early_q_acc_v, 32);
      late_i_acc_s <= to_signed(late_i_acc_v, 32);
      late_q_acc_s <= to_signed(late_q_acc_v, 32);
      prev_prompt_i_s <= to_signed(prev_i_acc_v, 32);
      prev_prompt_q_s <= to_signed(prev_q_acc_v, 32);
      wait for 1 ns;

      assert prompt_mag_s = exp_prompt_mag_v
        report "prompt_mag mismatch at discriminator case " & integer'image(case_idx_v)
        severity failure;
      assert early_mag_s = exp_early_mag_v
        report "early_mag mismatch at discriminator case " & integer'image(case_idx_v)
        severity failure;
      assert late_mag_s = exp_late_mag_v
        report "late_mag mismatch at discriminator case " & integer'image(case_idx_v)
        severity failure;
      assert dll_err_q15_s = exp_dll_v
        report "dll_err mismatch at discriminator case " & integer'image(case_idx_v)
        severity failure;
      assert carrier_err_pll_q15_s = exp_pll_v
        report "pll_err mismatch at discriminator case " & integer'image(case_idx_v)
        severity failure;
      assert carrier_err_fll_q15_s = exp_fll_v
        report "fll_err mismatch at discriminator case " & integer'image(case_idx_v)
        severity failure;
      assert carrier_err_sel_q15_s = exp_sel_v
        report "sel_err mismatch at discriminator case " & integer'image(case_idx_v)
        severity failure;
      assert prompt_i_s = exp_prompt_i_v
        report "prompt_i_s mismatch at discriminator case " & integer'image(case_idx_v)
        severity failure;
      assert prompt_q_s = exp_prompt_q_v
        report "prompt_q_s mismatch at discriminator case " & integer'image(case_idx_v)
        severity failure;
      assert early_i_s = exp_early_i_v
        report "early_i_s mismatch at discriminator case " & integer'image(case_idx_v)
        severity failure;
      assert early_q_s = exp_early_q_v
        report "early_q_s mismatch at discriminator case " & integer'image(case_idx_v)
        severity failure;
      assert late_i_s = exp_late_i_v
        report "late_i_s mismatch at discriminator case " & integer'image(case_idx_v)
        severity failure;
      assert late_q_s = exp_late_q_v
        report "late_q_s mismatch at discriminator case " & integer'image(case_idx_v)
        severity failure;
    end loop;

    file_close(vec_file);

    finish;
  end process;
end architecture;
