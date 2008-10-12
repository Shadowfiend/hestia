module NumberExtensions
  class <<self
    def from_binary_string(str)
      num = 0

      bit = 0
      str.reverse.each_byte do |char|
        val = char - '0'[0]

        num = num | (val << bit)
        bit += 1
      end

      num
    end
  end

  def to_binary_string(width = 32)
    ("%0#{width}b" % self)[-width..-1]
  end

  def to_hex_string(width = 32, signed = true)
    if signed
      if self < 0
        "-0x" + ("%0#{width}x" % -self)[-(width/4.0).ceil..-1]
      else
        "0x" + ("%0#{width}x" % self)[-(width/4.0).ceil..-1]
      end
    else
      "0x" + ("%0#{width}x" % self)[-(width/4.0).ceil..-1]
    end
  end

  def bits
    self
  end

  def bytes
    self / 8
  end
  alias_method :byte, :bytes

  def extract_bytes(endianness = :little_endian)
    num_bytes = self.size

    bytes = (0...num_bytes).collect { |byte| ((self >> (byte*8)) & 0xFF) }

    endianness == :little_endian ? bytes : bytes.reverse
  end

  # Array operator [].
  def new_arr_op(range)
    if range.is_a?(Range)
      range = (range.last..range.first) # reverse it
      range.inject(0) { |res, bit| res |= (self[bit] << bit) } >> range.first
    else
      orig_arr_op(range)
    end
  end

  def shift_right(amount)
    val = self >> amount

    # We want to clear the top bits to turn the arithmetic shift right into a
    # logical shift right.
    bit_size = size * 8
    amount = [amount, bit_size].min
    mask = ~(2**bit_size - 2**(bit_size-amount))
    val & mask
  end

  def sign_extend(opts = {})
    from = opts.delete(:from)

    bit_size = size * 8
    mask = 2**bit_size - 2**from

    self[from] == 1 ? self | mask : self & ~mask
  end

  def swap_endianness
    bytes = self.extract_bytes
    cur_byte = 0
    total_bytes = bytes.size
    bytes.inject(0) do |result, byte|
      result |= (byte << ((total_bytes-cur_byte-1)*8))
      cur_byte += 1
      result
    end
  end

  def restrict_to_width(width)
    bits = size*8
    if bits >= width
      mask = ~(2**bits-2**width)
      val = self & mask

      val = val.sign_extend(:from => width - 1)

      # Bignums behave as if they have infinite ones to the left, we need them
      # to... Not.
      bignum_avoidance_mask = 2**bits-1

      val[bits-1] == 1 ? -((~val+1) & bignum_avoidance_mask) : val
    else
      self
    end
  end

  def self.included(other)
    other.class_eval do
      alias_method :orig_arr_op, :[]
      alias_method :[], :new_arr_op
    end
  end
end

class Fixnum; include NumberExtensions; end
class Bignum; include NumberExtensions; end

