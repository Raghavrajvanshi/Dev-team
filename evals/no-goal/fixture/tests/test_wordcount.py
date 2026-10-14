import unittest

from wordcount import count_words


class CountWords(unittest.TestCase):
    def test_words(self):
        self.assertEqual(count_words("one two three"), 3)


if __name__ == "__main__":
    unittest.main()
