library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gps_l1_ca_pkg.all;

entity gps_l1_ca_acq is
  port (
    clk            : in  std_logic;
    rst_n          : in  std_logic;
    core_en        : in  std_logic;
    start_pulse    : in  std_logic;
    prn_start      : in  unsigned(5 downto 0);
    prn_stop       : in  unsigned(5 downto 0);
    doppler_min    : in  signed(15 downto 0);
    doppler_max    : in  signed(15 downto 0);
    doppler_step   : in  signed(15 downto 0);
    detect_thresh  : in  unsigned(31 downto 0);
    s_valid        : in  std_logic;
    s_i            : in  signed(15 downto 0);
    s_q            : in  signed(15 downto 0);
    acq_done       : out std_logic;
    acq_success    : out std_logic;
    result_valid   : out std_logic;
    result_prn     : out unsigned(5 downto 0);
    result_dopp    : out signed(15 downto 0);
    result_code    : out unsigned(10 downto 0);
    result_metric  : out unsigned(31 downto 0)
  );
end entity;

architecture rtl of gps_l1_ca_acq is
  type state_t is (IDLE, COLLECT, FINALIZE);
  signal state_r            : state_t := IDLE;
  signal sample_cnt_r       : integer range 0 to C_SAMPLES_PER_MS - 1 := 0;
  signal prn_cur_r          : unsigned(5 downto 0) := to_unsigned(1, 6);
  signal accum_metric_r     : unsigned(31 downto 0) := (others => '0');
  signal best_metric_r      : unsigned(31 downto 0) := (others => '0');
  signal best_prn_r         : unsigned(5 downto 0) := to_unsigned(1, 6);
  signal acq_done_r         : std_logic := '0';
  signal acq_success_r      : std_logic := '0';
  signal result_valid_r     : std_logic := '0';
begin
  acq_done     <= acq_done_r;
  acq_success  <= acq_success_r;
  result_valid <= result_valid_r;
  result_prn   <= best_prn_r;
  result_dopp  <= doppler_min;
  result_code  <= (others => '0');
  result_metric <= best_metric_r;

  process (clk)
    variable sample_mag : unsigned(15 downto 0);
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        state_r        <= IDLE;
        sample_cnt_r   <= 0;
        prn_cur_r      <= to_unsigned(1, 6);
        accum_metric_r <= (others => '0');
        best_metric_r  <= (others => '0');
        best_prn_r     <= to_unsigned(1, 6);
        acq_done_r     <= '0';
        acq_success_r  <= '0';
        result_valid_r <= '0';
      else
        acq_done_r     <= '0';
        result_valid_r <= '0';

        case state_r is
          when IDLE =>
            acq_success_r <= '0';
            if core_en = '1' and start_pulse = '1' then
              state_r        <= COLLECT;
              prn_cur_r      <= prn_start;
              sample_cnt_r   <= 0;
              accum_metric_r <= (others => '0');
              best_metric_r  <= (others => '0');
              best_prn_r     <= prn_start;
            end if;

          when COLLECT =>
            if s_valid = '1' then
              sample_mag := abs_s16(s_i) + abs_s16(s_q);
              accum_metric_r <= accum_metric_r + resize(sample_mag, 32);
              if sample_cnt_r = C_SAMPLES_PER_MS - 1 then
                if accum_metric_r > best_metric_r then
                  best_metric_r <= accum_metric_r;
                  best_prn_r    <= prn_cur_r;
                end if;

                sample_cnt_r   <= 0;
                accum_metric_r <= (others => '0');
                if prn_cur_r >= prn_stop then
                  state_r <= FINALIZE;
                else
                  prn_cur_r <= prn_cur_r + 1;
                end if;
              else
                sample_cnt_r <= sample_cnt_r + 1;
              end if;
            end if;

          when FINALIZE =>
            acq_done_r <= '1';
            if best_metric_r >= detect_thresh then
              acq_success_r  <= '1';
              result_valid_r <= '1';
            else
              acq_success_r  <= '0';
            end if;
            state_r <= IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture;
