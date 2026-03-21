library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gps_l1_ca_acq_fft_pkg.all;

entity gps_l1_ca_acq_fft_prn_gen is
  port (
    clk   : in  std_logic;
    rst_n : in  std_logic;
    start : in  std_logic;
    prn_i : in  unsigned(5 downto 0);
    seq_o : out prn_seq_t;
    done_o: out std_logic
  );
end entity;

architecture rtl of gps_l1_ca_acq_fft_prn_gen is
  signal seq_r  : prn_seq_t := (others => '0');
  signal done_r : std_logic := '0';
begin
  seq_o  <= seq_r;
  done_o <= done_r;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        seq_r  <= (others => '0');
        done_r <= '0';
      else
        done_r <= '0';
        if start = '1' then
          seq_r  <= build_prn_sequence(to_integer(prn_i));
          done_r <= '1';
        end if;
      end if;
    end if;
  end process;
end architecture;
