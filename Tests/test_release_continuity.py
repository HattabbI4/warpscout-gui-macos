import subprocess
import tempfile
import unittest
from pathlib import Path
from zipfile import ZipFile


script = Path(__file__).resolve().parents[1] / ".github/scripts/verify-release-continuity.sh"


def verify_with_gh(gh, cwd=None):
    return subprocess.run(
        ["bash", "-c", 'gh() { ' + gh + '; }\nsource "$1"', "test", str(script)],
        cwd=cwd, capture_output=True, text=True,
    )


class ReleaseContinuityTests(unittest.TestCase):
    def test_only_empty_release_history_allows_bootstrap(self):
        cases = [
            ("empty history", "return 0", 0),
            ("history unavailable", "return 71", 71),
            ("published archive unavailable", 'if [[ "$2" == list ]]; then echo v1.0.0; else return 72; fi', 72),
        ]
        for label, gh, expected in cases:
            with self.subTest(label=label):
                result = verify_with_gh(gh)
                self.assertEqual(result.returncode, expected, result.stderr)

    def test_signed_zips_require_the_previous_key_for_each_architecture(self):
        gh = '''case "$1 $2" in
            "release list") echo v1.0.0 ;;
            "release download") cp "previous/$5" "$7" ;;
            *) return 2 ;;
        esac'''
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            dist = work / "dist"
            previous = work / "previous"
            dist.mkdir()
            previous.mkdir()

            def write_previous_key(arch, public_key):
                with ZipFile(previous / f"WarpScout-macOS-{arch}.zip", "w") as archive:
                    archive.writestr("WarpScout.app/Contents/Resources/UpdatePublicKey", public_key)

            keys = {}
            for arch in ("arm64", "x86_64"):
                private_key = work / f"{arch}.pem"
                subprocess.run(["openssl", "genpkey", "-algorithm", "ED25519", "-out", private_key], check=True)
                public_der = subprocess.check_output(["openssl", "pkey", "-in", private_key, "-pubout", "-outform", "DER"])
                keys[arch] = public_der[-32:]
                write_previous_key(arch, keys[arch])
                candidate = dist / f"WarpScout-macOS-{arch}.zip"
                with ZipFile(candidate, "w") as archive:
                    archive.writestr("WarpScout.app/Contents/MacOS/WarpScout", arch)
                subprocess.run(["openssl", "pkeyutl", "-sign", "-rawin", "-inkey", private_key,
                                "-in", candidate, "-out", str(candidate) + ".sig"], check=True)

            result = verify_with_gh(gh, work)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for arch, other in (("x86_64", "arm64"), ("arm64", "x86_64")):
                with self.subTest(arch=arch):
                    write_previous_key(arch, keys[other])
                    result = verify_with_gh(gh, work)
                    self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                    write_previous_key(arch, keys[arch])
