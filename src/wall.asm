; ============================================================================
;  wall.asm -- the desktop background, generated once into WALLBUF and then
;  copied over the back buffer every frame.  Three styles:
;     0 = synthwave sunset with a perspective grid
;     1 = night sky with stars and a crescent moon
;     2 = falling green code
; ============================================================================

; PIXEL -- map wp_r/wp_g/wp_b to the nearest palette entry, store it at
; [edi] and advance edi by one.  All colour in wall.asm is expressed as
; 0..255 rgb triples so the wallpaper can be re-tuned without touching code.
%macro PIXEL 0
    call rgb2pal
    mov [edi], al
    inc edi
%endmacro

; ---------------------------------------------------------------------------
;  rgb2pal -- [wp_r], [wp_g], [wp_b] (0..255) -> al = nearest palette index
; ---------------------------------------------------------------------------
rgb2pal:
    push ebx
    push ecx
    push edx
    mov eax, [wp_r]
    mov ebx, [wp_g]
    mov ecx, [wp_b]
    mov edx, eax
    add edx, ebx
    add edx, ecx                    ; brightness sum
    cmp edx, 100
    jb .dark
    cmp edx, 560
    jb .mid
    cmp eax, 190
    jb .ltgray
    cmp ebx, 170
    jb .gold
    cmp ecx, 170
    jb .pink
    jmp .white
.dark:
    cmp edx, 36
    jb .black
    cmp ecx, eax
    jb .navy
    jmp .dkgray
.mid:
    cmp eax, ebx
    jge .mrg
    cmp ebx, ecx
    jge .mgreen
    jmp .mblue
.mrg:
    cmp eax, ecx
    jge .mred
    jmp .mblue
.mgreen:
    cmp ebx, 150
    jb .teal
    jmp .green
.mblue:
    cmp ecx, 150
    jb .navy
    jmp .blue
.mred:
    cmp eax, 205
    jae .orange
    cmp ebx, 110
    jb .red
    jmp .orange
.black:  mov al, C_BLACK
    jmp .out
.dkgray: mov al, C_DKGRAY
    jmp .out
.navy:   mov al, C_NAVY
    jmp .out
.blue:   mov al, C_BLUE
    jmp .out
.teal:   mov al, C_TEAL
    jmp .out
.green:  mov al, C_GREEN
    jmp .out
.lime:   mov al, C_LIME
    jmp .out
.gold:   mov al, C_GOLD
    jmp .out
.orange: mov al, C_ORANGE
    jmp .out
.red:    mov al, C_RED
    jmp .out
.pink:   mov al, C_PINK
    jmp .out
.white:  mov al, C_WHITE
    jmp .out
.ltgray: mov al, C_LTGRAY
.out:
    pop edx
    pop ecx
    pop ebx
    ret

wallpaper_build:
    push ebx
    push esi
    push edi
    mov eax, [wallpaper_style]
    test eax, eax
    jz .style0
    cmp eax, 1
    je .style1
    jmp .style2

; ---------------------------------------------------------------------------
;  style 0 -- synthwave
; ---------------------------------------------------------------------------
.style0:
    mov esi, 0                     ; y
.s0y:
    mov edi, WALLBUF
    mov eax, esi
    imul eax, SCRW
    add edi, eax
    cmp esi, HORIZON
    jl .s0sky

; ---------------------------------------------------------------------------
;  ground: a perspective grid that fades with distance from the horizon
; ---------------------------------------------------------------------------
    mov eax, esi
    sub eax, HORIZON
    inc eax
    mov [tmp1], eax                ; gd, 1..(SCRH-HORIZON)
    mov eax, edx
    imul eax, eax
    shr eax, 6
    add eax, 4
    mov [tmp2], eax                ; column spacing widens towards the viewer
    mov dword [tmp3], 0
.s0gloop:
    mov dword [xpos], 0
.s0gc:
    mov eax, [tmp1]                ; every eighth row is a horizontal line
    and eax, 7
    jz .s0gline
    mov eax, [xpos]
    add eax, 160
    xor edx, edx
    mov ecx, [tmp2]
    div ecx
    test edx, edx
    jnz .s0gbase
.s0gline:
    mov dword [wp_r], 255
    mov dword [wp_g], 70
    mov dword [wp_b], 190
    jmp .s0gput
.s0gbase:
    mov eax, [tmp1]                ; the base darkens away from the horizon
    shl eax, 2
    cmp eax, 170
    jbe .s0gdim
    mov eax, 170
.s0gdim:
    xor edx, edx
    mov ecx, 170
    div ecx
    xor ecx, ecx
    mov ecx, 150
    sub ecx, eax
    mov [wp_r], ecx
    mov eax, ecx
    shr eax, 2
    mov [wp_g], eax
    mov eax, ecx
    shr eax, 1
    add eax, 6
    mov [wp_b], eax
.s0gput:
    PIXEL
    inc dword [xpos]
    cmp dword [xpos], SCRW
    jl .s0gc

; ---------------------------------------------------------------------------
;  sky: a vertical gradient, a banded sun and a scatter of stars
; ---------------------------------------------------------------------------
    jmp .s0next
.s0sky:
    mov eax, esi
    shl eax, 8
    xor edx, edx
    mov ecx, HORIZON
    div ecx
    mov [tmp1], eax                ; f = 0..255 down the sky
    imul eax, eax
    shr eax, 8
    mov [tmp2], eax                ; f2
    mov dword [wp_r], 30
    mov dword [wp_g], 14
    mov dword [wp_b], 90
    push eax
    lea ebx, [eax + eax*2]
    shr ebx, 2
    add [wp_r], ebx
    shr eax, 2
    add [wp_g], eax
    pop eax
    mov eax, [tmp1]
    cmp eax, 90
    jbe .s0blue
    sub eax, 90                     ; below the horizon the sky glows
    add [wp_b], eax
    jmp .s0bluedone
.s0blue:
    mov ebx, 90
    sub ebx, eax
    shr ebx, 1
    sub [wp_b], ebx
.s0bluedone:
    ; sun band mask: 0 = lit, 1 = dark stripe
    mov eax, esi
    sub eax, HORIZON
    add eax, 44
    cmp eax, 12
    jl .s0sun
    sub eax, 12
    xor edx, edx
    mov ecx, 8
    div ecx
    cmp edx, 4
    jl .s0sun
    jmp .s0sunloop
.s0sun:
    mov dword [tmp3], 1
.s0sunloop:
    ; remember the sky colour so every pixel can be painted independently
    mov eax, [wp_r]
    mov [sky_r], eax
    mov eax, [wp_g]
    mov [sky_g], eax
    mov eax, [wp_b]
    mov [sky_b], eax
    mov dword [xpos], 0
.s0sc:
    mov eax, [xpos]
    sub eax, 160
    imul eax, eax
    mov ecx, esi
    sub ecx, HORIZON
    add ecx, 44
    imul ecx, ecx
    add eax, ecx
    cmp eax, 1600                 ; sun radius 40
    jae .s0nossun
    cmp dword [tmp3], 0
    jz .s0nosunband
    mov dword [wp_r], 255
    mov dword [wp_g], 110
    mov dword [wp_b], 40
    jmp .s0sput
.s0nosunband:
    mov dword [wp_r], 255
    mov dword [wp_g], 210
    mov dword [wp_b], 70
    jmp .s0sput
.s0nossun:
    ; a sparse scatter of stars in the upper sky
    cmp esi, 70
    jae .s0nostar
    mov eax, [xpos]
    imul eax, 73
    mov ecx, esi
    imul ecx, 151
    add eax, ecx
    and eax, 255
    cmp eax, 250
    jb .s0nostar
    mov dword [wp_r], 235
    mov dword [wp_g], 235
    mov dword [wp_b], 225
    jmp .s0sput
.s0nostar:
    mov eax, [sky_r]
    mov [wp_r], eax
    mov eax, [sky_g]
    mov [wp_g], eax
    mov eax, [sky_b]
    mov [wp_b], eax
.s0sput:
    PIXEL
    inc dword [xpos]
    cmp dword [xpos], SCRW
    jl .s0sc
.s0next:
    inc esi
    cmp esi, SCRH
    jl .s0y
    jmp .done

; ---------------------------------------------------------------------------
;  style 1 -- night sky
; ---------------------------------------------------------------------------
.style1:
    mov esi, 0
.s1y:
    mov edi, WALLBUF
    mov eax, esi
    imul eax, SCRW
    add edi, eax
    mov eax, esi
    shl eax, 9
    xor edx, edx
    mov ecx, SCRH
    div ecx
    mov [tmp1], eax                ; f
    mov dword [wp_r], 6
    mov dword [wp_g], 8
    mov dword [wp_b], 34
    add [wp_r], eax
    shr eax, 3
    add [wp_g], eax
    mov eax, [tmp1]
    shr eax, 1
    add [wp_b], eax
    mov dword [xpos], 0
.s1c:
    ; stars: a cheap hash, sparse enough to look like a sky
    mov eax, [xpos]
    imul eax, 40503
    add eax, esi
    imul eax, 2246822519
    shr eax, 11
    and eax, 127
    cmp eax, 122
    jae .s1nostar
    mov [tmp2], eax
    mov dword [wp_r], 255
    mov dword [wp_g], 255
    mov dword [wp_b], 255
    jmp .s1put
.s1nostar:
    ; moon at (244, 40) r 15, minus an offset circle to make a crescent
    mov eax, [xpos]
    sub eax, 244
    imul eax, eax
    mov ecx, esi
    sub ecx, 40
    imul ecx, ecx
    add eax, ecx
    cmp eax, 225
    jae .s1put
    mov eax, [xpos]
    sub eax, 250
    imul eax, eax
    mov ecx, esi
    sub ecx, 34
    imul ecx, ecx
    add eax, ecx
    cmp eax, 196
    jbe .s1put
    mov dword [wp_r], 235
    mov dword [wp_g], 235
    mov dword [wp_b], 210
    jmp .s1put
.s1put:
    PIXEL
    inc dword [xpos]
    cmp dword [xpos], SCRW
    jl .s1c
    inc esi
    cmp esi, SCRH
    jl .s1y
    jmp .done

; ---------------------------------------------------------------------------
;  style 2 -- matrix rain
; ---------------------------------------------------------------------------
.style2:
    mov dword [xpos], 0
.s2x:
    mov edi, WALLBUF
    add edi, [xpos]
    mov eax, [xpos]
    imul eax, 2654435761
    shr eax, 13
    mov [tmp1], eax                ; column hash
    mov ebx, eax
    and ebx, 3
    mov [tmp2], ebx                ; only one column in four has rain
    mov [tmp3], eax
    and eax, 255
    mov [tmp4], eax                ; head y
    mov esi, 0
.s2y:
    mov dword [wp_r], 0
    mov dword [wp_g], 16
    mov dword [wp_b], 9
    cmp dword [tmp2], 0
    jne .s2put
    mov eax, [tmp4]
    sub eax, esi                   ; distance from the head
    cmp eax, 46
    jge .s2put
    test eax, eax
    js .s2put
    mov ecx, 230
    imul ecx, eax
    shr ecx, 5
    mov ebx, 46
    sub ebx, ecx
    ; head is bright white-green, tail fades
    mov [wp_r], ebx
    shl ebx, 1
    mov [wp_g], ebx
    shr ebx, 1
    mov [wp_b], ebx
    test eax, eax
    jnz .s2put
    mov dword [wp_r], 255
    mov dword [wp_g], 255
    mov dword [wp_b], 255
.s2put:
    PIXEL
    add edi, SCRW - 1
    inc esi
    cmp esi, SCRH
    jl .s2y
    inc dword [xpos]
    cmp dword [xpos], SCRW
    jl .s2x
.done:
    pop edi
    pop esi
    pop ebx
    ret

sky_r: dd 0
sky_g: dd 0
sky_b: dd 0
