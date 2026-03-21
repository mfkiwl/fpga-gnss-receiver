library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gps_l1_ca_acq_fft_pkg.all;

entity gps_l1_ca_acq_fft_prn_gen_tb is
end entity;

architecture tb of gps_l1_ca_acq_fft_prn_gen_tb is
  constant C_CLK_PERIOD : time := 10 ns;

  signal clk   : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal start : std_logic := '0';
  signal prn_i : unsigned(5 downto 0) := (others => '0');
  signal seq_o : prn_seq_t;
  signal done_o: std_logic;

  function g2_tap_a(prn_v : integer) return integer is
  begin
    case prn_v is
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

  function g2_tap_b(prn_v : integer) return integer is
  begin
    case prn_v is
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

  function ref_prn_sequence(prn_v : integer) return prn_seq_t is
    variable g1 : std_logic_vector(9 downto 0) := (others => '1');
    variable g2 : std_logic_vector(9 downto 0) := (others => '1');
    variable seq_v : prn_seq_t;
    variable ta : integer;
    variable tb : integer;
    variable g1_out : std_logic;
    variable g2_out : std_logic;
    variable fb1 : std_logic;
    variable fb2 : std_logic;
  begin
    ta := g2_tap_a(prn_v);
    tb := g2_tap_b(prn_v);

    for i in 0 to 1022 loop
      g1_out := g1(9);
      g2_out := g2(10 - ta) xor g2(10 - tb);
      seq_v(i) := g1_out xor g2_out;

      fb1 := g1(2) xor g1(9);
      fb2 := g2(1) xor g2(2) xor g2(5) xor g2(7) xor g2(8) xor g2(9);
      g1 := g1(8 downto 0) & fb1;
      g2 := g2(8 downto 0) & fb2;
    end loop;

    return seq_v;
  end function;
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
    variable ref1_v  : prn_seq_t;
    variable ref19_v : prn_seq_t;
  begin
    rst_n <= '0';
    wait for 3 * C_CLK_PERIOD;
    rst_n <= '1';
    wait until rising_edge(clk);

    prn_i <= to_unsigned(1, 6);
    start <= '1';
    wait until rising_edge(clk);
    start <= '0';
    wait until rising_edge(clk);

    assert done_o = '1'
      report "PRN gen did not assert done after start"
      severity failure;

    ref1_v := ref_prn_sequence(1);
    for i in 0 to 1022 loop
      assert seq_o(i) = ref1_v(i)
        report "PRN1 mismatch at chip " & integer'image(i)
        severity failure;
    end loop;

    prn_i <= to_unsigned(19, 6);
    start <= '1';
    wait until rising_edge(clk);
    start <= '0';
    wait until rising_edge(clk);

    assert done_o = '1'
      report "PRN gen did not assert done for PRN19"
      severity failure;

    ref19_v := ref_prn_sequence(19);
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
