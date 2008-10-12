require File.join(File.dirname(__FILE__), 'lib', 'isa')

@isa3220 = isa do
  instruction_width 16.bits
  data_width 32.bits
  byte_order :little_endian
  instruction_start 0x40000

  opcode_width 4.bits
  reg_width 4.bits
  ext_width 4.bits
  zz_width 2.bits

  terminating_instruction 0x4FFE

  ground_register 0, :as => :zero
  reserve_register 14, :as => :jump
  reserve_register 15, :as => :stack

  register_args 'dest', 'src', 'addrsrc'
  destination_register 'dest'

  reg_formats 'R:val', '$:val', 'r:val'

  op_type 'arith', :takes    => ':op :dest, :src',
                   :produces => ':opcode:dest:src:ext',
                   :with_opcode => 0 do
    op('add',  :with_ext => 0)  { regs[dest] + regs[src] }
    op('sub',  :with_ext => 1)  { regs[dest] - regs[src] }
    op('mul',  :with_ext => 2)  { regs[dest] * regs[src] }
    op('neg',  :with_ext => 3)  { - regs[src] }
    op('shl',  :with_ext => 4)  { regs[dest] << regs[src] }
    op('shrl', :with_ext => 5)  { regs[dest].shift_right regs[src] }
    op('shra', :with_ext => 6)  { regs[dest] >> regs[src] }
    op('not',  :with_ext => 7)  { ~ regs[src] }
    op('and',  :with_ext => 8)  { regs[dest] & regs[src] }
    op('or',   :with_ext => 9)  { regs[dest] | regs[src] }
    op('cmpz', :with_ext => 10) { regs[src].zero? ? 1 : 0 }
    op('mov',  :with_ext => 11) { regs[src] }
    op('xor',  :with_ext => 12) { regs[dest] ^ regs[src] }
    op('sxb0', :with_ext => 13) { regs[src].sign_extend :from => 7 }
    op('sxb1', :with_ext => 14) { regs[src].sign_extend(:from => 15) }
    op('sxb2', :with_ext => 15) { regs[src].sign_extend :from => 23 }
  end

  op_type 'arith_with_immediate', :takes    => ':op :dest, :imm',
                                  :produces => ':opcode:dest:imm:ext',
                                  :with_opcode => 1 do
    op('addi',  :with_ext => 0)  { regs[dest] + imm }
    op('subi',  :with_ext => 1)  { regs[dest] - imm }
    op('muli',  :with_ext => 2)  { regs[dest] * imm }
    op('negi',  :with_ext => 3)  { - imm }
    op('shli',  :with_ext => 4)  { regs[dest] << imm }
    op('shrli', :with_ext => 5)  { regs[dest].shift_right imm }
    op('shrai', :with_ext => 6)  { regs[dest] >> imm }
    op('noti',  :with_ext => 7)  { ~ imm }
    op('andi',  :with_ext => 8)  { regs[dest] & imm }
    op('ori',   :with_ext => 9)  { regs[dest] | imm }
    op('xori',  :with_ext => 12) { regs[dest] ^ imm }
  end

  op_type 'conditional_branch', :takes    => ':op :imm',
                                :produces => ':opcode:imm' do
    op('beqz', :with_opcode => 4) do
      regs[jump].zero? ? self.pc += imm : pc
    end
    op('bgez', :with_opcode => 5) do
      (regs[jump] >= 0) ? self.pc += imm : pc
    end
    op('bgtz', :with_opcode => 6) do
      (regs[jump] > 0) ? self.pc += imm : pc
    end

    mnemonic('blez') do
      insert_op 'neg', :dest => jump, :src => jump
      insert_op 'bgez', :imm => imm
    end

    mnemonic('bltz') do
      insert_op 'neg', :dest => jump, :src => jump
      insert_op 'bgtz', :imm => imm
    end

    mnemonic('bnez') do
      insert_op 'cmpz', :dest => jump, :src => jump
      insert_op 'beqz', :imm => imm
    end

    mnemonic('br') do
      insert_op 'add', :dest => jump, :src => zero # guarantee jump with beqz
      insert_op 'beqz', :imm => imm
    end
  end

  op 'jump', :takes    => ':op :addrsrc',
             :produces => ':opcode:addrsrc',
             :with_opcode => 7,
             :aliases => %w{call return} do
    temp = pc + 2
    self.pc = regs[addrsrc]
    regs[14] = temp
  end

  mnemonic 'jump', :takes    => ':op :imm',
                   :aliases => %w{call return} do
    insert_op 'mimm', :dest => jump, :imm => pc + imm
    insert_op 'jump', :addrsrc => jump
  end

  op_type 'load', :takes    => ':op :dest, :src',
                  :produces => ':opcode:dest:src00:zz',
                  :with_opcode => 8 do
    op('ld.b', :with_zz => 0) { mem[regs[src]] }
    op('ld.w', :with_zz => 1) { mem[regs[src]+1..regs[src]] }
    op('ld.d', :with_zz => 2) { mem[regs[src]+3..regs[src]] }
  end

  op_type 'store', :takes    => ':op :src, :addrsrc',
                   :produces => ':opcode:src:addrsrc00:zz',
                   :with_opcode => 9 do
    op('st.b', :with_zz => 0) { mem[regs[addrsrc]] = regs[src][7..0] }
    op('st.w', :with_zz => 1) do
      mem[regs[addrsrc]+1..regs[addrsrc]] = regs[src][15..0]
    end
    op('st.d', :with_zz => 2) do
      mem[regs[addrsrc]+3..regs[addrsrc]] = regs[src][31..0]
    end
  end

  op_type 'load with stack pointer', :takes    => ':op :dest, :offset',
                                     :produces => ':opcode:dest:offset:zz',
                                     :with_opcode => 10 do
    before(:all) { addr = regs[stack + offset.pad] }

    op('lds.b', :with_zz => 0) { mem[addr].pad }
    op('lds.w', :with_zz => 1) { mem[addr+1..addr].pad }
    op('lds.d', :with_zz => 2) { mem[addr+3..addr] }
  end

  op_type 'store with stack pointer', :takes    => ':op :src, :offset',
                                      :produces => ':opcode:src:offset:zz',
                                      :with_opcode => 11 do
    before(:all) { addr = regs[stack + offset.pad] }

    op('sts.b', :with_zz => 0) { mem[addr] = regs[src][7..0] }
    op('sts.w', :with_zz => 1) { mem[addr+1..addr] = regs[src][15..0] }
    op('sts.d', :with_zz => 2) { mem[addr+3..addr] = regs[src] }
  end

  op_type 'move immediate to byte', :takes    => ':op :dest, :imm',
                                    :produces => ':opcode:dest:imm' do
    op('mib0', :with_opcode => 12) { regs[dest][31..8] | imm }
    op('mib1', :with_opcode => 13) do
      regs[dest][31..16] | (imm << 8) | regs[dest][7..0]
    end
    op('mib2', :with_opcode => 14) do
      regs[dest][31..24] | (imm << 16) | regs[dest][15..0]
    end
    op('mib3', :with_opcode => 15) { (imm << 24) | regs[dest][23..0] }

    mnemonic('mimm') do
      insert_op 'mib0', :dest => dest, :imm => imm[7..0]
      insert_op 'mib1', :dest => dest, :imm => imm[15..8]
      insert_op 'mib2', :dest => dest, :imm => imm[23..16]
      insert_op 'mib3', :dest => dest, :imm => imm[31..24]
    end
  end
end

