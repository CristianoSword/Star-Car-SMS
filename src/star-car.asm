; ============================================================
; STAR-CAR - Step 1: Road with Vertical Scroll
; ============================================================

; ------------------------------------------------------------
; MEMORY MAP
; ------------------------------------------------------------
.memorymap
defaultslot 0
slotsize $8000
slot 0 $0000
slot 1 $8000
.endme

.rombankmap
bankstotal 1
banksize $8000
banks 1
.endro

; ------------------------------------------------------------
; VARIABLES IN RAM
; ------------------------------------------------------------
.enum $c000
scroll  db              ; Vertical scroll buffer (1 byte)
input   db              ; Player controller state
.ende

; ------------------------------------------------------------
; CONSTANTS
; ------------------------------------------------------------
.equ vspeed 2           ; Vertical speed (scroll)

; ------------------------------------------------------------
; ROM START
; ------------------------------------------------------------
.bank 0 slot 0
.org $0000

; Reset - entry point
di                      ; Disable interrupts
im 1                    ; Interrupt mode 1
jp main                 ; Jump to main

; ------------------------------------------------------------
; FRAME INTERRUPT (V-BLANK)
; ------------------------------------------------------------
.org $0038
ex af,af'               ; Save accumulator in shadow register
in a,($bf)              ; Read VDP status / satisfy interrupt
ex af,af'               ; Restore accumulator
ei                      ; Enable interrupts
ret                     ; Return from interrupt

; ------------------------------------------------------------
; MAIN PROGRAM
; ------------------------------------------------------------
.org $0100

main:
    di                  ; Disable interrupts
    ld sp,$dff0         ; Stack pointer
    
    ; 1. Initialize VDP (Display OFF)
    call init_vdp
    
    ; 2. Load Palette (CRAM) - CRITICAL: Must use CRAM write command
    call load_palette
    
    ; 3. Load Tiles (VRAM)
    call load_tiles
    
    ; 4. Draw Road (Name Table)
    call draw_road
    
    ; 5. Initialize Variables
    xor a
    ld (scroll),a
    
    ; 6. Turn ON Display
    ; Reg 1: Display ON, V-Int ON, Mode 4 ($E0 = 11100000)
    ld a,$E0
    ld b,1
    call setreg
    
    ei                  ; Enable interrupts

; ------------------------------------------------------------
; MAIN LOOP
; ------------------------------------------------------------
mloop:
    halt                ; Wait for V-blank
    
    ; Update VDP with scroll buffer
    ld a,(scroll)
    ld b,9              ; Reg 9: Vertical Scroll
    call setreg

    ; Update scroll buffer (movement)
    ld a,(scroll)
    sub vspeed          ; Move up
    ld (scroll),a

    jp mloop

; ------------------------------------------------------------
; SUBROUTINES
; ------------------------------------------------------------

; Initialize RAM (clear)
init_ram:
    ld hl,$c000         ; Start of RAM
    ld bc,$2000         ; 8KB of RAM
    xor a               ; A = 0
-:  ld (hl),a
    inc hl
    dec bc
    ld a,b
    or c
    jp nz,-
    ret

; Initialize VDP (registers)
init_vdp:
    ld hl,vdp_init_data
    ld b,11             ; 11 registers (0-10)
    ld c,0              ; Register counter (starts at 0)
-:  ld a,(hl)
    out ($bf),a         ; Send data
    ld a,c
    or $80              ; Set register write command bit
    out ($bf),a         ; Send register index
    inc hl
    inc c
    djnz -
    ret

; VDP initialization data
vdp_init_data:
.db %00000100           ; Reg 0: Mode 4
.db %10000000           ; Reg 1: Display OFF, V-Int ON, Mode 4
.db $0E                 ; Reg 2: Name Table ($3800)
.db $FF                 ; Reg 3: Color Table (unused)
.db $FF                 ; Reg 4: Pattern Gen (unused)
.db $7E                 ; Reg 5: Sprite Attr ($3F00)
.db $FB                 ; Reg 6: Sprite Patt ($2000)
.db $00                 ; Reg 7: Border Color (Black)
.db $00                 ; Reg 8: Scroll X
.db $00                 ; Reg 9: Scroll Y
.db $FF                 ; Reg 10: Line Int (OFF)

; Set VDP register
; A = value, B = register number
setreg:
    out ($bf),a
    ld a,b
    or $80
    out ($bf),a
    ret

; Prepare VRAM for writing
; HL = address in VRAM
vrampr:
    ld a,l
    out ($bf),a         ; Low byte of address
    ld a,h
    or $40              ; Set bit 14 (write command)
    out ($bf),a         ; High byte + command
    ret

; Load tiles into VRAM
load_tiles:
    ld hl,$0000         ; Destination address in VRAM
    call vrampr
    
    ld hl,tiles         ; Source data
    ld bc,tiles_end - tiles  ; Size
    ld de,$be           ; VDP data port
-:  ld a,(hl)
    out ($be),a
    inc hl
    dec bc
    ld a,b
    or c
    jp nz,-
    ret

; Prepare CRAM for writing (Palette)
; HL = address in CRAM (usually $0000 for color 0)
crampr:
    ld a,l
    out ($bf),a         ; Low byte of address
    ld a,h
    or $C0              ; Set bits 14 and 15 (CRAM write command)
    out ($bf),a         ; High byte + command
    ret

; Load palette
load_palette:
    ld hl,$0000         ; Palette index 0
    call crampr
    
    ; Color palette (16 colors)
    ld hl,palette_data
    ld b,16
-:  ld a,(hl)
    out ($be),a
    inc hl
    djnz -
    ret

palette_data:
.db $00                 ; Color 0: Transparent (black)
.db $11                 ; Color 1: Dark Purple (R=1, G=0, B=1)
.db $3F                 ; Color 2: White (R=3, G=3, B=3)
.db $33                 ; Color 3: Light Purple (R=3, G=0, B=3)
.db $00,$00,$00,$00     ; Colors 4-7 (not used)
.db $00,$00,$00,$00     ; Colors 8-11 (not used)
.db $00,$00,$00,$00     ; Colors 12-15 (not used)

; Draw road on name table
draw_road:
    ld hl,$3800         ; Name table in VRAM
    call vrampr
    
    ld b,28             ; 28 lines height
-:  push bc
    
    ; Left border (tile 3)
    ld a,3
    out ($be),a         ; Low byte (Tile Index)
    xor a
    out ($be),a         ; High byte (Attributes = 0)
    
    ; 6 road tiles (tile 1)
    ld c,6
--: ld a,1
    out ($be),a         ; Low byte
    xor a
    out ($be),a         ; High byte
    dec c
    jp nz,--
    
    ; Center line (tile 2)
    ld a,2
    out ($be),a         ; Low byte
    xor a
    out ($be),a         ; High byte
    
    ld a,2
    out ($be),a         ; Low byte
    xor a
    out ($be),a         ; High byte
    
    ; 6 road tiles (tile 1)
    ld c,6
--: ld a,1
    out ($be),a         ; Low byte
    xor a
    out ($be),a         ; High byte
    dec c
    jp nz,--
    
    ; Right border (tile 3)
    ld a,3
    out ($be),a         ; Low byte
    xor a
    out ($be),a         ; High byte
    
    ; Complete line with empty tiles (tile 0)
    ld c,16
--: xor a
    out ($be),a         ; Low byte (0)
    out ($be),a         ; High byte (0)
    dec c
    jp nz,--
    
    pop bc
    djnz -
    ret

; Include tiles (must be before header to fit in bank 0)
.include "src/tiles.inc"

; ------------------------------------------------------------
; SMS HEADER (required at $7FF0-$7FFF)
; ------------------------------------------------------------
.org $7FF0
.db "TMR SEGA"            ; Header signature
.dw $0000                 ; Checksum (not used in homebrew)
.db $00,$00,$00           ; Product code + version
.db $4C                   ; Region code + ROM size ($4C = Export, 32KB)
