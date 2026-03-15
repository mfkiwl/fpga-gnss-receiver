library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axis_skid_buffer is
  generic (
    G_DATA_W : integer := 32
  );
  port (
    clk         : in  std_logic;
    rst_n       : in  std_logic;
    s_tvalid    : in  std_logic;
    s_tready    : out std_logic;
    s_tdata     : in  std_logic_vector(G_DATA_W - 1 downto 0);
    m_tvalid    : out std_logic;
    m_tready    : in  std_logic;
    m_tdata     : out std_logic_vector(G_DATA_W - 1 downto 0)
  );
end entity;

architecture rtl of axis_skid_buffer is
  signal full_r : std_logic := '0';
  signal data_r : std_logic_vector(G_DATA_W - 1 downto 0) := (others => '0');
  signal s_tready_i : std_logic;
begin
  s_tready_i <= not full_r or m_tready;
  s_tready <= s_tready_i;
  m_tvalid <= full_r;
  m_tdata  <= data_r;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        full_r <= '0';
        data_r <= (others => '0');
      else
        if s_tvalid = '1' and s_tready_i = '1' then
          data_r <= s_tdata;
          full_r <= '1';
        elsif m_tready = '1' then
          full_r <= '0';
        end if;
      end if;
    end if;
  end process;
end architecture;
