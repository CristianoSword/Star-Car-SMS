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
.equ highvp $c000          ; Primeiro vpos do hi-score
.equ scorvp $c004          ; Primeiro vpos do score
.equ plrvp  $c008          ; Primeiro vpos do player
.equ maevp  $c018          ; Primeiro vpos da Mae
.equ ashvp  $c028          ; Primeiro vpos do Ash

.equ highhp $c080          ; Primeiro hpos do hi-score
.equ highcc $c081          ; Primeiro char code do hi-score
.equ scorhp $c088          ; Primeiro hpos do score
.equ scorcc $c089          ; Primeiro char code do score
.equ plrhp  $c090          ; Primeiro hpos do player
.equ plrcc  $c091          ; Primeiro char code do player
.equ maehp  $c0b0          ; Primeiro hpos da Mae
.equ maecc  $c0b1          ; Primeiro char code da Mae
.equ ashhp  $c0d0          ; Primeiro hpos do Ash
.equ ashcc  $c0d1          ; Primeiro char code do Ash

.enum $c100
scroll  db              ; Vertical scroll buffer (1 byte)
input   db              ; Player controller state
oldinp  db              ; Estado anterior do controle
status  db              ; Last VDP status read in interrupt
vblank  db              ; Flag de frame pronto
gstate  db              ; Estado atual do jogo
gtimer  db              ; Temporizador do estado atual
score0  db              ; Score: unidades
score1  db              ; Score: dezenas
score2  db              ; Score: centenas
score3  db              ; Score: milhares
hisc0   db              ; Hi-score: unidades
hisc1   db              ; Hi-score: dezenas
hisc2   db              ; Hi-score: centenas
hisc3   db              ; Hi-score: milhares
scdiv   db              ; Divisor para ritmo do score
sfxid   db              ; Efeito sonoro atual
sfxtim  db              ; Duração restante do efeito sonoro
plx     db              ; Player X position
ply     db              ; Player Y position
ashdir  db              ; Enemy direction (0=left, 1=right)
ashy    db              ; Enemy Y position
ashx    db              ; Enemy X position
maedel  db              ; Delay before second enemy becomes visible
maedir  db              ; Enemy direction (0=left, 1=right)
maey    db              ; Enemy Y position
maex    db              ; Enemy X position
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
.equ sctick 6           ; Quantos frames por ponto de score
.equ deadwait 90        ; Duração da tela de morte

.equ st_title 0         ; Tela inicial
.equ st_ready 1         ; Tela pronta para iniciar
.equ st_play 2          ; Gameplay ativo
.equ st_dead 3          ; Tela de morte

.equ sfx_none 0         ; Sem efeito sonoro
.equ sfx_start 1        ; Bip de início
.equ sfx_crash 2        ; Bip de colisão

.equ tile_digit0 32     ; Primeiro tile de dígito
.equ tile_h 42          ; Letras do HUD
.equ tile_i 43
.equ tile_s 44
.equ tile_c 45
.equ tile_a 46          ; Letras da UI
.equ tile_d 47
.equ tile_e 48
.equ tile_g 49
.equ tile_m 50
.equ tile_o 51
.equ tile_p 52
.equ tile_r 53
.equ tile_t 54
.equ tile_v 55
.equ tile_y 56
.equ tile_dash 57

; SAT buffer map for the player car (first 16 sprites)

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
ld a,1
ld (vblank),a           ; Sinaliza que um frame começou
ex af,af'               ; Restore accumulator
ei                      ; Enable interrupts
ret                     ; Return from interrupt

; NMI do botão Pause: apenas retorna
.org $0066
retn

; ------------------------------------------------------------
; MAIN PROGRAM
; ------------------------------------------------------------
.org $0100

main:
    di                  ; Disable interrupts
    ld sp,$dff0         ; Stack pointer
    call init_ram       ; Clear RAM used by buffers and variables
    call psg_silence    ; Garante áudio desligado no boot
    
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
    call prep_title
    
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
    call wait_vblank    ; Espera um frame real
    
    ; Push sprite buffer and scroll during vblank
    call ldsat
    ld a,(scroll)
    ld b,9              ; Reg 9: Vertical Scroll
    call setreg

    call getkey
    call update_sfx
    call run_state
    call sync_input

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
    ld (oldinp),a
    ld (gstate),a
    ld (gtimer),a
    ld (sfxid),a
    ld (sfxtim),a
    call reset_round
    call clear_sat
    call init_car_tiles
    call init_hud
    call reset_score
    call update_hud
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

; Zera o score atual
reset_score:
    xor a
    ld (score0),a
    ld (score1),a
    ld (score2),a
    ld (score3),a
    ld a,sctick
    ld (scdiv),a
    ret

; Mantém o espelho do input para detectar borda do botão
sync_input:
    ld a,(input)
    ld (oldinp),a
    ret

; Testa borda de descida do botão 1 (ativo em zero)
btn1_edge:
    ld a,(input)
    bit 4,a
    jp nz,btn1_no

    ld a,(oldinp)
    bit 4,a
    jp z,btn1_no

    ld a,1
    ret

btn1_no:
    xor a
    ret

; Read controller 1
getkey:
    in a,($dc)
    ld (input),a
    ret

; Espera até o frame interrupt sinalizar vblank
wait_vblank:
    xor a
    ld (vblank),a
wait_vblank_loop:
    halt
    ld a,(vblank)
    or a
    jp z,wait_vblank_loop
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
    ld hl,highvp
    ld b,64
    ld a,$d0
clear_sat_y:
    ld (hl),a
    inc hl
    djnz clear_sat_y

    ld hl,highhp
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

; Inicializa as posições fixas do HUD em sprites
init_hud:
    ld hl,hud_y_data
    ld de,highvp
    ld b,8
init_hud_y_loop:
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    djnz init_hud_y_loop

    ld hl,hud_xc_data
    ld de,highhp
    ld b,16
init_hud_xc_loop:
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    djnz init_hud_xc_loop
    ret

; Atualiza os dígitos do hi-score e do score atual
update_hud:
    ld a,(hisc3)
    add a,tile_digit0
    ld (highcc+0),a
    ld a,(hisc2)
    add a,tile_digit0
    ld (highcc+2),a
    ld a,(hisc1)
    add a,tile_digit0
    ld (highcc+4),a
    ld a,(hisc0)
    add a,tile_digit0
    ld (highcc+6),a

    ld a,(score3)
    add a,tile_digit0
    ld (scorcc+0),a
    ld a,(score2)
    add a,tile_digit0
    ld (scorcc+2),a
    ld a,(score1)
    add a,tile_digit0
    ld (scorcc+4),a
    ld a,(score0)
    add a,tile_digit0
    ld (scorcc+6),a
    ret

; Atualiza score em BCD
step_score:
    ld a,(scdiv)
    dec a
    ld (scdiv),a
    ret nz

    ld a,sctick
    ld (scdiv),a

    ld a,(score0)
    inc a
    cp 10
    jp c,score_store0
    xor a
    ld (score0),a

    ld a,(score1)
    inc a
    cp 10
    jp c,score_store1
    xor a
    ld (score1),a

    ld a,(score2)
    inc a
    cp 10
    jp c,score_store2
    xor a
    ld (score2),a

    ld a,(score3)
    inc a
    cp 10
    jp c,score_store3
    ld a,9
    ld (score0),a
    ld (score1),a
    ld (score2),a

score_store3:
    ld (score3),a
    jp score_done

score_store2:
    ld (score2),a
    jp score_done

score_store1:
    ld (score1),a
    jp score_done

score_store0:
    ld (score0),a

score_done:
    call sync_hiscore
    call update_hud
    ret

; Atualiza o hi-score se o score atual passou
sync_hiscore:
    ld a,(score3)
    ld b,a
    ld a,(hisc3)
    cp b
    jp c,copy_hiscore
    jp nz,no_hiscore

    ld a,(score2)
    ld b,a
    ld a,(hisc2)
    cp b
    jp c,copy_hiscore
    jp nz,no_hiscore

    ld a,(score1)
    ld b,a
    ld a,(hisc1)
    cp b
    jp c,copy_hiscore
    jp nz,no_hiscore

    ld a,(score0)
    ld b,a
    ld a,(hisc0)
    cp b
    jp c,copy_hiscore

no_hiscore:
    ret

copy_hiscore:
    ld a,(score0)
    ld (hisc0),a
    ld a,(score1)
    ld (hisc1),a
    ld a,(score2)
    ld (hisc2),a
    ld a,(score3)
    ld (hisc3),a
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
    ld (ashvp+16),a      ; Terminador após hi, score, player, Mae e Ash
    ret

; Despacha a lógica conforme o estado atual
run_state:
    ld a,(gstate)
    cp st_title
    jp z,state_title
    cp st_ready
    jp z,state_ready
    cp st_play
    jp z,state_play
    jp state_dead

; Tela inicial
state_title:
    xor a
    ld (scroll),a
    call btn1_edge
    or a
    ret z
    call prep_ready
    ret

; Tela antes da corrida
state_ready:
    xor a
    ld (scroll),a
    call btn1_edge
    or a
    ret z
    call prep_play
    ret

; Gameplay principal
state_play:
    call check_collision
    ld a,(gstate)
    cp st_play
    ret nz

    call move_player
    ld ix,ashdir
    call enemy
    ld ix,maedir
    call enemy
    call handle_mae
    call step_score
    call upbuf

    ld a,(scroll)
    sub vspeed
    ld (scroll),a
    ret

; Tela de morte com retorno automático
state_dead:
    xor a
    ld (scroll),a
    ld a,(gtimer)
    or a
    jp z,dead_to_title
    dec a
    ld (gtimer),a
    ret

dead_to_title:
    call prep_title
    ret

; Prepara a tela inicial
prep_title:
    xor a
    ld (gstate),a
    ld (scroll),a
    call reset_round
    ld a,$ff
    ld (maedel),a
    call init_car_tiles
    ld hl,car_tiles
    ld de,maecc
    call load_carcc
    ld a,48
    ld (plx),a
    ld a,128
    ld (ply),a
    ld a,24
    ld (ashx),a
    ld a,48
    ld (ashy),a
    ld a,72
    ld (maex),a
    ld a,88
    ld (maey),a
    call draw_title_screen
    call update_hud
    call upbuf
    ret

; Prepara a tela de ready e um novo jogo
prep_ready:
    ld a,st_ready
    ld (gstate),a
    xor a
    ld (scroll),a
    call reset_round
    call reset_score
    call init_car_tiles
    call draw_ready_screen
    call update_hud
    call upbuf
    ret

; Entra em gameplay
prep_play:
    ld a,st_play
    ld (gstate),a
    xor a
    ld (scroll),a
    call draw_road
    call start_sfx_start
    call upbuf
    ret

; Prepara a tela de morte
prep_dead:
    ld a,st_dead
    ld (gstate),a
    ld a,deadwait
    ld (gtimer),a
    xor a
    ld (scroll),a
    call draw_dead_screen
    call start_sfx_crash
    ret

; Detecta colisão e troca de estado
check_collision:
    ld a,(status)
    bit 5,a
    ret z

    call prep_dead
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
    ld hl,highvp
    otir

    ld hl,$3f80
    call vrampr
    ld b,128
    ld c,$be
    ld hl,highhp
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

; Limpa toda a name table
clear_name_table:
    ld hl,$3800
    call vrampr
    ld bc,$0700
clear_name_loop:
    xor a
    out ($be),a
    dec bc
    ld a,b
    or c
    jp nz,clear_name_loop
    ret

; Desenha uma string terminada em $ff na VRAM
; HL = endereço na VRAM, DE = ponteiro da string
draw_text:
    call vrampr
draw_text_loop:
    ld a,(de)
    cp $ff
    ret z
    out ($be),a
    xor a
    out ($be),a
    inc de
    jp draw_text_loop

; Tela inicial
draw_title_screen:
    call clear_name_table
    call draw_road
    ld hl,$3924
    ld de,title_starcar
    call draw_text
    ld hl,$3a64
    ld de,title_press1
    call draw_text
    ret

; Tela de pronta para iniciar
draw_ready_screen:
    call clear_name_table
    call draw_road
    ld hl,$3a26
    ld de,txt_ready
    call draw_text
    ld hl,$3b64
    ld de,title_press1
    call draw_text
    ret

; Tela de game over
draw_dead_screen:
    call clear_name_table
    call draw_road
    ld hl,$3a28
    ld de,txt_game
    call draw_text
    ld hl,$3aa8
    ld de,txt_over
    call draw_text
    ret

; Desliga todos os canais do PSG
psg_silence:
    ld a,$9f
    out ($7f),a
    ld a,$bf
    out ($7f),a
    ld a,$df
    out ($7f),a
    ld a,$ff
    out ($7f),a
    ret

; Inicia um bip curto de start
start_sfx_start:
    call psg_silence
    ld a,sfx_start
    ld (sfxid),a
    ld a,10
    ld (sfxtim),a
    ld a,$80
    out ($7f),a
    ld a,$04
    out ($7f),a
    ld a,$94
    out ($7f),a
    ret

; Inicia um ruído simples de colisão
start_sfx_crash:
    call psg_silence
    ld a,sfx_crash
    ld (sfxid),a
    ld a,18
    ld (sfxtim),a
    ld a,$e6
    out ($7f),a
    ld a,$f2
    out ($7f),a
    ret

; Conta o tempo do efeito atual
update_sfx:
    ld a,(sfxtim)
    or a
    ret z
    dec a
    ld (sfxtim),a
    ret nz
    xor a
    ld (sfxid),a
    call psg_silence
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
    
    ; Carrega as duas paletas: fundo e sprites
    ld hl,palette_data
    ld b,32
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
.db $00                 ; Sprite color 0: transparência
.db $33                 ; Sprite color 1: magenta
.db $1B                 ; Sprite color 2: coral
.db $22                 ; Sprite color 3: roxo
.db $00,$00,$00,$00     ; Sprite colors 4-7
.db $00,$00,$00,$00     ; Sprite colors 8-11
.db $00,$00,$00,$00     ; Sprite colors 12-15

; Draw road on name table
draw_road:
    ld hl,$3800         ; Name table in VRAM
    call vrampr
    
    ld b,32             ; 32 linhas para o scroll vertical não revelar lixo
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

hud_y_data:
.db 8,8,8,8
.db 24,24,24,24

hud_xc_data:
.db 152,tile_digit0,160,tile_digit0,168,tile_digit0,176,tile_digit0
.db 152,tile_digit0,160,tile_digit0,168,tile_digit0,176,tile_digit0

title_starcar:
.db tile_s,tile_t,tile_a,tile_r,tile_dash,tile_c,tile_a,tile_r,$ff

title_press1:
.db tile_p,tile_r,tile_e,tile_s,tile_s,0,tile_digit0+1,$ff

txt_ready:
.db tile_r,tile_e,tile_a,tile_d,tile_y,$ff

txt_game:
.db tile_g,tile_a,tile_m,tile_e,$ff

txt_over:
.db tile_o,tile_v,tile_e,tile_r,$ff

txt_hi:
.db tile_h,tile_i,$ff

txt_sc:
.db tile_s,tile_c,$ff

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
