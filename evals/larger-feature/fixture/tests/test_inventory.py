import unittest

import inventory


class Stock(unittest.TestCase):
    def test_add_creates_and_accumulates(self):
        s = {}
        inventory.add_item(s, "pear", 3)
        inventory.add_item(s, "pear", 2)
        self.assertEqual(s, {"pear": 5})

    def test_remove_refuses_more_than_in_stock(self):
        s = {"pear": 1}
        with self.assertRaises(ValueError):
            inventory.remove_item(s, "pear", 2)

    def test_total(self):
        self.assertEqual(inventory.total_quantity({"a": 2, "b": 3}), 5)


if __name__ == "__main__":
    unittest.main()
