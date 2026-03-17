# Rocket Chip 完整日志功能构建指南

## 📋 功能说明

本次修改为 Rocket Chip 添加了完整的日志追踪功能，包括：

### 实现的日志功能

1. **X寄存器写入日志** - 包含PC、指令编码、寄存器号和数据值
2. **F寄存器写入日志** - 包含PC、指令编码、寄存器号和数据值（100%准确的PC追踪）
3. **内存写入日志** - 包含PC、地址、数据和大小
4. **异常日志** - 包含PC、指令、cause和tval（仅同步异常，不含中断）

### 日志格式示例

```
# X寄存器写入
3 0x80000000 (0x00a50513) x10 0x00000005

# F寄存器写入  
3 0x80000100 (0x02a52007) f0 0x3f800000

# 内存写入
3 0x80000200 (STORE) addr=0x80001000 data=0x12345678 size=2

# 异常
3 0x80000300 (0x00000000) EXCEPTION cause=0x0000000000000002 tval=0x80000300
```

---

## 🔧 构建步骤

### 步骤1：检查当前修改

```bash
cd /mnt/disk1/shared/git/rocket-chip

# 查看修改的文件
git status

# 查看修改统计
git diff --stat
```

应该看到以下修改：
```
 src/main/scala/rocket/Configs.scala    |  1 +
 src/main/scala/rocket/RocketCore.scala | 50 +++++++++++++
 src/main/scala/system/Configs.scala    |  3 +
 src/main/scala/tile/Core.scala         |  2 +-
 src/main/scala/tile/FPU.scala          | 22 +++++-
 5 files changed, 74 insertions(+), 4 deletions(-)
```

---

### 步骤2：生成Verilog

#### 使用mill构建系统（推荐）

```bash
# 生成带日志功能的Verilog
mill emulator[freechips.rocketchip.system.TestHarness,freechips.rocketchip.system.DefaultConfigWithTrace].mfccompiler.compile

# 生成的文件位置
ls -lh out/emulator/freechips.rocketchip.system.TestHarness/freechips.rocketchip.system.DefaultConfigWithTrace/mfccompiler/compile.dest/
```

#### 或使用Makefile快捷方式

```bash
# 使用Makefile（内部调用mill）
make verilog CONFIG=freechips.rocketchip.system.DefaultConfigWithTrace

# 查看生成的Verilog文件
find out/ -name "*.v" -o -name "*.sv" | head -10
```

---

### 步骤3：生成C++模拟器（可选）

如果要使用Verilator仿真：

```bash
# 生成完整的C++模拟器（需要较长时间，10-30分钟）
mill emulator[freechips.rocketchip.system.TestHarness,freechips.rocketchip.system.DefaultConfigWithTrace].verilator.elf

# 模拟器可执行文件位置
ls -lh out/emulator/freechips.rocketchip.system.TestHarness/freechips.rocketchip.system.DefaultConfigWithTrace/verilator/elf.dest/emulator
```

---

### 步骤4：运行测试程序

#### 准备测试程序

```bash
# 如果还没有编译过rocket-tools
cd dependencies/rocket-tools
./build.sh

# 创建简单的测试程序
cat > test.c << 'EOF'
#include <stdio.h>

int main() {
    int a = 5;
    int b = 10;
    int c = a + b;
    
    float f1 = 3.14f;
    float f2 = 2.0f;
    float f3 = f1 * f2;
    
    int arr[10];
    arr[0] = c;
    
    return 0;
}
EOF

# 编译测试程序
riscv64-unknown-elf-gcc -march=rv64imafdc -mabi=lp64d -o test.riscv test.c
```

#### 运行仿真

```bash
# 设置模拟器路径（方便后续使用）
EMULATOR=out/emulator/freechips.rocketchip.system.TestHarness/freechips.rocketchip.system.DefaultConfigWithTrace/verilator/elf.dest/emulator

# 运行模拟器（日志会输出到stdout）
$EMULATOR +max-cycles=10000 test.riscv 2>&1 | tee test.log

# 或者使用重定向保存日志
$EMULATOR test.riscv > simulation.log 2>&1

# 如果需要更多调试信息
$EMULATOR +verbose test.riscv 2>&1 | tee test.log
```

---

## 📊 日志解析

### 日志格式详细说明

#### 1. X寄存器写入
```
<priv> 0x<pc> (0x<inst>) x<rd> 0x<data>
```
- `priv`: 特权级 (0=U, 1=S, 3=M)
- `pc`: 指令地址
- `inst`: 指令编码（32位）
- `rd`: 目标寄存器号（0-31）
- `data`: 写入的数据值

#### 2. F寄存器写入
```
<priv> 0x<pc> (0x<inst>) f<rd> 0x<data>
```
- 字段同X寄存器
- `data`: IEEE格式的浮点数（32位或64位）

#### 3. 内存写入
```
<priv> 0x<pc> (STORE) addr=0x<address> data=0x<data> size=<size>
```
- `address`: 内存地址
- `data`: 写入的数据
- `size`: 0=byte, 1=halfword, 2=word, 3=doubleword

#### 4. 异常
```
<priv> 0x<pc> (0x<inst>) EXCEPTION cause=0x<cause> tval=0x<tval>
```
- `cause`: 异常原因码
- `tval`: 异常相关值

常见cause值：
- `0x2`: 非法指令
- `0x3`: 断点
- `0x5`: load访问异常
- `0x7`: store访问异常
- `0xd`: load页面故障
- `0xf`: store页面故障

---

## 🔍 过滤和分析日志

### 提取特定类型日志

```bash
# 只看X寄存器写入
grep " x[0-9]* 0x" simulation.log

# 只看F寄存器写入
grep " f[0-9]* 0x" simulation.log

# 只看内存写入
grep "STORE" simulation.log

# 只看异常
grep "EXCEPTION" simulation.log

# 统计各类操作数量
echo "X register writes: $(grep -c ' x[0-9]* 0x' simulation.log)"
echo "F register writes: $(grep -c ' f[0-9]* 0x' simulation.log)"
echo "Memory stores: $(grep -c 'STORE' simulation.log)"
echo "Exceptions: $(grep -c 'EXCEPTION' simulation.log)"
```

### Python解析脚本示例

```python
#!/usr/bin/env python3
import re

def parse_log(filename):
    x_writes = []
    f_writes = []
    stores = []
    exceptions = []
    
    with open(filename, 'r') as f:
        for line in f:
            # X寄存器写入
            m = re.match(r'(\d+) 0x([0-9a-f]+) \(0x([0-9a-f]+)\) x(\d+) 0x([0-9a-f]+)', line)
            if m:
                x_writes.append({
                    'priv': int(m.group(1)),
                    'pc': int(m.group(2), 16),
                    'inst': int(m.group(3), 16),
                    'rd': int(m.group(4)),
                    'data': int(m.group(5), 16)
                })
            
            # F寄存器写入
            m = re.match(r'(\d+) 0x([0-9a-f]+) \(0x([0-9a-f]+)\) f(\d+) 0x([0-9a-f]+)', line)
            if m:
                f_writes.append({
                    'priv': int(m.group(1)),
                    'pc': int(m.group(2), 16),
                    'inst': int(m.group(3), 16),
                    'rd': int(m.group(4)),
                    'data': int(m.group(5), 16)
                })
            
            # 内存写入
            m = re.match(r'(\d+) 0x([0-9a-f]+) \(STORE\) addr=0x([0-9a-f]+) data=0x([0-9a-f]+) size=(\d+)', line)
            if m:
                stores.append({
                    'priv': int(m.group(1)),
                    'pc': int(m.group(2), 16),
                    'addr': int(m.group(3), 16),
                    'data': int(m.group(4), 16),
                    'size': int(m.group(5))
                })
            
            # 异常
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
x, f, s, e = parse_log('simulation.log')
print(f"Found {len(x)} X writes, {len(f)} F writes, {len(s)} stores, {len(e)} exceptions")
```

---

## ⚠️ 注意事项

### 1. 日志量
- 日志输出量很大，建议使用管道或重定向保存
- 长时间运行可能产生GB级别的日志文件

### 2. 性能影响
- printf会显著降低仿真速度
- 建议只在调试阶段使用

### 3. 占位符日志
某些长延迟指令会打印两次日志：
```
# 第一次：提交时（占位符）
3 0x80000100 (0x12345678) x5 p5 0xXXXXXXXXXXXXXXXX

# 第二次：数据就绪时（实际值）
3 0x80000100 (0x12345678) x5 0x00000042
```

如果只需要最终值，可以过滤掉包含`0xXXX...`的行：
```bash
grep -v '0xXXXXXXXX' simulation.log
```

---

## 🐛 故障排除

### 问题1：编译错误
```bash
# 清理并重新编译
mill clean
mill emulator[freechips.rocketchip.system.TestHarness,freechips.rocketchip.system.DefaultConfigWithTrace].mfccompiler.compile
```

### 问题2：找不到配置
```bash
# 检查配置是否正确添加到Scala文件
grep "DefaultConfigWithTrace" src/main/scala/system/Configs.scala

# 检查配置是否正确添加到build.sc
grep "DefaultConfigWithTrace" build.sc
```

### 问题3：没有日志输出
- 确认使用的是`DefaultConfigWithTrace`配置
- 检查`enableCommitLog`是否为true（在Core.scala中）
- 确认测试程序实际执行了指令

---

## 📝 修改说明

### 核心修改内容

1. **添加PC追踪机制** (RocketCore.scala)
   - 32项追踪buffer保存PC和指令
   - 在load、div、rocc指令发起时保存
   - 数据返回时查找对应PC

2. **添加F寄存器日志** (FPU.scala)
   - 在load和计算写回点打印完整日志
   - 使用追踪的PC而非当前PC

3. **添加内存写入日志** (RocketCore.scala)
   - 在MEM阶段检测store操作并打印

4. **添加异常日志** (RocketCore.scala)
   - 在WB阶段检测同步异常并打印

5. **添加配置类** (Configs.scala, system/Configs.scala)
   - `WithTraceCoreIngress`: 启用trace功能
   - `DefaultConfigWithTrace`: 预配置的完整配置

---

## 📚 参考资料

- [Rocket Chip文档](https://chipyard.readthedocs.io/)
- [RISC-V特权级规范](https://riscv.org/specifications/privileged-isa/)
- [Chisel语言文档](https://www.chisel-lang.org/)

---

## ✅ 验证清单

构建完成后，确认以下内容：

- [ ] Verilog生成成功
- [ ] 模拟器编译成功（如需要）
- [ ] 运行测试程序可以看到日志输出
- [ ] X寄存器写入日志包含PC和数据
- [ ] F寄存器写入日志包含PC和数据
- [ ] Store操作有内存写入日志
- [ ] 异常会打印异常日志

---

生成时间: 2024
版本: Rocket Chip with Complete Logging
