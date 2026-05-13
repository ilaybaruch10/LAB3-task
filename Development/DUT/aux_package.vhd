library ieee;
use ieee.std_logic_1164.all;
------------------------------------------------------------------------
-- aux_package.vhd
-- Shared constants for the SRMC Multi-Cycle CPU (Control + Datapath)
------------------------------------------------------------------------
package aux_package is

    -- ----------------------------------------------------------------
    -- ALU Function select codes (ALUFN, 4-bit)
    -- ----------------------------------------------------------------
    constant ALU_ADD : std_logic_vector(3 downto 0) := "0000";
    constant ALU_SUB : std_logic_vector(3 downto 0) := "0001";
    constant ALU_AND : std_logic_vector(3 downto 0) := "0010";
    constant ALU_OR  : std_logic_vector(3 downto 0) := "0011";
    constant ALU_XOR : std_logic_vector(3 downto 0) := "0100";

    -- ----------------------------------------------------------------
    -- RF read-address mux select codes (RFaddr_rd, 2-bit)
    --   SEL_RA : read IR[11:8]  (ra field - used in st data read)
    --   SEL_RB : read IR[7:4]   (rb field - base register)
    --   SEL_RC : read IR[3:0]   (rc field - 2nd ALU operand in R-type)
    -- ----------------------------------------------------------------
    constant SEL_RA : std_logic_vector(1 downto 0) := "00";
    constant SEL_RB : std_logic_vector(1 downto 0) := "01";
    constant SEL_RC : std_logic_vector(1 downto 0) := "10";

    -- ----------------------------------------------------------------
    -- PCsel mux codes
    --   PC_SEQ    : PC <- PC + 1                        (sequential)
    --   PC_BRANCH : PC <- (PC+1) + sign_ext(offset)    (branch taken)
    -- ----------------------------------------------------------------
    constant PC_SEQ    : std_logic := '0';
    constant PC_BRANCH : std_logic := '1';

    -- ----------------------------------------------------------------
    -- CPU parameters
    -- ----------------------------------------------------------------
    constant DWIDTH : integer := 16;   -- data / bus width (bits)
    constant AWIDTH : integer := 6;    -- memory address width (64 words)
    constant RFAW   : integer := 4;    -- register file address width (16 regs)

end aux_package;
