class Dissassembler
  def self.disassemble_file(filename)
  end

  def initialize(isa)
    @isa = isa
  end

  # Disassembles the given +ops+ into op strings. Returns an array of
  # operations. Each +op+ should be a 2-tuple with [upper_byte, lower_byte].
  def disassemble(ops)
    ops.collect do |op|
      num = 0
      num
    end
  end
end

