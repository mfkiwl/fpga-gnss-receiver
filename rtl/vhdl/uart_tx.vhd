library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
  generic (
    G_CLK_HZ   : integer := 50000000;
    G_BAUD_HZ  : integer := 115200
  );
  port (
    clk       : in  std_logic;
    rst_n     : in  std_logic;
    tx_valid  : in  std_logic;
    tx_ready  : out std_logic;
    tx_data   : in  std_logic_vector(7 downto 0);
    txd       : out std_logic;
    busy      : out std_logic
  );
end entity;

architecture rtl of uart_tx is
  constant C_DIV : integer := G_CLK_HZ / G_BAUD_HZ;
  signal bit_div_r   : integer range 0 to C_DIV - 1 := 0;
  signal bit_cnt_r   : integer range 0 to 9 := 0;
  signal shreg_r     : std_logic_vector(9 downto 0) := (others => '1');
  signal active_r    : std_logic := '0';
begin
  tx_ready <= not active_r;
  txd      <= shreg_r(0);
  busy     <= active_r;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        bit_div_r <= 0;
        bit_cnt_r <= 0;
        shreg_r   <= (others => '1');
        active_r  <= '0';
      else
        if active_r = '0' then
          if tx_valid = '1' then
            shreg_r   <= '1' & tx_data & '0';
            active_r  <= '1';
            bit_div_r <= 0;
            bit_cnt_r <= 0;
          end if;
        else
          if bit_div_r = C_DIV - 1 then
            bit_div_r <= 0;
            shreg_r   <= '1' & shreg_r(9 downto 1);
            if bit_cnt_r = 9 then
              active_r <= '0';
            else
              bit_cnt_r <= bit_cnt_r + 1;
            end if;
          else
            bit_div_r <= bit_div_r + 1;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
