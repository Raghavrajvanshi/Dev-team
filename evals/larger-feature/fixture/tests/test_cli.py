import io
import os
import tempfile
import unittest
from contextlib import redirect_stdout

import cli


class Cli(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.file = os.path.join(self.dir, "stock.json")

    def run_cli(self, *argv):
        out = io.StringIO()
        with redirect_stdout(out):
            code = cli.main(["--file", self.file, *argv])
        return code, out.getvalue()

    def test_add_then_total(self):
        self.run_cli("add", "pear", "3")
        self.run_cli("add", "fig", "4")
        self.assertEqual(self.run_cli("total"), (0, "7\n"))


if __name__ == "__main__":
    unittest.main()
