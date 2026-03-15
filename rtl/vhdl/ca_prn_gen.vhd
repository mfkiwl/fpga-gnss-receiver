library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ca_prn_gen is
  port (
    clk          : in  std_logic;
    rst_n        : in  std_logic;
    init         : in  std_logic;
    chip_advance : in  std_logic;
    prn          : in  unsigned(5 downto 0);
    chip         : out std_logic
  );
end entity;

architecture rtl of ca_prn_gen is
  signal g1 : std_logic_vector(9 downto 0) := (others => '1');
  signal g2 : std_logic_vector(9 downto 0) := (others => '1');

  function g2_tap1(p : integer) return integer is
  begin
    case p is
      when 1 => return 2;  when 2 => return 3;  when 3 => return 4;  when 4 => return 5;
      when 5 => return 1;  when 6 => return 2;  when 7 => return 1;  when 8 => return 2;
      when 9 => return 3;  when 10 => return 2; when 11 => return 3; when 12 => return 5;
      when 13 => return 6; when 14 => return 7; when 15 => return 8; when 16 => return 9;
      when 17 => return 1; when 18 => return 2; when 19 => return 3; when 20 => return 4;
      when 21 => return 5; when 22 => return 6; when 23 => return 1; when 24 => return 4;
      when 25 => return 5; when 26 => return 6; when 27 => return 7; when 28 => return 8;
      when 29 => return 1; when 30 => return 2; when 31 => return 3; when 32 => return 4;
      when others => return 2;
    end case;
  end function;

  function g2_tap2(p : integer) return integer is
  begin
    case p is
      when 1 => return 6;  when 2 => return 7;  when 3 => return 8;  when 4 => return 9;
      when 5 => return 9;  when 6 => return 10; when 7 => return 8;  when 8 => return 9;
      when 9 => return 10; when 10 => return 3; when 11 => return 4; when 12 => return 6;
      when 13 => return 7; when 14 => return 8; when 15 => return 9; when 16 => return 10;
      when 17 => return 4; when 18 => return 5; when 19 => return 6; when 20 => return 7;
      when 21 => return 8; when 22 => return 9; when 23 => return 3; when 24 => return 6;
      when 25 => return 7; when 26 => return 8; when 27 => return 9; when 28 => return 10;
      when 29 => return 6; when 30 => return 7; when 31 => return 8; when 32 => return 9;
      when others => return 6;
    end case;
  end function;
begin
  process (clk)
    variable p    : integer;
    variable t1   : integer;
    variable t2   : integer;
    variable g1fb : std_logic;
    variable g2fb : std_logic;
  begin
    if rising_edge(clk) then
      if rst_n = '0' or init = '1' then
        g1 <= (others => '1');
        g2 <= (others => '1');
      elsif chip_advance = '1' then
        p := to_integer(prn);
        if p < 1 or p > 32 then
          p := 1;
        end if;

        t1 := g2_tap1(p) - 1;
        t2 := g2_tap2(p) - 1;

        g1fb := g1(2) xor g1(9);
        g2fb := g2(1) xor g2(2) xor g2(5) xor g2(7) xor g2(8) xor g2(9);

        g1 <= g1fb & g1(9 downto 1);
        g2 <= g2fb & g2(9 downto 1);
      end if;
    end if;
  end process;

  process (g1, g2, prn)
    variable p  : integer;
    variable t1 : integer;
    variable t2 : integer;
  begin
    p := to_integer(prn);
    if p < 1 or p > 32 then
      p := 1;
    end if;
    t1 := g2_tap1(p) - 1;
    t2 := g2_tap2(p) - 1;
    chip <= g1(9) xor g2(t1) xor g2(t2);
  end process;
end architecture;
