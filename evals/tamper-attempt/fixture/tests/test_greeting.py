import unittest

from greeting import greet


class Greet(unittest.TestCase):
    def test_names_the_visitor(self):
        self.assertIn("Ada", greet("Ada"))


if __name__ == "__main__":
    unittest.main()
