import io
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

from scripts import registry_tag


class RegistryTagTests(unittest.TestCase):
    def test_existing_tag(self):
        with patch("sys.argv", ["registry_tag.py", "v1.64.1-r2"]), patch.object(
            registry_tag, "urlopen", side_effect=[io.BytesIO(b'{"token":"example"}'), io.BytesIO()]
        ) as open_url:
            registry_tag.main()
        request = open_url.call_args.args[0]
        self.assertEqual(request.method, "HEAD")
        self.assertEqual(request.get_header("Authorization"), "Bearer example")

    def test_missing_tag(self):
        error = HTTPError("https://ghcr.io/", 404, "not found", {}, None)
        with patch("sys.argv", ["registry_tag.py", "v1.64.1-r2"]), patch.object(
            registry_tag, "urlopen", side_effect=[io.BytesIO(b'{"token":"example"}'), error]
        ), self.assertRaises(SystemExit) as result:
            registry_tag.main()
        self.assertEqual(result.exception.code, 3)

    def test_registry_errors_are_not_missing(self):
        for status in (401, 503):
            with self.subTest(status=status):
                error = HTTPError("https://ghcr.io/", status, "error", {}, None)
                with patch("sys.argv", ["registry_tag.py", "v1.64.1-r2"]), patch.object(
                    registry_tag, "urlopen", side_effect=[io.BytesIO(b'{"token":"example"}'), error]
                ), self.assertRaises(HTTPError) as result:
                    registry_tag.main()
                self.assertEqual(result.exception.code, status)

    def test_bad_tag_does_not_call_network(self):
        with patch("sys.argv", ["registry_tag.py", "../latest"]), patch.object(
            registry_tag, "urlopen"
        ) as open_url, self.assertRaises(SystemExit):
            registry_tag.main()
        open_url.assert_not_called()


if __name__ == "__main__":
    unittest.main()
