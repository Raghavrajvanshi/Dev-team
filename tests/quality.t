use strict;
use warnings;
use FindBin;
use JSON::PP;
use Test::More;
require "$FindBin::Bin/lib.pl";
our ($PLUGIN, $REPO);

sub slurp { open my $h, '<', $_[0] or die "$_[0]: $!"; local $/; <$h> }
sub front { slurp("$PLUGIN/agents/$_[0].md") =~ /\A---\n(.*?)\n---/s ? $1 : '' }

# --- the new roles can look things up and see results ---
for my $role (qw(researcher ux-designer architect)) {
    like(front($role), qr/^tools:.*\bWebSearch\b.*\bWebFetch\b/m, "$role can search and fetch the web, so it does not work from memory");
}
like(front('fullstack-engineer'), qr/^tools:.*\bWebFetch\b/m, 'engineers can confirm an API in the docs');
unlike(front('reviewer'), qr/^tools:.*\b(?:Write|Edit)\b/m, 'the reviewer stays read-only');
like(front('ux-designer'), qr/^effort: high$/m, 'the designer thinks at high effort');
like(front('fullstack-engineer'), qr/^effort: high$/m, 'engineers think at high effort by default');
like(front('reviewer'), qr/^effort: high$/m, 'the reviewer thinks at high effort');

# --- agent frontmatter and the recommended defaults must agree ---
new_repo();
dt('init');
for my $role (qw(architect fullstack-engineer qa-engineer reviewer goal-verifier researcher ux-designer)) {
    my ($model) = front($role) =~ /^model: (\w+)$/m;
    my ($effort) = front($role) =~ /^effort: (\w+)$/m;
    my ($rc, $out) = dt('models', 'get', $role);
    like($out, qr/model=\Q$model\E effort=\Q$effort\E changed=no/, "$role: frontmatter matches the recommended default ($model/$effort)");
}

# --- the process reaches the team ---
my $orch = slurp("$PLUGIN/skills/orchestrate/SKILL.md");
like($orch, qr/spawn `researcher`/, 'the PM researches before designing');
like($orch, qr/spawn `ux-designer` \(spec mode\)/, 'user-facing goals get a design spec');
like($orch, qr/critique mode/, 'and a critique pass on screenshots');
like($orch, qr/At most 2 polish rounds/, 'with bounded polish rounds');
like($orch, qr/Quality is never traded for spawns/, 'and quality is not traded for spawn caps');
my $goal = slurp("$PLUGIN/skills/goal/SKILL.md");
like($goal, qr/Structural criteria are necessary, not sufficient/, 'intake requires a quality criterion for user-facing goals');
like($goal, qr/1-3 live references/, 'and asks for live references');
like(slurp("$PLUGIN/skills/devteam-craft/SKILL.md"), qr/Minimal means no waste, not low ambition/, 'the craft charter no longer pushes quality down');
like(slurp("$PLUGIN/agents/architect.md"), qr/never a reason to cut design fidelity/, 'the complexity budget is not a ceiling on quality');
like(slurp("$PLUGIN/agents/goal-verifier.md"), qr/open the screenshots.*with Read/s, 'the verifier judges quality from screenshots');
like(slurp("$PLUGIN/skills/devteam-design-quality/SKILL.md"), qr/Flat clip-art boxes are a defect/, 'the devteam-design-quality skill names the failure we saw');
like(slurp("$PLUGIN/skills/devteam-research/SKILL.md"), qr/Never build from memory|never build from memory/i, 'the devteam-research skill forbids working from memory');

# --- cached knowledge ---
my ($rc, $out) = dt('knowledge');
like($out, qr/no cached knowledge/, 'knowledge starts empty');
sh('mkdir -p .devteam/knowledge && echo "retrieved: 2026-10-10" > .devteam/knowledge/react.md && echo x > .devteam/knowledge/old.md && touch -t 202401010000 .devteam/knowledge/old.md');
($rc, $out) = dt('knowledge');
like($out, qr/^react\s+0 days/m, 'a fresh topic is listed with its age');
($rc, $out) = dt('knowledge', '--stale', '30');
like($out, qr/^old\s+\d{3,} days/m, '--stale lists topics older than the threshold');
unlike($out, qr/react/, 'and not the fresh ones');

# --- screenshots (with a stand-in browser so the test needs no real Chrome) ---
my $fake = "$REPO/fake-chrome";
open my $f, '>', $fake or die;
print $f "#!/bin/sh\nfor a in \"\$@\"; do case \"\$a\" in --screenshot=*) out=\"\${a#--screenshot=}\";; --window-size=*) size=\"\${a#--window-size=}\";; esac; done\nprintf 'PNG %s %s' \"\$size\" \"\$*\" > \"\$out\"\n";
close $f;
chmod 0755, $fake;
$ENV{DT_CHROME} = $fake;
dt('goal', 'new', 'shots');
($rc, $out) = dt('shot', '--widths', '390,1280', '--name', 'home', 'file:///site/index.html');
is($rc, 0, 'dt shot runs') or diag $out;
my @paths = split /\n/, $out;
is(scalar @paths, 2, 'one screenshot per width');
like($paths[0], qr{/goals/G-001/evidence/shots/home-390\.png$}, 'screenshots land in the goal evidence');
like(slurp($paths[1]), qr/PNG 1280,2400/, 'the requested window size reached the browser');

# --- dt must not declare file-level data below its dispatcher's exit: it would be empty when used ---
{
    my @l = split /\n/, slurp("$PLUGIN/bin/dt");
    my ($exit) = grep { $l[$_] =~ /^exit \$EXIT;/ } 0 .. $#l;
    ok(defined $exit, 'dt has a dispatcher with a single exit');
    my @late = grep { $l[$_] =~ /^my [\@%\$]/ } $exit + 1 .. $#l;
    is(scalar @late, 0, 'no file-level my declaration follows the dispatcher exit') or diag join "\n", map { $l[$_] } @late;
}

# --- the selftest skill covers every manual check the report expects ---
{
    my $dt = slurp("$PLUGIN/bin/dt");
    my ($block) = $dt =~ /my \@MANUAL = \((.*?)\);/s;
    my @ids = $block =~ /\['([a-z-]+)',/g;
    cmp_ok(scalar @ids, '>=', 6, 'the report expects manual checks');
    my $skill = slurp("$PLUGIN/skills/selftest/SKILL.md");
    for my $id (grep { $_ ne 'pm-mode' } @ids) { like($skill, qr/\b\Q$id\E\b/, "selftest records $id") }
    like($skill, qr/dt trace note pm-mode/, 'selftest says how to record the PM mode check');
    like($skill, qr/^disable-model-invocation: true$/m, 'selftest is user-only: it spawns agents');
}

# --- preloaded skills need collision-proof names that match their folders (a bare name once resolved to another plugin's skill) ---
{
    for my $a (glob "$PLUGIN/agents/*.md") {
        my ($fm) = slurp($a) =~ /\A---\n(.*?)\n---/s;
        my ($list) = $fm =~ /^skills:\n((?:  - \S+\n?)+)/m;
        for my $n (($list // '') =~ /^  - (\S+)$/mg) {
            like($n, qr/^devteam-/, "$a preloads '$n' by a devteam- prefixed name");
            like(slurp("$PLUGIN/skills/$n/SKILL.md"), qr/^name: \Q$n\E$/m, "'$n' is a real skill whose name matches its folder");
        }
    }
    unlike(slurp("$PLUGIN/agents/project-manager.md"), qr/^skills:/m, 'PM mode preloads nothing by a bare name');
    like(slurp("$PLUGIN/agents/project-manager.md"), qr/`devteam:orchestrate`/, 'and names orchestrate by its qualified name');
}

# --- outcomes: the PM flow that records a partial close must stay consistent with what dt requires ---
{
    my $o = slurp("$PLUGIN/skills/orchestrate/SKILL.md");
    like($o, qr/dt close --accept-partial --reason "<their words>" --by user/, 'orchestrate shows the exact partial-close command');
    like($o, qr/Never supply the reason yourself/, 'orchestrate forbids inventing the reason');
    like($o, qr/cannot be closed as partial/, 'orchestrate says integrity failures cannot close as partial');
    like($o, qr/\*\*accept as partial\*\*/, 'the close-out question offers accept as partial');
    like(slurp("$PLUGIN/skills/stop/SKILL.md"), qr/outcome/, 'stop reports the recorded outcome');
}

# --- concurrent sessions: the PM flow must keep using what dt provides ---
{
    my $o = slurp("$PLUGIN/skills/orchestrate/SKILL.md");
    like($o, qr/dt scope start <task-id>/, 'orchestrate sets the task scope before spawning');
    like($o, qr/dt scope check/, 'orchestrate checks the scope after each task');
    like($o, qr/dt sessions ack/, 'orchestrate handles a refused spawn with the user\'s choice');
    like($o, qr/Never accept to silence it/, 'orchestrate forbids accepting out-of-scope writes to silence them');
    like(slurp("$PLUGIN/skills/start/SKILL.md"), qr/ENGAGE NEEDS A CHOICE.*--take-over.*--accept-others/s, 'start handles a choice from dt engage');
    my $dt = slurp("$PLUGIN/bin/dt");
    like($dt, qr/'sessions-registry'/, 'the registry check is a recorded manual check');
}

done_testing;
