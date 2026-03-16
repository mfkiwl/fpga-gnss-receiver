library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gps_l1_ca_pkg.all;

entity gps_l1_ca_observables is
  generic (
    G_NUM_CHANNELS            : integer := 5;
    G_REQUIRE_EPH_FOR_VALID   : boolean := true;
    G_IONO_CORR_MM            : integer := 0;
    G_TROPO_CORR_MM           : integer := 0
  );
  port (
    clk               : in  std_logic;
    rst_n             : in  std_logic;
    obs_en_i          : in  std_logic;
    epoch_tick_i      : in  std_logic;
    sample_counter_i  : in  unsigned(31 downto 0);
    tow_seconds_i     : in  unsigned(31 downto 0);
    chan_alloc_i      : in  std_logic_vector(G_NUM_CHANNELS - 1 downto 0);
    chan_code_lock_i  : in  std_logic_vector(G_NUM_CHANNELS - 1 downto 0);
    chan_prn_i        : in  u6_arr_t(0 to G_NUM_CHANNELS - 1);
    chan_dopp_i       : in  s16_arr_t(0 to G_NUM_CHANNELS - 1);
    chan_code_i       : in  u11_arr_t(0 to G_NUM_CHANNELS - 1);
    eph_valid_prn_i   : in  std_logic_vector(31 downto 0);
    sat_x_ecef_i      : in  s32_arr_t(0 to 31);
    sat_y_ecef_i      : in  s32_arr_t(0 to 31);
    sat_z_ecef_i      : in  s32_arr_t(0 to 31);
    sat_clk_corr_m_i  : in  s32_arr_t(0 to 31);
    rx_est_valid_i    : in  std_logic;
    rx_est_lat_e7_i   : in  signed(31 downto 0);
    rx_est_lon_e7_i   : in  signed(31 downto 0);
    rx_est_height_mm_i: in  signed(31 downto 0);
    obs_valid_o       : out std_logic;
    obs_epoch_o       : out unsigned(31 downto 0);
    obs_count_o       : out unsigned(7 downto 0);
    obs_valid_mask_o  : out std_logic_vector(G_NUM_CHANNELS - 1 downto 0);
    obs_prn_o         : out u6_arr_t(0 to G_NUM_CHANNELS - 1);
    obs_dopp_o        : out s16_arr_t(0 to G_NUM_CHANNELS - 1);
    obs_range_o       : out u32_arr_t(0 to G_NUM_CHANNELS - 1);
    obs_sat_x_o       : out s32_arr_t(0 to G_NUM_CHANNELS - 1);
    obs_sat_y_o       : out s32_arr_t(0 to G_NUM_CHANNELS - 1);
    obs_sat_z_o       : out s32_arr_t(0 to G_NUM_CHANNELS - 1);
    obs_clk_corr_o    : out s32_arr_t(0 to G_NUM_CHANNELS - 1);
    obs_first_prn_o   : out unsigned(5 downto 0);
    obs_first_range_o : out unsigned(31 downto 0)
  );
end entity;

architecture rtl of gps_l1_ca_observables is
begin
  obs_valid_o       <= '0';
  obs_epoch_o       <= (others => '0');
  obs_count_o       <= (others => '0');
  obs_valid_mask_o  <= (others => '0');
  obs_prn_o         <= (others => (others => '0'));
  obs_dopp_o        <= (others => (others => '0'));
  obs_range_o       <= (others => (others => '0'));
  obs_sat_x_o       <= (others => (others => '0'));
  obs_sat_y_o       <= (others => (others => '0'));
  obs_sat_z_o       <= (others => (others => '0'));
  obs_clk_corr_o    <= (others => (others => '0'));
  obs_first_prn_o   <= (others => '0');
  obs_first_range_o <= (others => '0');
end architecture;
