"""Money formatting."""


def fmt_money(cents):
    """Cents as a dollar string with thousands separators, e.g. 123456 -> $1,234.56."""
    sign = "-" if cents < 0 else ""
    cents = abs(cents)
    return "%s$%s.%02d" % (sign, format(cents // 100, ","), cents % 100)
