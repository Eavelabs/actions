#!/usr/bin/env bash
#
# release-notes action 的冒烟测试
#
# 直接在当前目录下运行：bash tests/test.sh
# 或在 CI 中：bash tests/test.sh
#
# 验证核心的"多级 fallback 提取"逻辑，不真正创建 GitHub Release。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

pass=0
fail=0

# 从 action.yml 中抽取 changelog 提取逻辑到独立的可测函数。
# 这里把 action.yml 的 bash 提取逻辑内联为函数进行黑盒测试。
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

has_content() {
  echo "$1" | grep -v '^[[:space:]]*$' | grep -v '^#' | grep -v '^>' \
    | grep -v '^---' | grep -v '（待补充）' | grep -q .
}

# resolve: 实现与 action.yml 相同的 4 级 fallback
resolve() {
  local changelog="$1" version="$2"
  local changes unrel c
  if [ -f "$changelog" ]; then
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
    if [ -z "$changes" ]; then changes="fallback $version"; fi
  else
    changes="fallback $version"
  fi
  printf "%s" "$changes"
}

# compose_meta: 实现与 action.yml 的 🔧 Normalize version & compose release title 步骤相同的逻辑
# 输出：title（第1行）、tag（第2行）、version（第3行）
compose_meta() {
  local name="$1" raw_version="$2" suffix="$3" prefix="$4"
  local version title tag
  version="$raw_version"
  if [[ "$version" == [vV]* ]]; then version="${version:1}"; fi  # 去掉误传的 'v'/'V' 前缀
  prefix="$(printf '%s' "${prefix:-v}" | tr 'A-Z' 'a-z')"        # 前缀统一转小写
  if [ -z "$prefix" ]; then prefix="v"; fi
  if [ -n "$name" ]; then
    title="${name} ${prefix}${version}${suffix}"
  else
    title="${prefix}${version}${suffix}"
  fi
  tag="${prefix}${version}"
  printf "%s\n%s\n%s\n" "$title" "$tag" "$version"
}

check_contains() {
  local name="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    echo "  ✔ $name"
    pass=$((pass + 1))
  else
    echo "  ✘ $name"
    echo "    needle:   $needle"
    echo "    haystack: $haystack"
    fail=$((fail + 1))
  fi
}

check_not_contains() {
  local name="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF -- "$needle"; then
    echo "  ✘ $name"
    echo "    needle:   $needle"
    echo "    haystack: $haystack"
    fail=$((fail + 1))
  else
    echo "  ✔ $name"
    pass=$((pass + 1))
  fi
}

check_eq() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" == "$actual" ]; then
    echo "  ✔ $name"
    pass=$((pass + 1))
  else
    echo "  ✘ $name"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    fail=$((fail + 1))
  fi
}

echo "== release-notes 提取逻辑测试 =="

# --- 用例 1: 精确版本命中 ---
cat > "$TEST_DIR/ch1.md" <<'EOF'
# Changelog

## [Unreleased]
- 新的工作

## [1.0.0] - 2026-01-01
- 修复 bug
- 新增功能
EOF
check_contains "精确版本命中并含变更" "$(resolve "$TEST_DIR/ch1.md" "1.0.0")" "修复 bug"
check_not_contains "精确版本不混入 Unreleased" "$(resolve "$TEST_DIR/ch1.md" "1.0.0")" "新的工作"

# --- 用例 2: 版本缺失 -> Unreleased ---
check_contains "版本缺失回退 Unreleased" "$(resolve "$TEST_DIR/ch1.md" "2.0.0")" "新的工作"

# --- 用例 3: Unreleased 无有效变更 -> 下一个有内容版本 ---
cat > "$TEST_DIR/ch3.md" <<'EOF'
# Changelog

## [Unreleased]
（待补充）

## [0.9.0] - 2025-12-01
- 历史功能
EOF
check_contains "Unreleased空则取下一版本" "$(resolve "$TEST_DIR/ch3.md" "2.0.0")" "历史功能"

# --- 用例 4: 全部为空 -> 默认文案 ---
cat > "$TEST_DIR/ch4.md" <<'EOF'
# Changelog

## [Unreleased]
（待补充）
EOF
check_eq "全部为空回退默认文案" "$(resolve "$TEST_DIR/ch4.md" "9.9.9")" "fallback 9.9.9"

# --- 用例 5: 文件不存在 -> 默认文案 ---
check_eq "文件不存在回退" "$(resolve "$TEST_DIR/nope.md" "1.0.0")" "fallback 1.0.0"

echo "== release-notes 标题/tag 组装测试 =="

# 辅助：取 compose_meta 输出的第 N 行（1=title, 2=tag, 3=version）
meta_title()  { compose_meta "$@" | sed -n '1p'; }
meta_tag()    { compose_meta "$@" | sed -n '2p'; }
meta_version() { compose_meta "$@" | sed -n '3p'; }

# --- 用例 6: 无项目名 -> 只有版本 ---
check_eq "无项目名标题" "$(meta_title "" "1.0.0" "" "")" "v1.0.0"
check_eq "无项目名tag" "$(meta_tag "" "1.0.0" "" "")" "v1.0.0"

# --- 用例 7: 有项目名 ---
check_eq "有项目名标题" "$(meta_title "MyApp" "1.0.0" "" "")" "MyApp v1.0.0"
check_eq "有项目名tag" "$(meta_tag "MyApp" "1.0.0" "" "")" "v1.0.0"

# --- 用例 8: 项目名 + 后缀 ---
check_eq "项目名+后缀标题" "$(meta_title "MyApp" "1.0.0" " (Test)" "")" "MyApp v1.0.0 (Test)"

# --- 用例 9: 无项目名 + 后缀 ---
check_eq "无项目名+后缀标题" "$(meta_title "" "0.0.1b5" " (Test)" "")" "v0.0.1b5 (Test)"

# --- 用例 10: 误传带 v 的版本号 -> 不出现 vv ---
check_eq "误传v版本title无vv" "$(meta_title "Eavelabs actions" "v0.0.1" "" "")" "Eavelabs actions v0.0.1"
check_eq "误传v版本tag无vv" "$(meta_tag "Eavelabs actions" "v0.0.1" "" "")" "v0.0.1"
check_eq "误传v版本规范化" "$(meta_version "Eavelabs actions" "v0.0.1" "" "")" "0.0.1"

# --- 用例 10b: 误传带大写 V 的版本号 -> 不出现 vV ---
check_eq "误传V版本title无vV" "$(meta_title "Eavelabs actions" "V0.0.1" "" "")" "Eavelabs actions v0.0.1"
check_eq "误传V版本tag无vV" "$(meta_tag "Eavelabs actions" "V0.0.1" "" "")" "v0.0.1"
check_eq "误传V版本规范化" "$(meta_version "Eavelabs actions" "V0.0.1" "" "")" "0.0.1"

# --- 用例 11: 自定义 tag 前缀 ---
check_eq "自定义前缀标题" "$(meta_title "MyApp" "1.0.0" "" "r")" "MyApp r1.0.0"
check_eq "自定义前缀tag" "$(meta_tag "MyApp" "1.0.0" "" "r")" "r1.0.0"

# --- 用例 12: tag_prefix 传大写 V -> 统一转小写 v ---
check_eq "大写前缀V转小写标题" "$(meta_title "MyApp" "1.0.0" "" "V")" "MyApp v1.0.0"
check_eq "大写前缀V转小写tag" "$(meta_tag "MyApp" "1.0.0" "" "V")" "v1.0.0"

echo
echo "通过: $pass  失败: $fail"
[ "$fail" -eq 0 ] || exit 1
