"""Version 6 = Version 4 + two elements (Find_Caller_Contact, Create_Call_Case) + value edits.
Usage: python3 -I patch_v6.py <v4.xml> <out.xml>"""
import sys

src, out = sys.argv[1], sys.argv[2]
x = open(src, encoding="utf-8").read()


def section(name, closing):
    s = x.index(f"<name>{name}</name>")
    return s, x.index(closing, s)


def replace_in(name, closing, old, new):
    global x
    s, e = section(name, closing)
    block = x[s:e]
    if block.count(old) != 1:
        sys.exit(f"{name}: expected exactly one {old!r}, found {block.count(old)}")
    x = x[:s] + block.replace(old, new) + x[e:]


# Edit A: Get_Voice_Call -> go to Find_Caller_Contact first, and also fetch FromPhoneNumber.
replace_in("Get_Voice_Call", "</recordLookups>",
           "<targetReference>Test_Route_to_Fin</targetReference>",
           "<targetReference>Find_Caller_Contact</targetReference>")
replace_in("Get_Voice_Call", "</recordLookups>",
           "        <queriedFields>CallDisposition</queriedFields>\n",
           "        <queriedFields>CallDisposition</queriedFields>\n"
           "        <queriedFields>FromPhoneNumber</queriedFields>\n")

# Edit B: Get_Linked_Case looks up the Case created at call start (caseId).
replace_in("Get_Linked_Case", "</recordLookups>",
           "<elementReference>Refresh_Call.Case__c</elementReference>",
           "<elementReference>caseId</elementReference>")

# Edit C: Set_Case_and_Contact_on_Call writes the found Contact back to the Voice Call.
replace_in("Set_Case_and_Contact_on_Call", "</recordUpdates>",
           "<elementReference>Refresh_Call.Contact__c</elementReference>",
           "<elementReference>Find_Caller_Contact.Id</elementReference>")

# New element 1: Find Contact by the caller's phone number.
FIND = """    <recordLookups>
        <name>Find_Caller_Contact</name>
        <label>Find Contact</label>
        <locationX>0</locationX>
        <locationY>0</locationY>
        <assignNullValuesIfNoRecordsFound>false</assignNullValuesIfNoRecordsFound>
        <connector>
            <targetReference>Create_Call_Case</targetReference>
        </connector>
        <faultConnector>
            <targetReference>Create_Call_Case</targetReference>
        </faultConnector>
        <filterLogic>and</filterLogic>
        <filters>
            <field>Phone</field>
            <operator>EqualTo</operator>
            <value>
                <elementReference>Get_Voice_Call.FromPhoneNumber</elementReference>
            </value>
        </filters>
        <getFirstRecordOnly>true</getFirstRecordOnly>
        <object>Contact</object>
        <queriedFields>Id</queriedFields>
        <storeOutputAutomatically>true</storeOutputAutomatically>
    </recordLookups>
"""

# New element 2: Create Case with that Contact; its Id goes into caseId.
CREATE = """    <recordCreates>
        <name>Create_Call_Case</name>
        <label>Create Case</label>
        <locationX>0</locationX>
        <locationY>0</locationY>
        <assignRecordIdToReference>caseId</assignRecordIdToReference>
        <connector>
            <targetReference>Test_Route_to_Fin</targetReference>
        </connector>
        <faultConnector>
            <targetReference>Test_Route_to_Fin</targetReference>
        </faultConnector>
        <inputAssignments>
            <field>ContactId</field>
            <value>
                <elementReference>Find_Caller_Contact.Id</elementReference>
            </value>
        </inputAssignments>
        <inputAssignments>
            <field>Origin</field>
            <value>
                <stringValue>Phone</stringValue>
            </value>
        </inputAssignments>
        <inputAssignments>
            <field>Subject</field>
            <value>
                <stringValue>Onlia voice call</stringValue>
            </value>
        </inputAssignments>
        <object>Case</object>
    </recordCreates>
"""

for tag, snippet in (("    <recordCreates>\n", CREATE), ("    <recordLookups>\n", FIND)):
    if x.count(tag) < 1:
        sys.exit(f"missing {tag.strip()}")
    i = x.index(tag)
    x = x[:i] + snippet + x[i:]

open(out, "w", encoding="utf-8").write(x)
print("v6 written")
