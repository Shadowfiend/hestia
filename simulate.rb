#require 'isa_def'
require 'lib/console_simulator'

if ARGV.length < 1
  $stderr.puts "Expected a filename as a parameter."
  exit 1
end

ConsoleSimulator.new(@isa3220).simulate_file(ARGV[0])

