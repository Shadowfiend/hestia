require File.join(File.dirname(__FILE__), 'instruction_parser')

class AssemblyFileParser
  def initialize(isa)
    @isa = isa
    @instruction_parser = InstructionParser.new isa
  end

  # Parses the file given by +filename+. Returns a hash with the following
  # sections:
  #  [+data_start+] The start of the data section.
  #  [+data+] An array of values of the data section (integers).
  #  [+instructions+] A set of Instruction objects, in order.
  #
  # Note that mnemonics are eliminated at this point, as well, so the
  # +instructions+ index of the hash is a list of only basic instructions with
  # resolved labels.
  def parse_file(filename)
    labels, lines = nil, nil

    file = File.open(filename, 'r+') do |file|
      labels, lines = preprocess_file file
    end

    remaining_lines, data_start, data = read_data_section_from lines
    read_instructions_from remaining_lines, labels

    { :data_start => data_start, :data => data,
      :instructions => @instruction_parser.instructions }
  end

  private
    def read_data_section_from(lines)
      done_with_data = false
      data_start = nil
      data = []

      remaining_lines = lines.select do |line|
        done_with_data = true if line =~ /^.text$/

        unless done_with_data
          # Split into form [param, arg0, arg1, ...]
          line = line.scan(/[A-Za-z0-9.]+/)

          if line[0] == '.data'
            data_start = line[1].to_i(16)
          elsif data_start.is_a?(Integer)
            line.collect! { |num| num.to_i(16) }
            line.each { |value| data << value }
          end
        end

        done_with_data
      end

      # We drop the first item from remaining_lines, as it is .text.
      [remaining_lines[1..-1], data_start, data]
    end

    def read_instructions_from(lines, labels)
      @instruction_parser.clear

      pc = @isa.instruction_start
      lines.each do |line|
        line.gsub!(/\b(#{labels.keys.join('|')})\b/) do |label|
          val = (labels[$1] - pc).to_hex_string
          puts "Branch to label #{$1} at #{labels[$1].to_hex_string} from #{pc.to_hex_string} calculated as #{val}."
          val
        end

        updated_pc = @instruction_parser.add_instruction line, pc

        pc += @isa.instruction_width.bytes
      end
    end

    def preprocess_file(file)
      labels = {}
      in_instructions = false
      pc = @isa.instruction_start - @isa.instruction_width.bytes

      file_data = file.read
      preprocessed_data = []
      file_data.each_line do |line|
        line = line.gsub(/#.+$/, '').strip
        next if line.empty?

        if in_instructions
          pc += @isa.instruction_width.bytes

          # NEED TO RESOLVE LABEL OFFSETS _AFTER_ MNEMONIC EXPANSION

          puts "[#{pc.to_hex_string}] #{line}"
          if match = line.match(/^([^:]+):$/)
            pc -= @isa.instruction_width.bytes # labels don't count
            labels[match[1]] = pc
            next # don't add to the preprocessed_data
          end
        else
          in_instructions = line =~ /^.text$/
        end

        preprocessed_data << line
      end

      [labels, preprocessed_data]
    end
end

