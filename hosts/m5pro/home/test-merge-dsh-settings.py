"""Run with the same PyYAML-enabled Python as the activation helper."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

import yaml

spec = importlib.util.spec_from_file_location(
  "merge_settings", Path(__file__).with_name("merge-dsh-settings.py")
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class MergeSettingsTest(unittest.TestCase):
  def test_merge_backup_permissions_and_idempotence(self):
    with tempfile.TemporaryDirectory() as directory:
      root = Path(directory)
      path = root / "settings.yaml"
      managed = root / "managed.json"
      managed.write_text(json.dumps({"agent-default-model": {"model": "new"}}))
      original = b"# keep backup\nother: 42\nagent-default-model:\n  model: old\n  reasoning: high\n"
      path.write_bytes(original)
      module.main(path, managed)
      self.assertEqual(yaml.safe_load(path.read_text()), {
        "other": 42, "agent-default-model": {"model": "new", "reasoning": "high"}
      })
      backups = list(root.glob("settings.yaml.pre-deploy-*"))
      self.assertEqual(len(backups), 1)
      self.assertEqual(backups[0].read_bytes(), original)
      for file in [path, backups[0]]:
        self.assertEqual(file.stat().st_mode & 0o777, 0o600)
      module.main(path, managed)
      self.assertEqual(list(root.glob("settings.yaml.pre-deploy-*")), backups)

  def test_new_file(self):
    with tempfile.TemporaryDirectory() as directory:
      root = Path(directory)
      managed = root / "managed.json"
      managed.write_text('{"agent-default-model": {"model": "new"}}')
      path = root / "nested" / "settings.yaml"
      module.main(path, managed)
      self.assertEqual(yaml.safe_load(path.read_text()), json.loads(managed.read_text()))

  def test_invalid_mapping_and_symlink_untouched(self):
    with tempfile.TemporaryDirectory() as directory:
      root = Path(directory)
      path = root / "settings.yaml"
      managed = root / "managed.json"
      managed.write_text('{"agent-default-model": {"model": "new"}}')
      for original in ["[invalid", "[]", "agent-default-model: nope"]:
        path.write_text(original)
        with self.assertRaises((ValueError, yaml.YAMLError)):
          module.main(path, managed)
        self.assertEqual(path.read_text(), original)
      path.unlink()
      path.symlink_to(managed)
      with self.assertRaises(ValueError):
        module.main(path, managed)
      self.assertTrue(path.is_symlink())


if __name__ == "__main__":
  unittest.main()
