const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { previousTag, readRange, collectPullRequests, generateNotes } = require('./release-notes.cjs');
const feedback = require('./pr-feedback.cjs');

test('beta starts at the previous beta; snapshot starts at any previous version; stable ignores prereleases', async t => {
  const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'pcl-notes-'));
  t.after(() => {
    assert.equal(path.dirname(cwd), os.tmpdir());
    assert.ok(path.basename(cwd).startsWith('pcl-notes-'));
    fs.rmSync(cwd, { recursive: true, force: true });
  });
  const git = args => execFileSync('git', args, { cwd, encoding: 'utf8' }).trim();
  git(['init', '--initial-branch=main']);
  const shas = [];
  for (const tag of ['v1.0.0', 'v1.1.0-snapshot.1', 'v1.1.0-beta.1', 'v1.1.0', 'v1.2.0-snapshot.1', 'v1.2.0-beta.1', 'v1.2.0-snapshot.2', 'v1.2.0']) {
    git(['-c', 'user.name=Tests', '-c', 'user.email=test@example.invalid', 'commit', '--allow-empty', '-m', `chore: ${tag}`]);
    shas.push(git(['rev-parse', 'HEAD']));
    git(['tag', tag]);
  }
  assert.equal(previousTag('v1.1.0-beta.1', cwd), null);
  assert.equal(previousTag('v1.2.0-beta.1', cwd), 'v1.1.0-beta.1');
  assert.equal(previousTag('v1.2.0-snapshot.1', cwd), 'v1.1.0');
  assert.equal(previousTag('v1.2.0-snapshot.2', cwd), 'v1.2.0-beta.1');
  assert.equal(previousTag('v1.2.0', cwd), 'v1.1.0');
  assert.deepEqual(readRange('v1.2.0-beta.1', 'v1.1.0-beta.1', cwd), shas.slice(3, 6));
  assert.deepEqual(readRange('v1.1.0-beta.1', null, cwd), shas.slice(0, 3));
  const calls = [];
  const pr = number => ({ number, title: `feat: PR ${number}`, merged_at: '2026-01-01', merge_commit_sha: shas[number],
    base: { repo: { full_name: 'Sparkzure/PCL-Slash' } }, user: { login: 'lecyn' } });
  const github = { rest: { pulls: { list() {} } }, paginate: async (method, args) => { calls.push(args); return [pr(2), pr(3), pr(5)]; } };
  const directory = path.join(cwd, 'assets');
  await generateNotes({ github, context: { repo: { owner: 'Sparkzure', repo: 'PCL-Slash' } }, core: { info() {} },
    tag: 'v1.2.0-beta.1', cwd, directory });
  const notes = fs.readFileSync(path.join(directory, 'draft-body.md'), 'utf8');
  assert.ok(!notes.includes('PR 2'));
  assert.ok(notes.includes('PR 3') && notes.includes('PR 5'));
  assert.equal(notes, fs.readFileSync(path.join(directory, 'CHANGELOG.md'), 'utf8'));
  assert.equal(calls[0].per_page, 100);
});

test('collects merge, squash and rebase PRs once, excludes direct commits, unmerged and out-of-range PRs', async () => {
  const pr = (number, sha, extra = {}) => ({ number, title: `fix: ${number}`, merge_commit_sha: sha,
    merged_at: '2026-01-01', base: { repo: { full_name: 'Sparkzure/PCL-Slash' } }, ...extra });
  const all = [pr(5, 'rebase'), pr(2, 'merge'), pr(3, 'squash'), pr(2, 'merge'), pr(6, 'old'),
    pr(7, 'future'), pr(8, 'direct', { merged_at: null }),
    pr(9, 'merge', { base: { repo: { full_name: 'other/repo' } } })];
  const list = () => {};
  const github = { rest: { pulls: { list } }, paginate: async (method, args) => {
    assert.equal(method, list);
    assert.equal(args.state, 'closed');
    return all;
  } };
  const pulls = await collectPullRequests({ github, owner: 'sparkzure', repo: 'PCL-Slash', commits: ['merge', 'direct', 'squash', 'rebase'] });
  assert.deepEqual(pulls.map(pr => pr.number), [2, 3, 5]);
  const broken = { ...github, paginate: async () => { throw new Error('API failure'); } };
  await assert.rejects(collectPullRequests({ github: broken, owner: 'o', repo: 'r', commits: ['a'] }), /API failure/);
});

test('PR title feedback creates once, updates on correction and never edits human comments', async () => {
  const comments = [{ id: 1, user: { login: 'human' }, body: '<!-- pcl-slash-pr-title -->' }];
  const writes = [];
  const failures = [];
  const github = { paginate: async () => comments, rest: { issues: {
    listComments() {},
    async createComment(args) { writes.push(['create', args]); comments.push({ id: 2, user: { login: 'github-actions[bot]' }, body: args.body }); },
    async updateComment(args) { writes.push(['update', args]); comments[1].body = args.body; }
  } } };
  const context = { repo: { owner: 'o', repo: 'r' }, payload: { pull_request: { number: 4, title: '标题不规范' } } };
  const args = { github, context, core: { setFailed(message) { failures.push(message); } } };
  await feedback(args);
  await feedback(args);
  assert.equal(writes.length, 1);
  assert.equal(failures.length, 2);
  context.payload.pull_request.title = 'feat(theme): 新增主题';
  await feedback(args);
  await feedback(args);
  assert.equal(writes.length, 2);
  assert.equal(writes[1][1].comment_id, 2);
  assert.match(writes[1][1].body, /已符合规范/);
  comments.splice(1);
  await feedback(args);
  assert.equal(writes.length, 2);
});
