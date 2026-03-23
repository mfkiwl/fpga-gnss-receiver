library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gps_l1_ca_pkg.all;
use work.gps_l1_ca_nco_pkg.all;

package gps_l1_ca_acq_fft_pkg is
  constant C_CARR_FCW_PER_HZ : integer := 2147;

  constant C_DEF_COH_MS    : integer := 1;
  constant C_DEF_CODE_BINS : integer := 16;
  constant C_DEF_CODE_STEP : integer := 64;
  constant C_DEF_DOPP_BINS : integer := 9;

  constant C_MAX_CODE_BINS : integer := 1023;
  constant C_MAX_DOPP_BINS : integer := 81;
  constant C_MAX_BINS      : integer := C_MAX_CODE_BINS * C_MAX_DOPP_BINS;

  constant C_NFFT     : integer := 2048;
  constant C_FFT_BITS : integer := 11;

  type sample_arr_t is array (0 to C_SAMPLES_PER_MS - 1) of signed(15 downto 0);
  type metric_arr_t is array (0 to C_MAX_BINS - 1) of unsigned(31 downto 0);
  type coh_arr_t is array (0 to C_MAX_BINS - 1) of signed(55 downto 0);
  type code_arr_t is array (0 to C_MAX_BINS - 1) of unsigned(10 downto 0);
  type dopp_arr_t is array (0 to C_MAX_BINS - 1) of signed(15 downto 0);
  type prn_seq_t is array (0 to 1022) of std_logic;

  type cpx32_t is record
    re : signed(31 downto 0);
    im : signed(31 downto 0);
  end record;

  type cpx32_vec_t is array (0 to C_NFFT - 1) of cpx32_t;
  type cpx32_bank_t is array (0 to C_MAX_CODE_BINS - 1) of cpx32_vec_t;
  type prn_fft_lut_t is array (1 to 32) of cpx32_vec_t;

  constant C_CPX_ZERO : cpx32_t := (
    re => (others => '0'),
    im => (others => '0')
  );

  constant C_S32_MAX : signed(31 downto 0) := signed'(x"7FFFFFFF");
  constant C_S32_MIN : signed(31 downto 0) := signed'(x"80000000");

  function abs_i(x : integer) return integer;

  function sat_add_u32(
    a : unsigned(31 downto 0);
    b : unsigned(31 downto 0)
  ) return u32_t;

  function abs_s56_sat_u32(x : signed(55 downto 0)) return u32_t;

  function clamp_s16(x : integer) return signed;

  function carr_fcw_from_hz(dopp_hz : signed(15 downto 0)) return signed;

  function build_prn_sequence(prn_i : integer) return prn_seq_t;

  function fft_radix2(x : cpx32_vec_t; inverse : boolean) return cpx32_vec_t;

  function build_code_fft_input(prn_seq : prn_seq_t; code_start : integer) return cpx32_vec_t;

  function build_mixed_fft_input(
    cap_i   : sample_arr_t;
    cap_q   : sample_arr_t;
    dopp_hz : signed(15 downto 0)
  ) return cpx32_vec_t;

  function corr0_from_spectra(
    sig_fft  : cpx32_vec_t;
    code_fft : cpx32_vec_t
  ) return cpx32_t;

  function prn_fft_from_lut(prn_i : integer) return cpx32_vec_t;
end package;

package body gps_l1_ca_acq_fft_pkg is
  function abs_i(x : integer) return integer is
  begin
    if x < 0 then
      return -x;
    end if;
    return x;
  end function;

  function sat_add_u32(
    a : unsigned(31 downto 0);
    b : unsigned(31 downto 0)
  ) return u32_t is
    variable sum_v : unsigned(32 downto 0);
  begin
    sum_v := ('0' & a) + ('0' & b);
    if sum_v(32) = '1' then
      return (others => '1');
    end if;
    return sum_v(31 downto 0);
  end function;

  function abs_s56_sat_u32(x : signed(55 downto 0)) return u32_t is
    variable ax : unsigned(55 downto 0);
  begin
    if x < 0 then
      ax := unsigned(-x);
    else
      ax := unsigned(x);
    end if;

    if ax(55 downto 32) /= to_unsigned(0, 24) then
      return (others => '1');
    end if;
    return ax(31 downto 0);
  end function;

  function clamp_s16(x : integer) return signed is
  begin
    if x > 32767 then
      return to_signed(32767, 16);
    elsif x < -32768 then
      return to_signed(-32768, 16);
    else
      return to_signed(x, 16);
    end if;
  end function;

  function carr_fcw_from_hz(dopp_hz : signed(15 downto 0)) return signed is
  begin
    return to_signed(to_integer(dopp_hz) * C_CARR_FCW_PER_HZ, 32);
  end function;

  function g2_tap_a(prn_i : integer) return integer is
  begin
    case prn_i is
      when 1  => return 2;
      when 2  => return 3;
      when 3  => return 4;
      when 4  => return 5;
      when 5  => return 1;
      when 6  => return 2;
      when 7  => return 1;
      when 8  => return 2;
      when 9  => return 3;
      when 10 => return 2;
      when 11 => return 3;
      when 12 => return 5;
      when 13 => return 6;
      when 14 => return 7;
      when 15 => return 8;
      when 16 => return 9;
      when 17 => return 1;
      when 18 => return 2;
      when 19 => return 3;
      when 20 => return 4;
      when 21 => return 5;
      when 22 => return 6;
      when 23 => return 1;
      when 24 => return 4;
      when 25 => return 5;
      when 26 => return 6;
      when 27 => return 7;
      when 28 => return 8;
      when 29 => return 1;
      when 30 => return 2;
      when 31 => return 3;
      when others => return 4;
    end case;
  end function;

  function g2_tap_b(prn_i : integer) return integer is
  begin
    case prn_i is
      when 1  => return 6;
      when 2  => return 7;
      when 3  => return 8;
      when 4  => return 9;
      when 5  => return 9;
      when 6  => return 10;
      when 7  => return 8;
      when 8  => return 9;
      when 9  => return 10;
      when 10 => return 3;
      when 11 => return 4;
      when 12 => return 6;
      when 13 => return 7;
      when 14 => return 8;
      when 15 => return 9;
      when 16 => return 10;
      when 17 => return 4;
      when 18 => return 5;
      when 19 => return 6;
      when 20 => return 7;
      when 21 => return 8;
      when 22 => return 9;
      when 23 => return 3;
      when 24 => return 6;
      when 25 => return 7;
      when 26 => return 8;
      when 27 => return 9;
      when 28 => return 10;
      when 29 => return 6;
      when 30 => return 7;
      when 31 => return 8;
      when others => return 9;
    end case;
  end function;

  function build_prn_sequence(prn_i : integer) return prn_seq_t is
    variable g1 : std_logic_vector(9 downto 0);
    variable g2 : std_logic_vector(9 downto 0);
    variable g1_out : std_logic;
    variable g2_out : std_logic;
    variable fb1 : std_logic;
    variable fb2 : std_logic;
    variable ta  : integer;
    variable tb  : integer;
    variable seq_v : prn_seq_t;
  begin
    g1 := (others => '1');
    g2 := (others => '1');
    ta := g2_tap_a(prn_i);
    tb := g2_tap_b(prn_i);

    for chip in 0 to 1022 loop
      g1_out := g1(9);
      g2_out := g2(ta - 1) xor g2(tb - 1);
      seq_v(chip) := g1_out xor g2_out;

      fb1 := g1(2) xor g1(9);
      fb2 := g2(1) xor g2(2) xor g2(5) xor g2(7) xor g2(8) xor g2(9);

      g1 := g1(8 downto 0) & fb1;
      g2 := g2(8 downto 0) & fb2;
    end loop;
    return seq_v;
  end function;

  function sat_resize_s32(x : signed) return signed is
    variable lo : signed(31 downto 0);
  begin
    if x'length <= 32 then
      return resize(x, 32);
    end if;

    lo := x(31 downto 0);
    if resize(lo, x'length) /= x then
      if x(x'high) = '1' then
        return C_S32_MIN;
      else
        return C_S32_MAX;
      end if;
    end if;

    return lo;
  end function;

  function div_pow2_tz(x : signed; sh : natural) return signed is
  begin
    if sh = 0 then
      return x;
    end if;

    if x < 0 then
      return -shift_right(-x, sh);
    end if;
    return shift_right(x, sh);
  end function;

  function cpx_add_sat(a : cpx32_t; b : cpx32_t) return cpx32_t is
    variable out_v  : cpx32_t;
    variable sum_re : signed(32 downto 0);
    variable sum_im : signed(32 downto 0);
  begin
    sum_re := resize(a.re, 33) + resize(b.re, 33);
    sum_im := resize(a.im, 33) + resize(b.im, 33);
    out_v.re := sat_resize_s32(sum_re);
    out_v.im := sat_resize_s32(sum_im);
    return out_v;
  end function;

  function cpx_sub_sat(a : cpx32_t; b : cpx32_t) return cpx32_t is
    variable out_v  : cpx32_t;
    variable sum_re : signed(32 downto 0);
    variable sum_im : signed(32 downto 0);
  begin
    sum_re := resize(a.re, 33) - resize(b.re, 33);
    sum_im := resize(a.im, 33) - resize(b.im, 33);
    out_v.re := sat_resize_s32(sum_re);
    out_v.im := sat_resize_s32(sum_im);
    return out_v;
  end function;

  function cpx_mul_q15(
    a  : cpx32_t;
    wr : signed(15 downto 0);
    wi : signed(15 downto 0)
  ) return cpx32_t is
    variable out_v     : cpx32_t;
    variable rr        : signed(47 downto 0);
    variable ii        : signed(47 downto 0);
    variable ri        : signed(47 downto 0);
    variable ir        : signed(47 downto 0);
    variable sum_re    : signed(48 downto 0);
    variable sum_im    : signed(48 downto 0);
    variable scale_re  : signed(48 downto 0);
    variable scale_im  : signed(48 downto 0);
  begin
    rr := a.re * wr;
    ii := a.im * wi;
    ri := a.re * wi;
    ir := a.im * wr;

    sum_re := resize(rr, 49) - resize(ii, 49);
    sum_im := resize(ri, 49) + resize(ir, 49);

    scale_re := div_pow2_tz(sum_re, 15);
    scale_im := div_pow2_tz(sum_im, 15);

    out_v.re := sat_resize_s32(scale_re);
    out_v.im := sat_resize_s32(scale_im);
    return out_v;
  end function;

  function bit_reverse(i : integer; bits : integer) return integer is
    variable in_v  : integer := i;
    variable out_v : integer := 0;
  begin
    for b in 0 to bits - 1 loop
      out_v := (out_v * 2) + (in_v mod 2);
      in_v := in_v / 2;
    end loop;
    return out_v;
  end function;

  function fft_radix2(x : cpx32_vec_t; inverse : boolean) return cpx32_vec_t is
    variable a      : cpx32_vec_t := (others => C_CPX_ZERO);
    variable len_i  : integer;
    variable half_i : integer;
    variable base_i : integer;
    variable j      : integer;
    variable tw_idx : integer;
    variable wr     : signed(15 downto 0);
    variable wi     : signed(15 downto 0);
    variable u      : cpx32_t;
    variable t      : cpx32_t;
  begin
    for i in 0 to C_NFFT - 1 loop
      a(bit_reverse(i, C_FFT_BITS)) := x(i);
    end loop;

    len_i := 2;
    while len_i <= C_NFFT loop
      half_i := len_i / 2;
      base_i := 0;
      while base_i < C_NFFT loop
        for k in 0 to half_i - 1 loop
          j := base_i + k;
          tw_idx := (k * 1024) / len_i;
          wr := lo_cos_q15(to_unsigned(tw_idx, 10));
          if inverse then
            wi := lo_sin_q15(to_unsigned(tw_idx, 10));
          else
            wi := -lo_sin_q15(to_unsigned(tw_idx, 10));
          end if;

          t := cpx_mul_q15(a(j + half_i), wr, wi);
          u := a(j);

          a(j)          := cpx_add_sat(u, t);
          a(j + half_i) := cpx_sub_sat(u, t);
        end loop;
        base_i := base_i + len_i;
      end loop;
      len_i := len_i * 2;
    end loop;

    if inverse then
      for i in 0 to C_NFFT - 1 loop
        a(i).re := sat_resize_s32(div_pow2_tz(a(i).re, C_FFT_BITS));
        a(i).im := sat_resize_s32(div_pow2_tz(a(i).im, C_FFT_BITS));
      end loop;
    end if;

    return a;
  end function;

  function build_code_fft_input(prn_seq : prn_seq_t; code_start : integer) return cpx32_vec_t is
    variable out_v         : cpx32_vec_t := (others => C_CPX_ZERO);
    variable chip_idx      : integer;
    variable code_nco      : unsigned(31 downto 0);
    variable next_code_nco : unsigned(31 downto 0);
  begin
    chip_idx := code_start mod 1023;
    if chip_idx < 0 then
      chip_idx := chip_idx + 1023;
    end if;

    code_nco := shift_left(to_unsigned(chip_idx, 32), 21);

    for s in 0 to C_SAMPLES_PER_MS - 1 loop
      if prn_seq(chip_idx) = '1' then
        out_v(s).re := to_signed(-32767, 32);
      else
        out_v(s).re := to_signed(32767, 32);
      end if;
      out_v(s).im := (others => '0');

      next_code_nco := code_nco + C_CODE_NCO_FCW;
      if next_code_nco < code_nco then
        if chip_idx = 1022 then
          chip_idx := 0;
        else
          chip_idx := chip_idx + 1;
        end if;
      end if;
      code_nco := next_code_nco;
    end loop;

    return out_v;
  end function;

  function build_mixed_fft_input(
    cap_i   : sample_arr_t;
    cap_q   : sample_arr_t;
    dopp_hz : signed(15 downto 0)
  ) return cpx32_vec_t is
    variable out_v      : cpx32_vec_t := (others => C_CPX_ZERO);
    variable carr_phase : signed(31 downto 0) := (others => '0');
    variable carr_fcw   : signed(31 downto 0);
    variable phase_idx  : integer;
    variable lo_i       : signed(15 downto 0);
    variable lo_q       : signed(15 downto 0);
    variable prod_ii    : signed(31 downto 0);
    variable prod_qq    : signed(31 downto 0);
    variable prod_iq    : signed(31 downto 0);
    variable prod_qi    : signed(31 downto 0);
    variable mix_re     : signed(32 downto 0);
    variable mix_im     : signed(32 downto 0);
  begin
    carr_fcw := carr_fcw_from_hz(dopp_hz);

    for s in 0 to C_SAMPLES_PER_MS - 1 loop
      phase_idx := to_integer(unsigned(carr_phase(31 downto 22)));
      lo_i := lo_cos_q15(to_unsigned(phase_idx, 10));
      lo_q := -lo_sin_q15(to_unsigned(phase_idx, 10));

      prod_ii := cap_i(s) * lo_i;
      prod_qq := cap_q(s) * lo_q;
      prod_iq := cap_i(s) * lo_q;
      prod_qi := cap_q(s) * lo_i;

      mix_re := resize(prod_ii, 33) - resize(prod_qq, 33);
      mix_im := resize(prod_iq, 33) + resize(prod_qi, 33);

      out_v(s).re := sat_resize_s32(div_pow2_tz(mix_re, 15));
      out_v(s).im := sat_resize_s32(div_pow2_tz(mix_im, 15));

      carr_phase := carr_phase + carr_fcw;
    end loop;

    return out_v;
  end function;

  function corr0_from_spectra(
    sig_fft  : cpx32_vec_t;
    code_fft : cpx32_vec_t
  ) return cpx32_t is
    variable out_v   : cpx32_t := C_CPX_ZERO;
    variable acc_re  : signed(79 downto 0) := (others => '0');
    variable acc_im  : signed(79 downto 0) := (others => '0');
    variable prod_rr : signed(63 downto 0);
    variable prod_ii : signed(63 downto 0);
    variable prod_ir : signed(63 downto 0);
    variable prod_ri : signed(63 downto 0);
    variable term_re : signed(64 downto 0);
    variable term_im : signed(64 downto 0);
  begin
    for k in 0 to C_NFFT - 1 loop
      prod_rr := sig_fft(k).re * code_fft(k).re;
      prod_ii := sig_fft(k).im * code_fft(k).im;
      prod_ir := sig_fft(k).im * code_fft(k).re;
      prod_ri := sig_fft(k).re * code_fft(k).im;

      term_re := resize(prod_rr, 65) + resize(prod_ii, 65);
      term_im := resize(prod_ir, 65) - resize(prod_ri, 65);

      acc_re := acc_re + resize(term_re, 80);
      acc_im := acc_im + resize(term_im, 80);
    end loop;

    out_v.re := sat_resize_s32(div_pow2_tz(acc_re, C_FFT_BITS));
    out_v.im := sat_resize_s32(div_pow2_tz(acc_im, C_FFT_BITS));
    return out_v;
  end function;

  function neg_sat_s32(x : signed(31 downto 0)) return signed is
  begin
    if x = C_S32_MIN then
      return C_S32_MAX;
    end if;
    return -x;
  end function;

  function build_prn_fft_lut return prn_fft_lut_t is
    variable out_v      : prn_fft_lut_t := (others => (others => C_CPX_ZERO));
    variable seq_v      : prn_seq_t;
    variable fft_raw_v  : cpx32_vec_t;
  begin
    for prn in 1 to 32 loop
      seq_v := build_prn_sequence(prn);
      fft_raw_v := fft_radix2(build_code_fft_input(seq_v, 0), false);
      for k in 0 to C_NFFT - 1 loop
        out_v(prn)(k).re := fft_raw_v(k).re;
        out_v(prn)(k).im := neg_sat_s32(fft_raw_v(k).im);
      end loop;
    end loop;
    return out_v;
  end function;

  constant C_PRN_FFT_LUT : prn_fft_lut_t := build_prn_fft_lut;

  function prn_fft_from_lut(prn_i : integer) return cpx32_vec_t is
  begin
    if prn_i >= 1 and prn_i <= 32 then
      return C_PRN_FFT_LUT(prn_i);
    end if;
    return (others => C_CPX_ZERO);
  end function;
end package body;
