library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;
use work.gps_l1_ca_pkg.all;
use work.gps_l1_ca_track_pkg.all;

entity gps_l1_ca_track_loop_filters_tb is
  generic (
    G_VECTOR_FILE : string := "sim/vectors/track_loop_filters_vectors.txt"
  );
end entity;

architecture tb of gps_l1_ca_track_loop_filters_tb is
  signal state_s              : track_state_t := TRACK_PULLIN;
  signal dll_err_q15_s        : integer := 0;
  signal carrier_err_pll_q15_s: integer := 0;
  signal carrier_err_fll_q15_s: integer := 0;
  signal dopp_step_pullin_s   : unsigned(15 downto 0) := (others => '0');
  signal dopp_step_lock_s     : unsigned(15 downto 0) := (others => '0');
  signal pll_bw_hz_s          : unsigned(15 downto 0) := (others => '0');
  signal dll_bw_hz_s          : unsigned(15 downto 0) := (others => '0');
  signal pll_bw_narrow_hz_s   : unsigned(15 downto 0) := (others => '0');
  signal dll_bw_narrow_hz_s   : unsigned(15 downto 0) := (others => '0');
  signal fll_bw_hz_s          : unsigned(15 downto 0) := (others => '0');
  signal code_loop_i_s        : signed(31 downto 0) := (others => '0');
  signal carr_loop_i_s        : signed(31 downto 0) := (others => '0');

  signal code_loop_i_o_s      : signed(31 downto 0);
  signal code_fcw_o_s         : unsigned(31 downto 0);
  signal carr_loop_i_o_s      : signed(31 downto 0);
  signal carr_fcw_cmd_o_s     : signed(31 downto 0);
  signal dopp_o_s             : signed(15 downto 0);
begin
  dut : entity work.gps_l1_ca_track_loop_filters
    port map (
      state_i               => state_s,
      dll_err_q15_i         => dll_err_q15_s,
      carrier_err_pll_q15_i => carrier_err_pll_q15_s,
      carrier_err_fll_q15_i => carrier_err_fll_q15_s,
      dopp_step_pullin_i    => dopp_step_pullin_s,
      dopp_step_lock_i      => dopp_step_lock_s,
      pll_bw_hz_i           => pll_bw_hz_s,
      dll_bw_hz_i           => dll_bw_hz_s,
      pll_bw_narrow_hz_i    => pll_bw_narrow_hz_s,
      dll_bw_narrow_hz_i    => dll_bw_narrow_hz_s,
      fll_bw_hz_i           => fll_bw_hz_s,
      code_loop_i_i         => code_loop_i_s,
      carr_loop_i_i         => carr_loop_i_s,
      code_loop_i_o         => code_loop_i_o_s,
      code_fcw_o            => code_fcw_o_s,
      carr_loop_i_o         => carr_loop_i_o_s,
      carr_fcw_cmd_o        => carr_fcw_cmd_o_s,
      dopp_o                => dopp_o_s
    );

  stim : process
    file vec_file              : text;
    variable read_status_v     : file_open_status;
    variable l_v               : line;
    variable case_count_v      : integer;
    variable state_v           : integer;
    variable dll_err_v         : integer;
    variable pll_err_v         : integer;
    variable fll_err_v         : integer;
    variable code_loop_i_v     : integer;
    variable carr_loop_i_v     : integer;
    variable exp_code_loop_i_v : integer;
    variable exp_code_delta_v  : integer;
    variable exp_carr_loop_i_v : integer;
    variable exp_carr_cmd_v    : integer;
    variable exp_dopp_v        : integer;
    variable exp_code_fcw_v    : unsigned(31 downto 0);
  begin
    dopp_step_pullin_s <= to_unsigned(80, 16);
    dopp_step_lock_s <= to_unsigned(20, 16);
    pll_bw_hz_s <= to_unsigned(8960, 16);
    dll_bw_hz_s <= to_unsigned(512, 16);
    pll_bw_narrow_hz_s <= to_unsigned(1280, 16);
    dll_bw_narrow_hz_s <= to_unsigned(128, 16);
    fll_bw_hz_s <= to_unsigned(2560, 16);
    file_open(read_status_v, vec_file, G_VECTOR_FILE, read_mode);
    assert read_status_v = open_ok
      report "Unable to open loop-filter vector file: " & G_VECTOR_FILE
      severity failure;

    readline(vec_file, l_v);
    read(l_v, case_count_v);
    assert case_count_v > 0
      report "Expected at least one loop-filter vector row."
      severity failure;

    for case_idx_v in 0 to case_count_v - 1 loop
      readline(vec_file, l_v);
      read(l_v, state_v);
      read(l_v, dll_err_v);
      read(l_v, pll_err_v);
      read(l_v, fll_err_v);
      read(l_v, code_loop_i_v);
      read(l_v, carr_loop_i_v);
      read(l_v, exp_code_loop_i_v);
      read(l_v, exp_code_delta_v);
      read(l_v, exp_carr_loop_i_v);
      read(l_v, exp_carr_cmd_v);
      read(l_v, exp_dopp_v);

      if state_v = 2 then
        state_s <= TRACK_LOCKED;
      else
        state_s <= TRACK_PULLIN;
      end if;
      dll_err_q15_s <= dll_err_v;
      carrier_err_pll_q15_s <= pll_err_v;
      carrier_err_fll_q15_s <= fll_err_v;
      code_loop_i_s <= to_signed(code_loop_i_v, 32);
      carr_loop_i_s <= to_signed(carr_loop_i_v, 32);
      wait for 1 ns;

      if exp_code_delta_v >= 0 then
        exp_code_fcw_v := C_CODE_NCO_FCW + to_unsigned(exp_code_delta_v, 32);
      else
        exp_code_fcw_v := C_CODE_NCO_FCW - to_unsigned(-exp_code_delta_v, 32);
      end if;

      assert to_integer(code_loop_i_o_s) = exp_code_loop_i_v
        report "code_loop_i mismatch at loop-filter case " & integer'image(case_idx_v)
        severity failure;
      assert code_fcw_o_s = exp_code_fcw_v
        report "code_fcw mismatch at loop-filter case " & integer'image(case_idx_v)
        severity failure;
      assert to_integer(carr_loop_i_o_s) = exp_carr_loop_i_v
        report "carr_loop_i mismatch at loop-filter case " & integer'image(case_idx_v)
        severity failure;
      assert to_integer(carr_fcw_cmd_o_s) = exp_carr_cmd_v
        report "carr_fcw_cmd mismatch at loop-filter case " & integer'image(case_idx_v)
        severity failure;
      assert to_integer(dopp_o_s) = exp_dopp_v
        report "dopp mismatch at loop-filter case " & integer'image(case_idx_v)
        severity failure;
    end loop;

    file_close(vec_file);

    finish;
  end process;
end architecture;
