"""Test logic chọn service bằng Git repo tạm, không build image hay kết nối EC2."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SELECTOR = Path(__file__).resolve().parents[1] / 'select-services.py'
CATALOG = SELECTOR.with_name('images.tsv').read_text()
ALL = {line.split()[0] for line in CATALOG.splitlines() if line.strip()}
JAVA = {'ledgerwriter', 'balancereader', 'transactionhistory'}


class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.git('init', '-q')
        self.git('config', 'user.email', 'ci-test@example.invalid')
        self.git('config', 'user.name', 'CI test')
        self.write('scripts/ci/images.tsv', CATALOG)
        for line in CATALOG.splitlines():
            self.write(line.split()[2] + '/example.txt', 'original')
        self.write('README.md', 'original')
        self.base = self.commit()

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.repo).decode().strip()

    def write(self, path, content):
        dest = self.repo / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content)

    def commit(self):
        self.git('add', '.')
        self.git('commit', '-qm', 'fixture')
        return self.git('rev-parse', 'HEAD')

    def select(self, base=None, force=False):
        subprocess.run(['python3', str(SELECTOR)], cwd=self.repo, check=True,
                       env={**os.environ, 'BASE_COMMIT': self.base if base is None else base,
                            'FORCE_ALL': str(force).lower()}, capture_output=True)
        return {line.split()[0] for line in
                (self.repo / 'reports/selected-services.tsv').read_text().splitlines()}

    def test_first_build(self):
        self.assertEqual(self.select(base=''), ALL)

    def test_same_commit(self):
        self.assertEqual(self.select(), set())

    def test_frontend_only(self):
        self.write('src/frontend/frontend.py', '# changed'); self.commit()
        self.assertEqual(self.select(), {'frontend'})

    def test_multiple_commits_since_success(self):
        self.write('src/frontend/frontend.py', '# changed'); self.commit()
        self.write('src/accounts/contacts/contacts.py', '# changed'); self.commit()
        self.assertEqual(self.select(), {'frontend', 'contacts'})

    def test_rename_between_services(self):
        self.git('mv', 'src/frontend/example.txt', 'src/accounts/contacts/moved.txt')
        self.commit()
        self.assertEqual(self.select(), {'frontend', 'contacts'})

    def test_deleted_file(self):
        self.git('rm', 'src/accounts/userservice/example.txt'); self.commit()
        self.assertEqual(self.select(), {'userservice'})

    def test_maven_config(self):
        self.write('.mvn/wrapper/maven-wrapper.properties', 'changed'); self.commit()
        self.assertEqual(self.select(), JAVA)

    def test_python_config(self):
        self.write('.pylintrc', 'changed'); self.commit()
        self.assertEqual(self.select(), {'frontend', 'contacts', 'userservice'})

    def test_pipeline_change(self):
        self.write('Jenkinsfile', 'changed'); self.commit()
        self.assertEqual(self.select(), ALL)

    def test_docs_only(self):
        self.write('README.md', 'changed'); self.commit()
        self.assertEqual(self.select(), set())

    def test_unknown_config(self):
        self.write('shared-config.json', '{}'); self.commit()
        self.assertEqual(self.select(), ALL)

    def test_missing_baseline(self):
        self.assertEqual(self.select(base='f' * 40), ALL)

    def test_force_all(self):
        self.assertEqual(self.select(force=True), ALL)


if __name__ == '__main__':
    unittest.main()
