
// Created by David Guillen Fandos
// david@davidgf.net
// You may use it as long as you share the sources

`define CMD_RESET          5'h00  // Reset!
`define CMD_SET_OFFSET     5'h01  // Password buteforce offset (prefix length)
`define CMD_PUSH_MSG_BYTE  5'h02  // Push byte to initial message register (into LSB)
`define CMD_SEL_MSG_LEN    5'h03
`define CMD_SEL_SSID_BYTE  5'h04  // ESSID byte pos + byte + length
`define CMD_SET_SSID_BYTE  5'h05
`define CMD_SET_SSID_LEN   5'h06
`define CMD_SEL_MAP_BYTE   5'h07  // Select and set bytes in MAP (+ num entries)
`define CMD_SET_MAP_BYTE   5'h08
`define CMD_SET_MAP_LEN    5'h09
`define CMD_PUSH_MIC_BYTE  5'h0A  // MIC set
`define CMD_SET_CLK_M_VAL  5'h0B  // Set M value for core DCM
`define CMD_SET_CLK_D_VAL  5'h0C  // Set D value for core DCM and perform a frequency update

`define CMD_WR_REG_LSB     5'h0E  // Write scratch reg LS byte (pushing to left)
`define CMD_WR_REG_ADDR    5'h0F  // Write regiter value to RAM address (32 bit or 8 bit)

`define CMD_START          5'h1F  // Start! This is, stop resetting devices

// Memory map is:
// 0-127    working mem (128 words x 32 bit)
// 128-144  ucode byte memory (16 x 8 bit)


`define RESP_HIT           5'h01   // Found a hit!
`define RESP_PING          5'h02   // Ping indicating current progress (~1 per second)
`define RESP_FINISHED      5'h1F   // This cracker device is done working!


