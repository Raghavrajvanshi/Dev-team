use strict;
use warnings;
use FindBin;
use Test::More;
require "$FindBin::Bin/lib.pl";
our ($PLUGIN, $REPO);

# Text that is not ASCII must survive the CLI unchanged. Found live: a check command holding a single ellipsis was
# stored double-encoded, so the command that ran later compared against garbage and the goal could not pass.
sub raw { open my $h, '<:raw', $_[0] or die "$_[0]: $!"; local $/; <$h> }
my $ell = "\xE2\x80\xA6";             # U+2026 as UTF-8 bytes
my $eacute = "caf\xC3\xA9";

new_repo();
my ($rc, $out);
dt('init');
dt('engage', 's1');
dt('goal', 'new', "Export $eacute $ell");
($rc, $out) = dt('criteria', 'add', '--id', 'C1', '--text', "WHEN exported THEN $eacute ends with $ell",
    '--check', "printf '%s' '$ell$eacute' > $REPO/u.txt");
is($rc, 0, 'a criterion with non-ASCII text and check is accepted') or diag $out;

my $cj = raw("$REPO/.devteam/goals/G-001/criteria.json");
like($cj, qr/\Q$ell\E/, 'criteria.json holds the characters as UTF-8');
unlike($cj, qr/\xC3\xA2\xC2\x80/, 'and not encoded twice');
like($cj, qr/\Q$eacute\E/, 'a Latin-1 range character too');

($rc, $out) = dt('criteria', 'show');
like($out, qr/\Q$ell\E/, '`dt criteria show` prints it as UTF-8');

dt('goal', 'confirm', '--lane', 'standard', '--lifecycle', 'agile-kanban');
dt('state', 'transition', 'VERIFYING');
($rc, $out) = dt('verify');
is(raw("$REPO/u.txt"), "$ell$eacute", 'the check command that ran received the original bytes');
like($out, qr/verify: 1\/1 pass/, 'and the criterion passes') or diag $out;

($rc, $out) = dt('close');
like(raw("$REPO/.devteam/goals/G-001/closure.md"), qr/WHEN exported THEN \Q$eacute\E ends with \Q$ell\E/, 'the closure report keeps the text');
unlike(raw("$REPO/.devteam/state.json"), qr/\xC3\xA2\xC2\x80/, 'state.json (the goal title) is not double-encoded either');

# hook input is bytes too: a path with a non-ASCII name is the same string the shell and git use
my $dir = "$REPO/d$eacute";
mkdir $dir;
my ($hrc, $hout) = hook('git-guard', { session_id => 's1', cwd => $REPO, tool_name => 'Bash', tool_input => { command => "echo $ell" } });
is($hout, '', 'a hook given non-ASCII input decides without error');

done_testing;
