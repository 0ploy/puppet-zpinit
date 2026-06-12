# Renders a flat-ish Hash into a zpinit service TOML document.
#
# This is deliberately NOT a general TOML serializer. It models exactly the
# shape a zpinit service file needs:
#
#   * top-level scalars and arrays  -> `key = value`
#   * one level of nested Hashes    -> `[table]` sections (env, log, ready)
#
# TOML requires every bare `key = value` to precede any `[table]` header
# (otherwise the key would bind to the table), so scalars are always emitted
# first regardless of their position in the input Hash. nil values are
# skipped; empty tables are omitted. Strings are emitted as TOML basic
# strings with correct escaping, which is why env values etc. are safe to
# pass through verbatim.
#
# Determinism: Ruby/Puppet preserve Hash insertion order, so the same input
# always renders byte-identically -- important for file resource idempotence.
Puppet::Functions.create_function(:'zpinit::to_toml') do
  dispatch :to_toml do
    param 'Hash', :data
    return_type 'String'
  end

  def to_toml(data)
    scalars = data.reject { |_, v| v.is_a?(Hash) || v.nil? }
    tables  = data.select { |_, v| v.is_a?(Hash) }

    lines = []
    scalars.each { |k, v| lines << "#{k} = #{render(v)}" }

    tables.each do |name, tbl|
      next if tbl.nil? || tbl.empty?
      lines << ''
      lines << "[#{name}]"
      tbl.each do |k, v|
        next if v.nil?
        lines << "#{k} = #{render(v)}"
      end
    end

    "#{lines.join("\n")}\n"
  end

  def render(value)
    case value
    when String
      toml_string(value)
    when Integer, Float
      value.to_s
    when TrueClass, FalseClass
      value.to_s
    when Array
      "[#{value.map { |e| render(e) }.join(', ')}]"
    else
      raise Puppet::Error, "zpinit::to_toml: cannot render #{value.class} (#{value.inspect})"
    end
  end

  # Emit a TOML basic string: double-quoted, with the escapes TOML mandates.
  def toml_string(str)
    escaped = str.to_s.gsub(/["\\\n\r\t\f\b]|[\x00-\x1f]/) do |c|
      case c
      when '\\' then '\\\\'
      when '"'  then '\\"'
      when "\n" then '\\n'
      when "\r" then '\\r'
      when "\t" then '\\t'
      when "\f" then '\\f'
      when "\b" then '\\b'
      else format('\\u%04X', c.ord)
      end
    end
    "\"#{escaped}\""
  end
end
