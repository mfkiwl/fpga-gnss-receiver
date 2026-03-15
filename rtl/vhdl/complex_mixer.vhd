library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity complex_mixer is
  port (
    i_in   : in  signed(15 downto 0);
    q_in   : in  signed(15 downto 0);
    lo_i   : in  signed(15 downto 0);
    lo_q   : in  signed(15 downto 0);
    i_out  : out signed(15 downto 0);
    q_out  : out signed(15 downto 0)
  );
end entity;

architecture rtl of complex_mixer is
  signal ii : signed(63 downto 0);
  signal qq : signed(63 downto 0);
  signal iq : signed(63 downto 0);
  signal qi : signed(63 downto 0);
begin
  ii <= resize(i_in, 32) * resize(lo_i, 32);
  qq <= resize(q_in, 32) * resize(lo_q, 32);
  iq <= resize(i_in, 32) * resize(lo_q, 32);
  qi <= resize(q_in, 32) * resize(lo_i, 32);

  i_out <= resize(shift_right(ii - qq, 15), 16);
  q_out <= resize(shift_right(iq + qi, 15), 16);
end architecture;
