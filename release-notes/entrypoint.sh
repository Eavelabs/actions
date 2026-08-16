#!/usr/bin/env bash
#
# release-notes action 的核心逻辑入口。
#
# 在 CI（GitHub Actions composite step）中运行：
#   bash "${GITHUB_ACTION_PATH}/entrypoint.sh"
#
# 需要的环境变量（由 action.yml 传入）：
#   INPUT_VERSION           版本号；若为空且 INPUT_DERIVE_VERSION_FROM_REF=true，
#                           则从 GITHUB_REF（refs/tags/v1.2.3）自动推导
#   INPUT_TAG_PREFIX        tag 前缀，默认 "v"
#   INPUT_CHANGELOG_PATH    CHANGELOG 路径（单文件），默认 "CHANGELOG.md"
#   INPUT_CHANGELOG_GLOBS   逗号/换行分隔的多个候选路径，按序取第一个存在者
#   INPUT_FALLBACK_TEXT     无内容时的默认文案，默认 "Release version"
#   INPUT_RELEASE_NAME      release 标题中的项目名，默认空
#   INPUT_RELEASE_NAME_SUFFIX  release 标题后缀，默认空
#   INPUT_DERIVE_VERSION_FROM_REF  "true" 时从 GITHUB_REF 推导版本号
#   GITHUB_REF              （可选）GitHub 提供的 ref，如 refs/tags/v1.2.3
#   TEST_MODE               若为 "1"，改为向 stdout 打印（用于单测），而非写 $GITHUB_OUTPUT
#
# 在 TEST_MODE 下输出（每行一个）：
#   changes_b64  (以 base64 编码，避免换行/特殊字符干扰 stdout 解析)
#   changelog_file  (实际选中的 changelog 文件；无则为空)
#   version
#   tag
#   title
#
# 在 CI 模式下写入 $GITHUB_OUTPUT：
#   changes / changelog_file / version / tag / title
set -euo pipefail

# ---------------------------------------------------------------------------
# 从 changelog 提取某个 `## [SECTION]` 章节正文（多行，可带 ` - 日期` 后缀）。
# 使用 awk 的 index() 做"字符串匹配"（非正则），避免版本号中的 `[` `]` `.`
# 被当作正则元字符。
# ---------------------------------------------------------------------------
extract() {
  local changelog="$1" sec="$2"
  awk -v sec="$sec" 'BEGIN{found=0; buf=""; pfx="## [" sec "]"}
    /^## \[/ {
      if (found) exit
      if (index($0, pfx) == 1) {
        r = substr($0, length(pfx)+1, 1)
        if (r == "" || r == " ") found=1
      }
      next
    }
    found { buf = buf $0 "\n" }
    END { printf "%s", buf }' "$changelog"
}

# 判断内容是否含"有效变更"：排除说明(>)、标题(#)、分隔线(---)、空行、
# 以及各种语言的占位符。
has_content() {
  local text="$1" line
  # 逐行过滤，只要有一行是"真实内容"即判定有效
  while IFS= read -r line; do
    # 空行
    if [[ -z "${line//[[:space:]]/}" ]]; then continue; fi
    # Markdown 标题 / 引用 / 分隔线
    if [[ "$line" =~ ^[[:space:]]*# ]]; then continue; fi
    if [[ "$line" =~ ^[[:space:]]*'>>' ]]; then continue; fi
    if [[ "$line" =~ ^[[:space:]]*---+[[:space:]]*$ ]]; then continue; fi
    # 占位符：中英文常见占位
    case "$line" in
      *"待补充"*|*"待定"*|*"TODO"*|*"TBD"*|*"WIP"*|*"coming soon"*|*"coming-soon"*|*"占位"*) continue ;;
    esac
    # 找到第一行真实内容即可
    echo "$line" | grep -q . && return 0
  done <<< "$text"
  return 1
}

# ---------------------------------------------------------------------------
# 4 级 fallback：
#   1) 精确版本章节
#   2) [Unreleased]（若含有效变更）
#   3) 下一个有实际内容的版本章节
#   4) 默认文案（绝不报错、不返回空）
# ---------------------------------------------------------------------------
resolve_changes() {
  local changelog="$1" version="$2" fallback_text="$3"
  local changes unrel c sec
  if [ ! -f "$changelog" ]; then
    printf "%s %s" "$fallback_text" "$version"
    return
  fi
  changes="$(extract "$changelog" "$version")"
  if [ -z "$changes" ]; then
    unrel="$(extract "$changelog" "Unreleased")"
    if has_content "$unrel"; then changes="$unrel"; fi
  fi
  if [ -z "$changes" ]; then
    for sec in $(awk '/^## \[/ && $0 !~ /Unreleased/ {gsub(/^## \[/,""); gsub(/\].*$/,""); print}' "$changelog"); do
      c="$(extract "$changelog" "$sec")"
      if has_content "$c"; then changes="$c"; break; fi
    done
  fi
  if [ -z "$changes" ]; then
    changes="$fallback_text $version"
  fi
  printf "%s" "$changes"
}

# ---------------------------------------------------------------------------
# 在多个候选路径中，按序取第一个实际存在的文件。
# 输入：以逗号或换行分隔的路径列表；输出：第一个存在的文件（无则空）。
# ---------------------------------------------------------------------------
pick_changelog() {
  local globs="$1" path
  local IFS=$'\n,'
  for path in $globs; do
    # 去掉首尾空白
    path="${path#"${path%%[![:space:]]*}"}"   # 去前导空白
    path="${path%"${path##*[![:space:]]}"}"   # 去尾随空白
    [ -z "$path" ] && continue
    if [ -f "$path" ]; then
      printf '%s' "$path"
      return 0
    fi
  done
  return 0  # 无则返回空
}

# ---------------------------------------------------------------------------
# 版本号 / tag / 标题组装。
# ---------------------------------------------------------------------------
compose_meta() {
  local raw_version="$1" raw_prefix="$2" rel_name="$3" rel_suffix="$4"
  local version prefix title tag
  version="$(printf '%s' "$raw_version" | tr -d '[:space:]')"   # 清洗所有空白
  # 去掉可能误传的 'v'/'V' 前缀（如 "v1.0.0" / "V1.0.0" -> "1.0.0"），避免标题/tag 出现 vv / vV
  if [[ "$version" == [vV]* ]]; then version="${version:1}"; fi
  prefix="$(printf '%s' "${raw_prefix:-v}" | tr 'A-Z' 'a-z')"   # 前缀统一转小写
  if [ -z "$prefix" ]; then prefix="v"; fi
  if [ -n "$rel_name" ]; then
    title="${rel_name} ${prefix}${version}${rel_suffix}"
  else
    title="${prefix}${version}${rel_suffix}"
  fi
  tag="${prefix}${version}"
  printf "%s\n%s\n%s" "$title" "$tag" "$version"
}

# ---------------------------------------------------------------------------
# 从 GitHub ref 推导版本号。
# 输入：GITHUB_REF（如 refs/tags/v1.2.3）、tag 前缀（如 v）；输出：版本号（无则空）。
# 规则：取 refs/tags/<prefix><ver> 中前缀之后的剩余部分。
# ---------------------------------------------------------------------------
derive_version_from_ref() {
  local ref="$1" prefix="$2"
  local tail ver
  if [[ "$ref" != refs/tags/* ]]; then
    printf ''
    return 0
  fi
  tail="${ref#refs/tags/}"
  # 去掉 tag 前缀（前缀统一为小写形式，ref 中的 v/V 也容错）
  if [ -n "$prefix" ]; then
    # 先尝试去掉指定前缀（如 r、release-）
    if [[ "$tail" == "$prefix"* ]]; then
      tail="${tail#"$prefix"}"
    # 前缀为空或为 "v" 时，也兼容单字母 v/V
    elif [[ "$tail" =~ ^[vV] ]]; then
      tail="${tail:1}"
    fi
  elif [[ "$tail" =~ ^[vV] ]]; then
    tail="${tail:1}"
  fi
  # 去掉可能残留的空白；非纯数字版本（如 awesome）也原样返回
  printf '%s' "$(printf '%s' "$tail" | tr -d '[:space:]')"
}

# ===========================================================================
main() {
  local version="${INPUT_VERSION:-}"
  local prefix="${INPUT_TAG_PREFIX:-v}"
  local changelog="${INPUT_CHANGELOG_PATH:-CHANGELOG.md}"
  local changelog_globs="${INPUT_CHANGELOG_GLOBS:-}"
  local fallback="${INPUT_FALLBACK_TEXT:-Release version}"
  local rel_name="${INPUT_RELEASE_NAME:-}"
  local rel_suffix="${INPUT_RELEASE_NAME_SUFFIX:-}"
  local derive="${INPUT_DERIVE_VERSION_FROM_REF:-false}"
  local release_type="${INPUT_RELEASE_TYPE:-}"
  local prerelease="${INPUT_PRERELEASE:-false}"
  local draft="${INPUT_DRAFT:-false}"
  local test_mode="${TEST_MODE:-0}"

  # a) 便捷 release 类型映射：一键设置 prerelease / draft
  #    优先级：显式传的 prerelease/draft > release_type 推导
  case "$release_type" in
    stable)    prerelease=false; draft=false ;;
    preview|beta|rc|alpha) prerelease=true; draft=false ;;
    draft)     prerelease=false; draft=true ;;
    ""|*)      ;;  # 未指定则保持输入的 prerelease/draft 原值
  esac

  # d) 多候选 changelog：若提供了 globs，则按序取第一个存在的文件
  local picked_file=""
  if [ -n "$changelog_globs" ]; then
    picked_file="$(pick_changelog "$changelog_globs")"
    if [ -n "$picked_file" ]; then
      changelog="$picked_file"
    fi
  fi

  # c) 从 ref 自动推导版本号：仅当未显式传 version 且开启推导时
  if [ -z "$version" ] && [ "$derive" = "true" ]; then
    version="$(derive_version_from_ref "${GITHUB_REF:-}" "$prefix")"
  fi
  # 若最终仍无版本号，给出提示并回退（避免空 tag）
  if [ -z "$version" ]; then
    version="unknown"
  fi

  local changes title tag clean_version
  changes="$(resolve_changes "$changelog" "$version" "$fallback")"
  # 组装标题/tag/规范化版本
  title="$(compose_meta "$version" "$prefix" "$rel_name" "$rel_suffix" | sed -n '1p')"
  tag="$(compose_meta "$version" "$prefix" "$rel_name" "$rel_suffix" | sed -n '2p')"
  clean_version="$(compose_meta "$version" "$prefix" "$rel_name" "$rel_suffix" | sed -n '3p')"

  if [ "$test_mode" = "1" ]; then
    # 单测模式：base64 编码 changes 避免换行干扰，其余逐行输出
    printf 'changes_b64=%s\n' "$(printf '%s' "$changes" | base64 -w 0)"
    printf 'changelog_file=%s\n' "$changelog"
    printf 'version=%s\n' "$clean_version"
    printf 'tag=%s\n' "$tag"
    printf 'title=%s\n' "$title"
    printf 'prerelease=%s\n' "$prerelease"
    printf 'draft=%s\n' "$draft"
  else
    {
      printf 'changelog_file=%s\n' "$changelog"
      printf 'version=%s\n' "$clean_version"
      printf 'tag=%s\n' "$tag"
      printf 'title=%s\n' "$title"
      printf 'prerelease=%s\n' "$prerelease"
      printf 'draft=%s\n' "$draft"
    } >> "$GITHUB_OUTPUT"
    printf 'changes<<__CHANGELOG_EOF__\n%s\n__CHANGELOG_EOF__\n' "$changes" >> "$GITHUB_OUTPUT"
  fi
}

main "$@"
