# Changelog

本文件记录本仓库（Eavelabs/actions）自身的变更，遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/) 格式，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### 新增

- 首个 action：`release-notes`，从 `CHANGELOG.md` 提取版本内容（多级 fallback）并创建 GitHub Release
- 建立多 action 集合的仓库结构：每个 action 平铺一个独立目录
- 仓库级 CI：`.github/workflows/test.yml` 统一测试所有 action

### 修复

- 移除 `release-notes` 中硬编码的 `PySpring` 品牌名，新增 `release_name` input 以支持自定义 release 标题
- release 标题组装改为经 env 传入 shell 变量，避免内联替换导致的引号/特殊字符问题
- 将依赖 `softprops/action-gh-release` 升级到 `v2`（安全修复）
- `release.yml` 改用 `${{ inputs.* }}` 引用 workflow_dispatch 输入，避免 context 取值坑
- 规范化版本号，自动去掉误传的 `v`/`V` 前缀，避免标题/tag 出现重复前缀（如 `vv0.0.1`、`vV0.0.1`）
- tag 前缀统一转为小写 `v`，确保最终 tag/标题始终是 `v<编号>` 的小写形式

### 测试

- 为 `release-notes` 新增"标题/tag 组装 + 版本/前缀规范化"用例，测试脚本用例增至 22 个，全部通过
