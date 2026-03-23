library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.fft_types.all;
use work.gps_l1_ca_acq_fft_pkg.all;

entity gps_l1_ca_acq_fft_shared_core is
  port (
    clk       : in  std_logic;
    rst_n     : in  std_logic;
    start     : in  std_logic;
    inverse_i : in  std_logic;
    din_i     : in  cpx32_vec_t;
    dout_o    : out cpx32_vec_t;
    done_o    : out std_logic
  );
end entity;

architecture rtl of gps_l1_ca_acq_fft_shared_core is
  constant C_DATA_BITS : integer := 24;
  constant C_PHASE_BITS: integer := 11;
  constant C_FFT_DELAY : integer := 6382;
  constant C_IFFT_NORM_SHIFT : integer := 11;
  constant C_TOTAL_CYCLES : integer := C_FFT_DELAY + C_NFFT;

  type state_t is (IDLE, RUN);

  signal state_r      : state_t := IDLE;
  signal inverse_r    : std_logic := '0';
  signal cycle_r      : integer range 0 to C_TOTAL_CYCLES := 0;
  signal in_frame_r   : cpx32_vec_t := (others => C_CPX_ZERO);
  signal out_frame_r  : cpx32_vec_t := (others => C_CPX_ZERO);
  signal done_r       : std_logic := '0';

  signal fft_phase_r  : unsigned(C_PHASE_BITS - 1 downto 0) := (others => '0');
  signal fft_din_r    : complex := to_complex(0, 0);
  signal fft_dout_s   : complex;

  function neg_sat_s32(x : signed(31 downto 0)) return signed is
  begin
    if x = C_S32_MIN then
      return C_S32_MAX;
    end if;
    return -x;
  end function;
begin
  dout_o <= out_frame_r;
  done_o <= done_r;

  fft2048_u : entity work.fft2048_wide_wrapper1
    generic map (
      dataBits => C_DATA_BITS,
      twBits   => 12,
      inverse  => false
    )
    port map (
      clk   => clk,
      din   => fft_din_r,
      phase => fft_phase_r,
      dout  => fft_dout_s
    );

  process (clk)
    variable in_idx_v  : integer;
    variable out_idx_v : integer;
    variable in_v      : cpx32_t;
    variable out_v     : cpx32_t;
    variable out_re_v  : signed(31 downto 0);
    variable out_im_v  : signed(31 downto 0);
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        state_r     <= IDLE;
        inverse_r   <= '0';
        cycle_r     <= 0;
        in_frame_r  <= (others => C_CPX_ZERO);
        out_frame_r <= (others => C_CPX_ZERO);
        done_r      <= '0';
        fft_phase_r <= (others => '0');
        fft_din_r   <= to_complex(0, 0);
      else
        done_r <= '0';

        case state_r is
          when IDLE =>
            fft_din_r <= to_complex(0, 0);
            if start = '1' then
              in_frame_r <= din_i;
              inverse_r  <= inverse_i;
              cycle_r    <= 0;
              state_r    <= RUN;
            end if;

          when RUN =>
            in_idx_v := cycle_r mod C_NFFT;
            fft_phase_r <= to_unsigned(in_idx_v, fft_phase_r'length);

            if cycle_r < C_NFFT then
              in_v := in_frame_r(cycle_r);
              if inverse_r = '1' then
                in_v.im := neg_sat_s32(in_v.im);
              end if;

              fft_din_r <= to_complex(
                resize(in_v.re, C_DATA_BITS),
                resize(in_v.im, C_DATA_BITS)
              );
            else
              fft_din_r <= to_complex(0, 0);
            end if;

            if (cycle_r >= C_FFT_DELAY) and (cycle_r < C_TOTAL_CYCLES) then
              out_idx_v := cycle_r - C_FFT_DELAY;
              out_re_v := resize(complex_re(fft_dout_s, C_DATA_BITS), 32);
              out_im_v := resize(complex_im(fft_dout_s, C_DATA_BITS), 32);
              if inverse_r = '1' then
                out_im_v := neg_sat_s32(out_im_v);
                out_re_v := shift_right(out_re_v, C_IFFT_NORM_SHIFT);
                out_im_v := shift_right(out_im_v, C_IFFT_NORM_SHIFT);
              end if;

              out_v.re := out_re_v;
              out_v.im := out_im_v;
              out_frame_r(out_idx_v) <= out_v;
            end if;

            if cycle_r + 1 >= C_TOTAL_CYCLES then
              state_r <= IDLE;
              done_r  <= '1';
            else
              cycle_r <= cycle_r + 1;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
