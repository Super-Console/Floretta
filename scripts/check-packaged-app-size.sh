#!/usr/bin/env bash
# E4 packaged-app size gate.
#
# Budgets (strictly less than, 1024-based, same MB as docs/STREAMING.md):
#   iOS app    < 15 MiB
#   macOS app  < 25 MiB
#
# What is measured
# ---------------
# With --ios and --macos, the argument is the shipped bundle:
#   *.app        regular files inside that bundle
#   *.ipa        regular files inside Payload/*.app only
#                (not the zip, not SwiftSupport, not Symbols)
#   *.xcarchive  regular files inside Products/Applications/*.app
#                (not dSYMs)
# Intermediates.noindex, Index.noindex, ModuleCache.noindex, and *.dSYM
# are refused. This script does not run xcodebuild, sign, archive, or upload.
#
# With no path, GitHub Actions on ubuntu-24.04 has no Xcode and no macOS
# runner, so a Release .app/.ipa is not produced. The script then measures
# a reproducible stand-in and applies the same two budgets:
#   * every release FlorettaCore / FlorettaUI .swift.o from `swift build -c release`,
#     linked into a throwaway executable and stripped with `strip --strip-unneeded`
#     (DWARF stays out; it belongs in a dSYM, not the app). An empty Swift
#     executable built the same way is subtracted. libswift*.so is dynamic and
#     is not counted: the Swift runtime ships in iOS 26 and macOS 26.
#     SPM does not emit libFlorettaCore.so for this automatic library.
#   * counted once per app or appex that links that product, because
#     Package.swift leaves the library type automatic and Xcode static-links
#     it into each executable
#   * Copy Bundle Resources bytes (asset-catalog source files, not Assets.car)
#     plus each target's Release INFOPLIST_FILE
#     including embedded appex resources
# Not in that sum: Floretta/ SwiftUI Mach-O, SwiftFlow 0.3.1, the code
# signature. Those cannot be built on this runner. See docs/PACKAGED-SIZE.md.
#
# The script also fails if Floretta/, FlorettaCore/, or FlorettaUI/ ships a
# Node or Python runtime. scripts/make-app-icon.py is a maintainer tool and
# is not part of that scan.
#
# Usage (from the repo root):
#   scripts/check-packaged-app-size.sh
#   scripts/check-packaged-app-size.sh --self-test
#   scripts/check-packaged-app-size.sh --ios path/to/Floretta-iOS.app \
#       --macos path/to/Floretta-macOS.app
set -euo pipefail
# Command substitutions must keep failing when a nested call returns non-zero.
shopt -s inherit_errexit
export LC_ALL=C

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

IOS_BUDGET=$((15 * 1024 * 1024))
MACOS_BUDGET=$((25 * 1024 * 1024))

usage() {
  sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'
}

file_bytes() {
  if stat -c '%s' "$1" >/dev/null 2>&1; then
    stat -c '%s' "$1"
  else
    stat -f '%z' "$1"
  fi
}

bytes_of_path() {
  local p="$1" sum=0 s f
  if [[ -d "$p" ]]; then
    while IFS= read -r -d '' f; do
      s="$(file_bytes "$f")"
      sum=$((sum + s))
    done < <(find "$p" -type f -print0)
    echo "$sum"
  elif [[ -f "$p" ]]; then
    file_bytes "$p"
  else
    echo "not a file or directory: $p" >&2
    return 1
  fi
}

reject_junk_path() {
  local p="$1"
  case "$p" in
    *"/Intermediates.noindex/"*|*"/Intermediates/"*|*"/Index.noindex/"*|*"/ModuleCache.noindex/"*|*.dSYM|*.dSYM/*)
      echo "refusing DerivedData intermediates or dSYM (pass the .app, .ipa, or .xcarchive): $p" >&2
      return 1
      ;;
  esac
}

# Sum of regular files in a shipped .app. Symlinks are not followed.
measure_app_dir() {
  local app="$1"
  [[ -d "$app" ]] || { echo "app bundle is missing: $app" >&2; return 1; }
  case "$app" in
    *.app) ;;
    *) echo "expected a .app bundle: $app" >&2; return 1 ;;
  esac
  reject_junk_path "$app"
  bytes_of_path "$app"
}

# Prints the absolute .app path to measure for a user-supplied artifact.
resolve_bundle() {
  local input="$1" tmp apps=() app
  [[ -e "$input" ]] || { echo "bundle path does not exist: $input" >&2; return 1; }
  reject_junk_path "$input"
  case "$input" in
    *.app)
      echo "$input"
      ;;
    *.xcarchive)
      apps=("$input"/Products/Applications/*.app)
      [[ -d "${apps[0]}" ]] || { echo "xcarchive has no Products/Applications/*.app: $input" >&2; return 1; }
      if [[ ${#apps[@]} -ne 1 ]]; then
        echo "xcarchive has more than one .app: $input" >&2
        return 1
      fi
      echo "${apps[0]}"
      ;;
    *.ipa)
      tmp="$(mktemp -d)"
      unzip -q "$input" -d "$tmp"
      apps=("$tmp"/Payload/*.app)
      [[ -d "${apps[0]}" ]] || { echo "ipa has no Payload/*.app: $input" >&2; rm -rf "$tmp"; return 1; }
      if [[ ${#apps[@]} -ne 1 ]]; then
        echo "ipa has more than one Payload app: $input" >&2
        rm -rf "$tmp"
        return 1
      fi
      # Caller deletes nothing: the temp dir lives until process exit.
      # Record it so the shell trap can remove it.
      RESOLVE_TMP_DIRS+=("$tmp")
      echo "${apps[0]}"
      ;;
    *)
      echo "pass a .app, .ipa, or .xcarchive: $input" >&2
      return 1
      ;;
  esac
}

# Fails when a shipped tree contains a Node or Python runtime.
reject_runtime_tree() {
  local dir="$1" f base first
  [[ -d "$dir" ]] || return 0
  if find "$dir" -type d \( -name node_modules -o -name Python.framework -o -name python.framework \) -print -quit | grep -q .; then
    echo "Node or Python runtime directory under $dir" >&2
    find "$dir" -type d \( -name node_modules -o -name Python.framework -o -name python.framework \) -print >&2
    return 1
  fi
  while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    case "$base" in
      node|nodejs|node.exe|python|python.exe|python2|python3|electron|electron.exe|package.json)
        echo "Node or Python runtime file: $f" >&2
        return 1
        ;;
      python3.*)
        echo "Node or Python runtime file: $f" >&2
        return 1
        ;;
      *.py)
        echo "Python source in a shipped tree: $f" >&2
        return 1
        ;;
    esac
    first="$(head -n 1 "$f" 2>/dev/null || true)"
    case "$first" in
      '#!'*node*| '#!'*python*)
        echo "Node or Python shebang in a shipped tree: $f" >&2
        return 1
        ;;
    esac
  done < <(find "$dir" -type f -print0)
}

reject_runtime_package() {
  local hit
  hit="$(grep -nE 'https?://[^" ]*(nodejs|python\.org|electron|pypi)[^" ]*' Package.swift || true)"
  if [[ -n "$hit" ]]; then
    echo "Package.swift depends on a Node, Python, or Electron package:" >&2
    echo "$hit" >&2
    return 1
  fi
  hit="$(grep -nE '"(Node|Python|PythonKit|Electron|NPM)"' Package.swift || true)"
  if [[ -n "$hit" ]]; then
    echo "Package.swift names a Node, Python, or Electron product:" >&2
    echo "$hit" >&2
    return 1
  fi
}

reject_shipped_runtimes() {
  reject_runtime_tree "$root/Floretta"
  reject_runtime_tree "$root/FlorettaCore"
  reject_runtime_tree "$root/FlorettaUI"
  reject_runtime_package
}

report_budget() {
  local platform="$1" bytes="$2" budget="$3" mib
  mib="$(awk -v b="$bytes" 'BEGIN { printf "%.3f", b/1024/1024 }')"
  if (( bytes >= budget )); then
    echo "FAIL ${platform} payload ${bytes} bytes (${mib} MiB) is not under ${budget} bytes" >&2
    return 1
  fi
  echo "ok ${platform} payload ${bytes} bytes (${mib} MiB) < ${budget} bytes"
}

# --- Xcode project -----------------------------------------------------------

parse_pbxproj() {
  local prog
  prog="$(mktemp)"
  cat >"$prog" <<'END_AWK'
function nchar(s, ch,    n, i) {
  n = 0
  for (i = 1; i <= length(s); i++) if (substr(s, i, 1) == ch) n++
  return n
}
function leading_id(line,    i, c, id) {
  i = 1
  while (substr(line, i, 1) == " " || substr(line, i, 1) == "\t") i++
  id = ""
  c = substr(line, i, 1)
  while (c ~ /[A-Fa-f0-9]/) {
    id = id c
    i++
    c = substr(line, i, 1)
  }
  if (length(id) < 8) return ""
  return id
}
function grab(buf, key,    re, rest, val, i, c) {
  re = "(^|[^A-Za-z0-9_])" key "[ \\t]*=[ \\t]*"
  if (!match(buf, re)) return ""
  rest = substr(buf, RSTART + RLENGTH)
  if (substr(rest, 1, 1) == "\"") {
    val = ""
    for (i = 2; i <= length(rest); i++) {
      c = substr(rest, i, 1)
      if (c == "\"") break
      val = val c
    }
    return val
  }
  if (!match(rest, /^[^;]*/)) return ""
  val = substr(rest, RSTART, RLENGTH)
  gsub(/[ \t]*\/\*.*\*\//, "", val)
  gsub(/^[ \t]+|[ \t]+$/, "", val)
  gsub(/\r/, "", val)
  return val
}
function emit_ids(buf, key, kind, id,    re, rest, body, token) {
  re = "(^|[^A-Za-z0-9_])" key "[ \\t]*=[ \\t]*\\("
  if (!match(buf, re)) return
  rest = substr(buf, RSTART + RLENGTH)
  if (!match(rest, /^[^)]*/)) return
  body = substr(rest, RSTART, RLENGTH)
  while (match(body, /[A-Fa-f0-9]+/)) {
    token = substr(body, RSTART, RLENGTH)
    if (length(token) == 24) print kind "\t" id "\t" token
    body = substr(body, RSTART + RLENGTH)
  }
}
function dash(v) { return v == "" ? "-" : v }
function process(id, buf,    isa) {
  isa = grab(buf, "isa")
  if (isa == "PBXFileReference" || isa == "PBXGroup") {
    print "node\t" id "\t" isa "\t" grab(buf, "sourceTree") "\t" grab(buf, "path")
    if (isa == "PBXGroup") emit_ids(buf, "children", "child", id)
  } else if (isa == "PBXBuildFile") {
    print "buildfile\t" id "\t" dash(grab(buf, "fileRef")) "\t" dash(grab(buf, "productRef"))
  } else if (isa == "PBXResourcesBuildPhase" || isa == "PBXFrameworksBuildPhase") {
    print "phase\t" id "\t" isa
    emit_ids(buf, "files", "phasefile", id)
  } else if (isa == "PBXNativeTarget") {
    print "target\t" id "\t" grab(buf, "productType") "\t" grab(buf, "name") "\t" grab(buf, "buildConfigurationList")
    emit_ids(buf, "buildPhases", "targetphase", id)
  } else if (isa == "XCConfigurationList") {
    emit_ids(buf, "buildConfigurations", "configof", id)
  } else if (isa == "XCBuildConfiguration") {
    print "config\t" id "\t" dash(grab(buf, "name")) "\t" dash(grab(buf, "SDKROOT")) "\t" dash(grab(buf, "INFOPLIST_FILE")) "\t" dash(grab(buf, "SUPPORTED_PLATFORMS"))
  } else if (isa == "XCSwiftPackageProductDependency") {
    print "product\t" id "\t" grab(buf, "productName")
  }
}
BEGIN { depth = 0; buf = ""; id = "" }
{
  line = $0
  if (depth == 0) {
    tid = leading_id(line)
    if (tid != "" && line ~ /=/) {
      id = tid
      buf = line "\n"
      depth = nchar(line, "{") - nchar(line, "}")
      if (depth <= 0) {
        process(id, buf)
        depth = 0
        buf = ""
        id = ""
      }
      next
    }
  }
  if (depth > 0) {
    buf = buf line "\n"
    depth += nchar(line, "{") - nchar(line, "}")
    if (depth <= 0) {
      process(id, buf)
      depth = 0
      buf = ""
      id = ""
    }
  }
}
END_AWK
  awk -f "$prog" "$root/Floretta.xcodeproj/project.pbxproj"
  rm -f "$prog"
}

# Fills the caller's arrays by parsing the project. Prints nothing.
load_project() {
  local line kind a b c d e
  declare -gA ISA ST NODE_PATH PARENT FILE_REF PRODUCT_REF PHASE_ISA
  declare -gA PHASE_FILES TARGET_TYPE TARGET_NAME TARGET_LIST TARGET_PHASES
  declare -gA CONFIG_NAME CONFIG_SDK CONFIG_PLIST CONFIG_PLATFORMS CONFIGS_OF PRODUCT_NAME
  ISA=()
  ST=()
  NODE_PATH=()
  PARENT=()
  FILE_REF=()
  PRODUCT_REF=()
  PHASE_ISA=()
  PHASE_FILES=()
  TARGET_TYPE=()
  TARGET_NAME=()
  TARGET_LIST=()
  TARGET_PHASES=()
  CONFIG_NAME=()
  CONFIG_SDK=()
  CONFIG_PLIST=()
  CONFIG_PLATFORMS=()
  CONFIGS_OF=()
  PRODUCT_NAME=()
  while IFS=$'\t' read -r kind a b c d e; do
    case "$kind" in
      node)
        ISA["$a"]="$b"
        ST["$a"]="$c"
        NODE_PATH["$a"]="$d"
        ;;
      child)
        PARENT["$b"]="$a"
        ;;
      buildfile)
        [[ "$b" == "-" ]] && b=""
        [[ "$c" == "-" ]] && c=""
        FILE_REF["$a"]="$b"
        PRODUCT_REF["$a"]="$c"
        ;;
      phase)
        PHASE_ISA["$a"]="$b"
        ;;
      phasefile)
        PHASE_FILES["$a"]+="${b}"$'\n'
        ;;
      target)
        TARGET_TYPE["$a"]="$b"
        TARGET_NAME["$a"]="$c"
        TARGET_LIST["$a"]="$d"
        ;;
      targetphase)
        TARGET_PHASES["$a"]+="${b}"$'\n'
        ;;
      configof)
        CONFIGS_OF["$a"]+="${b}"$'\n'
        ;;
      config)
        [[ "$b" == "-" ]] && b=""
        [[ "$c" == "-" ]] && c=""
        [[ "$d" == "-" ]] && d=""
        [[ "$e" == "-" ]] && e=""
        CONFIG_NAME["$a"]="$b"
        CONFIG_SDK["$a"]="$c"
        CONFIG_PLIST["$a"]="$d"
        CONFIG_PLATFORMS["$a"]="$e"
        ;;
      product)
        PRODUCT_NAME["$a"]="$b"
        ;;
    esac
  done < <(parse_pbxproj)
}

declare -A PREFIX PREFIX_DONE

group_prefix() {
  local id="$1" st path parent base
  if [[ -z "$id" ]]; then
    echo ""
    return
  fi
  if [[ -n "${PREFIX_DONE[$id]:-}" ]]; then
    echo "${PREFIX[$id]}"
    return
  fi
  if [[ "${ISA[$id]:-}" != "PBXGroup" ]]; then
    PREFIX_DONE["$id"]=1
    PREFIX["$id"]=""
    echo ""
    return
  fi
  st="${ST[$id]:-}"
  path="${NODE_PATH[$id]:-}"
  parent="${PARENT[$id]:-}"
  if [[ "$st" == "SOURCE_ROOT" ]]; then
    PREFIX["$id"]="$path"
  elif [[ "$st" == "BUILT_PRODUCTS_DIR" ]]; then
    PREFIX["$id"]=""
  else
    base="$(group_prefix "$parent")"
    if [[ -z "$path" ]]; then
      PREFIX["$id"]="$base"
    elif [[ -z "$base" ]]; then
      PREFIX["$id"]="$path"
    else
      PREFIX["$id"]="$base/$path"
    fi
  fi
  PREFIX_DONE["$id"]=1
  echo "${PREFIX[$id]}"
}

# Echoes a repo-relative path, or empty when the ref is a built product.
resolve_file_ref() {
  local id="$1" st path parent prefix rel candidate
  st="${ST[$id]:-}"
  path="${NODE_PATH[$id]:-}"
  if [[ "$st" == "BUILT_PRODUCTS_DIR" || -z "$id" ]]; then
    echo ""
    return 0
  fi
  if [[ "$st" == "SOURCE_ROOT" || "$st" == "<absolute>" ]]; then
    rel="$path"
  else
    parent="${PARENT[$id]:-}"
    prefix="$(group_prefix "$parent")"
    if [[ -z "$prefix" ]]; then
      rel="$path"
    else
      rel="$prefix/$path"
    fi
  fi
  candidate="$root/$rel"
  if [[ ! -e "$candidate" ]]; then
    echo "resource referenced by the Xcode project is missing: $rel" >&2
    return 1
  fi
  echo "$rel"
}

platform_of_target() {
  local tid="$1" list cid name sdk platforms
  list="${TARGET_LIST[$tid]:-}"
  [[ -n "$list" ]] || { echo "target has no configuration list: ${TARGET_NAME[$tid]}" >&2; return 1; }
  while IFS= read -r cid; do
    [[ -z "$cid" ]] && continue
    name="${CONFIG_NAME[$cid]:-}"
    if [[ "$name" == "Release" ]]; then
      sdk="${CONFIG_SDK[$cid]:-}"
      platforms="${CONFIG_PLATFORMS[$cid]:-}"
      case "$sdk" in
        iphoneos|iphonesimulator) echo ios; return 0 ;;
        macosx) echo macos; return 0 ;;
      esac
      case "$platforms" in
        *iphoneos*) echo ios; return 0 ;;
        *macosx*) echo macos; return 0 ;;
      esac
      echo "Release SDKROOT is not iphoneos or macosx for ${TARGET_NAME[$tid]} (sdk=$sdk platforms=$platforms)" >&2
      return 1
    fi
  done <<< "${CONFIGS_OF[$list]:-}"
  echo "target has no Release configuration: ${TARGET_NAME[$tid]}" >&2
  return 1
}

release_plist_rel() {
  local tid="$1" list cid
  list="${TARGET_LIST[$tid]:-}"
  while IFS= read -r cid; do
    [[ -z "$cid" ]] && continue
    if [[ "${CONFIG_NAME[$cid]:-}" == "Release" ]]; then
      echo "${CONFIG_PLIST[$cid]:-}"
      return 0
    fi
  done <<< "${CONFIGS_OF[$list]:-}"
  echo ""
}

# Prints lines:
#   resource <ios|macos> <repo-relative-path>
#   link <ios|macos> <product> <count>
project_payload_lines() {
  local tid phase bid ref rel plist plat product seen_key
  declare -A LINK_COUNT=()
  PREFIX=()
  PREFIX_DONE=()
  for tid in "${!TARGET_TYPE[@]}"; do
    case "${TARGET_TYPE[$tid]}" in
      com.apple.product-type.application|com.apple.product-type.app-extension) ;;
      *) continue ;;
    esac
    plat="$(platform_of_target "$tid")"
    while IFS= read -r phase; do
      [[ -z "$phase" ]] && continue
      case "${PHASE_ISA[$phase]:-}" in
        PBXResourcesBuildPhase)
          while IFS= read -r bid; do
            [[ -z "$bid" ]] && continue
            ref="${FILE_REF[$bid]:-}"
            [[ -n "$ref" ]] || continue
            rel="$(resolve_file_ref "$ref")"
            [[ -n "$rel" ]] || continue
            echo "resource ${plat} ${rel}"
          done <<< "${PHASE_FILES[$phase]:-}"
          ;;
        PBXFrameworksBuildPhase)
          while IFS= read -r bid; do
            [[ -z "$bid" ]] && continue
            ref="${PRODUCT_REF[$bid]:-}"
            [[ -n "$ref" ]] || continue
            product="${PRODUCT_NAME[$ref]:-}"
            [[ -n "$product" ]] || { echo "framework product has no name: $ref" >&2; return 1; }
            seen_key="${tid}|${product}"
            if [[ -z "${LINK_COUNT[$seen_key]:-}" ]]; then
              LINK_COUNT["$seen_key"]=1
              echo "linkref ${plat} ${product}"
            fi
          done <<< "${PHASE_FILES[$phase]:-}"
          ;;
      esac
    done <<< "${TARGET_PHASES[$tid]:-}"
    plist="$(release_plist_rel "$tid")"
    if [[ -n "$plist" ]]; then
      if [[ ! -f "$root/$plist" ]]; then
        echo "INFOPLIST_FILE is missing: $plist" >&2
        return 1
      fi
      echo "resource ${plat} ${plist}"
    fi
  done
}

declare -A LINK_TOTAL

summarize_links() {
  local plat product
  LINK_TOTAL=()
  while IFS=' ' read -r kind plat product; do
    [[ "$kind" == "linkref" ]] || continue
    LINK_TOTAL["${plat}|${product}"]=$(( ${LINK_TOTAL["${plat}|${product}"]:-0} + 1 ))
  done
}

# --- release libraries -------------------------------------------------------

# Prints one absolute .swift.o path per line, from a single release build dir.
release_objects() {
  local name="$1" f dir dirs=""
  local -a found=()
  [[ -d "$root/.build" ]] || { echo "swift build did not create .build" >&2; return 1; }
  while IFS= read -r -d '' f; do
    case "$f" in
      *"/debug/"*) continue ;;
    esac
    found+=("$f")
    dir="${f%/${name}.build/*}"
    case "
${dirs}
" in
      *"
${dir}
"*) ;;
      *) dirs+="${dir}"$'\n' ;;
    esac
  done < <(find "$root/.build" -type f -path "*/release/${name}.build/*.swift.o" -print0)
  if [[ ${#found[@]} -eq 0 ]]; then
    echo "release ${name} .swift.o files were not produced" >&2
    return 1
  fi
  local count
  count="$(printf '%s\n' "$dirs" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$count" -ne 1 ]]; then
    echo "release ${name} objects came from more than one build directory:" >&2
    printf '%s\n' "$dirs" >&2
    return 1
  fi
  printf '%s\n' "${found[@]}" | LC_ALL=C sort
}

# Links object files plus an empty main, strips DWARF, prints the file size.
linked_stripped_bytes() {
  local out="$1"
  shift
  swiftc -parse-as-library -O -o "$out" "$SIZE_PROBE_SRC" "$@"
  strip --strip-unneeded "$out"
  file_bytes "$out"
}

proxy_measure() {
  local lines rel bytes plat core_path ui_path core_bytes ui_bytes
  local ios_resources=0 macos_resources=0 ios_total macos_total
  local core_copies ui_copies product copies lib_bytes
  echo "measurement=ci-proxy"
  echo "runner=ubuntu-24.04 has no Xcode; this is not a Release .app or .ipa"
  echo "excluded=Floretta SwiftUI Mach-O, SwiftFlow 0.3.1, code signature, libswift*.so, dSYM, DerivedData"
  reject_shipped_runtimes
  load_project
  lines="$(project_payload_lines)"
  summarize_links <<<"$lines"
  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    plat="${rel%% *}"
    rel="${rel#* }"
    bytes="$(bytes_of_path "$root/$rel")"
    echo "resource ${plat} ${rel} ${bytes}"
    if [[ "$plat" == "ios" ]]; then
      ios_resources=$((ios_resources + bytes))
    else
      macos_resources=$((macos_resources + bytes))
    fi
  done < <(echo "$lines" | awk '$1=="resource" { print $2 " " $3 }')

  if ! command -v swift >/dev/null 2>&1 || ! command -v swiftc >/dev/null 2>&1; then
    echo "swift and swiftc must be on PATH; the size gate cannot link the release objects" >&2
    return 1
  fi
  if ! command -v strip >/dev/null 2>&1; then
    echo "strip is not on PATH; DWARF would be counted as if it shipped in the app" >&2
    return 1
  fi
  swift build -c release
  local probe_dir probe_src empty_bin core_bin both_bin
  local -a core_objs=() ui_objs=()
  probe_dir="$(mktemp -d)"
  probe_src="$probe_dir/main.swift"
  SIZE_PROBE_SRC="$probe_src"
  cat >"$probe_src" <<'EOF'
@main
struct FlorettaSizeProbe {
    static func main() {}
}
EOF
  mapfile -t core_objs < <(release_objects FlorettaCore)
  mapfile -t ui_objs < <(release_objects FlorettaUI)
  empty_bin="$probe_dir/empty"
  core_bin="$probe_dir/core"
  both_bin="$probe_dir/both"
  local empty_bytes core_linked ui_linked
  empty_bytes="$(linked_stripped_bytes "$empty_bin")"
  core_linked="$(linked_stripped_bytes "$core_bin" "${core_objs[@]}")"
  ui_linked="$(linked_stripped_bytes "$both_bin" "${core_objs[@]}" "${ui_objs[@]}")"
  core_bytes=$((core_linked - empty_bytes))
  ui_bytes=$((ui_linked - core_linked))
  if (( core_bytes <= 0 || ui_bytes < 0 )); then
    echo "linked size delta is not usable: core=${core_bytes} ui=${ui_bytes}" >&2
    rm -rf "$probe_dir"
    return 1
  fi
  rm -rf "$probe_dir"
  echo "library FlorettaCore stripped_link_delta=${core_bytes} objects=${#core_objs[@]} empty=${empty_bytes}"
  echo "library FlorettaUI stripped_link_delta=${ui_bytes} objects=${#ui_objs[@]}"

  ios_total=$ios_resources
  macos_total=$macos_resources
  for product in FlorettaCore FlorettaUI; do
    if [[ "$product" == "FlorettaCore" ]]; then
      lib_bytes=$core_bytes
    else
      lib_bytes=$ui_bytes
    fi
    for plat in ios macos; do
      copies="${LINK_TOTAL["${plat}|${product}"]:-0}"
      echo "link ${plat} ${product} copies=${copies} each=${lib_bytes}"
      if [[ "$plat" == "ios" ]]; then
        ios_total=$((ios_total + copies * lib_bytes))
      else
        macos_total=$((macos_total + copies * lib_bytes))
      fi
    done
  done
  if [[ "${LINK_TOTAL[ios|FlorettaCore]:-0}" -lt 1 || "${LINK_TOTAL[macos|FlorettaCore]:-0}" -lt 1 ]]; then
    echo "FlorettaCore is not linked into an iOS or macOS app target" >&2
    return 1
  fi
  local app_swift=0 s f
  while IFS= read -r -d '' f; do
    s="$(file_bytes "$f")"
    app_swift=$((app_swift + s))
  done < <(find "$root/Floretta" -type f -name '*.swift' -print0)
  echo "app_swift_source_bytes=${app_swift} (not added to the budget; source is not the Mach-O)"
  echo "ios_resource_bytes=${ios_resources}"
  echo "macos_resource_bytes=${macos_resources}"
  local fail=0
  report_budget ios "$ios_total" "$IOS_BUDGET" || fail=1
  report_budget macos "$macos_total" "$MACOS_BUDGET" || fail=1
  return "$fail"
}

bundle_measure() {
  local ios_input="$1" macos_input="$2" ios_app macos_app ios_bytes macos_bytes
  echo "measurement=app-bundle"
  reject_shipped_runtimes
  ios_app="$(resolve_bundle "$ios_input")"
  macos_app="$(resolve_bundle "$macos_input")"
  reject_runtime_tree "$ios_app"
  reject_runtime_tree "$macos_app"
  ios_bytes="$(measure_app_dir "$ios_app")"
  macos_bytes="$(measure_app_dir "$macos_app")"
  echo "ios_bundle=$ios_app"
  echo "macos_bundle=$macos_app"
  local fail=0
  report_budget ios "$ios_bytes" "$IOS_BUDGET" || fail=1
  report_budget macos "$macos_bytes" "$MACOS_BUDGET" || fail=1
  return "$fail"
}

# --- self test ---------------------------------------------------------------

expect_fail() {
  local label="$1"
  shift
  set +e
  "$@" >/tmp/floretta-size-self-out 2>/tmp/floretta-size-self-err
  local rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "self-test expected failure: $label" >&2
    cat /tmp/floretta-size-self-out >&2 || true
    cat /tmp/floretta-size-self-err >&2 || true
    return 1
  fi
  echo "self-test fail-path ok: $label"
}

expect_ok() {
  local label="$1"
  shift
  if ! "$@" >/tmp/floretta-size-self-out 2>/tmp/floretta-size-self-err; then
    echo "self-test expected success: $label" >&2
    cat /tmp/floretta-size-self-out >&2 || true
    cat /tmp/floretta-size-self-err >&2 || true
    return 1
  fi
  echo "self-test pass-path ok: $label"
}

self_test() {
  local tmp small_ios small_mac exact_ios under_ios exact_mac under_mac
  local ipa_over ipa_support junk app
  tmp="$(mktemp -d)"
  small_ios="$tmp/small-ios/Floretta-iOS.app"
  small_mac="$tmp/small-mac/Floretta-macOS.app"
  mkdir -p "$small_ios" "$small_mac"
  echo ok >"$small_ios/Info.plist"
  echo ok >"$small_mac/Info.plist"
  expect_ok "small bundles" bash "$0" --ios "$small_ios" --macos "$small_mac"

  exact_ios="$tmp/exact-ios/Floretta-iOS.app"
  under_ios="$tmp/under-ios/Floretta-iOS.app"
  exact_mac="$tmp/exact-mac/Floretta-macOS.app"
  under_mac="$tmp/under-mac/Floretta-macOS.app"
  mkdir -p "$exact_ios" "$under_ios" "$exact_mac" "$under_mac"
  truncate -s "$IOS_BUDGET" "$exact_ios/payload"
  truncate -s $((IOS_BUDGET - 1)) "$under_ios/payload"
  truncate -s "$MACOS_BUDGET" "$exact_mac/payload"
  truncate -s $((MACOS_BUDGET - 1)) "$under_mac/payload"
  expect_fail "iOS at 15 MiB" bash "$0" --ios "$exact_ios" --macos "$small_mac"
  expect_ok "iOS one byte under 15 MiB" bash "$0" --ios "$under_ios" --macos "$small_mac"
  expect_fail "macOS at 25 MiB" bash "$0" --ios "$small_ios" --macos "$exact_mac"
  expect_ok "macOS one byte under 25 MiB" bash "$0" --ios "$small_ios" --macos "$under_mac"

  # A sibling dSYM is not the app.
  mkdir -p "$tmp/dsym/Floretta-iOS.app" "$tmp/dsym/Floretta-iOS.app.dSYM"
  echo ok >"$tmp/dsym/Floretta-iOS.app/Info.plist"
  truncate -s $((30 * 1024 * 1024)) "$tmp/dsym/Floretta-iOS.app.dSYM/huge"
  expect_ok "dSYM sibling ignored" bash "$0" --ios "$tmp/dsym/Floretta-iOS.app" --macos "$small_mac"

  mkdir -p "$tmp/junk/Intermediates.noindex/Floretta-iOS.app"
  echo ok >"$tmp/junk/Intermediates.noindex/Floretta-iOS.app/Info.plist"
  expect_fail "Intermediates.noindex refused" bash "$0" --ios "$tmp/junk/Intermediates.noindex/Floretta-iOS.app" --macos "$small_mac"

  # IPA: Payload app is the budget. SwiftSupport is not.
  mkdir -p "$tmp/ipa-over/Payload/Floretta-iOS.app" "$tmp/ipa-over/SwiftSupport"
  truncate -s "$IOS_BUDGET" "$tmp/ipa-over/Payload/Floretta-iOS.app/payload"
  truncate -s 1024 "$tmp/ipa-over/SwiftSupport/ignored"
  (cd "$tmp/ipa-over" && zip -qr "$tmp/over.ipa" Payload SwiftSupport)
  expect_fail "ipa Payload at 15 MiB" bash "$0" --ios "$tmp/over.ipa" --macos "$small_mac"

  mkdir -p "$tmp/ipa-ok/Payload/Floretta-iOS.app" "$tmp/ipa-ok/SwiftSupport"
  echo ok >"$tmp/ipa-ok/Payload/Floretta-iOS.app/Info.plist"
  truncate -s $((30 * 1024 * 1024)) "$tmp/ipa-ok/SwiftSupport/ignored"
  (cd "$tmp/ipa-ok" && zip -qr "$tmp/ok.ipa" Payload SwiftSupport)
  expect_ok "ipa ignores SwiftSupport" bash "$0" --ios "$tmp/ok.ipa" --macos "$small_mac"

  # Runtime ban. Checked in-process; a shipped Node/Python file must fail the gate.
  mkdir -p "$tmp/runtime/node_modules" "$tmp/runtime-clean"
  echo '{}' >"$tmp/runtime/package.json"
  echo 'print(1)' >"$tmp/runtime/tool.py"
  : >"$tmp/runtime/node"
  echo 'let x = 1' >"$tmp/runtime-clean/main.swift"
  if reject_runtime_tree "$tmp/runtime"; then
    echo "self-test expected runtime tree to fail" >&2
    return 1
  fi
  echo "self-test fail-path ok: runtime tree"
  reject_runtime_tree "$tmp/runtime-clean"
  echo "self-test pass-path ok: clean tree"
  reject_shipped_runtimes
  echo "self-test pass-path ok: shipped trees have no Node or Python runtime"

  load_project
  local got ios_res macos_res
  got="$(project_payload_lines | sort)"
  ios_res="$(echo "$got" | awk '$1=="resource" && $2=="ios" { print $3 }' | sort)"
  macos_res="$(echo "$got" | awk '$1=="resource" && $2=="macos" { print $3 }' | sort)"
  local expect_ios expect_mac
  expect_ios=$'Floretta/Share/Info-iOS.plist\nFloretta/Shared/Localizable.xcstrings\nFloretta/iOS/Assets.xcassets\nFloretta/iOS/Info.plist\nNOTICE'
  expect_mac=$'Floretta/QuickLook/Info-Preview.plist\nFloretta/QuickLook/Info-Thumbnail.plist\nFloretta/Share/Info-macOS.plist\nFloretta/Shared/Localizable.xcstrings\nFloretta/Shared/Localizable.xcstrings\nFloretta/Shared/Localizable.xcstrings\nFloretta/macOS/Assets.xcassets\nFloretta/macOS/Info.plist\nNOTICE'
  if [[ "$ios_res" != "$expect_ios" ]]; then
    echo "iOS resource list changed:" >&2
    echo "$ios_res" >&2
    return 1
  fi
  if [[ "$macos_res" != "$expect_mac" ]]; then
    echo "macOS resource list changed:" >&2
    echo "$macos_res" >&2
    return 1
  fi
  summarize_links <<<"$got"
  [[ "${LINK_TOTAL[ios|FlorettaCore]:-0}" -eq 2 ]] || { echo "ios FlorettaCore links ${LINK_TOTAL[ios|FlorettaCore]:-0}" >&2; return 1; }
  [[ "${LINK_TOTAL[ios|FlorettaUI]:-0}" -eq 1 ]] || { echo "ios FlorettaUI links" >&2; return 1; }
  [[ "${LINK_TOTAL[ios|SwiftFlow]:-0}" -eq 1 ]] || { echo "ios SwiftFlow links" >&2; return 1; }
  [[ "${LINK_TOTAL[macos|FlorettaCore]:-0}" -eq 4 ]] || { echo "macos FlorettaCore links ${LINK_TOTAL[macos|FlorettaCore]:-0}" >&2; return 1; }
  [[ "${LINK_TOTAL[macos|FlorettaUI]:-0}" -eq 1 ]] || { echo "macos FlorettaUI links" >&2; return 1; }
  [[ "${LINK_TOTAL[macos|SwiftFlow]:-0}" -eq 3 ]] || { echo "macos SwiftFlow links" >&2; return 1; }
  echo "self-test pass-path ok: Xcode resource list and link counts"
  echo "$got" | awk '$1=="resource" && $3 ~ /Tests/ { found=1 } END { exit found ? 1 : 0 }'
  echo "self-test pass-path ok: test files are not in the payload"
  rm -rf "$tmp"
  echo "self-test ok"
}

RESOLVE_TMP_DIRS=()
cleanup() {
  local d
  for d in "${RESOLVE_TMP_DIRS[@]+"${RESOLVE_TMP_DIRS[@]}"}"; do
    rm -rf "$d"
  done
}
trap cleanup EXIT

ios_arg=""
macos_arg=""
mode="proxy"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --self-test)
      mode="self-test"
      shift
      ;;
    --ios)
      ios_arg="${2:-}"
      [[ -n "$ios_arg" ]] || { echo "--ios needs a path" >&2; exit 1; }
      shift 2
      ;;
    --macos)
      macos_arg="${2:-}"
      [[ -n "$macos_arg" ]] || { echo "--macos needs a path" >&2; exit 1; }
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$mode" == "self-test" ]]; then
  self_test
  exit 0
fi

if [[ -n "$ios_arg" || -n "$macos_arg" ]]; then
  if [[ -z "$ios_arg" || -z "$macos_arg" ]]; then
    echo "pass both --ios and --macos" >&2
    exit 1
  fi
  bundle_measure "$ios_arg" "$macos_arg"
  exit 0
fi

proxy_measure
