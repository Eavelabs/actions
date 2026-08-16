# release-notes

从仓库的 `CHANGELOG.md` 提取版本对应内容，并创建 GitHub Release。

这是 actions 集合中的 **第 1 个 action**（release note 相关）。

## 特性

**多级 fallback 提取**：精确版本 → `[Unreleased]` → 下一个有实际内容的版本章节 → 默认文案（绝不报错、不返回空）。

- **占位符智能识别**：`待补充`、`待定`、`TODO`、`TBD`、`WIP`、`coming soon`、`占位` 等均视为"无有效变更"。
- **版本号容错**：自动清洗版本号内的空白，去掉误传的 `v`/`V` 前缀（避免 `vv1.0.0`），tag 前缀统一小写。
- **单份逻辑**：提取与组装逻辑收敛在独立 `entrypoint.sh`，测试直接复用，杜绝 `action.yml` 与测试各自维护一份导致漂移。
- **多场景支持**：可从 tag 自动推导版本、可在多个 changelog 路径间回退、可用 `release_type` 一键切换发布类型。

## 用法

```yaml
steps:
  - uses: actions/checkout@v6
  - name: 🚀 Create Release
    uses: Eavelabs/actions/release-notes@v1
    with:
      version: "1.0.0"
      prerelease: "false"
    env:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## inputs

| 参数 | 说明 | 默认 |
|---|---|---|
| `version` | 版本号（如 `1.0.0`）。不填且 `derive_version_from_ref=true` 时从 tag 自动推导 | 空 |
| `tag_prefix` | tag 前缀 | `v` |
| `prerelease` | 标记为预发布 | `false` |
| `draft` | 创建为草稿 | `false` |
| `release_type` | 发布类型快捷开关：`stable` / `preview` / `beta` / `rc` / `alpha` / `draft`，自动映射 prerelease/draft | 空 |
| `release_name_suffix` | release 标题后缀（如 ` (Test)`） | 空 |
| `release_name` | release 标题中的项目名（如 `MyApp`），不填则标题只含版本号 | 空 |
| `changelog_path` | CHANGELOG.md 路径 | `CHANGELOG.md` |
| `changelog_globs` | 逗号/换行分隔的多个候选 changelog 路径，按序取第一个存在者（优先于 `changelog_path`）。如 `docs/CHANGELOG.md,CHANGELOG.md` | 空 |
| `derive_version_from_ref` | `true` 时从 `GITHUB_REF`（如 `refs/tags/v1.2.3`）自动推导版本号 | `false` |
| `extra_body` | 附加到更新内容之后的 Markdown | 空 |
| `fallback_text` | 无内容时的默认文案 | `Release version` |
| `files` | 附加发行包文件（如 `dist/*`） | 空 |
| `generate_release_notes` | 是否在 changelog 内容之后附加 GitHub 自动生成的提交变更记录 | `false` |
| `target_commitish` | 指定 tag 从哪个 commit 创建（默认使用触发该 workflow 的 commit） | 空 |
| `discussion_category_name` | 将 release 关联到某个现有 discussion 的 category 名 | 空 |
| `fail_on_unmatched_files` | `files` 中有文件匹配不到资产时报错 | `false` |
| `replace_assets` | 上传前先移除同名的既有资产（避免重名冲突） | `false` |

## outputs

| 参数 | 说明 |
|---|---|
| `version` | 规范化后的版本（不含 tag 前缀） |
| `tag` | 创建的 tag |
| `title` | release 标题 |
| `changes` | 提取的更新内容 |
| `changelog_file` | 实际选中的 changelog 文件（配合 `changelog_globs`） |
| `prerelease` / `draft` | 生效的预发布/草稿标记（受 `release_type` 影响） |

## 示例

**预发布（测试环境）**：
```yaml
- uses: Eavelabs/actions/release-notes@v1
  with:
    version: "0.0.1b5"
    prerelease: "true"
    release_name_suffix: " (Test)"
```

**正式发布（含发行包，自定义标题项目名，附加自动变更记录）**：
```yaml
- uses: Eavelabs/actions/release-notes@v1
  with:
    version: "1.0.0"
    release_type: "stable"
    release_name: "MyApp"
    files: "dist/*"
    generate_release_notes: "true"
    replace_assets: "true"
```

**从 tag 自动推导版本号（推 `v1.2.3` 标签即触发，无需手动传 version）**：
```yaml
on:
  push:
    tags: [ 'v*' ]
jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v6
      - uses: Eavelabs/actions/release-notes@v1
        with:
          derive_version_from_ref: "true"   # 版本从 ${{ github.ref }} 自动读取
          release_type: "stable"
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**多 changelog 路径回退（changelog 可能在 `docs/` 或根目录）**：
```yaml
- uses: Eavelabs/actions/release-notes@v1
  with:
    version: "1.0.0"
    changelog_globs: "docs/CHANGELOG.md,CHANGELOG.md"
```

## 测试

```bash
bash tests/test.sh
```

测试通过 `TEST_MODE=1` 直接调用 `entrypoint.sh`，与 action 运行时的逻辑完全一致。
