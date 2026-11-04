# Offline maintenance checks

Run from the repository root:

```bash
python3 tests/maintenance/test_maintenance.py
```

Requires Python 3.10+, Bash and jq. Tests run sequentially with temporary homes,
stub downloads/MCP commands, and no package installation or network access.
They never run the full installer against your account. The preflight CI matrix
runs this suite on Linux and macOS.

Coverage includes failed/truncated downloads, stale completion markers, settings
preservation, repeated hook installation, nvm with `nounset`, shell paths containing
spaces/metacharacters, malformed statusline input, arithmetic injection, and drift
between the template and both embedded statusline copies.

Set `CLI_MAXXING_TEST_BASH` to test another Bash executable, or
`CLI_MAXXING_TEST_ROOT` to run the same regressions against a baseline checkout.
The latter must include all installer files and `templates/statusline.sh`.

To compare statusline implementations with identical offline fixtures:

```bash
python3 tests/maintenance/benchmark_statusline.py /path/to/baseline/statusline.sh templates/statusline.sh
```

The benchmark alternates implementations, discards two warmups, then reports 20
measurements per implementation. It measures script execution, not end-to-end
Claude responsiveness. Live vendor downloads, credentials, package installation,
and fresh OS/login integration remain the responsibility of the existing
throwaway-machine CI suite.

Settings merges use a `settings.json.cli-maxxing-lock` directory. If another
installer owns it, the merge stops and preserves the file. A process killed
without a cleanup opportunity can leave the lock behind; check that no installer
is running before removing that reported lock and rerunning. This lock does not
coordinate with arbitrary external editors or Claude's own settings writes.
