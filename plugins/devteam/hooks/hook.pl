#!/usr/bin/env perl
# Entry point for every devteam hook: hook.pl <handler>, hook input JSON on stdin.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use JSON::PP;
use Hooks;

my $name = shift // die "usage: hook.pl <handler>\n";
my $raw = do { local $/; <STDIN> } // '';
Hooks::dispatch($name, eval { decode_json($raw) } // {});
