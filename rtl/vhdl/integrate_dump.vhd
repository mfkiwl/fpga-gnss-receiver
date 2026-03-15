library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity integrate_dump is
  generic (
    G_DUMP_LEN : integer := 2000
  );
  port (
    clk        : in  std_logic;
    rst_n      : in  std_logic;
    in_valid   : in  std_logic;
    in_sample  : in  signed(15 downto 0);
    out_valid  : out std_logic;
    out_sum    : out signed(31 downto 0)
  );
end entity;

architecture rtl of integrate_dump is
  signal accum_r     : signed(31 downto 0) := (others => '0');
  signal sample_cnt  : integer range 0 to G_DUMP_LEN - 1 := 0;
  signal out_valid_r : std_logic := '0';
  signal out_sum_r   : signed(31 downto 0) := (others => '0');
begin
  out_valid <= out_valid_r;
  out_sum   <= out_sum_r;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        accum_r     <= (others => '0');
        sample_cnt  <= 0;
        out_valid_r <= '0';
        out_sum_r   <= (others => '0');
      else
        out_valid_r <= '0';
        if in_valid = '1' then
          accum_r <= accum_r + resize(in_sample, accum_r'length);
          if sample_cnt = G_DUMP_LEN - 1 then
            out_sum_r   <= accum_r + resize(in_sample, accum_r'length);
            out_valid_r <= '1';
            accum_r     <= (others => '0');
            sample_cnt  <= 0;
          else
            sample_cnt <= sample_cnt + 1;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
