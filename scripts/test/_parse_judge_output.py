import json, sys, re

text = sys.stdin.read()

# Extract JSON from LLM output (may have markdown fences or extra text)
if '```' in text:
    parts = text.split('```')
    for p in parts:
        if p.strip().startswith('['):
            text = p.strip()
            break

# Find the JSON array
match = re.search(r'\[.*\]', text, re.DOTALL)
if match:
    text = match.group(0)

try:
    metrics = json.loads(text)
    passed = sum(1 for m in metrics if m.get('passed', False))
    total = len(metrics)

    print(f'=== LLM-as-Judge: {passed}/{total} metrics passed ===')
    for m in metrics:
        status = 'PASS' if m.get('passed') else 'WARN'
        print(f'  [{status}] {m["metric"]}: {m["score"]:.2f} — {m.get("reasoning", "?")}')

    print(f'LLM_JUDGE_PASS={passed}')
    print(f'LLM_JUDGE_TOTAL={total}')
    sys.exit(0 if passed >= 5 else 1)

except (json.JSONDecodeError, KeyError, TypeError) as e:
    print(f'LLM_JUDGE_PARSE_ERROR={e}')
    print('--- Raw judge output (first 500 chars) ---')
    raw = text[:500] if isinstance(text, str) else str(e)
    print(raw)
    sys.exit(1)
