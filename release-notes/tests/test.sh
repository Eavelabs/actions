#!/usr/bin/env bash
#
# release-notes action 的冒烟测试
#
# 直接在当前目录下运行：bash tests/test.sh
# 或在 CI 中：bash tests/test.sh
#
# 通过 TEST_MODE=1 直接调用 entrypoint.sh，与 action.yml 共享同一份逻辑，
# 避免两份实现漂移。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRYPOINT="$ROOT/entrypoint.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

pass=0
fail=0

# ---------------------------------------------------------------------------
# 运行 entrypoint.sh（TEST_MODE=1），解析输出。
# 输出行示例：
#   changes_b64=<base64>
#   changelog_file=...
#   version=1.0.0
#   tag=v1.0.0
#   title=...
#   prerelease=...
#   draft=...
# extra_env 可传额外环境变量（"K=V K2=V2"）。
# ---------------------------------------------------------------------------
run_entrypoint() {
  local changelog="$1" version="$2" extra_env="${3:-}" prefix="${4:-v}" name="${5:-}" suffix="${6:-}"
  local out b64
  out="$( \
    INPUT_CHANGELOG_PATH="$changelog" \
    INPUT_VERSION="$version" \
    INPUT_TAG_PREFIX="$prefix" \
    INPUT_RELEASE_NAME="$name" \
    INPUT_RELEASE_NAME_SUFFIX="$suffix" \
    INPUT_FALLBACK_TEXT="fallback" \
    TEST_MODE=1 \
    env $extra_env \
    bash "$ENTRYPOINT" \
  )"
  b64="$(echo "$out" | sed -n 's/^changes_b64=//p')"
  printf 'changes=%s\n' "$(printf '%s' "$b64" | base64 -d 2>/dev/null)"
  echo "$out" | sed -n '/^changes_b64=/!p'  # 其余行原样输出
}

# 辅助 getter：从 run_entrypoint 输出中取某字段
get_field() {
  local out="$1" field="$2"
  echo "$out" | sed -n "s/^${field}=//p"
}
changes_of()   { get_field "$1" "changes"; }
meta_title()   { get_field "$1" "title"; }
meta_tag()     { get_field "$1" "tag"; }
meta_version() { get_field "$1" "version"; }
meta_file()    { get_field "$1" "changelog_file"; }
meta_prerelease() { get_field "$1" "prerelease"; }
meta_draft()   { get_field "$1" "draft"; }

check_contains() {
  local name="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "  ✔ $name"; pass=$((pass + 1))
  else
    echo "  ✘ $name"; echo "    needle:   $needle"; echo "    haystack: $haystack"; fail=$((fail + 1))
  fi
}

check_not_contains() {
  local name="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    echo "  ✘ $name"; echo "    needle:   $needle"; echo "    haystack: $haystack"; fail=$((fail + 1))
  else
    echo "  ✔ $name"; pass=$((pass + 1))
  fi
}

check_eq() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" == "$actual" ]; then
    echo "  ✔ $name"; pass=$((pass + 1))
  else
    echo "  ✘ $name"; echo "    expected: $expected"; echo "    actual:   $actual"; fail=$((fail + 1))
  fi
}

echo "== 提取逻辑测试（复用 entrypoint.sh）=="

# --- 用例 1: 精确版本命中 ---
cat > "$TEST_DIR/ch1.md" <<'EOF'
# Changelog

## [Unreleased]
- 新的工作

## [1.0.0] - 2026-01-01
- 修复 bug
- 新增功能
EOF
out="$(run_entrypoint "$TEST_DIR/ch1.md" "1.0.0")"
check_contains "精确版本命中并含变更" "$(changes_of "$out")" "修复 bug"
check_not_contains "精确版本不混入 Unreleased" "$(changes_of "$out")" "新的工作"

# --- 用例 2: 版本缺失 -> Unreleased ---
out="$(run_entrypoint "$TEST_DIR/ch1.md" "2.0.0")"
check_contains "版本缺失回退 Unreleased" "$(changes_of "$out")" "新的工作"

# --- 用例 3: Unreleased 无有效变更 -> 下一个有内容版本 ---
cat > "$TEST_DIR/ch3.md" <<'EOF'
# Changelog

## [Unreleased]
（待补充）

## [0.9.0] - 2025-12-01
- 历史功能
EOF
out="$(run_entrypoint "$TEST_DIR/ch3.md" "2.0.0")"
check_contains "Unreleased空则取下一版本" "$(changes_of "$out")" "历史功能"

# --- 用例 4: 全部为空 -> 默认文案 ---
cat > "$TEST_DIR/ch4.md" <<'EOF'
# Changelog

## [Unreleased]
（待补充）
EOF
out="$(run_entrypoint "$TEST_DIR/ch4.md" "9.9.9")"
check_eq "全部为空回退默认文案" "$(changes_of "$out")" "fallback 9.9.9"

# --- 用例 5: 文件不存在 -> 默认文案 ---
out="$(run_entrypoint "$TEST_DIR/nope.md" "1.0.0")"
check_eq "文件不存在回退" "$(changes_of "$out")" "fallback 1.0.0"

# --- 用例 5b: 自定义 fallback 文案 ---
out="$(run_entrypoint "$TEST_DIR/nope.md" "1.0.0" "INPUT_FALLBACK_TEXT=custom-fallback")"
check_eq "自定义 fallback 文案" "$(changes_of "$out")" "custom-fallback 1.0.0"

# --- 用例 5c: 增强占位符识别（TODO/TBD/待定 视为无效）---
cat > "$TEST_DIR/ch5c.md" <<'EOF'
# Changelog

## [Unreleased]
- TODO
- TBD
- 待定内容

## [0.5.0] - 2025-01-01
- 真实功能
EOF
out="$(run_entrypoint "$TEST_DIR/ch5c.md" "3.0.0")"
check_contains "TODO/TBD/待定占位被跳过取下一版本" "$(changes_of "$out")" "真实功能"

echo "== 标题/tag 组装测试（复用 entrypoint.sh）=="

# --- 用例 6: 无项目名 ---
out="$(run_entrypoint "$TEST_DIR/ch1.md" "1.0.0")"
check_eq "无项目名标题" "$(meta_title "$out")" "v1.0.0"
check_eq "无项目名tag" "$(meta_tag "$out")" "v1.0.0"

# --- 用例 7: 有项目名 ---
out="$(run_entrypoint "$TEST_DIR/ch1.md" "1.0.0" "" "v" "MyApp")"
check_eq "有项目名标题" "$(meta_title "$out")" "MyApp v1.0.0"
check_eq "有项目名tag" "$(meta_tag "$out")" "v1.0.0"

# --- 用例 8: 项目名 + 后缀 ---
out="$(run_entrypoint "$TEST_DIR/ch1.md" "1.0.0" "" "v" "MyApp" " (Test)")"
check_eq "项目名+后缀标题" "$(meta_title "$out")" "MyApp v1.0.0 (Test)"

# --- 用例 9: 无项目名 + 后缀 ---
out="$(run_entrypoint "$TEST_DIR/ch1.md" "0.0.1b5" "" "v" "" " (Test)")"
check_eq "无项目名+后缀标题" "$(meta_title "$out")" "v0.0.1b5 (Test)"

# --- 用例 10: 误传带 v 的版本号 -> 不出现 vv ---
out="$(run_entrypoint "$TEST_DIR/ch1.md" "v0.0.1" "" "v" "Eavelabs actions")"
check_eq "误传v版本title无vv" "$(meta_title "$out")" "Eavelabs actions v0.0.1"
check_eq "误传v版本tag无vv" "$(meta_tag "$out")" "v0.0.1"
check_eq "误传v版本规范化" "$(meta_version "$out")" "0.0.1"

# --- 用例 10b: 误传带大写 V 的版本号 -> 不出现 vV ---
out="$(run_entrypoint "$TEST_DIR/ch1.md" "V0.0.1" "" "v" "Eavelabs actions")"
check_eq "误传V版本title无vV" "$(meta_title "$out")" "Eavelabs actions v0.0.1"
check_eq "误传V版本tag无vV" "$(meta_tag "$out")" "v0.0.1"
check_eq "误传V版本规范化" "$(meta_version "$out")" "0.0.1"

# --- 用例 10c: 版本号内/外含空白被清洗 ---
out="$(run_entrypoint "$TEST_DIR/ch1.md" " 1.0.0 " "" "v" "")"
check_eq "版本号空白清洗title" "$(meta_title "$out")" "v1.0.0"
check_eq "版本号空白清洗tag" "$(meta_tag "$out")" "v1.0.0"

# --- 用例 11: 自定义 tag 前缀 ---
out="$(run_entrypoint "$TEST_DIR/ch1.md" "1.0.0" "" "r" "MyApp")"
check_eq "自定义前缀标题" "$(meta_title "$out")" "MyApp r1.0.0"
check_eq "自定义前缀tag" "$(meta_tag "$out")" "r1.0.0"

# --- 用例 12: tag_prefix 传大写 V -> 统一转小写 v ---
out="$(run_entrypoint "$TEST_DIR/ch1.md" "1.0.0" "" "V" "MyApp")"
check_eq "大写前缀V转小写标题" "$(meta_title "$out")" "MyApp v1.0.0"
check_eq "大写前缀V转小写tag" "$(meta_tag "$out")" "v1.0.0"

echo "== 场景 c: 从 GITHUB_REF 自动推导版本号 =="

# --- 用例 13: ref 自动推导版本号，未显式传 version ---
out="$(run_entrypoint "$TEST_DIR/ch1.md" "" "GITHUB_REF=refs/tags/v1.2.3 INPUT_DERIVE_VERSION_FROM_REF=true")"
check_eq "ref推导版本" "$(meta_version "$out")" "1.2.3"
check_eq "ref推导tag" "$(meta_tag "$out")" "v1.2.3"
check_contains "ref推导无对应版本则回退Unreleased" "$(changes_of "$out")" "新的工作"

# --- 用例 13b: ref 版本恰好存在时精确命中 ---
out="$(run_entrypoint "$TEST_DIR/ch1.md" "" "GITHUB_REF=refs/tags/v1.0.0 INPUT_DERIVE_VERSION_FROM_REF=true")"
check_contains "ref版本存在则精确命中" "$(changes_of "$out")" "修复 bug"

# --- 用例 14: ref 带大写 V / 自定义前缀 ---
out="$(run_entrypoint "$TEST_DIR/ch1.md" "" "GITHUB_REF=refs/tags/V2.0.0 INPUT_DERIVE_VERSION_FROM_REF=true")"
check_eq "ref大写V推导" "$(meta_version "$out")" "2.0.0"

out="$(run_entrypoint "$TEST_DIR/ch1.md" "" "GITHUB_REF=refs/tags/r3.1.0 INPUT_DERIVE_VERSION_FROM_REF=true" "r")"
check_eq "ref自定义前缀推导" "$(meta_version "$out")" "3.1.0"
check_eq "ref自定义前缀tag" "$(meta_tag "$out")" "r3.1.0"

# --- 用例 15: 未开启推导且未传版本 -> 回退 unknown ---
out="$(run_entrypoint "$TEST_DIR/ch1.md" "" "GITHUB_REF=refs/tags/v1.2.3")"
check_eq "未开启推导回退unknown" "$(meta_version "$out")" "unknown"
check_eq "unknown回退tag" "$(meta_tag "$out")" "vunknown"

echo "== 场景 d: 多候选 changelog 路径 =="

# --- 用例 16: globs 按序取第一个存在者 ---
out="$(run_entrypoint "$TEST_DIR/nope.md" "1.0.0" "INPUT_CHANGELOG_GLOBS=$TEST_DIR/nope.md,$TEST_DIR/ch1.md")"
check_contains "globs取第二个存在文件" "$(changes_of "$out")" "修复 bug"
check_eq "globs选中的文件" "$(meta_file "$out")" "$TEST_DIR/ch1.md"

# --- 用例 17: globs 全部不存在 -> 用默认 changelog_path（也回退） ---
out="$(run_entrypoint "$TEST_DIR/nope.md" "1.0.0" "INPUT_CHANGELOG_GLOBS=$TEST_DIR/x.md,$TEST_DIR/y.md")"
check_eq "globs全不存在回退默认文案" "$(changes_of "$out")" "fallback 1.0.0"

echo "== 场景 a: release_type 便捷参数 =="

# --- 用例 18: release_type=stable -> prerelease=false, draft=false ---
out="$(run_entrypoint "$TEST_DIR/ch1.md" "1.0.0" "INPUT_RELEASE_TYPE=stable INPUT_PRERELEASE=true INPUT_DRAFT=true")"
check_eq "stable强制稳定" "$(meta_prerelease "$out")" "false"
check_eq "stable非草稿" "$(meta_draft "$out")" "false"

# --- 用例 19: release_type=preview -> prerelease=true ---
out="$(run_entrypoint "$TEST_DIR/ch1.md" "1.0.0" "INPUT_RELEASE_TYPE=preview")"
check_eq "preview预发布" "$(meta_prerelease "$out")" "true"

# --- 用例 20: release_type=draft -> draft=true ---
out="$(run_entrypoint "$TEST_DIR/ch1.md" "1.0.0" "INPUT_RELEASE_TYPE=draft")"
check_eq "draft草稿" "$(meta_draft "$out")" "true"

# --- 用例 21: 不指定 release_type -> 保留输入的 prerelease/draft ---
out="$(run_entrypoint "$TEST_DIR/ch1.md" "1.0.0" "INPUT_PRERELEASE=true")"
check_eq "保留输入prerelease" "$(meta_prerelease "$out")" "true"

echo
echo "通过: $pass  失败: $fail"
[ "$fail" -eq 0 ] || exit 1
