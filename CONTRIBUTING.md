# 贡献指南

本仓库是可复用的 GitHub Composite Actions **集合**。每个 action 独立成目录，遵循统一约定。

## 目录约定

每个 action 在仓库根目录平铺一个目录 `<name>/`：

```
<name>/
├── action.yml      # action 定义（必须）
├── README.md       # 该 action 文档：用法 / inputs / outputs / 示例（必须）
├── src/            # 脚本实现（如需）
└── tests/          # 该 action 测试（推荐）
```

## 命名规则

- 目录名使用短横线命名（kebab-case），如 `release-notes`、`check-license`。
- 引用方式：`uses: <owner>/actions/<name>@v1`（`<owner>` 为仓库所属用户名/组织）。
- `name` / `description` 写清楚用途，不要以 `<name> action` 开头（GitHub 会显示在 marketplace）。

## 新增 action 清单

1. 在仓库根目录新建目录 `<name>/` 并编写 `action.yml`
2. 编写 `README.md`（含 inputs / outputs 表格、至少一个完整示例）
3. 若逻辑复杂，将核心逻辑抽到 `src/` 脚本，并写 `tests/` 测试
4. 在根 `README.md` 的 Actions 表格中登记
5. 在 `.github/CODEOWNERS.md` 中登记负责人（如需）

## 测试

- 每个 action 的测试放在其 `tests/` 下，使用纯 shell 脚本，可在本地与 CI 运行。
- 仓库级 CI（`.github/workflows/test.yml`）会遍历所有 action 的 `tests/` 并执行。

本地运行单个 action 测试：

```bash
bash release-notes/tests/test.sh
```

## 版本 / tag

- 用语义化版本 tag：`v1`、`v1.0.0`、`v1.0.1`。
- 不破坏兼容的变更推进 `v1` 移动 tag；破坏性变更升 `v2`。
- 调用方建议固定到 `@v1`（移动 tag）以获得小版本自动更新。
