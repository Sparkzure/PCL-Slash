const { execFileSync } = require('node:child_process');
const { writeFileSync, mkdirSync } = require('node:fs');
const { parseSubject, COMMIT_BASELINE } = require('./commit-policy.cjs');
const tagPattern = /^v\d+\.\d+\.\d+(?:\.\d+)?(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?(?:\+[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$/;
function validateTag(tag) {
  if (!tagPattern.test(tag)) throw new Error(`版本标签无效：${tag}；请使用 v1.2.3 或 v1.2.3.4，可附加 -beta.1 等预发布后缀。`);
  return tag;
}
function previousTag(tag, cwd) {
  const git = args => execFileSync('git', args, { cwd, encoding: 'utf8' }).trim();
  const channel = tagChannel(tag);
  const candidates = git(['tag', '--merged', tag]).split('\n').filter(value => value !== tag && tagPattern.test(value) &&
    (channel === 'release' ? tagChannel(value) === 'release' : channel === 'beta' ? tagChannel(value) === 'beta' : true));
  if (!candidates.length) return null;
  try { return git(['describe', '--tags', '--abbrev=0', ...candidates.map(value => `--match=${value}`), `${tag}^`]); }
  catch { return null; } // 首个版本或根提交没有更早的版本标签。
}
function tagChannel(tag) {
  return tag.split('+')[0].match(/-([0-9A-Za-z]+)/)?.[1].toLowerCase() || 'release';
}
function readRange(tag, previous, cwd, baseline = COMMIT_BASELINE) {
  if (!/^[0-9a-f]{40}$/i.test(baseline || '')) throw new Error('修改日志基线必须为完整的提交 SHA');
  try { execFileSync('git', ['cat-file', '-e', `${baseline}^{commit}`], { cwd, stdio: 'pipe' }); }
  catch { throw new Error(`无法读取修改日志基线 ${baseline}，请确保检出了完整 Git 历史。`); }
  // 版本范围之外，再排除历史基线本身和全部祖先，包括基线前已合并的分支提交。
  return execFileSync('git', ['rev-list', '--reverse', previous ? `${previous}..${tag}` : tag, `^${baseline}`, '--'],
    { cwd, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 }).trim().split('\n').filter(Boolean);
}
async function collectCommits({ github, owner, repo, tag, previous, commits }) {
  const included = new Set(commits);
  const found = new Map();
  // 分页比较整个版本区间；首个版本从当前标签遍历历史。以本地 SHA 集合校验，避免漏掉提交。
  // API 仍可能返回被基线排除的旧提交，不能按筛选后的提交数限制页数。
  for (let page = 1; found.size < included.size; page++) {
    const args = { owner, repo, per_page: 100, page };
    const entries = previous
      ? (await github.rest.repos.compareCommitsWithBasehead({ ...args, basehead: `${previous}...${tag}` })).data.commits
      : (await github.rest.repos.listCommits({ ...args, sha: tag })).data;
    for (const entry of entries) {
      if (included.has(entry.sha)) found.set(entry.sha, entry);
    }
    if (entries.length < 100) break;
  }
  if (found.size !== included.size) throw new Error(`提交元数据不完整：缺少 ${included.size - found.size} 个提交，拒绝生成不完整的发行说明。`);
  // 普通合并提交仅用于组织历史；实际改动由其分支提交表达，squash / rebase 提交正常收录。
  return [...included].map(sha => found.get(sha)).filter(entry => entry.parents.length < 2);
}
function escape(text) { return text.replace(/[\r\n]+/g, ' ').replace(/[\\`*_[\]<>~!]/g, value => `\\${value}`); }
const categories = [
  ['breaking', '破坏性变更'], ['feat', '新增功能'], ['fix', '问题修复'], ['perf', '性能优化'],
  ['refactor', '代码重构'], ['docs', '文档'], ['style', '代码风格'], ['test', '测试'],
  ['build', '构建'], ['ci', '持续集成'], ['chore', '维护'], ['revert', '回退'], ['other', '其他']
];
function authorLink(entry, repository) {
  const login = entry.author?.login;
  if (login) return `[@${escape(login)}](https://github.com/${login.endsWith('[bot]')
    ? `apps/${encodeURIComponent(login.slice(0, -5))}` : encodeURIComponent(login)})`;
  const { name, email } = entry.commit.author || {};
  // 未关联 GitHub 账号时保留原始作者，并链接到该作者的仓库提交记录。
  return `[${escape(name || email || '未知提交人')}](https://github.com/${repository}/commits?author=${encodeURIComponent(email || name || '')})`;
}
function renderNotes({ commits, repository }) {
  if (!commits.length) return '此范围内没有可记录的提交。\n';
  const groups = new Map(categories.map(([key]) => [key, []]));
  for (const entry of commits) {
    const subject = entry.commit.message.split(/\r?\n/)[0];
    const parsed = parseSubject(subject);
    const breaking = parsed?.breaking || /^BREAKING(?: CHANGE|-CHANGE):\s*\S/m.test(entry.commit.message);
    const category = breaking ? 'breaking' : parsed?.type || 'other';
    groups.get(category).push(`- ${escape(subject || '（无标题）')} ([${entry.sha.slice(0, 7)}](https://github.com/${repository}/commit/${entry.sha})) by ${authorLink(entry, repository)}`);
  }
  return categories.filter(([key]) => groups.get(key).length)
    .map(([key, title]) => `## ${title}\n\n${groups.get(key).join('\n')}`).join('\n\n') + '\n';
}
function draftBody(notes) {
  if (notes.length <= 100000) return notes;
  return notes.slice(0, 99000).replace(/\n[^\n]*$/, '') + '\n\n历史记录较长，完整内容见附件 CHANGELOG.md。\n';
}
async function generateNotes({ github, context, core, tag = process.env.RELEASE_TAG, cwd, directory = 'release-assets', baseline = COMMIT_BASELINE }) {
  validateTag(tag);
  const previous = previousTag(tag, cwd);
  const { owner, repo } = context.repo;
  const commits = await collectCommits({ github, owner, repo, tag, previous, commits: readRange(tag, previous, cwd, baseline) });
  const notes = renderNotes({ commits, repository: `${owner}/${repo}` });
  mkdirSync(directory, { recursive: true });
  const { join } = require('node:path');
  writeFileSync(join(directory, 'CHANGELOG.md'), notes);
  writeFileSync(join(directory, 'draft-body.md'), draftBody(notes));
  core.info(`发行说明范围：${previous || '全部历史'} → ${tag}，排除 ${baseline} 及其祖先，共 ${commits.length} 个非合并提交。`);
}
if (require.main === module) {
  validateTag(process.env.RELEASE_TAG || process.env.GITHUB_REF_NAME || '');
  if (process.argv[2] !== 'validate-tag') throw new Error('请通过 actions/github-script 调用 generateNotes，以读取提交元数据。');
}
module.exports = { validateTag, previousTag, tagChannel, readRange, collectCommits, renderNotes, draftBody, generateNotes };
