;
; Microcode for KFMMC_DRIVE_SPI_MODE.sv
; Written by kitune-san
;
; Convert this code to ROM using ldstasm
; https://github.com/kitune-san/LDST_Sequencer
;

; Registers
define reg1                 0x04
define reg2                 0x05
define reg3                 0x06
define reg4                 0x07

define spi_data             0x80
define spi_status           0x81
define status_flags         0x82
;define error_flags          0x83
;define interrupt_flags      0x84
define csd_input            0x85
define block_addr_1         0x86
define block_addr_2         0x87
define block_addr_3         0x88
define block_addr_4         0x89
;define trans_data           0x8A
;define command              0x8B
define storage_sectors_1    0x8C
define storage_sectors_2    0x8D
define storage_sectors_3    0x8E
define storage_sectors_4    0x8F
define storage_cylinder_1   0x90
define storage_cylinder_2   0x91
define storage_head         0x92
define storage_spt          0x93
define logical_cylinder_1   0x94
define logical_cylinder_2   0x95
define logical_head         0x96
define logical_spt          0x97


define ide_fifo             0xC1
define ide_data_req         0xC2
define ide_status           0xC3
define ide_error            0xC4
define ide_features         0xC5
define ide_sector_count     0xC6
define ide_sector_number    0xC7
define ide_cylinder_l       0xC8
define ide_cylinder_h       0xC9
define ide_head_number      0xCA
define ide_drive            0xCB
define ide_lba              0xCC
define ide_command          0xCD

reset:
    ; busy=1 CS=H
    ldi     0x03
    st      status_flags
    ; Reset error
;    ldi     0x00
;    st      error_flags
    ; Reset IDE
    ldi     0x80
    st      ide_status
    ldi     0x00
    st      ide_error

restart:
    ; Send dummy data
    ldi     10
    st      reg1
init_clock_loop:
    ldi     0xFF
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l
    ld      reg1
    st      a
    ldi     1
    st      b
    ldi     sub
    st      alu
    ld      alu
    st      reg1
    ldi     send_cmd0.h
    jz      send_cmd0.l
    ldi     init_clock_loop.h
    jmp     init_clock_loop.l

send_cmd0:
    ; CS=L
    ldi     0b11111101
    st      a
    ldi     clear_status_bit.h
    call    clear_status_bit.l

    ; Send CMD0 40 00 00 00 00 95
    ldi     0x40
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ldi     send_spi_arg_0.h
    call    send_spi_arg_0.l

    ldi     0x95
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ldi     10
    st      reg1
    ldi     wait_spi_r1_response.h
    call    wait_spi_r1_response.l

    ld      reg2
    st      a
    ldi     0x01
    st      b
    ldi     xor
    st      alu
    ld      alu
    ldi     mode_check.h
    jz      mode_check.l

    ldi     reset.h
    jmp     reset.l

mode_check:
    ; Is not MMC mode?
    ld      status_flags
    st      a
    ldi     0x04
    st      b
    ldi     and
    st      alu
    ld      alu

    ; no
    ldi     send_cmd8.h
    jz      send_cmd8.l

    ; yes
    ldi     255
    st      reg3
send_cmd1:
    ; Send CMD1 41 00 00 00 00 F9
    ldi     0x41
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ldi     send_4_dummy_clock.h
    call    send_4_dummy_clock.l

    ldi     0xF9
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ldi     10
    st      reg1
    ldi     wait_spi_r1_response.h
    call    wait_spi_r1_response.l

    ld      reg2
    st      a
    ldi     0x00
    st      b
    ldi     xor
    st      alu
    ld      alu
    ldi     send_cmd9.h
    jz      send_cmd9.l

    ld      reg3
    st      a
    ldi     1
    st      b
    ldi     sub
    st      alu
    ld      alu
    st      reg3

    ldi     reset.h
    jz      reset.l

    ldi     send_cmd1.h
    jmp     send_cmd1.l

send_cmd8:
    ; Send dummy byte
    ldi     send_1_dummy_clock.h
    call    send_1_dummy_clock.l

    ; Send CMD8 48 00 00 01 AA 87
    ldi     0x48
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l
    ldi     0x00
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l
    ldi     0x00
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l
    ldi     0x01
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l
    ldi     0xAA
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l
    ldi     0x87
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ldi     10
    st      reg1
    ldi     wait_spi_r1_response.h
    call    wait_spi_r1_response.l

    ld      reg2
    st      a
    ldi     0x01
    st      b
    ldi     xor
    st      alu
    ld      alu
    ldi     check_cmd8_response.h
    jz      check_cmd8_response.l

    ; mmc_mode=1
    ldi     0b00000100
    st      a
    ldi     set_status_bit.h
    call    set_status_bit.l

    ldi     restart.h
    jmp     restart.l

check_cmd8_response:
    ; Recive 31-8
    ldi     send_3_dummy_clock.h
    call    send_3_dummy_clock.l

    ld      spi_data
    st      a
    ldi     0x01
    st      b
    ldi     and
    st      alu
    ld      alu
    ldi     reset.h
    jz      reset.l

    ; Recive 7-0
    ldi     0xFF
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ld      spi_data
    st      a
    ldi     0xAA
    st      b
    ldi     sub
    st      alu
    ld      alu
    ldi     send_cmd55.h
    jz      send_cmd55.l

    ldi     reset.h
    jmp     reset.l

send_cmd55:
    ; Send dummy byte
    ldi     send_1_dummy_clock.h
    call    send_1_dummy_clock.l

    ; Send CMD55 77 00 00 00 00 FF
    ldi     0x77
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ldi     send_spi_arg_0.h
    call    send_spi_arg_0.l

    ldi     10
    st      reg1
    ldi     wait_spi_r1_response.h
    call    wait_spi_r1_response.l

    ld      reg2
    st      a
    ldi     0x01
    st      b
    ldi     xor
    st      alu
    ld      alu
    ldi     send_acmd41.h
    jz      send_acmd41.l

    ldi     reset.h
    jmp     reset.l

send_acmd41:
    ; Send dummy byte
    ldi     send_1_dummy_clock.h
    call    send_1_dummy_clock.l

    ; Send ACMD41 69 40 FF 80 00 FF
    ldi     0x69
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l
    ldi     0x40
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l
    ldi     0xFF
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l
    ldi     0x80
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l
    ldi     0x00
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ldi     10
    st      reg1
    ldi     wait_spi_r1_response.h
    call    wait_spi_r1_response.l

    ld      reg2
    st      a
    ldi     0x00
    st      b
    ldi     xor
    st      alu
    ld      alu
    ldi     send_cmd9.h
    jz      send_cmd9.l

    ldi     send_cmd55.h
    jmp     send_cmd55.l

send_cmd9:
    ; Send dummy byte
    ldi     send_1_dummy_clock.h
    call    send_1_dummy_clock.l

    ; Read CSD
    ; Send ACMD41 49 00 00 00 00 FF
    ldi     0x49
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ldi     send_spi_arg_0.h
    call    send_spi_arg_0.l

    ldi     10
    st      reg1
    ldi     wait_spi_r1_response.h
    call    wait_spi_r1_response.l

    ld      reg2
    st      a
    ldi     0x00
    st      b
    ldi     xor
    st      alu
    ld      alu
    ldi     cmd9_read_csd_1.h
    jz      cmd9_read_csd_1.l

    ldi     reset.h
    jmp     reset.l

cmd9_read_csd_1:
    ldi     10
    st      reg1
    ldi     0xFE
    st      reg2
    ldi     wait_to_start_spi_transmission.h
    call    wait_to_start_spi_transmission.l

    ld      reg3
    st      a
    ldi     0xFE
    st      b
    ldi     xor
    st      alu
    ld      alu
    ldi     cmd9_read_csd_2.h
    jz      cmd9_read_csd_2.l

    ldi     reset.h
    jmp     reset.l

cmd9_read_csd_2:
    ldi     16
    st      reg1
cmd9_read_csd_3:
    ldi     0xFF
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l
    ld      spi_data
    st      csd_input
    ld      reg1
    st      a
    ldi     1
    st      b
    ldi     sub
    st      alu
    ld      alu
    st      reg1
    ldi     send_cmd58.h
    jz      send_cmd58.l

    ldi     cmd9_read_csd_3.h
    jmp     cmd9_read_csd_3.l

send_cmd58:
    ; Send dummy byte
    ldi     send_1_dummy_clock.h
    call    send_1_dummy_clock.l

    ; Read OCR
    ; Send CMD58 7A 00 00 00 00 FF
    ldi     0x7A
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ldi     send_spi_arg_0.h
    call    send_spi_arg_0.l

    ldi     10
    st      reg1
    ldi     wait_spi_r1_response.h
    call    wait_spi_r1_response.l

    ld      reg2
    st      a
    ldi     0x00
    st      b
    ldi     xor
    st      alu
    ld      alu
    ldi     send_cmd58_get_ccs.h
    jz      send_cmd58_get_ccs.l

    ldi     reset.h
    jmp     reset.l

send_cmd58_get_ccs:
    ldi     0b10111111
    st      a
    ldi     clear_status_bit.h
    call    clear_status_bit.l

    ldi     0xFF
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ld      spi_data
    st      a
    ldi     0x40
    st      b
    ldi     and
    st      alu
    ld      alu
    st      a
    ldi     set_status_bit.h
    call    set_status_bit.l

    ldi     send_3_dummy_clock.h
    call    send_3_dummy_clock.l

calc_ide_chs:
    ; Calculate CHS
    ld      storage_sectors_1
    st      reg1
    ld      storage_sectors_2
    st      reg2
    ld      storage_sectors_3
    st      reg3
    ld      storage_sectors_4
    st      reg4

    ; initial-cylinder = 0
    ldi     0
    st      storage_cylinder_1
    st      storage_cylinder_2
    ; initial-head = 15
    ldi     15
    st      storage_head
    ; initial-spt = 63
    ldi     63
    st      storage_spt

loop_calc_ide_chs:
    ; LBA -= 945(0x03B1)
    ld      reg1
    st      a
    ldi     0xB1
    st      b
    ldi     sub
    st      alu
    ld      alu
    st      reg1

    ld      reg2
    st      a
    ldi     0x03
    st      b
    ldi     sbc
    st      alu
    ld      alu
    st      reg2

    ldi     0x00
    st      b

    ld      reg3
    st      a
    ld      alu
    st      reg3

    ld      reg4
    st      a
    ld      alu
    st      reg4

    ldi     increment_cylinder.h
    jc      increment_cylinder.l

    ldi     end_calc_ide_chs.h
    jmp     end_calc_ide_chs.l

increment_cylinder:
    ; ++cylinder
    ld      storage_cylinder_1
    st      a
    ldi     1
    st      b
    ldi     add
    st      alu
    ld      alu
    st      storage_cylinder_1

    ld      storage_cylinder_2
    st      a
    ldi     0
    st      b
    ldi     adc
    st      alu
    ld      alu
    st      storage_cylinder_2
    st      b

    ldi     0x40
    st      a
    ldi     sub
    st      alu
    ld      alu

    ldi     loop_calc_ide_chs.h
    jc      loop_calc_ide_chs.l

    ldi     0xFF
    st      storage_cylinder_1
    ldi     0x3F
    st      storage_cylinder_2

end_calc_ide_chs:

    ld      storage_cylinder_1
    st      logical_cylinder_1

    ld      storage_cylinder_2
    st      logical_cylinder_2

    ld      storage_head
    st      logical_head

    ld      storage_spt
    st      logical_spt

diagnostic:

    ; err=0
    ldi     0b11111110
    st      a
    ldi     clear_ide_status_bit.h
    call    clear_ide_status_bit.l

    ldi     0x00
    st      ide_error
    ldi     0x01
    st      ide_sector_count
    ldi     0x01
    st      ide_sector_number
    ldi     0x00
    st      ide_cylinder_l
    st      ide_cylinder_h
    st      ide_head_number
    st      ide_drive

    ldi     busy_wait.h
    call    busy_wait.l


ready:
    ; busy=0
    ldi     0b11111110
    st      a
    ldi     clear_status_bit.h
    call    clear_status_bit.l

    ; ide busy=0
    ldi     0b01111111
    st      a
    ldi     clear_ide_status_bit.h
    call    clear_ide_status_bit.l
    ; ide ready=1
    ldi     0b01000000
    st      a
    ldi     set_ide_status_bit.h
    call    set_ide_status_bit.l

    ; normal spi clock mode
    ldi     0b00000010
    st      spi_status

wait_command:
    ld      ide_status
    st      a
    ldi     0b10000000
    st      b
    ldi     and
    st      alu
    ld      alu
    ldi     wait_command.h
    jz      wait_command.l

    ; Check Device Diagnostic command
    ld      ide_command
    st      a
    ldi     0x90    ; DEVICE DIAGNOSTIC
    st      b
    ldi     xor
    st      alu
    ld      alu
    ldi     diagnostic.h
    jz      diagnostic.l

    ; check drive select
    ld      ide_drive
    st      a
    ldi     0x01
    st      b
    ldi     and
    st      alu
    ld      alu
    ldi     ready.h
    jz      ready.l

    ; Clear flags
    ldi     0
;    st      error_flags
;    st      interrupt_flags
    st      ide_error

    ; ide ready=0 dreq=0, err=0
    ldi     0b10110110
    st      a
    ldi     clear_ide_status_bit.h
    call    clear_ide_status_bit.l

    ; Check command
    ldi     xor
    st      alu
    ld      ide_command
    st      a

    ldi     0x08    ; DEVICE RESET
    st      b
    ld      alu
    ldi     reset.h
    jz      reset.l

    ldi     0x91    ; INITIALIZE DEVICE PARAMETERS
    st      b
    ld      alu
    ldi     init_device_parameters.h
    jz      init_device_parameters.l

    ldi     0x20    ; READ SECTOR(S)
    st      b
    ld      alu
    ldi     read_sectors_command.h
    jz      read_sectors_command.l

    ldi     0x21    ; READ SECTOR(S)
    st      b
    ld      alu
    ldi     read_sectors_command.h
    jz      read_sectors_command.l

    ldi     0x30    ; WRITE SECTOR(S)
    st      b
    ld      alu
    ldi     write_sectors_command.h
    jz      write_sectors_command.l

    ldi     0x31    ; WRITE SECTOR(S)
    st      b
    ld      alu
    ldi     write_sectors_command.h
    jz      write_sectors_command.l

    ldi     0x40    ; READ VERIFY SECTOR(S)
    st      b
    ld      alu
    ldi     verify_command.h
    jz      verify_command.l

    ldi     0x41    ; READ VERIFY SECTOR(S)
    st      b
    ld      alu
    ldi     verify_command.h
    jz      verify_command.l

    ldi     0xC4    ; READ MULTIPLE
    st      b
    ld      alu
    ldi     read_sectors_command.h
    jz      read_sectors_command.l

    ldi     0xC5    ; WRITE MULTIPLE
    st      b
    ld      alu
    ldi     write_sectors_command.h
    jz      write_sectors_command.l

    ldi     0xC6    ; SET MULTIPLE
    st      b
    ld      alu
    ldi     invalid_command.h
    jz      invalid_command.l

    ldi     0x70    ; SEEK
    st      b
    ld      alu
    ldi     ready.h
    jz      ready.l

    ldi     0xEC    ; IDENTIFY DEVICE
    st      b
    ld      alu
    ldi     identify_device_cmd.h
    jz      identify_device_cmd.l

invalid_command:
    ; ide err=1
    ldi     0b00000001
    st      a
    ldi     set_ide_status_bit.h
    call    set_ide_status_bit.l

    ldi     0b00000100
    st      ide_error

    ldi     ready.h
    jmp     ready.l


init_device_parameters:
    ; Check argument
    ldi     0
    st      a
    ldi     or
    st      alu

    ld      ide_sector_count
    st      b
    ld      alu
    ldi     invalid_command.h
    jz      invalid_command.l

    ld      ide_head_number
    st      b
    ld      alu
    ldi     invalid_command.h
    jz      invalid_command.l

    ld      ide_sector_count
    st      logical_spt

    ld      ide_head_number
    st      logical_head

    ; total_cylinder = LBA / (spt * total_headers)
    ; x = spt * total_headers
    ldi     0
    st      reg1
    st      reg2
    st      logical_cylinder_1
    st      logical_cylinder_2

spt_x_headers_loop:
    ld      reg1
    st      a
    ld      logical_spt
    st      b
    ldi     add
    st      alu
    ld      alu
    st      reg1

    ld      reg2
    st      a
    ldi     0
    st      b
    ldi     adc
    st      alu
    ld      alu
    st      reg2

    ld      logical_head
    st      a
    ldi     1
    st      b
    ldi     sub
    st      alu
    ld      alu
    st      logical_head

    ldi     end_spt_x_headers_loop.h
    jz      end_spt_x_headers_loop.l

    ldi     spt_x_headers_loop.h
    jmp     spt_x_headers_loop.l

end_spt_x_headers_loop:
    ld      ide_head_number
    st      logical_head

    ; total_cylinder = LBA / x
    ld      storage_sectors_1
    st      block_addr_1

    ld      storage_sectors_2
    st      block_addr_2

    ld      storage_sectors_3
    st      block_addr_3

    ld      storage_sectors_4
    st      block_addr_4

calc_total_cylinder_loop:
    ld      block_addr_1
    st      a
    ld      reg1
    st      b
    ldi     sub
    st      alu
    ld      alu
    st      block_addr_1

    ld      block_addr_2
    st      a
    ld      reg2
    st      b
    ldi     sbc
    st      alu
    ld      alu
    st      block_addr_2

    ldi     0
    st      b

    ld      block_addr_3
    st      a
    ld      alu
    st      block_addr_3

    ld      block_addr_4
    st      a
    ld      alu
    st      block_addr_4

    ldi     calc_total_cylinder_loop_inc_c.h
    jc      calc_total_cylinder_loop_inc_c.l

    ldi     end_calc_total_cylinder_loop.h
    jmp     end_calc_total_cylinder_loop.l

calc_total_cylinder_loop_inc_c:
    ld      logical_cylinder_1
    st      a
    ldi     1
    st      b
    ldi     add
    st      alu
    ld      alu
    st      logical_cylinder_1

    ld      logical_cylinder_2
    st      a
    ldi     0
    st      b
    ldi     adc
    st      alu
    ld      alu
    st      logical_cylinder_2
    st      b

    ldi     0x40
    st      a
    ldi     sub
    st      alu
    ld      alu

    ldi     calc_total_cylinder_loop.h
    jc      calc_total_cylinder_loop.l

    ldi     0xFF
    st      logical_cylinder_1
    ldi     0x3F
    st      logical_cylinder_2

end_calc_total_cylinder_loop:
    ldi     ready.h
    jmp     ready.l


verify_command:
    ldi     0x08
    st      a
    ldi     set_status_bit.h
    call    set_status_bit.l

read_sectors_command:
    ldi     calc_lba.h
    call    calc_lba.l

send_cmd17:
    ; Read command
    ldi     0xFF
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ; Block read
    ; Send CMD17 51 xx xx xx xx FF
    ldi     0x51
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ldi     send_address.h
    call    send_address.l

    ldi     10
    st      reg1
    ldi     wait_spi_r1_response.h
    call    wait_spi_r1_response.l

    ld      reg2
    st      a
    ldi     0x00
    st      b
    ldi     xor
    st      alu
    ld      alu
    ldi     send_cmd17_clear_wait_token_count.h
    jz      send_cmd17_clear_wait_token_count.l

    ldi     send_cmd17_error.h
    jmp     send_cmd17_error.l

send_cmd17_clear_wait_token_count:
    ldi     255
    st      reg4

send_cmd17_data_token:
    ldi     255
    st      reg1
    ldi     0xFE
    st      reg2
    ldi     wait_to_start_spi_transmission.h
    call    wait_to_start_spi_transmission.l

    ld      reg3
    st      a
    ldi     0xFE
    st      b
    ldi     xor
    st      alu
    ld      alu
    ldi     send_cmd17_set_read_count.h
    jz      send_cmd17_set_read_count.l

    ld      reg4
    st      a
    ldi     1
    st      b
    ldi     sub
    st      alu
    ld      alu
    st      reg4

    ldi     send_cmd17_error.h
    jz      send_cmd17_error.l

    ldi     send_cmd17_data_token.h
    jmp     send_cmd17_data_token.l


send_cmd17_set_read_count:
    ldi     0xFF
    st      reg1
    ldi     0x01
    st      reg2

send_cmd17_read_data:
    ldi     0xFF
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

;    ; Read byte interrupt
;    ldi     0b00000001
;    st      interrupt_flags
;
;    ldi     and
;    st      alu
;    ldi     0b00000001
;    st      b
;send_cmd17_wait:
;    ld      interrupt_flags
;    st      a
;    ld      alu
;    ldi     send_cmd17_next_check.h
;    jz      send_cmd17_next_check.l
;
;    ldi     send_cmd17_wait.h
;    jmp     send_cmd17_wait.l

    ; Put read data into FIFO
    ld      spi_data
    st      ide_fifo

send_cmd17_next_check:
    ldi     dec_16.h
    call    dec_16.l

    ldi     send_cmd17_read_data.h
    jc      send_cmd17_read_data.l

;    ; Read completion interrupt
;    ldi     0b00000010
;    st      interrupt_flags
;
;    ldi     busy_wait.h
;    jmp     busy_wait.l

    ldi     busy_wait.h
    call    busy_wait.l

    ld      status_flags
    st      a
    ldi     0x08
    st      b
    ldi     and
    st      alu
    ld      alu

    ldi     send_cmd17_transmit_data.h
    jz      send_cmd17_transmit_data.l

    ldi     send_cmd17_next_sector.h
    jmp     send_cmd17_next_sector.l

send_cmd17_transmit_data:
    ldi     transmit_data.h
    call    transmit_data.l

send_cmd17_next_sector:
    ld      ide_sector_count
    st      a
    ldi     1
    st      b
    ldi     sub
    st      alu
    ld      alu
    st      ide_sector_count

    ldi     end_read_sectors_command.h
    jz      end_read_sectors_command.l

    ; Increment LBA
    ldi     increment_lba.h
    call    increment_lba.l

    ; Next sector
    ldi     send_cmd17.h
    jmp     send_cmd17.l

send_cmd17_error:
    ; ide err=1
    ldi     0b01000000
    st      ide_error
    ldi     0b00000001
    st      a
    ldi     set_ide_status_bit.h
    call    set_ide_status_bit.l

end_read_sectors_command:
    ldi     0b11110111
    st      a
    ldi     clear_status_bit.h
    call    clear_status_bit.l

    ldi     ready.h
    jmp     ready.l


write_sectors_command:
    ldi     calc_lba.h
    call    calc_lba.l

send_cmd24:
    ldi     transmit_data.h
    call    transmit_data.l

    ; Write command
    ldi     0xFF
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ; Block Write
    ; Send CMD24 58 xx xx xx xx FF
    ldi     0x58
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ldi     send_address.h
    call    send_address.l

    ldi     10
    st      reg1
    ldi     wait_spi_r1_response.h
    call    wait_spi_r1_response.l

    ld      reg2
    st      a
    ldi     0x00
    st      b
    ldi     xor
    st      alu
    ld      alu
    ldi     send_cmd24_set_write_count.h
    jz      send_cmd24_set_write_count.l

    ldi     send_cmd24_error.h
    jmp     send_cmd24_error.l

send_cmd24_set_write_count:
    ldi     0xFF
    st      reg1
    ldi     0x01
    st      reg2

send_cmd24_data_token:
    ldi     0xFF
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ldi     0xFE
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

send_cmd24_data_request:
;    ; Request write byte interrupt
;    ldi     0b00000100
;    st      interrupt_flags
;
;    ldi     and
;    st      alu
;    ldi     0b00000100
;    st      b
;send_cmd24_wait:
;    ld      interrupt_flags
;    st      a
;    ld      alu
;    ldi     send_cmd24_write.h
;    jz      send_cmd24_write.l
;
;    ldi     send_cmd24_wait.h
;    jmp     send_cmd24_wait.l

send_cmd24_write:
    ld      ide_fifo
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

send_cmd24_next_check:
    ldi     dec_16.h
    call    dec_16.l

    ldi     send_cmd24_data_request.h
    jc      send_cmd24_data_request.l

    ; Write completion
    ldi     send_3_dummy_clock.h
    call    send_3_dummy_clock.l

    ; Check data response
    ld      spi_data
    st      a
    ldi     0b00011111
    st      b
    ldi     and
    st      alu
    ld      alu
    st      a
    ldi     0b00000101
    st      b
    ldi     xor
    st      alu
    ld      alu

    ldi     send_cmd24_complete.h
    jz      send_cmd24_complete.l

    ldi     send_cmd24_error.h
    jmp     send_cmd24_error.l

send_cmd24_complete:
;    ; Write completion interrupt
;    ldi     0b00001000
;    st      interrupt_flags

    ldi     busy_wait.h
    call    busy_wait.l

    ld      ide_sector_count
    st      a
    ldi     1
    st      b
    ldi     sub
    st      alu
    ld      alu
    st      ide_sector_count

    ldi     end_write_sectors_command.h
    jz      end_write_sectors_command.l

    ; Increment LBA
    ldi     increment_lba.h
    call    increment_lba.l

    ; Next sector
    ldi     send_cmd24.h
    jmp     send_cmd24.l

send_cmd24_error:
;    ldi     0b00000010
;    st      error_flags
    ; ide err=1
    ldi     0b01000000
    st      ide_error
    ldi     0b00000001
    st      a
    ldi     set_ide_status_bit.h
    call    set_ide_status_bit.l

end_write_sectors_command:
    ldi     ready.h
    jmp     ready.l

identify_device_cmd:
    ; Set identify info to fifo
    ldi     0x40                ;   0 : 
    st      ide_fifo
    ldi     0x00                ;   1 : 
    st      ide_fifo
    ld      storage_cylinder_1  ;   2 : Storage Cylinder L
    st      ide_fifo
    ld      storage_cylinder_2  ;   3 : Storage Cylinder H
    st      ide_fifo
    ldi     0x00                ;   4 : 
    st      ide_fifo
    ldi     0x00                ;   5 : 
    st      ide_fifo
    ld      storage_head        ;   6 : Storage head
    st      ide_fifo
    ldi     0x00                ;   7 : 
    st      ide_fifo
    ldi     0x00                ;   8 : 
    st      ide_fifo
    ldi     0x00                ;   9 : 
    st      ide_fifo
    ldi     0x00                ;  10 : 
    st      ide_fifo
    ldi     0x00                ;  11 : 
    st      ide_fifo
    ld      storage_spt         ;  12 : Storage spt
    st      ide_fifo
    ldi     0x00                ;  13 : 
    st      ide_fifo
    ldi     0x00                ;  14 : 
    st      ide_fifo
    ldi     0x00                ;  15 : 
    st      ide_fifo
    ldi     0x00                ;  16 : 
    st      ide_fifo
    ldi     0x00                ;  17 : 
    st      ide_fifo
    ldi     0x00                ;  18 : 
    st      ide_fifo
    ldi     0x00                ;  19 : 
    st      ide_fifo
    ldi     0x46                ;  20 : KFMMC-
    st      ide_fifo
    ldi     0x4B                ;  21 : 
    st      ide_fifo
    ldi     0x4D                ;  22 : 
    st      ide_fifo
    ldi     0x4D                ;  23 : 
    st      ide_fifo
    ldi     0x49                ;  24 : 
    st      ide_fifo
    ldi     0x43                ;  25 : 
    st      ide_fifo
    ldi     0x45                ;  26 : 
    st      ide_fifo
    ldi     0x44                ;  27 : 
    st      ide_fifo
    ldi     0x30                ;  28 : 
    st      ide_fifo
    ldi     0x30                ;  29 : 
    st      ide_fifo
    ldi     0x30                ;  30 : 
    st      ide_fifo
    ldi     0x30                ;  31 : 
    st      ide_fifo
    ldi     0x20                ;  32 : 
    st      ide_fifo
    ldi     0x30                ;  33 : 
    st      ide_fifo
    ldi     0x20                ;  34 : 
    st      ide_fifo
    ldi     0x20                ;  35 : 
    st      ide_fifo
    ldi     0x20                ;  36 : 
    st      ide_fifo
    ldi     0x20                ;  37 : 
    st      ide_fifo
    ldi     0x20                ;  38 : 
    st      ide_fifo
    ldi     0x20                ;  39 : 
    st      ide_fifo
    ldi     0x00                ;  40 : 
    st      ide_fifo
    ldi     0x00                ;  41 : 
    st      ide_fifo
    ldi     0x00                ;  42 : 
    st      ide_fifo
    ldi     0x00                ;  43 : 
    st      ide_fifo
    ldi     0x00                ;  44 : 
    st      ide_fifo
    ldi     0x00                ;  45 : 
    st      ide_fifo
    ldi     0x30                ;  46 : 
    st      ide_fifo
    ldi     0x30                ;  47 : 
    st      ide_fifo
    ldi     0x30                ;  48 : 
    st      ide_fifo
    ldi     0x30                ;  49 : 
    st      ide_fifo
    ldi     0x30                ;  50 : 
    st      ide_fifo
    ldi     0x30                ;  51 : 
    st      ide_fifo
    ldi     0x30                ;  52 : 
    st      ide_fifo
    ldi     0x30                ;  53 : 
    st      ide_fifo
    ldi     0x46                ;  54 : 
    st      ide_fifo
    ldi     0x4B                ;  55 : 
    st      ide_fifo
    ldi     0x4D                ;  56 : 
    st      ide_fifo
    ldi     0x4D                ;  57 : 
    st      ide_fifo
    ldi     0x49                ;  58 : 
    st      ide_fifo
    ldi     0x43                ;  59 : 
    st      ide_fifo
    ldi     0x45                ;  60 : 
    st      ide_fifo
    ldi     0x44                ;  61 : 
    st      ide_fifo
    ldi     0x30                ;  62 : 
    st      ide_fifo
    ldi     0x30                ;  63 : 
    st      ide_fifo
    ldi     0x30                ;  64 : 
    st      ide_fifo
    ldi     0x30                ;  65 : 
    st      ide_fifo
    ldi     0x20                ;  66 : 
    st      ide_fifo
    ldi     0x30                ;  67 : 
    st      ide_fifo
    ldi     0x20                ;  68 : 
    st      ide_fifo
    ldi     0x20                ;  69 : 
    st      ide_fifo
    ldi     0x20                ;  70 : 
    st      ide_fifo
    ldi     0x20                ;  71 : 
    st      ide_fifo
    ldi     0x20                ;  72 : 
    st      ide_fifo
    ldi     0x20                ;  73 : 
    st      ide_fifo
    ldi     0x20                ;  74 : 
    st      ide_fifo
    ldi     0x20                ;  75 : 
    st      ide_fifo
    ldi     0x20                ;  76 : 
    st      ide_fifo
    ldi     0x20                ;  77 : 
    st      ide_fifo
    ldi     0x20                ;  78 : 
    st      ide_fifo
    ldi     0x20                ;  79 : 
    st      ide_fifo
    ldi     0x20                ;  80 : 
    st      ide_fifo
    ldi     0x20                ;  81 : 
    st      ide_fifo
    ldi     0x20                ;  82 : 
    st      ide_fifo
    ldi     0x20                ;  83 : 
    st      ide_fifo
    ldi     0x20                ;  84 : 
    st      ide_fifo
    ldi     0x20                ;  85 : 
    st      ide_fifo
    ldi     0x20                ;  86 : 
    st      ide_fifo
    ldi     0x20                ;  87 : 
    st      ide_fifo
    ldi     0x20                ;  88 : 
    st      ide_fifo
    ldi     0x20                ;  89 : 
    st      ide_fifo
    ldi     0x20                ;  90 : 
    st      ide_fifo
    ldi     0x20                ;  91 : 
    st      ide_fifo
    ldi     0x20                ;  92 : 
    st      ide_fifo
    ldi     0x20                ;  93 : 
    st      ide_fifo
    ldi     0x01                ;  94 : 
    st      ide_fifo
    ldi     0x80                ;  95 : 
    st      ide_fifo
    ldi     0x00                ;  96 : 
    st      ide_fifo
    ldi     0x00                ;  97 : 
    st      ide_fifo
    ldi     0x00                ;  98 : 
    st      ide_fifo
    ldi     0x02                ;  99 : 
    st      ide_fifo
    ldi     0x01                ; 100 : 
    st      ide_fifo 
    ldi     0x40                ; 101 : 
    st      ide_fifo 
    ldi     0x00                ; 102 : 
    st      ide_fifo 
    ldi     0x02                ; 103 : 
    st      ide_fifo 
    ldi     0x00                ; 104 : 
    st      ide_fifo 
    ldi     0x02                ; 105 : 
    st      ide_fifo 
    ldi     0x07                ; 106 : 
    st      ide_fifo 
    ldi     0x00                ; 107 : 
    st      ide_fifo 
    ld      logical_cylinder_1  ; 108 : Logical cylinder L
    st      ide_fifo 
    ld      logical_cylinder_2  ; 109 : Logical cylinder H
    st      ide_fifo 
    ld      logical_head        ; 110 : Logical head
    st      ide_fifo 
    ldi     0x00                ; 111 : 
    st      ide_fifo 
    ld      logical_spt         ; 112 : Logical spt
    st      ide_fifo 
    ldi     0x00                ; 113 : 
    st      ide_fifo 
    ld      storage_sectors_1   ; 114 : storage_total_sectors 15-0 L
    st      ide_fifo 
    ld      storage_sectors_2   ; 115 : storage_total_sectors 15-0 H
    st      ide_fifo 
    ld      storage_sectors_3   ; 116 : storage_total_sectors 31-16 L
    st      ide_fifo
    ld      storage_sectors_4   ; 117 : storage_total_sectors 31-16 H
    st      ide_fifo 
    ldi     0x00                ; 118 : 
    st      ide_fifo 
    ldi     0x00                ; 119 : 
    st      ide_fifo 
    ld      storage_sectors_1   ; 120 : storage_total_sectors 15-0 L
    st      ide_fifo
    ld      storage_sectors_2   ; 121 : storage_total_sectors 15-0 H
    st      ide_fifo
    ld      storage_sectors_3   ; 122 : storage_total_sectors 31-16 L
    st      ide_fifo
    ld      storage_sectors_4   ; 123 : storage_total_sectors 31-16 H
    st      ide_fifo 
    ldi     0x00                ; 124 : 
    st      ide_fifo 
    ldi     0x00                ; 125 : 
    st      ide_fifo 
    ldi     0x00                ; 126 : 
    st      ide_fifo 
    ldi     0x00                ; 127 : 
    st      ide_fifo 
    ldi     0x00                ; 128 : 
    st      ide_fifo 
    ldi     0x00                ; 129 : 
    st      ide_fifo 
    ldi     0x78                ; 130 : 
    st      ide_fifo 
    ldi     0x00                ; 131 : 
    st      ide_fifo 
    ldi     0x78                ; 132 : 
    st      ide_fifo 
    ldi     0x00                ; 133 : 
    st      ide_fifo 
    ldi     0x78                ; 134 : 
    st      ide_fifo 
    ldi     0x00                ; 135 : 
    st      ide_fifo 
    ldi     0x78                ; 136 : 
    st      ide_fifo 
    ldi     0x00                ; 137 : 
    st      ide_fifo 
    ldi     0x00                ; 138 : 
    st      ide_fifo 
    ldi     0x00                ; 139 : 
    st      ide_fifo 
    ldi     0x00                ; 140 : 
    st      ide_fifo 
    ldi     0x00                ; 141 : 
    st      ide_fifo 
    ldi     0x00                ; 142 : 
    st      ide_fifo 
    ldi     0x00                ; 143 : 
    st      ide_fifo 
    ldi     0x00                ; 144 : 
    st      ide_fifo 
    ldi     0x00                ; 145 : 
    st      ide_fifo 
    ldi     0x00                ; 146 : 
    st      ide_fifo 
    ldi     0x00                ; 147 : 
    st      ide_fifo 
    ldi     0x00                ; 148 : 
    st      ide_fifo 
    ldi     0x00                ; 149 : 
    st      ide_fifo 
    ldi     0x00                ; 150 : 
    st      ide_fifo 
    ldi     0x00                ; 151 : 
    st      ide_fifo 
    ldi     0x00                ; 152 : 
    st      ide_fifo 
    ldi     0x00                ; 153 : 
    st      ide_fifo 
    ldi     0x00                ; 154 : 
    st      ide_fifo 
    ldi     0x00                ; 155 : 
    st      ide_fifo 
    ldi     0x00                ; 156 : 
    st      ide_fifo 
    ldi     0x00                ; 157 : 
    st      ide_fifo 
    ldi     0x00                ; 158 : 
    st      ide_fifo 
    ldi     0x00                ; 159 : 
    st      ide_fifo 
    ldi     0x7E                ; 160 : 
    st      ide_fifo 
    ldi     0x00                ; 161 : 
    st      ide_fifo 
    ldi     0x00                ; 162 : 
    st      ide_fifo 
    ldi     0x00                ; 163 : 
    st      ide_fifo 
    ldi     0x00                ; 164 : 
    st      ide_fifo 
    ldi     0x00                ; 165 : 
    st      ide_fifo 
    ldi     0x00                ; 166 : 
    st      ide_fifo 
    ldi     0x00                ; 167 : 
    st      ide_fifo 
    ldi     0x00                ; 168 : 
    st      ide_fifo 
    ldi     0x00                ; 169 : 
    st      ide_fifo 
    ldi     0x00                ; 170 : 
    st      ide_fifo 
    ldi     0x00                ; 171 : 
    st      ide_fifo 
    ldi     0x00                ; 172 : 
    st      ide_fifo 
    ldi     0x00                ; 173 : 
    st      ide_fifo 
    ldi     0x00                ; 174 : 
    st      ide_fifo 
    ldi     0x00                ; 175 : 
    st      ide_fifo 
    ldi     0x00                ; 176 : 
    st      ide_fifo 
    ldi     0x00                ; 177 : 
    st      ide_fifo 
    ldi     0x00                ; 178 : 
    st      ide_fifo 
    ldi     0x00                ; 179 : 
    st      ide_fifo 
    ldi     0x00                ; 180 : 
    st      ide_fifo 
    ldi     0x00                ; 181 : 
    st      ide_fifo 
    ldi     0x00                ; 182 : 
    st      ide_fifo 
    ldi     0x00                ; 183 : 
    st      ide_fifo 
    ldi     0x00                ; 184 : 
    st      ide_fifo 
    ldi     0x00                ; 185 : 
    st      ide_fifo 
    ldi     0x0B                ; 186 : 
    st      ide_fifo 
    ldi     0x63                ; 187 : 
    st      ide_fifo 

    ldi     1
    st      b
    ldi     sub
    st      alu

fifo_in_188_256:
    ; 188-256
    ldi     69
    st      a

fifo_in_188_256_rep:
    ldi     0x00
    st      ide_fifo

    ld      alu
    st      a

    ldi     fifo_in_257_511.h
    jz      fifo_in_257_511.l

    ldi     fifo_in_188_256_rep.h
    jmp     fifo_in_188_256_rep.l

fifo_in_257_511:
    ;257-511
    ldi     255
    st      a

fifo_in_257_511_rep:
    ldi     0x00
    st      ide_fifo

    ld      alu
    st      a

    ldi     identify_transmit.h
    jz      identify_transmit.l

    ldi     fifo_in_257_511_rep.h
    jmp     fifo_in_257_511_rep.l

identify_transmit:
    ldi     transmit_data.h
    call    transmit_data.l

    ldi     ready.h
    jmp     ready.l


;
; Busy wait
;
busy_wait:
    ldi     0xFF
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ld      spi_data
    st      a
    ldi     0xFF
    st      b
    ldi     xor
    st      alu
    ld      alu

    ldi     end_busy_wait.h
    jz      end_busy_wait.l

    ldi     busy_wait.h
    jmp     busy_wait.l

end_busy_wait:
    ret

;
; Calculate LBA
;
calc_lba:
    ld      ide_lba
    st      a
    ldi     0x01
    st      b
    ldi     and
    st      alu
    ld      alu

    ldi     calc_lba_from_chs.h
    jz      calc_lba_from_chs.l


    ld      ide_sector_number
    st      block_addr_1

    ld      ide_cylinder_l
    st      block_addr_2

    ld      ide_cylinder_h
    st      block_addr_3

    ld      ide_head_number
    st      block_addr_4

    ret

calc_lba_from_chs:
    ; LBA = (H + C * total_headers) * spt + (S - 1)
    ldi     0
    st      block_addr_1
    st      block_addr_2
    st      block_addr_3
    st      block_addr_4
    st      reg2
    st      reg3

    ; x = H + C * total_headers
    ld      ide_head_number
    st      reg1

    ld      logical_head
    st      reg4

c_x_h_loop:
    ld      reg1
    st      a
    ld      ide_cylinder_l
    st      b
    ldi     add
    st      alu
    ld      alu
    st      reg1

    ld      reg2
    st      a
    ld      ide_cylinder_h
    st      b
    ldi     adc
    st      alu
    ld      alu
    st      reg2

    ld      reg3
    st      a
    ldi     0
    st      b
    ld      alu
    st      reg3


    ld      reg4
    st      a
    ldi     1
    st      b
    ldi     sub
    st      alu
    ld      alu
    st      reg4

    ldi     end_c_x_h_loop.h
    jz      end_c_x_h_loop.l

    ldi     c_x_h_loop.h
    jmp     c_x_h_loop.l

end_c_x_h_loop:
    ld      logical_spt
    st      reg4

x_spt_loop:
    ; x *= spt
    ld      block_addr_1
    st      a
    ld      reg1
    st      b
    ldi     add
    st      alu
    ld      alu
    st      block_addr_1

    ld      block_addr_2
    st      a
    ld      reg2
    st      b
    ldi     adc
    st      alu
    ld      alu
    st      block_addr_2

    ld      block_addr_3
    st      a
    ld      reg3
    st      b
    ld      alu
    st      block_addr_3

    ld      block_addr_4
    st      a
    ldi     0
    st      b
    ld      alu
    st      block_addr_4


    ld      reg4
    st      a
    ldi     1
    st      b
    ldi     sub
    st      alu
    ld      alu
    st      reg4

    ldi     end_x_spt_loop.h
    jz      end_x_spt_loop.l

    ldi     x_spt_loop.h
    jmp     x_spt_loop.l

end_x_spt_loop:
    ; LBA = x + S - 1
    ld      block_addr_1
    st      a
    ld      ide_sector_number
    st      b
    ldi     add
    st      alu
    ld      alu
    st      block_addr_1

    ld      block_addr_2
    st      a
    ldi     0
    st      b
    ldi     adc
    st      alu
    ld      alu
    st      block_addr_2

    ld      block_addr_3
    st      a
    ld      alu
    st      block_addr_3

    ld      block_addr_4
    st      a
    ld      alu
    st      block_addr_4


    ld      block_addr_1
    st      a
    ldi     1
    st      b
    ldi     sub
    st      alu
    ld      alu
    st      block_addr_1

    ld      block_addr_2
    st      a
    ldi     0
    st      b
    ldi     sbc
    st      alu
    ld      alu
    st      block_addr_2

    ld      block_addr_3
    st      a
    ld      alu
    st      block_addr_3

    ld      block_addr_4
    st      a
    ld      alu
    st      block_addr_4

    ret


;
; Increment LBA
;
increment_lba:
    ld      block_addr_1
    st      a
    ldi     1
    st      b
    ldi     add
    st      alu
    ld      alu
    st      block_addr_1

    ld      block_addr_2
    st      a
    ldi     0
    st      b
    ldi     adc
    st      alu
    ld      alu
    st      block_addr_2

    ld      block_addr_3
    st      a
    ld      alu
    st      block_addr_3

    ld      block_addr_4
    st      a
    ld      alu
    st      block_addr_4
    ret


;
; Transmit data to System
;
transmit_data:
    ; Set data request
    ldi     0b00000001
    st      ide_data_req
    ; busy=0
    ldi     0b01111111
    st      a
    ldi     clear_ide_status_bit.h
    call    clear_ide_status_bit.l

    ldi     and
    st      alu
    ldi     0b00001000
    st      b
transmit_wait:
    ld      ide_status
    st      a
    ld      alu

    ldi     transmit_end.h
    jz      transmit_end.l

    ldi     transmit_wait.h
    jmp     transmit_wait.l

transmit_end:
    ; busy=1
    ldi     0b10000000
    st      ide_status
    ret


;
; Set status bit
; args:
;       a : set bit
;
set_status_bit:
    ld      status_flags
    st      b
    ldi     or
    st      alu
    ld      alu
    st      status_flags
    ret

;
; Clear status bit
; args:
;       a : clear bit (inverse)
;
clear_status_bit:
    ld      status_flags
    st      b
    ldi     and
    st      alu
    ld      alu
    st      status_flags
    ret

;
; Set ide status bit
; args:
;       a : set bit
;
set_ide_status_bit:
    ld      ide_status
    st      b
    ldi     or
    st      alu
    ld      alu
    st      ide_status
    ret

;
; Clear ide status bit
; args:
;       a : clear bit (inverse)
;
clear_ide_status_bit:
    ld      ide_status
    st      b
    ldi     and
    st      alu
    ld      alu
    st      ide_status
    ret

;
; Wait for SPI communication termination
;
wait_spi_comm:
    ldi     0x01
    st      b
    ld      spi_status
    st      a
    ldi     and
    st      alu
    ld      alu

    ldi     wait_spi_comm_end.h
    jz      wait_spi_comm_end.l

    ldi     wait_spi_comm.h
    jmp     wait_spi_comm.l

wait_spi_comm_end:
    ret

;
; Send Dummy clock
;
send_4_dummy_clock:
    ldi     0xFF
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l
send_3_dummy_clock:
    ldi     0xFF
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l
send_2_dummy_clock:
    ldi     0xFF
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l
send_1_dummy_clock:
    ldi     0xFF
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l
    ret


;
; Send 4 bytes 0x00 data
;
send_spi_arg_0:
    ldi     0x00
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l
    ldi     0x00
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l
    ldi     0x00
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l
    ldi     0x00
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l
    ret


;
;   Wait for R1 response
;   args:
;       reg1 : try count
;   return:
;       reg2 : response data (0xFF is error)
wait_spi_r1_response:
    ldi     0xFF
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l
    ld      spi_data
    st      reg2
    st      a
    ldi     0x80
    st      b
    ldi     and
    st      alu
    ld      alu
    ; Recieved response data
    ldi     wait_spi_r1_response_end.h
    jz      wait_spi_r1_response_end.l

    ld      reg1
    st      a
    ldi     1
    st      b
    ldi     sub
    st      alu
    ld      alu
    st      reg1
    ; Try count over
    ldi     wait_spi_r1_response_end.h
    jz      wait_spi_r1_response_end.l

    ; Retry
    ldi     wait_spi_r1_response.h
    jmp     wait_spi_r1_response.l

wait_spi_r1_response_end:
    ret


;
;    Wait to start spi transmission
;    args:
;        reg1 : try count
;        reg2 : check data
;    return:
;        reg3 : response data
;
wait_to_start_spi_transmission:
    ldi     0xFF
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l
    ld      spi_data
    st      reg3
    st      a
    ld      reg2
    st      b
    ldi     xor
    st      alu
    ld      alu
    ; Recieved response data
    ldi     wait_to_start_spi_transmission_end.h
    jz      wait_to_start_spi_transmission_end.l

    ld      reg1
    st      a
    ldi     1
    st      b
    ldi     sub
    st      alu
    ld      alu
    st      reg1
    ; Try count over
    ldi     wait_to_start_spi_transmission_end.h
    jz      wait_to_start_spi_transmission_end.l

    ; Retry
    ldi     wait_to_start_spi_transmission.h
    jmp     wait_to_start_spi_transmission.l

wait_to_start_spi_transmission_end:
    ret


;
; Send address to MMC
;
send_address:
    ; Check CCS bit
    ld      status_flags
    st      a
    ldi     0b01000000
    st      b
    ldi     and
    st      alu
    ld      alu
    ldi     send_address_legacy.h
    jz      send_address_legacy.l

send_address_block:
    ld      block_addr_4
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ld      block_addr_3
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ld      block_addr_2
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ld      block_addr_1
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ret

send_address_legacy:
    ld      block_addr_1
    st      a
    ldi     shl
    st      alu
    ld      alu
    st      reg1

    ld      block_addr_2
    st      a
    ldi     shcl
    st      alu
    ld      alu
    st      reg2

    ld      block_addr_3
    st      a
    ld      alu

    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ld      reg2
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ld      reg1
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ldi     0
    st      spi_data
    ldi     wait_spi_comm.h
    call    wait_spi_comm.l

    ret

;
; Decrement 16bit counter
;
dec_16:
    ; reg1 - 1
    ld      reg1
    st      a
    ldi     1
    st      b
    ldi     sub
    st      alu
    ld      alu
    st      reg1

    ; reg2 - !carry
    ld      reg2
    st      a
    ldi     0
    st      b
    ldi     sbc
    st      alu
    ld      alu
    st      reg2

    ret

