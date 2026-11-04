"""Offline regressions. Never execute real installers or inspect live swarm files."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(os.environ.get('CLI_MAXXING_TEST_ROOT', Path(__file__).resolve().parents[2]))
BASH = os.environ.get('CLI_MAXXING_TEST_BASH', '/bin/bash')


def function(path, name):
    text = (ROOT / path).read_text()
    start = text.index(name + '() {')
    # Ignore the closing brace of a JSON heredoc in the original installers.
    end = start + re.search(r'\n}\n(?![A-Z][A-Z0-9_]*\n)', text[start:]).end()
    return text[start:end]


class Sandbox(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='cli-maxxing-test-')
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)
        self.home = self.work / 'home with spaces'
        self.bin = self.work / 'bin'
        self.home.mkdir()
        self.bin.mkdir()
        self.env = {'HOME': str(self.home), 'PATH': str(self.bin) + ':/usr/bin:/bin',
                    'SHELL': BASH, 'TMPDIR': str(self.work) + '/', 'FIXTURE_BIN': str(self.bin),
                    'LC_ALL': 'C', 'TRACE': str(self.work / 'trace')}
        jq = shutil.which('jq')
        if not jq:
            self.skipTest('jq is required')
        (self.bin / 'jq').symlink_to(jq)
        self.stub('brew', 'exit 0')
        self.stub('pgrep', 'exit 1')
        # Prevent old statusline implementations touching real /tmp activity files.
        self.stub('find', 'exit 0')
        self.stub('rm', 'for arg in "$@"; do case "$arg" in /tmp/fidgetflo-*) exit 91;; esac; done\nexec /bin/rm "$@"')
        self.stub('uname', 'echo Linux')
        self.stub('claude', 'echo fixture-claude')
        self.stub('bash', 'exec ' + BASH + ' "$@"')
        nvm = self.home / '.nvm'
        nvm.mkdir()
        (nvm / 'nvm.sh').write_text('export PATH="$FIXTURE_BIN:/usr/bin:/bin"\n')

    def stub(self, name, body):
        p = self.bin / name
        p.write_text('#!/bin/bash\n' + body + '\n')
        p.chmod(0o755)

    def run_shell(self, text, data='', **env):
        return subprocess.run([BASH, '-c', text], input=data, text=True,
                              capture_output=True, env={**self.env, **env},
                              cwd=self.work, timeout=30)

    def script(self, name, data='', **env):
        return subprocess.run(
            [BASH, str(ROOT / name)], input=data, text=True, capture_output=True,
            env={**self.env, **env}, cwd=self.work, timeout=30)


class Statusline(Sandbox):
    def render(self, payload):
        return self.script('templates/statusline.sh', json.dumps(payload))

    def test_normal_payload(self):
        r = self.render({'model': {'display_name': 'Test'}, 'cost': {'total_duration_ms': 65000},
                         'context_window': {'used_percentage': 42.9},
                         'rate_limits': {'five_hour': {'used_percentage': 75}}})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stderr, '')
        self.assertIn('Test • ⏱ 1m5s • 42% ctx', r.stdout)
        self.assertIn('75%', r.stdout)

    def test_untrusted_arithmetic(self):
        payload = {'rate_limits': {'five_hour': {'used_percentage': 'a[$(touch "$HOME/executed")]'}}}
        r = self.render(payload)
        self.assertFalse((self.home / 'executed').exists(), 'JSON executed shell code')
        self.assertEqual(r.stderr, '')
        self.assertEqual(r.returncode, 0)

    def test_malformed_types_and_ranges(self):
        for payload in [None, [], 'text', {},
                        {'cost': {'total_duration_ms': '008'}},
                        {'cost': {'total_duration_ms': 1e100}, 'context_window': {'used_percentage': []}},
                        {'rate_limits': {'five_hour': {'used_percentage': '08'}}},
                        {'rate_limits': {'five_hour': {'used_percentage': {}}, 'seven_day': {'used_percentage': -30}}}]:
            with self.subTest(payload=payload):
                r = self.render(payload)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertEqual(r.stderr, '')
                self.assertIn('% ctx', r.stdout)

    def test_invalid_json(self):
        r = self.script('templates/statusline.sh', '{broken')
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stderr, '')
        self.assertIn('Claude', r.stdout)

    def test_single_parser(self):
        real = str((self.bin / 'jq').resolve())
        (self.bin / 'jq').unlink()
        self.stub('jq', 'echo jq >> "$TRACE"\nexec "' + real + '" "$@"')
        self.render({})
        self.assertEqual((self.work / 'trace').read_text().splitlines(), ['jq'])

    def test_embedded_copies_match(self):
        for path in ['step-4/step-4-install.sh', 'step-final/step-final-install.sh']:
            text = (ROOT / path).read_text()
            embedded = text.split("<< 'STATUSLINE_EOF'\n", 1)[1].split('\nSTATUSLINE_EOF', 1)[0] + '\n'
            self.assertTrue(embedded == (ROOT / 'templates/statusline.sh').read_text(), path)


    def test_missing_jq_has_quiet_fallback(self):
        no_tools = self.work / 'no-tools'
        no_tools.mkdir()
        (no_tools / 'cat').symlink_to(shutil.which('cat'))
        r = self.script('templates/statusline.sh', '{}', PATH=str(no_tools))
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stderr, '')
        self.assertIn('jq missing', r.stdout)

    def test_vault_marker_and_control_characters(self):
        marker = self.home / '.claude/.mogging-vault'
        marker.parent.mkdir()
        marker.write_text('/fixture/vault\n')
        r = self.render({'model': {'display_name': 'Test\nModel\x1b'},
                         'workspace': {'current_dir': '/fixture/vault/notes'}})
        self.assertEqual(r.stderr, '')
        self.assertIn('🧠 Brain²', r.stdout)
        self.assertIn('TestModel', r.stdout)
        self.assertEqual(len(r.stdout.splitlines()), 1)



class Orchestration(Sandbox):
    def setUp(self):
        super().setUp()
        self.stub('curl', r'''out=""; url=""
while [ "$#" -gt 0 ]; do
 case "$1" in -o|--output) out="$2"; shift;; https://*) url="$1";; esac
 shift
done
case "$url" in
 */preflight.sh)
   body='cm_preflight() { export CLI_MAXXING_PREFLIGHT_DONE=1; export CLI_MAXXING_NO_SUDO="${NO_SUDO:-0}"; }';;
 *)
   step="${url##*/}"; step="${step%-install.sh}"
   body="echo $step >> \"\$TRACE\""
   body="$body
mkdir -p \"\$HOME/.cli-maxxing\"
touch \"\$HOME/.cli-maxxing/$step.done\""
   if [ "$step" = step-2 ]; then
     body="$body
 touch \"\$HOME/.cli-maxxing/ghostty.done\" \"\$HOME/.cli-maxxing/arc.done\""
   fi
   case "$url" in *"${FAIL_STEP:-never-match}"*) body="$body
exit 9";; esac;;
esac
if [ -n "$out" ]; then printf '%s\n' "$body" > "$out"; else printf '%s\n' "$body"; fi
case "$url" in *"${PARTIAL_STEP:-never-match}"*) exit 18;; esac
''')

    def test_update_reports_failure(self):
        r = self.script('update.sh', FAIL_STEP='step-3/')
        self.assertNotEqual(r.returncode, 0, r.stdout)
        self.assertNotIn('All steps are current', r.stdout)
        self.assertIn('step-final', (self.work / 'trace').read_text())

    def test_partial_download_never_executes(self):
        r = self.script('step-2/step-2-install.sh', PARTIAL_STEP='ghostty-install')
        self.assertNotEqual(r.returncode, 0)
        trace = (self.work / 'trace').read_text() if (self.work / 'trace').exists() else ''
        self.assertNotIn('ghostty', trace)
        self.assertIn('arc', trace)

    def test_stale_markers_do_not_mask_failed_install(self):
        crumbs = self.home / '.cli-maxxing'
        crumbs.mkdir()
        for name in ['step-1', 'step-3', 'step-4', 'step-8', 'step-final', 'arc', 'ghostty']:
            (crumbs / (name + '.done')).touch()
        r = self.script('install.sh', FAIL_STEP='step-3/')
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse((crumbs / 'step-3.done').exists())

    def test_step_one_failure_stops_install(self):
        r = self.script('install.sh', FAIL_STEP='step-1/')
        self.assertNotEqual(r.returncode, 0)
        self.assertNotIn('step-3', (self.work / 'trace').read_text())

    def test_successful_update(self):
        r = self.script('update.sh')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len((self.work / 'trace').read_text().splitlines()), 9)
        self.assertEqual(list(self.work.glob('cli-maxxing-download.*')), [])

    def test_successful_install_twice(self):
        for _ in range(2):
            r = self.script('install.sh')
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(list(self.work.glob('cli-maxxing-download.*')), [])

    def test_no_sudo_installs_and_updates_only_eligible_steps(self):
        for script in ['install.sh', 'update.sh']:
            (self.work / 'trace').unlink(missing_ok=True)
            r = self.script(script, NO_SUDO='1')
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            trace = (self.work / 'trace').read_text().splitlines()
            self.assertNotIn('step-2', trace)
            self.assertNotIn('step-3', trace)
            self.assertIn('step-4', trace)
            self.assertIn('step-final', trace)

    def test_partial_preflight_stops_before_steps(self):
        for script in ['install.sh', 'update.sh']:
            (self.work / 'trace').unlink(missing_ok=True)
            r = self.script(script, PARTIAL_STEP='scripts/preflight.sh')
            self.assertNotEqual(r.returncode, 0)
            self.assertFalse((self.work / 'trace').exists())



class Settings(Sandbox):
    def setUp(self):
        super().setUp()
        self.settings = self.home / '.claude/settings.json'
        self.settings.parent.mkdir()

    def test_final_preserves_projects_and_is_idempotent(self):
        project = self.home / 'Documents/project/.claude/settings.json'
        project.parent.mkdir(parents=True)
        project.write_text('{"statusLine":{"type":"command","command":"custom"}}')
        self.stub('find', 'printf "%s\\n" "$HOME/Documents/project/.claude/settings.json"')
        self.settings.write_text('{"permissions":{"allow":["Read"]},"statusLine":null}')
        for _ in range(2):
            r = self.script('step-final/step-final-install.sh')
            self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(project.read_text())['statusLine']['command'], 'custom')
        data = json.loads(self.settings.read_text())
        self.assertEqual(data['permissions'], {'allow': ['Read']})
        self.assertEqual(data['statusLine']['command'], '~/.claude/statusline.sh')
        self.assertEqual(len(re.findall('alias cskip=', (self.home / '.bashrc').read_text())), 1)

    def test_final_invalid_settings_fail_without_replacement(self):
        self.settings.write_text('{"statusLine": broken}')
        r = self.script('step-final/step-final-install.sh')
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.settings.read_text(), '{"statusLine": broken}')
        self.assertFalse((self.home / '.cli-maxxing/step-final.done').exists())

    def test_memory_hook_preserves_other_stop_hooks(self):
        existing = {'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': 'my-hook'}]}]}}
        self.settings.write_text(json.dumps(existing))
        body = 'set -u\nERRORS=0\ninfo() { :; }; success() { :; }; warn() { :; }; soft_fail() { ERRORS=$((ERRORS+1)); };\n'
        body += function('step-3/step-3-install.sh', 'configure_memory_hook')
        body += '\nconfigure_memory_hook\nconfigure_memory_hook\n'
        r = self.run_shell(body)
        self.assertEqual(r.returncode, 0, r.stderr)
        hooks = json.loads(self.settings.read_text())['hooks']['Stop']
        self.assertEqual(hooks[0], existing['hooks']['Stop'][0])
        self.assertEqual(len(hooks), 2)


    def test_settings_lock_preserves_another_writers_lock(self):
        self.settings.write_text('{"permissions":{"allow":["Read"]}}')
        lock = self.settings.with_name('settings.json.cli-maxxing-lock')
        lock.mkdir()
        r = self.script('step-final/step-final-install.sh')
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.settings.read_text(), '{"permissions":{"allow":["Read"]}}')
        self.assertTrue(lock.exists())
        self.assertEqual(list(self.settings.parent.glob('.settings.*')), [])

    def test_settings_reject_nonobjects_and_multiple_roots(self):
        for value in ['[]', 'null', '{} {}']:
            self.settings.write_text(value)
            r = self.script('step-final/step-final-install.sh')
            self.assertNotEqual(r.returncode, 0, value)
            self.assertEqual(self.settings.read_text(), value)
            self.assertFalse(self.settings.with_name('settings.json.cli-maxxing-lock').exists())
            self.assertEqual(list(self.settings.parent.glob('.settings.*')), [])



class Recovery(Sandbox):
    def test_all_runtime_sources_tolerate_nounset(self):
        (self.home / '.nvm/nvm.sh').write_text('unused="$UNSET_NVM_INTERNAL"\nexport PATH="$FIXTURE_BIN:/usr/bin:/bin"\n')
        paths = ['install.sh', 'update.sh', 'uninstall.sh'] + [
            str(p.relative_to(ROOT)) for p in ROOT.glob('step-*/*.sh')
            if 'source_runtime_path() {' in p.read_text()]
        for path in paths:
            name = 'reload_path' if path == 'install.sh' else 'source_runtime_path'
            body = 'set -u\n' + function(path, name) + '\n' + name + '\necho survived\n'
            with self.subTest(path=path):
                r = self.run_shell(body)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertIn('survived', r.stdout)

    def test_no_flicker_handles_home_with_spaces(self):
        (self.home / '.bashrc').touch()
        body = 'set -u\ninfo() { :; }; success() { :; }; warn() { :; };\n'
        body += function('step-3/step-3-install.sh', 'detect_os') + '\n'
        body += function('step-3/step-3-install.sh', 'configure_no_flicker') + '\n'
        body += 'detect_os\nconfigure_no_flicker\nconfigure_no_flicker\n'
        r = self.run_shell(body)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((self.home / '.bashrc').exists())
        self.assertEqual((self.home / '.bashrc').read_text().count('export CLAUDE_CODE_NO_FLICKER='), 1)

    def test_batch_telegram_does_not_create_configuration(self):
        r = self.script('step-6/step-6-install.sh')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse((self.home / '.claude/channels/telegram').exists())

    def test_productivity_inventory_queries_once(self):
        self.stub('claude', 'echo called >> "$TRACE"\necho "notion: fixture"')
        body = 'set -u\ninfo() { :; }; print_summary() { :; };\n'
        body += function('step-5/step-5-install.sh', 'choose_tools') + '\nchoose_tools\necho "$CHOICES"\n'
        r = self.run_shell(body)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.strip(), '1')
        self.assertEqual((self.work / 'trace').read_text().splitlines(), ['called'])

    def test_uninstall_preserves_custom_statusline(self):
        settings = self.home / '.claude/settings.json'
        settings.parent.mkdir()
        settings.write_text('{"statusLine":{"type":"command","command":"my-custom-command"},"other":true}')
        body = 'set -u\nBLUE=""; NC=""; success() { :; }; skip() { :; }; warn() { :; };\n'
        body += function('uninstall.sh', 'uninstall_status_line') + '\nuninstall_status_line\n'
        r = self.run_shell(body)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(settings.read_text())['statusLine']['command'], 'my-custom-command')

    def test_failure_counts_prevent_completion(self):
        for step in ['1', '3', '4', '7']:
            path = f'step-{step}/step-{step}-install.sh'
            main = function(path, 'main')
            names = re.findall(r'^(\w+)\(\) \{', (ROOT / path).read_text(), re.M)
            stubs = '\n'.join(n + '() { :; }' for n in names if n != 'main')
            body = 'set -u\nERRORS=1; CHOICES=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""; CLI_MAXXING_PREFLIGHT_DONE=1;\n'
            body += stubs + '\n' + main + '\nmain\n'
            r = self.run_shell(body)
            with self.subTest(step=step):
                self.assertNotEqual(r.returncode, 0)
                self.assertNotIn('unbound variable', r.stderr)
                self.assertFalse((self.home / f'.cli-maxxing/step-{step}.done').exists())


    def run_step3_hyperresearch(self, os_name, supported_python=False):
        # A bin-only PATH guarantees the host cannot supply Python or installers.
        self.stub('pipx', 'echo called >> "$TRACE"\nexit 19')
        self.stub('brew', 'exit 1')
        for name in ['mkdir', 'touch']:
            (self.bin / name).symlink_to(shutil.which(name))
        if supported_python:
            self.stub('python3.13', 'echo "Python 3.13.0"')
        path = 'step-3/step-3-install.sh'
        names = re.findall(r'^(\w+)\(\) \{', (ROOT / path).read_text(), re.M)
        stubs = '\n'.join(n + '() { :; }' for n in names
                          if n not in ['main', 'install_hyperresearch', 'soft_fail', 'warn'])
        body = 'set -u\nERRORS=0; RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""; CLI_MAXXING_PREFLIGHT_DONE=1;\n'
        body += 'soft_fail() { ERRORS=$((ERRORS+1)); }; warn() { echo "$*"; };\n'
        body += stubs + '\n' + function(path, 'install_hyperresearch') + '\n' + function(path, 'main')
        body += '\nmain\nrc=$?\necho "ERRORS=$ERRORS"\nexit "$rc"\n'
        return self.run_shell(body, PATH=str(self.bin), OS=os_name)

    def test_step3_linux_unsupported_python_is_an_optional_skip(self):
        r = self.run_step3_hyperresearch('linux')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('hyperresearch skipped', r.stdout)
        self.assertIn('ERRORS=0', r.stdout)
        self.assertTrue((self.home / '.cli-maxxing/step-3.done').exists())
        self.assertFalse((self.work / 'trace').exists())

    def test_step3_mac_python_install_failure_blocks_completion(self):
        r = self.run_step3_hyperresearch('mac')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('ERRORS=1', r.stdout)
        self.assertFalse((self.home / '.cli-maxxing/step-3.done').exists())

    def test_step3_hyperresearch_install_failure_blocks_completion(self):
        r = self.run_step3_hyperresearch('linux', supported_python=True)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('ERRORS=1', r.stdout)
        self.assertFalse((self.home / '.cli-maxxing/step-3.done').exists())
        self.assertEqual((self.work / 'trace').read_text().splitlines(), ['called'])

    def test_preflight_failure_never_evaluates_partial_body(self):
        self.stub('curl', 'echo \'touch "$HOME/preflight-executed"\'\nexit 18')
        for path in ['step-1/step-1-install.sh', 'step-3/step-3-install.sh',
                     'step-4/step-4-install.sh', 'step-7/step-7-install.sh', 'step-2/ghostty-install.sh']:
            main = function(path, 'main')
            names = re.findall(r'^(\w+)\(\) \{', (ROOT / path).read_text(), re.M)
            stubs = '\n'.join(n + '() { :; }' for n in names if n not in ['main', 'fail'])
            body = 'set -u\nERRORS=0; CHOICES=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""; fail() { exit 1; };\n'
            body += stubs + '\n' + main + '\nmain\n'
            r = self.run_shell(body)
            with self.subTest(path=path):
                self.assertNotEqual(r.returncode, 0)
                self.assertFalse((self.home / 'preflight-executed').exists())
            (self.home / 'preflight-executed').unlink(missing_ok=True)

    def test_step8_rejected_update_preserves_old_skill_and_fails(self):
        skill = self.home / '.claude/skills/safetycheck/SKILL.md'
        skill.parent.mkdir(parents=True)
        skill.write_text('existing verified skill')
        self.stub('curl', 'while [ "$#" -gt 0 ]; do if [ "$1" = -o ]; then echo invalid > "$2"; exit 0; fi; shift; done; exit 1')
        path = 'step-8/step-8-install.sh'
        names = re.findall(r'^(\w+)\(\) \{', (ROOT / path).read_text(), re.M)
        stubs = '\n'.join(n + '() { :; }' for n in names if n not in ['main', 'install_skill', 'soft_fail'])
        body = 'set -u\nERRORS=0; TEST_FAIL=0; RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""; soft_fail() { ERRORS=$((ERRORS+1)); };\n'
        body += stubs + '\n' + function(path, 'install_skill') + '\n' + function(path, 'main') + '\nmain\n'
        r = self.run_shell(body)
        self.assertEqual(skill.read_text(), 'existing verified skill')
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse((self.home / '.cli-maxxing/step-8.done').exists())

    def test_persisted_claude_path_is_shell_quoted(self):
        special = self.work / 'bin $(touch PWNED)'
        special.mkdir()
        executable = special / 'claude'
        executable.write_text('#!/bin/bash\necho fixture\n')
        executable.chmod(0o755)
        (self.home / '.local/bin').mkdir(parents=True)
        body = 'set -u\ninfo() { :; }; success() { :; }; warn() { :; }; OS=linux; USER_SHELL=bash; SHELL_RCS=("$HOME/.bashrc"); SHELL_PROFILES=("$HOME/.bash_profile");\n'
        body += function('step-1/step-1-install.sh', 'install_claude_code') + '\ninstall_claude_code\n. "$HOME/.bashrc"\n'
        r = self.run_shell(body, PATH=str(special) + ':' + self.env['PATH'])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse((self.work / 'PWNED').exists())



    def test_ghostty_preserves_existing_configuration(self):
        config = self.home / '.config/ghostty/config'
        config.parent.mkdir(parents=True)
        config.write_text('font-size = 18\n# personal configuration\n')
        body = 'OS=linux; info() { :; }; success() { :; };\n'
        body += function('step-2/ghostty-install.sh', 'configure_ghostty') + '\nconfigure_ghostty\nconfigure_ghostty\n'
        r = self.run_shell(body)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(config.read_text(), 'font-size = 18\n# personal configuration\n')

    def test_pdf_temporary_files_cleaned_on_success_and_failure(self):
        # Keep the old BSD -t form inside the fixture on every platform.
        self.stub('mktemp', 'if [ "$1" = -t ]; then shift; exec /usr/bin/mktemp "$TMPDIR/$1"; fi\nexec /usr/bin/mktemp "$@"')
        source = self.work / 'source.md'
        source.write_text('# Title\n\nBody\n')
        self.stub('pandoc', 'test -s "$1" || exit 90\nexit "${PANDOC_RC:-0}"')
        for code in [0, 7]:
            r = subprocess.run([BASH, str(ROOT / 'pdf-skill/render-pdf.sh'), str(source)],
                               env={**self.env, 'PANDOC_RC': str(code)}, cwd=self.work,
                               text=True, capture_output=True, timeout=30)
            self.assertEqual(r.returncode, code, r.stderr)
            self.assertEqual(list(self.work.glob('renderpdf.*')), [])



if __name__ == '__main__':
    unittest.main(verbosity=2)
