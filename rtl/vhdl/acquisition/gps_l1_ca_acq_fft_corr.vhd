library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gps_l1_ca_acq_fft_pkg.all;

entity gps_l1_ca_acq_fft_corr is
  port (
    clk        : in  std_logic;
    rst_n      : in  std_logic;
    start      : in  std_logic;
    sig_fft_i  : in  cpx32_vec_t;
    code_fft_i : in  cpx32_vec_t;
    corr_o     : out cpx32_t;
    done_o     : out std_logic
  );
end entity;

architecture rtl of gps_l1_ca_acq_fft_corr is
  signal corr_r : cpx32_t := C_CPX_ZERO;
  signal done_r : std_logic := '0';
begin
  corr_o <= corr_r;
  done_o <= done_r;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        corr_r <= C_CPX_ZERO;
        done_r <= '0';
      else
        done_r <= '0';
        if start = '1' then
          corr_r <= corr0_from_spectra(sig_fft_i, code_fft_i);
          done_r <= '1';
        end if;
      end if;
    end if;
  end process;
end architecture;
