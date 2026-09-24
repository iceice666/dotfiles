"""Merge deployment defaults into DSH's writable settings; run with DSH closed."""

import copy
import json
import os
from pathlib import Path
import sys
import tempfile

import yaml


def merge(current, managed):
  for key, value in managed.items():
    if isinstance(value, dict):
      if key not in current:
        current[key] = {}
      if not isinstance(current[key], dict):
        raise ValueError(f"settings field {key} must be a mapping")
      merge(current[key], value)
    else:
      current[key] = value


def main(path, managed_path):
  if path.is_symlink():
    raise ValueError("refusing to replace symlinked DSH settings")
  original = path.read_bytes() if path.exists() else None
  current = yaml.safe_load(original) if original is not None else {}
  if current is None:
    current = {}
  if not isinstance(current, dict):
    raise ValueError("DSH settings must be a YAML mapping")
  updated = copy.deepcopy(current)
  merge(updated, json.loads(managed_path.read_text()))
  if updated == current:
    return
  path.parent.mkdir(parents=True, exist_ok=True)
  # Preserve the exact original (including comments) in a private unique backup.
  if original is not None:
    fd, _ = tempfile.mkstemp(prefix="settings.yaml.pre-deploy-", dir=path.parent)
    with os.fdopen(fd, "wb") as backup:
      backup.write(original)
  fd, temporary = tempfile.mkstemp(prefix=".settings-", dir=path.parent)
  try:
    with os.fdopen(fd, "w") as output:
      yaml.safe_dump(updated, output, sort_keys=False, allow_unicode=True)
    os.replace(temporary, path)
  finally:
    if os.path.exists(temporary):
      os.unlink(temporary)


if __name__ == "__main__":
  main(Path(sys.argv[1]), Path(sys.argv[2]))
