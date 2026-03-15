library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity xilinx_inferred_true_dual_port_ram is
  generic (
    G_DATA_W : integer := 32;
    G_ADDR_W : integer := 11
  );
  port (
    clka  : in  std_logic;
    ena   : in  std_logic;
    wea   : in  std_logic;
    addra : in  unsigned(G_ADDR_W - 1 downto 0);
    dina  : in  std_logic_vector(G_DATA_W - 1 downto 0);
    douta : out std_logic_vector(G_DATA_W - 1 downto 0);
    clkb  : in  std_logic;
    enb   : in  std_logic;
    web   : in  std_logic;
    addrb : in  unsigned(G_ADDR_W - 1 downto 0);
    dinb  : in  std_logic_vector(G_DATA_W - 1 downto 0);
    doutb : out std_logic_vector(G_DATA_W - 1 downto 0)
  );
end entity;

architecture rtl of xilinx_inferred_true_dual_port_ram is
  type ram_t is array (0 to (2 ** G_ADDR_W) - 1) of std_logic_vector(G_DATA_W - 1 downto 0);
  signal ram : ram_t := (others => (others => '0'));
begin
  process (clka)
  begin
    if rising_edge(clka) then
      if ena = '1' then
        if wea = '1' then
          ram(to_integer(addra)) <= dina;
        end if;
        douta <= ram(to_integer(addra));
      end if;
    end if;
  end process;

  process (clkb)
  begin
    if rising_edge(clkb) then
      if enb = '1' then
        if web = '1' then
          ram(to_integer(addrb)) <= dinb;
        end if;
        doutb <= ram(to_integer(addrb));
      end if;
    end if;
  end process;
end architecture;
