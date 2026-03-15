library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity gps_l1_ca_ctrl is
  generic (
    ADDRW : integer := 8;
    DATAW : integer := 32
  );
  port (
    clk    : in  std_logic;
    rst_n  : in  std_logic;

    ctrl_wreq  : in  std_logic;
    ctrl_waddr : in  unsigned(ADDRW - 1 downto 0);
    ctrl_wdata : in  std_logic_vector(DATAW - 1 downto 0);
    ctrl_wack  : out std_logic;

    ctrl_rreq  : in  std_logic;
    ctrl_raddr : in  unsigned(ADDRW - 1 downto 0);
    ctrl_rdata : out std_logic_vector(DATAW - 1 downto 0);
    ctrl_rack  : out std_logic;

    acq_done_i         : in  std_logic;
    acq_success_i      : in  std_logic;
    detected_prn_i     : in  unsigned(5 downto 0);
    detected_code_i    : in  unsigned(10 downto 0);
    detected_dopp_i    : in  signed(15 downto 0);
    track_state_i      : in  std_logic_vector(1 downto 0);
    code_lock_i        : in  std_logic;
    carrier_lock_i     : in  std_logic;
    nav_bit_valid_i    : in  std_logic;
    uart_busy_i        : in  std_logic;

    core_en_o          : out std_logic;
    soft_reset_req_o   : out std_logic;
    acq_start_pulse_o  : out std_logic;
    tracking_en_o      : out std_logic;
    uart_en_o          : out std_logic;
    prn_start_o        : out unsigned(5 downto 0);
    prn_stop_o         : out unsigned(5 downto 0);
    doppler_min_o      : out signed(15 downto 0);
    doppler_max_o      : out signed(15 downto 0);
    doppler_step_o     : out signed(15 downto 0);
    detect_thresh_o    : out unsigned(31 downto 0);
    pll_gain_o         : out unsigned(15 downto 0);
    dll_gain_o         : out unsigned(15 downto 0);
    lock_thresh_o      : out unsigned(15 downto 0);
    init_prn_o         : out unsigned(5 downto 0);
    init_dopp_o        : out signed(15 downto 0)
  );
end entity;

architecture rtl of gps_l1_ca_ctrl is
  signal ctrl_wack_r       : std_logic := '0';
  signal ctrl_rack_r       : std_logic := '0';
  signal ctrl_rdata_r      : std_logic_vector(DATAW - 1 downto 0) := (others => '0');
  signal core_en_r         : std_logic := '0';
  signal tracking_en_r     : std_logic := '0';
  signal uart_en_r         : std_logic := '0';
  signal soft_reset_req_r  : std_logic := '0';
  signal acq_start_pulse_r : std_logic := '0';
  signal prn_start_r       : unsigned(5 downto 0) := to_unsigned(1, 6);
  signal prn_stop_r        : unsigned(5 downto 0) := to_unsigned(8, 6);
  signal doppler_min_r     : signed(15 downto 0) := to_signed(-5000, 16);
  signal doppler_max_r     : signed(15 downto 0) := to_signed(5000, 16);
  signal doppler_step_r    : signed(15 downto 0) := to_signed(500, 16);
  signal detect_thresh_r   : unsigned(31 downto 0) := to_unsigned(10000, 32);
  signal pll_gain_r        : unsigned(15 downto 0) := to_unsigned(64, 16);
  signal dll_gain_r        : unsigned(15 downto 0) := to_unsigned(64, 16);
  signal lock_thresh_r     : unsigned(15 downto 0) := to_unsigned(100, 16);
  signal init_prn_r        : unsigned(5 downto 0) := to_unsigned(1, 6);
  signal init_dopp_r       : signed(15 downto 0) := (others => '0');
begin
  ctrl_wack <= ctrl_wack_r;
  ctrl_rack <= ctrl_rack_r;
  ctrl_rdata <= ctrl_rdata_r;

  core_en_o         <= core_en_r;
  tracking_en_o     <= tracking_en_r;
  uart_en_o         <= uart_en_r;
  soft_reset_req_o  <= soft_reset_req_r;
  acq_start_pulse_o <= acq_start_pulse_r;
  prn_start_o       <= prn_start_r;
  prn_stop_o        <= prn_stop_r;
  doppler_min_o     <= doppler_min_r;
  doppler_max_o     <= doppler_max_r;
  doppler_step_o    <= doppler_step_r;
  detect_thresh_o   <= detect_thresh_r;
  pll_gain_o        <= pll_gain_r;
  dll_gain_o        <= dll_gain_r;
  lock_thresh_o     <= lock_thresh_r;
  init_prn_o        <= init_prn_r;
  init_dopp_o       <= init_dopp_r;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        ctrl_wack_r       <= '0';
        ctrl_rack_r       <= '0';
        acq_start_pulse_r <= '0';
        soft_reset_req_r  <= '0';
      else
        ctrl_wack_r       <= '0';
        ctrl_rack_r       <= '0';
        acq_start_pulse_r <= '0';
        soft_reset_req_r  <= '0';

        if ctrl_wreq = '1' then
          ctrl_wack_r <= '1';
          case to_integer(ctrl_waddr) is
            when 16#00# =>
              core_en_r         <= ctrl_wdata(0);
              soft_reset_req_r  <= ctrl_wdata(1);
              acq_start_pulse_r <= ctrl_wdata(2);
              tracking_en_r     <= ctrl_wdata(3);
              uart_en_r         <= ctrl_wdata(4);
            when 16#04# =>
              prn_start_r <= unsigned(ctrl_wdata(5 downto 0));
              prn_stop_r  <= unsigned(ctrl_wdata(13 downto 8));
            when 16#08# =>
              doppler_min_r <= signed(ctrl_wdata(15 downto 0));
            when 16#0C# =>
              doppler_max_r <= signed(ctrl_wdata(15 downto 0));
            when 16#10# =>
              doppler_step_r <= signed(ctrl_wdata(15 downto 0));
            when 16#14# =>
              detect_thresh_r <= unsigned(ctrl_wdata);
            when 16#18# =>
              pll_gain_r <= unsigned(ctrl_wdata(15 downto 0));
            when 16#1C# =>
              dll_gain_r <= unsigned(ctrl_wdata(15 downto 0));
            when 16#20# =>
              lock_thresh_r <= unsigned(ctrl_wdata(15 downto 0));
            when 16#24# =>
              init_prn_r <= unsigned(ctrl_wdata(5 downto 0));
            when 16#28# =>
              init_dopp_r <= signed(ctrl_wdata(15 downto 0));
            when others =>
              null;
          end case;
        end if;

        if ctrl_rreq = '1' then
          ctrl_rack_r <= '1';
        end if;
      end if;
    end if;
  end process;

  process (all)
    variable rd : std_logic_vector(DATAW - 1 downto 0);
  begin
    rd := (others => '0');
    case to_integer(ctrl_raddr) is
      when 16#00# =>
        rd(0) := core_en_r;
        rd(3) := tracking_en_r;
        rd(4) := uart_en_r;
      when 16#04# =>
        rd(5 downto 0)   := std_logic_vector(prn_start_r);
        rd(13 downto 8)  := std_logic_vector(prn_stop_r);
      when 16#08# =>
        rd(15 downto 0) := std_logic_vector(doppler_min_r);
      when 16#0C# =>
        rd(15 downto 0) := std_logic_vector(doppler_max_r);
      when 16#10# =>
        rd(15 downto 0) := std_logic_vector(doppler_step_r);
      when 16#14# =>
        rd := std_logic_vector(detect_thresh_r);
      when 16#18# =>
        rd(15 downto 0) := std_logic_vector(pll_gain_r);
      when 16#1C# =>
        rd(15 downto 0) := std_logic_vector(dll_gain_r);
      when 16#20# =>
        rd(15 downto 0) := std_logic_vector(lock_thresh_r);
      when 16#24# =>
        rd(5 downto 0) := std_logic_vector(init_prn_r);
      when 16#28# =>
        rd(15 downto 0) := std_logic_vector(init_dopp_r);
      when 16#40# =>
        rd(0) := acq_done_i;
        rd(1) := acq_success_i;
        rd(2) := code_lock_i;
        rd(3) := carrier_lock_i;
        rd(4) := nav_bit_valid_i;
        rd(5) := uart_busy_i;
        rd(7 downto 6) := track_state_i;
      when 16#44# =>
        rd(5 downto 0) := std_logic_vector(detected_prn_i);
        rd(26 downto 16) := std_logic_vector(detected_code_i);
      when 16#48# =>
        rd(15 downto 0) := std_logic_vector(detected_dopp_i);
      when others =>
        null;
    end case;
    ctrl_rdata_r <= rd;
  end process;
end architecture;
