import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).parent


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


aggregate = load("aggregate")
resolver = load("resolve_ruby_versions")


class ScriptTests(unittest.TestCase):
    def test_version_resolution(self):
        rows = resolver.resolve(["3.4.0", "3.4.10", "4.0.0", "4.0.6"], ["4.0", "3.4"], ["first", "latest"])
        self.assertEqual(rows[0][2], "4.0.0")
        self.assertEqual(rows[1][2], "4.0.6")
        self.assertEqual(rows[3][2], "3.4.10")

    def test_version_resolution_uses_available_docker_image(self):
        rows = resolver.resolve(["3.1.0", "3.1.7"], ["3.1"], ["latest"])
        self.assertEqual(rows[0][2], "3.1.6")
        self.assertEqual(rows[0][3], "ruby:3.1.6")

    def test_stats(self):
        self.assertEqual(aggregate.mean([1, 2, None]), 1.5)
        self.assertEqual(aggregate.median([1, 9, 3]), 3)

    def test_version_label(self):
        self.assertEqual(aggregate.parse_version("ruby4.0-latest-4.0.6"), ("4.0", "latest", "4.0.6"))


if __name__ == "__main__":
    unittest.main()
