use strict;
use warnings;
use FindBin;
use Test::More;
require "$FindBin::Bin/lib.pl";
our $REPO;

new_repo();
my ($rc, $out);

($rc, $out) = dt('state');
isnt($rc, 0, 'commands refuse to run before init');
($rc, $out) = dt('init');
is($rc, 0, 'init');
is(state()->{status}, 'IDLE', 'starts IDLE');

($rc, $out) = dt('preflight');
is($rc, 0, 'preflight passes in a clean repo') or diag $out;
like($out, qr/warn gates/, 'gates reported as not configured');
$ENV{DT_CLAUDE_VERSION} = '2.1.289';
($rc, $out) = dt('preflight');
is($rc, 1, 'preflight fails on an old Claude Code');
like($out, qr/FAIL claude-version.*2\.1\.289/, 'names the version problem');
$ENV{DT_CLAUDE_VERSION} = '2.1.295';
sh('echo dirty > b.txt');
($rc, $out) = dt('preflight');
is($rc, 1, 'preflight fails on a dirty tree');
sh('rm b.txt');

# --- goal lifecycle ---
($rc, $out) = dt('goal', 'new', 'Add', 'greeting');
is($rc, 0, 'goal new') or diag $out;
is(state()->{status}, 'INTAKE', 'INTAKE after goal new');
is(state()->{goal}, 'G-001', 'first goal id');
($rc, $out) = dt('goal', 'new', 'again');
isnt($rc, 0, 'cannot start a second goal');
($rc, $out) = dt('goal', 'confirm', '--lane', 'standard', '--lifecycle', 'agile-kanban');
isnt($rc, 0, 'cannot confirm without a done-criterion');
like($out, qr/at least one done-criterion/, 'says why');

dt('criteria', 'add', '--id', 'C1', '--text', 'WHEN a.txt exists THEN it says hi', '--check', 'grep -q hi a.txt');
dt('criteria', 'add', '--id', 'C2', '--type', 'manual', '--text', 'WHEN a user reads it THEN it feels friendly');
($rc, $out) = dt('criteria', 'add', '--id', 'C3', '--text', 'no check given');
isnt($rc, 0, 'cmd criterion needs a check');

($rc, $out) = dt('goal', 'confirm', '--lane', 'huge', '--lifecycle', 'agile-kanban');
isnt($rc, 0, 'rejects unknown lane');
($rc, $out) = dt('goal', 'confirm', '--lane', 'standard', '--lifecycle', 'nope');
isnt($rc, 0, 'rejects unknown lifecycle');
($rc, $out) = dt('goal', 'confirm', '--lane', 'standard', '--lifecycle', 'agile-kanban', '--grants', 'integration,restore');
is($rc, 0, 'confirm') or diag $out;
my $s = state();
is($s->{status}, 'ACTIVE', 'ACTIVE after confirm');
is($s->{spawn_cap}, 7, 'standard spawn cap');
ok($s->{git_grants}{integration} && $s->{git_grants}{restore}, 'grants recorded');

# --- branch handling ---
($rc, $out) = dt('branch', 'start');
is($rc, 0, 'branch start') or diag $out;
is(state()->{integration_branch}, 'devteam/G-001', 'integration branch recorded');
is(state()->{original_branch}, 'main', 'original branch recorded');

# --- locks and verify ---
sh('echo "test" > t.txt && git add t.txt && git commit -q -m t');
dt('criteria', 'lock', 't.txt');
($rc, $out) = dt('verify');
isnt($rc, 0, 'verify fails while a manual criterion is open');
like($out, qr/awaiting confirmation: C2/, 'lists pending manual criteria');
dt('criteria', 'confirm', 'C2', '--by', 'user');
($rc, $out) = dt('verify');
is($rc, 0, 'verify passes once all are confirmed') or diag $out;
sh('echo weakened > t.txt');
($rc, $out) = dt('verify');
isnt($rc, 0, 'editing a locked file fails verification');
like($out, qr/LOCK_VIOLATION: t\.txt/, 'names the locked file');
sh('git checkout -q t.txt');

# --- gates, cached by tree hash ---
($rc, $out) = dt('gate', 'run');
like($out, qr/not configured/, 'no gates configured');
sh(qq{perl -MJSON::PP -e 'open F,"<.devteam/config.json";local \$/;\$c=decode_json(<F>);\$c->{gates}{test}="echo ran >> .devteam/runs.txt";open O,">.devteam/config.json";print O encode_json(\$c)'});
dt('resync');
dt('gate', 'run', '--full');
dt('gate', 'run', '--full');
($rc, $out) = sh('wc -l < .devteam/runs.txt');
is($out + 0, 1, 'the second identical run was served from the cache');
sh('echo change >> a.txt');
dt('gate', 'run', '--full');
($rc, $out) = sh('wc -l < .devteam/runs.txt');
is($out + 0, 2, 'a changed tree reruns the gate');
sh('git checkout -q a.txt');

# --- close gate ---
($rc, $out) = dt('close');
isnt($rc, 0, 'close refuses unless VERIFYING');
dt('state', 'transition', 'VERIFYING');
($rc, $out) = dt('close');
is($rc, 0, 'close succeeds when everything is verified') or diag $out;
is(state()->{status}, 'IDLE', 'back to IDLE after ACHIEVED');
ok(-f "$REPO/.devteam/goals/G-001/closure.md", 'closure report written');
($rc, $out) = dt('state', 'transition', 'ACHIEVED');
isnt($rc, 0, 'ACHIEVED cannot be set by hand');
($rc, $out) = dt('branch', 'finish');
is($rc, 0, 'branch finish') or diag $out;
like(`cd $REPO && git rev-parse --abbrev-ref HEAD`, qr/^main/, 'original branch restored');

# --- tamper detection ---
sh(q{sed -i.bak 's/"IDLE"/"ACTIVE"/' .devteam/state.json});
($rc, $out) = dt('status');
like($out, qr/TAMPER/, 'status reports edits made outside dt');
dt('resync');
($rc, $out) = dt('status');
unlike($out, qr/TAMPER/, 'resync accepts the current contents');

# --- state transitions ---
sh(q{sed -i.bak 's/"ACTIVE"/"IDLE"/' .devteam/state.json}); dt('resync');
sh('rm -f .devteam/state.json.bak');
($rc, $out) = dt('state', 'transition', 'VERIFYING');
isnt($rc, 0, 'IDLE -> VERIFYING is illegal');
($rc, $out) = dt('state', 'transition', 'BLOCKED');
isnt($rc, 0, 'BLOCKED needs a reason');

# --- lifecycle suggestion ---
sub suggest { my (undef, $o) = dt('lifecycle', 'suggest', @_); $o }
like(suggest(qw(--size tiny)), qr/recommended: direct/, 'tiny -> direct');
like(suggest(qw(--size standard --delivery maintenance)), qr/recommended: agile-kanban/, 'maintenance -> kanban');
like(suggest(qw(--size large --requirements evolving --delivery product)), qr/recommended: agile-scrum/, 'large evolving product -> scrum');
like(suggest(qw(--size standard --requirements stable --risk normal --delivery project --ops no)), qr/recommended: waterfall/, 'fixed spec -> waterfall');
my $o = suggest(qw(--size standard --risk regulated));
like($o, qr/note: v-model fits best but is not installed/, 'notes an uninstalled best fit');
like($o, qr/recommended: (?:waterfall|agile-kanban)/, 'falls back to an installed profile');
like(suggest(qw(--size standard)), qr/runner-up:/, 'offers a runner-up');

# --- models ---
($rc, $out) = dt('models', 'set', 'fullstack-engineer,qa-engineer', '--model', 'opus', '--effort', 'high');
is($rc, 0, 'models set');
($rc, $out) = dt('models', 'get', 'qa-engineer');
like($out, qr/model=opus effort=high changed=yes/, 'custom setting reported as changed');
($rc, $out) = dt('models', 'get', 'reviewer');
like($out, qr/changed=no/, 'untouched member reported as recommended');
($rc, $out) = dt('models', 'set', 'reviewer', '--model', 'gpt');
isnt($rc, 0, 'rejects unknown model');
dt('models', 'set', 'qa-engineer', '--model', 'recommended', '--effort', 'recommended');
($rc, $out) = dt('models', 'get', 'qa-engineer');
like($out, qr/changed=no/, 'recommended restores the default');

# --- lane change ---
($rc, $out) = dt('goal', 'lane', 'large');
is($rc, 1, 'cannot re-lane without a running goal');

# --- criteria edit/remove, gate set, queue, board ---
dt('goal', 'new', 'second goal');
ok(-f "$REPO/.devteam/goals/G-002/board.md", 'a new goal gets a board');
dt('criteria', 'add', '--id', 'C1', '--text', 'WHEN a THEN b', '--check', 'true');
($rc, $out) = dt('goal', 'lane', 'large');
is($rc, 0, 'lane can be changed during intake');
is(state()->{spawn_cap}, 20, 'and the caps follow it');
($rc, $out) = dt('criteria', 'edit', 'C1', '--text', 'WHEN c THEN d');
is($rc, 0, 'criteria edit');
($rc, $out) = dt('criteria', 'show');
like($out, qr/WHEN c THEN d/, 'edit applied');
($rc, $out) = dt('criteria', 'remove', 'C9');
isnt($rc, 0, 'removing an unknown criterion fails');
($rc, $out) = dt('criteria', 'remove', 'C1');
is($rc, 0, 'criteria remove');
($rc, $out) = dt('gate', 'set', 'test=make test', 'timeout=60');
is($rc, 0, 'gate set');
($rc, $out) = dt('gate', 'set', 'bogus=1');
isnt($rc, 0, 'gate set rejects unknown keys');
dt('queue', 'add', 'fix the footer');
dt('queue', 'add', 'second');
($rc, $out) = dt('queue');
like($out, qr/1\. fix the footer\n2\. second/, 'queue lists in order');
($rc, $out) = dt('queue', 'pop');
is($out, "fix the footer\n", 'pop returns the first');

# --- setup completeness shows up in status ---
($rc, $out) = dt('status');
like($out, qr/setup: incomplete \(no project profile; no standards\)/, 'status names the missing profile and standards');
dt('models', 'choose');
sh('printf "# profile\\n" > .devteam/profile.md && printf "source-hash: none\\n" > .devteam/standards.md');
($rc, $out) = dt('status');
like($out, qr/setup: complete/, 'and reports complete once models are chosen and profile and standards exist');

# --- local ignore: the tree stays clean and the tracked .gitignore is never touched ---
($rc, $out) = dt('gitignore');
is($rc, 0, 'gitignore runs');
like(slurp_file("$REPO/.git/info/exclude"), qr{^\.devteam/$}m, 'entries go to .git/info/exclude');
ok(!-e "$REPO/.gitignore", 'the tracked .gitignore is not created or changed');
($rc, $out) = dt('gitignore');
like($out, qr/already ignored/, 'gitignore is idempotent');
sh('mkdir -p .claude && echo "{}" > .claude/settings.local.json && mkdir -p .devteam/x');
($rc, $out) = dt('preflight');
is($rc, 0, 'the allow-list file and .devteam do not make the tree dirty') or diag $out;
sub slurp_file { open my $h, '<', $_[0] or return ''; local $/; <$h> }

done_testing;
