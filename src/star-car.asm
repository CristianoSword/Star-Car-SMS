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
    ld sp,$dff0         ; Initialize stack pointer

    ; Initialize RAM
    call init_ram

    ; Initialize VDP
    call init_vdp

    ; Load tiles into VRAM
    call load_tiles

    ; Load palette
    call load_palette

    ; Draw road on name table
    call draw_road

    ; Initialize game variables
    xor a
    ld (scroll),a       ; Scroll starts at 0

    ; Turn on display
    ld a,%11100000      ; Display ON, frame interrupt ON
    ld b,1              ; VDP register 1
    call setreg

    ei                  ; Enable interrupts

; ------------------------------------------------------------
; MAIN LOOP
; ------------------------------------------------------------
mloop:
    halt                ; Wait for V-blank (frame interrupt)

    ; Update VDP with scroll buffer
    ld a,(scroll)       ; Load scroll value
    ld b,9              ; VDP register 9 (vertical scroll)
    call setreg         ; Update VDP register

    ; Update scroll buffer (movement)
    ld a,(scroll)       ; Load current scroll
    sub vspeed          ; Subtract vertical speed
    ld (scroll),a       ; Save new value

    jp mloop            ; Infinite loop

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
    ld c,0              ; Register counter
-:  ld a,(hl)
    push bc
    ld b,c
    call setreg
    pop bc
    inc hl
    inc c
    djnz -
    ret

; VDP initialization data
vdp_init_data:
.db %00000110           ; Reg 0: Mode control 1
.db %10000000           ; Reg 1: Mode control 2 (display OFF)
.db $ff                 ; Reg 2: Name table = $3800
.db $ff                 ; Reg 3: Color table (not used)
.db $ff                 ; Reg 4: Pattern table (not used)
.db $ff                 ; Reg 5: Sprite attr table = $3f00
.db $ff                 ; Reg 6: Sprite pattern table = $2000
.db $00                 ; Reg 7: Border color (black)
.db $00                 ; Reg 8: Scroll X = 0
.db $00                 ; Reg 9: Scroll Y = 0
.db $ff                 ; Reg 10: Line interrupt (disabled)

; Set VDP register
; A = value, B = register number
setreg:
    out ($bf),a         ; Send value
    ld a,$80
    or b
    out ($bf),a         ; Send command
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

; Load palette
load_palette:
    ld hl,$c000         ; Palette address (CRAM)
    call vrampr
    
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
.db $05                 ; Color 1: Dark purple
.db $3f                 ; Color 2: White
.db $15                 ; Color 3: Light purple
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
    out ($be),a
    
    ; 6 road tiles (tile 1)
    ld c,6
--: ld a,1
    out ($be),a
    dec c
    jp nz,--
    
    ; Center line (tile 2)
    ld a,2
    out ($be),a
    ld a,2
    out ($be),a
    
    ; 6 road tiles (tile 1)
    ld c,6
--: ld a,1
    out ($be),a
    dec c
    jp nz,--
    
    ; Right border (tile 3)
    ld a,3
    out ($be),a
    
    ; Complete line with empty tiles
    ld c,16
--: xor a
    out ($be),a
    dec c
    jp nz,--
    
    pop bc
    djnz -
    ret

; Include tiles
.include "src/tiles.inc"
