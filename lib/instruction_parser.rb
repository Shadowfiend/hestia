class InstructionParser
  attr_reader :instructions

  def initialize(isa)
    @isa = isa
    @instructions = []
  end

  # Adds an Instruction object corresponding to the given +instruction_str+,
  # given the provided +pc+. Returns an updated pc for the last instruction.
  # Typically, this updated pc will be the same as the incoming pc, but
  # mnemonics expand into multiple instructions, which changes this.
  def add_instruction(instruction_str, pc)
    instructions = parse(instruction_str, pc)
    instructions.each { |instr| @instructions << instr }

    pc + instructions.length * @isa.instruction_width.bytes
  end
  alias_method :<<, :add_instruction

  def clear
    @instructions.clear
  end

  private
    # Returns an array of parsed instructions -- one or more.
    def parse(instr, pc)
      valid_ops = @isa.ops.select { |op| op.valid_instruction?(instr) }

      raise "Ambiguous instruction `#{instr}'." if valid_ops.length > 1
      raise "Unknown instruction `#{instr}'." if valid_ops.length == 0

      instr = valid_ops.first.parse_instruction instr, :pc => pc

      # Expand mnemonics.
      begin
        instr.instructions
      rescue NoMethodError
        [instr]
      end
    end
end

