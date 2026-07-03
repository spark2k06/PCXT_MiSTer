# MCGA Mode 13h EGA BIOS Gap Audit

This audit supports `MCGA-002` from `MCGA_GATE_MODE13_TASKS.md`.

## Scope

Reviewed BIOS artifacts:

- `output_files/IBM-EGA.rom`
- `output_files/IBM-EGA.zip`
- `egabios.asm`
- `egabios.rom`
- `EGA_BIOS_LOADING_AUDIT.md`

## IBM EGA Option ROM

`output_files/IBM-EGA.rom` is the current IBM EGA ROM artifact used as the
reference EGA option ROM.

Binary header:

```text
55 AA 20 EB 28 32 34 30 30 36 32 37 37 33 35 36
20 28 43 29 43 4F 50 59 52 49 47 48 54 20 49 42
4D 20 31 39 38 34 39 2F 31 33 2F 38 34 ...
```

Interpretation:

- `55 AA` is the PC option ROM signature.
- `20` means 32 blocks of 512 bytes, or 16 KiB.
- The visible ASCII string identifies IBM copyright text from 1984.

No local 8086 disassembler is available in this environment. A direct binary
scan of the ROM found no immediate instruction patterns for the normal simple
mode `13h` dispatch forms:

| Pattern | Bytes | Result |
| --- | --- | --- |
| `cmp al,13h` | `3C 13` | not found |
| `mov al,13h` | `B0 13` | not found |
| `mov ax,0013h` | `B8 13 00` | not found |
| `cmp ax,0013h` | `3D 13 00` | not found |

This scan is not a formal full disassembly proof, but it matches the
architecture expectation: IBM EGA predates MCGA/VGA packed 256-color mode
`13h`, so this ROM must not be treated as a provider of BIOS mode
`320x200x256`.

## Local `egabios` Shim

The local `egabios.asm` is a 2 KiB compatibility option ROM shim documented by
`EGA_BIOS_LOADING_AUDIT.md`. It is not the IBM EGA ROM and is not a full MCGA or
VGA BIOS.

The INT 10h mode-set dispatch in `egabios.asm` handles:

- text modes `00h..07h`, then chains to the previous INT 10h handler;
- EGA graphics mode `0Dh`, programmed locally;
- unsupported modes, which are chained to the previous INT 10h handler.

Relevant source structure:

```text
cmp ah, 00h
jne .chk_pal
cmp al, 0Dh
je .mode0d
cmp al, 07h
jbe .txtmode
jmp chain_old_int10
```

The only `0013h` literal in `egabios.asm` is an Attribute Controller register
write:

```text
mov bx, 0013h
call attr_write
```

That writes Attribute Controller index `13h` for EGA mode setup. It is not BIOS
video mode `13h`.

A direct binary scan of `egabios.rom` also found no immediate instruction
patterns for `AL/AX=13h` mode dispatch.

## Implementation Consequence

The MCGA work cannot assume existing BIOS support for `INT 10h AX=0013h`.

Final MCGA mode `13h` support must provide its own BIOS-visible entry path,
using one of these delivery options:

- extend or replace the current EGA option-ROM shim;
- add a chained option ROM for MCGA mode `13h`;
- use a DOS TSR only as a bring-up path, not as the final out-of-box path.

The long-term preference remains a BIOS or option-ROM path because a TSR loaded
from DOS cannot help software that probes or sets video mode before the TSR is
installed.
