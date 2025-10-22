#define DRAM_BASE 0x80000000

.section .text.start, "ax", @progbits
.globl _start
_start:
  csrwi 0x7c1, 0 // disable chicken bits
  li   t0, 0
  csrw mscratch, t0
  csrw mepc,     t0
  csrw mtval,    t0
  csrw pmpcfg0,  t0
  csrw pmpaddr0, t0
  csrw pmpaddr1, t0
  csrw pmpaddr2, t0
  csrw pmpaddr3, t0
  csrw pmpaddr4, t0
  csrw pmpaddr5, t0
  csrw pmpaddr6, t0
  csrw pmpaddr7, t0

  csrr t1, misa

  li   t2, (1 << ('S' - 'A'))
  and  t2, t1, t2
  beqz t2, 1f
  csrw satp,     t0
  csrw sscratch, t0
  csrw sepc,     t0
  csrw stval,    t0
  csrw scause,   t0
1:
  li   t2, (1 << ('H' - 'A'))
  and  t2, t1, t2
  beqz t2, 2f
  csrw vsatp,    t0
  csrw hgatp,    t0
  csrw vsscratch, t0
  csrw vsepc,     t0
  csrw vstval,    t0
  csrw vscause,   t0
2:
  li s0, DRAM_BASE
  csrr a0, mhartid
  la a1, _dtb
  jr s0

.section .text.hang, "ax", @progbits
.globl _hang
_hang:
  csrwi 0x7c1, 0 // disable chicken bits
  csrr a0, mhartid
  la a1, _dtb
  csrwi mie, 0
1:
  wfi
  j 1b

.section .rodata.dtb, "a", @progbits
.globl _dtb
.align 5, 0
_dtb:
.ascii "DTB goes here"
