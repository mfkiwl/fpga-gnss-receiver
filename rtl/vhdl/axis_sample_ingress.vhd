library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axis_sample_ingress is
  port (
    clk            : in  std_logic;
    rst_n          : in  std_logic;
    in_valid       : in  std_logic;
    in_i           : in  signed(15 downto 0);
    in_q           : in  signed(15 downto 0);
    in_ready       : out std_logic;
    out_tvalid     : out std_logic;
    out_tready     : in  std_logic;
    out_i          : out signed(15 downto 0);
    out_q          : out signed(15 downto 0);
    sample_counter : out unsigned(31 downto 0)
  );
end entity;

architecture rtl of axis_sample_ingress is
  signal sample_counter_r : unsigned(31 downto 0) := (others => '0');
  signal out_tvalid_r     : std_logic := '0';
  signal out_i_r          : signed(15 downto 0) := (others => '0');
  signal out_q_r          : signed(15 downto 0) := (others => '0');
begin
  in_ready       <= out_tready;
  out_tvalid     <= out_tvalid_r;
  out_i          <= out_i_r;
  out_q          <= out_q_r;
  sample_counter <= sample_counter_r;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        sample_counter_r <= (others => '0');
        out_tvalid_r     <= '0';
        out_i_r          <= (others => '0');
        out_q_r          <= (others => '0');
      else
        out_tvalid_r <= '0';
        if in_valid = '1' and out_tready = '1' then
          out_tvalid_r     <= '1';
          out_i_r          <= in_i;
          out_q_r          <= in_q;
          sample_counter_r <= sample_counter_r + 1;
        end if;
      end if;
    end if;
  end process;
end architecture;
