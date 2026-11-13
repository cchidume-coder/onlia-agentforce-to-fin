import json,subprocess,sys,time
rid=sys.argv[1]
for _ in range(14):
    out=subprocess.run(["intercom","fin","simulations","result",rid,"--json"],capture_output=True,text=True).stdout
    d=json.loads(out[out.index('{'):])
    if d.get('status') not in ('running','pending'): break
    time.sleep(15)
print("status:",d.get('status'),"| duration:",d.get('duration_seconds'))
for e in d.get('events',[]):
    t=e.get('event_type'); dd=e.get('data') or {}
    if t=='fin_message': print("FIN :",dd.get('text','')[:200])
    elif t=='customer_message': print("USER:",dd.get('text','')[:160])
    elif t=='action_called': print("  >> CONNECTOR",dd.get('action_name'),"| mock" if dd.get('mock_id') else "| (no mock id)")
    elif t in ('procedure_started','end_section','goto_section','escalation','switch','procedure_switched','handoff','procedure_finished'): print("  [",t,"]",json.dumps(dd)[:180])
    elif t not in ('fin_thoughts','guidance_applied','attribute_update','task_instruction_started','conditional_evaluation'): print("  [",t,"]",json.dumps(dd)[:160])
print("--- assertions")
for a in d.get('assertions_results',[]):
    g=a.get('global',{})
    if a.get('assertion_type')=='action': print(" ",g.get('status'),"| connector assertion | actual calls:",[c.get('name') if isinstance(c,dict) else c for c in g.get('actual_calls',[])])
    for r in g.get('assertion_results',[]) or []: print(" ",'PASS' if r.get('passed') else 'FAIL','|',r.get('assertion','')[:120])
