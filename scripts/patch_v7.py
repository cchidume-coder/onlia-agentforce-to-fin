"""Version 7 = Version 6 minus Get_Linked_Case, Existing_Case, Reuse_Case, Create_a_Case.
Queue_Available's 'Queue found' goes straight to Set_Case_and_Contact_on_Call.
Usage: python3 -I patch_v7.py <v6.xml> <out.xml>"""
import sys

src, out = sys.argv[1], sys.argv[2]
x = open(src, encoding="utf-8").read()


def remove(name, tag):
    global x
    anchor = f"<name>{name}</name>"
    if x.count(anchor) != 1:
        sys.exit(f"{name}: anchor count {x.count(anchor)}")
    i = x.index(anchor)
    start = x.rfind(f"    <{tag}>\n", 0, i)
    end = x.index(f"    </{tag}>\n", i) + len(f"    </{tag}>\n")
    if start < 0 or x.count("<name>", start, i) != 0:
        sys.exit(f"{name}: could not isolate its <{tag}> block")
    x = x[:start] + x[end:]


# Repoint Queue_Available 'Queue found' before removing its old target.
qs = x.index("<name>Queue_Available</name>")
qe = x.index("</decisions>", qs)
blk = x[qs:qe]
old = "<targetReference>Get_Linked_Case</targetReference>"
if blk.count(old) != 1:
    sys.exit("Queue_Available connector not as expected")
x = x[:qs] + blk.replace(old, "<targetReference>Set_Case_and_Contact_on_Call</targetReference>") + x[qe:]

for name, tag in (("Get_Linked_Case", "recordLookups"), ("Existing_Case", "decisions"),
                  ("Reuse_Case", "assignments"), ("Create_a_Case", "recordCreates")):
    remove(name, tag)

open(out, "w", encoding="utf-8").write(x)
print("v7 written")
