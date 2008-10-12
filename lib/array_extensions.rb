class Array
  def count(data)
    self.inject(0) do |sum, val|
      sum += 1 if val == data
      sum
    end
  end

  # Converts an array of [key, value] pairs into a hash.
  def to_hash
    Hash[self.flatten]
  end
end

