library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkg_types.all;

entity fifo is
  port (
    clk   : in  std_logic;
    rst_n : in  std_logic;
    wr_en : in  std_logic;
    rd_en : in  std_logic;
    din   : in  byte_t;
    dout  : out byte_t;
    full  : out std_logic;
    empty : out std_logic
  );
end entity;

architecture rtl of fifo is
  type mem_t is array (0 to 3) of byte_t;
  signal mem : mem_t := (others => (others => '0'));

  signal wr_ptr : idx_t := 0;
  signal rd_ptr : idx_t := 0;
  signal count  : integer range 0 to 4 := 0;
begin
  full  <= '1' when count = 4 else '0';
  empty <= '1' when count = 0 else '0';
  dout  <= mem(rd_ptr);

  process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        wr_ptr <= 0;
        rd_ptr <= 0;
        count  <= 0;
      else
        if (wr_en = '1' and count < 4) then
          mem(wr_ptr) <= din;
          if wr_ptr = 3 then
            wr_ptr <= 0;
          else
            wr_ptr <= wr_ptr + 1;
          end if;
          count <= count + 1;
        end if;

        if (rd_en = '1' and count > 0) then
          if rd_ptr = 3 then
            rd_ptr <= 0;
          else
            rd_ptr <= rd_ptr + 1;
          end if;
          count <= count - 1;
        end if;
      end if;
    end if;
  end process;
end architecture;
