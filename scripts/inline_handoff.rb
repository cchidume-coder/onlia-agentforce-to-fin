# Put the Broker Handoff steps INSIDE a procedure as a "Broker Handoff" sub-procedure, run whenever the
# caller asks for a broker. Replaces the cross-procedure <switch> step added earlier.
# Usage: ruby inline_handoff.rb in.yaml out.yaml
require "yaml"

SWITCH_MARK = 'switch to="Onlia - Broker Handoff"'
REQUEST = "The caller asks to speak to a broker, a licensed agent, a person or a human, or confirms they want to be connected to one, or asks for something only a broker can do (a coverage change or upgrade, pricing, finalizing a quote, billing help, or a pricing or billing exception)"
VERIFIED = "There is NO successful Onlia Verify Code result in this conversation (a successful result has isSuccess true, empty errors and isVerified true)"
SUMMARY = "newSubject set to a short subject under 50 characters describing why the caller called, and newDescription set to 3 to 5 sentences summarising the call for the broker: what the caller asked for, what was already done on this call (for example verification, policy lookup, pink slip sent, contact details updated) and what they now need from the broker"

src, dst = ARGV
d = YAML.load_file(src)
proc_ = d["procedure"]
main = proc_["main"]

# 1. Replace (or add) the trigger step in main: run the sub-procedure.
trigger = { "if" => REQUEST, "then" => { "run" => "Broker Handoff" } }
idx = main.index { |s| s.to_s.include?(SWITCH_MARK) }
if idx then main[idx] = trigger else main << trigger end

# 2. The sub-procedure itself.
steps = []
steps << { "if" => VERIFIED, "then" => { "run" => "Verify Caller" } } if proc_.key?("Verify Caller")
steps << "<use action=\"Onlia Find Latest Case\" /> with contactId set to the customerId from the successful Onlia Verify Code result in this conversation."
steps << {
  "if" => "Onlia Find Latest Case found a case for the caller",
  "then" => "<use action=\"Onlia Update Case\" /> with caseId set to the case found by Onlia Find Latest Case, contactId set to the verified customerId, #{SUMMARY}. Do not create a new case.",
  "else" => "<use action=\"Onlia Update Or Create Case\" /> with contactId set to the verified customerId, #{SUMMARY}.",
}
steps << "Only after the case step above has run, say ONE short line in your own words, for example: \"That's not something I'm able to handle, but I'll pass you to someone on our licensed team who can help.\" <handoff id=\"handoff-broker\" />"
proc_["Broker Handoff"] = steps

# 3. The handoff tool (same as the Onlia - Broker Handoff procedure).
msg = "You'll be passed over to a licensed broker now."
d["inline_tool_definitions"] ||= {}
d["inline_tool_definitions"]["handoff-broker"] = {
  "type" => "handoff",
  "in_office_hours" => { "type" => "end_call", "data" => { "handover_message" => msg } },
  "out_of_office_hours" => { "type" => "end_call", "data" => { "handover_message" => msg } },
}

File.write(dst, d.to_yaml(line_width: -1))
puts "#{File.basename(src)}: trigger step #{idx ? 'replaced at main[' + idx.to_s + ']' : 'appended'}; sub-procedure steps: #{steps.size}; verify-first: #{proc_.key?('Verify Caller')}"
