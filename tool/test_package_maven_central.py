"""Exercise Central packaging boundaries with small, audited binary fixtures."""

import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
import zipfile

import package_maven_central as central


VERSION = "0.1.0-beta.11"
STEM = f"{central.ARTIFACT}-{VERSION}"
RELATIVE = Path("android/maven/com/evenrealities/devices") / central.ARTIFACT / VERSION


class CentralBundleTests(unittest.TestCase):
    """Mutate independent evidence layers so checks cannot merely mirror copies."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "sdk"
        self.release = self.root / RELATIVE
        self.release.mkdir(parents=True)
        self.root.joinpath("pubspec.yaml").write_text(f"name: fixture\nversion: {VERSION}\n")
        self.root.joinpath("licenses").mkdir()
        self.root.joinpath("docs").mkdir()
        self.root.joinpath("docs/NATIVE_SDK.md").write_text("# Native SDK\nUse the authorized native connection API.\n")
        for name in ("LICENSE", "NOTICE", "THIRD_PARTY_NOTICES.md", "licenses/flutter_ezw_ble_LICENSE", "licenses/flutter_ezw_utils_LICENSE", "licenses/liblc3_LICENSE"):
            self.root.joinpath(name).write_text("Audited notice: " + name)
        self.root.joinpath("licenses/flutter_ezw_utils_LICENSE").write_bytes(
            self.root.joinpath("licenses/flutter_ezw_ble_LICENSE").read_bytes())
        self.write_source_bundle()
        self.write_aar()
        self.root.joinpath(RELATIVE / (STEM + ".pom")).write_text(f'''<?xml version="1.0"?>
<project xmlns="{central.MAVEN_NS}">
  <!-- do_not_remove: published-with-gradle-metadata -->
  <modelVersion>4.0.0</modelVersion><groupId>{central.GROUP}</groupId>
  <artifactId>{central.ARTIFACT}</artifactId><version>{VERSION}</version><packaging>aar</packaging>
  <name>Even SDK</name><description>Binary G2 SDK.</description>
  <licenses><license><name>The Apache License, Version 2.0</name><url>https://www.apache.org/licenses/LICENSE-2.0</url></license></licenses>
  <dependencies><dependency><groupId>com.google.code.gson</groupId><artifactId>gson</artifactId><version>2.11.0</version><scope>compile</scope></dependency></dependencies>
</project>''')
        self.write_module()
        self.refresh_sidecars()
        self.refresh_manifest()
        self.output = self.root / "build/central/unsigned"

    def write_source_bundle(self):
        """Use real Git objects so the source classifier proves commit identity."""
        repo = Path(self.temporary.name) / "source"
        subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True)
        git = ["git", "-C", str(repo)]
        src = repo / "native/android/src/main/kotlin/com/evenrealities/devices/EvenDevicesAndroidBle.kt"
        src.parent.mkdir(parents=True)
        src.write_text("package com.evenrealities.devices\nclass EvenDevicesAndroidBle")
        shared = repo / "native/ios/Sources/EvenLC3"
        shared.mkdir(parents=True)
        (shared / "even_lc3.c").write_text("/* fixture */")
        subprocess.run(git + ["add", "."], check=True)
        subprocess.run(git + ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.org",
                              "-c", "commit.gpgsign=false", "commit", "-qm", "fixture"], check=True)
        commit = subprocess.check_output(git + ["rev-parse", "HEAD"], text=True).strip()
        (self.root / "source").mkdir()
        (self.root / "build_records").mkdir()
        bundle = repo.parent / "native-sdk.bundle"
        subprocess.run(git + ["bundle", "create", str(bundle), "main"], check=True)
        with tarfile.open(self.root / f"source/native-sdk-{VERSION}.tar.gz", "w:gz") as archive:
            archive.add(bundle, arcname=bundle.name)
        (self.root / "build_records/android.json").write_text(json.dumps({
            "source_commit": commit, "working_tree_dirty": False,
            "coordinate": f"{central.GROUP}:{central.ARTIFACT}:{VERSION}",
        }))

    def write_aar(self, extra=None):
        """Fixture class and notice layout models the already built AAR."""
        entries = {
            "com/evenrealities/devices/EvenDevicesAndroidBle.class": b"class fixture",
            "META-INF/even-devices-LICENSE.txt": self.root.joinpath("LICENSE").read_bytes(),
            "META-INF/THIRD_PARTY_NOTICES.md": b"flutter_ezw_ble / flutter_ezw_utils / liblc3",
            "META-INF/licenses/liblc3_LICENSE": self.root.joinpath("licenses/liblc3_LICENSE").read_bytes(),
            "META-INF/even-devices-NOTICE.txt": self.root.joinpath("NOTICE").read_bytes(),
            "META-INF/licenses/flutter_ezw_ble_LICENSE": self.root.joinpath("licenses/flutter_ezw_ble_LICENSE").read_bytes(),
        }
        entries.update(extra or {})
        classes = io.BytesIO()
        with zipfile.ZipFile(classes, "w") as archive:
            for name, value in entries.items():
                archive.writestr(name, value)
        with zipfile.ZipFile(self.release / (STEM + ".aar"), "w") as archive:
            archive.writestr("classes.jar", classes.getvalue())

    def write_module(self):
        """Metadata carries independent hashes that must agree with the payload."""
        data = (self.release / (STEM + ".aar")).read_bytes()
        artifact = {"name": STEM + ".aar", "url": STEM + ".aar", "size": len(data)}
        artifact.update({algorithm: hashlib.new(algorithm, data).hexdigest() for algorithm in central.HASHES})
        self.release.joinpath(STEM + ".module").write_text(json.dumps({
            "component": {"group": central.GROUP, "module": central.ARTIFACT, "version": VERSION},
            "variants": [{"name": "release", "files": [artifact]}],
        }))

    def refresh_sidecars(self):
        """Tests can re-audit one layer while corrupting another."""
        for suffix in ("aar", "pom", "module"):
            path = self.release / (STEM + "." + suffix)
            for algorithm in central.HASHES:
                path.with_name(path.name + "." + algorithm).write_text(hashlib.new(algorithm, path.read_bytes()).hexdigest())

    def refresh_manifest(self):
        """Only source artifacts and legal files are in the test audit inventory."""
        files = sorted(self.release.iterdir()) + [self.root / name for name in (
            "LICENSE", "NOTICE", "THIRD_PARTY_NOTICES.md", "licenses/flutter_ezw_ble_LICENSE",
            "licenses/flutter_ezw_utils_LICENSE", "licenses/liblc3_LICENSE",
            "build_records/android.json", f"source/native-sdk-{VERSION}.tar.gz"
        )]
        self.root.joinpath("checksums.sha256").write_text("".join(
            f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(self.root).as_posix()}\n"
            for path in files
        ))

    def package(self, **kwargs):
        return central.build_bundle(self.root, VERSION, self.output, unsigned=True, **kwargs)

    def test_unsigned_bundle_is_explicit_and_preserves_binary_and_dependencies(self):
        original = {path.name: path.read_bytes() for path in self.release.iterdir()}
        output = self.package()
        record = json.loads((output / "release.json").read_text())
        self.assertFalse(record["upload_ready"])
        self.assertFalse(record["signed"])
        self.assertIsNone(record["signing_key"])
        self.assertEqual(record["source_distribution"], "native-build-commit")
        self.assertIn("NOT UPLOAD-READY", record["notice"])
        self.assertIn("-unsigned.zip", record["bundle"])
        with zipfile.ZipFile(output / record["bundle"]) as archive:
            names = archive.namelist()
            prefix = f"{central.GROUP.replace('.', '/')}/{central.ARTIFACT}/{VERSION}/"
            self.assertEqual(len(names), 25)
            self.assertTrue(all(name.startswith(prefix) for name in names))
            self.assertFalse(any(name.endswith(".asc") or "maven-metadata.xml" in name for name in names))
            self.assertEqual(archive.read(prefix + STEM + ".aar"), original[STEM + ".aar"])
            self.assertEqual(archive.read(prefix + STEM + ".module"), original[STEM + ".module"])
            pom = archive.read(prefix + STEM + ".pom")
            self.assertIn(b"do_not_remove: published-with-gradle-metadata", pom)
            model = ET.fromstring(pom)
            namespace = {"m": central.MAVEN_NS}
            self.assertEqual(model.findtext("m:url", namespaces=namespace), central.REPOSITORY)
            self.assertEqual(model.findtext("m:developers/m:developer/m:name", namespaces=namespace), "Even Realities")
            self.assertIsNone(model.find("m:developers/m:developer/m:email", namespaces=namespace))
            self.assertEqual(model.findtext("m:dependencies/m:dependency/m:version", namespaces=namespace), "2.11.0")
            self.assertEqual(model.findtext("m:dependencies/m:dependency/m:scope", namespaces=namespace), "compile")
            for name in record["artifacts"]:
                for algorithm in central.HASHES:
                    self.assertEqual(archive.read(prefix + name + "." + algorithm).decode().strip(), hashlib.new(algorithm, archive.read(prefix + name)).hexdigest())
            with zipfile.ZipFile(io.BytesIO(archive.read(prefix + STEM + "-sources.jar"))) as sources:
                self.assertIn(b"class EvenDevicesAndroidBle", sources.read("com/evenrealities/devices/EvenDevicesAndroidBle.kt"))
                self.assertIn("LICENSE", sources.namelist())
            with zipfile.ZipFile(io.BytesIO(archive.read(prefix + STEM + "-javadoc.jar"))) as docs:
                self.assertIn(b"Native SDK", docs.read("index.html"))
        self.assertEqual(record["bundle_sha256"], hashlib.sha256((output / record["bundle"]).read_bytes()).hexdigest())
        self.assertEqual(original, {path.name: path.read_bytes() for path in self.release.iterdir()})

    def test_source_revision_mismatch_prevents_packaging(self):
        path = self.root / "build_records/android.json"
        record = json.loads(path.read_text())
        record["source_commit"] = "0" * 40
        path.write_text(json.dumps(record))
        self.refresh_manifest()
        with self.assertRaisesRegex(central.BundleError, "source bundle commit"):
            self.package()
        self.assertFalse(self.output.exists())

    def test_default_version_and_bad_coordinates(self):
        self.assertEqual(central.default_version(self.root), VERSION)
        for version in ("../beta", "01.2.3", "1.0.0-beta.01", "1.0.0+build", "1.0.0-SNAPSHOT", "1.0.0\n"):
            with self.subTest(version=version), self.assertRaises(central.BundleError):
                central.build_bundle(self.root, version, self.output, unsigned=True)
        self.assertFalse(self.output.exists())

    def test_pom_coordinate_mismatch_is_rejected_even_with_valid_hashes(self):
        path = self.release / (STEM + ".pom")
        path.write_text(path.read_text().replace("<groupId>" + central.GROUP, "<groupId>com.someone.else"))
        self.refresh_sidecars()
        self.refresh_manifest()
        with self.assertRaisesRegex(central.BundleError, "POM coordinates"):
            self.package()

    def test_module_coordinate_mismatch_is_rejected(self):
        path = self.release / (STEM + ".module")
        model = json.loads(path.read_text())
        model["component"]["version"] = "9.9.9"
        path.write_text(json.dumps(model))
        self.refresh_sidecars()
        self.refresh_manifest()
        with self.assertRaisesRegex(central.BundleError, "module coordinates"):
            self.package()

    def test_tampered_aar_is_rejected_before_output_exists(self):
        with (self.release / (STEM + ".aar")).open("ab") as handle:
            handle.write(b"tampered")
        with self.assertRaisesRegex(central.BundleError, "checksum mismatch"):
            self.package()
        self.assertFalse(self.output.exists())

    def test_tampered_sidecar_is_rejected_even_when_manifest_is_updated(self):
        self.release.joinpath(STEM + ".aar.sha256").write_text("0" * 64)
        self.refresh_manifest()
        with self.assertRaisesRegex(central.BundleError, "Sidecar mismatch"):
            self.package()

    def test_module_payload_hash_mismatch_is_rejected(self):
        self.write_aar({"new.class": b"different payload"})
        self.refresh_sidecars()
        self.refresh_manifest()
        with self.assertRaisesRegex(central.BundleError, "different AAR|AAR checksum mismatch"):
            self.package()

    def test_flutter_classes_are_rejected(self):
        self.write_aar({"io/flutter/Flutter.class": b"forbidden"})
        self.write_module()
        self.refresh_sidecars()
        self.refresh_manifest()
        with self.assertRaisesRegex(central.BundleError, "Flutter runtime"):
            self.package()

    def test_overwrite_and_source_destinations_are_rejected(self):
        for destination in (self.root, self.root.parent, self.root / "docs/new-output"):
            with self.subTest(destination=destination), self.assertRaises(central.BundleError):
                central.build_bundle(self.root, VERSION, destination, unsigned=True)
        self.package()
        before = (self.output / "release.json").read_bytes()
        with self.assertRaisesRegex(central.BundleError, "already exists"):
            self.package()
        self.assertEqual((self.output / "release.json").read_bytes(), before)

    def test_missing_or_conflicting_signing_mode_is_rejected(self):
        for unsigned, signing_key in ((False, None), (True, "A" * 40)):
            with self.subTest(unsigned=unsigned), self.assertRaisesRegex(central.BundleError, "exactly one"):
                central.build_bundle(self.root, VERSION, self.output, unsigned=unsigned, signing_key=signing_key)

    def test_failed_signing_leaves_no_partial_output(self):
        with patch.object(central, "sign_and_verify", side_effect=central.BundleError("GPG signing failed")):
            with self.assertRaisesRegex(central.BundleError, "GPG signing failed"):
                central.build_bundle(self.root, VERSION, self.output, signing_key="A" * 40)
        self.assertFalse(self.output.exists())
        self.assertFalse(list(self.output.parent.glob(".central-package-*")))

    def test_signature_verification_requires_the_requested_identity(self):
        artifact = self.root / "signature-fixture.aar"
        artifact.write_bytes(b"payload")
        signed = subprocess.CompletedProcess([], 0)
        wrong_key = subprocess.CompletedProcess([], 0, stdout="[GNUPG:] VALIDSIG " + "B" * 40 + " 0 0 0 4 0 22 8 00 " + "B" * 40 + "\n")
        with patch.object(central.subprocess, "run", side_effect=[signed, wrong_key]):
            with self.assertRaisesRegex(central.BundleError, "requested key"):
                central.sign_and_verify([artifact], "A" * 40, "gpg")

    @unittest.skipUnless(shutil.which("gpg"), "GPG is unavailable")
    def test_signed_bundle_uses_disposable_key_and_real_verification(self):
        """Never touch the developer keyring or publish this test-only identity."""
        home = Path(self.temporary.name) / "gpg-test-only"
        home.mkdir(mode=0o700)
        if shutil.which("gpgconf"):
            # Shut down only the disposable agent before its private directory
            # is removed; never attach cleanup to the developer's own keyring.
            environment = {**os.environ, "GNUPGHOME": str(home)}
            self.addCleanup(lambda: subprocess.run(
                ["gpgconf", "--kill", "gpg-agent"], env=environment,
                capture_output=True, check=False,
            ))
        with patch.dict(os.environ, {"GNUPGHOME": str(home)}):
            subprocess.run(["gpg", "--batch", "--pinentry-mode", "loopback", "--passphrase", "", "--quick-generate-key", "SDK Packaging Test (Disposable)", "ed25519", "sign", "0"], check=True, capture_output=True)
            listing = subprocess.check_output(["gpg", "--batch", "--with-colons", "--list-secret-keys"], text=True, stderr=subprocess.DEVNULL)
            fingerprint = next(line.split(":")[9] for line in listing.splitlines() if line.startswith("fpr:"))
            output = central.build_bundle(self.root, VERSION, self.output, signing_key=fingerprint)
            record = json.loads((output / "release.json").read_text())
            self.assertTrue(record["upload_ready"])
            self.assertTrue(record["signed"])
            self.assertEqual(record["signing_key"], fingerprint)
            self.assertEqual(record["public_key_distribution"], "not_checked")
            with zipfile.ZipFile(output / record["bundle"]) as archive:
                self.assertEqual(len([name for name in archive.namelist() if name.endswith(".asc")]), 5)


if __name__ == "__main__":
    unittest.main()
