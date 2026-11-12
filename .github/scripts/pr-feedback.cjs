const { validateMessage } = require('./commit-policy.cjs');
const MARKER = '<!-- pcl-slash-pr-title -->';

module.exports = async function prFeedback({ github, context, core }) {
  const pr = context.payload.pull_request;
  let invalid = false;
  try { validateMessage(pr.title); } catch { invalid = true; }
  const comments = await github.paginate(github.rest.issues.listComments,
    { ...context.repo, issue_number: pr.number, per_page: 100 });
  const existing = comments.find(comment => comment.user?.login === 'github-actions[bot]' && comment.body?.includes(MARKER));
  const body = MARKER + '\n' + (invalid
    ? '请将 PR 标题改为 `type(scope): 描述`，例如 `fix(login): 修复微软登录失败`。scope 可省略；标题最多 100 个字符。\n\n支持 feat、fix、perf、refactor、docs、style、test、build、ci、chore、revert；不兼容变更可加 `!`。发行说明会直接使用 PR 标题，请准确描述最终改动。\n\n请参考仓库 CONTRIBUTING.md 和 PR 模板，补充改动原因与验证结果。修改标题后会自动重新检查。'
    : 'PR 标题已符合规范。请继续等待构建、提交规范检查和维护者审查。');
  if (existing) {
    if (existing.body !== body) await github.rest.issues.updateComment({ ...context.repo, comment_id: existing.id, body });
  } else if (invalid) {
    await github.rest.issues.createComment({ ...context.repo, issue_number: pr.number, body });
  }
  if (invalid) core.setFailed('PR 标题不符合提交规范，请按评论提示修改。');
};
