require File.join(File.dirname(__FILE__), 'string_extensions')
require File.join(File.dirname(__FILE__), 'fixnum_extensions')
require File.join(File.dirname(__FILE__), 'array_extensions')
require File.join(File.dirname(__FILE__), 'hash_extensions')

class Op
  attr_reader :assembly, :binary, :name, :blocks, :isa

  class <<self
    def register_args(*args)
      args.empty? ? @register_args : @register_args = args
    end

    def destination_register(reg_num = nil)
      reg_num.nil? ? @destination_register : @destination_register = reg_num
    end
  end

  # Creates a new ISA operation with the given name, options, and block.
  def initialize(isa, name, options, block)
    @isa = isa
    @name = name
    @blocks = options[:before] + [block]

    @assembly = AssemblyRepresentation.new self, options[:takes], options[:static]
    @binary = BinaryRepresentation.new options[:produces]

    options.each do |key, value|
      match = key.to_s.match(/^with_(.*)$/)

      unless match.nil?
        fixed_var = match[1]
        fixed_val = value
        @binary.fix_var fixed_var, value.to_i
      end
    end
  end

  def valid_instruction?(instr)
    @assembly.valid?(instr)
  end

  def valid_op?(num_or_string)
    op = num_or_string.is_a?(Fixnum) ? num_or_string :
                                       NumberExtensions.from_binary_string(num_or_string)

    @binary.valid?(op)
  end

  # Parses the given assembly instruction +string+ into an Instruction object.
  # Also takes in +extra_vars+ for the given instruction (particularly important
  # is the PC for branch-related mnemonics).
  def parse_instruction(string, extra_vars = {})
    instruction_for @assembly.parse(string).merge(extra_vars)
  end

  # Returns an instruction for this op with its variables set to +vars+.
  def instruction_for(vars)
    Instruction.new self, vars
  end

  # Parses the given assembled instruction +num_or_string+, which should either
  # be a direct data value or a binary String, into an Instruction.
  def parse_op(num_or_string)
    op = num_or_string.is_a?(Fixnum) ? num_or_string :
                                       NumberExtensions.from_binary_string(num_or_string)

    Instruction.new self, @binary.disassemble(op)
  end

  protected
    attr_writer :assembly, :binary
end

class Mnemonic < Op
  def initialize(isa, name, options, block)
    options[:produces] ||= ''

    super

    @block = @blocks.pop
  end

  # Returns all instructions this mnemonic expands to with their variables set
  # to +vars+.
  def instruction_for(vars)
    instr = Instruction.new self, vars

    (@instructions ||= []).clear
    @vars = instr.vars
    instance_eval &@block # the before/after and such are left to others

    instr.send :instance_variable_set, :@instructions, @instructions
    class <<instr
      def instructions
        @instructions
      end
    end

    instr
  end


  private
    def insert_op(op_name, vars = {})
      instr = @isa.op_for(op_name).instruction_for(@vars.merge(vars))

      instrs = nil
      begin
        instrs = instr.instructions
      rescue NoMethodError
        instrs = [instr]
      end

      @instructions += instrs
    end

    def method_missing(meth, *args)
      if args.empty? && @vars.has_key?(meth.to_s)
        @vars[meth.to_s]
      else
        super
      end
    end
end

class Instruction
  attr_reader :vars

  def initialize(op, vars)
    @op = op
    @vars = vars
    @vars.stringify_keys!

    @vars['op'] = @op.name
  end

  # Runs the instruction with the given program counter and memory store.
  # Returns the next instruction address (pc).
  def run(pc, mem)
    @vars['pc'] = pc
    @vars['mem'] = mem

    val = @op.blocks.collect do |block|
      inject_vars block.binding
      block.call
    end.last

    if @vars.keys.any? { |var| var.to_s == Op.destination_register }
      @op.isa.regs[@vars[Op.destination_register]] = val.swap_endianness
    end

    @vars['pc'] != pc ? @vars['pc'] : pc + 2
  end

  def to_s
    @op.assembly.vars_to_assembly_string @vars
  end

  def to_i
    @op.binary.assemble @vars
  end

  def to_binary
    to_i.to_binary_string(BinaryRepresentation.instr_width)
  end

  def to_hex
    to_i.to_hex_string(BinaryRepresentation.instr_width)
  end

  def terminating_instruction?
    to_i == @op.isa.terminating_instruction
  end

  private
    # Injects @vars into the given +binding+. Note: this is serious Ruby voodoo.
    # Super-serious.
    #
    # We define a method_missing for looking up these variables. The reason we
    # do this is because when the blocks are initially parsed, these variables
    # do not exist as local variables, so the references are parsed as method
    # vcalls.  In order to make those references work, we need to go through the
    # method-handling functionality, not the variable-handling one.
    def inject_vars(binding)
      metaclass = eval('class <<self;self;end', binding)

      metaclass.class_eval do
        class <<self; attr_accessor :vars; end

        def method_missing(meth, *args)
          vars = (class <<self;self;end).vars
          if args.empty? && vars.has_key?(meth.to_s)
            vars[meth.to_s]
          elsif vars.has_key?(meth.to_s[0..-2]) and meth.to_s.ends_with?('=')
            vars[meth.to_s[0..-2]] = args.first
          else
            super
          end
        end
      end

      metaclass.vars = @vars
    end
end

# Handles the assembly-level representation of an operation. In charge of
# converting an assembler string into an Instruction.
class AssemblyRepresentation
  class <<self
    def reg_formats(*fmts)
      @reg_out_fmt = fmts.first.match(/^([^:]+)?(:val)([^:]+)?$/).captures
      @reg_out_fmt.compact!

      @basic_format = []
      format_rx = fmts.collect do |fmt|
        extracted = fmt.match(/^([^:]+)?:val([^:]+)?$/).captures
        extracted.collect! { |str| str ? Regexp.escape(str) : str }

        @basic_format << "#{extracted.first}\\d+#{extracted.last}"
        "#{extracted.first}(\\d+)#{extracted.last}"
      end.join("|")
      @basic_format = @basic_format.join('|')

      @format_rx = Regexp.new(format_rx, true)
    end

    def valid_reg?(reg)
      @format_rx =~ reg
    end

    def register_from(reg)
      @format_rx.match(reg).captures.compact[0].to_i
    end

    def format_register(reg_num)
      @reg_out_fmt.collect { |part| part == ':val' ? reg_num.to_s : part }.join
    end

    def register_format
      @basic_format
    end
  end

  def initialize(op, assembly_format, static_vars)
    @op = op
    @format = parse_format(assembly_format)
    @static_vars = static_vars || {}

    # FIXME clean up
    @capture_vars = []
    next_pos = 1
    @matcher_rx = @format.inject('^') do |matcher_rx, cur_part|
      if cur_part == ':op'
        matcher_rx << Regexp.escape(@op.name)
      elsif cur_part.starts_with?(':')
        if Op.register_args.include?(cur_part[1..-1])
          matcher_rx << "(#{AssemblyRepresentation.register_format})"
        elsif @format[next_pos].nil?
          matcher_rx << "(-?(?:0x)?[A-F0-9]+)"
        else
          matcher_rx << "([^#{@format[next_pos][0..0]}]+)"
        end
        @capture_vars << cur_part[1..-1]
      else
        matcher_rx << cur_part
      end

      next_pos += 1
      matcher_rx
    end
    @matcher_rx << '$' unless @matcher_rx.ends_with?('$')

    @matcher_rx = Regexp.new(@matcher_rx, true) # convert to regex
  end

  def valid?(string)
    @matcher_rx =~ string
  end

  def parse(string)
    matches = @matcher_rx.match(string)

    vars = {}
    pos = 0
    matches.captures.each do |var_val|
      var = @capture_vars[pos]

      if Op.register_args.include?(var)
        vars[var] = self.class.register_from(var_val)
      elsif match = var_val.match(/^(-)?(0x)?([A-F0-9]+)$/i)
        val = "#{match[1]}#{match[3]}"
        vars[var] = match[2].nil? ? val.to_i : val.to_i(16)
      else
        vars[var] = var_val
      end

      pos += 1
    end

    @static_vars.merge(vars)
  end

  # This method takes in a set of variables that have been pre-set and returns
  # the assembly instruction that corresponds to those variables taking into
  # account this assembly representation's format.
  def vars_to_assembly_string(vars)
    @format.collect do |cur_part|
      if cur_part.starts_with?(':')
        var = cur_part[1..-1]

        raise "Unset variable `#{var}' prevents disassembly." if vars[var].nil?

        if Op.register_args.include?(var)
          AssemblyRepresentation.format_register(vars[var])
        else
          vars[var]
        end
      else
        cur_part
      end
    end.join
  end

  private
    def parse_format(format)
      format.scan(/([^:]+)?(:[a-zA-Z0-9]+)([^:]+)?/).flatten.compact
    end
end

class BinaryRepresentation
  class <<self
    # Sets the instr_width if +width+ is passed; otherwise, returns the current
    # instr_width.
    def instr_width(width = nil)
      width ? @instr_width = width : @instr_width
    end

    def method_missing(method, *args)
      meth_name = method.to_s
      if meth_name.ends_with?('_width')
        var_widths[meth_name[0..-7]] = args.first
      else
        super
      end
    end

    def var_widths
      @var_widths ||= {}
    end
  end

  def initialize(format)
    format = parse_format(format)
    @var_order = format.collect do |var|
      var =~ /[0-9]+/ ? var : var[1..-1] # drop the start :
    end
  end

  def fix_var(var, value)
    vars[var] = value
  end

  # Assembles the instruction represented by this BinaryRepresentation given a
  # set of variables that are set for it. If not all variables are set,
  # an exception will be raised. If it is impossible to determine the full
  # length of the binary representation, an exception will also be raised.
  def assemble(extra_vars)
    extra_vars.merge! vars

    i = -1
    binary_string = @var_order.collect do |var|
      i += 1

      if var =~ /[0-1]+/
        var.to_i.to_binary_string(var_widths[i])
      else
        extra_vars[var].to_binary_string(var_widths[i])
      end
    end.join

    NumberExtensions.from_binary_string(binary_string)
  end

  # Takes +num+, which is a Fixnum or Bignum of size +instr_width+, and
  # disassembles it into its component variables.
  def disassemble(num)
    klass = self.class
    op = num.to_binary_string(klass.instr_width)

    vars = {}
    op_parts = binary_recognizer.match(op).captures
    op_parts.each_index { |i| vars[@var_order[i]] = op_parts[i].to_i(2) }

    vars
  end

  private
    def binary_recognizer
      return @binary_recognizer if @binary_recognizer

      i = -1
      @binary_recognizer = var_widths.collect do |width|
        i += 1
        existing_val = vars[@var_order[i]]
        if existing_val
          "(#{existing_val.to_binary_string(width)})"
        else
          "(\\d{#{width}})"
        end
      end.join
      @binary_recognizer = Regexp.new("^#{binary_recognizer}$", true)
    end

    def parse_format(format)
      format.scan(/(:[a-zA-Z]+|[0-1]+)/).flatten.compact
    end

    def vars
      @vars ||= {}
    end

    def var_widths
      klass = self.class
      widths = klass.var_widths

      ordered_widths = @var_order.collect do |var, value|
        if var =~ /[0-1]+/
          var.length
        elsif Op.register_args.include?(var)
          widths['reg']
        else
          widths[var]
        end
      end

      unknowns = ordered_widths.count(nil)
      if unknowns > 1
        raise 'More than one unspecified width for binary assembly.'
      elsif unknowns == 1
        # Fill in the remaining width.
        total = ordered_widths.inject(0) { |sum, width| sum += width ? width : 0 }

        remaining = klass.instr_width - total
        ordered_widths.each_index do |i|
          ordered_widths[i] = remaining if ordered_widths[i].nil?
        end
      end

      ordered_widths
    end
end

