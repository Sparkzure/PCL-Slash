const fs = require('node:fs');
const path = require('node:path');
const { releasePlan } = require('./release-channel.cjs');

function versionContents(base, assembly, tag) {
  const plan = releasePlan(tag);
  function replaceOnce(text, pattern, value) {
    if ((text.match(new RegExp(pattern.source, 'g')) || []).length !== 1) throw new Error(`Missing or duplicate version marker: ${pattern}`);
    return text.replace(pattern, value);
  }
  base = replaceOnce(base, /Public Const VersionBaseName As String = "[^"]*"/, `Public Const VersionBaseName As String = "${plan.version}"`);
  for (const attribute of ['AssemblyVersion', 'AssemblyFileVersion']) {
    assembly = replaceOnce(assembly, new RegExp(`<Assembly: ${attribute}\\("[^"]*"\\)>`), `<Assembly: ${attribute}("${plan.assemblyVersion}")>`);
  }
  const informational = `<Assembly: AssemblyInformationalVersion("${plan.version}")>`;
  if (assembly.includes('<Assembly: AssemblyInformationalVersion(')) {
    assembly = replaceOnce(assembly, /<Assembly: AssemblyInformationalVersion\("[^"]*"\)>/, informational);
  } else {
    const newline = assembly.includes('\r\n') ? '\r\n' : '\n';
    assembly += newline + informational + newline;
  }
  return { base, assembly, plan };
}
function stampVersion(root, tag) {
  const basePath = path.join(root, 'Plain Craft Launcher 2/Modules/Base/ModBase.vb');
  const assemblyPath = path.join(root, 'Plain Craft Launcher 2/My Project/AssemblyInfo.vb');
  const { base, assembly, plan } = versionContents(fs.readFileSync(basePath, 'utf8'), fs.readFileSync(assemblyPath, 'utf8'), tag);
  // 先校验全部标记，再写入。只改构建工作副本，不向仓库提交。
  fs.writeFileSync(basePath, base);
  fs.writeFileSync(assemblyPath, assembly);
  return plan;
}
if (require.main === module) stampVersion(process.cwd(), process.env.RELEASE_TAG || process.env.GITHUB_REF_NAME);
module.exports = { stampVersion, versionContents };
