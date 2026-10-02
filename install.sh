#!/usr/bin/env bash
#
# install.sh — install a selection of skills from this repo into Claude Code
# and OpenCode skill directories.
#
# Run without skill IDs for an interactive picker (fzf when available).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$SCRIPT_DIR/skills"

# --- defaults ---------------------------------------------------------------
DO_CLAUDE=1
DO_OPENCODE=1
SCOPE="project"          # project | global
PROJECT_DIR="$PWD"
LINK=0                   # 1 = symlinks, 0 = copies (default)
FORCE=0
ALL=0
MODE="install"           # install | remove
IDS=()

die() {
  printf 'install.sh: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf '  ! %s\n' "$*" >&2
}

usage() {
  cat <<'EOF'
Usage: ./install.sh [skill-id ...] [options]

Install a selection of skills from this repo into Claude Code and OpenCode.
Run without skill IDs for an interactive picker (fzf when available).

Arguments:
  skill-id ...        Skills to install (skill ID = directory name in skills/)

Options:
  --all               Install every skill in the repo
  --remove [id ...]   Uninstall instead of install (picker if no IDs given)
  --claude            Target only Claude Code
  --opencode          Target only OpenCode
  --global            Install into ~/.claude/skills + ~/.config/opencode/skills
  --project <dir>     Project-local target dir (default: current working dir)
  --link              Install as symlinks instead of copies
  --force             Replace conflicting or diverged existing entries
  -h, --help          Show this help

Examples:
  ./install.sh                          # pick interactively, project-local
  ./install.sh worker --global          # copy 'worker' into both global dirs
  ./install.sh --all --opencode --link  # symlink everything for OpenCode
  ./install.sh --remove worker          # uninstall 'worker'
EOF
}

# --- argument parsing ---------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --all) ALL=1 ;;
    --remove) MODE="remove" ;;
    --claude) DO_CLAUDE=1; DO_OPENCODE=0 ;;
    --opencode) DO_OPENCODE=1; DO_CLAUDE=0 ;;
    --global) SCOPE="global" ;;
    --project)
      if [ $# -lt 2 ]; then
        die "--project requires a directory"
      fi
      PROJECT_DIR="$2"
      shift
      ;;
    --project=*) PROJECT_DIR="${1#*=}" ;;
    --link) LINK=1 ;;
    --copy) LINK=0 ;;
    --force) FORCE=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [ $# -gt 0 ]; do
        IDS+=("$1")
        shift
      done
      break
      ;;
    -*) die "unknown option: $1 (see --help)" ;;
    *) IDS+=("$1") ;;
  esac
  shift
done

if [ ! -d "$PROJECT_DIR" ]; then
  die "project directory not found: $PROJECT_DIR"
fi
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# --- skill discovery ------------------------------------------------------------

# Print the IDs of all skills (directories containing a SKILL.md), sorted.
discover_skills() {
  local d
  for d in "$SKILLS_ROOT"/*/; do
    if [ ! -d "$d" ]; then
      continue
    fi
    if [ ! -f "$d/SKILL.md" ]; then
      continue
    fi
    basename "$d"
  done | sort
}

# Print the frontmatter description of a skill, best effort.
skill_description() {
  local id="$1"
  awk '
    BEGIN { q = sprintf("%c", 39) }
    NR == 1 && $0 ~ /^---[ \t]*$/ { infm = 1; next }
    infm && $0 ~ /^(---|\.\.\.)[ \t]*$/ { exit }
    infm {
      if (!key && $0 ~ /^description[ \t]*:/) {
        val = $0
        sub(/^description[ \t]*:[ \t]*/, "", val)
        if (val ~ /^[>|]/) { key = 1; next }
        if (val ~ /^".*"$/) { sub(/^"/, "", val); sub(/"$/, "", val) }
        if (val ~ "^" q ".*" q "$") { sub("^" q, "", val); sub(q "$", "", val) }
        gsub(/[ \t]+/, " ", val)
        print val
        exit
      } else if (key) {
        if ($0 ~ /^[ \t]+[^ \t]/) {
          line = $0
          sub(/^[ \t]+/, "", line)
          gsub(/[ \t]+/, " ", line)
          if (started) printf " "
          printf "%s", line
          started = 1
        } else if ($0 ~ /^[^ \t]/) {
          exit
        }
      }
    }
    END { if (started) printf "\n" }
  ' "$SKILLS_ROOT/$id/SKILL.md"
}

in_list() {
  local needle="$1"
  shift
  local x
  for x in "$@"; do
    if [ "$x" = "$needle" ]; then
      return 0
    fi
  done
  return 1
}

# --- selection --------------------------------------------------------------------

SELECTED=()

pick_interactive() {
  local ids=("$@")
  local picks=()
  local i id line tok out

  if command -v fzf >/dev/null 2>&1 && [ -t 0 ]; then
    out="$(printf '%s\n' "${ids[@]}" | fzf --multi --prompt 'skills: ' || true)"
    if [ -n "$out" ]; then
      while IFS= read -r line; do
        if [ -n "$line" ]; then
          picks+=("$line")
        fi
      done < <(printf '%s\n' "$out")
    fi
  else
    printf 'Available skills:\n'
    i=1
    for id in "${ids[@]}"; do
      printf '  %2d. %s\n' "$i" "$id"
      i=$((i + 1))
    done
    printf 'Select (numbers, comma or space separated, or "all"): '
    if ! read -r line; then
      die "no selection received"
    fi
    line="${line//,/ }"
    for tok in $line; do
      case "$tok" in
        all)
          picks=("${ids[@]}")
          ;;
        [0-9]*)
          if [ "$tok" -ge 1 ] && [ "$tok" -le "${#ids[@]}" ]; then
            picks+=("${ids[$((tok - 1))]}")
          else
            die "invalid selection: $tok (valid range: 1-${#ids[@]})"
          fi
          ;;
        *)
          die "invalid selection: $tok"
          ;;
      esac
    done
  fi

  if [ "${#picks[@]}" -eq 0 ]; then
    printf 'No skills selected; nothing to do.\n'
    exit 0
  fi
  SELECTED=("${picks[@]}")
}

resolve_selection() {
  local all_ids=()
  local id k bad

  while IFS= read -r id; do
    if [ -n "$id" ]; then
      all_ids+=("$id")
    fi
  done < <(discover_skills)

  if [ "${#all_ids[@]}" -eq 0 ]; then
    die "no skills found in $SKILLS_ROOT (expected skills/<id>/SKILL.md)"
  fi

  if [ "$ALL" -eq 1 ]; then
    SELECTED=("${all_ids[@]}")
    return 0
  fi

  if [ "$#" -gt 0 ]; then
    bad=0
    for id in "$@"; do
      if ! in_list "$id" "${all_ids[@]}"; then
        printf 'unknown skill: %s\n' "$id" >&2
        bad=1
      fi
    done
    if [ "$bad" -eq 1 ]; then
      printf 'Available skills:\n' >&2
      for k in "${all_ids[@]}"; do
        printf '  %s\n' "$k" >&2
      done
      exit 1
    fi
    SELECTED=("$@")
    return 0
  fi

  pick_interactive "${all_ids[@]}"
}

# --- actions ------------------------------------------------------------------------

TOOLS=()
if [ "$DO_CLAUDE" -eq 1 ]; then
  TOOLS+=("claude")
fi
if [ "$DO_OPENCODE" -eq 1 ]; then
  TOOLS+=("opencode")
fi
if [ "${#TOOLS[@]}" -eq 0 ]; then
  die "no tools selected (use --claude and/or --opencode)"
fi

target_dir_for() {
  local tool="$1"
  if [ "$SCOPE" = "global" ]; then
    if [ "$tool" = "claude" ]; then
      printf '%s\n' "$HOME/.claude/skills"
    else
      printf '%s\n' "$HOME/.config/opencode/skills"
    fi
  else
    if [ "$tool" = "claude" ]; then
      printf '%s\n' "$PROJECT_DIR/.claude/skills"
    else
      printf '%s\n' "$PROJECT_DIR/.opencode/skills"
    fi
  fi
}

dir_identical() {
  diff -qr "$1" "$2" >/dev/null 2>&1
}

INSTALLED=0
SKIPPED=0
REMOVED=0

install_skill_to() {
  local id="$1" target="$2"
  local src="$SKILLS_ROOT/$id"
  local dest="$target/$id"
  local desc

  desc="$(skill_description "$id")"
  if [ -z "$desc" ]; then
    warn "skip $id: no non-empty description in SKILL.md (OpenCode will not advertise it)"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  mkdir -p "$target"

  if [ "$LINK" -eq 1 ]; then
    if [ -L "$dest" ]; then
      if [ "$(readlink "$dest")" = "$src" ]; then
        printf '  = %s already linked\n' "$id"
        SKIPPED=$((SKIPPED + 1))
        return 0
      fi
      if [ "$FORCE" -eq 1 ]; then
        rm "$dest"
      else
        warn "skip $id: $dest is a symlink to $(readlink "$dest") (use --force to replace)"
        SKIPPED=$((SKIPPED + 1))
        return 0
      fi
    elif [ -e "$dest" ]; then
      if [ "$FORCE" -eq 1 ]; then
        rm -rf "$dest"
      else
        warn "skip $id: $dest already exists (use --force to replace with a symlink)"
        SKIPPED=$((SKIPPED + 1))
        return 0
      fi
    fi
    ln -s "$src" "$dest"
    printf '  + %s linked\n' "$id"
    INSTALLED=$((INSTALLED + 1))
    return 0
  fi

  # copy mode
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ -L "$dest" ] || ! dir_identical "$src" "$dest"; then
      if [ "$FORCE" -eq 1 ]; then
        rm -rf "$dest"
      else
        warn "skip $id: $dest already exists and differs from the repo (use --force to update)"
        SKIPPED=$((SKIPPED + 1))
        return 0
      fi
    else
      printf '  = %s up to date\n' "$id"
      SKIPPED=$((SKIPPED + 1))
      return 0
    fi
  fi
  cp -R "$src" "$dest"
  printf '  + %s copied\n' "$id"
  INSTALLED=$((INSTALLED + 1))
}

remove_skill_from() {
  local id="$1" target="$2"
  local src="$SKILLS_ROOT/$id"
  local dest="$target/$id"
  local linkto

  if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
    printf '  - %s not present\n' "$id"
    return 0
  fi

  if [ -L "$dest" ]; then
    linkto="$(readlink "$dest")"
    case "$linkto" in
      /*) : ;;
      *) linkto="$(cd "$(dirname "$dest")" && pwd)/$linkto" ;;
    esac
    case "$linkto" in
      "$SKILLS_ROOT"/*)
        rm "$dest"
        printf '  - %s unlinked\n' "$id"
        REMOVED=$((REMOVED + 1))
        return 0
        ;;
      *)
        if [ "$FORCE" -eq 1 ]; then
          rm "$dest"
          printf '  - %s unlinked (forced)\n' "$id"
          REMOVED=$((REMOVED + 1))
        else
          warn "skip $id: $dest links to $linkto, not in this repo (use --force to remove anyway)"
          SKIPPED=$((SKIPPED + 1))
        fi
        return 0
        ;;
    esac
  fi

  if dir_identical "$src" "$dest"; then
    rm -rf "$dest"
    printf '  - %s removed\n' "$id"
    REMOVED=$((REMOVED + 1))
    return 0
  fi

  if [ "$FORCE" -eq 1 ]; then
    rm -rf "$dest"
    printf '  - %s removed (forced)\n' "$id"
    REMOVED=$((REMOVED + 1))
  else
    warn "skip $id: $dest differs from the repo copy (use --force to remove anyway)"
    SKIPPED=$((SKIPPED + 1))
  fi
}

# --- main -------------------------------------------------------------------------------

main() {
  if [ ! -d "$SKILLS_ROOT" ]; then
    die "skills directory not found: $SKILLS_ROOT"
  fi

  resolve_selection ${IDS[@]+"${IDS[@]}"}

  local label
  if [ "$MODE" = "install" ]; then
    label="Installing"
  else
    label="Removing"
  fi

  local tool target id
  for tool in "${TOOLS[@]}"; do
    target="$(target_dir_for "$tool")"
    printf '%s %s (%s)\n' "$label" "$target" "$tool"
    for id in "${SELECTED[@]}"; do
      if [ "$MODE" = "install" ]; then
        install_skill_to "$id" "$target"
      else
        remove_skill_from "$id" "$target"
      fi
    done
    printf '\n'
  done

  if [ "$MODE" = "install" ]; then
    printf 'Done: %s installed, %s skipped.\n' "$INSTALLED" "$SKIPPED"
  else
    printf 'Done: %s removed, %s skipped.\n' "$REMOVED" "$SKIPPED"
  fi
  printf 'Note: skills are loaded at startup - restart OpenCode / Claude Code to pick up changes.\n'
}

main
