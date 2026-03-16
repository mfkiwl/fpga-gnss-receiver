library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gps_l1_ca_pkg.all;

entity gps_l1_ca_pvt is
  generic (
    G_NUM_CHANNELS : integer := 5;
    G_LOG_INTERNAL : boolean := false
  );
  port (
    clk              : in  std_logic;
    rst_n            : in  std_logic;
    pvt_en_i         : in  std_logic;
    obs_valid_i      : in  std_logic;
    obs_count_i      : in  unsigned(7 downto 0);
    obs_valid_mask_i : in  std_logic_vector(G_NUM_CHANNELS - 1 downto 0);
    obs_prn_i        : in  u6_arr_t(0 to G_NUM_CHANNELS - 1);
    obs_dopp_i       : in  s16_arr_t(0 to G_NUM_CHANNELS - 1);
    obs_range_i      : in  u32_arr_t(0 to G_NUM_CHANNELS - 1);
    obs_sat_x_i      : in  s32_arr_t(0 to G_NUM_CHANNELS - 1);
    obs_sat_y_i      : in  s32_arr_t(0 to G_NUM_CHANNELS - 1);
    obs_sat_z_i      : in  s32_arr_t(0 to G_NUM_CHANNELS - 1);
    obs_clk_corr_i   : in  s32_arr_t(0 to G_NUM_CHANNELS - 1);
    pvt_valid_o      : out std_logic;
    pvt_sats_used_o  : out unsigned(7 downto 0);
    pvt_lat_e7_o     : out signed(31 downto 0);
    pvt_lon_e7_o     : out signed(31 downto 0);
    pvt_height_mm_o  : out signed(31 downto 0);
    pvt_cbias_o      : out signed(31 downto 0)
  );
end entity;

architecture rtl of gps_l1_ca_pvt is
begin
  pvt_valid_o     <= '0';
  pvt_sats_used_o <= (others => '0');
  pvt_lat_e7_o    <= (others => '0');
  pvt_lon_e7_o    <= (others => '0');
  pvt_height_mm_o <= (others => '0');
  pvt_cbias_o     <= (others => '0');
end architecture;
