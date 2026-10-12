use strict;
use warnings;
use FindBin;
use JSON::PP;
use Test::More;
require "$FindBin::Bin/lib.pl";
our ($PLUGIN, $REPO);

sub slurp { open my $h, '<', $_[0] or die "$_[0]: $!"; local $/; <$h> }
sub decision { my $j = eval { decode_json($_[0]) } or return ''; $j->{hookSpecificOutput}{permissionDecision} // '' }
sub reason   { my $j = eval { decode_json($_[0]) } or return ''; $j->{hookSpecificOutput}{permissionDecisionReason} // '' }

# --- the agent's contract ---
my $agent = slurp("$PLUGIN/agents/devops-engineer.md");
my ($fm) = $agent =~ /\A---\n(.*?)\n---/s;
like($fm, qr/^name: devops-engineer$/m, 'the agent file is the devops-engineer role');
like($fm, qr/^description: DevOps Engineer:/m, 'its description leads with its title');
my ($tools) = $fm =~ /^tools: (.*)$/m;
my %t = map { $_ => 1 } split /,\s*/, $tools;
ok($t{Edit} && $t{Write} && $t{Bash}, 'it can write files and run checks');
ok(!$t{WebSearch}, 'it fetches pages only to confirm a version; it does not search the web');
like($fm, qr/^skills:\n  - devteam-craft$/m, 'it preloads the craft charter by its qualified name');
cmp_ok(scalar(() = $agent =~ /\n/g), '<=', 60, 'one agent file of at most 60 lines');
like($agent, qr/Do not deploy, apply, push, publish/, 'it never deploys');
like($agent, qr/^DEPLOY FACTS: /m, 'what a deploy would do is reported for the user to run');
like($agent, qr/^CHECKS: /m, 'and what was verified, and what could not be');
like($agent, qr/pinned to a full commit SHA/, 'third-party actions are pinned');
like($agent, qr/diagnosed before it is changed/, 'a failing step is diagnosed first');
like($agent, qr/names its rollback/, 'a deploy path names its rollback');

new_repo();
dt('init');
my ($rc, $out) = dt('models', 'get', 'devops-engineer');
(my $model) = $fm =~ /^model: (\S+)/m;
(my $effort) = $fm =~ /^effort: (\S+)/m;
like($out, qr/model=\Q$model\E effort=\Q$effort\E/, 'its frontmatter model and effort are the configured defaults');
($rc, $out) = dt('team');
like($out, qr/DevOps Engineer\s+devops-engineer/, 'the roster lists the role now that it ships');

# --- the PM flow routes to it ---
my $o = slurp("$PLUGIN/skills/orchestrate/SKILL.md");
like($o, qr/`dt risk planned <the task's files>`.*`pipeline:`.*`devops-engineer`/s, 'a task whose files are pipeline files goes to the DevOps Engineer');
like($o, qr/DEPLOY FACTS/, 'its deploy facts reach the close-out question');
like($o, qr/a security FIX is never dismissed, on the reviewer's word or yours: it is fixed, or put to the user before `dt close`/, 'a security FIX is fixed or put to the user, never closed over (found live)');
like($o, qr/contradicts `design.md`, changes scope or a criterion is an exception stop/, 'a requirement that contradicts the design is an exception stop (found live)');

# --- the guard: nothing that changes a cluster, a cloud account or a registry runs from a subagent ---
dt('engage', 's1');
dt('goal', 'new', 'infra');
dt('criteria', 'add', '--id', 'C1', '--text', 'WHEN x THEN y', '--check', 'true');
dt('goal', 'confirm', '--lane', 'standard', '--lifecycle', 'agile-kanban');
sub bash {
    my ($cmd, $role) = @_;
    hook('git-guard', { session_id => 's1', cwd => $REPO, agent_id => 'a1', agent_type => $role // 'devteam:devops-engineer', tool_name => 'Bash', tool_input => { command => $cmd } });
}
for my $cmd ('terraform apply -auto-approve', 'tofu destroy', 'kubectl apply -f deploy.yaml', 'kubectl --context prod delete pod x',
    'helm upgrade --install app ./chart', 'docker push registry.example/app:1', 'docker login registry.example', 'npm publish',
    'cargo publish', 'twine upload dist/*', 'pulumi up --yes', 'aws s3 sync . s3://bucket', 'gcloud run deploy app', 'vercel --prod',
    'sudo terraform destroy', 'FOO=1 kubectl apply -f x.yaml', 'sh -c "helm upgrade x y"', 'bash -c "cd infra && terraform apply"',
    'make build && docker push app', 'kubectl apply --dry-run=server -f x.yaml', 'serverless deploy', 'cdk deploy') {
    my ($c, $o2) = bash($cmd);
    is(decision($o2), 'deny', "denied: $cmd");
}
like(reason((bash('terraform apply'))[1]), qr/'terraform apply'.*outside the working tree.*DEPLOY FACTS/, 'the refusal names the command and says what to do');
for my $cmd ('terraform plan', 'terraform validate', 'terraform fmt -check', 'kubectl apply --dry-run=client -f x.yaml',
    'helm lint ./chart', 'helm template app ./chart', 'helm upgrade --dry-run app ./chart', 'docker build -t app .', 'docker compose config',
    'npm test', 'npm ci', 'actionlint', 'hadolint Dockerfile', 'shellcheck ci.sh', 'echo terraform apply', 'grep -rn "docker push" .',
    'git status', 'cat deploy.sh', 'cargo test', 'sh -c "echo hi"') {
    my ($c, $o2) = bash($cmd);
    is($o2, '', "allowed: $cmd");
}
is(decision((bash('kubectl apply -f x.yaml', 'devteam:fullstack-engineer'))[1]), 'deny', 'every subagent role is held to it, not only the DevOps Engineer');
is((hook('git-guard', { session_id => 's1', tool_name => 'Bash', tool_input => { command => 'terraform apply' } }))[1], '', 'the main thread is not governed by the hook');

# --- the role is a writer (it may commit on a goal branch with the grant) and is gated like an engineer ---
my $hooks = slurp("$PLUGIN/lib/Hooks.pm");
like($hooks, qr/qw\(fullstack-engineer backend-engineer frontend-engineer\s+mobile-engineer devops-engineer qa-engineer/, 'devops-engineer is in the writer list');

done_testing;
