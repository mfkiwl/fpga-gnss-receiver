library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gps_l1_ca_pkg.all;
use work.gps_l1_ca_acq_fft_pkg.all;

entity gps_l1_ca_acq_fft is
  generic (
    G_DWELL_MS : integer := 2
  );
  port (
    clk                  : in  std_logic;
    rst_n                : in  std_logic;
    core_en              : in  std_logic;
    start_pulse          : in  std_logic;
    prn_start            : in  unsigned(5 downto 0);
    prn_stop             : in  unsigned(5 downto 0);
    doppler_min          : in  signed(15 downto 0);
    doppler_max          : in  signed(15 downto 0);
    doppler_step         : in  signed(15 downto 0);
    detect_thresh        : in  unsigned(31 downto 0);
    coh_ms_i             : in  unsigned(7 downto 0);
    noncoh_dwells_i      : in  unsigned(7 downto 0);
    doppler_bin_count_i  : in  unsigned(7 downto 0);
    code_bin_count_i     : in  unsigned(10 downto 0);
    code_bin_step_i      : in  unsigned(10 downto 0);
    s_valid              : in  std_logic;
    s_i                  : in  signed(15 downto 0);
    s_q                  : in  signed(15 downto 0);
    acq_done             : out std_logic;
    acq_success          : out std_logic;
    result_valid         : out std_logic;
    result_prn           : out unsigned(5 downto 0);
    result_dopp          : out signed(15 downto 0);
    result_code          : out unsigned(10 downto 0);
    result_metric        : out unsigned(31 downto 0)
  );
end entity;

architecture rtl of gps_l1_ca_acq_fft is
  type state_t is (
    IDLE,
    PRN_PREP,
    CAPTURE_MS,
    DOPP_START,
    DOPP_WAIT,
    CODE_EVAL,
    COH_COMMIT,
    PRN_EVAL,
    FINALIZE
  );

  signal state_r              : state_t := IDLE;
  signal prn_cur_r            : unsigned(5 downto 0) := to_unsigned(1, 6);
  signal prn_stop_r           : unsigned(5 downto 0) := to_unsigned(1, 6);

  signal cap_i_r              : sample_arr_t;
  signal cap_q_r              : sample_arr_t;
  signal cap_sample_idx_r     : integer range 0 to C_SAMPLES_PER_MS - 1 := 0;

  signal coh_i_acc_r          : coh_arr_t;
  signal coh_q_acc_r          : coh_arr_t;
  signal noncoh_metric_r      : metric_arr_t;
  signal bin_code_r           : code_arr_t;
  signal bin_dopp_r           : dopp_arr_t;

  signal prn_fft_r            : cpx32_vec_t := (others => C_CPX_ZERO);
  signal corr_vec_r           : cpx32_vec_t := (others => C_CPX_ZERO);

  signal active_code_bins_r   : integer range 1 to C_MAX_CODE_BINS := C_DEF_CODE_BINS;
  signal active_dopp_bins_r   : integer range 1 to C_MAX_DOPP_BINS := C_DEF_DOPP_BINS;
  signal active_total_bins_r  : integer range 1 to C_MAX_BINS := C_DEF_CODE_BINS * C_DEF_DOPP_BINS;
  signal active_coh_ms_r      : integer range 1 to 255 := C_DEF_COH_MS;
  signal active_noncoh_r      : integer range 1 to 255 := G_DWELL_MS;

  signal coh_ms_idx_r         : integer range 0 to 254 := 0;
  signal noncoh_idx_r         : integer range 0 to 254 := 0;

  signal dopp_idx_r           : integer range 0 to C_MAX_DOPP_BINS - 1 := 0;
  signal code_eval_idx_r      : integer range 0 to C_MAX_CODE_BINS - 1 := 0;

  signal finalize_bin_idx_r   : integer range 0 to C_MAX_BINS - 1 := 0;
  signal prn_eval_idx_r       : integer range 0 to C_MAX_BINS - 1 := 0;
  signal prn_best_metric_r    : unsigned(31 downto 0) := (others => '0');
  signal prn_best_code_r      : unsigned(10 downto 0) := (others => '0');
  signal prn_best_dopp_r      : signed(15 downto 0) := (others => '0');

  signal best_metric_r        : unsigned(31 downto 0) := (others => '0');
  signal best_prn_r           : unsigned(5 downto 0) := to_unsigned(1, 6);
  signal best_code_r          : unsigned(10 downto 0) := (others => '0');
  signal best_dopp_r          : signed(15 downto 0) := (others => '0');

  signal acq_done_r           : std_logic := '0';
  signal acq_success_r        : std_logic := '0';
  signal result_valid_r       : std_logic := '0';

  signal bin_proc_start_r     : std_logic := '0';
  signal bin_proc_done_s      : std_logic;
  signal bin_proc_corr_s      : cpx32_vec_t;
  signal mix_dopp_hz_s        : signed(15 downto 0);
begin
  acq_done      <= acq_done_r;
  acq_success   <= acq_success_r;
  result_valid  <= result_valid_r;
  result_prn    <= best_prn_r;
  result_dopp   <= best_dopp_r;
  result_code   <= best_code_r;
  result_metric <= best_metric_r;

  mix_dopp_hz_s <= bin_dopp_r(dopp_idx_r * active_code_bins_r);

  bin_proc_u : entity work.gps_l1_ca_acq_fft_bin_proc
    port map (
      clk       => clk,
      rst_n     => rst_n,
      start     => bin_proc_start_r,
      cap_i_i   => cap_i_r,
      cap_q_i   => cap_q_r,
      dopp_hz_i => mix_dopp_hz_s,
      prn_fft_i => prn_fft_r,
      corr_o    => bin_proc_corr_s,
      done_o    => bin_proc_done_s
    );

  process (clk)
    variable coh_cfg_i         : integer;
    variable noncoh_cfg_i      : integer;
    variable code_bins_cfg_i   : integer;
    variable code_step_cfg_i   : integer;
    variable dopp_bins_cfg_i   : integer;

    variable step_i            : integer;
    variable dopp_min_i        : integer;
    variable dopp_max_i        : integer;
    variable dopp_span_i       : integer;
    variable full_dopp_bins_i  : integer;
    variable active_dopp_i     : integer;
    variable start_dopp_idx_i  : integer;
    variable active_code_i     : integer;
    variable total_bins_i      : integer;
    variable bin_i             : integer;
    variable d_i               : integer;
    variable c_i               : integer;
    variable code_i            : integer;
    variable dopp_hz_i         : integer;
    variable next_prn_i        : integer;
    variable prn_start_i       : integer;
    variable prn_stop_i        : integer;

    variable coh_metric_v      : unsigned(31 downto 0);
    variable noncoh_sum_v      : unsigned(31 downto 0);
    variable prn_metric_next_v : unsigned(31 downto 0);
    variable prn_code_next_v   : unsigned(10 downto 0);
    variable prn_dopp_next_v   : signed(15 downto 0);
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        state_r             <= IDLE;
        prn_cur_r           <= to_unsigned(1, 6);
        prn_stop_r          <= to_unsigned(1, 6);
        cap_sample_idx_r    <= 0;
        active_code_bins_r  <= C_DEF_CODE_BINS;
        active_dopp_bins_r  <= C_DEF_DOPP_BINS;
        active_total_bins_r <= C_DEF_CODE_BINS * C_DEF_DOPP_BINS;
        active_coh_ms_r     <= C_DEF_COH_MS;
        active_noncoh_r     <= G_DWELL_MS;
        coh_ms_idx_r        <= 0;
        noncoh_idx_r        <= 0;
        dopp_idx_r          <= 0;
        code_eval_idx_r     <= 0;
        finalize_bin_idx_r  <= 0;
        prn_eval_idx_r      <= 0;
        prn_best_metric_r   <= (others => '0');
        prn_best_code_r     <= (others => '0');
        prn_best_dopp_r     <= (others => '0');
        best_metric_r       <= (others => '0');
        best_prn_r          <= to_unsigned(1, 6);
        best_code_r         <= (others => '0');
        best_dopp_r         <= (others => '0');
        acq_done_r          <= '0';
        acq_success_r       <= '0';
        result_valid_r      <= '0';

        prn_fft_r           <= (others => C_CPX_ZERO);
        corr_vec_r          <= (others => C_CPX_ZERO);
        bin_proc_start_r    <= '0';

        for i in 0 to C_MAX_BINS - 1 loop
          noncoh_metric_r(i) <= (others => '0');
          coh_i_acc_r(i) <= (others => '0');
          coh_q_acc_r(i) <= (others => '0');
          bin_code_r(i) <= (others => '0');
          bin_dopp_r(i) <= (others => '0');
        end loop;
      else
        acq_done_r       <= '0';
        result_valid_r   <= '0';
        bin_proc_start_r <= '0';

        case state_r is
          when IDLE =>
            acq_success_r <= '0';
            if core_en = '1' and start_pulse = '1' then
              coh_cfg_i := to_integer(coh_ms_i);
              if coh_cfg_i <= 0 then
                coh_cfg_i := C_DEF_COH_MS;
              elsif coh_cfg_i > 255 then
                coh_cfg_i := 255;
              end if;

              noncoh_cfg_i := to_integer(noncoh_dwells_i);
              if noncoh_cfg_i <= 0 then
                noncoh_cfg_i := G_DWELL_MS;
              elsif noncoh_cfg_i > 255 then
                noncoh_cfg_i := 255;
              end if;

              code_bins_cfg_i := to_integer(code_bin_count_i);
              if code_bins_cfg_i <= 0 then
                code_bins_cfg_i := C_DEF_CODE_BINS;
              elsif code_bins_cfg_i > C_MAX_CODE_BINS then
                code_bins_cfg_i := C_MAX_CODE_BINS;
              end if;

              code_step_cfg_i := to_integer(code_bin_step_i);
              if code_step_cfg_i <= 0 then
                code_step_cfg_i := C_DEF_CODE_STEP;
              elsif code_step_cfg_i > 1022 then
                code_step_cfg_i := 1022;
              end if;

              step_i := abs_i(to_integer(doppler_step));
              if step_i < 1 then
                step_i := 1;
              end if;

              dopp_min_i := to_integer(doppler_min);
              dopp_max_i := to_integer(doppler_max);
              if dopp_max_i < dopp_min_i then
                dopp_span_i := dopp_min_i;
                dopp_min_i := dopp_max_i;
                dopp_max_i := dopp_span_i;
              end if;

              dopp_span_i := dopp_max_i - dopp_min_i;
              full_dopp_bins_i := (dopp_span_i / step_i) + 1;
              if full_dopp_bins_i < 1 then
                full_dopp_bins_i := 1;
              end if;

              dopp_bins_cfg_i := to_integer(doppler_bin_count_i);
              if dopp_bins_cfg_i <= 0 then
                active_dopp_i := C_DEF_DOPP_BINS;
              else
                active_dopp_i := dopp_bins_cfg_i;
              end if;
              if active_dopp_i > C_MAX_DOPP_BINS then
                active_dopp_i := C_MAX_DOPP_BINS;
              end if;
              if active_dopp_i > full_dopp_bins_i then
                active_dopp_i := full_dopp_bins_i;
              end if;
              if active_dopp_i < 1 then
                active_dopp_i := 1;
              end if;

              start_dopp_idx_i := (full_dopp_bins_i - active_dopp_i) / 2;

              active_code_i := code_bins_cfg_i;
              total_bins_i := active_code_i * active_dopp_i;
              if total_bins_i < 1 then
                total_bins_i := 1;
              elsif total_bins_i > C_MAX_BINS then
                total_bins_i := C_MAX_BINS;
              end if;

              for i in 0 to C_MAX_BINS - 1 loop
                noncoh_metric_r(i) <= (others => '0');
                coh_i_acc_r(i) <= (others => '0');
                coh_q_acc_r(i) <= (others => '0');
                bin_code_r(i) <= (others => '0');
                bin_dopp_r(i) <= (others => '0');
              end loop;

              bin_i := 0;
              for d in 0 to C_MAX_DOPP_BINS - 1 loop
                exit when d >= active_dopp_i;
                d_i := start_dopp_idx_i + d;
                dopp_hz_i := dopp_min_i + d_i * step_i;
                for c in 0 to C_MAX_CODE_BINS - 1 loop
                  exit when c >= active_code_i;
                  if bin_i < total_bins_i then
                    c_i := c * code_step_cfg_i;
                    code_i := c_i mod 1023;
                    if code_i < 0 then
                      code_i := code_i + 1023;
                    end if;
                    bin_code_r(bin_i) <= to_unsigned(code_i, 11);
                    bin_dopp_r(bin_i) <= clamp_s16(dopp_hz_i);
                    bin_i := bin_i + 1;
                  end if;
                end loop;
              end loop;

              active_code_bins_r  <= active_code_i;
              active_dopp_bins_r  <= active_dopp_i;
              active_total_bins_r <= total_bins_i;
              active_coh_ms_r     <= coh_cfg_i;
              active_noncoh_r     <= noncoh_cfg_i;

              prn_start_i := to_integer(prn_start);
              prn_stop_i  := to_integer(prn_stop);
              if prn_start_i < 1 then
                prn_start_i := 1;
              elsif prn_start_i > 32 then
                prn_start_i := 32;
              end if;
              if prn_stop_i < 1 then
                prn_stop_i := 1;
              elsif prn_stop_i > 32 then
                prn_stop_i := 32;
              end if;

              prn_cur_r           <= to_unsigned(prn_start_i, prn_cur_r'length);
              prn_stop_r          <= to_unsigned(prn_stop_i, prn_stop_r'length);
              cap_sample_idx_r    <= 0;
              coh_ms_idx_r        <= 0;
              noncoh_idx_r        <= 0;
              dopp_idx_r          <= 0;
              code_eval_idx_r     <= 0;
              finalize_bin_idx_r  <= 0;
              prn_eval_idx_r      <= 0;
              prn_best_metric_r   <= (others => '0');
              prn_best_code_r     <= (others => '0');
              prn_best_dopp_r     <= (others => '0');
              best_metric_r       <= (others => '0');
              best_prn_r          <= to_unsigned(prn_start_i, best_prn_r'length);
              best_code_r         <= (others => '0');
              best_dopp_r         <= (others => '0');

              state_r <= PRN_PREP;
            end if;

          when PRN_PREP =>
            prn_fft_r        <= prn_fft_from_lut(to_integer(prn_cur_r));
            cap_sample_idx_r <= 0;
            dopp_idx_r       <= 0;
            code_eval_idx_r  <= 0;
            state_r          <= CAPTURE_MS;

          when CAPTURE_MS =>
            if s_valid = '1' then
              cap_i_r(cap_sample_idx_r) <= s_i;
              cap_q_r(cap_sample_idx_r) <= s_q;
              if cap_sample_idx_r = C_SAMPLES_PER_MS - 1 then
                dopp_idx_r      <= 0;
                code_eval_idx_r <= 0;
                state_r         <= DOPP_START;
              else
                cap_sample_idx_r <= cap_sample_idx_r + 1;
              end if;
            end if;

          when DOPP_START =>
            bin_proc_start_r <= '1';
            state_r <= DOPP_WAIT;

          when DOPP_WAIT =>
            if bin_proc_done_s = '1' then
              corr_vec_r      <= bin_proc_corr_s;
              code_eval_idx_r <= 0;
              state_r         <= CODE_EVAL;
            end if;

          when CODE_EVAL =>
            bin_i  := (dopp_idx_r * active_code_bins_r) + code_eval_idx_r;
            code_i := to_integer(bin_code_r(bin_i));
            if code_i < 0 then
              code_i := 0;
            elsif code_i > C_NFFT - 1 then
              code_i := C_NFFT - 1;
            end if;

            coh_i_acc_r(bin_i) <= coh_i_acc_r(bin_i) + resize(corr_vec_r(code_i).re, coh_i_acc_r(bin_i)'length);
            coh_q_acc_r(bin_i) <= coh_q_acc_r(bin_i) + resize(corr_vec_r(code_i).im, coh_q_acc_r(bin_i)'length);

            if code_eval_idx_r + 1 >= active_code_bins_r then
              if dopp_idx_r + 1 >= active_dopp_bins_r then
                if coh_ms_idx_r + 1 >= active_coh_ms_r then
                  finalize_bin_idx_r <= 0;
                  state_r <= COH_COMMIT;
                else
                  coh_ms_idx_r     <= coh_ms_idx_r + 1;
                  cap_sample_idx_r <= 0;
                  state_r          <= CAPTURE_MS;
                end if;
              else
                dopp_idx_r <= dopp_idx_r + 1;
                state_r <= DOPP_START;
              end if;
            else
              code_eval_idx_r <= code_eval_idx_r + 1;
            end if;

          when COH_COMMIT =>
            coh_metric_v := sat_add_u32(
              abs_s56_sat_u32(coh_i_acc_r(finalize_bin_idx_r)),
              abs_s56_sat_u32(coh_q_acc_r(finalize_bin_idx_r))
            );
            noncoh_sum_v := sat_add_u32(noncoh_metric_r(finalize_bin_idx_r), coh_metric_v);
            noncoh_metric_r(finalize_bin_idx_r) <= noncoh_sum_v;
            coh_i_acc_r(finalize_bin_idx_r) <= (others => '0');
            coh_q_acc_r(finalize_bin_idx_r) <= (others => '0');

            if finalize_bin_idx_r + 1 >= active_total_bins_r then
              coh_ms_idx_r <= 0;
              if noncoh_idx_r + 1 >= active_noncoh_r then
                prn_eval_idx_r    <= 0;
                prn_best_metric_r <= (others => '0');
                prn_best_code_r   <= bin_code_r(0);
                prn_best_dopp_r   <= bin_dopp_r(0);
                state_r           <= PRN_EVAL;
              else
                noncoh_idx_r     <= noncoh_idx_r + 1;
                cap_sample_idx_r <= 0;
                dopp_idx_r       <= 0;
                code_eval_idx_r  <= 0;
                state_r          <= CAPTURE_MS;
              end if;
            else
              finalize_bin_idx_r <= finalize_bin_idx_r + 1;
            end if;

          when PRN_EVAL =>
            prn_metric_next_v := prn_best_metric_r;
            prn_code_next_v   := prn_best_code_r;
            prn_dopp_next_v   := prn_best_dopp_r;
            if noncoh_metric_r(prn_eval_idx_r) >= prn_metric_next_v then
              prn_metric_next_v := noncoh_metric_r(prn_eval_idx_r);
              prn_code_next_v   := bin_code_r(prn_eval_idx_r);
              prn_dopp_next_v   := bin_dopp_r(prn_eval_idx_r);
            end if;

            if prn_eval_idx_r + 1 >= active_total_bins_r then
              if prn_metric_next_v >= best_metric_r then
                best_metric_r <= prn_metric_next_v;
                best_prn_r    <= prn_cur_r;
                best_code_r   <= prn_code_next_v;
                best_dopp_r   <= prn_dopp_next_v;
              end if;

              if prn_cur_r >= prn_stop_r then
                state_r <= FINALIZE;
              else
                next_prn_i := to_integer(prn_cur_r) + 1;
                if next_prn_i > 63 then
                  next_prn_i := 63;
                end if;

                prn_cur_r      <= to_unsigned(next_prn_i, prn_cur_r'length);
                cap_sample_idx_r <= 0;
                coh_ms_idx_r     <= 0;
                noncoh_idx_r     <= 0;
                dopp_idx_r       <= 0;
                code_eval_idx_r  <= 0;

                for i in 0 to C_MAX_BINS - 1 loop
                  noncoh_metric_r(i) <= (others => '0');
                  coh_i_acc_r(i) <= (others => '0');
                  coh_q_acc_r(i) <= (others => '0');
                end loop;

                state_r <= PRN_PREP;
              end if;
            else
              prn_best_metric_r <= prn_metric_next_v;
              prn_best_code_r   <= prn_code_next_v;
              prn_best_dopp_r   <= prn_dopp_next_v;
              prn_eval_idx_r    <= prn_eval_idx_r + 1;
            end if;

          when FINALIZE =>
            acq_done_r <= '1';
            if best_metric_r >= detect_thresh then
              acq_success_r  <= '1';
              result_valid_r <= '1';
            else
              acq_success_r  <= '0';
            end if;
            state_r <= IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture;
