require File.join(File.dirname(__FILE__), 'op')

class ISA
  attr_reader :ops, :regs, :data_width

  def initialize(&block)
    @type_group = nil
    @type_group_opts = nil
    @ops = []
    @static_vars = {}
    @regs = RegisterFile.new
    @type_group_before = []
    @general_before = []
    @instruction_start = 0

    instance_eval &block unless block.nil?
  end

  def add_op(op_name, options = {}, &block)
    add_op_type Op, op_name, options, &block
  end
  alias_method :op, :add_op

  def add_mnemonic(mnemonic_name, options = {}, &block)
    add_op_type Mnemonic, mnemonic_name, options, &block
  end
  alias_method :mnemonic, :add_mnemonic

  def add_op_type(type, name, options = {}, &block)
    options = options.reverse_merge @type_group_opts if @type_group_opts
    options[:type_group] = @type_group

    options[:before] = @general_before + @type_group_before

    ops << type.new(self, name, options.merge(:static => @static_vars), block)

    if options[:aliases]
      options[:aliases].each do |equiv|
        ops << type.new(self, equiv, options.merge(:static => @static_vars), block)
      end
    end
  end

  def op_type(type_label, options = {}, &block)
    start_op_type type_label, options

    raise ExpectedBlockError.new if block.nil?
    instance_eval &block

    end_op_type
  end

  def before(moment, &block) # +when+ is for readability; we ignore it
    if @type_group
      @type_group_before << block
    else
      @general_before << block
    end
  end

  def start_op_type(type_label, options = {}, &block)
    @type_group = type_label
    @type_group_opts = options
  end

  def end_op_type
    @type_group = nil
    @type_group_opts = nil
    @type_group_before.clear
  end

  def byte_order(order)
    # no-op, for now
  end

  def instruction_start(mem_location = nil)
    mem_location.nil? ? @instruction_start : @instruction_start = mem_location
  end

  def instruction_width(width = nil)
    width.nil? ? BinaryRepresentation.instr_width :
                 BinaryRepresentation.instr_width(width)
  end

  def data_width(width = nil)
    if width.nil?
      @data_width
    else
      @regs.data_width = @data_width = width
    end
  end

  def reg_formats(*fmts)
    AssemblyRepresentation.reg_formats *fmts
  end

  def method_missing(method, *args)
    meth_name = method.to_s
    if meth_name.ends_with?('_width')
      BinaryRepresentation.send method, *args

      regs.num_regs = 2 ** args.first if method == :reg_width
    else
      super
    end
  end

  def ground_register(num, opts = {})
    regs[num] = 0
    regs.make_immutable num

    @static_vars[opts[:as].to_s] = num
  end

  def reserve_register(num, opts = {})
    regs.make_reserved num

    @static_vars[opts[:as].to_s] = num
  end

  def register_args(*args)
    Op.register_args(*args)
  end

  def destination_register(reg_num)
    Op.destination_register(reg_num)
  end

  def op_for(op_name)
    ops.detect { |op| op.name == op_name }
  end

  def terminating_instruction(instr = nil)
    instr.nil? ? @terminating_instruction : @terminating_instruction = instr
  end
end

class ExpectedBlockError < RuntimeError
  def initialize
    super 'Block expected.'
  end
end

def isa(&block)
  ISA.new &block
end

class RegisterFile
  attr_accessor :num_regs, :data_width

  def initialize
    @regs = []
    @immutable_regs = []
    @reserved_regs = []
  end

  def [](idx)
    raise "Register #{idx} out of range." if idx > num_regs

    @regs[idx] ||= 0
  end

  def []=(idx, val)
    raise "Register #{idx} out of range." if idx > num_regs

    if immutable_regs.include?(idx)
      warn 'Immutable register modified, value unchanged.'
      return
    elsif reserved_regs.include?(idx)
      warn 'Reserved register modified, value updated.'
    end

    @regs[idx] = val.swap_endianness.restrict_to_width(data_width)
  end

  def warn(msg)
  end

  def make_reserved(reg)
    reserved_regs << reg
  end

  def make_immutable(reg)
    immutable_regs << reg
  end

  def method_missing(method, *args, &block)
    # Proxy through to array for things like collect.
    @regs.send(method, *args, &block)
  end

  private
    attr_reader :immutable_regs, :reserved_regs
end

