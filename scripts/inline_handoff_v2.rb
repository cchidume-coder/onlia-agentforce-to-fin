# Built-in Broker Handoff for a procedure that currently uses <switch to="Onlia - Broker Handoff" />.
# - removes only a standalone switch step (the one added earlier),
# - replaces an embedded switch tag with a pointer to the final step (keeps the surrounding text),
# - appends: if caller asks for/agrees to a broker -> run Broker Handoff,
# - adds the Broker Handoff sub-procedure + handoff tool (same as Pink Slip).
# Usage: ruby inline_handoff_v2.rb in.yaml out.yaml   (prints every change)
require "yaml"

TAG = '<switch to="Onlia - Broker Handoff" />'
POINTER = "use the Broker Handoff steps (the final step of this procedure handles it)"
STANDALONE = /\AIf the caller asks to speak to a broker, a licensed agent, a person or a human/
REQUEST = "The caller asks to speak to a broker, a licensed agent, a person or a human, or agrees to be connected to one or to a broker callback, or asks for something only a broker can do (a coverage change or upgrade, pricing, finalizing a quote, billing help, or a pricing or billing exception)"
VERIFIED = "There is NO successful Onlia Verify Code result in this conversation (a successful result has isSuccess true, empty errors and isVerified true)"
SUMMARY = "newSubject set to a short subject under 50 characters describing why the caller called (for example \"Policy upgrade request - caller verified\"), and newDescription set to 3 to 5 sentences for the broker: what the caller asked for, what was already done on this call (verification, policy or quote lookup, contact details updated, and so on) and what they now need from the broker"
MSG = "You'll be passed over to a licensed broker now."

src, dst = ARGV
d = YAML.load_file(src)
pr = d["procedure"]; main = pr["main"]
log = []

swap = lambda do |s, where|
  return s unless s.is_a?(String) && s.include?(TAG)
  log << "  replaced tag in #{where}"
  s.gsub(TAG, POINTER)
end

removed = main.reject! { |s| s.is_a?(String) && s.strip.match?(STANDALONE) && s.include?(TAG) }
log << "  removed standalone switch step" if removed

main.each_with_index do |s, i|
  if s.is_a?(String)
    main[i] = swap.(s, "main[#{i}]")
  elsif s.is_a?(Hash)
    %w[then else].each do |k|
      v = s[k]
      if v.is_a?(String) then s[k] = swap.(v, "main[#{i}].#{k}")
      elsif v.is_a?(Array) then s[k] = v.map.with_index { |x, j| swap.(x, "main[#{i}].#{k}[#{j}]") }
      end
    end
  end
end
pr.each { |name, steps| next if name == "main" || !steps.is_a?(Array); steps.map!.with_index { |x, j| swap.(x, "#{name}[#{j}]") } }

leftover = d.to_yaml.include?(TAG)
abort "switch tag still present somewhere" if leftover

main << { "if" => REQUEST, "then" => { "run" => "Broker Handoff" } }
log << "  appended final step: if broker requested -> run Broker Handoff"

pr["Broker Handoff"] = [
  { "if" => VERIFIED, "then" => { "run" => "Verify Caller" } },
  "<use action=\"Onlia Find Latest Case\" /> with contactId set to the customerId from the successful Onlia Verify Code result in this conversation. Do not mention it to the caller.",
  { "if" => "Onlia Find Latest Case found a case for the caller",
    "then" => "<use action=\"Onlia Update Case\" /> with caseId set to the case found by Onlia Find Latest Case, contactId set to the verified customerId, #{SUMMARY}. Do not create a new case. Do not mention it to the caller.",
    "else" => "<use action=\"Onlia Update Or Create Case\" /> with contactId set to the verified customerId, #{SUMMARY}. Do not mention it to the caller." },
  "Only after the case step above has run, say ONE short line in your own words, for example: \"That's not something I'm able to handle, but I'll pass you to someone on our licensed team who can help.\" <handoff id=\"handoff-broker\" />",
]
log << "  added sub-procedure Broker Handoff (4 steps)"
d["inline_tool_definitions"] ||= {}
d["inline_tool_definitions"]["handoff-broker"] = {
  "type" => "handoff",
  "in_office_hours" => { "type" => "end_call", "data" => { "handover_message" => MSG } },
  "out_of_office_hours" => { "type" => "end_call", "data" => { "handover_message" => MSG } },
}
log << "  added handoff tool"
File.write(dst, d.to_yaml(line_width: -1))
puts File.basename(src) + ":"; puts log
