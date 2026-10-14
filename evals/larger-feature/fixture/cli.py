"""Command line front end for the stock ledger (state is kept in a JSON file)."""
import argparse
import json
import os
import sys

import inventory


def load(path):
    if not os.path.exists(path):
        return {}
    with open(path) as f:
        return json.load(f)


def save(path, stock):
    with open(path, "w") as f:
        json.dump(stock, f, indent=2, sort_keys=True)


def main(argv=None):
    p = argparse.ArgumentParser(prog="stock")
    p.add_argument("--file", default="stock.json")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("add", "remove"):
        s = sub.add_parser(name)
        s.add_argument("item")
        s.add_argument("qty", type=int)
    sub.add_parser("total")
    args = p.parse_args(argv)
    stock = load(args.file)
    if args.cmd == "add":
        inventory.add_item(stock, args.item, args.qty)
    elif args.cmd == "remove":
        try:
            inventory.remove_item(stock, args.item, args.qty)
        except ValueError as e:
            print(e, file=sys.stderr)
            return 1
    elif args.cmd == "total":
        print(inventory.total_quantity(stock))
        return 0
    save(args.file, stock)
    return 0


if __name__ == "__main__":
    sys.exit(main())
