library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package gps_l1_ca_pkg is
  constant C_SAMPLE_RATE_HZ : integer := 2000000;
  constant C_CODE_RATE_HZ   : integer := 1023000;
  constant C_SAMPLES_PER_MS : integer := 2000;
  constant C_PRN_MIN        : integer := 1;
  constant C_PRN_MAX        : integer := 32;

  constant C_CODE_NCO_FCW : unsigned(31 downto 0) := x"82EF9DB2";

  subtype s16_t is signed(15 downto 0);
  subtype u32_t is unsigned(31 downto 0);

  type track_state_t is (TRACK_IDLE, TRACK_PULLIN, TRACK_LOCKED);

  type acq_result_t is record
    valid      : std_logic;
    prn        : unsigned(5 downto 0);
    doppler_hz : signed(15 downto 0);
    code_phase : unsigned(10 downto 0);
    metric     : unsigned(31 downto 0);
  end record;

  type track_report_t is record
    valid       : std_logic;
    prn         : unsigned(5 downto 0);
    doppler_hz  : signed(15 downto 0);
    code_phase  : unsigned(10 downto 0);
    prompt_i    : signed(23 downto 0);
    prompt_q    : signed(23 downto 0);
    code_lock   : std_logic;
    carrier_lock: std_logic;
    state       : track_state_t;
  end record;

  type nav_report_t is record
    valid      : std_logic;
    nav_bit    : std_logic;
    bit_count  : unsigned(15 downto 0);
  end record;

  function abs_s16(x : signed(15 downto 0)) return unsigned;
  function state_to_slv(x : track_state_t) return std_logic_vector;
end package;

package body gps_l1_ca_pkg is
  function abs_s16(x : signed(15 downto 0)) return unsigned is
    variable v : signed(15 downto 0);
  begin
    if x < 0 then
      v := -x;
    else
      v := x;
    end if;
    return unsigned(v);
  end function;

  function state_to_slv(x : track_state_t) return std_logic_vector is
  begin
    case x is
      when TRACK_IDLE   => return "00";
      when TRACK_PULLIN => return "01";
      when TRACK_LOCKED => return "10";
    end case;
  end function;
end package body;
