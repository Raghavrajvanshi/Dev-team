package DT::Git;
# Classify a shell command's git/gh usage into tiers. Pure function; best-effort by design
# (hooks cannot see through every shell trick), so anything unparseable is "unverifiable".
use strict;
use warnings;
use Text::ParseWords qw(shellwords);
use Exporter 'import';
our @EXPORT_OK = qw(classify %RANK);

# none < read < local < remote < destructive < unverifiable
our %RANK = (none => 0, read => 1, local => 2, remote => 3, destructive => 4, unverifiable => 5);

my %READ = map { $_ => 1 } qw(status diff log show blame rev-parse rev-list ls-files ls-tree cat-file describe
  grep shortlog name-rev merge-base show-ref for-each-ref count-objects check-ignore diff-tree diff-index
  var version help fetch);
my %LOCAL = map { $_ => 1 } qw(add commit merge rebase cherry-pick revert restore rm mv apply am init notes);
my %DESTRUCTIVE = map { $_ => 1 } qw(clean filter-branch gc prune update-ref submodule);
my %GH_READ = (
    pr => { map { $_ => 1 } qw(view list diff checks status) }, issue => { map { $_ => 1 } qw(view list status) },
    repo => { map { $_ => 1 } qw(view list) }, run => { map { $_ => 1 } qw(view list watch) },
    workflow => { map { $_ => 1 } qw(list view) }, release => { map { $_ => 1 } qw(view list) },
    auth => { status => 1 },
);

sub segments {
    my ($s) = @_;
    my (@seg, $q);
    my $cur = '';
    my @c = split //, $s;
    for (my $i = 0; $i < @c; $i++) {
        my $ch = $c[$i];
        if ($q) {
            $cur .= $ch;
            if ($ch eq '\\' && $q eq '"') { $cur .= $c[++$i] // '' }
            elsif ($ch eq $q) { undef $q }
            next;
        }
        if ($ch eq "'" || $ch eq '"') { $q = $ch; $cur .= $ch; next }
        if ($ch eq '\\') { $cur .= $ch . ($c[++$i] // ''); next }
        if ($ch =~ /[;&|\n]/) {
            push @seg, $cur if $cur =~ /\S/;
            $cur = '';
            $i++ while defined $c[$i + 1] && $c[$i + 1] =~ /[;&|]/;
            next;
        }
        $cur .= $ch;
    }
    push @seg, $cur if $cur =~ /\S/;
    return @seg;
}

sub git_sub {
    my (@w) = @_;
    my $sub;
    while (@w) {
        my $w = shift @w;
        if ($w =~ /^-[Cc]$/ || $w =~ /^--(?:git-dir|work-tree|namespace|exec-path)$/) { shift @w; next }
        next if $w =~ /^-/;
        $sub = $w;
        last;
    }
    return ($sub, @w);
}

sub classify_git {
    my ($sub, @a) = @_;
    return ('none', 0) unless defined $sub;
    my %o = map { $_ => 1 } grep { /^-/ } @a;
    my @pos = grep { !/^-/ } @a;
    my $has = sub { for my $f (@_) { return 1 if $o{$f} } 0 };
    return ('read', 0) if $READ{$sub};
    return ('destructive', 0) if $DESTRUCTIVE{$sub};
    if ($sub eq 'push' || $sub eq 'pull' || $sub eq 'clone') { return ('remote', 0) }
    if ($sub eq 'branch') {
        return ('destructive', 0) if $has->('-D') || ($has->('-d', '--delete') && $has->('-f', '--force'));
        return ('read', 0) if !@pos || $has->('-a', '-r', '--list', '-v', '-vv', '--show-current', '--contains', '--merged', '--no-merged');
        return ('local', 0);
    }
    if ($sub eq 'tag') { return (!@pos || $has->('-l', '--list')) ? ('read', 0) : ('local', 0) }
    if ($sub eq 'remote') { return (!@pos || $pos[0] =~ /^(?:show|get-url)$/) ? ('read', 0) : ('destructive', 0) }
    if ($sub eq 'config') { return ($has->('--get', '--get-all', '--list', '-l')) ? ('read', 0) : ('destructive', 0) }
    if ($sub eq 'stash') { return (!@pos || $pos[0] !~ /^(?:list|show)$/) ? ('local', 0) : ('read', 0) }
    if ($sub eq 'worktree') {
        return ('read', 0) if @pos && $pos[0] eq 'list';
        return ('destructive', 0) if @pos && $pos[0] eq 'prune';
        return ($has->('-f', '--force')) ? ('destructive', 0) : ('local', 0);
    }
    if ($sub eq 'reset') { return ($has->('--hard', '--merge', '--keep')) ? ('destructive', 0) : ('local', 0) }
    if ($sub eq 'reflog') { return (@pos && $pos[0] =~ /^(?:expire|delete)$/) ? ('destructive', 0) : ('read', 0) }
    if ($sub eq 'symbolic-ref') { return (@pos > 1) ? ('destructive', 0) : ('read', 0) }
    if ($sub eq 'switch' || $sub eq 'checkout') {
        return ('destructive', 0) if $has->('-f', '--force', '-B', '-C');
        my $dashdash = grep { $_ eq '--' } @a;
        my $switch = ($sub eq 'switch' || (!$dashdash && @pos) || $has->('-b')) ? 1 : 0;
        return ('local', $switch);
    }
    return ('local', 0) if $LOCAL{$sub};
    return ('destructive', 0);    # unknown subcommand or alias: fail safe
}

sub classify_gh {
    my (@w) = @_;
    my @pos = grep { !/^-/ } @w;
    my ($grp, $verb) = @pos;
    return ('none', 0) unless defined $grp;
    if ($grp eq 'api') {
        my $m = '';
        for my $i (0 .. $#w) { $m = uc($w[$i + 1] // '') if $w[$i] =~ /^(?:-X|--method)$/ }
        my $fields = grep { /^(?:-f|-F|--field|--raw-field|--input)$/ } @w;
        return ($m && $m ne 'GET') || $fields ? ('remote', 0) : ('read', 0);
    }
    return ('read', 0) if $GH_READ{$grp} && defined $verb && $GH_READ{$grp}{$verb};
    return ('destructive', 0) if $grp =~ /^(?:auth|secret|variable|ssh-key|gpg-key|config|extension|alias)$/;
    return ('destructive', 0) if $grp eq 'repo' && defined $verb && $verb =~ /^(?:delete|archive|rename)$/;
    return ('remote', 0);
}

# Returns { tier => ..., switch => 0|1 } for the most severe git/gh use in the command.
sub classify {
    my ($cmd) = @_;
    my %r = (tier => 'none', switch => 0);
    return \%r unless defined $cmd && $cmd =~ /\b(?:git|gh)\b/;
    if ($cmd =~ /(?:\$\(|`|<\(|\beval\b|\b(?:ba|z|da)?sh\s+-c\b|\bxargs\b|\bsource\b)/) { $r{tier} = 'unverifiable'; return \%r }
    for my $seg (segments($cmd)) {
        my @w = eval { shellwords($seg) };
        if ($@ || !@w) { if ($seg =~ /\b(?:git|gh)\b/) { $r{tier} = 'unverifiable'; return \%r } next }
        shift @w while @w && ($w[0] =~ /^[A-Za-z_][A-Za-z0-9_]*=/ || $w[0] =~ m{^(?:sudo|command|env|nice|time)$});
        next unless @w;
        (my $prog = $w[0]) =~ s{.*/}{};
        shift @w;
        my ($tier, $sw);
        if ($prog eq 'git') { my ($sub, @rest) = git_sub(@w); ($tier, $sw) = classify_git($sub, @rest) }
        elsif ($prog eq 'gh') { ($tier, $sw) = classify_gh(@w) }
        else { next }
        $r{switch} ||= $sw;
        $r{tier} = $tier if $RANK{$tier} > $RANK{ $r{tier} };
    }
    return \%r;
}

1;
