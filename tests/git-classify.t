use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../plugins/devteam/lib";
use Test::More;
use DT::Git qw(classify);

my @cases = (
    # command                                         tier          switch
    ['ls -la',                                        'none',       0],
    ['echo "git push is bad"',                        'read',       0],   # mentions git but runs echo -> none expected below
    ['git status --short',                            'read',       0],
    ['git -C /tmp/x diff HEAD',                       'read',       0],
    ['git log --oneline | head -5',                   'read',       0],
    ['git add -A && git commit -m "x"',               'local',      0],
    ['git commit --amend --no-edit',                  'local',      0],
    ['git branch',                                    'read',       0],
    ['git branch -a',                                 'read',       0],
    ['git branch feature/x',                          'local',      0],
    ['git branch -D feature/x',                       'destructive',0],
    ['git push origin main',                          'remote',     0],
    ['git pull',                                      'remote',     0],
    ['git fetch origin',                              'read',       0],
    ['git reset --hard HEAD~1',                       'destructive',0],
    ['git reset HEAD file',                           'local',      0],
    ['git clean -fd',                                 'destructive',0],
    ['git checkout -- file.txt',                      'local',      0],
    ['git checkout main',                             'local',      1],
    ['git checkout -b devteam/G-001',                 'local',      1],
    ['git checkout -f main',                          'destructive',0],
    ['git switch -c x',                               'local',      1],
    ['git worktree add ../w -b t',                    'local',      0],
    ['git worktree remove --force ../w',              'destructive',0],
    ['git worktree list',                             'read',       0],
    ['git stash',                                     'local',      0],
    ['git stash list',                                'read',       0],
    ['git remote -v',                                 'read',       0],
    ['git remote add o url',                          'destructive',0],
    ['git config user.name x',                        'destructive',0],
    ['git config --get user.name',                    'read',       0],
    ['git frobnicate',                                'destructive',0],
    ['cd repo && git push --force',                   'remote',     0],
    ['FOO=1 git status',                              'read',       0],
    ['/usr/bin/git diff',                             'read',       0],
    ['gh pr view 3',                                  'read',       0],
    ['gh pr create --title t',                        'remote',     0],
    ['gh pr merge 3',                                 'remote',     0],
    ['gh repo delete x --yes',                        'destructive',0],
    ['gh api repos/a/b',                              'read',       0],
    ['gh api -X POST repos/a/b/issues',               'remote',     0],
    ['gh auth status',                                'read',       0],
    ['gh auth login',                                 'destructive',0],
    ['sh -c "git push"',                              'unverifiable',0],
    ['git $(echo push)',                              'unverifiable',0],
    ['echo x | xargs git rm',                         'unverifiable',0],
    ['git commit -m "unbalanced',                     'unverifiable',0],
    ['npm test && git status',                        'read',       0],
);
# `echo "git push is bad"` runs echo, not git, so the correct tier is none.
$cases[1][1] = 'none';

for my $c (@cases) {
    my ($cmd, $tier, $sw) = @$c;
    my $r = classify($cmd);
    is($r->{tier}, $tier, "tier: $cmd");
    is($r->{switch}, $sw, "switch: $cmd") if $sw;
}
done_testing;
