import hashlib
import http.server
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import ssl
import subprocess
import sys
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "installer.sh"


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.user_home = self.root / "user-home"
        self.user_home.mkdir()
        self.env = dict(os.environ, HOME=str(self.user_home),
                        PATH=str(self.bin) + ":/usr/bin:/bin",
                        TEST_ROOT=str(self.root), TEST_SCRIPT=str(SCRIPT),
                        TEST_SCENARIO="success", TEST_PLATFORM="Linux")
        self.write_program("java", 'import sys; print(\'openjdk version "21.0.12"\', file=sys.stderr)')
        self.write_program("uname", 'import os; print(os.environ["TEST_PLATFORM"])')
        for name in ("sha256sum", "shasum"):
            self.write_program(name, 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest() + "  -")')
        self.write_program("jq", '''
import json, sys
try:
    value = json.load(sys.stdin)["tag_name"]
    if not isinstance(value, str) or not value: raise ValueError()
    print(value)
except (ValueError, KeyError):
    sys.exit(1)
''')
        self.write_program("tar", '''
import os, pathlib, sys
root = pathlib.Path(os.environ["TEST_ROOT"])
(root / "extracted").touch()
if os.environ["TEST_SCENARIO"] == "extract-error": sys.exit(2)
archive = pathlib.Path(sys.argv[sys.argv.index("-xf") + 1])
assert archive.read_bytes() == b"complete-archive"
destination = pathlib.Path(sys.argv[sys.argv.index("-C") + 1])
binary = destination / "web3j-shadow-5.0.3/bin/web3j"
binary.parent.mkdir(parents=True)
binary.write_text("#!/bin/sh\\nexit 0\\n")
binary.chmod(0o755)
''')
        self.write_program("curl", '''
import hashlib, json, os, pathlib, sys
args = sys.argv[1:]
root = pathlib.Path(os.environ["TEST_ROOT"])
with (root / "requests.jsonl").open("a") as log: log.write(json.dumps(args) + "\\n")
script = pathlib.Path(os.environ["TEST_SCRIPT"]).read_bytes()
if args == ["-sSfL", "https://get.web3j.io"]:
    sys.stdout.buffer.write(script)
    sys.exit(0)
required = ["--disable", "--proto", "=https", "--proto-redir", "=https",
            "--fail", "--show-error", "--silent", "--location"]
assert args[:len(required)] == required, args
url = next(a for a in args if a.startswith("https://"))
scenario = os.environ["TEST_SCENARIO"]
digest = hashlib.sha256(b"".join(line for line in script.splitlines(keepends=True)
                                if not line.startswith(b"CHECKSUM_URL="))).hexdigest()
if url.endswith("checksum-linux.txt"):
    if scenario == "checksum-error": sys.exit(22)
    payload = ("" if scenario == "empty-checksum" else "0"*64 if scenario == "wrong-checksum" else digest).encode()
elif url == "https://get.web3j.io":
    if scenario == "bootstrap-error": sys.exit(22)
    payload = script
elif url.endswith("/releases/latest"):
    if scenario == "metadata-error": sys.exit(22)
    payload = json.dumps({"tag_name": "v1/../../escape" if scenario == "bad-tag" else "v5.0.3"}).encode()
elif url.endswith(".tar"):
    payload = b"partial" if scenario == "archive-error" else b"complete-archive"
else:
    raise AssertionError(url)
if "--output" in args:
    pathlib.Path(args[args.index("--output") + 1]).write_bytes(payload)
else:
    sys.stdout.buffer.write(payload)
if scenario == "archive-error" and url.endswith(".tar"): sys.exit(18)
''')

    def write_program(self, name, body):
        program = self.bin / name
        program.write_text("#!" + sys.executable + "\n" + body + "\n")
        program.chmod(0o755)

    def run_installer(self, scenario="success", piped=False):
        self.env["TEST_SCENARIO"] = scenario
        return subprocess.run(["sh"] if piped else ["sh", str(SCRIPT)],
                              input=SCRIPT.read_text() if piped else None,
                              text=True, capture_output=True, cwd=self.root,
                              env=self.env, timeout=20)

    def test_success_downloads_before_extracting(self):
        for platform in ("Linux", "Darwin"):
            with self.subTest(platform=platform):
                self.env["TEST_PLATFORM"] = platform
                result = self.run_installer()
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertTrue((self.user_home / ".web3j/web3j").is_symlink())
                self.assertFalse(list((self.user_home / ".web3j").glob("download.*")))
                shutil.rmtree(self.user_home / ".web3j")
                (self.root / "extracted").unlink()

    def test_documented_command_downloads_and_verifies_a_complete_file(self):
        command = (ROOT / "README.md").read_text().split("```sh\n", 1)[1].split("```", 1)[0]
        result = subprocess.run(["sh", "-c", command], text=True, capture_output=True,
                                cwd=self.root, env=self.env, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.user_home / ".web3j/web3j").is_symlink())
        requests = [json.loads(line) for line in (self.root / "requests.jsonl").read_text().splitlines()]
        self.assertIn("https://get.web3j.io", requests[1])
        self.assertIn("--output", requests[1])

    def test_failures_never_extract_or_replace_existing_files(self):
        for scenario in ("checksum-error", "empty-checksum", "wrong-checksum",
                         "metadata-error", "bad-tag", "archive-error"):
            with self.subTest(scenario=scenario):
                existing = self.user_home / ".web3j/source.sh"
                existing.parent.mkdir(exist_ok=True)
                existing.write_text("existing installation")
                result = self.run_installer(scenario)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse((self.root / "extracted").exists())
                self.assertEqual(existing.read_text(), "existing installation")
                self.assertFalse(list(existing.parent.glob("download.*")))

    def test_pipe_download_failure_stops(self):
        result = self.run_installer("bootstrap-error", piped=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "extracted").exists())

    def test_extraction_error_stops_before_completion(self):
        result = self.run_installer("extract-error")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("successfully installed", result.stdout)
        self.assertFalse((self.user_home / ".web3j/web3j").exists())

    def test_committed_checksum_matches_script_bytes(self):
        content = b"".join(line for line in SCRIPT.read_bytes().splitlines(keepends=True)
                           if not line.startswith(b"CHECKSUM_URL="))
        self.assertEqual(hashlib.sha256(content).hexdigest(),
                         (ROOT / "checksum-linux.txt").read_text().strip())

    def test_immutable_checksum_pin_matches_the_committed_checksum(self):
        match = re.search(r'^CHECKSUM_URL="https://raw.githubusercontent.com/LFDT-web3j/web3j-installer/([a-f0-9]{40})/checksum-linux.txt"$',
                          SCRIPT.read_text(), re.MULTILINE)
        self.assertIsNotNone(match, "Checksum URL must pin an immutable commit")
        pinned = subprocess.check_output(["git", "show", match.group(1) + ":checksum-linux.txt"],
                                         cwd=ROOT, text=True).strip()
        self.assertEqual(pinned, (ROOT / "checksum-linux.txt").read_text().strip())


class CurlTransportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        cls.cert = cls.root / "cert.pem"
        key = cls.root / "key.pem"
        config = cls.root / "openssl.cnf"
        config.write_text("[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n"
                          "[dn]\nCN=localhost\n[ext]\nsubjectAltName=DNS:localhost\n")
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                        "-days", "1", "-config", str(config), "-keyout", str(key),
                        "-out", str(cls.cert)], check=True, capture_output=True)

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path == "/downgrade":
                    self.send_response(302)
                    self.send_header("Location", "http://localhost:" + str(self.server.server_port) + "/ok")
                    self.end_headers()
                elif self.path == "/missing":
                    self.send_error(404)
                else:
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(b"complete-download")

            def log_message(self, *args):
                pass

        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cls.cert, key)
        cls.server.socket = context.wrap_socket(cls.server.socket, server_side=True)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        text = SCRIPT.read_text()
        cls.helper = text[text.index("fetch_https()"):text.index("fetch_checksum()")]

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()
        cls.temp.cleanup()

    def fetch(self, scheme, path):
        output = self.root / "download"
        output.unlink(missing_ok=True)
        url = f"{scheme}://localhost:{self.server.server_port}/{path}"
        command = self.helper + "\nfetch_https --cacert " + shlex.quote(str(self.cert))
        command += " --output " + shlex.quote(str(output)) + " " + shlex.quote(url)
        result = subprocess.run(["sh", "-c", command], capture_output=True, text=True, timeout=10)
        return result, output

    def test_valid_https_succeeds(self):
        result, output = self.fetch("https", "ok")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output.read_bytes(), b"complete-download")

    def test_initial_http_is_rejected(self):
        result, _ = self.fetch("http", "ok")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("disabled", result.stderr.lower())

    def test_https_to_http_redirect_is_rejected(self):
        result, _ = self.fetch("https", "downgrade")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("disabled", result.stderr.lower())

    def test_http_error_is_rejected(self):
        result, _ = self.fetch("https", "missing")
        self.assertEqual(result.returncode, 22)


if __name__ == "__main__":
    unittest.main()

