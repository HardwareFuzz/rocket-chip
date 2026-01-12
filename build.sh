#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./build.sh [--out DIR] [--top TOP] [--config CONFIG] [--help]

Generate a dual-core Rocket Chip SoC (Chisel elaboration).
Defaults:
  TOP    = freechips.rocketchip.system.ExampleRocketSystem
  CONFIG = freechips.rocketchip.system.DualCoreConfig
  OUT    = build_result/rocket_2c

Note: This runs Chisel elaboration and writes FIRRTL/annotations into OUT.
EOF
}

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/build_result/rocket_2c}"
TOP="${TOP:-freechips.rocketchip.system.ExampleRocketSystem}"
CONFIG="${CONFIG:-freechips.rocketchip.system.DualCoreConfig}"
CHISEL_CROSS="${CHISEL_CROSS:-6.7.0}"
MILL_CMD="mill"

command_exists() { command -v "$1" >/dev/null 2>&1; }

if ! command_exists mill; then
  MILL_CMD="${ROOT_DIR}/.millw"
  if [[ ! -x "${MILL_CMD}" ]]; then
    echo "[info] mill not found; downloading mill wrapper..."
    curl -fsSL https://github.com/com-lihaoyi/mill/releases/download/0.10.9/0.10.9 > "${MILL_CMD}"
    chmod +x "${MILL_CMD}"
  fi
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT_DIR="$2"; shift 2 ;;
    --top) TOP="$2"; shift 2 ;;
    --config) CONFIG="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

mkdir -p "$OUT_DIR"

pushd "$ROOT_DIR" >/dev/null
# Build the Rocket Chip assembly jar via mill and then invoke it directly.
"${MILL_CMD}" -i "rocketchip[${CHISEL_CROSS}].assembly"
JAR_PATH="${ROOT_DIR}/out/rocketchip/${CHISEL_CROSS}/assembly.dest/out.jar"
if [[ ! -f "${JAR_PATH}" ]]; then
  echo "Error: assembly jar not found at ${JAR_PATH}" >&2
  exit 1
fi

CONFIG_ARGS=()
IFS='_' read -r -a CONFIG_PARTS <<< "${CONFIG}"
for cfg in "${CONFIG_PARTS[@]}"; do
  CONFIG_ARGS+=(--config "${cfg}")
done

java -jar "${JAR_PATH}" --dir "${OUT_DIR}" --top "${TOP}" "${CONFIG_ARGS[@]}"
popd >/dev/null

echo "Elaboration complete: $OUT_DIR (top=$TOP, config=$CONFIG)"
