import copy
import hashlib
import io
import json
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts import stable_refresh as refresh


def manifest(version="158.0.8200.1"):
    downloads = {}
    for artifact, archive in zip(("chrome", "chrome-headless-shell"), refresh.ARCHIVES):
        downloads[artifact] = [{
            "platform": "linux64",
            "url": f"https://storage.googleapis.com/chrome-for-testing-public/{version}/linux64/{archive}",
        }]
    return {"channels": {"Stable": {"channel": "Stable", "version": version, "downloads": downloads}}}


class RefreshTests(unittest.TestCase):
    def setUp(self):
        self.dockerfile = Path("Dockerfile").read_text()

    def test_valid_stable(self):
        version, urls = refresh.stable(manifest())
        self.assertEqual(version, "158.0.8200.1")
        self.assertEqual(set(urls), set(refresh.ARCHIVES))

    def test_wrong_host_artifact_and_malformed_manifest(self):
        for replacement in ("https://evil.example/archive.zip", "https://storage.googleapis.com/chrome-for-testing-public/158.0.8200.1/linux64/other.zip"):
            item = manifest()
            item["channels"]["Stable"]["downloads"]["chrome"][0]["url"] = replacement
            with self.assertRaises(ValueError):
                refresh.stable(item)
        with self.assertRaises(KeyError):
            refresh.stable({})
        item = manifest()
        item["channels"]["Stable"]["downloads"]["chrome"].append(copy.deepcopy(item["channels"]["Stable"]["downloads"]["chrome"][0]))
        with self.assertRaises(ValueError):
            refresh.stable(item)

    def test_update_increments_revision_and_replaces_both_hashes(self):
        _, old, _ = refresh.pins(self.dockerfile)
        hashes = dict(zip(refresh.ARCHIVES, ("a" * 64, "b" * 64)))
        result = refresh.update(self.dockerfile, "158.0.8200.1", hashes)
        self.assertEqual(refresh.pins(result)[1], old.rsplit("-r", 1)[0] + "-r" + str(int(old.rsplit("-r", 1)[1]) + 1))
        self.assertEqual(refresh.pins(result)[2], "158.0.8200.1")
        self.assertIn("a" * 64, result)
        self.assertIn("b" * 64, result)
        with self.assertRaises(ValueError):
            refresh.update(result, "157.0.8103.38", hashes)

    def test_rejects_bad_hash_or_pins(self):
        for hashes in ({}, dict.fromkeys(refresh.ARCHIVES, "not-a-hash")):
            with self.assertRaises(ValueError):
                refresh.update(self.dockerfile, "158.0.8200.1", hashes)
        with self.assertRaises(ValueError):
            refresh.pins(self.dockerfile.replace("ARG RUNTIME_VERSION=1.64.1-r2", "ARG RUNTIME_VERSION=1.64.0-r2"))
        with self.assertRaises(ValueError):
            refresh.pins(self.dockerfile.replace("8cdeb344", "INVALID!"))

    def test_unchanged_stable_does_not_download_or_write(self):
        class Response(io.BytesIO):
            pass

        class Opener:
            def open(self, url, timeout):
                return Response(json.dumps(manifest(refresh.pins(self_text)[2])).encode())

        self_text = self.dockerfile
        with patch.object(refresh, "build_opener", return_value=Opener()), patch.object(refresh, "digest") as digest, patch.object(Path, "write_text") as write, patch("sys.argv", ["stable_refresh.py", "refresh"]):
            refresh.main()
        digest.assert_not_called()
        write.assert_not_called()

    def test_redirect_rejected(self):
        with self.assertRaises(ValueError):
            refresh.NoRedirect().redirect_request(None, None, 302, "", {}, "https://evil.example")

    def test_hashes_downloaded_bytes_and_rejects_truncation(self):
        data = b"PK\x03\x04" + b"archive bytes"

        class Response(io.BytesIO):
            headers = {"Content-Length": str(len(data))}

        class Opener:
            def open(self, url, timeout):
                return Response(data)

        with patch.object(refresh, "build_opener", return_value=Opener()):
            self.assertEqual(refresh.digest("https://example.invalid"), hashlib.sha256(data).hexdigest())
            Response.headers = {"Content-Length": str(len(data) + 1)}
            with self.assertRaises(ValueError):
                refresh.digest("https://example.invalid")


if __name__ == "__main__":
    unittest.main()
