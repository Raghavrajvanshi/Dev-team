use strict;
use warnings;
use FindBin;
use Test::More;
require "$FindBin::Bin/lib.pl";
our ($PLUGIN, $REPO);

sub slurp { open my $h, '<', $_[0] or die "$_[0]: $!"; local $/; <$h> }
my @rows;
for (split /\n/, slurp("$PLUGIN/team.tsv")) {
    next if /^#/ || !/\S/;
    my ($role, $name, $title, $where) = split /\t/;
    push @rows, { role => $role, name => $name, title => $title, where => $where };
}

# --- the roster itself ---
my %seen;
is(scalar(grep { $seen{ $_->{role} }++ } @rows), 0, 'roles are unique');
%seen = ();
is(scalar(grep { $seen{ $_->{name} }++ } @rows), 0, 'full names are unique');
%seen = ();
is(scalar(grep { $seen{ (split ' ', $_->{name})[0] }++ } @rows), 0, 'first names are unique, so they can be used to address people');
is(scalar(grep { $_->{name} !~ /^[A-Z][a-z]+ [A-Z][A-Za-z]+$/ } @rows), 0, 'names are plain ASCII first and last names');
is(scalar(grep { !defined $_->{where} || $_->{where} !~ /^(?:main|agent)$/ } @rows), 0, 'every row says where the role runs');

# --- agents and skills must carry the same names as the roster ---
for my $r (grep { $_->{where} eq 'agent' && -f "$PLUGIN/agents/$_->{role}.md" } @rows) {
    my $a = slurp("$PLUGIN/agents/$r->{role}.md");
    like($a, qr/^description: \Q$r->{name}\E, \Q$r->{title}\E[:.]/m, "$r->{role}: description starts with its name and title");
    like($a, qr/You are \Q$r->{name}\E,/, "$r->{role}: the prompt introduces its person");
}
my %skill = ('goal-keeper' => 'goal', 'project-manager' => 'orchestrate');
for my $r (grep { $skill{ $_->{role} } } @rows) {
    like(slurp("$PLUGIN/skills/$skill{$r->{role}}/SKILL.md"), qr/\Q$r->{name}\E/, "$skill{$r->{role}} skill names $r->{name}");
}
like(slurp("$PLUGIN/agents/project-manager.md"), qr/Daniel Reyes/, 'PM mode agent is the same person as the PM skill');
like(slurp("$PLUGIN/skills/architect-intake/SKILL.md"), qr/Priya Raman/, 'architect-intake speaks as the Architect');

# --- CLI ---
new_repo();
dt('init');
my ($rc, $out) = dt('team');
is($rc, 0, 'dt team');
like($out, qr/Priya Raman\s+Software Architect\s+architect\n/, 'lists shipped members with name, title and role');
unlike($out, qr/Wei Chen/, 'planned roles are not listed by default');
($rc, $out) = dt('team', '--all');
like($out, qr/Wei Chen\s+Backend Engineer\s+backend-engineer \(planned\)/, '--all lists planned roles, flagged');

($rc, $out) = dt('who', 'architect');
is($out, "Priya Raman, Software Architect\n", 'who resolves a role id');
($rc, $out) = dt('who', 'priya');
is($out, "Priya Raman, Software Architect\n", 'who resolves a first name, any case');
($rc, $out) = dt('who', 'Marcus Lindqvist', '--role');
is($out, "fullstack-engineer\n", 'who --role resolves a full name to the role id');
($rc, $out) = dt('who', 'nobody');
isnt($rc, 0, 'unknown person is an error');

# --- models accept names and show them ---
($rc, $out) = dt('models', 'show');
like($out, qr/^architect\s+opus\s+high\s+recommended\s+Priya Raman$/m, 'models show lists the person next to the role');
($rc, $out) = dt('models', 'set', 'priya,marcus', '--model', 'haiku');
is($rc, 0, 'models set accepts first names');
($rc, $out) = dt('models', 'get', 'Marcus');
like($out, qr/model=haiku/, 'and the change landed on the right role');
($rc, $out) = dt('models', 'get', 'architect');
like($out, qr/model=haiku/, 'Priya is the architect');
done_testing;
