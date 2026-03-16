library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gps_l1_ca_pkg.all;

entity gps_l1_ca_nav_store is
  generic (
    G_NUM_CHANNELS : integer := 5
  );
  port (
    clk               : in  std_logic;
    rst_n             : in  std_logic;
    nav_en_i          : in  std_logic;
    chan_nav_valid_i  : in  std_logic_vector(G_NUM_CHANNELS - 1 downto 0);
    chan_nav_bit_i    : in  std_logic_vector(G_NUM_CHANNELS - 1 downto 0);
    chan_prn_i        : in  u6_arr_t(0 to G_NUM_CHANNELS - 1);
    eph_valid_prn_o   : out std_logic_vector(31 downto 0);
    nav_word_count_o  : out unsigned(31 downto 0);
    tow_seconds_o     : out unsigned(31 downto 0);
    sat_x_ecef_o      : out s32_arr_t(0 to 31);
    sat_y_ecef_o      : out s32_arr_t(0 to 31);
    sat_z_ecef_o      : out s32_arr_t(0 to 31);
    sat_clk_corr_m_o  : out s32_arr_t(0 to 31)
  );
end entity;

architecture rtl of gps_l1_ca_nav_store is
begin
  eph_valid_prn_o  <= (others => '0');
  nav_word_count_o <= (others => '0');
  tow_seconds_o    <= (others => '0');
  sat_x_ecef_o     <= (others => (others => '0'));
  sat_y_ecef_o     <= (others => (others => '0'));
  sat_z_ecef_o     <= (others => (others => '0'));
  sat_clk_corr_m_o <= (others => (others => '0'));
end architecture;
