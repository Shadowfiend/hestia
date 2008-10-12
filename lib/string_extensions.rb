class String
  def starts_with?(str)
    self[0...str.length] == str
  end

  def ends_with?(str)
    self[length-str.length..-1] == str
  end
end

