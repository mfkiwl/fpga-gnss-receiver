library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity nco_phase_accum is
  generic (
    G_PHASE_W : integer := 32
  );
  port (
    clk   : in  std_logic;
    rst_n : in  std_logic;
    en    : in  std_logic;
    fcw   : in  unsigned(G_PHASE_W - 1 downto 0);
    phase : out unsigned(G_PHASE_W - 1 downto 0)
  );
end entity;

architecture rtl of nco_phase_accum is
  signal phase_r : unsigned(G_PHASE_W - 1 downto 0) := (others => '0');
begin
  phase <= phase_r;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        phase_r <= (others => '0');
      elsif en = '1' then
        phase_r <= phase_r + fcw;
      end if;
    end if;
  end process;
end architecture;
