library ieee;
use ieee.std_logic_1164.all;
use work.aux_package.all;
------------------------------------------------------------------------
-- Control.vhd
-- Control Unit for the SRMC 1-BUS Multi-Cycle CPU
--
-- Type   : FSM - Mealy Synchronized Output Machine
-- States : S_FETCH, S_DEC1, S_R_DEC2_EX, S_R_WB,
--          S_I_DEC2, S_I_AG, S_I_WB_MW
--
-- The FSM sequences through states to orchestrate the datapath:
--   FETCH     -> load IR from ProgMem, PC <- PC+1
--   DEC1      -> decode opcode; single-cycle instructions (mov / jmp /
--                jc / jnc / done) complete here; multi-cycle ops load
--                RF[rb] into REG-A and continue
--   R_DEC2_EX -> R-type: put RF[rc] on bus, run ALU, latch result in REG-C
--   R_WB      -> R-type: write REG-C result back to RF[ra]
--   I_DEC2    -> I-type: compute effective address = REG-A + sign_ext(imm)
--                result latched into REG-C master
--   I_AG      -> I-type: put address on bus (REG-C slave), latch into
--                DTCM address register
--   I_WB_MW   -> ld: DTCM_out -> RF[ra]
--                st: RF[ra]   -> DTCM
--
-- Port notes:
--   done_op  : decoded 'done' opcode flag from OPC decoder (status in)
--   done     : one-cycle pulse to testbench signalling program end (out)
--   andOp / orOp / xorOp : renamed because 'and','or','xor' are VHDL
--              reserved operators
--   RFaddr_rd (2-bit mux select): "00"=ra, "01"=rb, "10"=rc
--   RFaddr_wr (1-bit): always '0' -> datapath writes to IR[ra] field
------------------------------------------------------------------------
entity Control is
    port(
        clk      : in  std_logic;
        rst      : in  std_logic;   -- async reset -> S_FETCH
        ena      : in  std_logic;   -- '0' freezes FSM (CPU pause)

        -- ---- Status inputs from OPC decoder (datapath) ----
        st       : in  std_logic;   -- store instruction
        ld       : in  std_logic;   -- load instruction
        mov      : in  std_logic;   -- move immediate
        done_op  : in  std_logic;   -- done opcode (signals end of program)
        add      : in  std_logic;   -- add
        sub      : in  std_logic;   -- subtract
        jmp      : in  std_logic;   -- unconditional jump
        jc       : in  std_logic;   -- jump if carry set
        jnc      : in  std_logic;   -- jump if carry clear
        andOp    : in  std_logic;   -- bitwise AND
        orOp     : in  std_logic;   -- bitwise OR
        xorOp    : in  std_logic;   -- bitwise XOR
        Nflag    : in  std_logic;   -- ALU negative flag
        Zflag    : in  std_logic;   -- ALU zero flag
        Cflag    : in  std_logic;   -- ALU carry flag

        -- ---- Control outputs to datapath ----
        DTCM_wr      : out std_logic;                    -- DTCM write enable
        Cin          : out std_logic;                    -- REG-C master load
        Cout         : out std_logic;                    -- REG-C slave -> bus
        DTCM_addr_in : out std_logic;                    -- latch bus into DTCM addr reg
        DTCM_out     : out std_logic;                    -- DTCM data -> bus
        ALUFN        : out std_logic_vector(3 downto 0); -- ALU operation select
        Ain          : out std_logic;                    -- REG-A load from bus
        RFin         : out std_logic;                    -- RF write enable (to ra)
        RFout        : out std_logic;                    -- RF read -> bus
        RFaddr_rd    : out std_logic_vector(1 downto 0); -- RF read addr mux
        RFaddr_wr    : out std_logic;                    -- RF write addr select
        IRin         : out std_logic;                    -- IR load from bus
        PCin         : out std_logic;                    -- PC load enable
        PCsel        : out std_logic;                    -- PC mux: seq / branch
        Imm1_in      : out std_logic;                    -- sign_ext(IR[7:0]) -> bus
        Imm2_in      : out std_logic;                    -- sign_ext(IR[3:0]) -> bus
        done         : out std_logic                     -- pulse to testbench
    );
end Control;
------------------------------------------------------------------------
architecture FSM of Control is

    type state_t is (
        S_FETCH,       -- fetch instruction; PC <- PC+1
        S_DEC1,        -- decode; single-cycle ops complete here
        S_R_DEC2_EX,   -- R-type: execute ALU op, latch into REG-C
        S_R_WB,        -- R-type: write REG-C to RF[ra]
        S_I_DEC2,      -- I-type: compute EA = REG-A + imm, latch REG-C
        S_I_AG,        -- I-type: address generation -> DTCM addr reg
        S_I_WB_MW      -- I-type: ld writeback or st memory write
    );
i 
    signal current_state : state_t;
    signal next_state    : state_t;

begin

    --------------------------------------------------------------------
    -- Process 1 – State register
    -- Synchronous transition; asynchronous reset to S_FETCH.
    -- When ena='0' the state is frozen (CPU halted).
    --------------------------------------------------------------------
    state_reg: process(clk, rst)
    begin
        if rst = '1' then
            current_state <= S_FETCH;
        elsif rising_edge(clk) then
            if ena = '1' then
                current_state <= next_state;
            end if;
        end if;
    end process state_reg;

    --------------------------------------------------------------------
    -- Process 2 – Next-state and output logic (Mealy / combinational)
    -- All outputs default to '0' / inactive before the case statement.
    --------------------------------------------------------------------
    fsm_out: process(current_state,
                     st, ld, mov, done_op,
                     add, sub, jmp, jc, jnc, andOp, orOp, xorOp,
                     Nflag, Zflag, Cflag)
    begin
        -- ---- safe defaults (all inactive) ----
        DTCM_wr      <= '0';
        Cin          <= '0';
        Cout         <= '0';
        DTCM_addr_in <= '0';
        DTCM_out     <= '0';
        ALUFN        <= ALU_ADD;   -- default: add (don't-care when ALU not used)
        Ain          <= '0';
        RFin         <= '0';
        RFout        <= '0';
        RFaddr_rd    <= SEL_RB;    -- default: rb field
        RFaddr_wr    <= '0';       -- always write to ra (IR[11:8])
        IRin         <= '0';
        PCin         <= '0';
        PCsel        <= PC_SEQ;
        Imm1_in      <= '0';
        Imm2_in      <= '0';
        done         <= '0';
        next_state   <= S_FETCH;   -- safe default

        case current_state is

            -- --------------------------------------------------------
            -- FETCH
            -- ProgMem[PC] -> bus -> IR
            -- PC <- PC + 1  (PCsel = PC_SEQ)
            -- --------------------------------------------------------
            when S_FETCH =>
                IRin       <= '1';      -- latch instruction into IR
                PCin       <= '1';      -- update PC
                PCsel      <= PC_SEQ;   -- select PC+1 path
                next_state <= S_DEC1;

            -- --------------------------------------------------------
            -- DEC1 – Decode and dispatch
            -- Priority order: R-type -> I-type -> mov -> jmp/jc/jnc -> done
            --
            -- R-type / I-type (ld,st):
            --   RF[rb] -> bus -> REG-A  (load base / first operand)
            -- mov:
            --   sign_ext(IR[7:0]) -> bus -> RF[ra]
            -- jmp:
            --   PC <- (PC+1) + sign_ext(offset)
            -- jc / jnc:
            --   conditional branch on Cflag
            -- done_op:
            --   assert done pulse to testbench
            -- --------------------------------------------------------
            when S_DEC1 =>

                if (add='1' or sub='1' or andOp='1' or orOp='1' or xorOp='1') then
                    -- R-type: load RF[rb] into REG-A
                    RFout      <= '1';
                    RFaddr_rd  <= SEL_RB;
                    Ain        <= '1';
                    next_state <= S_R_DEC2_EX;

                elsif (ld='1' or st='1') then
                    -- I-type (ld / st): load RF[rb] into REG-A as address base
                    RFout      <= '1';
                    RFaddr_rd  <= SEL_RB;
                    Ain        <= '1';
                    next_state <= S_I_DEC2;

                elsif mov = '1' then
                    -- mov ra, imm8:  R[ra] <- sign_ext(IR[7:0])
                    Imm1_in    <= '1';  -- drive bus with sign_ext(IR[7:0])
                    RFin       <= '1';  -- RF[ra] <- bus
                    next_state <= S_FETCH;

                elsif jmp = '1' then
                    -- Unconditional branch: PC <- (PC+1) + offset
                    PCin       <= '1';
                    PCsel      <= PC_BRANCH;
                    next_state <= S_FETCH;

                elsif jc = '1' then
                    -- Branch if carry set
                    if Cflag = '1' then
                        PCin  <= '1';
                        PCsel <= PC_BRANCH;
                    end if;
                    next_state <= S_FETCH;

                elsif jnc = '1' then
                    -- Branch if carry clear
                    if Cflag = '0' then
                        PCin  <= '1';
                        PCsel <= PC_BRANCH;
                    end if;
                    next_state <= S_FETCH;

                elsif done_op = '1' then
                    -- Signal testbench to read DTCM content (one-cycle pulse)
                    done       <= '1';
                    next_state <= S_FETCH;

                else
                    -- NOP or unrecognised opcode: stall one cycle
                    next_state <= S_FETCH;
                end if;

            -- --------------------------------------------------------
            -- R_DEC2_EX
            -- RF[rc] -> bus (ALU operand B)
            -- ALU: A=REG-A, B=bus, function=ALUFN
            -- Result latched into REG-C master  (Cin=1)
            -- --------------------------------------------------------
            when S_R_DEC2_EX =>
                RFout     <= '1';
                RFaddr_rd <= SEL_RC;    -- select rc field

                -- Select ALU function from decoded opcode
                if    add   = '1' then ALUFN <= ALU_ADD;
                elsif sub   = '1' then ALUFN <= ALU_SUB;
                elsif andOp = '1' then ALUFN <= ALU_AND;
                elsif orOp  = '1' then ALUFN <= ALU_OR;
                elsif xorOp = '1' then ALUFN <= ALU_XOR;
                else                   ALUFN <= ALU_ADD;  -- safe default
                end if;

                Cin        <= '1';      -- latch ALU result into REG-C master
                next_state <= S_R_WB;

            -- --------------------------------------------------------
            -- R_WB
            -- REG-C slave -> bus -> RF[ra]
            -- --------------------------------------------------------
            when S_R_WB =>
                Cout       <= '1';      -- REG-C slave drives bus
                RFin       <= '1';      -- RF[ra] <- bus
                next_state <= S_FETCH;

            -- --------------------------------------------------------
            -- I_DEC2 – Effective address computation
            -- EA = REG-A + sign_ext(IR[3:0])
            -- Imm2 drives bus (ALU operand B), ALU adds, Cin latches result
            -- --------------------------------------------------------
            when S_I_DEC2 =>
                Imm2_in    <= '1';      -- sign_ext(IR[3:0]) drives bus
                ALUFN      <= ALU_ADD;  -- EA = REG-A + imm
                Cin        <= '1';      -- latch address into REG-C master
                next_state <= S_I_AG;

            -- --------------------------------------------------------
            -- I_AG – Address generation
            -- REG-C slave -> bus (effective address)
            -- DTCM address register <- bus
            -- --------------------------------------------------------
            when S_I_AG =>
                Cout         <= '1';    -- REG-C slave drives bus with EA
                DTCM_addr_in <= '1';    -- latch EA into DTCM address register
                next_state   <= S_I_WB_MW;

            -- --------------------------------------------------------
            -- I_WB_MW – Memory access / writeback
            -- ld: DTCM registered output -> bus -> RF[ra]
            -- st: RF[ra] -> bus -> DTCM[addr]
            -- --------------------------------------------------------
            when S_I_WB_MW =>
                if ld = '1' then
                    -- Load: DTCM data (registered output, valid now) -> RF[ra]
                    DTCM_out <= '1';    -- DTCM dataOut -> bus
                    RFin     <= '1';    -- RF[ra] <- bus

                elsif st = '1' then
                    -- Store: RF[ra] -> bus -> DTCM
                    RFout     <= '1';
                    RFaddr_rd <= SEL_RA;  -- read source register ra
                    DTCM_wr   <= '1';     -- write bus to DTCM
                end if;
                next_state <= S_FETCH;

            -- --------------------------------------------------------
            -- Safety net: undefined states return to FETCH
            -- --------------------------------------------------------
            when others =>
                next_state <= S_FETCH;

        end case;
    end process fsm_out;

end FSM;
