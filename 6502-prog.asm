; ============================================================================
; APPLE II FID (FILE DEVELOPER) VERSION M
; ============================================================================
; Copyright 1979 Apple Computer Inc.
;
; Reverse engineered from 6502-prog.bin
; Binary format: 4-byte Apple II header + 4686 bytes code/data
; Load address: $0803
; Code length:  4686 bytes ($124E)
;
; PROGRAM DESCRIPTION
; ===================
; FID is Apple Computer's official disk utility for Apple II / DOS 3.3.
; It provides file management operations including:
;
;   1. COPY FILES        - Copy files between disks
;   2. CATALOG           - List files on disk
;   3. SPACE ON DISK     - Show free/used sectors
;   4. UNLOCK FILES      - Remove write protection from files
;   5. LOCK FILES        - Write-protect files
;   6. DELETE FILES      - Remove files from disk
;   7. RESET SLOT & DRIVE- Change default slot/drive
;   8. VERIFY FILES      - Check file integrity
;   9. QUIT              - Return to BASIC/DOS
;
; FID supports wildcard filenames with '=' and multi-file patterns
; separated by commas. It can prompt for confirmation on each file.
;
; ARCHITECTURE
; ============
; Entry point: $0803
;   1. init_system      - Validate DOS version, set text mode
;   2. show_main_menu   - Display banner + 9 options, get selection
;   3. setup_operation   - Configure slot/drive/filename for operation
;   4. process_files     - Read catalog, apply operation to matching files
;   5. Loop back to menu
;
; String display uses an indexed pointer table at $13E8 (49 entries).
; Menu dispatch uses the RTS trick via a jump table at $13CA.
;
; MEMORY MAP
; ==========
; ZERO-PAGE ($00-$FF):
;   $00-$01    FM_PARAM    - File Manager parameter list (low/high bytes)
;   $02-$03    RWTS_PARAM  - RWTS parameter list (low/high bytes)
;   $22        WNDLFT      - Text window left margin (usually 0)
;   $24        CH          - Cursor horizontal position (column 0-39)
;   $25        CV          - Cursor vertical position (row 0-23)
;   $33        PROMPT      - Prompt character ($80 for inverse, $3D for '>')
;   $76        HGRPAGE     - Hi-res page select ($00=page 1, $80=page 2)
;   $D9        ORONE       - Output OR mask ($80 for inverse text display)
;
; MAIN MEMORY:
;   $0200-$02FF  Input buffer (GETLN reads keyboard input here)
;   $0803-$1315  Program code (4883 bytes = $1312 bytes)
;   $1316-$1A50  Data section: variables, tables, strings, DOS params
;                Subdivisions:
;                  $1318-$1325  Initialized variables (track, sector, etc.)
;                  $1326-$134A  Catalog display format template
;                  $134B-$1373  Filename prompt format template
;                  $1374-$1391  Filename backup buffer
;                  $1392-$13AE  Working variables (matching, file processing)
;                  $13AF-$13B8  Menu selection characters table
;                  $13B9-$13C9  Input validation sub-tables
;                  $13CA-$13DB  RTS dispatch table (menu handlers)
;                  $13DC-$13E7  DOS parameter block pointers
;                  $13E8-$1449  String pointer table (49 entries)
;                  $144A-$18F8  ASCII text strings (Apple II encoded)
;                  $18F9-$1A50  DOS file manager / RWTS parameter blocks
;   $1B51-$1C5D  Working buffers (T/S lists, sector data) - runtime only
;
; DOS 3.3 ROM ROUTINES
; ====================
; $03D2  DOS_VERSION     - DOS version byte ($25 = DOS 3.3, $26 = 3.3.1)
; $03D3  DOS_WARM_START  - Return to BASIC/DOS prompt
; $03D6  DOS_FM_CALL     - File manager entry point
; $03D9  DOS_FM_ALT      - File manager alternate entry point
; $03DC  DOS_GET_FM      - Get file manager parameter list address → A,Y
; $03E3  DOS_GET_RWTS    - Get RWTS parameter list address → A,Y
;
; APPLE II MONITOR ROM ROUTINES
; ==============================
; $FBC1  BASCALC - Calculate text screen base address from CV ($25)
; $FC1A  VTAB    - Vertical tab to row in A register
; $FC58  HOME    - Clear screen and move cursor to top-left
; $FC62  CLREOL  - Clear to end of line
; $FC66  CLREOP  - Clear to end of page
; $FD0C  RDKEY   - Read one keypress (blocking, returns in A)
; $FD6F  GETLN   - Read line into $0200, returns length in X
; $FD8E  CROUT   - Output carriage return (newline)
; $FDDA  PRBYTE  - Print A register as 2-digit hexadecimal
; $FDED  COUT    - Output character in A register
; $FF3A  BELL    - Ring bell (beep sound)
;
; ROUND-TRIP VERIFICATION
; =======================
; This assembly source produces a binary that is byte-for-byte
; identical to the original 6502-prog.bin (minus the 4-byte header).
; Verify with:
;   python3 py6502/cli_asm6502.py 6502-prog_semantic.asm \
;       -b /tmp/test.bin --compare 6502-prog_noheader.bin
;
; ============================================================================
org $0803

; ============================================================================
; MACRO DEFINITIONS
; ============================================================================
.macro apple2_str = py6502.macros_examples.apple2_str

; ============================================================================
; EQUATES: Program Constants, Zero-Page & Memory Addresses
; ============================================================================
; These are for reference and documentation only. The code continues to use
; literal addresses for strict byte-for-byte compatibility.
;
; DOS Zero-Page Pointers (set up by setup_disk_params)
FM_PARAM_LO     = $00           ; File Manager parameter list (low byte)
FM_PARAM_HI     = $01           ; File Manager parameter list (high byte)
RWTS_PARAM_LO   = $02           ; RWTS parameter list (low byte)
RWTS_PARAM_HI   = $03           ; RWTS parameter list (high byte)

; Apple II Monitor Zero-Page Variables (standard locations)
WNDLFT          = $22           ; Text window left margin
CH              = $24           ; Cursor horizontal position (column)
CV              = $25           ; Cursor vertical position (row)
PROMPT          = $33           ; Prompt character
HGRPAGE         = $76           ; Hi-res page select (0=page 1, 1=page 2)
ORONE           = $D9           ; Output OR mask (for inverse/normal text)

; Input Buffer (used by GETLN to read keyboard input)
KEYBUF          = $0200         ; Input buffer, 256 bytes max

; ============================================================================
; FID PROGRAM VARIABLES (DATA SECTION at $1318-$13AE)
; ============================================================================
; Disk and file parameters used throughout the program

; Disk Drive Configuration
CURRENT_TRACK   = $1318         ; Current track in T/S list
CURRENT_SECTOR  = $1319         ; Current sector in T/S list
ERROR_FLAG      = $131A         ; Error flag (0=OK, $FF=error)
ERROR_CODE      = $131B         ; Error code number
SAVED_SP        = $131C         ; Saved stack pointer

DRIVE_DEST      = $131D         ; Destination disk drive (1-2)
DRIVE_SOURCE    = $131E         ; Source disk drive (1-2)
SLOT_DEST       = $131F         ; Destination slot (1-7)
SLOT_SOURCE     = $1320         ; Source slot (1-7)
SLOT_DEST_SFT   = $1321         ; Destination slot × 16 (for DOS)
SLOT_SOURCE_SFT = $1322         ; Source slot × 16 (for DOS)
SAME_DISK_FLAG  = $1323         ; $FF if source and destination are same

FILE_TYPE       = $1324         ; File type from catalog
FILE_STATUS     = $1325         ; File status/protection flags

; Catalog Reading & File Enumeration
BITMAP_COL      = $1392         ; Bitmap display column offset
FILE_INDEX      = $1393         ; Current file index in catalog
FILE_COUNT      = $1394         ; File count or operation status
FREE_SECT_LOW   = $1395         ; Free sectors (BCD, low digit)
FREE_SECT_HIGH  = $1396         ; Free sectors (BCD, high digit)
USED_SECT_LOW   = $1397         ; Used sectors (BCD, low digit)
USED_SECT_HIGH  = $1398         ; Used sectors (BCD, high digit)

; Filename Pattern Matching (wildcard support with '=')
SAVED_TRACK     = $1399         ; Saved track number
SAVED_TRACK_CP  = $139A         ; Copy of saved track
SAVED_SECTOR    = $139B         ; Saved sector number
SAVED_SECTOR_CP = $139C         ; Copy of saved sector
TS_LIST_POS     = $139D         ; T/S list array position
TS_LIST_MAX     = $139E         ; T/S list array max index
CATALOG_REMAIN  = $139F         ; Catalog entries remaining

MATCH_START     = $13A0         ; Filename match start position
MATCH_END       = $13A1         ; Filename match end position
FILENAME_END    = $13A2         ; Filename end position
FWD_MATCH_POS   = $13A3         ; Forward match position
SAVED_FWD_POS   = $13A4         ; Saved forward match position
FWD_CATALOG_POS = $13A5         ; Forward catalog match position
REV_CATALOG_POS = $13A6         ; Reverse catalog match position
SAVED_CAT_POS   = $13A7         ; Saved catalog position
MATCH_RESULT    = $13A8         ; Match result flags
HAS_WILDCARD    = $13A9         ; Non-0 if '=' wildcard present
PROMPT_MODE     = $13AA         ; 0=batch, non-0=prompt for each file
FILE_SELECTED   = $13AB         ; Non-0 if files were selected

; User Menu & Selection Control
MENU_CHAR       = $13AC         ; Selected menu character ('1'-'9')
OPERATION_MODE  = $13AD         ; Operation mode (0/1/2)
MENU_INDEX      = $13AE         ; Menu selection index (0-8)

; Menu Option Tables
MENU_CHARS      = $13AF         ; "123456789" - valid selections
NO_DISK_OPTIONS = $13B9         ; Options needing no disk init
FILE_OPS        = $13BC         ; File operation options
COPY_OPTION     = $13C3         ; Copy-only option
ALT_PATH_OPS    = $13C5         ; Alt-path operation options

; Dispatch Table
MENU_DISPATCH   = $13CA         ; 9 entries, (addr-1) for RTS trick

; String Pointer Table
STRING_TABLE    = $13E8         ; 49 word pointers to strings

; ============================================================================
; DOS 3.3 ROM ENTRY POINTS (Apple II Standard)
; ============================================================================
DOS_VERSION     = $03D2         ; Version byte ($25 = DOS 3.3)
DOS_WARM_START  = $03D3         ; Return to BASIC/DOS
DOS_FM_CALL     = $03D6         ; File manager call
DOS_FM_ALT      = $03D9         ; File manager alternate entry
DOS_GET_FM      = $03DC         ; Get FM parameter list address → A,Y
DOS_GET_RWTS    = $03E3         ; Get RWTS parameter list address → A,Y

; ============================================================================
; APPLE II MONITOR ROM ROUTINES (Firmware)
; ============================================================================
BASCALC         = $FBC1         ; Calculate text screen base from CV
VTAB            = $FC1A         ; Vertical tab to row in A
HOME            = $FC58         ; Clear screen, cursor to top-left
RDKEY           = $FD0C         ; Read one keypress (blocking)
GETLN           = $FD6F         ; Read line into $0200, X=length
CROUT           = $FD8E         ; Output carriage return
PRBYTE          = $FDDA         ; Print A register as 2-digit hex
COUT            = $FDED         ; Output character in A
BELL            = $FF3A         ; Ring bell (beep)

; ============================================================================
; PROGRAM DATA BLOCKS (loaded from disk)
; ============================================================================
FILE_MGR_PARAMS = $18F9         ; DOS file manager parameter block
RWTS_PARAMS     = $18F9         ; RWTS parameter block (shared space with FM)

; ============================================================================

; MAIN PROGRAM ENTRY POINT
; ============================================
; Initialization sequence:
; 1. Initialize graphics system
; 2. Set initial state variables
; 3. Enter main event loop
;

 jsr  init_system
 sta  $1394
 lda  #$00
 sta  $13ad
main_loop:
 tsx
 stx  $131c
 jsr  show_main_menu
 jsr  setup_operation
 lda  $13ac
 ldx  #$16
 jsr  find_in_table
 bne  +$09
 jsr  setup_disk_params
 jsr  $0d59
 jmp  loop_back
loc_082b:
 jsr  get_filename
 jsr  setup_disk_params
 jsr  process_files
 lda  $13ab
 bne  +$05
 ldx  #$0f
 jsr  print_string
loop_back:
 jsr  press_any_key
 jmp  main_loop

; ============================================
; SUBROUTINE at $0844
; Called from: $0803
; ============================================
;

; ============================================================================
; SUBROUTINE: init_system ($0844)
; ============================================================================
; Initialize the Apple II system for FID operation.
; - Sets hi-res page, output OR-mask, and prompt character to $80
; - Checks DOS version (must be 3.2 or 3.3)
; - If incompatible, prints error and returns to DOS
; ============================================================================

init_system:
; Subroutine called 1 time(s) from: $0803
; Initialize Apple II system and validate DOS version.
; Sets graphics mode, output masks, and prompt character.
; Checks if DOS 3.2 or 3.3 is running.
; If DOS version is invalid, displays error and returns to DOS.

 lda  #$80               ; Load prompt/output flags
 sta  $76                ; Set HGRPAGE (hi-res page) to $80
 sta  $d9                ; Set ORONE (output OR mask) for inverse text
 sta  $33                ; Set PROMPT character to $80

 sec                     ; Set carry flag
 lda  $03d2              ; Load DOS version byte ($25 for DOS 3.3)
 sbc  #$07               ; Subtract $07: if DOS 3.3, result is $1E
 sbc  #$1e               ; Subtract $1E: if DOS 3.3, result is 0, sets Z flag
 bmi  +$01               ; If result < 0 (invalid DOS), skip RTS and error
 rts                     ; Return if DOS version valid

loc_0857:
; DOS version check failed - display error and exit
 jsr  $fc58              ; HOME: clear screen, cursor to top-left
 ldx  #$15              ; String index 21: "INSUFFICIENT MEMORY..."
 jsr  print_string       ; Display error message
 jmp  $03d3              ; DOS_WARM_START: return to BASIC

; ============================================
; SUBROUTINE at $0862
; Called from: $0822, $082e
; ============================================
;

; ============================================================================
; SUBROUTINE: setup_disk_params ($0862)
; ============================================================================
; Prepare DOS file manager and RWTS parameter lists for disk access.
;
; Tasks:
;   1. Shift slot numbers left 4 bits (multiply by 16)
;      Slot bits go into high nibble for DOS disk access
;   2. Call DOS to get file manager parameter list address
;      Returns address in A (high) / Y (low) → store in $00-$01
;   3. Call DOS to get RWTS parameter list address
;      Returns address in A (high) / Y (low) → store in $02-$03
;   4. Initialize track/sector list and file manager parameters
;   5. Clear the file-selected flag
; ============================================================================

setup_disk_params:
; Subroutine called 2 time(s) from: $0822, $082e
 ldx  #$01               ; Start with X = 1
loc_0864:
; Shift slot numbers left 4 bits (multiply by 16)
; Loop: X counts down from 1 to 0 (process 2 slots)
; $131F is source slot, $1320 is destination slot
 lda  $131f,x            ; Load slot from ($131F,X)
 asl  A                  ; Multiply by 2
 asl  A                  ; Multiply by 4
 asl  A                  ; Multiply by 8
 asl  A                  ; Multiply by 16
 sta  $1321,x            ; Store shifted slot to ($1321,X)
 dex                     ; Decrement X
 bpl  -$0d               ; Loop if positive (X=1,0)

; Get DOS file manager parameter list address
 jsr  $03dc              ; DOS: Get FM parameter list → A,Y
 sty  $00                ; Store low byte to $00 (FM_PARAM_LO)
 sta  $01                ; Store high byte to $01 (FM_PARAM_HI)

; Get DOS RWTS parameter list address
 jsr  $03e3              ; DOS: Get RWTS parameter list → A,Y
 sty  $02                ; Store low byte to $02 (RWTS_PARAM_LO)
 sta  $03                ; Store high byte to $03 (RWTS_PARAM_HI)

; Initialize track/sector list and FM parameters
 jsr  $102d              ; Initialize T/S list (probably in DOS ROM)
 jsr  $0fe8              ; Initialize FM parameters (probably in DOS ROM)

; Clear file selection flag
 lda  #$00               ; Load zero
 sta  $13ab              ; Clear file-selected flag ($13AB)
 rts                     ; Return

; ============================================
; SUBROUTINE at $088B
; Called from: $0812
; ============================================
;

; ============================================================================
; SUBROUTINE: show_main_menu ($088B)
; ============================================================================
; Display the main FID menu and get user's selection.
; - Clears screen, prints banner and copyright
; - Displays 9 menu options (COPY, CATALOG, SPACE, etc.)
; - Reads user input and validates against menu_options table
; - Stores selection character in $13AC, index in $13AE
; ============================================================================
; SUBROUTINE: show_main_menu ($088B)
; ============================================================================
; Display FID main menu and get user selection.
; 1. Clear screen and print banner/copyright strings
; 2. Loop through 9 menu options, displaying each option number and text
; 3. Display menu prompt
; 4. Read user input and validate against valid menu options
; 5. Store selected character and index
; ============================================================================

show_main_menu:
; Subroutine called 1 time(s) from: $0812

 lda  #$00               ; Clear A
 sta  $22                ; WNDLFT = 0 (reset text window to left margin)
 jsr  $fc58              ; HOME: clear screen, cursor to top-left

 ldx  #$16              ; String index 22: FID banner (top half)
 jsr  print_string       ; Print banner decorative line
 ldx  #$17              ; String index 23: FID banner (bottom) + menu intro
 jsr  print_string       ; Print copyright and "CHOOSE ONE..."
 jsr  $fd8e              ; CROUT: output carriage return (newline)

; Display menu options loop (Y counts 0-8 for 9 options)
 ldy  #$00              ; Y = 0 (menu option counter)
loc_08a1:
 ldx  #$1f              ; String index 31: "        <" (spacing)
 jsr  print_string       ; Print left-side spacing

 lda  $13af,y            ; Load menu character from "123456789" table
 jsr  $fded              ; COUT: output character (print menu number)

 ldx  #$20              ; String index 32: ">   " (right bracket + spacing)
 jsr  print_string       ; Print right-side spacing

 tya                     ; Transfer Y (option index 0-8) to A
 clc                     ; Clear carry
 adc  #$28               ; Add $28 (40 decimal, offset to option names)
 tax                     ; Transfer to X (now X = 40-48 for string indices)
 jsr  print_string       ; Print option name (COPY FILES, CATALOG, etc.)

 iny                     ; Increment option counter
 cpy  #$09              ; Compare with 9 (we have options 0-8)
 bne  -$1d               ; Loop back if not done

; Display prompt and read user selection
 jsr  $fd8e              ; CROUT: output carriage return (newline)
 ldx  #$21              ; String index 33: "WHICH WOULD YOU LIKE?"
 jsr  print_string       ; Display prompt

 jsr  $fd6f              ; GETLN: read user input line, returns in $0200
 lda  $0200              ; Load first character of input
 ldx  #$00              ; Start search from offset 0
 jsr  find_in_table      ; Search for character in menu option table
 bne  -$48               ; If not found (A != 0), loop back to prompt again

; Valid selection found
 sta  $13ac              ; MENU_CHAR: store selected character
 sty  $13ae              ; MENU_INDEX: store option index (0-8)
 rts                     ; Return to main loop

; ============================================
; SUBROUTINE at $08DA
; Called from: $0815
; ============================================
;

; ============================================================================
; SUBROUTINE: setup_operation ($08DA)
; ============================================================================
; Configure the selected file operation.
; - Clears screen, shows operation name
; - For CATALOG/RESET/SPACE/QUIT: no disk init needed
; - For file operations (DELETE/LOCK/etc.): prompts for slot/drive
; - For COPY: prompts for source and destination slot/drive
; ============================================================================

setup_operation:
; Subroutine called 1 time(s) from: $0815
 jsr  $fc58              ; HOME: clear screen, cursor to top-left
 lda  #$0f              ; Load cursor column 15
 sta  $24                ; Set CH (horizontal position) for operation name
 lda  $13ae              ; Load menu option index (0-8)
 clc                     ; Clear carry
 adc  #$28               ; Add 40 (offset to operation name strings)
 tax                     ; Transfer to X for string index
 jsr  print_string       ; Display operation name
 lda  #$03              ; Load window left margin
 sta  $22                ; Set WNDLFT for setup prompts
 jsr  $fc58              ; HOME: clear screen again
 lda  $13ac              ; Load operation selection character
 ldx  #$0a              ; Check if operation needs NO disk setup
 jsr  find_in_table      ; Search in no-setup-needed list
 bne  +$07               ; If found, skip disk setup
 lda  #$00               ; Load 0 (no setup flag)
 sta  $13ad              ; Store setup state
 beq  +$37               ; Branch to return
loc_0903:
 ldx  #$0d              ; Check if COPY operation
 jsr  find_in_table      ; Search for COPY character
 bne  +$20               ; If not COPY, handle single-disk ops
 lda  #$01               ; State 1: getting source disk
 cmp  $13ad              ; Compare with setup state
 beq  +$29               ; If already set, continue
 sta  $13ad              ; Store state 1
 jsr  get_slot_drive     ; Get source disk parameters
 lda  #$00               ; Load 0 (different disks)
 sta  $1323              ; Clear SAME_DISK_FLAG
 lda  $131e              ; Load source drive
 sta  $131d              ; Store as dest drive (temporary)
 lda  $1320              ; Load source slot
 sta  $131f              ; Store as dest slot (temporary)
 bne  +$10               ; Branch to get destination
loc_092a:
 lda  #$02               ; State 2: getting destination disk
 cmp  $13ad              ; Compare with setup state
 beq  +$09               ; If already set, continue
 sta  $13ad              ; Store state 2
 jsr  get_slot_drive     ; Prompt for source disk
 jsr  get_dest_slot_drive; Prompt for destination disk
loc_093a:
 rts                     ; Return to caller

; ============================================
; SUBROUTINE at $093B
; Called from: $0914, $0934
; ============================================
;

; ============================================================================
; SUBROUTINE: get_slot_drive ($093B)
; ============================================================================
; Prompt user for source slot (1-7) and drive (1-2).
; Validates input, beeps on invalid entry.
; Stores slot in $1320, drive in $131E.
; ============================================================================

get_slot_drive:
; Subroutine called 2 time(s) from: $0914, $0934
 ldx  #$00               ; String index 0: "SLOT #1-7?" prompt
 jsr  print_string       ; Display slot prompt
 jsr  $fd6f              ; GETLN: read user input
 cpx  #$01               ; Check if exactly 1 character
 bne  +$0b               ; If not, invalid
 lda  $0200              ; Load input character
 cmp  #$b1               ; Compare with ASCII '1' ($B1)
 bcc  +$04               ; If less, invalid
 cmp  #$b8               ; Compare with ASCII '8' ($B8)
 bcc  +$08               ; If less, valid range (1-7)
loc_0952:
 ldx  #$22               ; String index 34: "INVALID SLOT" error
 jsr  beep_and_print     ; Ring bell and display error
 jmp  get_slot_drive     ; Retry slot input
loc_095a:
 and  #$07               ; Mask to extract slot number (1-7)
 sta  $1320              ; Store in SOURCE_SLOT
loc_095f:
 ldx  #$01               ; String index 1: "DRIVE #1-2?" prompt
 jsr  print_string       ; Display drive prompt
 jsr  $fd6f              ; GETLN: read user input
 cpx  #$01               ; Check if exactly 1 character
 bne  +$0b               ; If not, invalid
 lda  $0200              ; Load input character
 cmp  #$b1               ; Compare with ASCII '1' ($B1)
 bcc  +$04               ; If less, invalid
 cmp  #$b3               ; Compare with ASCII '3' ($B3)
 bcc  +$08               ; If less, valid range (1-2)
loc_0976:
 ldx  #$23               ; String index 35: "INVALID DRIVE" error
 jsr  beep_and_print     ; Ring bell and display error
 jmp  loc_095f           ; Retry drive input
loc_097e:
 and  #$07               ; Mask to extract drive number (1-2)
 sta  $131e              ; Store in SOURCE_DRIVE
 rts                     ; Return with slot/drive validated

; ============================================
; SUBROUTINE at $0984
; Called from: $0937
; ============================================
;

; ============================================================================
; SUBROUTINE: get_dest_slot_drive ($0984)
; ============================================================================
; Prompt user for destination slot (1-7) and drive (1-2).
; Also checks if source == destination (same-disk flag at $1323).
; Stores slot in $131F, drive in $131D.
; ============================================================================

get_dest_slot_drive:
; Subroutine called 1 time(s) from: $0937
 jsr  $fd8e
loc_0987:
 ldx  #$02
 jsr  print_string
 jsr  $fd6f
 cpx  #$01
 bne  +$0b
 lda  $0200
 cmp  #$b1
 bcc  +$04
 cmp  #$b8
 bcc  +$08
loc_099e:
 ldx  #$22
 jsr  beep_and_print
 jmp  loc_0987
loc_09a6:
 and  #$07
 sta  $131f
loc_09ab:
 ldx  #$03
 jsr  print_string
 jsr  $fd6f
 cpx  #$01
 bne  +$0b
 lda  $0200
 cmp  #$b1
 bcc  +$04
 cmp  #$b3
 bcc  +$08
loc_09c2:
 ldx  #$23
 jsr  beep_and_print
 jmp  loc_09ab
loc_09ca:
 and  #$07
 sta  $131d
 cmp  $131e
 bne  +$0f
 lda  $131f
 cmp  $1320
 bne  +$07
 lda  #$ff
 sta  $1323
 bne  +$05
loc_09e3:
 lda  #$00
 sta  $1323
loc_09e8:
 rts
loc_09e9:
 ldx  #$14
 jsr  beep_and_print
 jmp  loc_09fa

; ============================================
; SUBROUTINE at $09F1
; Called from: $082b
; ============================================
;

; ============================================================================
; SUBROUTINE: get_filename ($09F1)
; ============================================================================
; Prompt user for filename pattern.
; - Accepts up to 30 characters
; - Supports '=' wildcard and ',' separator
; - Validates first character is A-Z or '='
; - If prompting mode is on, asks Y/N for each matched file
; - Pressing ESC returns to main menu
; ============================================================================

get_filename:
; Subroutine called 1 time(s) from: $082b
 jsr  $fd8e
 jsr  $fd8e
 jsr  $fd8e
loc_09fa:
 lda  #$a0
 ldx  #$1d
loc_09fe:
 sta  $1355,x
 dex
 bpl  -$06
 ldx  #$04
 jsr  print_string
 jsr  $fd6f
 dex
 bmi  -$26
 cpx  #$1e
 bcc  +$02
 ldx  #$1d
loc_0a15:
 inx
loc_0a16:
 dex
 bmi  -$30
 lda  #$a0
 cmp  $0200,x
 beq  -$0a
 inx
 stx  $13a2
 ldy  #$ff
loc_0a26:
 iny
 cmp  $0200,y
 beq  -$06
 lda  #$00
 sta  $13a9
 sta  $13aa
 lda  $0200,y
 cmp  #$bd
 beq  +$08
 cmp  #$c0
 bcc  -$56
 cmp  #$e0
 bcs  -$5a
loc_0a43:
 ldx  #$00
loc_0a45:
 lda  $0200,y
 cmp  #$ac
 beq  -$63
 sta  $1355,x
 cmp  #$bd
 bne  +$05
 lda  #$ff
 sta  $13a9
loc_0a58:
 inx
 iny
 cpy  $13a2
 bcc  -$1a
 dex
 stx  $13a1
 ldx  #$00
 stx  $13a0
 lda  $13a9
 beq  +$21
loc_0a6d:
 ldx  #$0d
 jsr  print_string
 jsr  $fd6f
 lda  $0200
 cmp  #$ce
 beq  +$12
 cmp  #$d9
 beq  +$09
 jsr  $ff3a
 jsr  $fc1a
 jmp  loc_0a6d
loc_0a89:
 lda  #$ff
 sta  $13aa
loc_0a8e:
 ldx  #$05
 jsr  print_string
 jsr  $fd0c
 cmp  #$9b
 bne  +$05
 pla
 pla
 jmp  main_loop
loc_0a9f:
 lda  $25
 pha
 lda  #$01
 sta  $25
 jsr  $fbc1
 ldx  #$0a
 jsr  print_string
 pla
 sta  $25
 jsr  $fbc1
 rts

; ============================================
; SUBROUTINE at $0AB5
; Called from: $0b45, $0b6a
; ============================================
;

; ============================================================================
; SUBROUTINE: wait_key_cr ($0AB5)
; ============================================================================
; Print "INSERT SOURCE DISK..." prompt, wait for keypress, then CR.
; ============================================================================

wait_key_cr:
; Subroutine called 3 time(s) from: $0b45, $0b6a, $0e7f
 ldx  #$0b
 jsr  print_string
 jsr  $fd0c
 jsr  $fd8e
 rts

; ============================================
; SUBROUTINE at $0AC1
; Called from: $0e71, $0e8a
; ============================================
;

; ============================================================================
; SUBROUTINE: wait_key_cr2 ($0AC1)
; ============================================================================
; Print "INSERT DESTINATION DISK..." prompt, wait for keypress, then CR.
; ============================================================================

wait_key_cr2:
; Subroutine called 2 time(s) from: $0e71, $0e8a
 ldx  #$0c
 jsr  print_string
 jsr  $fd0c
 jsr  $fd8e
 rts

; ============================================
; SUBROUTINE at $0ACD
; Called from: $083b, $085c
; ============================================
;

; ============================================================================
; SUBROUTINE: print_string ($0ACD)
; ============================================================================
; Print a null-terminated Apple II string by index.
;
; ============================================================================
; SUBROUTINE: print_string ($0ACD)
; ============================================================================
; Print a null-terminated Apple II string from the string table.
;
; Entry:  X = string index (0-48)
; Exit:   String printed via COUT; registers unchanged
; Uses:   $04-$05 as pointer to current string
;
; Implementation:
;   1. Save all registers (A, X, Y)
;   2. Multiply X by 2 (strings are 16-bit word pointers)
;   3. Load pointer from STRING_TABLE ($13E8 + 2*index)
;   4. Store pointer in $04-$05 (zero-page pointer)
;   5. Loop through string, outputting each character via COUT
;   6. Stop at null terminator ($00)
;   7. Restore all registers and return
; ============================================================================

print_string:
; Subroutine called 43 time(s) from: $083b, $085c, $0894
 pha                     ; Save A register
 tya                     ; Transfer Y to A
 pha                     ; Save Y register
 txa                     ; Transfer X to A
 pha                     ; Save X register (string index)

; Convert string index to byte offset (X * 2)
 asl  A                  ; Multiply X by 2 (strings are word pointers)
 tax                     ; Transfer to X (now X = 2 * index)

; Load pointer to string from pointer table
 lda  $13e8,x            ; Load low byte of pointer from STRING_TABLE
 sta  $04                ; Store in $04 (pointer low byte)
 lda  $13e9,x            ; Load high byte of pointer from STRING_TABLE+1
 sta  $05                ; Store in $05 (pointer high byte)

; Print string loop
 ldy  #$00               ; Initialize Y = 0 (string offset)
loc_0ae0:
 lda  ($04),y            ; Load character from string at ($04),Y
 beq  +$06               ; If zero (end of string), skip to cleanup
 jsr  $fded              ; COUT: output character in A
 iny                     ; Increment string offset
 bne  -$0a               ; Loop if Y hasn't wrapped (max 256 chars)

; Restore registers and return
loc_0aea:
 pla                     ; Restore X register
 tax                     ; Transfer to X
 pla                     ; Restore Y register
 tay                     ; Transfer to Y
 pla                     ; Restore A register
 rts                     ; Return to caller

; ============================================
; SUBROUTINE at $0AF0
; Called from: $0954, $0978
; ============================================
;

; ============================================================================
; SUBROUTINE: beep_and_print ($0AF0)
; ============================================================================
; Sound the bell, print a string, pause briefly, then clear the line.
; Used for transient error/warning messages.
;
; Entry: X = string index
; ============================================================================

beep_and_print:
; Subroutine called 6 time(s) from: $0954, $0978, $09a0
 pha
 txa
 pha
 tya
 pha
 jsr  $ff3a
 jsr  print_string
 ldy  #$ff
loc_0afd:
 ldx  #$ff
loc_0aff:
 dex
 bne  -$03
 dey
 bne  -$08
 sty  $24
 lda  #$a0
 ldx  #$27
loc_0b0b:
 jsr  $fded
 dex
 bpl  -$06
 jsr  $fc1a
 jsr  $fc1a
 pla
 tay
 pla
 tax
 pla
 rts

; ============================================
; SUBROUTINE at $0B1D
; Called from: $083e, $1312
; ============================================
;

; ============================================================================
; SUBROUTINE: press_any_key ($0B1D)
; ============================================================================
; Clear keyboard strobe, print "PRESS ANY KEY TO CONTINUE",
; wait for keypress, then CR.
; ============================================================================

press_any_key:
; Subroutine called 2 time(s) from: $083e, $1312
 bit  $c010
 ldx  #$18
 jsr  print_string
 jsr  $fd0c
 jsr  $fd8e
 rts

; ============================================
; SUBROUTINE at $0B2C
; Called from: $081d, $08ce
; ============================================
;

; ============================================================================
; SUBROUTINE: find_in_table ($0B2C)
; ============================================================================
; Search for character A in a null-terminated table starting at $13AF+X.
;
; Entry: A = character to find, X = offset from $13AF
; Exit:  Z=1 if found (Y = position), Z=0 if not found
;
; Used to validate menu selections against different option groups:
;   X=$00: "123456789"  (all valid menu options)
;   X=$0A: "79"         (RESET SLOT, QUIT - no disk init)
;   X=$0D: "625348"     (file ops - DELETE,CATALOG,LOCK,SPACE,UNLOCK,VERIFY)
;   X=$14: "1"          (COPY only)
;   X=$16: "2739"       (CATALOG,RESET,SPACE,QUIT - alt path)
;
; ============================================================================
; SUBROUTINE: find_in_table ($0B2C)
; ============================================================================
; Search for a character in a null-terminated string table.
;
; Entry:  A = character to search for
;         X = offset to start of table (base address $13AF + X)
; Exit:   If found: Z=1 (sets Z flag), Y=index of character in table
;         If not found: Z=0 (clears Z flag)
;
; Algorithm:
; 1. Initialize Y = -1 (will be incremented before first comparison)
; 2. Decrement X by 1 (will be incremented before first comparison)
; 3. Loop:
;    - Increment X (table index)
;    - Increment Y (character count)
;    - Save A (character to search) on stack
;    - Load byte from table ($13AF,X)
;    - If byte is zero (end of table), not found - clean stack and return
;    - Restore A (character to search)
;    - Compare A with byte from table
;    - If not equal, loop back to try next byte
;    - If equal, found! Return with Z=1 and Y=index
;
; Note: Table searches for menu selection in different sub-tables:
;       - Offset $00: all valid menu selections "123456789"
;       - Offset $0A: no-disk-init options "79"
;       - Offset $0D: file operations "625348"
;       - Offset $14: copy-only operation "1"
;       - Offset $16: alternate-path operations "2739"
; ============================================================================

find_in_table:
; Subroutine called 4 time(s) from: $081d, $08ce, $08f7
; Search for character in null-terminated table at base + offset

 ldy  #$ff               ; Initialize Y = -1 (counter for found position)
 dex                     ; Pre-decrement X (will be incremented in loop)

loc_0b2f:
 inx                     ; Increment X (table offset)
 iny                     ; Increment Y (character index counter)
 pha                     ; Push A (save character to search)
 lda  $13af,x            ; Load byte from table at ($13AF + X)
 beq  +$07               ; If zero (end of table), branch to not-found
 pla                     ; Pop A (restore character to search)
 cmp  $13af,x            ; Compare A with byte from table
 bne  -$0e               ; If not equal, loop back to next byte

 rts                     ; Return (Z flag = 1, found! Y = index)

loc_0b3e:
; Character not found in table
 pla                     ; Pop A (clean up stack)
 rts                     ; Return (Z flag = 0, not found)

; ============================================
; SUBROUTINE at $0B40
; Called from: $0831
; ============================================
;

; ============================================================================
; SUBROUTINE: process_files ($0B40)
; ============================================================================
; Main file processing loop.
; - Reads catalog sectors from disk
; - For each file entry, calls the selected operation handler
; - Handles multi-sector catalog traversal
; - Checks for same-disk copy (prompts for disk swap)
; ============================================================================

process_files:
; Subroutine called 1 time(s) from: $0831
 lda  $1323              ; Load SAME_DISK_FLAG
 beq  +$03               ; If 0, skip wait prompt
 jsr  wait_key_cr        ; If same disk, wait for source disk
loc_0b48:
 jsr  init_catalog_read  ; Load first catalog sector
loc_0b4b:
 ldy  $139f              ; Load entries remaining counter
 cpy  #$00               ; Check if zero
 bne  +$06               ; If entries remain, skip sector check
 jsr  check_more_sectors ; Check for more catalog sectors
 bcc  +$01               ; If carry clear (more sectors), continue
 rts                     ; If carry set (done), return
loc_0b58:
 jsr  process_catalog_entry; Process catalog entry
 bcc  -$12               ; If carry clear, loop back
 jsr  $0d59              ; Update disk
 lda  $13a9              ; Load HAS_WILDCARD flag
 beq  +$0b               ; If no wildcard, skip same-disk check
 lda  $1323              ; Load SAME_DISK_FLAG
 beq  -$1f               ; If different disks, loop back
 jsr  wait_key_cr        ; If same disk, wait for disk swap
 jmp  loc_0b4b           ; Loop back to process more entries
loc_0b70:
 rts                     ; Return to caller

; ============================================
; SUBROUTINE at $0B71
; Called from: $0b48
; ============================================
;

; ============================================================================
; SUBROUTINE: init_catalog_read ($0B71)
; ============================================================================
; Initialize catalog reading by loading the first catalog sector.
; Sets up buffer pointers and clears the catalog entry counter.
; ============================================================================

init_catalog_read:
; Subroutine called 1 time(s) from: $0b48
 ldy  #$01               ; Load Y=1 (catalog sector index)
 ldx  #$01               ; Load X=1 (read buffer 1)
 jsr  $1185              ; DOS: read sector into buffer
 lda  $1952              ; Load sector size low byte
 sta  $1a52              ; Store working copy
 lda  $1953              ; Load sector size high byte
 sta  $1a53              ; Store working copy
 lda  #$00               ; Load 0
 sta  $139f              ; Clear entries remaining counter
 rts                     ; Return with buffer ready

; ============================================
; SUBROUTINE at $0B8A
; Called from: $0b52
; ============================================
;

; ============================================================================
; SUBROUTINE: check_more_sectors ($0B8A)
; ============================================================================
; Check if there are more catalog sectors to process.
; Follows the track/sector chain from the current catalog sector.
;
; Exit: C=1 if no more sectors, C=0 if more to process
; ============================================================================

check_more_sectors:
; Subroutine called 1 time(s) from: $0b52
 lda  $1a52
 ora  $1a53
 bne  +$02
 sec
 rts
loc_0b94:
 lda  $1a52
 sta  $1318
 lda  $1a53
 sta  $1319
 lda  $13e2
 sta  $1944
 lda  $13e3
 sta  $1945
 ldy  #$01
 ldx  #$01
 jsr  $1210
 ldy  #$0b
 sty  $139f
 clc
 rts

; ============================================
; SUBROUTINE at $0BBA
; Called from: $0b58
; ============================================
;

; ============================================================================
; SUBROUTINE: process_catalog_entry ($0BBA)
; ============================================================================
; Process one catalog file entry.
; - Extracts filename, file type, lock status, sector count
; - If prompting mode is on, shows filename and asks Y/N
; - Performs wildcard matching against the user's pattern
; - Calls the operation handler for matching files
; ============================================================================

process_catalog_entry:
; Subroutine called 1 time(s) from: $0b58
 tya
 tax
 clc
 adc  #$03
 sta  $13a5
 adc  #$1d
 sta  $13a6
 adc  #$03
 sta  $139f
 lda  $1a51,x
 cmp  #$ff
 bne  +$03
 jmp  $0c6b
loc_0bd6:
 ora  $1a52,x
 bne  +$03
 jmp  $0c6b
loc_0bde:
 txa
 pha
 jsr  $0c6d
 pla
 tax
 bcs  +$03
 jmp  $0c6b
loc_0bea:
 lda  $1a53,x
 sta  $1325
 lda  $1a52,x
 sta  $1319
 lda  $1a51,x
 sta  $1318
 lda  $1a72,x
 sta  $1324
 ldy  #$00
 lda  $1a54,x
 sta  $132b,y
 inx
 iny
 cpy  #$1e
 bne  -$0c
 jsr  $fd8e
 ldx  #$06
 jsr  print_string
 lda  $13aa
 beq  +$23
 jsr  $fd6f
 lda  $0200
 cmp  #$ce
 beq  +$3f
 cmp  #$d9
 beq  +$18
 cmp  #$d1
 beq  +$09
 jsr  $ff3a
 jsr  $fc1a
 jmp  $0c13
 ldx  #$1a
 jsr  print_string
 pla
 pla
 rts
 jsr  $fd8e
 lda  $13ac
 cmp  #$c3
 bne  +$10
 lda  $1325
 and  #$60
 bne  +$10
 ldx  $139f
 dex
 lda  $1a51,x
 bmi  +$07
 lda  #$ff
 sta  $13ab
 sec
 rts
 ldx  #$1e
 jsr  print_string
 ldx  #$1a
 jsr  print_string
 clc
 rts
 lda  $13a0
 sta  $13a3
 lda  $13a1
 sta  $13a2
 jsr  $0cc8
 ldx  $13a3
 ldy  $13a5
 jsr  $0cd8
 bcc  +$3f
 bit  $13a8
 bmi  +$36
 ldx  $13a2
 ldy  $13a6
 jsr  $0cf7
 bcc  +$2f
 bit  $13a8
 bmi  +$26
 ldx  $13a3
 inx
 stx  $13a4
 stx  $13a3
 ldy  $13a5
 sty  $13a7
 jsr  $0cd8
 bit  $13a8
 bmi  +$0e
 bcs  -$1a
 ldy  $13a7
 iny
 sty  $13a5
 ldx  $13a4
 bcc  -$19
 bvc  +$02
 sec
 rts
 clc
 rts
 lda  #$a0
 ldy  $13a6
 iny
 dey
 cmp  $1a51,y
 beq  -$06
 sty  $13a6
 rts
 jsr  $0d16
 bcs  +$19
 lda  $1355,x
 cmp  #$bd
 beq  +$11
 cmp  $1a51,y
 bne  +$0a
 inx
 stx  $13a3
 iny
 sty  $13a5
 bne  -$1b
 clc
 rts
 sec
 rts
 jsr  $0d16
 bcs  +$19
 lda  $1355,x
 cmp  #$bd
 beq  +$11
 cmp  $1a51,y
 bne  +$0a
 dex
 stx  $13a2
 dey
 sty  $13a6
 bne  -$1b
 clc
 rts
 sec
 rts
 txa
 pha
 tya
 pha
 ldy  $13a5
 ldx  $13a3
 cpx  $13a2
 bne  +$09
 lda  $1355,x
 cmp  #$bd
 beq  +$22
 bne  +$02
 bcs  +$0f
 cpy  $13a6
 beq  +$02
 bcs  +$0f
 lda  #$00
 sta  $13a8
 clc
 bcc  +$15
 cpy  $13a6
 beq  +$02
 bcs  +$08
 lda  #$80
 sta  $13a8
 sec
 bcs  +$06
 lda  #$c0
 sta  $13a8
 sec
 pla
 tay
 pla
 tax
 rts
 lda  $13ae
 asl  A
 tay
 iny
 lda  $13ca,y
 pha
 dey
 lda  $13ca,y
 pha
 rts
; ============================================================================
; HANDLER at $0D69: DELETE FILES
; ============================================================================
; Remove files from disk by marking catalog entry as deleted and freeing sectors.
;
; OPERATION:
;   1. Test FILE_STATUS byte (bit 7 = file attribute flag)
;   2. If bit 7 is clear, show "already deleted" or invalid file error message
;   3. If bit 7 is set, set DOS parameter block with delete operation code
;   4. Invoke file manager via $1266 subroutine
;   5. Display completion message and return
;
; INPUT:
;   FILE_STATUS ($1325) - File status byte from catalog entry
;
; EXIT:
;   File marked as deleted in catalog (filename zeroed out)
;   File sectors marked as available in sector bitmap
;   Message displayed to user
;
; REGISTERS: A, X (modified by called routines)
;
; NOTES:
;   - AND #$80 tests bit 7 of FILE_STATUS
;   - BEQ = Branch if Equal to zero (Z flag set when bit 7 is clear)
;   - Error condition: bit 7 clear (file already deleted or invalid state)
;   - Error code $05 = DELETE operation in DOS parameter block
;   - String index $12 = "file already deleted" or error message
;   - String index $0E = operation completion/status message
;
; BYTES: 20 ($0D69-$0D7C)
; ============================================================================
 lda  $1325             ; Load FILE_STATUS byte from catalog entry
                        ; Bit 7 indicates valid file (1=valid, 0=deleted/invalid)
 and  #$80              ; Test bit 7 with mask $80
                        ; Sets Z flag if result is 0 (bit 7 was clear = invalid)
                        ; Clears Z flag if result is nonzero (bit 7 was set = valid)
 beq  +$06              ; Branch if Equal: jump +6 bytes if Z flag set
                        ; Takes branch if bit 7 was clear (error condition)
                        ; Does NOT take branch if bit 7 was set (file is valid)
 ldx  #$12              ; Load X register with $12 (string index 18)
                        ; String 18 = "FILE ALREADY DELETED" or invalid file message
 jsr  print_string      ; Jump to subroutine at $0ACD (via print_string label)
                        ; Displays the error message and returns
 rts                    ; Return from Subroutine
                        ; Pops return address from stack (pushed by RTS dispatch)
 lda  #$05              ; Load accumulator with $05 (DELETE operation code)
                        ; This value identifies the delete operation to DOS file manager
 sta  $18f9             ; Store operation code at $18F9
                        ; $18F9 is part of DOS FM parameter block
 jsr  $1266             ; Jump to subroutine at $1266
                        ; Invokes DOS file manager with operation code in parameter block
                        ; File manager: zeros filename, marks sectors in bitmap, writes back
 ldx  #$0e              ; Load X register with $0E (string index 14)
                        ; String 14 = operation completion/status message
 jsr  print_string      ; Jump to subroutine at $0ACD (via print_string label)
                        ; Displays the completion status message to user
 rts                    ; Return from Subroutine
                        ; Pops return address from stack (pushed by RTS dispatch)
; ============================================================================
; HANDLER at $0D84: LOCK FILES
; ============================================================================
; Write-protect selected files by setting bit 7 in FILE_STATUS ($1325).
;
; OPERATION:
;   1. Test FILE_STATUS byte (bit 7 = write-protect flag)
;   2. If already locked, show "already locked" error message
;   3. If not locked, set DOS parameter block with lock operation code
;   4. Invoke file manager via $1266 subroutine
;   5. Display completion message and return
;
; INPUT:
;   FILE_STATUS ($1325) - File status byte from catalog entry
;
; EXIT:
;   File marked as write-protected (bit 7 set in catalog)
;   Message displayed to user
;
; REGISTERS: A, X (modified by called routines)
;
; NOTES:
;   - BIT instruction affects N flag from bit 7 of operand
;   - BMI = Branch if Minus (N=1, bit 7 set = already locked)
;   - Error code $07 = LOCK operation in DOS parameter block
;   - String index $0E = status message for file operation
;
; BYTES: 19 ($0D84-$0D96)
; ============================================================================
 bit  $1325             ; Test FILE_STATUS ($1325): set N flag from bit 7
                        ; Bit 7 = 1 (N=1) means file is already locked ($80)
                        ; Bit 7 = 0 (N=0) means file is not locked
 bmi  +$08              ; Branch if Minus: jump +8 bytes if N flag set
                        ; Takes branch if bit 7 was set (file already locked)
                        ; Does NOT take branch if bit 7 was clear (not locked)
 lda  #$07              ; Load accumulator with $07 (LOCK operation code)
                        ; This value identifies the operation to DOS file manager
 sta  $18f9             ; Store operation code at $18F9
                        ; $18F9 is part of DOS FM parameter block
 jsr  $1266             ; Jump to subroutine at $1266
                        ; Invokes DOS file manager with operation code in parameter block
                        ; File manager reads catalog, modifies FILE_STATUS, writes back
 ldx  #$0e              ; Load X register with $0E (string index 14)
                        ; String 14 = operation completion/status message
 jsr  print_string      ; Jump to subroutine at $0ACD (via print_string label)
                        ; Displays the status message from string table
 rts                    ; Return from Subroutine
                        ; Pops return address from stack (pushed by RTS dispatch)
; ============================================================================
; HANDLER at $0D97: UNLOCK FILES
; ============================================================================
; Remove write-protection from selected files by clearing bit 7 in FILE_STATUS.
;
; OPERATION:
;   1. Test FILE_STATUS byte (bit 7 = write-protect flag)
;   2. If not locked, show "not locked" error message
;   3. If locked, set DOS parameter block with unlock operation code
;   4. Invoke file manager via $1266 subroutine
;   5. Display completion message and return
;
; INPUT:
;   FILE_STATUS ($1325) - File status byte from catalog entry
;
; EXIT:
;   Write-protection removed from file (bit 7 cleared in catalog)
;   Message displayed to user
;
; REGISTERS: A, X (modified by called routines)
;
; NOTES:
;   - BPL = Branch if Plus (N=0, bit 7 clear = not locked)
;   - Opposite logic of LOCK handler
;   - Error code $08 = UNLOCK operation in DOS parameter block
;   - String index $0E = status message for file operation
;
; BYTES: 19 ($0D97-$0DA9)
; ============================================================================
 bit  $1325             ; Test FILE_STATUS ($1325): set N flag from bit 7
                        ; Bit 7 = 1 (N=1) means file is locked ($80)
                        ; Bit 7 = 0 (N=0) means file is not locked
 bpl  +$08              ; Branch if Plus: jump +8 bytes if N flag clear
                        ; Takes branch if bit 7 was clear (file not locked) - ERROR
                        ; Does NOT take branch if bit 7 was set (file is locked) - OK
 lda  #$08              ; Load accumulator with $08 (UNLOCK operation code)
                        ; This value identifies the operation to DOS file manager
 sta  $18f9             ; Store operation code at $18F9
                        ; $18F9 is part of DOS FM parameter block
 jsr  $1266             ; Jump to subroutine at $1266
                        ; Invokes DOS file manager with operation code in parameter block
                        ; File manager reads catalog, modifies FILE_STATUS, writes back
 ldx  #$0e              ; Load X register with $0E (string index 14)
                        ; String 14 = operation completion/status message
 jsr  print_string      ; Jump to subroutine at $0ACD (via print_string label)
                        ; Displays the status message from string table
 rts                    ; Return from Subroutine
                        ; Pops return address from stack (pushed by RTS dispatch)
; ============================================================================
; HANDLER at $0DAA: CATALOG FILES
; ============================================================================
; Display catalog (directory) of files on selected disk.
;
; OPERATION:
;   1. Load DOS CATALOG operation code
;   2. Store in DOS file manager parameter block
;   3. Invoke DOS file manager to display catalog
;   4. Return to main menu
;
; EXIT:
;   Catalog displayed to user (via DOS file manager at $1266)
;   Returns to main menu
;
; REGISTERS: A, X, Y (modified by called routines)
;
; NOTES:
;   - Operation code $06 = CATALOG operation in DOS parameter block
;   - DOS file manager handles all display formatting and output
;   - This is a simple wrapper that invokes the DOS routine
;   - File manager displays: filename, file type, size in sectors, lock status
;   - No additional processing needed in FID for catalog display
;
; BYTES: 9 ($0DAA-$0DB2)
; ============================================================================
 lda  #$06              ; Load accumulator with $06 (CATALOG operation code)
                        ; This value identifies the catalog operation to DOS file manager
 sta  $18f9             ; Store operation code at $18F9
                        ; $18F9 is part of DOS FM parameter block
 jsr  $1266             ; Jump to subroutine at $1266
                        ; Invokes DOS file manager to display disk catalog
                        ; File manager reads catalog sector, displays each file entry
 rts                    ; Return from Subroutine
                        ; Pops return address from stack (pushed by RTS dispatch)
                        ; Returns control to main menu loop
; ============================================================================
; HANDLER at $0DB3: RESET SLOT & DRIVE
; ============================================================================
; Reset disk operation parameters and return to main menu.
;
; OPERATION:
;   1. Clear menu selection character
;   2. Display "DONE" confirmation message
;   3. Return to main menu loop
;
; EXIT:
;   MENU_CHAR ($13AC) = $00 (clears current selection)
;   Message displayed to user
;   Returns to main loop for next operation
;
; REGISTERS: A, X (modified by called routines)
;
; NOTES:
;   - This is a simple confirmation handler
;   - Does NOT actually change slot/drive variables during execution
;   - Slot/drive are configured by setup_operation when file operation selected
;   - RESET option allows user to return to menu without performing operation
;   - Clearing $13AC (MENU_CHAR) resets selection state
;   - String index $0E = "DONE\n" (completion message)
;
; BYTES: 11 ($0DB3-$0DBD)
; ============================================================================
 lda  #$00              ; Load accumulator with $00
                        ; Clear value to reset menu selection state
 sta  $13ac             ; Store $00 in MENU_CHAR ($13AC)
                        ; This clears the current menu selection
 ldx  #$0e              ; Load X register with $0E (string index 14)
                        ; String 14 = "DONE\n" completion message
 jsr  print_string      ; Jump to subroutine at $0ACD (via print_string label)
                        ; Displays the "DONE" message to user
 rts                    ; Return from Subroutine
                        ; Pops return address from stack (pushed by RTS dispatch)
                        ; Returns control to main loop
; ============================================================================
; HANDLER at $0DBE: VERIFY FILES
; ============================================================================
; Verify file integrity by reading and checking each sector.
;
; OPERATION:
;   1. Load DOS VERIFY operation code
;   2. Store in DOS file manager parameter block
;   3. Invoke DOS file manager to verify selected files
;   4. Display completion message and return
;
; EXIT:
;   File verification completed (via DOS file manager at $1266)
;   Completion message displayed to user
;   Returns to main menu
;
; REGISTERS: A, X (modified by called routines)
;
; NOTES:
;   - Operation code $0C = VERIFY operation in DOS parameter block
;   - DOS file manager traverses file's T/S (track/sector) list
;   - Attempts to read each sector to verify accessibility
;   - Reports any read errors or bad sectors encountered
;   - String index $0E = "DONE\n" (completion message)
;
; BYTES: 15 ($0DBE-$0DCC)
; ============================================================================
 lda  #$0c              ; Load accumulator with $0C (VERIFY operation code)
                        ; This value identifies the verify operation to DOS file manager
 sta  $18f9             ; Store operation code at $18F9
                        ; $18F9 is part of DOS FM parameter block
 jsr  $1266             ; Jump to subroutine at $1266
                        ; Invokes DOS file manager to verify file sectors
                        ; File manager reads each sector, reports any errors
 ldx  #$0e              ; Load X register with $0E (string index 14)
                        ; String 14 = "DONE\n" completion message
 jsr  print_string      ; Jump to subroutine at $0ACD (via print_string label)
                        ; Displays the completion message to user
 rts                    ; Return from Subroutine
                        ; Pops return address from stack (pushed by RTS dispatch)
                        ; Returns control to main menu loop
; ============================================================================
; HANDLER at $0DCC: QUIT
; ============================================================================
; Exit FID and return control to DOS/BASIC prompt.
; ============================================================================
 pla                    ; Pop return address high byte
 pla                    ; Pop return address low byte
 lda  #$00              ; Load value to clear window
 sta  $22               ; Store in window left margin
 jsr  $fc58             ; HOME: clear screen, move cursor to top-left
 jmp  $03d3             ; Jump to DOS warm start ($03D3)
; ============================================================================
; HANDLER at $0DD8: SPACE ON DISK
; ============================================================================
; Display free and used sectors on selected disk using sector bitmap.
;
; OPERATION:
;   1. Initialize sector counters (free and used sectors)
;   2. Read sector bitmap from track $11 (DOS VTOC sector)
;   3. Scan each byte of bitmap to count free vs used sectors
;   4. Display free sector count in BCD format
;   5. Display used sector count in BCD format
;   6. Return to main menu
;
; EXIT:
;   Free sector count displayed (BCD format, high digit then low digit)
;   Used sector count displayed (BCD format, high digit then low digit)
;   Returns to main menu
;
; REGISTERS: A, X, Y (modified extensively, saved/restored as needed)
;
; NOTES:
;   - Sector bitmap on track $11 (VTOC track)
;   - Each bit in bitmap represents one sector (1=free, 0=used)
;   - Sector counters: $1395 (free low), $1396 (free high BCD)
;                      $1397 (used low), $1398 (used high BCD)
;   - $1985 is end-of-bitmap marker
;   - $FDDA is Apple II COUT routine (output accumulator in decimal)
;   - String index $1B = "FREE SECTORS:" display message
;   - String index $1C = "USED SECTORS:" display message
;   - Bitmap scanning done by subroutine at $0E1B
;
; BYTES: 62 ($0DD8-$1815) - includes sector bitmap processing loop
; ============================================================================
 lda  #$00              ; Load accumulator with $00
                        ; Initialize free sector counter value
 sta  $1395             ; Store in FREE_SECT_LOW ($1395)
                        ; Low byte of free sector counter (units digit)
 sta  $1396             ; Store in FREE_SECT_HIGH ($1396)
                        ; High byte of free sector counter (tens digit in BCD)
 sta  $1397             ; Store in USED_SECT_LOW ($1397)
                        ; Low byte of used sector counter (units digit)
 sta  $1398             ; Store in USED_SECT_HIGH ($1398)
                        ; High byte of used sector counter (tens digit in BCD)
 ldy  #$01              ; Load Y register with $01
                        ; Sector index for VTOC (track $11, sector 1)
 ldx  #$01              ; Load X register with $01
                        ; DOS buffer number (read into buffer 1)
 jsr  $1185             ; Jump to subroutine at $1185
                        ; DOS: read sector into memory buffer
                        ; Loads sector bitmap from track $11, sector 1
 ldy  #$00              ; Load Y register with $00
                        ; Initialize byte offset for bitmap scanning
 jsr  $0e1b             ; Jump to subroutine at $0E1B
                        ; Process sector bitmap: count free vs used sectors
                        ; Scans each byte, updates $1395-$1398 counters
 iny                    ; Increment Y register
                        ; Move to next sector/block in bitmap
 cpy  $1985             ; Compare Y with value at $1985
                        ; $1985 contains end-of-bitmap marker
 bne  -$09              ; Branch if Not Equal: loop back if more to scan
                        ; Loop continues until all bitmap sectors processed
 lda  $1396             ; Load accumulator with FREE_SECT_HIGH ($1396)
                        ; High digit (tens) of free sector count
 jsr  $fdda             ; Jump to subroutine at $FDDA
                        ; Apple II COUT: output accumulator as decimal digit
                        ; Displays tens digit of free sectors
 lda  $1395             ; Load accumulator with FREE_SECT_LOW ($1395)
                        ; Low digit (units) of free sector count
 jsr  $fdda             ; Jump to subroutine at $FDDA
                        ; Apple II COUT: output accumulator as decimal digit
                        ; Displays units digit of free sectors
 ldx  #$1b              ; Load X register with $1B (string index 27)
                        ; String 27 = "FREE SECTORS:" label text
 jsr  print_string      ; Jump to subroutine at $0ACD (via print_string label)
                        ; Displays the "FREE SECTORS:" label message
 lda  $1398             ; Load accumulator with USED_SECT_HIGH ($1398)
                        ; High digit (tens) of used sector count
 jsr  $fdda             ; Jump to subroutine at $FDDA
                        ; Apple II COUT: output accumulator as decimal digit
                        ; Displays tens digit of used sectors
 lda  $1397             ; Load accumulator with USED_SECT_LOW ($1397)
                        ; Low digit (units) of used sector count
 jsr  $fdda             ; Jump to subroutine at $FDDA
                        ; Apple II COUT: output accumulator as decimal digit
                        ; Displays units digit of used sectors
 ldx  #$1c              ; Load X register with $1C (string index 28)
                        ; String 28 = "USED SECTORS:" label text
 jsr  print_string      ; Jump to subroutine at $0ACD (via print_string label)
                        ; Displays the "USED SECTORS:" label message
 rts                    ; Return from Subroutine
                        ; Pops return address from stack (pushed by RTS dispatch)
                        ; Returns control to main menu loop
 tya
 pha
 asl  A
 asl  A
 tay
 ldx  #$00
 dey
 lda  #$01
 clc
 ror  A
 bcc  +$02
 iny
 ror  A
 pha
 and  $1989,y
 sed
 beq  +$16
 clc
 lda  #$01
 adc  $1395
 sta  $1395
 bcc  +$1e
 lda  #$00
 adc  $1396
 sta  $1396
 jmp  $0e5b
 clc
 lda  #$01
 adc  $1397
 sta  $1397
 bcc  +$08
 lda  #$00
 adc  $1398
 sta  $1398
 cld
 pla
 inx
 cpx  $1986
 bne  -$3e
 pla
 tay
 rts
; ============================================================================
; HANDLER at $0E66: COPY FILES
; ============================================================================
; Copy files from source disk to destination disk (or same disk with swap).
;
; OPERATION:
;   1. Get source filename pattern from user
;   2. Initialize source disk (read catalog and file list)
;   3. For each matching file:
;      a. Check if file already exists on destination
;      b. Prompt user if destination exists (replace? cancel?)
;      c. Read source file sector-by-sector into buffer
;      d. Write sectors to destination disk location
;      e. Update destination disk catalog and bitmap
;   4. Handle disk swap logic if copying on same disk
;   5. Display copy results/errors
;   6. Return to main menu
;
; INPUT:
;   User provides:
;   - Filename pattern (with optional '=' wildcards)
;   - Source slot/drive (if not COPY - single disk mode)
;   - Destination slot/drive (if COPY - two disk mode)
;   - Replace existing file (Y/N if destination file exists)
;
; EXIT:
;   Files copied to destination disk
;   Destination catalog updated
;   Destination sector bitmap updated
;   Results/error messages displayed
;
; REGISTERS: A, X, Y (heavily used throughout)
;
; KEY VARIABLES:
;   $131D-$131F    Destination slot/drive (set in setup_operation)
;   $1320-$1322    Source slot/drive (set in setup_operation)
;   $1323          SAME_DISK_FLAG ($FF if source == destination)
;   $1324          FILE_TYPE (type of current file being copied)
;   $1325          FILE_STATUS (write-protect and other flags)
;   $192C+          DOS parameter block for file operations
;   $1C52-$1C53    Source file track/sector list position
;   $192E-$1933    File attribute save buffer (6 bytes)
;   $190F-$1910    Current file track/sector info
;   $1399-$139B    Destination file track/sector info
;   $139D-$139E    T/S list position tracking
;   $1374-$1391    Filename backup buffer (30 bytes)
;
; SUBROUTINES CALLED:
;   $100E          get_source_filename - Get user's source pattern
;   $1082          init_disk_operation - Set up source disk
;   $0EB4          wait_key_dialog - Prompt user
;   wait_key_cr    Wait for key with CR, handle SAME_DISK_FLAG
;   wait_key_cr2   Wait for key with CR (different logic path)
;   $1133          process_source_files - Main copy loop
;   $0EE7          ???? (helper subroutine)
;   $1005          ???? (helper subroutine)
;   $10E4          ???? (helper subroutine)
;   $1185          DOS: read sector into buffer
;   $0F15          check_destination_space - Verify destination has room
;   $FF3A          (Apple II ROM: likely display/input routine)
;   $FC1A          (Apple II ROM: likely clear/reset routine)
;   $1266          DOS file manager - execute operation
;   beep_and_print Print error message with bell
;
; COMPLEXITY: ⭐⭐⭐⭐⭐ VERY HIGH
;   - Multi-sector file handling
;   - Disk swap logic and prompting
;   - Source/destination management
;   - Error recovery and validation
;   - File attribute preservation
;   - Catalog and bitmap updates
;
; NOTES:
;   [Phase 7.5 - Framework documented, internal logic requires further analysis]
;   - Operation code $01 and $02 used for DOS file operations
;   - Operation code $05 = UNLOCK
;   - Operation code $08 = LOCK
;   This handler is the most complex in FID, requiring careful tracing of:
;   • Sector I/O sequences
;   • DOS parameter block manipulation
;   • File attribute copying
;   • Error handling paths
;   • Disk swap user interaction
;   • Destination file conflict resolution
;
; BYTES: ~150-200 ($0E66-$0F9F estimated, extends into subroutines)
; ============================================================================
; === COPY HANDLER MAIN ENTRY ($0E66) ===
; Get source filename and initialize source disk
 jsr  $100e             ; Jump to subroutine at $100E
                        ; get_source_filename: Get filename pattern from user
                        ; User enters pattern with optional '=' wildcards
                        ; Stores filename in $132B (max 30 chars)
 jsr  $1082             ; Jump to subroutine at $1082
                        ; init_disk_operation: Initialize source disk
                        ; Reads source disk catalog into buffer
                        ; Sets up file enumeration
; Check if source and destination are same disk (SAME_DISK_FLAG)
 lda  $1323             ; Load SAME_DISK_FLAG ($1323)
                        ; $FF = source and destination same disk (copy within disk)
                        ; $00 = different disks (normal copy operation)
 beq  +$03              ; Branch if Equal: skip if different disks
                        ; If $1323 is 0 (not same disk), skip next call
 jsr  wait_key_cr2      ; Jump to subroutine (conditional)
                        ; Handle same-disk copy prompting
                        ; Prompts user to swap source/dest disks as needed
 jsr  $0eb4             ; Jump to subroutine at $0EB4
                        ; Process source file catalog and start copy loop
 jmp  $0e8d             ; Jump to address $0E8D
                        ; Skip alternative path, go to main copy loop
; Alternative path for same-disk copy
 lda  $1323             ; Load SAME_DISK_FLAG again (in alternative path)
                        ; This is for the different-disks case
 beq  +$03              ; Branch if Equal: skip if same disk
                        ; If different disks, skip next call
 jsr  wait_key_cr       ; Jump to subroutine (conditional)
                        ; Alternate disk prompt handler
 jsr  $1082             ; Jump to subroutine at $1082
                        ; init_disk_operation: Re-initialize disk (different source)
 lda  $1323             ; Load SAME_DISK_FLAG (third check)
                        ; Verify disk configuration
 beq  +$03              ; Branch if Equal
 jsr  wait_key_cr2      ; Jump to subroutine (conditional)
                        ; Final disk prompt if needed
 jsr  $1133             ; Jump to subroutine at $1133
                        ; process_source_files: Main copy processing loop
                        ; Iterates through matching files, performs copy
; Check completion status and handle errors
 bit  $131a             ; Test byte at $131A
                        ; Bit test loads and tests byte, sets N flag from bit 7
                        ; $131A contains error/status flags
 bmi  +$14              ; Branch if Minus: jump +20 bytes if bit 7 set (error)
                        ; If error detected, skip cleanup, display error
 ldy  $139e             ; Load Y with value at $139E
                        ; T/S list max position tracker
 cpy  #$f4              ; Compare Y with $F4 (244 decimal)
                        ; Check if T/S list scan is complete
 bne  -$22              ; Branch if Not Equal: loop back -34 bytes if not done
                        ; Continue scanning if more entries to process
 lda  $1c52             ; Load accumulator with low byte at $1C52
                        ; Source file track/sector position (low)
 ora  $1c53             ; Bitwise OR with high byte at $1C53
                        ; Source file track/sector position (high)
                        ; Combined check: non-zero means more data to read
 bne  -$2a              ; Branch if Not Equal: loop back -42 bytes if data remains
                        ; Continue loop if source file not fully processed
 jsr  $10e4             ; Jump to subroutine at $10E4
                        ; Final cleanup subroutine
 ldx  #$00              ; Load X register with $00
 ldy  #$00              ; Load Y register with $00
 jsr  $1185             ; Jump to subroutine at $1185
                        ; DOS: read sector into buffer (final operation)
 ldx  #$0e              ; Load X register with $0E (string index 14)
                        ; String 14 = "DONE\n" completion message
 jsr  print_string      ; Jump to subroutine at $0ACD (via print_string label)
                        ; Display completion message
 rts                    ; Return from Subroutine
                        ; Pops return address from stack
                        ; Returns to main menu loop
; === FILE ATTRIBUTE PRESERVATION HELPER ($0EE7 continuation) ===
; Save and restore file attributes (type, protection, etc.)
 jsr  $0ee7             ; Jump to subroutine at $0EE7
                        ; Get current file attributes from source catalog
; Copy track/sector list pointers to destination area
 lda  $190f             ; Load accumulator with high byte at $190F
                        ; Source file track/sector list pointer (high)
 sta  $1399             ; Store in destination area $1399
                        ; SAVED_TRACK: Destination T/S high byte
 lda  $1910             ; Load accumulator with low byte at $1910
                        ; Source file track/sector list pointer (low)
 sta  $139b             ; Store in destination area $139B
                        ; SAVED_SECTOR: Destination T/S low byte
; Save file attributes buffer (type, size info) - 6 bytes
 ldx  #$05              ; Load X register with $05
                        ; Loop counter for 6 bytes (0-5)
 lda  $192e,x           ; Load accumulator from $192E+X
                        ; Read file attribute byte from source buffer
                        ; $192E-$1933 contains file attributes (6 bytes)
 pha                    ; Push accumulator onto stack
                        ; Save attribute byte on stack
 dex                    ; Decrement X register
                        ; Move to previous byte in attribute buffer
 bpl  -$07              ; Branch if Plus: loop back if X >= 0
                        ; Continue until all 6 bytes saved on stack
; Restore attributes from stack
 jsr  $1005             ; Jump to subroutine at $1005
                        ; Apply saved attributes to destination
 ldx  #$00              ; Load X register with $00
                        ; Initialize index for attribute restoration
 pla                    ; Pull accumulator from stack
                        ; Restore first attribute byte (last pushed = first popped)
 sta  $192e,x           ; Store in $192E+X
                        ; Restore attribute byte to buffer
 inx                    ; Increment X register
                        ; Move to next destination byte
 cpx  #$06              ; Compare X with $06 (6 bytes)
                        ; Check if all attributes restored
 bcc  -$09              ; Branch if Carry Clear: loop back if X < 6
                        ; Continue until all 6 bytes restored
; Initialize destination file sector
 ldy  #$01              ; Load Y register with $01
                        ; Sector index for destination file
 ldx  #$00              ; Load X register with $00
                        ; DOS buffer number
 jsr  $1185             ; Jump to subroutine at $1185
                        ; DOS: read sector into buffer
                        ; Read first destination sector for file header
 lda  #$ff              ; Load accumulator with $FF
                        ; Maximum value flag
 sta  $1393             ; Store in FILE_COUNT ($1393)
                        ; Mark file index as initialized ($FF)
 rts                    ; Return from Subroutine
; === DESTINATION FILE SETUP SECTION ===
; Check destination disk space and initialize write operation
 jsr  $0f15             ; Jump to subroutine at $0F15
                        ; check_destination_space: Verify room on destination
                        ; Checks disk bitmap for available sectors
 lda  $1325             ; Load accumulator with FILE_STATUS ($1325)
                        ; File status/protection flags from source
 sta  $1900             ; Store in destination buffer $1900
                        ; Copy status to destination file area
 ldx  #$00              ; Load X register with $00
                        ; Initialize for DOS operation
 lda  #$01              ; Load accumulator with $01
                        ; DOS operation code for file read
 sta  $18f9             ; Store operation code at $18F9
                        ; DOS parameter block operation field
 jsr  $1266             ; Jump to subroutine at $1266
                        ; DOS file manager: execute read operation
                        ; Reads destination sector for initialization
; Setup destination T/S list tracking
 lda  $190f             ; Load accumulator with source T/S high byte
                        ; Source track/sector pointer (high)
 sta  $1399             ; Store in SAVED_TRACK ($1399)
                        ; Initialize destination track counter
 lda  $1910             ; Load accumulator with source T/S low byte
                        ; Source track/sector pointer (low)
 sta  $139b             ; Store in SAVED_SECTOR ($139B)
                        ; Initialize destination sector counter
; Copy file type to destination
 lda  $1324             ; Load accumulator with FILE_TYPE ($1324)
                        ; File type from source catalog (B, T, A, I, etc.)
 sta  $192c             ; Store in $192C
                        ; Destination file type area in DOS parameter block
; Calculate and store file size information
 lda  $192f             ; Load accumulator with $192F
                        ; File size information byte
 asl  A                 ; Arithmetic Shift Left
                        ; Multiply by 2
 asl  A                 ; Arithmetic Shift Left
 sta  $1392
 rts
; === SECTOR READ INITIALIZATION ($0F05+) ===
; Set up for reading source file sectors
 ldx  #$01              ; Load X register with $01
                        ; DOS buffer number for sector read
 lda  #$01              ; Load accumulator with $01
                        ; DOS operation code for read
 sta  $18f9             ; Store operation code at $18F9
                        ; DOS parameter block
 jsr  $1266             ; Jump to subroutine at $1266
                        ; DOS file manager: execute read operation
                        ; Reads first sector of source file
 lda  $1903             ; Load accumulator with $1903
                        ; DOS operation result/status byte
 cmp  #$06              ; Compare with $06
                        ; Check if read was successful
 bne  +$01              ; Branch if Not Equal: skip if error
                        ; If result is not $06, an error occurred
 rts                    ; Return from Subroutine
                        ; Success path: return with data loaded
; === FILE DIALOG & USER PROMPTING ===
; Display file information and get user confirmation
 jsr  $fd8e             ; Jump to subroutine at $FD8E
                        ; Apple II ROM: carriage return/newline
 jsr  $ff3a             ; Jump to subroutine at $FF3A
                        ; Apple II ROM: clear line or display control
 jsr  $ff3a             ; Jump to subroutine at $FF3A
                        ; Apple II ROM: second control sequence
 ldx  #$06              ; Load X register with $06 (string index 6)
                        ; String 6: Display format/filename template
 jsr  print_string      ; Jump to subroutine at $0ACD
                        ; Display catalog file format string
 ldx  #$07              ; Load X register with $07 (string index 7)
                        ; String 7: Additional file information
 jsr  print_string      ; Jump to subroutine at $0ACD
                        ; Display file information
 ldx  #$19              ; Load X register with $19 (string index 25)
                        ; String 25: Filename or prompt text
 jsr  print_string      ; Jump to subroutine at $0ACD
                        ; Display filename prompt
 jsr  $fd6f             ; Jump to subroutine at $FD6F
                        ; Apple II ROM: GETLN - get line input from user
 cpx  #$00              ; Compare X with $00
                        ; Check input length (X = number of chars)
 beq  +$4f              ; Branch if Equal: jump +79 bytes if no input
                        ; If user entered nothing, skip copy logic
; Check user response to file prompt
 lda  $0200             ; Load accumulator with $0200
                        ; First character of user input
 cmp  #$83              ; Compare with $83 (Apple II code for 'C')
                        ; Check if user pressed 'C' to cancel
 bne  +$0c              ; Branch if Not Equal: skip if not 'C'
                        ; If not cancel, continue with copy
 ldx  #$1a              ; Load X register with $1A (string index 26)
                        ; String 26: "COPY CANCELLED" or similar message
 jsr  print_string      ; Jump to subroutine at $0ACD
                        ; Display cancellation message
 pla                    ; Pull return address high byte from stack
 pla                    ; Pull return address low byte from stack
 pla                    ; Pull additional stack values (cleanup)
 pla                    ; Pull additional stack values (cleanup)
 pla                    ; Pull additional stack values (cleanup)
 pla                    ; Pull additional stack values (cleanup)
 rts                    ; Return from Subroutine
                        ; Exit copy operation, return to menu
; === FILENAME BACKUP & RESTORATION ===
; Save current filename and prepare for modification
 ldy  #$1d              ; Load Y register with $1D (30 decimal)
                        ; Loop counter for filename length
 lda  $132b,y           ; Load accumulator from $132B+Y
                        ; Read byte from filename buffer
 sta  $1374,y           ; Store in backup buffer $1374+Y
                        ; Save filename character for restoration
 lda  #$a0              ; Load accumulator with $A0
                        ; Space character (Apple II encoding)
 sta  $132b,y           ; Store space in $132B+Y
                        ; Clear filename buffer (pad with spaces)
 dey                    ; Decrement Y register
                        ; Move to previous character
 bpl  -$0e              ; Branch if Plus: loop back if Y >= 0
                        ; Continue until all 30 bytes processed
; Scan input buffer for filename characters
 ldy  #$ff              ; Load Y register with $FF
                        ; Initialize scan pointer (-1)
 iny                    ; Increment Y register
                        ; Start at position 0
 cmp  $0200,y           ; Compare accumulator with $0200+Y
                        ; Check character in input buffer
 beq  -$06              ; Branch if Equal: loop back if match found
                        ; Continue scanning until matching char found
 lda  $0200,y           ; Load accumulator from $0200+Y
                        ; Read character from input buffer
 cmp  #$c0              ; Compare with $C0 (Apple II code for '@')
                        ; Check if control character/end marker
 bcc  +$54              ; Branch if Carry Clear: jump +84 bytes if valid
                        ; If character is less than $C0, continue processing
 cmp  #$e0
 bcs  +$50
 ldx  #$00
 lda  $0200,y
 cmp  #$8d
 beq  -$70
 cmp  #$ac
 beq  +$43
 sta  $132b,x
 iny
 inx
 cpx  #$1e
 bcc  -$14
 jmp  $0f15
 bit  $1900
 bpl  +$29
 ldx  #$12
 jsr  print_string
 ldx  #$1d
 jsr  print_string
 jsr  $fd6f
 lda  $0200
 cmp  #$d9
 beq  +$0d
 cmp  #$ce
 beq  -$78
 jsr  $ff3a
 jsr  $fc1a
 jmp  $0f9f
 lda  #$08
 sta  $18f9
 jsr  $1266
 lda  #$05
 sta  $18f9
 jsr  $1266
 rts
 ldx  #$14
 jsr  beep_and_print
 jsr  $fc1a
 jsr  $fc1a
 jsr  $fc1a
 ldx  #$1d
 lda  $1374,x
 sta  $132b,x
 dex
 bpl  -$09
 jmp  $0f3a
 ldy  #$2c
 lda  #$00
 sta  $190f,y
 dey
 bpl  -$06
 lda  $131d
 sta  $18fe
 lda  $131f
 sta  $18ff
 lda  $1325
 sta  $1900
 rts
 lda  #$02
 sta  $18f9
 jsr  $1266
 rts
 lda  #$00
 sta  $139d
 lda  #$f4
 sta  $139e
 lda  $1318
 sta  $1c52
 lda  $1319
 sta  $1c53
 lda  #$00
 sta  $131a
 sta  $131b
 rts
 ldy  #$0f
 lda  ($02),y
 sta  $194b
 iny
 lda  ($02),y
 sta  $194c
 rts
 ldy  #$0f
 lda  $194b
 sta  ($02),y
 iny
 lda  $194c
 sta  ($02),y
 rts
 lda  $13e0
 sta  $1944
 lda  $13e1
 sta  $1945
 lda  $1c52
 sta  $139a
 sta  $1318
 lda  $1c53
 sta  $139c
 sta  $1319
 ora  $1318
 bne  +$08
 lda  #$ff
 sta  $131a
 ldy  #$00
 rts
 ldy  #$01
 ldx  #$01
 jsr  $1210
 lda  #$00
 sta  $139e
 tay
 rts
 ldy  $139e
 cpy  #$f4
 bne  +$09
 jsr  $1049
 bit  $131a
 bpl  +$01
 rts
 lda  $13e4
 sta  $1944
 lda  $13e5
 sta  $1945
 ldx  #$ff
 lda  $1c5d,y
 sta  $1318
 iny
 lda  $1c5d,y
 sta  $1319
 iny
 sty  $139e
 ora  $1318
 beq  +$12
 ldy  #$01
 txa
 ldx  #$01
 jsr  $1210
 tax
 inc  $1945
 inx
 cpx  $1394
 beq  +$07
 ldy  $139e
 cpy  #$f4
 bne  -$2f
 rts
 bit  $131a
 bmi  +$0f
 jsr  $119f
 lda  $192f
 sta  $1b52
 lda  $192e
 sta  $1b53
 lda  $13de
 sta  $1944
 lda  $13df
 sta  $1945
 lda  $1399
 sta  $1318
 lda  $139b
 sta  $1319
 ldy  #$00
 ldx  #$00
 jsr  $1210
 lda  $1b52
 sta  $1399
 lda  $1b53
 sta  $139b
 ldy  #$00
 lda  #$00
 cpy  #$05
 beq  +$07
 cpy  #$06
 beq  +$03
 sta  $1b51,y
 iny
 bne  -$0e
 sta  $139d
 clc
 lda  #$7a
 adc  $1b56
 sta  $1b56
 bcc  +$03
 inc  $1b57
 rts
 ldy  $139d
 cpy  #$f4
 bne  +$09
 jsr  $10d0
 lda  $131a
 beq  +$01
 rts
 lda  $13e4
 sta  $1944
 lda  $13e5
 sta  $1945
 inc  $139d
 inc  $139d
 lda  $1c5d,y
 ora  $1c5e,y
 beq  +$1f
 jsr  $119f
 lda  $192f
 sta  $1318
 sta  $1b5d,y
 lda  $192e
 sta  $1319
 sta  $1b5e,y
 ldy  #$00
 ldx  #$00
 jsr  $1210
 inc  $1945
 ldy  $139d
 cpy  $139e
 bne  -$35
 rts
 lda  $13dc
 sta  $1944
 lda  $13dd
 sta  $1945
 lda  #$11
 sta  $1318
 lda  #$00
 sta  $1319
 jsr  $1210
 rts
 pha
 tya
 pha
 txa
 pha
 lda  $192f
 dec  $192e
 bmi  +$2b
 clc
 ldx  #$03
 rol  $1930,x
 dex
 bpl  -$06
 bcc  -$10
 ldy  $1392
 ldx  $1986
 lda  #$ff
 clc
 ror  A
 bcs  +$02
 iny
 ror  A
 dex
 cpx  $192e
 bne  -$0b
 and  $1989,y
 sta  $1989,y
 pla
 tax
 pla
 tay
 pla
 rts
 ldx  $1393
 inx
 cpx  $1985
 bcs  +$28
 txa
 asl  A
 asl  A
 tay
 lda  $1989,y
 sta  $1930
 lda  $198a,y
 sta  $1931
 bne  +$05
 ora  $1930
 beq  -$1d
 stx  $1393
 stx  $192f
 ldx  $1986
 stx  $192e
 sty  $1392
 bne  -$64
 lda  #$09
 sta  $131b
 jmp  $12a4
 pha
 txa
 pha
 tya
 pha
 lda  #$00
 sta  $193f
 lda  $1321,x
 sta  $193d
 lda  $131d,x
 sta  $193e
 lda  $1318
 sta  $1940
 lda  $1319
 sta  $1941
 cpy  #$01
 beq  +$02
 ldy  #$02
 sty  $1948
 ldy  $13e6
 lda  $13e7
 jsr  $03d9
 bcc  +$0e
 lda  #$ff
 sta  $131a
 lda  $1949
 sta  $131b
 jmp  $12a4
 lda  $193d
 sta  $194b
 lda  $193e
 sta  $194c
 pla
 tay
 pla
 tax
 pla
 rts
 pha
 tya
 pha
 txa
 pha
 jsr  $103b
 lda  #$00
 sta  $18fd
 ldy  #$15
; === DOS PARAMETER BLOCK COPY & EXECUTION ===
; Copy DOS parameter block and execute file operation
 lda  $18f9,y           ; Load accumulator from $18F9+Y
                        ; Read DOS parameter block byte
 sta  ($00),y           ; Store in ($00)+Y (destination parameter area)
                        ; Copy parameter byte to destination
 dey                    ; Decrement Y register
                        ; Move to previous byte
 bpl  -$08              ; Branch if Plus: loop back if Y >= 0
                        ; Continue copying until all bytes transferred
 jsr  $03d6             ; Jump to subroutine at $03D6
                        ; DOS: execute file operation with parameter block
                        ; Performs read/write/lock/unlock based on parameter
 php                    ; Push processor status register onto stack
                        ; Save carry flag and other status flags
 ldy  #$15              ; Load Y register with $15 (21 decimal)
                        ; Offset for copying result bytes back
 lda  ($00),y           ; Load accumulator from ($00)+Y
                        ; Read result byte from DOS operation
 sta  $18f9,y           ; Store in $18F9+Y
                        ; Copy result back to parameter block
 dey                    ; Decrement Y register
                        ; Move to previous byte
 bpl  -$08              ; Branch if Plus: loop back if Y >= 0
                        ; Continue copying all result bytes
 plp                    ; Pull processor status register from stack
                        ; Restore carry flag from DOS operation
 bcc  +$0d              ; Branch if Carry Clear: jump +13 bytes if success
                        ; If carry is clear (no error), skip error handling
; DOS operation error path
 lda  $1903             ; Load accumulator with $1903
                        ; DOS operation result/error code
 cmp  #$06              ; Compare with $06
                        ; Check if result code is $06 (likely success)
 beq  +$06              ; Branch if Equal: jump +6 bytes if $06
                        ; If it's $06, continue normally
 sta  $131b             ; Store error code in $131B
                        ; Save error code for later display
 jmp  $12a4             ; Jump to address $12A4
                        ; Go to error reporting routine
; Cleanup and return
 jsr  $102d             ; Jump to subroutine at $102D
                        ; Cleanup routine after DOS operation
 pla                    ; Pull accumulator from stack
                        ; Restore A register from caller
 tax                    ; Transfer A to X register
                        ; Save value in X for return
 pla                    ; Pull Y register from stack
                        ; Restore Y register value
 tay                    ; Transfer to Y register
                        ; Restore Y for return
 pla                    ; Pull return address low byte from stack
                        ; (This was pre-pushed by caller)
 rts                    ; Return from Subroutine
                        ; Return to caller
; === ERROR REPORTING & MESSAGE DISPLAY ===
; Display DOS error messages based on error code
 jsr  $fd8e             ; Jump to subroutine at $FD8E
                        ; Apple II ROM: carriage return/newline
 jsr  $ff3a             ; Jump to subroutine at $FF3A
                        ; Apple II ROM: control sequence
 jsr  $ff3a             ; Jump to subroutine at $FF3A
                        ; Apple II ROM: second control sequence
 lda  $131b             ; Load accumulator with $131B
                        ; DOS error code from operation
 cmp  #$09              ; Compare with $09
                        ; Check for specific error code $09
 bne  +$1e              ; Branch if Not Equal: jump +30 bytes if not $09
                        ; If not error $09, check other codes
 ldx  #$10              ; Load X register with $10 (string index 16)
                        ; String 16: "ERROR. CODE=" message header
 jsr  print_string      ; Jump to subroutine at $0ACD
                        ; Display error code header message
 bit  $1325             ; Test byte at $1325
                        ; Bit test FILE_STATUS for write-protect bit 7
 bpl  +$08              ; Branch if Plus: jump +8 bytes if bit 7 clear
                        ; Skip unlock/delete if not locked
 lda  #$08              ; Load accumulator with $08
                        ; DOS operation code: UNLOCK
 sta  $18f9             ; Store operation code at $18F9
                        ; DOS parameter block
 jsr  $1266             ; Jump to subroutine at $1266
                        ; DOS file manager: unlock file
 lda  #$05              ; Load accumulator with $05
                        ; DOS operation code: DELETE
 sta  $18f9             ; Store operation code at $18F9
                        ; DOS parameter block
 jsr  $1266             ; Jump to subroutine at $1266
                        ; DOS file manager: delete file
 ldx  #$1a              ; Load X register with $1A (string index 26)
                        ; String 26: additional error message

; === ERROR CODE DISPATCH TABLE ===
; Branch to appropriate error message for different DOS error codes
 bne  +$34              ; Branch if Not Equal: jump +52 bytes
                        ; If not error $09, continue checking
 cmp  #$04              ; Compare error code with $04
                        ; Check for error code $04
 bne  +$04              ; Branch if Not Equal: skip this handler
 ldx  #$11              ; Load X register with $11 (string index 17)
                        ; String 17: error message for code $04
 bne  +$2c              ; Branch unconditionally +44 bytes
                        ; Skip remaining error checks
 cmp  #$10              ; Compare error code with $10
                        ; Check for error code $10
 bne  +$04              ; Branch if Not Equal: skip this handler
 ldx  #$11              ; Load X register with $11 (string index 17)
                        ; String 17: error message for code $10
 bne  +$24              ; Branch unconditionally +36 bytes
                        ; Skip remaining error checks
 cmp  #$0a              ; Compare error code with $0A
                        ; Check for error code $0A
 bne  +$04              ; Branch if Not Equal: skip this handler
 ldx  #$12              ; Load X register with $12 (string index 18)
                        ; String 18: error message for code $0A
 bne  +$1c              ; Branch unconditionally +28 bytes
                        ; Skip remaining error checks
 cmp  #$08              ; Compare error code with $08
                        ; Check for error code $08
 beq  +$16              ; Branch if Equal: jump +22 bytes if match
                        ; If error $08 found, process it
 cmp  #$80              ; Compare error code with $80
                        ; Check for error code $80 (bit 7 set)
 beq  +$12              ; Branch if Equal: jump +18 bytes if match
                        ; If error $80 found, process it
 cmp  #$40              ; Compare error code with $40
                        ; Check for error code $40
 beq  +$0e              ; Branch if Equal: jump +14 bytes if match
                        ; If error $40 found, process it
; Default error message
 ldx  #$08              ; Load X register with $08 (string index 8)
                        ; String 8: generic/default error message
 jsr  print_string      ; Jump to subroutine at $0ACD
                        ; Display default error message
 lda  $131b             ; Load accumulator with $131B
                        ; Reload error code
 jsr  $fdda             ; Jump to subroutine at $FDDA
                        ; Apple II ROM: output error code as decimal
 jmp  $03d3             ; Jump to address $03D3
                        ; Jump to DOS warm start (exit FID)

; === COMPLETION & RETURN TO MENU ===
; Display completion message and return to main menu
 ldx  #$13              ; Load X register with $13 (string index 19)
                        ; String 19: "COPY COMPLETE" or success message
 jsr  print_string      ; Jump to subroutine at $0ACD
                        ; Display completion message
 ldx  $131c             ; Load X register with $131C
                        ; Load some operation counter/state
 txs                    ; Transfer X to stack pointer register
                        ; Set stack pointer from X value
 ldx  #$00              ; Load X register with $00
                        ; Initialize index
 stx  $13ad             ; Store $00 in OPERATION_MODE ($13AD)
                        ; Clear operation mode flag
 jsr  press_any_key     ; Jump to subroutine
                        ; Wait for any key press before returning
                        ; Returns to main menu when key pressed
 jmp  main_loop

; ============================================================================
; DATA SECTION ($1316 - $1A50)
; ============================================================================
;
; Everything from $1316 to $1A50 (1851 bytes) is data:
;   $1318-$1325  Initialized working variables
;   $1326-$134A  Catalog file display format string (str idx 6)
;   $134B-$1373  Filename prompt format string (str idx 10)
;   $1374-$1391  Filename backup buffer (30 bytes)
;   $1392-$13AE  Working variables (29 bytes)
;   $13AF-$13B8  Menu option characters '123456789'
;   $13B9-$13C9  Input validation sub-tables
;   $13CA-$13DB  RTS dispatch table (9 entries)
;   $13DC-$13E7  DOS parameter block pointers
;   $13E8-$1449  String pointer table (49 entries)
;   $144A-$18F8  Apple II text strings (null-terminated)
;   $18F9-$1A50  DOS file manager parameter list + buffers
;

; --- Initialized Variables ($1318-$1325) ---
; These hold initial runtime values. Many are overwritten.
; Note: $1316-$1317 are the operand bytes of the JMP instruction
; at $1315 and are part of the code section.

 db   $CF               ; $1318: current track
 db   $A0               ; $1319: current sector
 db   $A0               ; $131A: error flag (0=OK, $FF=error)
 db   $81               ; $131B: error code
 db   $A0               ; $131C: saved stack pointer
 db   $A5               ; $131D: destination drive
 db   $B1               ; $131E: source drive
 db   $EC               ; $131F: destination slot
 db   $A0               ; $1320: source slot
 db   $83               ; $1321: shifted dest slot (slot*16)
 db   $A0               ; $1322: shifted src slot (slot*16)
 db   $A0               ; $1323: same-disk flag ($FF=same)
 db   $A2               ; $1324: file type byte
 db   $A0               ; $1325: file status/flags byte

; --- Catalog File Display Format ($1326-$134A) ---
; String index 6: "FILE" + formatting/placeholder bytes
; Used to display catalog entries with file attributes.

 db   $C6, $C9, $CC, $C5  ; $1326: "FILE"
 db   $A0               ; $132A: ' '
 db   $80               ; $132B: ctrl-@ (format code)
 db   $A0               ; $132C: ' '
 db   $F0               ; $132D: 'p'
 db   $A0               ; $132E: ' '
 db   $81               ; $132F: ctrl-A (format code)
 db   $A0               ; $1330: ' '
 db   $A5               ; $1331: '%'
 db   $B0               ; $1332: '0'
 db   $A0               ; $1333: ' '
 db   $98               ; $1334: ctrl-X (format code)
 db   $A0               ; $1335: ' '
 db   $A5               ; $1336: '%'
 db   $A0               ; $1337: ' '
 db   $A0               ; $1338: ' '
 db   $BA               ; $1339: ':'
 db   $A4               ; $133A: '$'
 db   $80               ; $133B: ctrl-@ (format code)
 db   $A0               ; $133C: ' '
 db   $87               ; $133D: ctrl-G (format code)
 db   $A0               ; $133E: ' '
 db   $C8               ; $133F: 'H'
 db   $A0               ; $1340: ' '
 db   $A0               ; $1341: ' '
 db   $AF               ; $1342: '/'
 db   $B2               ; $1343: '2'
 db   $A5               ; $1344: '%'
 db   $A0               ; $1345: ' '
 db   $BA               ; $1346: ':'
 db   $A0               ; $1347: ' '
 db   $C9               ; $1348: 'I'
 db   $A0               ; $1349: ' '
 db   $00               ; $134A: null terminator

; --- Filename Prompt Format ($134B-$1373) ---
; String index 10: "FILENAME:" + formatting/display codes

 db   $C6, $C9, $CC, $C5  ; $134B: "FILE"
 db   $CE, $C1, $CD, $C5  ; $134F: "NAME"
 db   $BA               ; $1353: ':'
 db   $A0               ; $1354: ' '
 db   $A0               ; $1355: ' '
 db   $9D               ; $1356: ctrl-?
 db   $CC               ; $1357: 'L'
 db   $AA               ; $1358: '*'
 db   $D3               ; $1359: 'S'
 db   $AF               ; $135A: '/'
 db   $D8               ; $135B: 'X'
 db   $A0               ; $135C: ' '
 db   $A0               ; $135D: ' '
 db   $D4               ; $135E: 'T'
 db   $89               ; $135F: ctrl-I
 db   $A0               ; $1360: ' '
 db   $8C               ; $1361: ctrl-L
 db   $A0               ; $1362: ' '
 db   $A0               ; $1363: ' '
 db   $C8               ; $1364: 'H'
 db   $A0               ; $1365: ' '
 db   $80               ; $1366: ctrl-@
 db   $A0               ; $1367: ' '
 db   $A0               ; $1368: ' '
 db   $A0               ; $1369: ' '
 db   $A0               ; $136A: ' '
 db   $E5               ; $136B: 'e'
 db   $AA               ; $136C: '*'
 db   $D2               ; $136D: 'R'
 db   $A0               ; $136E: ' '
 db   $A0               ; $136F: ' '
 db   $A0               ; $1370: ' '
 db   $A0               ; $1371: ' '
 db   $E0               ; $1372: '`'
 db   $00               ; $1373: null terminator

; --- Filename Backup Buffer ($1374-$1391) ---
; 30-byte buffer for saving/restoring filenames during operations.
; Initial values are meaningless; overwritten at runtime.

 db   $A0, $B9, $C5, $84, $A0, $86, $A0, $A0  ; $1374
 db   $B0, $A0, $AF, $A0, $AC, $A0, $A0, $CF  ; $137C
 db   $A0, $CC, $A0, $A4, $A0, $A0, $D0, $CC  ; $1384
 db   $A0, $CE, $92, $A0, $90, $B0  ; $138C

; --- Working Variables ($1392-$13AE) ---
; Runtime variables used by catalog traversal, file matching,
; and operation dispatch. Initial values overwritten at runtime.

 db   $E8               ; $1392: bitmap column offset
 db   $C8               ; $1393: current file index in catalog
 db   $A4               ; $1394: file count / status flag
 db   $B0               ; $1395: free sector count low (BCD)
 db   $A0               ; $1396: free sector count high (BCD)
 db   $A0               ; $1397: used sector count low (BCD)
 db   $C1               ; $1398: used sector count high (BCD)
 db   $C5               ; $1399: saved track number
 db   $A0               ; $139A: saved track copy
 db   $A0               ; $139B: saved sector number
 db   $A0               ; $139C: saved sector copy
 db   $AA               ; $139D: T/S list position
 db   $BA               ; $139E: T/S list max index
 db   $A0               ; $139F: catalog entries remaining
 db   $CD               ; $13A0: filename match start pos
 db   $A0               ; $13A1: filename match end pos
 db   $A0               ; $13A2: filename end position
 db   $8D               ; $13A3: forward match position
 db   $BA               ; $13A4: saved forward match pos
 db   $C0               ; $13A5: forward catalog match pos
 db   $E3               ; $13A6: reverse catalog match pos
 db   $A0               ; $13A7: saved forward catalog pos
 db   $A9               ; $13A8: match result flags
 db   $AE               ; $13A9: wildcard '=' present flag
 db   $A0               ; $13AA: prompting mode flag
 db   $AF               ; $13AB: file-was-selected flag
 db   $A2               ; $13AC: menu selection character
 db   $CF               ; $13AD: operation mode (0/1/2)
 db   $85               ; $13AE: menu selection index (0-8)

; --- Menu Option Characters ($13AF-$13B8) ---
; "123456789\0" - valid menu selection characters.
; Searched by find_in_table at various offsets.

 db   $B1, $B2, $B3, $B4  ; $13AF: "1234"
 db   $B5, $B6, $B7, $B8  ; $13B3: "5678"
 db   $B9               ; $13B7: "9"
 db   $00               ; $13B8: null terminator

; --- Input Validation Sub-tables ($13B9-$13C9) ---
; Sub-tables within the menu_options area, accessed via
; find_in_table with X = offset from $13AF.

; Options needing no disk init (offset $0A from $13AF):
; Menu options 7=RESET SLOT, 9=QUIT
 db   $B7, $B9  ; $13B9: "79"
 db   $00               ; $13BB: null terminator

; File operation options (offset $0D from $13AF):
; 6=DELETE, 2=CATALOG, 5=LOCK, 3=SPACE, 4=UNLOCK, 8=VERIFY
 db   $B6, $B2, $B5, $B3  ; $13BC: "6253"
 db   $B4, $B8  ; $13C0: "48"
 db   $00               ; $13C2: null terminator

; Copy-only option (offset $14 from $13AF):
 db   $B1               ; $13C3: "1"
 db   $00               ; $13C4: null terminator

; Alt-path options (offset $16 from $13AF):
; 2=CATALOG, 7=RESET, 3=SPACE, 9=QUIT
 db   $B2, $B7, $B3, $B9  ; $13C5: "2739"
 db   $00               ; $13C9: null terminator

; --- RTS Dispatch Table ($13CA-$13DB) ---
; 9 entries, each is (target_address - 1) for the RTS trick.
; Indexed by menu selection (0-8).
;
; Idx  Menu Option           Target
; ---  --------------------  ------
;  0   COPY FILES             $0E66
;  1   CATALOG                $0DAA
;  2   SPACE ON DISK          $0DD8
;  3   UNLOCK FILES           $0D97
;  4   LOCK FILES             $0D84
;  5   DELETE FILES           $0D69
;  6   RESET SLOT & DRIVE     $0DB3
;  7   VERIFY FILES           $0DBE
;  8   QUIT                   $0DCC

 db   $65, $0E  ; $13CA: Entry 0: $0E66-1 (COPY FILES)
 db   $A9, $0D  ; $13CC: Entry 1: $0DAA-1 (CATALOG)
 db   $D7, $0D  ; $13CE: Entry 2: $0DD8-1 (SPACE ON DISK)
 db   $96, $0D  ; $13D0: Entry 3: $0D97-1 (UNLOCK FILES)
 db   $83, $0D  ; $13D2: Entry 4: $0D84-1 (LOCK FILES)
 db   $68, $0D  ; $13D4: Entry 5: $0D69-1 (DELETE FILES)
 db   $B2, $0D  ; $13D6: Entry 6: $0DB3-1 (RESET SLOT & DRIVE)
 db   $BD, $0D  ; $13D8: Entry 7: $0DBE-1 (VERIFY FILES)
 db   $CB, $0D  ; $13DA: Entry 8: $0DCC-1 (QUIT)

; --- DOS Parameter Block Pointers ($13DC-$13E7) ---
; Addresses and parameters used by DOS file manager calls.

 db   $51               ; $13DC: catalog format ptr low
 db   $19               ; $13DD: catalog format ptr high
 db   $51               ; $13DE: T/S list format param
 db   $1B               ; $13DF: additional ptr low
 db   $51               ; $13E0: additional ptr high
 db   $1C               ; $13E1: format parameter
 db   $51               ; $13E2: format parameter
 db   $1A               ; $13E3: format parameter
 db   $51               ; $13E4: T/S list data ptr low
 db   $1D               ; $13E5: T/S list data ptr high
 db   $3C               ; $13E6: RWTS entry point low ($96)
 db   $19               ; $13E7: RWTS entry point high ($C3)

; --- String Pointer Table ($13E8-$1449) ---
; 49 little-endian word pointers to null-terminated Apple II strings.
; Indexed by print_string: X = string number, internally doubled.

; Prompt strings:
 dw   $144A              ; $13E8: [ 0] "SOURCE SLOT?"
 dw   $1457              ; $13EA: [ 1] "      DRIVE?"
 dw   $1464              ; $13EC: [ 2] "DESTINATION SLOT?"
 dw   $1476              ; $13EE: [ 3] "           DRIVE?"
 dw   $1488              ; $13F0: [ 4] "FILENAME?"
 dw   $1492              ; $13F2: [ 5] "INSERT DISKS...PRESS <ESC>..."

; Display format strings:
 dw   $1326              ; $13F4: [ 6] Catalog file display format
 dw   $14E0              ; $13F6: [ 7] "\nALREADY EXISTS.\n"

; Error/status strings:
 dw   $1563              ; $13F8: [ 8] "ERROR.   CODE="
 dw   $1572              ; $13FA: [ 9] "\nWOULD YOU LIKE TO MAKE ANOTHER COPY?"
 dw   $134B              ; $13FC: [10] Filename prompt format

; Disk swap prompts:
 dw   $1599              ; $13FE: [11] "\nINSERT SOURCE DISK AND PRESS A KEY"
 dw   $15BD              ; $1400: [12] "\nINSERT DESTINATION DISK..."

; Operation prompts:
 dw   $15E7              ; $1402: [13] "DO YOU WANT PROMPTING?"
 dw   $15FF              ; $1404: [14] "DONE\n"
 dw   $1605              ; $1406: [15] "NO FILES SELECTED\n"

; Error messages:
 dw   $1619              ; $1408: [16] "DISK FULL\n"
 dw   $1624              ; $140A: [17] "DISK WRITE PROTECTED\n"
 dw   $163A              ; $140C: [18] "FILE LOCKED\n"
 dw   $1647              ; $140E: [19] "I/O ERROR\n"
 dw   $1652              ; $1410: [20] "INVALID FILENAME"
 dw   $1663              ; $1412: [21] "INSUFFICIENT MEMORY..."

; Banner/title strings:
 dw   $1689              ; $1414: [22] FID banner (top half)
 dw   $172A              ; $1416: [23] FID banner (bottom) + menu intro

; User interaction:
 dw   $17C9              ; $1418: [24] "PRESS ANY KEY TO CONTINUE"
 dw   $14F3              ; $141A: [25] "TYPE IN A NEW FILE NAME..."
 dw   $17E4              ; $141C: [26] "CANCELLED\n"
 dw   $17EF              ; $141E: [27] " SECTORS FREE\n"
 dw   $17FE              ; $1420: [28] " SECTORS USED\n\n"
 dw   $180E              ; $1422: [29] "DO YOU WISH TO REPLACE IT ANYWAY?"
 dw   $1831              ; $1424: [30] "UNCOPYABLE FILE\n"

; Menu display formatting:
 dw   $1844              ; $1426: [31] "        <"
 dw   $184E              ; $1428: [32] ">   "
 dw   $1853              ; $142A: [33] "WHICH WOULD YOU LIKE?"
 dw   $186A              ; $142C: [34] "INVALID SLOT"
 dw   $1877              ; $142E: [35] "INVALID DRIVE"

; Menu option names (indices 36-48 = options 1-9):
 dw   $1885              ; $1430: [36] "COPY FILES\n"
 dw   $1885              ; $1432: [37] "COPY FILES\n" (dup)
 dw   $1885              ; $1434: [38] "COPY FILES\n" (dup)
 dw   $1885              ; $1436: [39] "COPY FILES\n" (dup)
 dw   $1885              ; $1438: [40] "COPY FILES\n" (dup)
 dw   $189F              ; $143A: [41] "CATALOG\n"
 dw   $18C8              ; $143C: [42] "SPACE ON DISK\n"
 dw   $18D7              ; $143E: [43] "UNLOCK FILES\n"
 dw   $18A8              ; $1440: [44] "LOCK FILES\n"
 dw   $1891              ; $1442: [45] "DELETE FILES\n"
 dw   $18B4              ; $1444: [46] "RESET SLOT & DRIVE\n"
 dw   $18E5              ; $1446: [47] "VERIFY FILES\n"
 dw   $18F3              ; $1448: [48] "QUIT\n"

; --- Apple II Text Strings ($144A-$18F8) ---
; Null-terminated strings with high bit set on each character.
; Decoded text shown in comments.

 @apple2_str "SOURCE SLOT?"  ; $144A
 @apple2_str "      DRIVE?"  ; $1457
 @apple2_str "DESTINATION SLOT?"  ; $1464
 @apple2_str "           DRIVE?"  ; $1476
 @apple2_str "FILENAME?"  ; $1488
 @apple2_str "INSERT DISKS.  PRESS <ESC> TO RETURN TO  MAIN MENU OR ANY OTHER KEY TO BEGIN\n"  ; $1492
 @apple2_str "\nALREADY EXISTS. \n"  ; $14E0
 @apple2_str "TYPE IN A NEW FILE NAME FOR THE COPY OR\n<RETURN> TO REPLACE EXISTING FILE OR\n<CTRL-C><RETURN> TO CANCEL COPY\n:"  ; $14F3
 db   $00  ; $1562: "\0"
 @apple2_str "ERROR.   CODE="  ; $1563
 @apple2_str "\nWOULD YOU LIKE TO MAKE ANOTHER COPY? "  ; $1572
 @apple2_str "\nINSERT SOURCE DISK AND PRESS A KEY"  ; $1599
 @apple2_str "\nINSERT DESTINATION DISK AND PRESS A KEY "  ; $15BD
 @apple2_str "DO YOU WANT PROMPTING? "  ; $15E7
 @apple2_str "DONE\n"  ; $15FF
 @apple2_str "NO FILES SELECTED\x87\n"  ; $1605
 @apple2_str "DISK FULL\n"  ; $1619
 @apple2_str "DISK WRITE PROTECTED\n"  ; $1624
 @apple2_str "FILE LOCKED\n"  ; $163A
 @apple2_str "I/O ERROR\n"  ; $1647
 @apple2_str "INVALID FILENAME"  ; $1652
 @apple2_str "\x87\x87INSUFFICIENT MEMORY TO RUN PROGRAM\n"  ; $1663
 @apple2_str "*****************************************        APPLE ][ FILE DEVELOPER       **                                      **             FID VERSION M            *"  ; $1689
 @apple2_str "*                                      **  COPYRIGHT 1979 APPLE COMPUTER INC.  *****************************************\nCHOOSE ONE OF THE FOLLOWING OPTIONS\n\n"  ; $172A
 @apple2_str "PRESS ANY KEY TO CONTINUE "  ; $17C9
 @apple2_str "CANCELLED\n"  ; $17E4
 @apple2_str " SECTORS FREE\n"  ; $17EF
 @apple2_str " SECTORS USED\n\n"  ; $17FE
 @apple2_str "DO YOU WISH TO REPLACE IT ANYWAY? "  ; $180E
 @apple2_str "\x87\x87UNCOPYABLE FILE\n"  ; $1831
 @apple2_str "        <"  ; $1844
 @apple2_str ">   "  ; $184E
 @apple2_str "WHICH WOULD YOU LIKE? "  ; $1853
 @apple2_str "INVALID SLOT"  ; $186A
 @apple2_str "INVALID DRIVE"  ; $1877
 @apple2_str "COPY FILES\n"  ; $1885
 @apple2_str "DELETE FILES\n"  ; $1891
 @apple2_str "CATALOG\n"  ; $189F
 @apple2_str "LOCK FILES\n"  ; $18A8
 @apple2_str "RESET SLOT & DRIVE\n"  ; $18B4
 @apple2_str "SPACE ON DISK\n"  ; $18C8
 @apple2_str "UNLOCK FILES\n"  ; $18D7
 @apple2_str "VERIFY FILES\n"  ; $18E5
 @apple2_str "QUIT\n"  ; $18F3

; --- DOS File Manager Parameter List ($18F9-$1A50) ---
; This area contains the DOS 3.3 file manager parameter list
; and working buffers. Laid out per the DOS 3.3 RWTS interface.
; Initial values here are from the binary; most are overwritten.

 db   $A0, $00, $01, $00, $00, $B0, $98, $CD  ; $18F9: operation code
 db   $2B, $13, $A0, $A0, $0F, $19, $51, $1B  ; $1901
 db   $51, $1D, $B0, $A0, $89, $D3, $F0, $96  ; $1909: Q.0 .Sp.
 db   $C3, $A0, $8D, $A0, $D2, $A0, $E8, $9F  ; $1911: C \n R h.
 db   $A0, $85, $A0, $AA, $D3, $D5, $99, $A0  ; $1919:  . *SU.
 db   $A9, $A0, $E8, $A0, $8C, $A0, $A0, $A0  ; $1921: ) h .
 db   $A0, $EF, $B3, $D3, $D0, $C5, $C3, $A2  ; $1929:  o3SPEC"
 db   $A0, $E8, $A0, $B9, $BA, $E9, $B0, $A0  ; $1931:  h 9:i0
 db   $8A, $A0, $8C, $01, $A0, $B3, $00, $D1  ; $1939
 db   $A0, $4D, $19, $A0, $A2, $85, $C5, $A0  ; $1941:  M. ".E
 db   $A0, $A0, $A0, $AA, $00, $01, $EF, $D8  ; $1949:    *..oX
 db   $02, $A0, $B8, $02, $00, $00, $00, $B9  ; $1951
 db   $A0, $A6, $A0, $A0, $F0, $BB, $A9, $A0  ; $1959:  &  p;)
 db   $90, $88, $A0, $89, $C3, $A9, $C8, $B0  ; $1961: .. .C)H0
 db   $EF, $A0, $A2, $A0, $E5, $A0, $A4, $A0  ; $1969: o " e $
 db   $A0, $C8, $A0, $A5, $A0, $FA, $A0, $7A  ; $1971:  H % z z
 db   $A0, $85, $B3, $90, $C9, $C8, $A5, $A0  ; $1979:  .3.IH%
 db   $11, $01, $00, $00, $A0, $D6, $00, $01  ; $1981
 db   $C5, $83, $A0, $E8, $A0, $A0, $B0, $AE  ; $1989: E. h  0.
 db   $A2, $A0, $E6, $A0, $A0, $CF, $A0, $FB  ; $1991: " f  O {
 db   $A0, $E7, $A0, $A0, $80, $A0, $A0, $C5  ; $1999:  g  .  E
 db   $AA, $A0, $82, $B1, $A0, $89, $A0, $F0  ; $19A1: * .1 . p
 db   $A0, $A0, $BA, $A4, $A0, $A0, $E8, $A0  ; $19A9:   :$  h
 db   $89, $A0, $A0, $CA, $B1, $85, $A0, $CC  ; $19B1: .  J1. L
 db   $A0, $A0, $9F, $A0, $C5, $B2, $8A, $C8  ; $19B9:   . E2.H
 db   $C5, $85, $A0, $91, $D3, $AC, $C6, $A0  ; $19C1: E. .S,F
 db   $85, $C5, $A0, $A0, $E8, $A0, $A0, $C6  ; $19C9: .E  h  F
 db   $A0, $A2, $AA, $A9, $A0, $A0, $CF, $A0  ; $19D1:  "*)  O
 db   $85, $CD, $E5, $A0, $A0, $80, $A0, $F0  ; $19D9: .Me  . p
 db   $A0, $81, $A0, $A5, $B0, $A0, $98, $A0  ; $19E1:  . %0 .
 db   $A5, $A0, $A0, $BA, $A4, $80, $A0, $87  ; $19E9: %  :$. .
 db   $A0, $89, $A0, $A0, $AF, $B2, $85, $A0  ; $19F1:  .  /2.
 db   $BA, $A0, $C9, $85, $CE, $81, $A7, $C3  ; $19F9: : I.N.'C
 db   $AA, $C5, $A6, $A0, $C6, $A5, $A0, $97  ; $1A01: *E& F% .
 db   $A0, $98, $A0, $C4, $FF, $B3, $97, $B1  ; $1A09:  . D.3.1
 db   $E5, $A0, $A0, $A9, $A0, $A9, $B2, $97  ; $1A11: e  ) )2.
 db   $C9, $D1, $A5, $D4, $80, $A0, $85, $B0  ; $1A19: IQ%T. .0
 db   $D5, $B0, $D1, $C0, $C5, $A5, $B3, $A0  ; $1A21: U0Q@E%3
 db   $B0, $D5, $9E, $A0, $F0, $A0, $A0, $C5  ; $1A29: 0U. p  E
 db   $A0, $85, $A0, $85, $A0, $C5, $D2, $C3  ; $1A31:  . . ERC
 db   $8A, $C4, $A8, $A0, $C8, $98, $B1, $A0  ; $1A39: .D( H.1
 db   $A0, $A0, $A0, $A6, $A0, $C6, $B8, $AE  ; $1A41:    & F8.
 db   $97, $A0, $B0, $A0, $C4, $FF, $B4, $97  ; $1A49: . 0 D.4.

; ============================================================================
; END OF APPLE II FID (FILE DEVELOPER) VERSION M
; ============================================================================
; Total binary size: 4686 bytes ($124E)
; Load address: $0803
; End address:  $1A50
; Round-trip verified: byte-for-byte identical
