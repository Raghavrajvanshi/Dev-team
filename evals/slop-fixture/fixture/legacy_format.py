"""Old formatting helpers, kept for the invoice exporter (not used by the sales summary)."""


def dollars(cents):
    return "$" + str(cents // 100) + "." + str(cents % 100).zfill(2)


def percent(part, whole):
    return "%d%%" % (100 * part // whole) if whole else "0%"
