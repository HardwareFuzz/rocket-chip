# Rocket Chip STORE 日志格式说明

## 日志格式
```
<priv> 0x<pc> (STORE) addr=0x<addr> data=0x<data> size=<size>
```

例如：
```
3 0x00000834 (STORE) addr=0x00000104 data=0x00000000 size=2
```

## 字段说明

### 1. data 字段为什么总是 8 位（十六进制）？

`data` 字段的位宽固定为 **coreDataBits**（通常是 64 位 = 8 字节），在十六进制中显示为 8 位数字。

**原因：**
- 硬件内存接口 (`io.dmem.s1_data.data`) 的数据总线宽度固定为 64 位
- 无论实际写入多少字节，硬件总是使用完整的数据总线宽度传输数据
- 这是标准的内存系统设计：使用固定宽度的数据总线

**代码位置：** `src/main/scala/rocket/RocketCore.scala:1217`
```scala
val mem_store_data = io.dmem.s1_data.data
when (mem_store_valid) {
  printf("3 0x%x (STORE) addr=0x%x data=0x%x size=%d\n", 
         mem_reg_pc, mem_store_addr, mem_store_data, mem_reg_mem_size)
}
```

### 2. size 字段的含义

`size` 字段使用 **log2 编码**，表示实际写入的字节数：

| size 值 | 字节数 (2^size) | 说明 |
|---------|-----------------|------|
| 0       | 1 字节          | byte (SB 指令) |
| 1       | 2 字节          | halfword (SH 指令) |
| 2       | 4 字节          | word (SW 指令) |
| 3       | 8 字节          | doubleword (SD 指令) |

### 3. 如何获取真实的有效数据？

根据 `size` 字段提取低位的有效字节：

#### 方法 1: 按字节数提取

```python
def get_real_data(data_hex, size):
    """
    data_hex: 十六进制字符串，如 "0x00000000"
    size: size 字段的值 (0, 1, 2, 3)
    返回: 实际有效的数据
    """
    data = int(data_hex, 16)
    num_bytes = 2 ** size  # 实际字节数
    mask = (1 << (num_bytes * 8)) - 1  # 创建掩码
    real_data = data & mask
    return hex(real_data)

# 示例
print(get_real_data("0x12345678", 0))  # size=0 (1字节): 0x78
print(get_real_data("0x12345678", 1))  # size=1 (2字节): 0x5678
print(get_real_data("0x12345678", 2))  # size=2 (4字节): 0x12345678
print(get_real_data("0x12345678", 3))  # size=3 (8字节): 0x12345678
```

#### 方法 2: 按地址对齐提取（更精确）

**注意：** 数据在 64 位总线上的位置取决于地址的低位（字节偏移）：

```python
def get_real_data_with_addr(data_hex, addr_hex, size):
    """
    data_hex: 数据字段，如 "0x1234567890abcdef"
    addr_hex: 地址，如 "0x104"
    size: size 字段 (0, 1, 2, 3)
    """
    data = int(data_hex, 16)
    addr = int(addr_hex, 16)
    num_bytes = 2 ** size
    
    # 计算字节偏移（地址的低 3 位）
    byte_offset = addr & 0x7
    
    # 提取从 byte_offset 开始的 num_bytes 个字节
    shift_bits = byte_offset * 8
    mask = (1 << (num_bytes * 8)) - 1
    real_data = (data >> shift_bits) & mask
    
    return hex(real_data)
```

### 4. 示例分析

```
3 0x00000834 (STORE) addr=0x00000104 data=0x00000000 size=2
```

- **size=2**: 表示写入 2^2 = 4 字节
- **addr=0x104**: 地址低 3 位为 0b100 (4)，表示在 8 字节对齐块中的偏移量为 4
- **data=0x00000000**: 64 位数据总线上的值
- **实际写入**: 从 data 的低 32 位（4 字节）取值：`0x00000000`

如果 data 不为 0：
```
3 0x00000834 (STORE) addr=0x00000108 data=0x1234567890abcdef size=1
```
- **size=1**: 写入 2^1 = 2 字节
- **addr=0x108**: 低 3 位为 0 (对齐)
- **实际写入**: 取低 16 位：`0xcdef`

### 5. 相关代码

**数据生成：** `src/main/scala/rocket/RocketCore.scala:671-672`
```scala
val size = Mux(ex_ctrl.rocc, log2Ceil(xLen/8).U, ex_reg_mem_size)
mem_reg_rs2 := new StoreGen(size, 0.U, ex_rs(1), coreDataBytes).data
```

**StoreGen 类：** `src/main/scala/rocket/AMOALU.scala:10-32`
- 负责根据 size 和地址生成正确对齐的 store 数据
- 生成 mask 字段用于字节使能

**数据接口：** `src/main/scala/rocket/HellaCache.scala:119-122`
```scala
trait HasCoreData extends HasCoreParameters {
  val data = UInt(coreDataBits.W)  // 固定 64 位宽度
  val mask = UInt(coreDataBytes.W) // 8 位 mask（每位对应 1 字节）
}
```

## 总结

1. **data 总是 64 位** 是硬件设计的结果，数据总线宽度固定
2. **size 字段** 告诉你实际写入了多少字节（2^size）
3. **提取真实数据**：根据 size 值取 data 的低 `2^size` 个字节
4. **更精确的分析**：还需要考虑地址的字节偏移量
