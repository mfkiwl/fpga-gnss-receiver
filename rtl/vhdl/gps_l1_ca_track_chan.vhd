library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gps_l1_ca_pkg.all;

entity gps_l1_ca_track_chan is
  port (
    clk            : in  std_logic;
    rst_n          : in  std_logic;
    core_en        : in  std_logic;
    tracking_en    : in  std_logic;
    init_prn       : in  unsigned(5 downto 0);
    init_dopp      : in  signed(15 downto 0);
    acq_valid      : in  std_logic;
    acq_prn        : in  unsigned(5 downto 0);
    acq_dopp       : in  signed(15 downto 0);
    acq_code       : in  unsigned(10 downto 0);
    s_valid        : in  std_logic;
    s_i            : in  signed(15 downto 0);
    s_q            : in  signed(15 downto 0);
    track_state_o  : out track_state_t;
    code_lock_o    : out std_logic;
    carrier_lock_o : out std_logic;
    report_valid_o : out std_logic;
    prn_o          : out unsigned(5 downto 0);
    dopp_o         : out signed(15 downto 0);
    code_o         : out unsigned(10 downto 0);
    prompt_i_o     : out signed(23 downto 0);
    prompt_q_o     : out signed(23 downto 0)
  );
end entity;

architecture rtl of gps_l1_ca_track_chan is
  signal state_r          : track_state_t := TRACK_IDLE;
  signal prn_r            : unsigned(5 downto 0) := (others => '0');
  signal dopp_r           : signed(15 downto 0) := (others => '0');
  signal code_phase_r     : unsigned(10 downto 0) := (others => '0');
  signal code_nco_phase_r : unsigned(31 downto 0) := (others => '0');
  signal prompt_i_acc_r   : signed(23 downto 0) := (others => '0');
  signal prompt_q_acc_r   : signed(23 downto 0) := (others => '0');
  signal ms_sample_cnt_r  : integer range 0 to C_SAMPLES_PER_MS - 1 := 0;
  signal ms_count_r       : integer range 0 to 255 := 0;
  signal report_valid_r   : std_logic := '0';
  signal code_lock_r      : std_logic := '0';
  signal carrier_lock_r   : std_logic := '0';
begin
  track_state_o  <= state_r;
  code_lock_o    <= code_lock_r;
  carrier_lock_o <= carrier_lock_r;
  report_valid_o <= report_valid_r;
  prn_o          <= prn_r;
  dopp_o         <= dopp_r;
  code_o         <= code_phase_r;
  prompt_i_o     <= prompt_i_acc_r;
  prompt_q_o     <= prompt_q_acc_r;

  process (clk)
    variable next_code : unsigned(31 downto 0);
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        state_r          <= TRACK_IDLE;
        prn_r            <= (others => '0');
        dopp_r           <= (others => '0');
        code_phase_r     <= (others => '0');
        code_nco_phase_r <= (others => '0');
        prompt_i_acc_r   <= (others => '0');
        prompt_q_acc_r   <= (others => '0');
        ms_sample_cnt_r  <= 0;
        ms_count_r       <= 0;
        report_valid_r   <= '0';
        code_lock_r      <= '0';
        carrier_lock_r   <= '0';
      else
        report_valid_r <= '0';

        if core_en = '0' or tracking_en = '0' then
          state_r     <= TRACK_IDLE;
          code_lock_r <= '0';
          carrier_lock_r <= '0';
        else
          case state_r is
            when TRACK_IDLE =>
              ms_sample_cnt_r <= 0;
              ms_count_r      <= 0;
              prompt_i_acc_r  <= (others => '0');
              prompt_q_acc_r  <= (others => '0');
              if acq_valid = '1' then
                prn_r        <= acq_prn;
                dopp_r       <= acq_dopp;
                code_phase_r <= acq_code;
                state_r      <= TRACK_PULLIN;
              else
                prn_r        <= init_prn;
                dopp_r       <= init_dopp;
              end if;

            when TRACK_PULLIN | TRACK_LOCKED =>
              if s_valid = '1' then
                prompt_i_acc_r <= prompt_i_acc_r + resize(s_i, prompt_i_acc_r'length);
                prompt_q_acc_r <= prompt_q_acc_r + resize(s_q, prompt_q_acc_r'length);

                next_code := code_nco_phase_r + C_CODE_NCO_FCW;
                code_nco_phase_r <= next_code;
                code_phase_r <= resize(next_code(31 downto 21), code_phase_r'length);

                if ms_sample_cnt_r = C_SAMPLES_PER_MS - 1 then
                  report_valid_r  <= '1';
                  ms_sample_cnt_r <= 0;
                  prompt_i_acc_r  <= (others => '0');
                  prompt_q_acc_r  <= (others => '0');
                  if ms_count_r < 255 then
                    ms_count_r <= ms_count_r + 1;
                  end if;

                  if ms_count_r >= 19 then
                    state_r       <= TRACK_LOCKED;
                    code_lock_r   <= '1';
                    carrier_lock_r<= '1';
                  else
                    state_r       <= TRACK_PULLIN;
                  end if;
                else
                  ms_sample_cnt_r <= ms_sample_cnt_r + 1;
                end if;
              end if;
          end case;
        end if;
      end if;
    end if;
  end process;
end architecture;
