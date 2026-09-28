; ============================================================================
;  gfx.asm -- 320x200x256 double buffered VGA output
;  Primitives draw into the back buffer (BACKBUF); gfx_present() blits it to
;  video memory.  The frame loop repaints the whole screen every tick, so no
;  damage tracking is required.
; ============================================================================

%define SCRW        320
%define SCRH        200
%define FB          0xA0000
%define HORIZON     120

; --- palette ---------------------------------------------------------------
C_BLACK   equ 0
C_DKGRAY  equ 1
C_GRAY    equ 2
C_LTGRAY  equ 3
C_WHITE   equ 4
C_NAVY    equ 5
C_BLUE    equ 6
C_TEAL    equ 7
C_GREEN   equ 8
C_LIME    equ 9
C_BROWN   equ 10
C_GOLD    equ 11
C_ORANGE  equ 12
C_RED     equ 13
C_PINK    equ 14
C_PURPLE  equ 15

; ---------------------------------------------------------------------------
;  GLYPH x, y, char, fg, bg   -- draw one 8x8 character
;  clobbers eax, ebp, ecx; saves esi, edi, edx, ebx
; ---------------------------------------------------------------------------
%macro GLYPH 5
    push ebp
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi
    movzx esi, byte %3
    shl esi, 3
    add esi, font8x8
    ; %1 is x and is sometimes edi itself, so snapshot it into eax before edi
    ; is reused for the row address -- reading %1 afterwards would pick up the
    ; address instead of x and "add edi, edi" would double the offset.
    mov eax, %1
    mov edi, %2
    imul edi, SCRW
    add edi, BACKBUF
    add edi, eax
    mov ebx, %4
    mov edx, %5
    mov ecx, 8
%%row:
    push ecx
    movzx eax, byte [esi]
    mov ebp, 7                      ; bit 7 is the leftmost font pixel
    mov ecx, 8
%%px:
    mov byte [edi], dl              ; opaque bg under every glyph pixel
    ;  Walk bit 7 downwards without shifting: "shl eax, 1" takes CF from bit 31
    ;  in BITS 32, and "shr" would already move the bit we are about to look at.
    bt eax, ebp
    jnc %%no
    mov byte [edi], bl
%%no:
    dec ebp
    inc edi
    dec ecx
    jnz %%px
    add edi, SCRW - 8
    inc esi
    pop ecx
    dec ecx
    jnz %%row
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    pop ebp
%endmacro

; ---------------------------------------------------------------------------
;  gfx_init
; ---------------------------------------------------------------------------
gfx_init:
    mov dx, 0x3C8                  ; DAC write index
    xor ecx, ecx
    mov esi, palette               ; 16 entries of r, g, b
.lp:
    mov al, cl
    out dx, al
    inc dx                         ; 0x3C9 = DAC data
    lodsb
    out dx, al
    lodsb
    out dx, al
    lodsb
    out dx, al
    dec dx
    inc ecx
    cmp ecx, 16
    jb .lp
    call build_ramps
    ret

; ---------------------------------------------------------------------------
;  build_ramps -- fill DAC entries 16..255 with interpolated colour ramps.
;  Each descriptor is 8 bytes: base, count, r0, g0, b0, r1, g1, b1.
;  Entry i of a ramp is  start + ((end - start) * i) >> 4.
;  The static 16 base colours are left untouched so every existing
;  C_* constant keeps working.
; ---------------------------------------------------------------------------
build_ramps:
    push ebp
    push eax
    push ebx
    push ecx
    push edx
    push esi
    mov esi, ramp_defs
.rd:
    mov al, [esi]
    cmp al, 0xFF
    je .fin
    movzx ebx, byte [esi + 1]     ; step count
    xor ecx, ecx                 ; step index
.step:
    cmp ecx, ebx
    jae .rd_next
    mov dx, 0x3C8
    mov al, [esi]
    add al, cl
    out dx, al
    inc dx                        ; 0x3C9, DAC data
    movzx bp, byte [esi + 2]
    movzx ax, byte [esi + 5]
    sub ax, bp
    imul ax, cx
    sar ax, 4                   ; 16 intervals; top step lands 1 unit short
    add ax, bp                    ; AX now holds 0..255
    out dx, al
    movzx bp, byte [esi + 3]
    movzx ax, byte [esi + 6]
    sub ax, bp
    imul ax, cx
    sar ax, 4
    add ax, bp                    ; AX now holds 0..255
    out dx, al
    movzx bp, byte [esi + 4]
    movzx ax, byte [esi + 7]
    sub ax, bp
    imul ax, cx
    sar ax, 4
    add ax, bp                    ; AX now holds 0..255
    out dx, al
    inc ecx
    jmp .step
.rd_next:
    add esi, 8
    jmp .rd
.fin:
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    pop ebp
    ret

ramp_defs:
    ;  DAC components are 6 bits, so every value here is 0..63.
    db  16, 16,   2,  5, 12,   38,  50,  62   ; 16  blue
    db  32, 16,   1,  9, 10,   33,  56,  55   ; 32  teal
    db  48, 16,   2,  8,  4,   38,  55,  30   ; 48  green
    db  64, 16,  10,  7,  2,   62,  51,  23   ; 64  gold
    db  80, 16,  11,  5,  2,   62,  37,  15   ; 80  orange
    db  96, 16,  11,  3,  3,   60,  27,  27   ; 96  red
    db 112, 16,  12,  3,  8,   61,  37,  50   ; 112 pink
    db 128, 16,   7,  4, 12,   46,  37,  60   ; 128 purple
    db 144, 16,   3,  3,  4,   58,  58,  60   ; 144 light neutral
    db 160, 16,   1,  1,  2,   24,  24,  27   ; 160 dark neutral
    db 0xFF

; ---------------------------------------------------------------------------
;  gfx_present -- back buffer -> video memory
; ---------------------------------------------------------------------------
gfx_present:
    push esi
    push edi
    push ecx
    mov esi, BACKBUF
    mov edi, FB
    mov ecx, SCRW * SCRH / 2
    cld
    rep movsw
    pop ecx
    pop edi
    pop esi
    ret

; ---------------------------------------------------------------------------
;  gfx_px(x, y, colour)
; ---------------------------------------------------------------------------
gfx_px:
    push ebp
    mov ebp, esp
    mov eax, [ebp+8]
    cmp eax, SCRW
    jae .out
    mov edx, [ebp+12]
    cmp edx, SCRH
    jae .out
    imul edx, SCRW
    add edx, BACKBUF
    add edx, eax
    mov al, [ebp+16]
    mov [edx], al
.out:
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  gfx_get(x, y) -> al
; ---------------------------------------------------------------------------
gfx_get:
    push ebp
    mov ebp, esp
    mov eax, [ebp+8]
    cmp eax, SCRW
    jae .out
    mov edx, [ebp+12]
    cmp edx, SCRH
    jae .out
    imul edx, SCRW
    add edx, BACKBUF
    add edx, eax
    movzx eax, byte [edx]
.out:
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  gfx_hline(x, y, w, colour)
; ---------------------------------------------------------------------------
gfx_hline:
    push ebp
    mov ebp, esp
    push ebx
    push edi
    mov edi, [ebp+8]
    mov ebx, [ebp+16]
    mov ecx, [ebp+12]
    cmp edi, SCRW
    jge .out
    cmp ecx, SCRH
    jge .out
    test ebx, ebx
    jz .out
    mov eax, SCRW
    sub eax, edi
    cmp ebx, eax
    jle .ok
    mov ebx, eax
.ok:
    imul ecx, SCRW
    mov eax, ecx
    add eax, BACKBUF
    add eax, edi
    mov edi, eax
    mov al, [ebp+20]
    mov ecx, ebx
    cld
    rep stosb
.out:
    pop edi
    pop ebx
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  gfx_vline(x, y, h, colour)
; ---------------------------------------------------------------------------
gfx_vline:
    push ebp
    mov ebp, esp
    push ebx
    push edi
    mov edi, [ebp+8]
    mov ebx, [ebp+16]
    mov ecx, [ebp+12]
    cmp edi, SCRW
    jge .out
    cmp ecx, SCRH
    jge .out
    test ebx, ebx
    jz .out
    mov eax, SCRH
    sub eax, ecx
    cmp ebx, eax
    jle .ok
    mov ebx, eax
.ok:
    imul edi, SCRW
    add edi, BACKBUF
    add edi, [ebp+8]
    mov al, [ebp+20]
.loop:
    mov [edi], al
    add edi, SCRW
    dec ebx
    jnz .loop
.out:
    pop edi
    pop ebx
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  gfx_fill(x, y, w, h, colour)   -- clipped to the screen
; ---------------------------------------------------------------------------
gfx_fill:
    push ebp
    mov ebp, esp
    push ebx
    push esi
    push edi
    push edx
    push ecx
    mov esi, [ebp+8]               ; x
    mov edi, [ebp+12]               ; y
    mov ebx, [ebp+16]              ; w
    mov ecx, [ebp+20]              ; h
    mov eax, [ebp+24]              ; colour
    cmp esi, SCRW
    jge .out
    cmp edi, SCRH
    jge .out
    test ebx, ebx
    jz .out
    test ecx, ecx
    jz .out
    mov edx, SCRW
    sub edx, esi
    cmp ebx, edx
    jle .w_ok
    mov ebx, edx
.w_ok:
    mov edx, SCRH
    sub edx, edi
    cmp ecx, edx
    jle .h_ok
    mov ecx, edx
.h_ok:
    mov edx, ecx
    mov edi, [ebp+12]
    imul edi, SCRW
    add edi, BACKBUF
    add edi, esi
.row:
    mov ecx, ebx
    rep stosb
    add edi, SCRW
    sub edi, ebx
    dec edx
    jnz .row
.out:
    pop ecx
    pop edx
    pop edi
    pop esi
    pop ebx
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  gfx_bevel(x, y, w, h, light, face)  -- raised panel
; ---------------------------------------------------------------------------
gfx_bevel:
    push ebp
    mov ebp, esp
    push dword [ebp+28]
    push dword [ebp+20]
    push dword [ebp+16]
    push dword [ebp+12]
    push dword [ebp+8]
    call gfx_fill
    add esp, 20
    push dword [ebp+24]
    push dword [ebp+16]
    push dword [ebp+12]
    push dword [ebp+8]
    call gfx_hline
    add esp, 16
    push dword [ebp+24]
    push dword [ebp+20]
    push dword [ebp+12]
    push dword [ebp+8]
    call gfx_vline
    add esp, 16
    push dword [ebp+28]
    push dword [ebp+16]
    mov eax, [ebp+12]
    add eax, [ebp+20]
    dec eax
    push eax
    push dword [ebp+8]
    call gfx_hline
    add esp, 16
    push dword [ebp+28]
    push dword [ebp+20]
    push dword [ebp+12]
    mov eax, [ebp+8]
    add eax, [ebp+16]
    dec eax
    push eax
    call gfx_vline
    add esp, 16
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  gfx_sunken(x, y, w, h, light, face)  -- pressed-in panel
; ---------------------------------------------------------------------------
gfx_sunken:
    push ebp
    mov ebp, esp
    push dword [ebp+28]
    push dword [ebp+20]
    push dword [ebp+16]
    push dword [ebp+12]
    push dword [ebp+8]
    call gfx_fill
    add esp, 20
    push dword [ebp+28]
    push dword [ebp+16]
    push dword [ebp+12]
    push dword [ebp+8]
    call gfx_hline
    add esp, 16
    push dword [ebp+28]
    push dword [ebp+20]
    push dword [ebp+12]
    push dword [ebp+8]
    call gfx_vline
    add esp, 16
    push dword [ebp+24]
    push dword [ebp+16]
    mov eax, [ebp+12]
    add eax, [ebp+20]
    dec eax
    push eax
    push dword [ebp+8]
    call gfx_hline
    add esp, 16
    push dword [ebp+24]
    push dword [ebp+20]
    push dword [ebp+12]
    mov eax, [ebp+8]
    add eax, [ebp+16]
    dec eax
    push eax
    call gfx_vline
    add esp, 16
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  gfx_frame(x, y, w, h, colour)  -- 1px outline
; ---------------------------------------------------------------------------
gfx_frame:
    push ebp
    mov ebp, esp
    push dword [ebp+24]
    push dword [ebp+16]
    push dword [ebp+12]
    push dword [ebp+8]
    call gfx_hline
    add esp, 16
    push dword [ebp+24]
    push dword [ebp+16]
    mov eax, [ebp+12]
    add eax, [ebp+20]
    dec eax
    push eax
    push dword [ebp+8]
    call gfx_hline
    add esp, 16
    push dword [ebp+24]
    push dword [ebp+20]
    push dword [ebp+12]
    push dword [ebp+8]
    call gfx_vline
    add esp, 16
    push dword [ebp+24]
    push dword [ebp+20]
    push dword [ebp+12]
    mov eax, [ebp+8]
    add eax, [ebp+16]
    dec eax
    push eax
    call gfx_vline
    add esp, 16
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  gfx_shadow(x, y, w, h)  -- 2 tone drop shadow
; ---------------------------------------------------------------------------
gfx_shadow:
    push ebp
    mov ebp, esp
    push dword C_DKGRAY
    push dword [ebp+16]
    add dword [esp], 1
    mov eax, [ebp+12]
    add eax, [ebp+20]
    push eax
    mov eax, [ebp+8]
    add eax, 1
    push eax
    call gfx_hline
    add esp, 16
    push dword C_DKGRAY
    push dword [ebp+20]
    add dword [esp], 1
    push dword [ebp+12]
    add dword [esp], 1
    mov eax, [ebp+8]
    add eax, [ebp+16]
    push eax
    call gfx_vline
    add esp, 16
    push dword C_BLACK
    push dword [ebp+16]
    add dword [esp], 2
    mov eax, [ebp+12]
    add eax, [ebp+20]
    add eax, 1
    push eax
    mov eax, [ebp+8]
    add eax, 2
    push eax
    call gfx_hline
    add esp, 16
    push dword C_BLACK
    push dword [ebp+20]
    add dword [esp], 1
    push dword [ebp+12]
    add dword [esp], 2
    mov eax, [ebp+8]
    add eax, [ebp+16]
    add eax, 1
    push eax
    call gfx_vline
    add esp, 16
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  gfx_char(x, y, char, fg, bg)
; ---------------------------------------------------------------------------
gfx_char:
    push ebp
    mov ebp, esp
    GLYPH dword [ebp+8], dword [ebp+12], byte [ebp+16], dword [ebp+20], dword [ebp+24]
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  gfx_text(x, y, str, fg, bg)  -- honours \n, clipped to the screen
; ---------------------------------------------------------------------------
gfx_text:
    push ebp
    mov ebp, esp
    push ebx
    push esi
    push edi
    push edx
    push ecx
    mov esi, [ebp+16]
    mov edi, [ebp+8]
    mov edx, [ebp+12]
    mov ebx, [ebp+20]
    mov ecx, [ebp+24]
.ch:
    movzx eax, byte [esi]
    test al, al
    jz .out
    inc esi
    cmp al, 10
    jne .print
    mov edi, [ebp+8]
    add edx, 8
    jmp .ch
.print:
    cmp edi, SCRW
    jge .out
    cmp edx, SCRH
    jge .out
    GLYPH edi, edx, al, ebx, ecx
    add edi, 8
    jmp .ch
.out:
    pop ecx
    pop edx
    pop edi
    pop esi
    pop ebx
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  gfx_text_n(x, y, str, n, fg, bg)  -- at most n characters
; ---------------------------------------------------------------------------
gfx_text_n:
    push ebp
    mov ebp, esp
    sub esp, 8
    mov eax, [ebp+32]
    mov [ebp-4], eax              ; bg
    mov eax, [ebp+20]
    mov [ebp-8], eax              ; count
    push ebx
    push esi
    push edi
    push edx
    push ecx
    mov esi, [ebp+16]
    mov edi, [ebp+8]
    mov edx, [ebp+12]
    mov ebx, [ebp+24]
.ch:
    mov ecx, [ebp-8]
    test ecx, ecx
    jz .out
    dec dword [ebp-8]
    movzx eax, byte [esi]
    test al, al
    jz .out
    inc esi
    cmp edi, SCRW
    jge .out
    cmp edx, SCRH
    jge .out
    GLYPH edi, edx, al, ebx, [ebp-4]
    add edi, 8
    jmp .ch
.out:
    pop ecx
    pop edx
    pop edi
    pop esi
    pop ebx
    add esp, 8
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  gfx_len(str) -> eax
; ---------------------------------------------------------------------------
gfx_len:
    push esi
    mov esi, [esp+8]
    xor eax, eax
.lp:
    cmp byte [esi], 0
    je .done
    inc esi
    inc eax
    jmp .lp
.done:
    pop esi
    ret

; ---------------------------------------------------------------------------
;  gfx_textc(cx, y, str, fg, bg)  -- centred on cx
; ---------------------------------------------------------------------------
gfx_textc:
    push ebp
    mov ebp, esp
    push ebx
    mov ebx, [ebp+16]
    push ebx
    call gfx_len
    add esp, 4
    shl eax, 2
    sub dword [ebp+8], eax
    push dword [ebp+24]
    push dword [ebp+20]
    push dword [ebp+16]
    push dword [ebp+12]
    push dword [ebp+8]
    call gfx_text
    add esp, 20
    pop ebx
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  gfx_sprite(x, y, w, h, src, zoom)  -- palette index 0 is transparent
;  Locals: [ebp-4] rows left, [ebp-8] columns that fit, [ebp-12] source stride
; ---------------------------------------------------------------------------
gfx_sprite:
    push ebp
    mov ebp, esp
    sub esp, 20
    push ebx
    push esi
    push edi
    push edx
    push ecx
    ; [ebp+8] x, [ebp+12] y, [ebp+16] w, [ebp+20] h, [ebp+24] src, [ebp+28] zoom
    mov eax, [ebp + 12]
    test eax, eax
    js .out
    cmp eax, SCRH
    jge .out
    mov eax, [ebp + 8]
    test eax, eax
    js .out
    cmp eax, SCRW
    jge .out
    mov eax, [ebp + 16]
    mov [ebp - 12], eax             ; source stride
    ; rows that fit
    mov eax, SCRH
    sub eax, [ebp + 12]
    mov ecx, [ebp + 28]
    xor edx, edx
    div ecx
    cmp eax, [ebp + 20]
    jae .rowsok                     ; all requested rows fit -- keep h
    mov [ebp + 20], eax             ; otherwise clamp h to what fits
.rowsok:
    mov eax, [ebp + 20]
    mov [ebp - 4], eax
    ; columns that fit
    mov eax, SCRW
    sub eax, [ebp + 8]
    mov ecx, [ebp + 28]
    xor edx, edx
    div ecx
    cmp eax, [ebp - 12]
    jle .colsok
    mov eax, [ebp - 12]
.colsok:
    mov [ebp - 8], eax
    ; --- draw ---
    mov esi, [ebp + 24]
    mov edi, BACKBUF
    mov eax, [ebp + 12]             ; y * SCRW
    imul eax, SCRW
    add edi, eax
    add edi, [ebp + 8]
    mov [ebp - 16], edi             ; start of this destination row
.srow:
    mov ebx, [ebp + 28]             ; vertical zoom
    mov edi, [ebp - 16]
.vrow:
    mov edx, [ebp - 8]              ; columns
.crow:
    movzx eax, byte [esi]
    test al, al
    jz .cskip
    mov ecx, [ebp + 28]
.hz:
    mov [edi], al
    inc edi
    dec ecx
    jnz .hz
.cskip:
    inc esi
    dec edx
    jnz .crow
    ; skip whatever is left of this source row
    mov eax, [ebp - 12]
    sub eax, [ebp - 8]
    add esi, eax
    dec ebx
    jnz .vrow
    add dword [ebp - 16], SCRW      ; next scanline
    dec dword [ebp - 4]
    jnz .srow
.out:
    pop ecx
    pop edx
    pop edi
    pop esi
    pop ebx
    leave
    ret

; ---------------------------------------------------------------------------
;  gfx_copy(dst, src, n)  -- raw back buffer blit
; ---------------------------------------------------------------------------
gfx_copy:
    push ebp
    mov ebp, esp
    push esi
    push edi
    push ecx
    mov edi, [ebp+8]
    mov esi, [ebp+12]
    mov ecx, [ebp+16]
    cld
    rep movsb
    pop ecx
    pop edi
    pop esi
    pop ebp
    ret


; ---------------------------------------------------------------------------
;  palette (16 entries, 3 bytes each: r, g, b)
; ---------------------------------------------------------------------------
; ---------------------------------------------------------------------------
;  gfx_vgrad(x, y, w, h, c0, c1) -- fill with a vertical gradient.
;  Row i takes colour  base + c0 + ((c1 - c0) * i) / (h - 1).
;  Requires c1 >= c0; it draws one horizontal slice per row.
; ---------------------------------------------------------------------------
gfx_vgrad:
    push ebp
    mov ebp, esp
    push ebx
    push esi
    push edi
    push edx
    push ecx
    mov esi, [ebp + 8]              ; x
    mov edi, [ebp + 12]             ; y
    mov ebx, [ebp + 16]             ; w
    mov ecx, [ebp + 20]             ; h
    test ecx, ecx
    jz .out
    test ebx, ebx
    jz .out
    mov dword [vg_i], 0
    ; c0 and c1 are already absolute palette indices; memory-to-memory mov is
    ; illegal on x86, so go via eax
    mov eax, [ebp + 24]
    mov [vg_c0], eax
    mov eax, [ebp + 28]
    mov [vg_c1], eax
    mov [vg_h], ecx
    mov [vg_den], ecx
    dec dword [vg_den]             ; h - 1
.row:
    xor eax, eax
    cmp dword [vg_den], 0
    je .have
    mov eax, [vg_c1]
    sub eax, [vg_c0]
    imul eax, [vg_i]
    mov cx, [vg_den]
    xor edx, edx
    div cx
    add eax, [vg_c0]
.have:
    push dword eax
    push dword 1
    push ebx
    push edi
    push esi
    call gfx_fill
    add esp, 20
    inc dword [vg_i]
    inc edi
    dec dword [vg_h]
    jnz .row
.out:
    pop ecx
    pop edx
    pop edi
    pop esi
    pop ebx
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  gfx_corners(x, y, w, h, col) -- paint the four corner pixels, which is
;  what makes a filled rectangle read as a rounded one at this resolution.
; ---------------------------------------------------------------------------
gfx_corners:
    push ebp
    mov ebp, esp
    push eax
    push edx
    mov eax, [ebp + 24]             ; col
    mov edx, [ebp + 8]
    mov [cr_x], edx
    mov edx, [ebp + 12]
    mov [cr_y], edx
    mov edx, [ebp + 16]
    dec edx
    mov ecx, [ebp + 20]
    dec ecx
    ; top-left
    mov [cr_o], eax
    mov edx, [cr_y]
    imul edx, SCRW
    add edx, BACKBUF
    add edx, [cr_x]
    mov al, [cr_o]
    mov [edx], al
    ; top-right
    mov edx, [cr_x]
    add edx, [ebp + 16]
    dec edx
    mov ecx, [cr_y]
    imul ecx, SCRW
    add ecx, BACKBUF
    add edx, ecx
    mov al, [cr_o]
    mov [edx], al
    ; bottom-left
    mov edx, [cr_y]
    add edx, [ebp + 20]
    dec edx
    imul edx, SCRW
    add edx, BACKBUF
    add edx, [cr_x]
    mov al, [cr_o]
    mov [edx], al
    ; bottom-right
    mov edx, [cr_x]
    add edx, [ebp + 16]
    dec edx
    mov ecx, [cr_y]
    add ecx, [ebp + 20]
    dec ecx
    imul ecx, SCRW
    add ecx, BACKBUF
    add edx, ecx
    mov al, [cr_o]
    mov [edx], al
    pop edx
    pop eax
    pop ebp
    ret

align 4
vg_i:   dd 0
vg_h:   dd 0
vg_den: dd 0
vg_c0:  dd 0
vg_c1:  dd 0
cr_x:   dd 0
cr_y:   dd 0
cr_o:   dd 0

align 4
palette:
    ;  The VGA DAC is 6 bits per channel, so every component is 0..63 and the
    ;  video hardware scales it back up to 8 bits for display.
    ;  0 black      1 dark grey   2 grey        3 light grey
    db 0, 0, 0,    11, 11, 14,   26, 26, 29,   42, 42, 45
    ;  4 white      5 navy       6 blue        7 teal
    db 60, 61, 63,  4, 6, 16,    10, 22, 55,   0, 42, 42
    ;  8 green      9 lime       10 brown      11 gold
    db 10, 45, 15,  47, 60, 15,  35, 21, 7,    63, 51, 10
    ; 12 orange     13 red        14 pink       15 purple
    db 63, 35, 7,   56, 11, 11,  63, 27, 42,   32, 22, 55
