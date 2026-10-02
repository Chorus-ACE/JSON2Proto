import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("update_assets", Path(__file__).parents[1] / "update_assets.py")
update = importlib.util.module_from_spec(spec)
spec.loader.exec_module(update)


class UpdateAssetsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.published = self.root / "published"
        self.generated = self.root / "generated"
        self.published.mkdir()
        self.generated.mkdir()
        for name in update.ASSETS:
            (self.generated / f"{name}.proto").write_bytes(name.encode())
            (self.published / f"{name}.aar").write_bytes(b"original archive")
        self.snapshot = {
            "converter": "converter-commit",
            "sources": {
                locale: {"repository": repo, "commit": "upstream-commit", "files": {f"{table}.json": "blob-sha" for table in update.TABLES}}
                for locale, repo in update.REPOSITORIES.items()
            },
        }
        self.state = {"inputs": update.fingerprint(self.snapshot), "artifacts": update.artifact_hashes(self.published), "protobuf": update.protobuf_hashes(self.generated)}

    def archive(self, command, check):
        self.assertEqual(command[:2], ["aa", "archive"])
        self.assertTrue(check)
        Path(command[5]).write_bytes(b"new archive:" + Path(command[3]).read_bytes())

    def test_unchanged_and_unrelated_upstream_commits_skip(self):
        self.assertFalse(update.needs_update(self.snapshot, self.state, self.published))
        self.snapshot["sources"]["jp"]["commit"] = "commit-changing-an-unrelated-table"
        self.assertFalse(update.needs_update(self.snapshot, self.state, self.published))

    def test_source_or_converter_change_requires_conversion(self):
        changed = copy.deepcopy(self.snapshot)
        changed["sources"]["tc"]["files"]["cards.json"] = "new-blob"
        self.assertTrue(update.needs_update(changed, self.state, self.published))
        changed = copy.deepcopy(self.snapshot)
        changed["converter"] = "new-converter"
        self.assertTrue(update.needs_update(changed, self.state, self.published))

    def test_missing_state_force_and_missing_assets_require_conversion(self):
        self.assertTrue(update.needs_update(self.snapshot, None, self.published))
        self.assertTrue(update.needs_update(self.snapshot, self.state, self.published, force=True))
        (self.published / "card.aar").unlink()
        self.assertTrue(update.needs_update(self.snapshot, self.state, self.published))

    def test_identical_protobuf_does_not_recompress_or_touch_files(self):
        before = {p.name: p.stat().st_mtime_ns for p in self.published.iterdir()}
        with patch.object(update.subprocess, "run") as run:
            self.assertEqual(update.prepare_assets(self.generated, self.published, self.state), [])
            run.assert_not_called()
        self.assertEqual(before, {p.name: p.stat().st_mtime_ns for p in self.published.iterdir()})

    def test_cold_cache_compares_archive_contents_without_recompressing(self):
        with patch.object(update, "archived_protobuf_hash", side_effect=lambda archive, name: update.file_hash(self.generated / f"{name}.proto")) as extract, \
             patch.object(update.subprocess, "run") as run:
            self.assertEqual(update.prepare_assets(self.generated, self.published), [])
            self.assertEqual(extract.call_count, 4)
            run.assert_not_called()

    def test_migration_removes_raw_files_and_requires_publication(self):
        for name in update.ASSETS:
            (self.published / f"{name}.proto").write_bytes(name.encode())
        self.assertTrue(update.needs_update(self.snapshot, self.state, self.published))
        before = update.artifact_hashes(self.published)
        with patch.object(update.subprocess, "run") as run:
            self.assertEqual(update.prepare_assets(self.generated, self.published, self.state), list(update.ASSETS))
            run.assert_not_called()
        self.assertEqual(before, update.artifact_hashes(self.published))
        self.assertEqual(sorted(p.name for p in self.published.iterdir()), sorted(f"{name}.aar" for name in update.ASSETS))
        self.assertFalse(update.needs_update(self.snapshot, self.state, self.published))

    def test_only_changed_asset_is_copied_and_archived(self):
        (self.generated / "card.proto").write_bytes(b"changed cards")
        with patch.object(update.subprocess, "run", side_effect=self.archive) as run:
            self.assertEqual(update.prepare_assets(self.generated, self.published, self.state), ["card"])
            self.assertEqual(run.call_count, 1)
        self.assertEqual((self.published / "card.aar").read_bytes(), b"new archive:changed cards")
        self.assertFalse((self.published / "card.proto").exists())
        self.assertEqual((self.published / "event.aar").read_bytes(), b"original archive")

    def test_missing_and_changed_archives_are_repaired(self):
        (self.published / "card.aar").unlink()
        (self.published / "event.aar").write_bytes(b"unexpected edit")
        with patch.object(update, "archived_protobuf_hash", return_value=None), \
             patch.object(update.subprocess, "run", side_effect=self.archive):
            self.assertEqual(update.prepare_assets(self.generated, self.published, self.state), ["event", "card"])

    def test_incomplete_conversion_is_rejected_before_any_staging(self):
        (self.generated / "gacha.proto").write_bytes(b"changed gacha")
        (self.generated / "card.proto").write_bytes(b"")
        before = update.artifact_hashes(self.published)
        with patch.object(update.subprocess, "run") as run:
            with self.assertRaises(ValueError):
                update.prepare_assets(self.generated, self.published)
            run.assert_not_called()
        self.assertEqual(before, update.artifact_hashes(self.published))

    def test_source_only_changes_are_remembered_without_asset_changes(self):
        self.snapshot["sources"]["jp"]["files"]["events.json"] = "changed-ignored-json-field"
        self.assertTrue(update.needs_update(self.snapshot, self.state, self.published))
        with patch.object(update.subprocess, "run") as run:
            self.assertEqual(update.prepare_assets(self.generated, self.published, self.state), [])
            run.assert_not_called()
        snapshot_path, state_path = self.root / "snapshot.json", self.root / "state.json"
        update.write_json(snapshot_path, self.snapshot)
        update.record(argparse.Namespace(snapshot=snapshot_path, state=state_path, published=self.published, generated=self.generated))
        self.assertFalse(update.needs_update(self.snapshot, update.read_json(state_path), self.published))

    def test_record_rejects_incomplete_assets(self):
        state_path = self.root / "state.json"
        (self.published / "card.aar").unlink()
        with self.assertRaises(ValueError):
            update.record(argparse.Namespace(snapshot=self.root / "snapshot.json", state=state_path, published=self.published, generated=self.generated))
        self.assertFalse(state_path.exists())

    def test_api_snapshot_includes_only_needed_files_and_pins_commit(self):
        tree = {"tree": [{"path": f"{table}.json", "type": "blob", "sha": table} for table in update.TABLES]}
        tree["tree"].append({"path": "unrelated.json", "type": "blob", "sha": "unrelated"})
        commit = {"sha": "pinned-commit", "commit": {"tree": {"sha": "pinned-tree"}}}
        with patch.object(update, "fetch", side_effect=[json.dumps(commit), json.dumps(tree)]) as fetch:
            snapshot = update.source_snapshot("jp")
        self.assertEqual(snapshot["commit"], "pinned-commit")
        self.assertNotIn("unrelated.json", snapshot["files"])
        self.assertTrue(fetch.call_args_list[1].args[0].endswith("/git/trees/pinned-tree"))

    def test_missing_source_truncated_tree_and_network_failure_abort(self):
        commit = {"sha": "commit", "commit": {"tree": {"sha": "tree"}}}
        for tree in ({"tree": []}, {"tree": [], "truncated": True}):
            with patch.object(update, "fetch", side_effect=[json.dumps(commit), json.dumps(tree)]):
                with self.assertRaises(ValueError):
                    update.source_snapshot("jp")
        with patch.object(update, "fetch", side_effect=OSError("network failure")):
            with self.assertRaises(OSError):
                update.source_snapshot("jp")

    def test_download_uses_snapshot_commit_and_verifies_git_blob(self):
        data = b'[{"id":1}]'
        source = {"repository": "Sekai-World/example", "commit": "pinned", "files": {
            "cards.json": hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()
        }}
        destination = self.root / "input" / "cards.json"
        with patch.object(update, "fetch", return_value=data) as fetch:
            update.download_one(source, "cards.json", destination)
            self.assertIn("/pinned/cards.json", fetch.call_args.args[0])
        self.assertEqual(destination.read_bytes(), data)
        with patch.object(update, "fetch", return_value=b"wrong content"):
            with self.assertRaises(ValueError):
                update.download_one(source, "cards.json", destination)
        self.assertEqual(destination.read_bytes(), data)

    def test_check_recovers_from_corrupt_cache_and_emits_skip_output(self):
        state_path = self.root / "state.json"
        args = argparse.Namespace(state=state_path, snapshot=self.root / "snapshot.json", published=self.published, force=False)
        for cached, expected in (("broken json", True), ("[]", True), (json.dumps(self.state), False)):
            state_path.write_text(cached)
            with patch.object(update, "source_snapshot", side_effect=lambda locale: self.snapshot["sources"][locale]), \
                 patch.object(update.subprocess, "check_output", return_value="converter-commit\n"), \
                 patch.object(update, "output") as output:
                update.check(args)
                output.assert_called_once_with("changed", expected)


if __name__ == "__main__":
    unittest.main()
