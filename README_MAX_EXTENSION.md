# Rocket Chip Maximum Extension Configurations

## 概述

本配置提供了带有最大扩展功能的Rocket Chip构建，包括完整的commit log日志功能。

## 配置详情

### RV64 配置 (`MaxExtensionRV64ConfigWithTrace`)

**特性:**
- ✅ 64位RISC-V ISA (RV64IMAFDC)
- ✅ B扩展 (Zba + Zbb + Zbs) - 位操作扩展
- ✅ FP16支持 - 半精度浮点
- ✅ H扩展 - Hypervisor虚拟化支持
- ✅ Commit Log - 完整的指令执行日志

**Commit Log包含:**
1. X寄存器写入: `<priv> 0x<pc> (0x<inst>) x<rd> 0x<data>`
2. F寄存器写入: `<priv> 0x<pc> (0x<inst>) f<rd> 0x<data>`
3. 内存写入: `<priv> 0x<pc> (STORE) addr=0x<addr> data=0x<data> size=<size>`
4. 同步异常: `<priv> 0x<pc> (0x<inst>) EXCEPTION cause=0x<cause> tval=0x<tval>`

### RV32 配置 (`MaxExtensionRV32ConfigWithTrace`)

**特性:**
- ✅ 32位RISC-V ISA (RV32IMAFDC)
- ✅ B扩展 (Zba + Zbb + Zbs)
- ✅ FP16支持 - 半精度浮点
- ✅ SV32虚拟内存
- ✅ Commit Log - 完整的指令执行日志

## 快速开始

### 1. 构建RV64配置（默认）

```bash
./build_max_extension.fish
```

这将生成Verilog并构建Verilator模拟器。

### 2. 仅生成Verilog

```bash
./build_max_extension.fish --rv64 --verilog
```

### 3. 构建RV32配置

```bash
./build_max_extension.fish --rv32
```

### 4. 构建两个配置

```bash
./build_max_extension.fish --both
```

### 5. 清理后重新构建

```bash
./build_max_extension.fish --clean --rv64
```

## 使用方法

### 编译测试程序

**RV64:**
```bash
riscv64-unknown-elf-gcc -march=rv64imafdch_zba_zbb_zbs \
  -mabi=lp64d -o test.riscv test.c
```

**RV32:**
```bash
riscv32-unknown-elf-gcc -march=rv32imafdch_zba_zbb_zbs \
  -mabi=ilp32d -o test.riscv test.c
```

### 运行模拟器

```bash
# 找到模拟器路径
EMULATOR=out/emulator/freechips.rocketchip.system.TestHarness/\
freechips.rocketchip.system.MaxExtensionRV64ConfigWithTrace/\
verilator/elf.dest/emulator

# 运行测试
$EMULATOR test.riscv > output.log 2>&1

# 或者直接查看输出
$EMULATOR test.riscv 2>&1 | less
```

## 日志解析

### 提取特定类型的日志

```bash
# X寄存器写入
grep ' x[0-9]* 0x' output.log

# F寄存器写入
grep ' f[0-9]* 0x' output.log

# 内存写入
grep 'STORE' output.log

# 异常
grep 'EXCEPTION' output.log

# 统计
echo "X writes: $(grep -c ' x[0-9]* 0x' output.log)"
echo "F writes: $(grep -c ' f[0-9]* 0x' output.log)"
echo "Stores:   $(grep -c 'STORE' output.log)"
echo "Exceptions: $(grep -c 'EXCEPTION' output.log)"
```

### Python解析示例

```python
#!/usr/bin/env python3
import re

def parse_commit_log(filename):
    x_writes = []
    f_writes = []
    stores = []
    exceptions = []
    
    with open(filename, 'r') as f:
        for line in f:
            # X寄存器
            m = re.match(r'(\d+) 0x([0-9a-f]+) \(0x([0-9a-f]+)\) x(\d+) 0x([0-9a-f]+)', line)
            if m:
                x_writes.append({
                    'priv': int(m.group(1)),
                    'pc': int(m.group(2), 16),
                    'inst': int(m.group(3), 16),
                    'rd': int(m.group(4)),
                    'data': int(m.group(5), 16)
                })
                continue
            
            # F寄存器
            m = re.match(r'(\d+) 0x([0-9a-f]+) \(0x([0-9a-f]+)\) f(\d+) 0x([0-9a-f]+)', line)
            if m:
                f_writes.append({
                    'priv': int(m.group(1)),
                    'pc': int(m.group(2), 16),
                    'inst': int(m.group(3), 16),
                    'rd': int(m.group(4)),
                    'data': int(m.group(5), 16)
                })
                continue
            
            # Store
            m = re.match(r'(\d+) 0x([0-9a-f]+) \(STORE\) addr=0x([0-9a-f]+) data=0x([0-9a-f]+) size=(\d+)', line)
            if m:
                stores.append({
                    'priv': int(m.group(1)),
                    'pc': int(m.group(2), 16),
                    'addr': int(m.group(3), 16),
                    'data': int(m.group(4), 16),
                    'size': int(m.group(5))
                })
                continue
            
            # Exception
            m = re.match(r'(\d+) 0x([0-9a-f]+) \(0x([0-9a-f]+)\) EXCEPTION cause=0x([0-9a-f]+) tval=0x([0-9a-f]+)', line)
            if m:
                exceptions.append({
                    'priv': int(m.group(1)),
                    'pc': int(m.group(2), 16),
                    'inst': int(m.group(3), 16),
                    'cause': int(m.group(4), 16),
                    'tval': int(m.group(5), 16)
                })
    
    return x_writes, f_writes, stores, exceptions

# 使用
x, f, s, e = parse_commit_log('output.log')
print(f"X writes: {len(x)}, F writes: {len(f)}, Stores: {len(s)}, Exceptions: {len(e)}")
```

## B扩展指令示例

```c
#include <stdint.h>

uint64_t test_b_extension(uint64_t a, uint64_t b) {
    // Zba - 地址生成
    uint64_t addr1 = a + (b << 2);  // sh2add
    uint64_t addr2 = a + (b << 3);  // sh3add
    
    // Zbb - 基本位操作
    uint64_t clz = __builtin_clzl(a);      // clz
    uint64_t ctz = __builtin_ctzl(a);      // ctz
    uint64_t popcnt = __builtin_popcountl(a); // cpop
    uint64_t max_val = (a > b) ? a : b;    // max
    uint64_t min_val = (a < b) ? a : b;    // min
    uint64_t rev8 = __builtin_bswap64(a);  // rev8
    
    // Zbs - 单bit操作
    uint64_t set_bit = a | (1ULL << 5);    // bset
    uint64_t clr_bit = a & ~(1ULL << 5);   // bclr
    uint64_t inv_bit = a ^ (1ULL << 5);    // binv
    uint64_t ext_bit = (a >> 5) & 1;       // bext
    
    return addr1 + clz + popcnt + set_bit;
}
```

## FP16示例

```c
#include <stdint.h>

// FP16需要_Float16类型支持
_Float16 test_fp16(_Float16 a, _Float16 b) {
    _Float16 add = a + b;      // fadd.h
    _Float16 mul = a * b;      // fmul.h
    _Float16 fma = a * b + 1.0f16;  // fmadd.h
    _Float16 div = a / b;      // fdiv.h
    _Float16 sqrt = __builtin_sqrtf16(a);  // fsqrt.h
    
    return add + mul + fma + div + sqrt;
}
```

## Hypervisor示例（仅RV64）

Hypervisor扩展需要特殊的引导代码和虚拟机监控器软件。请参考RISC-V Hypervisor规范。

## 构建输出

### Verilog文件位置
```
out/emulator/freechips.rocketchip.system.TestHarness/
  freechips.rocketchip.system.MaxExtensionRV64ConfigWithTrace/
    mfccompiler/compile.dest/
      *.v, *.sv
```

### 模拟器二进制位置
```
out/emulator/freechips.rocketchip.system.TestHarness/
  freechips.rocketchip.system.MaxExtensionRV64ConfigWithTrace/
    verilator/elf.dest/
      emulator
```

## 故障排除

### 1. Mill命令未找到
```bash
# 确保mill在PATH中
which mill

# 或使用项目自带的millw
./millw emulator[...].mfccompiler.compile
```

### 2. 编译时间过长
- Verilog生成: 约1-5分钟
- Verilator编译: 约10-30分钟（首次编译）
- 增量编译会快很多

### 3. 内存不足
Verilator编译需要大量内存（建议8GB以上）。可以考虑：
- 关闭其他应用
- 增加swap空间
- 使用`--verilog`仅生成Verilog

### 4. 日志量过大
Commit log会产生大量输出，建议：
- 使用重定向保存到文件
- 使用`head`或`tail`限制输出
- 使用grep过滤特定类型的日志

## 性能注意事项

- Commit log会显著降低仿真速度（约10-100倍）
- 仅在需要详细调试时启用
- 生产环境应使用无log版本（去掉`WithTrace`后缀）

## 相关文档

- [Rocket Chip文档](https://chipyard.readthedocs.io/)
- [RISC-V B扩展规范](https://github.com/riscv/riscv-bitmanip)
- [RISC-V Hypervisor规范](https://github.com/riscv/riscv-isa-manual)
- [RISC-V浮点规范](https://github.com/riscv/riscv-isa-manual)

## 版本信息

- Rocket Chip: master分支
- 配置日期: 2024
- 作者: Factory Droid
