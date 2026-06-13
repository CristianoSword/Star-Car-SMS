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
status  db              ; Last VDP status read in interrupt
plx     db              ; Player X position
ply     db              ; Player Y position
ashdir  db              ; Enemy direction (0=left, 1=right)
ashy    db              ; Enemy Y position
ashx    db              ; Enemy X position
maedel  db              ; Delay before second enemy becomes visible
maedir  db              ; Enemy direction (0=left, 1=right)
maey    db              ; Enemy Y position
maex    db              ; Enemy X position
saty    ds 64           ; Sprite Y buffer (64 sprites max)
satxt   ds 128          ; Sprite X/tile buffer
.ende

; ------------------------------------------------------------
; CONSTANTS
; ------------------------------------------------------------
.equ vspeed 2           ; Vertical speed (scroll)
.equ hspeed 2           ; Horizontal speed (player)
.equ espeed 2           ; Vertical speed of enemy cars
.equ leftb 8            ; Left border inside the road
.equ rightb 88          ; Right border inside the road
.equ plrini_x 48        ; Initial player X
.equ plrini_y 144       ; Initial player Y
.equ ashini_x 24        ; Initial enemy X
.equ ashini_y 16        ; Initial enemy Y
.equ ashini_dir 1       ; Enemy starts moving right
.equ maeini_x 72        ; Initial second enemy X
.equ maeini_y 88        ; Initial second enemy Y
.equ maeini_dir 0       ; Second enemy starts moving left
.equ maewait 96         ; Delay before second enemy appears

; SAT buffer map for the player car (first 16 sprites)
.equ plrvp saty
.equ plrhp satxt
.equ plrcc satxt+1
.equ ashvp saty+16
.equ ashhp satxt+32
.equ ashcc satxt+33
.equ maevp saty+32
.equ maehp satxt+64
.equ maecc satxt+65

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
ld (status),a           ; Mirror status for later collision/debug use
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
    call init_ram       ; Clear RAM used by buffers and variables
    
    ; 1. Initialize VDP (Display OFF)
    call init_vdp
    
    ; 2. Load Palette (CRAM) - CRITICAL: Must use CRAM write command
    call load_palette
    
    ; 3. Load Tiles (VRAM)
    call load_tiles
    call load_sprite_tiles
    
    ; 4. Draw Road (Name Table)
    call draw_road
    
    ; 5. Initialize game variables and sprite buffer
    call init_game
    call ldsat
    
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
    
    ; Push sprite buffer and scroll during vblank
    call ldsat
    ld a,(scroll)
    ld b,9              ; Reg 9: Vertical Scroll
    call setreg

    ; Read input and update gameplay state in RAM
    call check_collision
    call getkey
    call move_player
    ld ix,ashdir
    call enemy
    ld ix,maedir
    call enemy
    call handle_mae
    call upbuf

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
    ld bc,$1fe0         ; Leave top RAM bytes free for stack usage
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

; Initialize gameplay variables and SAT buffer
init_game:
    xor a
    ld (scroll),a
    call reset_round
    call clear_sat
    call init_car_tiles
    call upbuf
    ret

; Reset round positions after boot or collision
reset_round:
    ld a,plrini_x
    ld (plx),a
    ld a,plrini_y
    ld (ply),a

    ld a,ashini_dir
    ld (ashdir),a
    ld a,ashini_y
    ld (ashy),a
    ld a,ashini_x
    ld (ashx),a

    ld a,maewait
    ld (maedel),a
    ld a,maeini_dir
    ld (maedir),a
    ld a,maeini_y
    ld (maey),a
    ld a,maeini_x
    ld (maex),a
    ret

; Read controller 1
getkey:
    in a,($dc)
    ld (input),a
    ret

; Move player left/right inside the road bounds
move_player:
    ld a,(input)
    bit 3,a             ; Right pressed? (active low)
    jp nz,check_left

    ld a,(plx)
    cp rightb
    jp nc,check_left

    add a,hspeed
    ld (plx),a
    jp move_done

check_left:
    ld a,(input)
    bit 2,a             ; Left pressed? (active low)
    jp nz,move_done

    ld a,(plx)
    cp leftb
    jp c,move_done

    ld b,hspeed
    sub b
    ld (plx),a

move_done:
    ret

; Clear SAT buffer: hide all sprites, clear X/tile area
clear_sat:
    ld hl,saty
    ld b,64
    ld a,$d0
clear_sat_y:
    ld (hl),a
    inc hl
    djnz clear_sat_y

    ld hl,satxt
    ld b,128
    xor a
clear_sat_xt:
    ld (hl),a
    inc hl
    djnz clear_sat_xt
    ret

; Initialize player and enemy sprite char codes once
init_car_tiles:
    ld hl,car_tiles
    ld de,plrcc
    call load_carcc

    ld hl,car_tiles
    ld de,ashcc
    call load_carcc

    ld hl,invcar
    ld de,maecc
    call load_carcc
    ret

; Load 16 sprite character codes into SAT X/tile buffer
; HL = source tile list, DE = first SAT char code byte
load_carcc:
    ld b,16
load_carcc_loop:
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    inc de
    djnz load_carcc_loop
    ret

; Update SAT buffer from player and enemy coordinates
upbuf:
    ld a,(ply)
    ld hl,plrvp
    call cary

    ld a,(plx)
    ld hl,plrhp
    call carx

    ld a,(ashy)
    ld hl,ashvp
    call cary

    ld a,(ashx)
    ld hl,ashhp
    call carx

    ld a,(maey)
    ld hl,maevp
    call cary

    ld a,(maex)
    ld hl,maehp
    call carx

    ld a,$d0
    ld (saty+48),a       ; Terminator after player + two enemy cars
    ret

; Reset the round when sprites collide
check_collision:
    ld a,(status)
    bit 5,a
    ret z

    call reset_round
    call init_car_tiles
    call upbuf
    ret

; Handle delayed visibility of the second enemy
handle_mae:
    ld a,(maedel)
    cp $ff
    ret z

    cp 0
    jp nz,mae_tick

    ld hl,car_tiles
    ld de,maecc
    call load_carcc
    ld a,$ff
    ld (maedel),a
    ret

mae_tick:
    ld hl,maedel
    dec (hl)
    ret

; Convert a car Y coordinate into 16 sprite Y values
; A = Y coordinate, HL = first sprite Y buffer byte
cary:
    ld b,4
cary_push_rows:
    push af
    push af
    push af
    push af
    add a,8
    djnz cary_push_rows

    ld de,15
    add hl,de
    ld b,16
cary_pop_rows:
    pop af
    ld (hl),a
    dec hl
    djnz cary_pop_rows
    ret

; Convert a car X coordinate into 16 sprite X values
; A = X coordinate, HL = first sprite X buffer byte
carx:
    ld c,a
    .rept 4
    ld a,c
    ld b,4
-:  ld (hl),a
    inc hl
    inc hl
    add a,8
    djnz -
    .endr
    ret

; Copy RAM SAT buffer to VRAM SAT
ldsat:
    ld hl,$3f00
    call vrampr
    ld b,64
    ld c,$be
    ld hl,saty
    otir

    ld hl,$3f80
    call vrampr
    ld b,128
    ld c,$be
    ld hl,satxt
    otir
    ret

; Update enemy direction and position
; IX = enemy block: dir, y, x
enemy:
    ld a,(ix+0)
    cp 0
    jp nz,enemy_right

    ld a,(ix+2)
    cp leftb
    jp nc,enemy_move_left

    ld a,1
    ld (ix+0),a
    jp enemy_vertical

enemy_move_left:
    ld b,hspeed
    ld a,(ix+2)
    sub b
    ld (ix+2),a
    jp enemy_vertical

enemy_right:
    ld a,(ix+2)
    cp rightb
    jp c,enemy_move_right

    xor a
    ld (ix+0),a
    jp enemy_vertical

enemy_move_right:
    ld b,hspeed
    ld a,(ix+2)
    add a,b
    ld (ix+2),a

enemy_vertical:
    ld a,(ix+1)
    add a,espeed
    cp 177
    jp c,enemy_store_y
    xor a
enemy_store_y:
    ld (ix+1),a
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

; Load the same tile set into the sprite pattern area
load_sprite_tiles:
    ld hl,$2000
    call vrampr

    ld hl,tiles
    ld bc,tiles_end - tiles
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

car_tiles:
.db 16,17,18,19
.db 20,21,22,23
.db 24,25,26,27
.db 28,29,30,31

invcar:
.db 0,0,0,0
.db 0,0,0,0
.db 0,0,0,0
.db 0,0,0,0

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
