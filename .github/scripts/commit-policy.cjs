const { execFileSync } = require('node:child_process');
// 此提交及其祖先保留历史格式；此提交之后的新变更执行规范。
const COMMIT_BASELINE = '5ef81e490ae46b1100d61e33d0183094c7a80ca8';
const types = ['feat', 'fix', 'perf', 'refactor', 'docs', 'style', 'test', 'build', 'ci', 'chore', 'revert'];
const pattern = new RegExp(`^(${types.join('|')})(?:\\(([^\\s():]+)\\))?(!)?: (\\S.*)$`);

function parseSubject(subject) {
  const match = pattern.exec(subject);
  return match && { type: match[1], scope: match[2], breaking: !!match[3], description: match[4] };
}
function validateMessage(message) {
  const [subject, second] = message.split(/\r?\n/);
  if (!parseSubject(subject) || subject !== subject.trimEnd()) throw new Error(`提交标题不符合 type(scope): 描述：${subject}`);
  if (Array.from(subject).length > 100) throw new Error(`提交标题超过 100 个字符：${subject}`);
  if (second !== undefined && second !== '') throw new Error('标题和正文之间必须空一行');
}
function readCommits(range, cwd, excluded = []) {
  const output = execFileSync('git', ['log', '--no-merges', '--reverse', '--format=%H%x00%B%x00', range, ...excluded.map(sha => `^${sha}`), '--'], { cwd, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  const parts = output.split('\0');
  const result = [];
  for (let i = 0; i + 1 < parts.length; i += 2) result.push({ sha: parts[i].trim(), message: parts[i + 1].replace(/[\r\n]+$/, '') });
  return result;
}
function readPolicyCommits(base, head, cwd, baseline = COMMIT_BASELINE) {
  for (const sha of [base, head, baseline]) {
    if (!/^[0-9a-f]{40}$/i.test(sha || '')) throw new Error('提交规范检查需要完整的提交 SHA');
  }
  try { execFileSync('git', ['cat-file', '-e', `${baseline}^{commit}`], { cwd, stdio: 'pipe' }); }
  catch { throw new Error(`无法读取规范基线 ${baseline}，请确保检出了完整 Git 历史。`); }
  // 同时排除 PR 目标分支已有提交与基线的全部祖先，避免重复检查历史提交。
  return readCommits(`${base}..${head}`, cwd, [baseline]);
}
if (require.main === module) {
  try {
    validateMessage(process.env.PR_TITLE || '');
    for (const commit of readPolicyCommits(process.env.BASE_SHA, process.env.HEAD_SHA)) validateMessage(commit.message);
    console.log('PR 标题及新增的非合并提交均符合提交规范。');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
module.exports = { parseSubject, validateMessage, readCommits, readPolicyCommits, COMMIT_BASELINE };
