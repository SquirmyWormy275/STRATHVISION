"""Integrity and failure safeguards; never download or compile in unit tests."""

import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("transcription_setup", Path(__file__).with_name("setup.py"))
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class SetupSafetyTest(unittest.TestCase):
    def test_existing_corrupt_model_is_preserved_without_network(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ggml-base.bin"
            path.write_bytes(b"do not overwrite")
            with patch.object(setup.urllib.request, "urlopen") as network:
                with self.assertRaisesRegex(ValueError, "Integrity mismatch"):
                    setup.download_model(path)
            self.assertEqual(path.read_bytes(), b"do not overwrite")
            network.assert_not_called()

    def test_oversized_download_never_becomes_installed_model(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ggml-base.bin"
            with patch.object(setup, "MODEL_BYTES", 3), patch.object(
                setup.urllib.request, "urlopen", return_value=io.BytesIO(b"oversized")
            ):
                with self.assertRaisesRegex(ValueError, "exceeded"):
                    setup.download_model(path)
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_hash_mismatch_never_becomes_installed_model(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ggml-base.bin"
            with patch.object(setup, "MODEL_BYTES", 3), patch.object(
                setup.urllib.request, "urlopen", return_value=io.BytesIO(b"bad")
            ):
                with self.assertRaisesRegex(ValueError, "Integrity mismatch"):
                    setup.download_model(path)
            self.assertEqual(list(Path(directory).iterdir()), [])


if __name__ == "__main__":
    unittest.main()
