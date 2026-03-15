library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_types.all;

entity fifo_tb is
end entity;

architecture tb of fifo_tb is
  signal clk   : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal wr_en : std_logic := '0';
  signal rd_en : std_logic := '0';
  signal din   : byte_t    := (others => '0');
  signal dout  : byte_t;
  signal full  : std_logic;
  signal empty : std_logic;
begin
  clk <= not clk after 5 ns;

  uut : entity work.fifo
    port map (
      clk   => clk,
      rst_n => rst_n,
      wr_en => wr_en,
      rd_en => rd_en,
      din   => din,
      dout  => dout,
      full  => full,
      empty => empty
    );

  stim : process
  begin
    rst_n <= '0';
    wait for 20 ns;
    rst_n <= '1';

    wr_en <= '1';
    din <= x"11";
    wait for 10 ns;
    din <= x"22";
    wait for 10 ns;
    wr_en <= '0';

    rd_en <= '1';
    wait for 20 ns;
    rd_en <= '0';

    wait for 20 ns;
    assert false report "fifo_tb done" severity note;
    wait;
  end process;
end architecture;
