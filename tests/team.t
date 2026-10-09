use strict;
use warnings;
use FindBin;
use Test::More;
require "$FindBin::Bin/lib.pl";
our ($PLUGIN, $REPO);

sub slurp { open my $h, '<', $_[0] or die "$_[0]: $!"; local $/; <$h> }

# --- the data files ---
my @roles;
for (split /\n/, slurp("$PLUGIN/team.tsv")) {
    next if /^#/ || !/\S/;
    my ($role, $title, $where) = split /\t/;
    push @roles, { role => $role, title => $title, where => $where };
}
my %seen;
is(scalar(grep { $seen{ $_->{role} }++ } @roles), 0, 'roles are unique');
is(scalar(grep { !length($_->{title} // '') || ($_->{where} // '') !~ /^(?:main|agent)$/ } @roles), 0, 'every role has a title and says where it runs');
is(scalar(grep { /\t.*\t.*\t/ } split /\n/, slurp("$PLUGIN/team.tsv")), 0, 'the roster holds no names: names are generated at runtime');

my (%pool, $sec);
for (split /\n/, slurp("$PLUGIN/names.txt")) {
    next if /^#/ || !/\S/;
    if (/^\[(first|last)\]$/) { $sec = $1; next }
    push @{ $pool{$sec} }, $_;
}
for my $k (qw(first last)) {
    cmp_ok(scalar @{ $pool{$k} }, '>=', 40, "$k name pool is large enough to give each team distinct people");
    is(scalar(grep { !/^[A-Z][a-z]+$/ } @{ $pool{$k} }), 0, "$k names are plain ASCII words");
    my %u;
    is(scalar(grep { $u{$_}++ } @{ $pool{$k} }), 0, "$k names are unique");
}

# --- no person is hardcoded in any agent, skill or script ---
my $first = join '|', @{ $pool{first} };
my $last = join '|', @{ $pool{last} };
my @files = (glob("$PLUGIN/agents/*.md"), glob("$PLUGIN/skills/*/SKILL.md"), "$PLUGIN/bin/dt", glob("$PLUGIN/lib/*.pm"), glob("$PLUGIN/lib/DT/*.pm"));
is(scalar(grep { slurp($_) =~ /\b(?:$first) (?:$last)\b/ } @files), 0, 'no agent, skill or script hardcodes a person (examples are not drawn from the pool)');
for my $r (grep { -f "$PLUGIN/agents/$_->{role}.md" } @roles) {
    like(slurp("$PLUGIN/agents/$r->{role}.md"), qr/^description: \Q$r->{title}\E:/m, "$r->{role}: description leads with its title");
}

# --- runtime generation ---
new_repo();
dt('init');
$ENV{DT_SEED} = 7;
my ($rc, $out) = dt('team');
is($rc, 0, 'dt team');
my @lines = split /\n/, $out;
my $shipped = scalar grep { $_->{where} eq 'main' || -f "$PLUGIN/agents/$_->{role}.md" } @roles;
is(scalar @lines, $shipped, "every shipped member is listed ($shipped)");
like($out, qr/Software Architect\s+architect\n/, 'lists title and role id');
unlike($out, qr/Backend Engineer/, 'planned roles are hidden by default');
like($out, qr/Research Analyst\s+researcher\n/, 'the researcher has shipped');
like($out, qr/UX Designer\s+ux-designer\n/, 'the designer has shipped');
my @firsts = map { (split ' ', $_)[0] } @lines;
my %f;
is(scalar(grep { $f{$_}++ } @firsts), 0, 'no first name repeats within a team');
for my $l (@lines) { my ($fn, $ln) = split ' ', $l; ok((grep { $_ eq $fn } @{ $pool{first} }) && (grep { $_ eq $ln } @{ $pool{last} }), "drawn from the pool: $fn $ln") }

my $first_run = $out;
$ENV{DT_SEED} = 99;    # a different seed must not matter once names exist
($rc, $out) = dt('team');
is($out, $first_run, 'names are stable for the whole engagement');
($rc, $out) = dt('team', '--all');
like($out, qr/Backend Engineer\s+backend-engineer \(planned\)/, '--all lists planned roles, flagged, with names already drawn');

$ENV{DT_SEED} = 99;
($rc, $out) = dt('team', '--reroll');
isnt($out, $first_run, '--reroll draws a new team');

# --- lookup ---
my ($arch_name) = grep { /architect/ } split /\n/, $out;
(my $full = $arch_name) =~ s/\s{2,}.*//;
my $arch_first = (split ' ', $full)[0];
($rc, $out) = dt('who', 'architect');
is($out, "$full, Software Architect\n", 'who resolves a role id');
($rc, $out) = dt('who', lc $arch_first);
is($out, "$full, Software Architect\n", 'who resolves a first name, any case');
($rc, $out) = dt('who', $full, '--role');
is($out, "architect\n", 'who --role resolves a full name to the role id');
($rc, $out) = dt('who', 'nobody-here');
isnt($rc, 0, 'an unknown person is an error');

# --- models accept names and show them ---
($rc, $out) = dt('models', 'show');
like($out, qr/^architect\s+opus\s+high\s+recommended\s+\Q$full\E$/m, 'models show lists the person next to the role');
($rc, $out) = dt('models', 'set', $arch_first, '--model', 'haiku');
is($rc, 0, 'models set accepts a first name');
($rc, $out) = dt('models', 'get', 'architect');
like($out, qr/model=haiku/, 'and the change landed on the right role');

# --- standing the team down draws a new one next time ---
my ($before) = dt('team');
dt('engage', 's1');
ok(-f "$REPO/.devteam/team.json", 'names are kept in .devteam/team.json');
dt('disengage');
ok(!-f "$REPO/.devteam/team.json", 'disengaging stands the team down');
$ENV{DT_SEED} = 3;
my ($rc2, $after) = dt('team');
my ($rc3, $again) = dt('team');
is($after, $again, 'and the next engagement is stable again');
done_testing;
