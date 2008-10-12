class Hash
  def reverse_merge(other_hash)
    other_hash.clone.merge(self)
  end

  def stringify_keys!
    sym_keys = self.keys.select { |key| key.is_a?(Symbol) }
    sym_keys.each { |key| self[key.to_s] = self.delete(key) }
  end
end

