# Rewrite email read-back instructions to "read it back naturally", in every string of a procedure YAML.
# Usage: ruby natural_readback.rb in.yaml out.yaml   -> prints each changed sentence (before => after)
require "yaml"

RULES = [
  [/\b([Ss])pell (it|the email|the email address) back( to them)? (?:one character at a time|letter by letter)(?: in a clear spoken manner)?(?:, saying 'at' and 'dot')?/,
   ->(m) { "#{m[1] == 'S' ? 'R' : 'r'}ead #{m[2]} back#{m[3]} naturally" }],
  [/[Ss]pell it out letter by letter, saying 'at' for the at sign and 'dot' for each dot\./,
   ->(_) { "Read it back naturally." }],
  [/spell an email letter by letter; read postal codes digit by digit/,
   ->(_) { "read an email back naturally; read postal codes in short groups" }],
  [/Spell out any email address letter by letter, and read postal codes and phone numbers digit by digit\./,
   ->(_) { "Read any email address back naturally, and read postal codes and phone numbers in short groups." }],
]

$changes = []

def fix(s)
  out = s.dup
  RULES.each do |re, rep|
    out = out.gsub(re) do
      m = Regexp.last_match
      r = rep.call(m)
      $changes << [m[0], r]
      r
    end
  end
  out
end

def walk(o)
  case o
  when Hash then o.each { |k, v| o[k] = walk(v) }
  when Array then o.map! { |v| walk(v) }
  when String then fix(o)
  else o
  end
end

src, dst = ARGV
doc = YAML.load_file(src)
walk(doc["procedure"])
if doc["inline_tool_definitions"]
  doc["inline_tool_definitions"].each_value do |h|
    %w[in_office_hours out_of_office_hours].each do |k|
      next unless h[k] && h[k]["data"] && h[k]["data"].key?("handover_message")
      old = h[k]["data"]["handover_message"]
      new = "You'll be passed over to a licensed broker now."
      $changes << [old, new] unless old == new
      h[k]["data"]["handover_message"] = new
    end
  end
end
File.write(dst, doc.to_yaml(line_width: -1))
$changes.each { |b, a| puts "  - #{b}\n    => #{a}" }
puts "  (#{$changes.size} changes)"
