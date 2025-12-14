; ============================================================
; RACER - Step 1: Estrada com Scroll Vertical
; Tutorial baseado em SMS Power - Create a Racing Game
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
scroll  db              ; Buffer do scroll vertical (1 byte)
input   db              ; Estado do controle do jogador
.ende

; ------------------------------------------------------------
; CONSTANTS
; ------------------------------------------------------------
.equ vspeed 2           ; Velocidade vertical (scroll)

; ------------------------------------------------------------
; ROM START
; ------------------------------------------------------------
.bank 0 slot 0
.org $0000

; Reset - ponto de entrada
di                      ; Desabilita interrupções
im 1                    ; Interrupt mode 1
jp main                 ; Pula para main

; ------------------------------------------------------------
; FRAME INTERRUPT (V-BLANK)
; ------------------------------------------------------------
.org $0038
ex af,af'               ; Salva acumulador em shadow register
in a,($bf)              ; Lê VDP status / satisfaz interrupção
ex af,af'               ; Restaura acumulador
ei                      ; Reabilita interrupções
ret                     ; Retorna da interrupção

; ------------------------------------------------------------
; MAIN PROGRAM
; ------------------------------------------------------------
.org $0100

main:
    ld sp,$dff0         ; Inicializa stack pointer

    ; Inicializa RAM
    call init_ram

    ; Inicializa VDP
    call init_vdp

    ; Carrega tiles na VRAM
    call load_tiles

    ; Carrega paleta
    call load_palette

    ; Desenha estrada no name table
    call draw_road

    ; Inicializa variáveis do jogo
    xor a
    ld (scroll),a       ; Scroll começa em 0

    ; Liga display
    ld a,%11100000      ; Display ON, frame interrupt ON
    ld b,1              ; VDP register 1
    call setreg

    ei                  ; Habilita interrupções

; ------------------------------------------------------------
; MAIN LOOP
; ------------------------------------------------------------
mloop:
    halt                ; Aguarda V-blank (frame interrupt)

    ; Atualiza VDP com buffer de scroll
    ld a,(scroll)       ; Carrega valor do scroll
    ld b,9              ; VDP register 9 (vertical scroll)
    call setreg         ; Atualiza registro da VDP

    ; Atualiza buffer de scroll (movimento)
    ld a,(scroll)       ; Carrega scroll atual
    sub vspeed          ; Subtrai velocidade vertical
    ld (scroll),a       ; Salva novo valor

    jp mloop            ; Loop infinito

; ------------------------------------------------------------
; SUBROUTINES
; ------------------------------------------------------------

; Inicializa RAM (limpa)
init_ram:
    ld hl,$c000         ; Início da RAM
    ld bc,$2000         ; 8KB de RAM
    xor a               ; A = 0
-:  ld (hl),a
    inc hl
    dec bc
    ld a,b
    or c
    jp nz,-
    ret

; Inicializa VDP (registros)
init_vdp:
    ld hl,vdp_init_data
    ld b,11             ; 11 registros (0-10)
    ld c,0              ; Contador de registro
-:  ld a,(hl)
    push bc
    ld b,c
    call setreg
    pop bc
    inc hl
    inc c
    djnz -
    ret

; Dados de inicialização da VDP
vdp_init_data:
.db %00000110           ; Reg 0: Mode control 1
.db %10000000           ; Reg 1: Mode control 2 (display OFF)
.db $ff                 ; Reg 2: Name table = $3800
.db $ff                 ; Reg 3: Color table (não usado)
.db $ff                 ; Reg 4: Pattern table (não usado)
.db $ff                 ; Reg 5: Sprite attr table = $3f00
.db $ff                 ; Reg 6: Sprite pattern table = $2000
.db $00                 ; Reg 7: Border color (preto)
.db $00                 ; Reg 8: Scroll X = 0
.db $00                 ; Reg 9: Scroll Y = 0
.db $ff                 ; Reg 10: Line interrupt (desabilitado)

; Define registro da VDP
; A = valor, B = número do registro
setreg:
    out ($bf),a         ; Envia valor
    ld a,$80
    or b
    out ($bf),a         ; Envia comando
    ret

; Prepara VRAM para escrita
; HL = endereço na VRAM
vrampr:
    ld a,l
    out ($bf),a         ; Byte baixo do endereço
    ld a,h
    or $40              ; Set bit 14 (comando de escrita)
    out ($bf),a         ; Byte alto + comando
    ret

; Carrega tiles na VRAM
load_tiles:
    ld hl,$0000         ; Endereço destino na VRAM
    call vrampr
    
    ld hl,tiles         ; Origem dos dados
    ld bc,tiles_end - tiles  ; Tamanho
    ld de,$be           ; Porta de dados da VDP
-:  ld a,(hl)
    out ($be),a
    inc hl
    dec bc
    ld a,b
    or c
    jp nz,-
    ret

; Carrega paleta
load_palette:
    ld hl,$c000         ; Endereço da paleta (CRAM)
    call vrampr
    
    ; Paleta de cores (16 cores)
    ld hl,palette_data
    ld b,16
-:  ld a,(hl)
    out ($be),a
    inc hl
    djnz -
    ret

palette_data:
.db $00                 ; Cor 0: Transparente (preto)
.db $05                 ; Cor 1: Roxo escuro
.db $3f                 ; Cor 2: Branco
.db $15                 ; Cor 3: Roxo claro
.db $00,$00,$00,$00     ; Cores 4-7 (não usadas)
.db $00,$00,$00,$00     ; Cores 8-11 (não usadas)
.db $00,$00,$00,$00     ; Cores 12-15 (não usadas)

; Desenha estrada no name table
draw_road:
    ld hl,$3800         ; Name table na VRAM
    call vrampr
    
    ld b,28             ; 28 linhas de altura
-:  push bc
    
    ; Borda esquerda (tile 3)
    ld a,3
    out ($be),a
    
    ; 6 tiles da estrada (tile 1)
    ld c,6
--: ld a,1
    out ($be),a
    dec c
    jp nz,--
    
    ; Linha central (tile 2)
    ld a,2
    out ($be),a
    ld a,2
    out ($be),a
    
    ; 6 tiles da estrada (tile 1)
    ld c,6
--: ld a,1
    out ($be),a
    dec c
    jp nz,--
    
    ; Borda direita (tile 3)
    ld a,3
    out ($be),a
    
    ; Completar linha com tiles vazios
    ld c,16
--: xor a
    out ($be),a
    dec c
    jp nz,--
    
    pop bc
    djnz -
    ret

; Incluir tiles
.include "tiles.inc"

