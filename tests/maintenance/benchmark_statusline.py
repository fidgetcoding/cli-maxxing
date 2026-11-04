"""Compare two statusline files with identical offline fixtures, alternating runs."""
import json
from pathlib import Path
import statistics
import subprocess
import sys
import time
from test_maintenance import Sandbox, BASH

fixture = Sandbox()
fixture.setUp()
try:
    payload = json.dumps({'model': {'display_name': 'Test'}, 'cost': {'total_duration_ms': 65000},
                          'context_window': {'used_percentage': 42},
                          'rate_limits': {'five_hour': {'used_percentage': 75}}})
    paths = [Path(p).resolve() for p in sys.argv[1:]]
    samples = {str(p): [] for p in paths}
    for i in range(22):
        for p in paths if i % 2 else reversed(paths):
            start = time.perf_counter()
            r = subprocess.run([BASH, str(p)], input=payload, text=True, capture_output=True,
                               env=fixture.env, cwd=fixture.work, timeout=30)
            elapsed = (time.perf_counter() - start) * 1000
            if r.returncode or r.stderr:
                raise RuntimeError(f'{p.name}: rc={r.returncode}, stderr={r.stderr}')
            if i >= 2:
                samples[str(p)].append(elapsed)
    print(json.dumps({p: {'runs': len(v), 'median_ms': round(statistics.median(v), 2),
                          'min_ms': round(min(v), 2), 'max_ms': round(max(v), 2)}
                      for p, v in samples.items()}, indent=2))
finally:
    fixture.doCleanups()
