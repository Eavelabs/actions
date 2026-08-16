# release-notes

从仓库的 `CHANGELOG.md` 提取版本对应内容，并创建 GitHub Release。

这是 actions 集合中的 **第 1 个 action**（release note 相关）。

## 特性

**多级 fallback 提取**：精确版本 → `[Unreleased]` → 下一个有实际内容的版本章节 → 默认文案（绝不报错、不返回空）。

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
| `version` | 版本号（必须） | — |
| `tag_prefix` | tag 前缀 | `v` |
| `prerelease` | 标记为预发布 | `false` |
| `draft` | 创建为草稿 | `false` |
| `release_name_suffix` | release 标题后缀（如 ` (Test)`） | 空 |
| `release_name` | release 标题中的项目名（如 `MyApp`），不填则标题只含版本号 | 空 |
| `changelog_path` | CHANGELOG.md 路径 | `CHANGELOG.md` |
| `extra_body` | 附加到更新内容之后的 Markdown | 空 |
| `fallback_text` | 无内容时的默认文案 | `Release version` |
| `files` | 附加发行包文件（如 `dist/*`） | 空 |

## outputs

| 参数 | 说明 |
|---|---|
| `version` | 使用的版本 |
| `tag` | 创建的 tag |
| `changes` | 提取的更新内容 |

## 示例

**预发布（测试环境）**：
```yaml
- uses: Eavelabs/actions/release-notes@v1
  with:
    version: "0.0.1b5"
    prerelease: "true"
    release_name_suffix: " (Test)"
```

**正式发布（含发行包，自定义标题项目名）**：
```yaml
- uses: Eavelabs/actions/release-notes@v1
  with:
    version: "1.0.0"
    prerelease: "false"
    release_name: "MyApp"
    files: "dist/*"
```
