"""A tiny stock ledger: item name -> quantity on hand."""


def add_item(stock, name, qty):
    """Add qty units of name (creating the item when it is new)."""
    stock[name] = stock.get(name, 0) + qty


def remove_item(stock, name, qty):
    """Take qty units of name out; raises ValueError when there are not enough."""
    have = stock.get(name, 0)
    if qty > have:
        raise ValueError("only %d of %s in stock" % (have, name))
    stock[name] = have - qty


def total_quantity(stock):
    """Units on hand across every item."""
    return sum(stock.values())
