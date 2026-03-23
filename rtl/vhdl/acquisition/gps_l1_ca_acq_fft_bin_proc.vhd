library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gps_l1_ca_acq_fft_pkg.all;

entity gps_l1_ca_acq_fft_bin_proc is
  port (
    clk       : in  std_logic;
    rst_n     : in  std_logic;
    start     : in  std_logic;
    cap_i_i   : in  sample_arr_t;
    cap_q_i   : in  sample_arr_t;
    dopp_hz_i : in  signed(15 downto 0);
    prn_fft_i : in  cpx32_vec_t;
    corr_o    : out cpx32_vec_t;
    done_o    : out std_logic
  );
end entity;

architecture rtl of gps_l1_ca_acq_fft_bin_proc is
  constant C_SPEC_MUL_SHIFT : integer := 11;

  type state_t is (IDLE, FFT_WAIT, IFFT_START, IFFT_WAIT);

  signal state_r      : state_t := IDLE;
  signal done_r       : std_logic := '0';

  signal fft_start_r  : std_logic := '0';
  signal fft_inv_r    : std_logic := '0';
  signal fft_in_r     : cpx32_vec_t := (others => C_CPX_ZERO);
  signal fft_out_s    : cpx32_vec_t;
  signal fft_done_s   : std_logic;

  signal sig_fft_r    : cpx32_vec_t := (others => C_CPX_ZERO);
  signal prod_fft_r   : cpx32_vec_t := (others => C_CPX_ZERO);
  signal corr_r       : cpx32_vec_t := (others => C_CPX_ZERO);

  function sat_s32_from_s64(x : signed(63 downto 0)) return signed is
    variable sign_v : std_logic;
  begin
    sign_v := x(31);
    for i in 63 downto 32 loop
      if x(i) /= sign_v then
        if x(63) = '1' then
          return C_S32_MIN;
        end if;
        if x(63) = '0' then
          return C_S32_MAX;
        end if;
        return to_signed(0, 32);
      end if;
    end loop;
    if sign_v = '0' or sign_v = '1' then
      return x(31 downto 0);
    end if;
    return to_signed(0, 32);
  end function;
begin
  corr_o <= corr_r;
  done_o <= done_r;

  shared_fft_u : entity work.gps_l1_ca_acq_fft_shared_core
    port map (
      clk       => clk,
      rst_n     => rst_n,
      start     => fft_start_r,
      inverse_i => fft_inv_r,
      din_i     => fft_in_r,
      dout_o    => fft_out_s,
      done_o    => fft_done_s
    );

  process (clk)
    variable term_re_v : signed(64 downto 0);
    variable term_im_v : signed(64 downto 0);
    variable prod_rr_v : signed(63 downto 0);
    variable prod_ii_v : signed(63 downto 0);
    variable prod_ri_v : signed(63 downto 0);
    variable prod_ir_v : signed(63 downto 0);
    variable scaled_re_v : signed(63 downto 0);
    variable scaled_im_v : signed(63 downto 0);
    variable prod_v      : cpx32_vec_t;
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        state_r     <= IDLE;
        done_r      <= '0';
        fft_start_r <= '0';
        fft_inv_r   <= '0';
        fft_in_r    <= (others => C_CPX_ZERO);
        sig_fft_r   <= (others => C_CPX_ZERO);
        prod_fft_r  <= (others => C_CPX_ZERO);
        corr_r      <= (others => C_CPX_ZERO);
      else
        done_r      <= '0';
        fft_start_r <= '0';

        case state_r is
          when IDLE =>
            if start = '1' then
              fft_in_r    <= build_mixed_fft_input(cap_i_i, cap_q_i, dopp_hz_i);
              fft_inv_r   <= '0';
              fft_start_r <= '1';
              state_r     <= FFT_WAIT;
            end if;

          when FFT_WAIT =>
            if fft_done_s = '1' then
              sig_fft_r <= fft_out_s;
              state_r <= IFFT_START;
            end if;

          when IFFT_START =>
            prod_v := (others => C_CPX_ZERO);
            for k in 0 to C_NFFT - 1 loop
              prod_rr_v := sig_fft_r(k).re * prn_fft_i(k).re;
              prod_ii_v := sig_fft_r(k).im * prn_fft_i(k).im;
              prod_ri_v := sig_fft_r(k).re * prn_fft_i(k).im;
              prod_ir_v := sig_fft_r(k).im * prn_fft_i(k).re;

              term_re_v := resize(prod_rr_v, 65) - resize(prod_ii_v, 65);
              term_im_v := resize(prod_ri_v, 65) + resize(prod_ir_v, 65);

              scaled_re_v := shift_right(resize(term_re_v, 64), C_SPEC_MUL_SHIFT);
              scaled_im_v := shift_right(resize(term_im_v, 64), C_SPEC_MUL_SHIFT);

              prod_v(k).re := sat_s32_from_s64(scaled_re_v);
              prod_v(k).im := sat_s32_from_s64(scaled_im_v);
            end loop;

            prod_fft_r  <= prod_v;
            fft_in_r    <= prod_v;
            fft_inv_r   <= '1';
            fft_start_r <= '1';
            state_r     <= IFFT_WAIT;

          when IFFT_WAIT =>
            if fft_done_s = '1' then
              corr_r  <= fft_out_s;
              done_r  <= '1';
              state_r <= IDLE;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
