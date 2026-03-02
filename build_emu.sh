#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./build_emu.sh [--config <ConfigClass>] [--memorder-2c] [--clean] [--help]

Build a runnable Verilator-based Rocket Chip emulator binary via mill.

This complements build.sh (which only does Chisel elaboration).

Defaults:
  --memorder-2c: build the 2-core memorder metamorphic variants.

Output:
  build_result/<name>

Notes:
  - Requires: mill, firtool, verilator, cmake, ninja, clang/clang++
  - Requires RISCV (or SPIKE_ROOT) env var to locate fesvr include/lib.
EOF
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/build_result}"
MILL_CMD="${MILL_CMD:-mill}"

CLEAN=0
BUILD_MEMORDER_2C=0
CONFIG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG="$2"; shift 2 ;;
    --memorder-2c)
      BUILD_MEMORDER_2C=1; shift ;;
    --clean)
      CLEAN=1; shift ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${CONFIG}" && ${BUILD_MEMORDER_2C} -eq 0 ]]; then
  BUILD_MEMORDER_2C=1
fi

configs=()
names=()

add_cfg() {
  configs+=("$1")
  names+=("$2")
}

if [[ -n "${CONFIG}" ]]; then
  # Use the config class name as output suffix.
  add_cfg "${CONFIG}" "emulator_${CONFIG}"
fi

if [[ ${BUILD_MEMORDER_2C} -eq 1 ]]; then
  add_cfg "freechips.rocketchip.system.MemOrderCoherent2CNoTLMonitorsConfig" "rocket_2c_memorder_coherent_emu"
  add_cfg "freechips.rocketchip.system.MemOrderCoherent2CBlockingSDQ4NoTLMonitorsConfig" "rocket_2c_memorder_blocking_sdq4_emu"
  add_cfg "freechips.rocketchip.system.MemOrderCoherent2CNonblockingSDQ8NoTLMonitorsConfig" "rocket_2c_memorder_nonblocking_sdq8_emu"
  add_cfg "freechips.rocketchip.system.MemOrderCoherent2CNonblockingSDQ16NoTLMonitorsConfig" "rocket_2c_memorder_nonblocking_sdq16_emu"
fi

mkdir -p "${OUT_DIR}"

for i in "${!configs[@]}"; do
  cfg="${configs[$i]}"
  out_name="${names[$i]}"

  # mill cross module path uses the full class name in the out/ directory.
  top="freechips.rocketchip.system.TestHarness"
  rel_cfg="$cfg"
  # Ensure cfg is a fully-qualified name for the mill invocation.
  if [[ "$cfg" != *.* ]]; then
    rel_cfg="freechips.rocketchip.system.${cfg}"
  fi

  echo "[build] ${out_name} (config=${rel_cfg})"

  if (( CLEAN )); then
    rm -rf "${ROOT_DIR}/out/emulator/${top}/${rel_cfg}/verilator" || true
    rm -f "${OUT_DIR}/${out_name}" || true
  fi

  "${MILL_CMD}" -i "emulator[${top},${rel_cfg}].verilator.elf"

  emu_bin="${ROOT_DIR}/out/emulator/${top}/${rel_cfg}/verilator/elf.dest/emulator"
  if [[ ! -x "${emu_bin}" ]]; then
    echo "ERROR: emulator binary not found at ${emu_bin}" >&2
    exit 1
  fi

  cp -f "${emu_bin}" "${OUT_DIR}/${out_name}"
  chmod +x "${OUT_DIR}/${out_name}"
  echo "  -> ${OUT_DIR}/${out_name}"
done

cat <<'EOF'

Run tips:
  - Print global cycle count: add `-c` or `+cycle-count`
  - Limit runtime: add `-m N` or `+max-cycles=N`

Example:
  build_result/rocket_2c_memorder_coherent_emu +cycle-count $RISCV/riscv64-unknown-elf/share/riscv-tests/isa/rv64ui-p-add
EOF
