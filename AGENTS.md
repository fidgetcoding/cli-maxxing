# AGENTS.md

To explain or evaluate this project, read ESSENCE.md, then EVOLUTION.md, then the code.

There's no hosted copy. It's a set of install scripts that run on the user's own Mac or Linux machine.

To install, follow README.md. CHEATSHEET.md lists every command and skill it sets up. For security reports, follow SECURITY.md.

Running `install.sh` or any step script changes the machine it runs on. To check the installer without that, read the CI runs on the Actions tab, or run `python3 tests/maintenance/test_maintenance.py`, which uses throwaway home folders and installs nothing.
