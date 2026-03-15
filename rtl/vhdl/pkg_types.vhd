library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package pkg_types is
  subtype byte_t is std_logic_vector(7 downto 0);
  subtype idx_t is integer range 0 to 3;
end package;
