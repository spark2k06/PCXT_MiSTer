#============================================================
# SDIO
#============================================================
# set_location_assignment PIN_AF25 -to SDIO_DAT[0]
# set_location_assignment PIN_AF23 -to SDIO_DAT[1]
# set_location_assignment PIN_AD26 -to SDIO_DAT[2]
# set_location_assignment PIN_AF28 -to SDIO_DAT[3]
# set_location_assignment PIN_AF27 -to SDIO_CMD
# set_location_assignment PIN_AH26 -to SDIO_CLK
# set_instance_assignment -name CURRENT_STRENGTH_NEW "MAXIMUM CURRENT" -to SDIO_*

# set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SDIO_*
# set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to SDIO_DAT[*]
# set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to SDIO_CMD

#============================================================
# VGA   (from SoCkit board)
#============================================================
set_location_assignment PIN_AG5 -to VGA_R[0]
set_location_assignment PIN_AA12 -to VGA_R[1]
set_location_assignment PIN_AB12 -to VGA_R[2]
set_location_assignment PIN_AF6 -to VGA_R[3]
set_location_assignment PIN_AG6 -to VGA_R[4]
set_location_assignment PIN_AJ2 -to VGA_R[5]
set_location_assignment PIN_AH5 -to VGA_R[6]
set_location_assignment PIN_AJ1 -to VGA_R[7]

set_location_assignment PIN_Y21 -to VGA_G[0]
set_location_assignment PIN_AA25 -to VGA_G[1]
set_location_assignment PIN_AB26 -to VGA_G[2]
set_location_assignment PIN_AB22 -to VGA_G[3]
set_location_assignment PIN_AB23 -to VGA_G[4]
set_location_assignment PIN_AA24 -to VGA_G[5]
set_location_assignment PIN_AB25 -to VGA_G[6]
set_location_assignment PIN_AE27 -to VGA_G[7]

set_location_assignment PIN_AE28 -to VGA_B[0]
set_location_assignment PIN_Y23 -to VGA_B[1]
set_location_assignment PIN_Y24 -to VGA_B[2]
set_location_assignment PIN_AG28 -to VGA_B[3]
set_location_assignment PIN_AF28 -to VGA_B[4]
set_location_assignment PIN_V23 -to VGA_B[5]
set_location_assignment PIN_W24 -to VGA_B[6]
set_location_assignment PIN_AF29 -to VGA_B[7]

set_location_assignment PIN_AD12 -to VGA_HS
set_location_assignment PIN_AC12 -to VGA_VS

set_location_assignment PIN_AG2 -to VGA_SYNC_N
set_location_assignment PIN_AH3 -to VGA_BLANK_N
set_location_assignment PIN_W20 -to VGA_CLK

set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_*
set_instance_assignment -name CURRENT_STRENGTH_NEW 8MA -to VGA_*

#============================================================
# AUDIO
#============================================================
# HSMC J3 connector pin 1 HSMC_CLKIN_n1 PIN_AB27
# HSMC J3 connector pin 2 HSMC_RX _n[7] PIN_F8 
# set_location_assignment PIN_AB27 -to AUDIO_L
# set_location_assignment PIN_F8 -to AUDIO_R
# set_location_assignment PIN_AG26 -to AUDIO_SPDIF
# set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to AUDIO_*
# set_instance_assignment -name CURRENT_STRENGTH_NEW 8MA -to AUDIO_*

# Audio CODED is from SoCkit board
set_location_assignment PIN_AC27 -to AUD_ADCDAT
set_location_assignment PIN_AG30 -to AUD_ADCLRCK
set_location_assignment PIN_AE7 -to AUD_BCLK
set_location_assignment PIN_AG3 -to AUD_DACDAT
set_location_assignment PIN_AH4 -to AUD_DACLRCK
set_location_assignment PIN_AD26 -to AUD_MUTE
set_location_assignment PIN_AC9 -to AUD_XCK

set_location_assignment PIN_AH30 -to AUD_I2C_SCLK
set_location_assignment PIN_AF30 -to AUD_I2C_SDAT

set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to AUD_*


#============================================================
# I/O #1
#============================================================
# leds are from SoCkit board
set_location_assignment PIN_AE11 -to LED_USER
set_location_assignment PIN_AF10 -to LED_HDD
set_location_assignment PIN_AD10 -to LED_POWER
# buttons are from SoCkit board
set_location_assignment PIN_AD9  -to BTN_USER
set_location_assignment PIN_AD11 -to BTN_OSD
set_location_assignment PIN_AD27 -to BTN_RESET

set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to LED_*
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to BTN_*
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to BTN_*
