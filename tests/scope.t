use strict;
use warnings;
use FindBin;
use JSON::PP;
use Test::More;
require "$FindBin::Bin/lib.pl";
our $REPO;
use lib "$FindBin::Bin/../plugins/devteam/lib";
use DT::Scope;

# Writes outside the task's allowed files are surfaced, whoever made them, and never closed over silently.
new_repo();
my ($rc, $out);

# --- allowed-file patterns ---
my @cases = (
    ['src/a.js', 'src/a.js', 1], ['src/a.js', 'src/', 1], ['src/a.js', 'src', 1], ['src/deep/a.js', 'src/', 1],
    ['src/a.js', 'tests/', 0], ['srcx/a.js', 'src', 0], ['src/a.js', 'src/*.js', 1], ['src/deep/a.js', 'src/*.js', 0],
    ['src/deep/a.js', 'src/**/*.js', 1], ['a.txt', './a.txt', 1], ['src/a.js', 'src/?.js', 1], ['src/ab.js', 'src/?.js', 0],
    ['README.md', 'src/**', 0],
);
is(DT::Scope::matches($_->[0], $_->[1]) ? 1 : 0, $_->[2], "pattern '$_->[1]' vs $_->[0]") for @cases;

dt('init');
sh('mkdir -p src tests && echo pre > pre.txt');
dt('goal', 'new', 'scoped');
dt('criteria', 'add', '--id', 'C1', '--text', 'WHEN x THEN y', '--check', 'true');
dt('goal', 'confirm', '--lane', 'standard', '--lifecycle', 'agile-kanban');

($rc, $out) = dt('scope', 'check');
is($rc, 0, 'no scope yet: nothing to check');
like($out, qr/no scope set/, 'and it says so');
($rc, $out) = dt('scope', 'start', 'T1');
isnt($rc, 0, 'start needs allowed files');

($rc, $out) = dt('scope', 'start', 'T1', 'src/', 'tests/greet.t');
is($rc, 0, 'scope start') or diag $out;

# dirt that existed before the task is not the task's doing
($rc, $out) = dt('scope', 'check');
is($rc, 0, 'untouched tree is clean (the pre-existing untracked file is the baseline)') or diag $out;

sh('echo ok > src/greet.js && echo t > tests/greet.t');
($rc, $out) = dt('scope', 'check');
is($rc, 0, 'writes to allowed files are in scope') or diag $out;
like($out, qr/in scope/, 'and it says so');

sh('echo oops > README.md');
($rc, $out) = dt('scope', 'check');
is($rc, 1, 'a write outside the allowed files is reported');
like($out, qr/OUT OF SCOPE: 1.*README\.md.*writer unknown/s, 'with the path and an honest "writer unknown"');
unlike($out, qr/^  \S*greet/m, 'allowed files are not in the out-of-scope list');

sh('echo changed >> pre.txt');
($rc, $out) = dt('scope', 'check');
like($out, qr/OUT OF SCOPE: 2.*pre\.txt/s, 'editing a file that was already dirty at the start is caught');

# another session's write is attributed when our hooks saw it
dt('engage', 'S1');
hook('state-protect', { session_id => 'S2', hook_event_name => 'PreToolUse', tool_name => 'Write', tool_input => { file_path => "$REPO/notes.txt" } });
sh('echo n > notes.txt');
($rc, $out) = dt('scope', 'check');
like($out, qr/notes\.txt  written by another session \(S2 at /, 'a write our hooks saw another session make is attributed');
like($out, qr/README\.md  writer unknown/, 'others stay "writer unknown"');

# committed changes are still found: the base is the commit at task start
sh('git add -A && git commit -q -m "stray work"');
($rc, $out) = dt('scope', 'check');
like($out, qr/OUT OF SCOPE: 3.*README\.md.*notes\.txt.*pre\.txt/s, 'committing the stray files does not hide them');
like($out, qr/^  (?!src)/m, 'and only the stray ones are listed');

# nothing closes, and the next task cannot start, until the user has decided
dt('state', 'transition', 'VERIFYING');
($rc, $out) = dt('close');
isnt($rc, 0, 'close refuses while out-of-scope writes are unresolved');
like($out, qr/outside the task's scope are unresolved: .*README\.md/, 'and names them');
($rc, $out) = dt('close', '--accept-partial', '--reason', 'good enough', '--by', 'user');
isnt($rc, 0, 'a partial close cannot step over them either');
dt('state', 'transition', 'ACTIVE');
($rc, $out) = dt('scope', 'start', 'T2', 'src/');
isnt($rc, 0, 'the next task cannot start over them');
like($out, qr/still unresolved/, 'and the reason is given');
($rc, $out) = dt('status');
like($out, qr/scope T1: 3 unresolved out-of-scope write/, 'status shows it');

# the user keeps them
($rc, $out) = dt('scope', 'accept');
isnt($rc, 0, 'accept needs paths or --all');
($rc, $out) = dt('scope', 'accept', 'README.md');
is($rc, 0, 'accept one path') or diag $out;
($rc, $out) = dt('scope', 'check');
like($out, qr/OUT OF SCOPE: 2/, 'one fewer is reported');
($rc, $out) = dt('scope', 'accept', '--all');
is($rc, 0, 'accept --all') or diag $out;
($rc, $out) = dt('scope', 'check');
is($rc, 0, 'all resolved') or diag $out;
dt('state', 'transition', 'VERIFYING');
($rc, $out) = dt('close');
is($rc, 0, 'close goes through once every write is resolved') or diag $out;
my $ledger = do { local (@ARGV, $/) = "$REPO/.devteam/log.jsonl"; <> };
like($ledger, qr/"event":"scope_accept"/, 'the decision is in the ledger');

# a scoped task after a clean one starts from the current state
dt('goal', 'new', 'second');
dt('criteria', 'add', '--id', 'C1', '--text', 'WHEN x THEN y', '--check', 'true');
dt('goal', 'confirm', '--lane', 'standard', '--lifecycle', 'agile-kanban');
($rc, $out) = dt('scope', 'check');
like($out, qr/no scope set/, 'a new goal starts without a scope');

done_testing();
