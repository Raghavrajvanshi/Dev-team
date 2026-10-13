use strict;
use warnings;
use FindBin;
use Test::More;
require "$FindBin::Bin/lib.pl";
our ($PLUGIN, $REPO);

sub slurp { open my $h, '<', $_[0] or die "$_[0]: $!"; local $/; <$h> }

# --- the trigger data ---
my @rules = grep { !/^#/ && /\S/ } split /\n/, slurp("$PLUGIN/risk.tsv");
cmp_ok(scalar @rules, '>=', 10, 'risk.tsv holds the triggers');
my @cols = map { [ split /\t/ ] } @rules;
is(scalar(grep { @$_ != 3 || $_->[1] !~ /^(?:path|line|size)$/ || ($_->[1] eq 'size' && $_->[2] !~ /^\d+$/) } @cols), 0, 'every rule has a kind, path|line|size and a pattern (a number for size)');
is(scalar(grep { $_->[1] ne 'size' && !eval { qr/$_->[2]/i; 1 } } @cols), 0, 'every pattern compiles');

# --- dt risk ---
new_repo();
my ($rc, $out);
dt('init');

($rc, $out) = dt('risk');
is($rc, 0, 'dt risk runs on a clean tree');
like($out, qr/^risk: no triggers in 0 changed file\(s\)$/m, 'and finds nothing');

sh('mkdir -p src/auth src/ui && echo "export const ok = 1;" > src/auth/login.js && echo "{}" > package.json && echo "# notes" > author.md && echo "x" > src/tokenizer.js');
($rc, $out) = dt('risk');
like($out, qr/^risk: 2 trigger\(s\) in 4 changed file\(s\); a security review is warranted$/m, 'new files trigger by path');
like($out, qr/^  auth: src\/auth\/login\.js$/m, 'an auth path is named');
like($out, qr/^  dependency: package\.json$/m, 'a dependency manifest is named');
unlike($out, qr/author\.md|tokenizer/, 'a word that only starts like a trigger does not match');

# added lines, in new files and in tracked ones
sh('printf "const a = 1;\neval(userInput);\nconst password = \"hunter2hunter2\";\n" > src/ui/run.js');
($rc, $out) = dt('risk');
like($out, qr/^  dynamic-exec: src\/ui\/run\.js:2$/m, 'a risky added line is named with its line number (new file)');
like($out, qr/^  secret: src\/ui\/run\.js:3$/m, 'and a hardcoded secret');

sh('git add src package.json author.md && git commit -q -m base');
sh('printf "old();\nelement.innerHTML = html;\n" > src/ui/page.js && git add src/ui/page.js && git commit -q -m page');
sh('echo "eval(old)" >> src/ui/page.js && git commit -qam more');
($rc, $out) = dt('risk', 'diff', '--base', 'HEAD~2');
like($out, qr/^  dom-injection: src\/ui\/page\.js:2$/m, 'a tracked file: the line the diff adds, at its number');
like($out, qr/^  dynamic-exec: src\/ui\/page\.js:3$/m, 'across several commits since the base');
($rc, $out) = dt('risk', 'diff', '--base', 'HEAD~1');
unlike($out, qr/dom-injection/, 'an earlier commit is not part of a later base');
like($out, qr/dynamic-exec: src\/ui\/page\.js:3/, 'the later one is');

sh('echo "const b = 2;" >> src/ui/page.js');
($rc, $out) = dt('risk', 'diff', '--base', 'HEAD');
like($out, qr/^risk: no triggers in 1 changed file\(s\)$/m, 'risky code the change did not add is not reported');

# a binary or hidden-state file is not scanned
sh('printf "eval(x)\\0\\0" > blob.bin && mkdir -p .devteam/x && echo "eval(y); password = \\"abcdefghij\\"" > .devteam/x/n.txt');
($rc, $out) = dt('risk', 'diff', '--base', 'HEAD');
unlike($out, qr/blob\.bin|\.devteam/, 'binary files and .devteam/ are left alone');

# on a goal branch the base is where the goal started, so commits made since then are seen
new_repo();
dt('init');
dt('engage', 's1');
dt('goal', 'new', 'demo');
dt('criteria', 'add', '--id', 'C1', '--text', 'WHEN x THEN y', '--check', 'true');
dt('goal', 'confirm', '--lane', 'standard', '--lifecycle', 'agile-kanban', '--grants', 'integration');
sh('mkdir -p auth && echo ok > auth/before.js && git add auth && git commit -q -m before');
($rc, $out) = dt('branch', 'start');
is($rc, 0, 'dt branch start') or diag $out;
sh('mkdir -p billing && echo ok > billing/charge.js && git add billing && git commit -q -m charge');
($rc, $out) = dt('risk');
like($out, qr/^  payment: billing\/charge\.js$/m, 'committed work since the goal started is seen') or diag $out;
unlike($out, qr/auth\/before/, 'and what was there before it is not');

# found live: the first real login function (users.py) tripped no trigger at all
new_repo();
dt('init');
sh('printf "import hashlib\\nimport hmac\\nimport secrets\\n\\n\\ndef login(username, password):\\n    ok = hmac.compare_digest(hashlib.scrypt(password, salt=s, n=2, r=8, p=1), d)\\n    return secrets.token_urlsafe(32) if ok else None\\n" > users.py');
sh('printf "def tokenize(text):\\n    return text.split()\\n\\n@login_required\\ndef authority_list():\\n    import hmac\\n    return []\\n" > text.py');
($rc, $out) = dt('risk');
like($out, qr/^  auth-code: users\.py:6$/m, 'a login function is named by its definition line') or diag $out;
like($out, qr/^  crypto-api: users\.py:7$/m, 'and the key-derivation and comparison calls by the first line that uses one');
unlike($out, qr/text\.py/, 'tokenize, login_required, authority_list and a bare import hmac are not triggers');

# planned files: paths only, before any code exists
($rc, $out) = dt('risk', 'planned', 'src/payments/charge.ts', 'README.md', '.github/workflows/ci.yml');
like($out, qr/^risk: 2 trigger\(s\) in 3 planned file\(s\)/, 'planned paths are checked by name');
like($out, qr/^  payment: src\/payments\/charge\.ts$/m, 'a payment path');
like($out, qr/^  pipeline: \.github\/workflows\/ci\.yml$/m, 'a pipeline file');
($rc, $out) = dt('risk', 'planned');
isnt($rc, 0, 'planned needs paths');
($rc, $out) = dt('risk', 'nonsense');
isnt($rc, 0, 'an unknown subcommand is an error');
($rc, $out) = dt('risk', 'diff', '--base', 'no-such-ref');
isnt($rc, 0, 'an unknown base is an error, not a silent "no triggers"');
like($out, qr/not a commit/, 'and says why');

# --- the Security Engineer's contract ---
my $agent = slurp("$PLUGIN/agents/security-engineer.md");
my ($fm) = $agent =~ /\A---\n(.*?)\n---/s;
like($fm, qr/^name: security-engineer$/m, 'the agent file is the security-engineer role');
my ($tools) = $fm =~ /^tools: (.*)$/m;
is(scalar(grep { /^(?:Write|Edit|NotebookEdit)$/ } split /,\s*/, $tools // ''), 0, 'it has no tool that can change a file');
unlike($fm, qr/^skills:/m, 'it preloads nothing, so a spawn costs only its brief');
cmp_ok(scalar(() = $agent =~ /\n/g), '<=', 60, 'one agent file of at most 60 lines');
like($agent, qr/^## Mode `design`/m, 'it has a design mode');
like($agent, qr/^## Mode `diff`/m, 'and a diff mode');
like($agent, qr/STRIDE/, 'design mode applies STRIDE');
like($agent, qr/OWASP Top 10/, 'diff mode applies the OWASP Top 10');
like($agent, qr/Never print its value/, 'a leaked secret is never repeated in a report');
like($agent, qr/^VERDICT: CLEAR \| FIX \| STOP$/m, 'its reply carries a verdict the PM can act on');
like($agent, qr/^COVERAGE: /m, 'and says what it did not read');
(my $model) = $fm =~ /^model: (\S+)/m;
(my $effort) = $fm =~ /^effort: (\S+)/m;
($rc, $out) = dt('models', 'get', 'security-engineer');
like($out, qr/model=\Q$model\E\b/, 'its frontmatter model is the configured default');
like($out, qr/effort=\Q$effort\E\b/, 'and so is its effort');

# --- the PM flow uses it ---
my $o = slurp("$PLUGIN/skills/orchestrate/SKILL.md");
like($o, qr/dt risk planned/, 'orchestrate checks the plan for triggers before building');
like($o, qr/dt risk\b(?! planned)/, 'and the change after it');
like($o, qr/`security-engineer`/, 'orchestrate spawns the role by its id');
like($o, qr/`security-engineer` in `design` mode/, 'in design mode, after the Architect');
like($o, qr/spawn `security-engineer` \(`diff` mode\)/, 'and in diff mode, as one of the review lenses');
like($o, qr/`dt close` refuses when `dt risk` lists triggers and no Security Engineer reviewed the goal/, 'the tiny lane cannot close over a trigger without the user (found live: the PM skipped the step)');
like($o, qr/`dt close --accept-risk --by user`, never without their yes/, 'and only the user accepts it');
like($o, qr/`security-engineer` returns `STOP`/, 'a STOP from it is an exception stop');
like($o, qr/`run_in_background: false`/, 'agents are spawned synchronously: the tool otherwise returns at once (found live)');
like($o, qr/shorten research, design, security review, QA verification, critique or polish/, 'QA verification is never skipped to stay under a cap (found live)');
like($o, qr/RISKY: yes/, 'a risky review also triggers it');

done_testing;
