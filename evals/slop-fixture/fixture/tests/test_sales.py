import unittest

import sales


class Summarise(unittest.TestCase):
    def test_counts_and_totals(self):
        text = sales.summarise([{"cents": 1000}, {"cents": 2501}])
        self.assertEqual(text.splitlines()[:2], ["Orders: 2", "Revenue: $35.01"])

    def test_no_orders(self):
        self.assertEqual(sales.summarise([]).splitlines()[:2], ["Orders: 0", "Revenue: $0.00"])


if __name__ == "__main__":
    unittest.main()
