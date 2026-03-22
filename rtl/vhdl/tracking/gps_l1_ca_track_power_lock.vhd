library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gps_l1_ca_track_pkg.all;

entity gps_l1_ca_track_power_lock is
  port (
    prompt_i_s_i     : in  integer;
    prompt_q_s_i     : in  integer;
    early_i_s_i      : in  integer;
    early_q_s_i      : in  integer;
    late_i_s_i       : in  integer;
    late_q_s_i       : in  integer;
    cn0_sig_avg_i    : in  integer;
    cn0_noise_avg_i  : in  integer;
    nbd_avg_i        : in  integer;
    nbp_avg_i        : in  integer;
    cn0_sig_avg_o    : out integer;
    cn0_noise_avg_o  : out integer;
    nbd_avg_o        : out integer;
    nbp_avg_o        : out integer;
    cn0_dbhz_o       : out integer;
    carrier_metric_o : out integer
  );
end entity;

architecture rtl of gps_l1_ca_track_power_lock is
begin
  process (all)
    variable prompt_i_v          : integer;
    variable prompt_q_v          : integer;
    variable early_i_v           : integer;
    variable early_q_v           : integer;
    variable late_i_v            : integer;
    variable late_q_v            : integer;
    variable cn0_sig_avg_in_v    : integer;
    variable cn0_noise_avg_in_v  : integer;
    variable nbd_avg_in_v        : integer;
    variable nbp_avg_in_v        : integer;
    variable sig_pow_v          : integer;
    variable early_pow_v        : integer;
    variable late_pow_v         : integer;
    variable noise_sample_v     : integer;
    variable sig_sample_v       : integer;
    variable cn0_sig_avg_v      : integer;
    variable cn0_noise_avg_v    : integer;
    variable nbd_sample_v       : integer;
    variable nbp_sample_v       : integer;
    variable nbd_avg_v          : integer;
    variable nbp_avg_v          : integer;
    variable metric_v           : integer;
    variable cn0_v              : integer;
  begin
    -- Guard against uninitialized integer inputs at time 0.
    prompt_i_v := clamp_i(prompt_i_s_i, -32767, 32767);
    prompt_q_v := clamp_i(prompt_q_s_i, -32767, 32767);
    early_i_v := clamp_i(early_i_s_i, -32767, 32767);
    early_q_v := clamp_i(early_q_s_i, -32767, 32767);
    late_i_v := clamp_i(late_i_s_i, -32767, 32767);
    late_q_v := clamp_i(late_q_s_i, -32767, 32767);
    cn0_sig_avg_in_v := clamp_i(cn0_sig_avg_i, 1, 1000000000);
    cn0_noise_avg_in_v := clamp_i(cn0_noise_avg_i, 1, 1000000000);
    nbd_avg_in_v := clamp_i(nbd_avg_i, -1000000000, 1000000000);
    nbp_avg_in_v := clamp_i(nbp_avg_i, 1, 1000000000);

    sig_pow_v := prompt_i_v * prompt_i_v + prompt_q_v * prompt_q_v;
    early_pow_v := early_i_v * early_i_v + early_q_v * early_q_v;
    late_pow_v := late_i_v * late_i_v + late_q_v * late_q_v;

    -- Compute the mean without overflowing when both powers are near INTEGER'high.
    noise_sample_v := (early_pow_v / 2) + (late_pow_v / 2);
    if noise_sample_v < 1 then
      noise_sample_v := 1;
    end if;

    sig_sample_v := sig_pow_v - noise_sample_v;
    if sig_sample_v < 1 then
      sig_sample_v := 1;
    end if;

    cn0_sig_avg_v := cn0_sig_avg_in_v + (sig_sample_v - cn0_sig_avg_in_v) / C_CN0_AVG_DIV;
    cn0_noise_avg_v := cn0_noise_avg_in_v + (noise_sample_v - cn0_noise_avg_in_v) / C_CN0_AVG_DIV;

    if cn0_sig_avg_v < 1 then
      cn0_sig_avg_v := 1;
    elsif cn0_sig_avg_v > 2000000 then
      cn0_sig_avg_v := 2000000;
    end if;
    if cn0_noise_avg_v < 1 then
      cn0_noise_avg_v := 1;
    elsif cn0_noise_avg_v > 2000000 then
      cn0_noise_avg_v := 2000000;
    end if;

    cn0_v := cn0_dbhz_from_powers(cn0_sig_avg_v, cn0_noise_avg_v);

    nbd_sample_v := (prompt_i_v * prompt_i_v) - (prompt_q_v * prompt_q_v);
    nbp_sample_v := (prompt_i_v * prompt_i_v) + (prompt_q_v * prompt_q_v);
    if nbp_sample_v < 1 then
      nbp_sample_v := 1;
    end if;

    nbd_avg_v := nbd_avg_in_v + (nbd_sample_v - nbd_avg_in_v) / C_LOCK_SMOOTH_DIV;
    nbp_avg_v := nbp_avg_in_v + (nbp_sample_v - nbp_avg_in_v) / C_LOCK_SMOOTH_DIV;
    if nbp_avg_v < 1 then
      nbp_avg_v := 1;
    end if;

    metric_v := (nbd_avg_v * 32768) / nbp_avg_v;
    if metric_v > 32767 then
      metric_v := 32767;
    elsif metric_v < -32768 then
      metric_v := -32768;
    end if;

    cn0_sig_avg_o <= cn0_sig_avg_v;
    cn0_noise_avg_o <= cn0_noise_avg_v;
    nbd_avg_o <= nbd_avg_v;
    nbp_avg_o <= nbp_avg_v;
    cn0_dbhz_o <= clamp_i(cn0_v, 0, 99);
    carrier_metric_o <= metric_v;
  end process;
end architecture;
