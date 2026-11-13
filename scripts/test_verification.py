"""Test the Onlia verification loop end to end against the `onlia` org.

Sends a real code to the test contact's email, then asks you to type the
code you received. Nothing is printed except the results.
Run: python3 -I test_verification.py [email]
"""
import getpass
import json
import subprocess
import sys

EMAIL = sys.argv[1] if len(sys.argv) > 1 else "test.caller@example.com"


def call(flow, inputs):
    r = subprocess.run(
        ["sf", "api", "request", "rest",
         f"/services/data/v68.0/actions/custom/flow/{flow}",
         "-o", "onlia", "--method", "POST",
         "--body", json.dumps({"inputs": [inputs]})],
        capture_output=True, text=True,
    )
    out = r.stdout
    return json.loads(out[out.index("["):])[0]


sent = call("SvcCopilotTmpl__SendVerificationCode", {"customerToVerify": EMAIL})
ov = sent.get("outputValues") or {}
print("Send code:", "OK" if sent.get("isSuccess") else f"FAILED {sent.get('errors')}")
print(" ", ov.get("verificationMessage"))

code = getpass.getpass("Code from the email (hidden): ").strip()
res = call("SvcCopilotTmpl__VerifyCode", {
    "customerCode": code,
    "customerId": ov.get("customerId"),
    "customerType": ov.get("customerType"),
    "authenticationKey": ov.get("authenticationKey"),
})
rov = res.get("outputValues") or {}
print("Verified:", rov.get("isVerified"), "| contactId:", rov.get("customerId"))
print(" ", rov.get("messageAfterVerification"))
