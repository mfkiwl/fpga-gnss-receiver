library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.gps_l1_ca_acq_fft_pkg.all;

entity gps_l1_ca_acq_fft_prn_gen_tb is
  generic (
    G_PRN1_FILE  : string := "sim/vectors/acq_fft_prn_prn1.txt";
    G_PRN19_FILE : string := "sim/vectors/acq_fft_prn_prn19.txt"
  );
end entity;

architecture tb of gps_l1_ca_acq_fft_prn_gen_tb is
  constant C_CLK_PERIOD : time := 10 ns;

  signal clk   : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal start : std_logic := '0';
  signal prn_i : unsigned(5 downto 0) := (others => '0');
  signal seq_o : prn_seq_t;
  signal done_o: std_logic;
begin
  clk <= not clk after C_CLK_PERIOD / 2;

  dut : entity work.gps_l1_ca_acq_fft_prn_gen
    port map (
      clk    => clk,
      rst_n  => rst_n,
      start  => start,
      prn_i  => prn_i,
      seq_o  => seq_o,
      done_o => done_o
    );

  stim_proc : process
    procedure load_prn_seq(path_v : in string; variable seq_v : out prn_seq_t) is
      file seq_file : text;
      variable read_status_v : file_open_status;
      variable l_v : line;
      variable bit_v : integer;
      variable idx_v : integer := 0;
    begin
      file_open(read_status_v, seq_file, path_v, read_mode);
      assert read_status_v = open_ok
        report "Unable to open PRN vector file: " & path_v
        severity failure;

      while not endfile(seq_file) loop
        readline(seq_file, l_v);
        read(l_v, bit_v);
        assert idx_v <= 1022
          report "Too many PRN chips in vector file: " & path_v
          severity failure;
        if bit_v = 0 then
          seq_v(idx_v) := '0';
        else
          seq_v(idx_v) := '1';
        end if;
        idx_v := idx_v + 1;
      end loop;
      file_close(seq_file);

      assert idx_v = 1023
        report "Expected exactly 1023 chips in PRN vector file: " & path_v
        severity failure;
    end procedure;

    variable ref1_v  : prn_seq_t;
    variable ref19_v : prn_seq_t;
    variable ref32_v : prn_seq_t;
  begin
    rst_n <= '0';
    wait for 3 * C_CLK_PERIOD;
    assert done_o = '0'
      report "PRN gen done_o should remain low during reset"
      severity failure;
    rst_n <= '1';
    wait until rising_edge(clk);

    -- Single-cycle start for PRN1 reference.
    prn_i <= to_unsigned(1, 6);
    start <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    assert done_o = '1'
      report "PRN gen did not assert done after start"
      severity failure;
    start <= '0';
    wait until rising_edge(clk);

    load_prn_seq(G_PRN1_FILE, ref1_v);
    for i in 0 to 1022 loop
      assert seq_o(i) = ref1_v(i)
        report "PRN1 mismatch at chip " & integer'image(i)
        severity failure;
    end loop;

    -- Back-to-back starts with held start high should still produce valid done pulses.
    ref32_v := build_prn_sequence(32);
    prn_i <= to_unsigned(32, 6);
    start <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    assert done_o = '1'
      report "PRN gen expected done_o=1 on held-start cycle A"
      severity failure;
    wait until rising_edge(clk);
    wait for 1 ns;
    assert done_o = '1'
      report "PRN gen expected done_o=1 on held-start cycle B"
      severity failure;
    start <= '0';
    wait until rising_edge(clk);
    for i in 0 to 1022 loop
      assert seq_o(i) = ref32_v(i)
        report "PRN32 mismatch at chip " & integer'image(i)
        severity failure;
    end loop;

    -- Reset must dominate start and clear observable state.
    prn_i <= to_unsigned(1, 6);
    start <= '1';
    rst_n <= '0';
    wait until rising_edge(clk);
    wait for 1 ns;
    assert done_o = '0'
      report "PRN gen done_o must remain low while reset asserted"
      severity failure;
    for i in 0 to 1022 loop
      assert seq_o(i) = '0'
        report "PRN gen sequence should clear to zero during reset"
        severity failure;
    end loop;
    start <= '0';
    rst_n <= '1';
    wait until rising_edge(clk);

    prn_i <= to_unsigned(19, 6);
    start <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    assert done_o = '1'
      report "PRN gen did not assert done for PRN19"
      severity failure;
    start <= '0';
    wait until rising_edge(clk);

    load_prn_seq(G_PRN19_FILE, ref19_v);
    for i in 0 to 1022 loop
      assert seq_o(i) = ref19_v(i)
        report "PRN19 mismatch at chip " & integer'image(i)
        severity failure;
    end loop;

    assert seq_o /= ref1_v
      report "PRN19 sequence unexpectedly equals PRN1"
      severity failure;

    report "gps_l1_ca_acq_fft_prn_gen_tb passed";
    wait;
  end process;
end architecture;
