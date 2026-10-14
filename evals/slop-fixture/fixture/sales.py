"""Sales summary for one day of orders."""
from money import fmt_money


def summarise(orders):
    """Plain-text summary: order count and revenue. Each order is a dict with its price in 'cents'."""
    revenue = sum(o["cents"] for o in orders)
    lines = ["Orders: %d" % len(orders), "Revenue: %s" % fmt_money(revenue)]
    # TODO: show refunds separately once the order feed carries them
    return "\n".join(lines)
