require File.join(File.dirname(__FILE__), '..', 'isa_def')
require File.join(File.dirname(__FILE__), 'assembly_file_parser')

class ConsoleSimulator
  def initialize(isa)
    @isa = isa
    @mem = MemoryStore.new
    #@simulator = Simulator.new @isa, @mem
  end

  def simulate_file(filename, verbose = false)
    results = AssemblyFileParser.new(@isa).parse_file(filename)

    init_mem results[:data_start], results[:data]
    simulate_instructions results[:instructions], verbose
  end

  # Sets memory starting at +start_addr+ to +data+. +data+ is an array of
  # integers that will be inserted into memory in little-endian byte order.
  # Memory is addressed in little-endian order.
  def init_mem(start_addr, data)
    @mem.write_from start_addr, data
  end

  # Sets the instruction data for future +simulate+ calls. Takes in an array of
  # bytes to write to memory.
  def instruction_data=(data)
    @mem.write_from @isa.instruction_start, data
    @num_instructions = data.length / @isa.instruction_width.bytes
  end

  # Use this in conjunction with #instruction_data= to simulate a set of encoded
  # instructions (`ops', in this API's parlance). To run a set of +Instruction+
  # objects, use #simulate_instructions.
  def simulate
    simulate_instructions parse_instructions
  end

  # Parses the instructions in memory (starting at @isa.instruction_start) into
  # Instruction objects, which are returned. Also sets the memory data via
  # +init_mem+.
  def parse_instructions
    instruction_end = @isa.instruction_start +
      @num_instructions * @isa.instruction_width.bytes

    instruction_data = @mem[instruction_end..@isa.instruction_start]

    instruction_data.each do |data|
      @isa.ops.select { |op| op.valid_op?(data) }
  end

  # Use this to simulate a set of actual +Instruction+ objects. Use #simulate in
  # conjunction with #instruction_data= to simulate a set of ops (or encoded
  # instructions). See the +InstructionParser+ class for a class that will parse
  # a set of +Instruction+ objects out of a set of strings.
  def simulate_instructions(instructions, verbose)
    assembled = instructions.collect { |instr| instr.to_i }

    pc = @isa.instruction_start - @isa.instruction_width.bytes

    self.instruction_data = assembled
    #simulator.run @isa.instruction_start, @isa.bus_width, @num_instructions

    pc = @isa.instruction_start
    i = 0
    count = 0
    gets
    puts "######################################################################"
    puts "# Starting simulation from PC = #{pc.to_hex_string}"
    puts "######################################################################"
    while i < instructions.length
      count += 1

      instr = instructions[i]

      regs_before = []
      @isa.regs.each_with_index { |reg, i| regs_before[i] = reg || 0 }

      print "PC=#{pc.to_hex_string} " +
        "[#{instr.to_i.to_binary_string(@isa.instruction_width)}] #{instr.to_s}"

      pc = instr.run pc, @mem
      changed = []

      regs_before.each_with_index { |reg, i| changed << i if reg != @isa.regs[i] }
      change_str = changed.collect do |reg|
        "R#{reg}: #{regs_before[reg].to_hex_string(32, false)} => " +
          "#{@isa.regs[reg].to_hex_string(32, false)}"
      end.join('; ')
      puts "\tChanged: (#{change_str})"

      if instr.terminating_instruction?
        puts "# Terminating instruction detected."
        break
      end

      i = (pc - @isa.instruction_start) / @isa.instruction_width.bytes
    end
    puts "# Simulated #{count} instructions in total"
    puts "Final PC = #{pc.to_hex_string}"
    puts "Final Register File State:"
    0.upto(2**BinaryRepresentation.var_widths['reg']-1) do |reg|
      val = @isa.regs[reg]
      puts "# R[#{reg}] = #{val.to_hex_string(32, false)} (#{val})"
    end
  end
end

class MemoryStore
  def initialize
    @mem = {} # make this baby sparse
  end

  # If passed a range, this method will return the data in the appropriate byte
  # order. For example, if the range is 3..0, then the returned bytes will be
  # [byte3, byte2, byte1, byte0]. If the range is 0..3, on the other hand, then
  # the returned bytes will be [byte0, byte1, byte2, byte3].
  def [](loc)
    if loc.is_a?(Fixnum)
      puts "MEM[#{loc.to_hex_string}] => #{(@mem[loc]||0).to_hex_string(8)}"
      @mem[loc] || 0
    elsif loc.is_a?(Range)
      # We reverse the range if needed.
      range = loc.first > loc.last ? loc.last..loc.first : addr
      result = range.collect { |byte| @mem[byte] }

      byte_num = -1
      result.inject(0) do |num, byte|
        byte_num += 1
        num | (byte << (byte_num*8))
      end
    end
  end

  def []=(addr, val)
    if addr.is_a?(Fixnum)
      @mem[addr] = val
    elsif addr.is_a?(Range)
      # We reverse the range if needed.
      range = addr.first > addr.last ? addr.last..addr.first : addr

      if val.is_a?(Fixnum) || val.is_a?(Bignum)
        # assign in little-endian form into range
        bytes = val.extract_bytes
        range.each do |part|
          @mem[part] = bytes[part - range.first]
        end
      else
        bytes = val.extract_bytes.reverse # the values should also be MSB..LSB
        range.each do |part|
          @mem[part] = bytes[part - range.first]
        end
      end
    end
  end

  # Writes +data+ starting at +start_addr+. +data+ is expected to be a set of
  # Fixnums, each of which will be re-ordered into the appropriate byte order
  # before writing to memory.
  def write_from(start_addr, data)
    cur_addr = start_addr
    data.each do |num|
      self[cur_addr+3..cur_addr] = num
      cur_addr += 4
    end
  end
end

