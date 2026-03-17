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

### 1. data 字段的含义

`data` 字段给出了**真正写入内存的有效值**，已经根据地址低位偏移自动对齐到最低有效位。  
例如对于 `amoand.w` 这类可能只更新 32 位的原子指令，日志中的 `data` 会直接显示那 32 位的结果（其余字节清零），无需再手动移位或屏蔽。

硬件在写回阶段会同时记录字节掩码，并利用掩码把 64 位总线数据转换成“有效数据”后再打印。  
如果需要查看总线上的原始 64 位数值，可以参考调试日志：
```
ROCKET-DBG: WB store ... actual=0xXXXXXXXXXXXX eff=0xXXXXXXXX mask=0xXX ...
```
其中 `actual` 为总线原始数据，`eff` 为日志中显示的对齐结果。

### 2. size 字段的含义

`size` 字段使用 **log2 编码**，表示实际写入的字节数：

| size 值 | 字节数 (2^size) | 说明 |
|---------|-----------------|------|
| 0       | 1 字节          | byte (SB 指令) |
| 1       | 2 字节          | halfword (SH 指令) |
| 2       | 4 字节          | word (SW 指令) |
| 3       | 8 字节          | doubleword (SD 指令) |

### 3. 示例分析

```
3 0x00000834 (STORE) addr=0x00000104 data=0x00000000 size=2
```

- **size=2**: 表示写入 2^2 = 4 字节
- **addr=0x104**: 地址低 3 位为 0b100 (4)，表示在 8 字节对齐块中的偏移量为 4
- **data=0x00000000**: 已经对齐后的真实写入值（高 32 位被掩掉）
- **实际写入**: `0x00000000`

如果写入的数据为 `0xcdef`：
```
3 0x00000834 (STORE) addr=0x00000108 data=0x000000000000cdef size=1
```
- **size=1**: 写入 2^1 = 2 字节
- **addr=0x108**: 低 3 位为 0 (对齐)
- **实际写入**: `0xcdef`

### 4. 相关代码

- **数据生成：** `src/main/scala/rocket/RocketCore.scala`  
  `StoreGen` 根据大小和地址偏移生成写数据与掩码。
- **日志打印：** `RocketCore.scala` 中的提交阶段同时打印 `actual`（总线值）、`eff`（有效值）和 `mask`。
- **DCache 返回掩码：** `src/main/scala/rocket/DCache.scala` / `NBDcache.scala` 会把字节掩码带回核心，供日志使用。

## 总结

1. `data` 字段已经与真实写入值保持一致，无需再手动移位。
2. `size` 仍然表示写入字节数（以 log2 编码）。
3. 如果需要调试总线上的原始 64 位数据，可结合 `ROCKET-DBG: WB store ... actual=...` 日志与 `mask` 一起分析。
