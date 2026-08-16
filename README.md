<div align="center">

# ⚙️ actions

**可复用的 GitHub Composite Actions 集合**

以**多 action 集合**方式组织，每个 action 独立一个目录，方便持续扩展。

[![GitHub release](https://img.shields.io/github/v/release/Eavelabs/actions?style=flat-square&label=release)](https://github.com/Eavelabs/actions/releases)
[![GitHub Actions workflow status](https://img.shields.io/github/actions/workflow/status/Eavelabs/actions/test.yml?style=flat-square&label=CI%20Tests)](https://github.com/Eavelabs/actions/actions)
[![GitHub repo size](https://img.shields.io/github/repo-size/Eavelabs/actions?style=flat-square&label=repo%20size)](https://github.com/Eavelabs/actions)
[![GitHub stars](https://img.shields.io/github/stars/Eavelabs/actions?style=flat-square&label=Stars&logo=github)](https://github.com/Eavelabs/actions/stargazers)
[![License](https://img.shields.io/github/license/Eavelabs/actions?style=flat-square&label=License&color=blue)](LICENSE)

</div>

## 📦 Actions 索引

| Action | 目录 | 说明 |
|---|---|---|
| [release-notes](./release-notes/README.md) | `release-notes/` | 从 `CHANGELOG.md` 提取版本内容并创建 GitHub Release |

## 用法

每个 action 通过 `uses: <owner>/actions/<name>@<tag>` 引用，例如：

```yaml
steps:
  - uses: actions/checkout@v6
  - name: 🚀 Create Release
    uses: Eavelabs/actions/release-notes@v1
    with:
      version: "1.0.0"
    env:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

> **关于 owner**：`uses:` 路径必须是字面量，不支持变量。本仓库 owner 为 `Eavelabs`，若你 fork 或改名为其他 owner，请把示例中的 `Eavelabs` 替换为你的新地址；本仓库自己的 workflow（`.github/workflows/release.yml`）已用 `./release-notes` 本地路径引用，**不受 owner 变化影响**。

具体参数见各 action 自己的 README。

## 项目结构

```
.
├── release-notes/               # 第 1 个 action（每个 action 平铺一个目录）
│   ├── action.yml               #   action 定义
│   ├── README.md                #   该 action 文档
│   ├── src/                     #   脚本实现（如需）
│   └── tests/                   #   该 action 测试
├── .github/
│   ├── CODEOWNERS.md            # 代码所有者约定
│   └── workflows/               # 仓库级 CI（测试所有 action）
├── CONTRIBUTING.md              # 新增/修改 action 的指南
├── LICENSE
└── README.md
```

## 新增一个 action

1. 在仓库根目录新建独立目录 `<name>/`
2. 添加 `action.yml`（composite action 定义）
3. 添加 `README.md`（文档：用法 / inputs / outputs / 示例）
4. 如需脚本，放在 `src/`；如需测试，放在 `tests/`（参考 `release-notes/tests/test.sh`）
5. 在本 README 的 Actions 表格中登记
6. 打 tag（建议保留 `v1` 移动 tag 指向最新 v1.x）

详细规范见 [CONTRIBUTING.md](./CONTRIBUTING.md)。

## 版本管理

- 使用语义化版本 tag：`v1`、`v1.0.0`
- 建议维护一个 `v1` 移动 tag 指向最新 v1.x，调用方用 `@v1` 即可平滑升级
