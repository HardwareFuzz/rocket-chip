#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./build.sh [--isa <isa>] [--config <ConfigClass>] [--cores <1|2>] [--out-dir DIR] [--coverage|--coverage-light|--no-coverage] [--clean]
  ./build.sh --help

Build a runnable Verilator-based Rocket Chip emulator (out-of-tree mill build).

Options:
  --isa <isa>           ISA/build variant (default: rv64fd). May be specified multiple times.
                        Supported:
                          rv64fd (MaxExtensionRV64ConfigWithTrace: B+FP16+Zicond+H)
                          rv64f  (MaxExtensionRV64FConfigWithTrace: B+FP16+Zicond+F+H)
                          rv32fd (MaxExtensionRV32ConfigWithTrace: B+FP16+Zicond+FD)
                          rv32f  (MaxExtensionRV32NoDConfigWithTrace: B+FP16+Zicond+F)
  --config <ConfigClass> Override the config class (applies to all --isa values).
                         Examples: DefaultConfigWithTrace, TraceRV64Config, TraceRV32Config, DefaultSmallConfig
  --cores <1|2>         Core count tag used for output naming (default: 1)
  --out-dir DIR         Output directory for the final binary (default: ./build_result)
                        You can also set CX_OUT_DIR (shared across repos) or OUT_DIR.
  --coverage            Verilator full coverage (output suffix: _cov)
  --coverage-light      Line/user coverage only (output suffix: _cov_light)
  --no-coverage         Disable coverage (default)
  --clean               Remove prior build outputs for this target
  --help, -h            Show this help

Output artifact:
  <out-dir>/rocket-chip_<isa>_<N>c[_cov|_cov_light]

Dependencies:
  - mill (or ./.millw), firtool, verilator, cmake, ninja, clang/clang++
  - RISCV (or SPIKE_ROOT) env var for fesvr include/lib
EOF
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MILL_CMD="${MILL_CMD:-mill}"

ISAS=()
CORES="1"
CLEAN=0
COV_MODE="none" # none|full|light
CONFIG_CLASS=""
OUT_DIR_OPT=""

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
    --isa) ISAS+=("$2"); shift 2 ;;
    --config) CONFIG_CLASS="$2"; shift 2 ;;
    --cores) CORES="$2"; shift 2 ;;
    --out-dir)
      [[ $# -ge 2 ]] || die "--out-dir requires a value"
      OUT_DIR_OPT="$2"; shift 2 ;;
    --out-dir=*) OUT_DIR_OPT="${1#*=}"; shift ;;
    --coverage) COV_MODE="full"; shift ;;
    --coverage-light) COV_MODE="light"; shift ;;
    --no-coverage) COV_MODE="none"; shift ;;
    --clean) CLEAN=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

if [[ ${#ISAS[@]} -eq 0 ]]; then
  ISAS=("rv64fd")
fi

[[ "${CORES}" =~ ^[0-9]+$ ]] || die "--cores must be an integer"

if [[ "${CORES}" != "1" && "${CORES}" != "2" ]]; then
  die "--cores ${CORES} is unsupported (supported: 1 or 2)"
fi

validate_isa() {
  case "$1" in
    rv64fd|rv64f|rv32fd|rv32f) ;;
    *) die "unsupported --isa on this branch: $1 (supported: rv64fd, rv64f, rv32fd, rv32f)" ;;
  esac
}

for isa in "${ISAS[@]}"; do
  validate_isa "${isa}"
done

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

top="freechips.rocketchip.system.TestHarness"
config_pkg="freechips.rocketchip.system"

OUT_DIR_DEFAULT="${ROOT_DIR}/build_result"
OUT_DIR="${OUT_DIR_OPT:-${CX_OUT_DIR:-${OUT_DIR:-${OUT_DIR_DEFAULT}}}}"

mkdir -p "${OUT_DIR}"

# Ensure cmake find_package(verilator) picks up the system Verilator 5.x headers
# rather than any older VERILATOR_ROOT left in the environment.
if [[ -z "${VERILATOR_ROOT:-}" ]]; then
  _detected_root="$(verilator --getenv VERILATOR_ROOT 2>/dev/null || true)"
  if [[ -n "${_detected_root}" && -d "${_detected_root}" ]]; then
    export VERILATOR_ROOT="${_detected_root}"
  fi
fi

ensure_mill

# Coverage builds require a fresh mill process so VERILATOR_* env vars are visible.
mill_args=()
if [[ "${COV_MODE}" != "none" ]]; then
  mill_args+=("--no-server")
fi

build_one() {
  local isa_in="$1"
  local isa_tag="$1"
  local default_cfg_class=""

  if [[ "${CORES}" == "1" ]]; then
    case "${isa_in}" in
      rv64fd) default_cfg_class="MaxExtensionRV64ConfigWithTrace" ;;
      rv64f)  default_cfg_class="MaxExtensionRV64FConfigWithTrace" ;;
      rv32fd) default_cfg_class="MaxExtensionRV32ConfigWithTrace" ;;
      rv32f)  default_cfg_class="MaxExtensionRV32NoDConfigWithTrace" ;;
      *) die "internal: unexpected isa after validation: ${isa_in}" ;;
    esac
  else
    case "${isa_in}" in
      rv64fd) default_cfg_class="MaxExtensionRV64ConfigWithTrace2C" ;;
      rv64f)  default_cfg_class="MaxExtensionRV64FConfigWithTrace2C" ;;
      rv32fd) default_cfg_class="MaxExtensionRV32ConfigWithTrace2C" ;;
      rv32f)  default_cfg_class="MaxExtensionRV32NoDConfigWithTrace2C" ;;
      *) die "internal: unexpected isa after validation: ${isa_in}" ;;
    esac
  fi

  local cfg_class="${CONFIG_CLASS:-${default_cfg_class}}"
  local cfg="${config_pkg}.${cfg_class}"
  artifact_name="rocket-chip_${isa_tag}_${CORES}c${suffix}"
  artifact_path="${OUT_DIR}/${artifact_name}"

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
}

for isa in "${ISAS[@]}"; do
  build_one "${isa}"
done
