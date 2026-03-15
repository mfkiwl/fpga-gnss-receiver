library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity gps_l1_ca_phase1_tb is
end entity;

architecture tb of gps_l1_ca_phase1_tb is
  constant C_CLK_PER : time := 20 ns;

  signal clk          : std_logic := '0';
  signal rst_n        : std_logic := '0';
  signal sample_valid : std_logic := '0';
  signal sample_i     : signed(15 downto 0) := (others => '0');
  signal sample_q     : signed(15 downto 0) := (others => '0');
  signal sample_ready : std_logic;

  signal ctrl_wreq    : std_logic := '0';
  signal ctrl_waddr   : unsigned(7 downto 0) := (others => '0');
  signal ctrl_wdata   : std_logic_vector(31 downto 0) := (others => '0');
  signal ctrl_wack    : std_logic;
  signal ctrl_rreq    : std_logic := '0';
  signal ctrl_raddr   : unsigned(7 downto 0) := (others => '0');
  signal ctrl_rdata   : std_logic_vector(31 downto 0);
  signal ctrl_rack    : std_logic;

  signal uart_txd     : std_logic;
begin
  clk <= not clk after C_CLK_PER / 2;

  dut : entity work.gps_l1_ca_phase1_top
    port map (
      clk          => clk,
      rst_n        => rst_n,
      sample_valid => sample_valid,
      sample_i     => sample_i,
      sample_q     => sample_q,
      sample_ready => sample_ready,
      ctrl_wreq    => ctrl_wreq,
      ctrl_waddr   => ctrl_waddr,
      ctrl_wdata   => ctrl_wdata,
      ctrl_wack    => ctrl_wack,
      ctrl_rreq    => ctrl_rreq,
      ctrl_raddr   => ctrl_raddr,
      ctrl_rdata   => ctrl_rdata,
      ctrl_rack    => ctrl_rack,
      uart_txd     => uart_txd
    );

  stimulus : process
    procedure ctrl_write(addr : in natural; data : in std_logic_vector(31 downto 0)) is
    begin
      wait until rising_edge(clk);
      ctrl_waddr <= to_unsigned(addr, ctrl_waddr'length);
      ctrl_wdata <= data;
      ctrl_wreq  <= '1';
      wait until rising_edge(clk);
      ctrl_wreq  <= '0';
      wait until rising_edge(clk);
    end procedure;

    variable sample_cnt : integer := 0;
  begin
    rst_n <= '0';
    wait for 200 ns;
    rst_n <= '1';
    wait for 100 ns;

    ctrl_write(16#04#, x"00000201"); -- prn start=1, stop=2
    ctrl_write(16#08#, x"0000EC78"); -- -5000
    ctrl_write(16#0C#, x"00001388"); -- +5000
    ctrl_write(16#10#, x"000001F4"); -- step 500
    ctrl_write(16#14#, x"00000020"); -- low threshold for TB
    ctrl_write(16#24#, x"00000001"); -- init PRN
    ctrl_write(16#28#, x"00000000"); -- init Doppler

    -- core_en=1, acq_start=1, tracking_en=1, uart_en=1
    ctrl_write(16#00#, x"0000001D");
    -- keep run bits without start pulse
    ctrl_write(16#00#, x"00000019");

    while sample_cnt < 12000 loop
      wait until rising_edge(clk);
      if sample_ready = '1' then
        -- 2 MSPS over a 50 MHz sim clock -> one sample every 25 cycles.
        if (sample_cnt mod 25) = 0 then
          sample_valid <= '1';
          sample_i <= to_signed((sample_cnt mod 511) - 255, 16);
          sample_q <= to_signed(255 - (sample_cnt mod 511), 16);
        else
          sample_valid <= '0';
        end if;
      end if;
      sample_cnt := sample_cnt + 1;
    end loop;

    wait for 2 ms;
    assert false report "gps_l1_ca_phase1_tb completed" severity note;
    wait;
  end process;
end architecture;
