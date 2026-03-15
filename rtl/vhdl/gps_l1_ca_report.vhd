library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.gps_l1_ca_pkg.all;

entity gps_l1_ca_report is
  port (
    clk              : in  std_logic;
    rst_n            : in  std_logic;
    report_enable    : in  std_logic;
    sample_counter   : in  unsigned(31 downto 0);
    track_state      : in  track_state_t;
    code_lock        : in  std_logic;
    carrier_lock     : in  std_logic;
    report_valid_in  : in  std_logic;
    prn              : in  unsigned(5 downto 0);
    doppler_hz       : in  signed(15 downto 0);
    code_phase       : in  unsigned(10 downto 0);
    prompt_i         : in  signed(23 downto 0);
    prompt_q         : in  signed(23 downto 0);
    nav_valid        : in  std_logic;
    nav_bit          : in  std_logic;
    tx_ready         : in  std_logic;
    tx_valid         : out std_logic;
    tx_data          : out std_logic_vector(7 downto 0);
    tx_last          : out std_logic
  );
end entity;

architecture rtl of gps_l1_ca_report is
  type pkt_t is array (0 to 15) of std_logic_vector(7 downto 0);
  signal pkt_r          : pkt_t := (others => (others => '0'));
  signal pkt_busy_r     : std_logic := '0';
  signal pkt_index_r    : integer range 0 to 15 := 0;
  signal tx_valid_r     : std_logic := '0';
  signal tx_data_r      : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_last_r      : std_logic := '0';
begin
  tx_valid <= tx_valid_r;
  tx_data  <= tx_data_r;
  tx_last  <= tx_last_r;

  process (clk)
    variable pkt_v      : pkt_t;
    variable checksum_v : std_logic_vector(7 downto 0);
    variable state_v    : std_logic_vector(7 downto 0);
    variable trig_v     : std_logic;
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        pkt_r       <= (others => (others => '0'));
        pkt_busy_r  <= '0';
        pkt_index_r <= 0;
        tx_valid_r  <= '0';
        tx_data_r   <= (others => '0');
        tx_last_r   <= '0';
      else
        tx_valid_r <= '0';
        tx_last_r  <= '0';
        trig_v := report_valid_in or nav_valid;

        if report_enable = '1' and pkt_busy_r = '0' and trig_v = '1' then
          state_v := (others => '0');
          state_v(1 downto 0) := state_to_slv(track_state);
          state_v(2) := code_lock;
          state_v(3) := carrier_lock;
          state_v(4) := nav_valid;
          state_v(5) := nav_bit;

          pkt_v(0)  := x"A5";
          pkt_v(1)  := x"5A";
          pkt_v(2)  := "00" & std_logic_vector(prn);
          pkt_v(3)  := state_v;
          pkt_v(4)  := std_logic_vector(sample_counter(31 downto 24));
          pkt_v(5)  := std_logic_vector(sample_counter(23 downto 16));
          pkt_v(6)  := std_logic_vector(sample_counter(15 downto 8));
          pkt_v(7)  := std_logic_vector(sample_counter(7 downto 0));
          pkt_v(8)  := std_logic_vector(doppler_hz(15 downto 8));
          pkt_v(9)  := std_logic_vector(doppler_hz(7 downto 0));
          pkt_v(10) := "00000" & std_logic_vector(code_phase(10 downto 8));
          pkt_v(11) := std_logic_vector(code_phase(7 downto 0));
          pkt_v(12) := std_logic_vector(prompt_i(15 downto 8));
          pkt_v(13) := std_logic_vector(prompt_i(7 downto 0));
          pkt_v(14) := std_logic_vector(prompt_q(7 downto 0));
          pkt_v(15) := (others => '0');

          checksum_v := (others => '0');
          for i in 0 to 14 loop
            checksum_v := checksum_v xor pkt_v(i);
          end loop;
          pkt_v(15) := checksum_v;
          pkt_r <= pkt_v;

          pkt_busy_r  <= '1';
          pkt_index_r <= 0;
        end if;

        if pkt_busy_r = '1' and tx_ready = '1' then
          tx_valid_r <= '1';
          tx_data_r  <= pkt_r(pkt_index_r);
          if pkt_index_r = 15 then
            tx_last_r   <= '1';
            pkt_busy_r  <= '0';
            pkt_index_r <= 0;
          else
            pkt_index_r <= pkt_index_r + 1;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
