library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gps_l1_ca_acq_fft_pkg.all;

entity gps_l1_ca_acq_fft_code_gen is
  port (
    clk          : in  std_logic;
    rst_n        : in  std_logic;
    start        : in  std_logic;
    prn_seq_i    : in  prn_seq_t;
    code_start_i : in  unsigned(10 downto 0);
    code_fft_o   : out cpx32_vec_t;
    done_o       : out std_logic
  );
end entity;

architecture rtl of gps_l1_ca_acq_fft_code_gen is
  signal code_fft_r : cpx32_vec_t := (others => C_CPX_ZERO);
  signal done_r     : std_logic := '0';
begin
  code_fft_o <= code_fft_r;
  done_o     <= done_r;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        code_fft_r <= (others => C_CPX_ZERO);
        done_r     <= '0';
      else
        done_r <= '0';
        if start = '1' then
          code_fft_r <= fft_radix2(
            build_code_fft_input(prn_seq_i, to_integer(code_start_i)),
            false
          );
          done_r <= '1';
        end if;
      end if;
    end if;
  end process;
end architecture;
