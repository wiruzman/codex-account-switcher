"""Exercise switching with disposable state; never touch real account data."""
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'codex-account-switcher.sh'


class SwitchTests(unittest.TestCase):
    def test_generated_runtimes_are_not_synced_between_accounts(self):
        with tempfile.TemporaryDirectory(prefix='switcher-test-') as temporary:
            root = Path(temporary)
            store = root / 'store'
            live = root / 'live'
            auth = root / 'auth.json'
            personal = store / 'profiles/personal'
            target = store / 'profiles/work'

            def write(path, text):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)

            def runtime(base, generation):
                directory = base / 'artifact-sessions/runtime-generations' / generation
                write(directory / 'runtime/bin/node', 'dummy runtime')
                for path in sorted(directory.rglob('*'), reverse=True):
                    path.chmod(0o500 if path.is_dir() else 0o400)
                directory.chmod(0o500)
                return directory

            write(store / 'active-profile', 'personal\n')
            write(auth, 'personal auth fixture')
            write(target / 'auth/auth.json', 'work auth fixture')
            write(live / 'Preferences', 'personal preferences')
            write(target / 'app-support/Codex/Preferences', 'work preferences')
            write(live / 'obsolete-setting', 'remove on restore')
            old = runtime(personal / 'app-support/Codex', 'old-generation')
            current = runtime(live, 'current-generation')
            saved_current = runtime(personal / 'app-support/Codex', 'current-generation')
            saved_bin = saved_current / 'runtime/bin'
            saved_bin.chmod(0o700)
            write(saved_bin / 'obsolete-runtime-file', 'outdated generated file')
            saved_bin.chmod(0o500)
            runtime(target / 'app-support/Codex', 'work-generation')
            environment = dict(os.environ, SWITCHER_HOME=str(store),
                               CODEX_AUTH_FILE=str(auth), CODEX_APP_SUPPORT=str(live),
                               CODEX_APP_PATH='')
            try:
                result = subprocess.run(
                    ['/bin/bash', '-c', '''
source "$1" help >/dev/null
quit_codex() { :; }
codex_app_name() { printf 'Test Codex'; }
cmd_switch work --no-open
''', 'test', str(SCRIPT)], env=environment, text=True,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15)
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertEqual(auth.read_text(), 'work auth fixture')
                self.assertEqual((store / 'active-profile').read_text(), 'work\n')
                self.assertEqual((personal / 'auth/auth.json').read_text(), 'personal auth fixture')
                self.assertEqual((personal / 'app-support/Codex/Preferences').read_text(), 'personal preferences')
                self.assertEqual((live / 'Preferences').read_text(), 'work preferences')
                self.assertFalse((live / 'obsolete-setting').exists())
                self.assertTrue(old.exists(), 'Existing saved runtime should be left alone')
                self.assertTrue(current.exists(), 'Live runtime should be left alone')
                self.assertTrue((saved_bin / 'obsolete-runtime-file').exists())
                self.assertFalse((live / 'artifact-sessions/runtime-generations/work-generation').exists())
                self.assertEqual(stat.S_IMODE(auth.stat().st_mode), 0o600)
            finally:
                # The fixtures deliberately contain read-only directories.
                for base, directories, files in os.walk(root):
                    Path(base).chmod(0o700)
                    for name in files:
                        (Path(base) / name).chmod(0o600)


if __name__ == '__main__':
    unittest.main()
