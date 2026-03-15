library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity gps_l1_ca_nav is
  port (
    clk         : in  std_logic;
    rst_n       : in  std_logic;
    code_lock   : in  std_logic;
    prompt_valid: in  std_logic;
    prompt_i    : in  signed(23 downto 0);
    nav_valid   : out std_logic;
    nav_bit     : out std_logic
  );
end entity;

architecture rtl of gps_l1_ca_nav is
  signal accum_r     : signed(31 downto 0) := (others => '0');
  signal bit_cnt_r   : integer range 0 to 19 := 0;
  signal nav_valid_r : std_logic := '0';
  signal nav_bit_r   : std_logic := '0';
begin
  nav_valid <= nav_valid_r;
  nav_bit   <= nav_bit_r;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        accum_r     <= (others => '0');
        bit_cnt_r   <= 0;
        nav_valid_r <= '0';
        nav_bit_r   <= '0';
      else
        nav_valid_r <= '0';
        if code_lock = '1' and prompt_valid = '1' then
          accum_r <= accum_r + resize(prompt_i, accum_r'length);
          if bit_cnt_r = 19 then
            nav_valid_r <= '1';
            if accum_r < 0 then
              nav_bit_r <= '1';
            else
              nav_bit_r <= '0';
            end if;
            accum_r   <= (others => '0');
            bit_cnt_r <= 0;
          else
            bit_cnt_r <= bit_cnt_r + 1;
          end if;
        elsif code_lock = '0' then
          accum_r   <= (others => '0');
          bit_cnt_r <= 0;
        end if;
      end if;
    end if;
  end process;
end architecture;
