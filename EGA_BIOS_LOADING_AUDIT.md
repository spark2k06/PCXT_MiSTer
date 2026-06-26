# EGA BIOS Loading And Protection Audit

## Scope

This audit verifies how the optional EGA BIOS image is downloaded, mapped, and
write-protected by the current PCXT loader path.

Reviewed files:

- `PCXT.sv`
- `rtl/KFPC-XT/HDL/Bus_Arbiter.sv`
- `rtl/KFPC-XT/HDL/RAM.sv`
- `egabios.asm`
- `egabios.rom`

## ROM Image

`egabios.rom` is 2048 bytes. Its first bytes are:

```text
55 AA 04 E8 34 00 E8 46 00 E8 8F 00 2E A2 CC 02
```

The `55 AA 04` header matches the BIOS extension signature and a size of four
512-byte blocks, consistent with `egabios.asm`:

- `ROM_SIZE = 2048`
- `ROM_BLOCKS = ROM_SIZE / 512`
- `org 0`

The assembly source documents this BIOS as a minimal compatibility extension
for INT 10h/INT 11h probing and mode-setting smoke coverage, not as a hardware
source of truth.

## Download Selection And Address Mapping

`PCXT.sv` selects the EGA BIOS download when:

- `ioctl_index[5:0] == 3`
- `ioctl_addr[24:16] == 0`

The loader maps selected EGA BIOS bytes to:

```text
{4'b1100, ioctl_addr[15:0]} = C0000h + ioctl_addr[15:0]
```

So the current 2 KiB `egabios.rom` lands at `C0000h-C07FFh`.

The loader also accepts PCXT BIOS, Tandy BIOS, and XT-IDE downloads in the same
state machine. EGA BIOS writes use the same external bus path as those images:

- `bios_access_address` drives `address_ext`.
- `bios_write_data[7:0]` drives `data_bus_ext`.
- `bios_write_n` drives `memory_write_n_ext`.
- `bios_access_request` drives the external access request.

`Bus_Arbiter.sv` selects `address_ext` and external data while the CPU bus is
not driving a normal cycle, so BIOS downloads are isolated from ordinary CPU
execution.

## Protection State

`PCXT.sv` tracks `ega_bios_loaded`.

- Starting an EGA BIOS download clears `ega_bios_loaded`.
- Completing the second byte of an EGA BIOS word write sets `ega_bios_loaded`.
- In idle state, `bios_protect_flag` becomes `{ega_bios_loaded, ~status[31:30]}`.

`RAM.sv` interprets `bios_protect_flag[2]` as protection for:

```text
address[19:14] == 6'b110000
```

That range is `C0000h-C3FFFh`, a 16 KiB protection window. The current EGA BIOS
image only occupies `C0000h-C07FFh`, so the whole image is covered once
`ega_bios_loaded` is set. The larger protected window leaves room for a larger
EGA BIOS without changing the protection bit assignment.

## Result

The current loader places EGA BIOS downloads at the expected `C0000h` option-ROM
base and write-protects the containing `C0000h-C3FFFh` region after a successful
download. No HDL or BIOS source change is required for EGA-703.

An end-to-end smoke test is still required later: boot with the EGA BIOS loaded
and verify that the BIOS extension reaches its expected INT 10h/INT 11h
mode-setting behavior on the target core.
