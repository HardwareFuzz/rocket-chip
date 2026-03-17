#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./build.sh [--isa rv64fd] [--cores 1] [--coverage|--coverage-light|--no-coverage] [--clean]
  ./build.sh --help

Build a runnable Verilator-based Rocket Chip emulator (out-of-tree mill build).

Options:
  --isa rv64fd          ISA tag used for output naming (default: rv64fd)
  --cores 1             Core count tag used for output naming (default: 1)
  --coverage            Verilator full coverage (output suffix: _cov)
  --coverage-light      Line/user coverage only (output suffix: _cov_light)
  --no-coverage         Disable coverage (default)
  --clean               Remove prior build outputs for this target
  --help, -h            Show this help

Output artifact:
  build_result/rocket-chip_<isa>_<N>c[_cov|_cov_light]

Dependencies:
  - mill (or ./.millw), firtool, verilator, cmake, ninja, clang/clang++
  - RISCV (or SPIKE_ROOT) env var for fesvr include/lib
EOF
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/build_result}"
MILL_CMD="${MILL_CMD:-mill}"

ISA="rv64fd"
CORES="1"
CLEAN=0
COV_MODE="none" # none|full|light

die() { echo "ERROR: $*" >&2; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

ensure_mill() {
  if command_exists "${MILL_CMD}"; then
    return 0
  fi
  if [[ -x "${ROOT_DIR}/.millw" ]]; then
    MILL_CMD="${ROOT_DIR}/.millw"
    return 0
  fi
  die "mill not found (and ./.millw is missing)"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --isa) ISA="$2"; shift 2 ;;
    --cores) CORES="$2"; shift 2 ;;
    --coverage) COV_MODE="full"; shift ;;
    --coverage-light) COV_MODE="light"; shift ;;
    --no-coverage) COV_MODE="none"; shift ;;
    --clean) CLEAN=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[[ "${CORES}" =~ ^[0-9]+$ ]] || die "--cores must be an integer"

if [[ "${CORES}" != "1" ]]; then
  die "--cores ${CORES} is not supported on this branch (use branch '2hart')"
fi

case "${ISA}" in
  rv64fd) ;;
  rv64) ISA="rv64fd" ;; # alias
  *) die "unsupported --isa on this branch: ${ISA} (use rv64fd)" ;;
esac

config_class="DefaultConfigWithTrace"

suffix=""
extra_env=()
case "${COV_MODE}" in
  none)
    suffix=""
    ;;
  full)
    suffix="_cov"
    extra_env+=("VERILATOR_COVERAGE=1")
    ;;
  light)
    suffix="_cov_light"
    extra_env+=("VERILATOR_COVERAGE=1")
    extra_env+=("VERILATOR_EXTRA_ARGS=--coverage-line --coverage-user --coverage-max-width 0")
    ;;
  *) die "internal: unknown coverage mode: ${COV_MODE}" ;;
esac

artifact_name="rocket-chip_${ISA}_${CORES}c${suffix}"
artifact_path="${OUT_DIR}/${artifact_name}"

top="freechips.rocketchip.system.TestHarness"
cfg="freechips.rocketchip.system.${config_class}"

mkdir -p "${OUT_DIR}"

ensure_mill

# Coverage builds require a fresh mill process so VERILATOR_* env vars are visible.
mill_args=()
if [[ "${COV_MODE}" != "none" ]]; then
  mill_args+=("--no-server")
fi

if (( CLEAN )); then
  rm -rf "${ROOT_DIR}/out/emulator/${top}/${cfg}/verilator" || true
  rm -f "${artifact_path}" || true
fi

echo "[build] ${artifact_name} (config=${cfg})"
(
  cd "${ROOT_DIR}"
  env "${extra_env[@]}" "${MILL_CMD}" "${mill_args[@]}" -i "emulator[${top},${cfg}].verilator.elf"
)

emu_bin="${ROOT_DIR}/out/emulator/${top}/${cfg}/verilator/elf.dest/emulator"
[[ -x "${emu_bin}" ]] || die "emulator binary not found at ${emu_bin}"

cp -f "${emu_bin}" "${artifact_path}"
chmod +x "${artifact_path}"
echo "  -> ${artifact_path}"
