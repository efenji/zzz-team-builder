#!/bin/bash
#
# Реорганизация ассетов ZZZ Team Builder: zzz/ -> assets/
#
# Запускать из корня локальной копии репозитория (там, где лежит папка zzz).
#
#   bash reorganize-assets.sh            # только показать, что будет сделано
#   bash reorganize-assets.sh --apply    # выполнить
#
# Ничего не удаляет: файлы только перемещаются. Если что-то в zzz/ скрипту
# незнакомо — он это не трогает и в конце перечисляет отдельным списком.
#

set -u

APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

SRC="zzz"
DST="assets"

if [ ! -d "$SRC" ]; then
  echo "Не нашёл папку '$SRC' здесь. Запусти скрипт из корня репозитория." >&2
  exit 1
fi

if [ -e "$DST" ]; then
  echo "Папка '$DST' уже существует. Убери или переименуй её и запусти заново." >&2
  exit 1
fi

# git mv, если это git-репозиторий (тогда GitHub Desktop покажет аккуратные
# переименования); иначе обычный mv.
USE_GIT=0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && USE_GIT=1

moved=0
skipped=0

# Имя файла -> slug: нижний регистр, & -> and, апострофы выбрасываются,
# всё остальное не буквенно-цифровое -> дефис, дубли дефисов сжимаются.
slugify() {
  printf '%s' "$1" \
    | sed "s/&/ and /g; s/['’]//g" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//'
}

do_move() {
  local from="$1" to="$2"
  if [ "$APPLY" = "1" ]; then
    mkdir -p "$(dirname "$to")"
    if [ "$USE_GIT" = "1" ]; then
      git mv -- "$from" "$to" 2>/dev/null || mv -- "$from" "$to"
    else
      mv -- "$from" "$to"
    fi
  fi
  printf '  %s\n     -> %s\n' "$from" "$to"
  moved=$((moved + 1))
}

# Плоская папка: zzz/<from>/<Имя>.webp -> assets/<to>/<slug>.webp
flat_folder() {
  local from_dir="$SRC/$1" to_dir="$DST/$2"
  [ -d "$from_dir" ] || return 0
  echo ""
  echo "[$1 -> $2]"
  local f base slug
  while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    slug="$(slugify "${base%.*}")"
    do_move "$f" "$to_dir/$slug.${base##*.}"
  done < <(find "$from_dir" -maxdepth 1 -type f -name '*.webp' -print0 | sort -z)
}

echo "================================================================"
if [ "$APPLY" = "1" ]; then
  echo "РЕЖИМ: выполнение (файлы будут перемещены)"
else
  echo "РЕЖИМ: проверка — ничего не меняется, только показываю план."
  echo "Чтобы выполнить: bash reorganize-assets.sh --apply"
fi
echo "================================================================"

# --- 1. Агенты: файл -> папка агента, внутри card.webp -------------------
if [ -d "$SRC/agents" ]; then
  echo ""
  echo "[agents -> agents/<агент>/card.webp]"
  while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    slug="$(slugify "${base%.*}")"
    do_move "$f" "$DST/agents/$slug/card.${base##*.}"
  done < <(find "$SRC/agents" -maxdepth 1 -type f -name '*.webp' -print0 | sort -z)
fi

# --- 2. W-Engine ---------------------------------------------------------
flat_folder "w-engines" "w-engines"

# --- 3. Бангбу -----------------------------------------------------------
flat_folder "bangboo" "bangboo"

# --- 4. Диски: _S -> -slot ----------------------------------------------
if [ -d "$SRC/drive-discs" ]; then
  echo ""
  echo "[drive-discs -> disc-sets]"
  while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    stem="${base%.*}"
    suffix=""
    case "$stem" in
      *_S) stem="${stem%_S}"; suffix="-slot" ;;
    esac
    slug="$(slugify "$stem")"
    do_move "$f" "$DST/disc-sets/$slug$suffix.${base##*.}"
  done < <(find "$SRC/drive-discs" -maxdepth 1 -type f -name '*.webp' -print0 | sort -z)
fi

# --- 5. Атрибуты: base/ + special/ сливаются в attributes/ --------------
if [ -d "$SRC/agent attribute" ]; then
  echo ""
  echo "[agent attribute/{base,special} -> attributes]"
  while IFS= read -r -d '' f; do
    base="$(basename "$f")"
    slug="$(slugify "${base%.*}")"
    target="$DST/attributes/$slug.${base##*.}"
    if [ -e "$target" ]; then
      echo "  ПРОПУСК (такой файл уже перенесён): $f"
      skipped=$((skipped + 1))
      continue
    fi
    do_move "$f" "$target"
  done < <(find "$SRC/agent attribute" -type f -name '*.webp' -print0 | sort -z)
fi

# --- 6. Специальности ----------------------------------------------------
flat_folder "specialties" "specialties"

# --- 7. Иконки статов ----------------------------------------------------
flat_folder "icons" "stats"

# --- 8. Зеркало Enka: переносим целиком, внутри ничего не переименовываем -
if [ -d "$SRC/enka-ui" ]; then
  echo ""
  echo "[enka-ui -> assets/enka-ui (как есть, без переименований)]"
  if [ "$APPLY" = "1" ]; then
    mkdir -p "$DST"
    if [ "$USE_GIT" = "1" ]; then
      git mv -- "$SRC/enka-ui" "$DST/enka-ui" 2>/dev/null || mv -- "$SRC/enka-ui" "$DST/enka-ui"
    else
      mv -- "$SRC/enka-ui" "$DST/enka-ui"
    fi
  fi
  n=$(find "$SRC/enka-ui" "$DST/enka-ui" -type f 2>/dev/null | wc -l | tr -d ' ')
  echo "  перенесено файлов: $n"
fi

# --- Остатки -------------------------------------------------------------
echo ""
echo "================================================================"
leftovers="$(find "$SRC" -type f 2>/dev/null | sort)"
if [ "$APPLY" = "1" ] && [ -n "$leftovers" ]; then
  echo "ОСТАЛОСЬ в $SRC/ (скрипт это не тронул, разберись вручную):"
  printf '%s\n' "$leftovers" | sed 's/^/  /'
elif [ "$APPLY" = "1" ]; then
  echo "Папка $SRC/ пуста — можно удалить её в Finder."
fi

echo "Файлов перемещено: $moved"
[ "$skipped" -gt 0 ] && echo "Пропущено (дубли имён): $skipped"
if [ "$APPLY" != "1" ]; then
  echo ""
  echo "Это была проверка. Если план выше выглядит правильно, запусти:"
  echo "  bash reorganize-assets.sh --apply"
fi
echo "================================================================"
