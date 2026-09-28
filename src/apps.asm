; ============================================================================
;  apps.asm -- the window contents.
;
;  app_draw(w) paints the client area of one window.  Each application keeps
;  its state in the WINDOW scratch fields so several windows of the same kind
;  stay independent.  app_key(w, ev) feeds a key event to a window and returns
;  1 when the event was consumed.
;
;  Calling conventions used here:
;    gfx_fill(x, y, w, h, colour)        -> push colour, h, w, y, x
;    gfx_text(x, y, str, fg, bg)         -> push bg, fg, str, y, x
;    gfx_char(x, y, ch, fg, bg)          -> push bg, fg, ch, y, x
;    gfx_sprite(x, y, w, h, src, zoom)   -> push zoom, src, h, w, y, x
;    gfx_bevel(x, y, w, h, light, face)  -> push face, light, h, w, y, x
;    gfx_vline(x, y, h, colour)          -> push colour, h, y, x
; ============================================================================

TERM_HIST       equ 4
ATERM_COLS       equ 30
PAINT_PAL       equ 8
CALC_KEYS       equ 12

; ---------------------------------------------------------------------------
;  app_draw(w)
; ---------------------------------------------------------------------------
app_draw:
    push ebp
    mov ebp, esp
    push eax
    mov ebx, [ebp + 8]
    mov eax, [ebx + WINDOW.app]
    cmp eax, APP_TERMINAL
    je .terminal
    cmp eax, APP_NOTEPAD
    je .notepad
    cmp eax, APP_FILES
    je .files
    cmp eax, APP_CALC
    je .calc
    cmp eax, APP_PAINT
    je .paint
    cmp eax, APP_ABOUT
    je .about
    jmp .out

; --- terminal ---------------------------------------------------------------
.terminal:
    call fill_client_dark
    mov eax, [wmb_cx]
    add eax, 3
    mov [app_px], eax
    mov eax, [wmb_ay]
    add eax, 3
    mov [app_py], eax
    ; oldest history line first
    mov eax, [ebx + WINDOW.state2]
    and eax, TERM_HIST - 1
    mov [app_h0], eax
    xor ecx, ecx
.hist:
    cmp ecx, TERM_HIST
    jae .prompt
    mov eax, [app_h0]
    add eax, ecx
    and eax, TERM_HIST - 1
    imul eax, ATERM_COLS + 1
    lea edx, [term_hist]
    add edx, eax
    push dword C_BLACK
    push dword C_LTGRAY
    push edx
    push dword [app_py]
    push dword [app_px]
    call gfx_text
    add esp, 20
    add dword [app_py], 8
    inc ecx
    jmp .hist
.prompt:
    push dword C_BLACK
    push dword C_GREEN
    push aterm_prompt
    push dword [app_py]
    push dword [app_px]
    call gfx_text
    add esp, 20
    ; the line being typed
    mov eax, [app_px]
    add eax, 16
    push dword C_BLACK
    push dword C_WHITE
    push aterm_input
    push dword [app_py]
    push eax
    call gfx_text
    add esp, 20
    ; block cursor, only in the focused window
    test dword [ebx + WINDOW.flags], WIN_FOCUSED
    jz .out
    mov eax, [app_px]
    add eax, 16
    mov ecx, [ebx + WINDOW.state]
    imul edx, ecx, 6
    add eax, edx
    push dword C_GREEN
    push dword 5
    push dword [app_py]
    push eax
    call gfx_vline
    add esp, 16
    jmp .out

; --- notepad ----------------------------------------------------------------
.notepad:
    call fill_client_light
    push dword C_LTGRAY
    push dword C_RED
    push np_body
    mov eax, [wmb_ay]
    add eax, 3
    push eax
    mov eax, [wmb_cx]
    add eax, 3
    push eax
    call gfx_text
    add esp, 20
    ; block caret sits just past the last glyph, only while focused
    test dword [ebx + WINDOW.flags], WIN_FOCUSED
    jz .out
    mov eax, [wmb_cx]
    add eax, 3
    mov ecx, [ebx + WINDOW.state]
    imul edx, ecx, 8                      ; the font is 8 pixels wide
    add eax, edx
    mov edx, [wmb_ay]
    add edx, 3
    push dword C_RED
    push dword 7
    push edx
    push eax
    call gfx_vline
    add esp, 16
    jmp .out

; --- file manager -----------------------------------------------------------
.files:
    call fill_client_light
    mov eax, [wmb_ay]
    add eax, 3
    mov [app_py], eax
    xor ebx, ebx
.entry:
    cmp ebx, [fs_count]
    jae .out
    imul eax, ebx, FSFILE_SIZE
    add eax, fs_files
    mov ecx, [eax + FSFILE.icon]   ; already a pointer to the bitmap
    push dword 1
    push ecx
    push dword ICON_H
    push dword ICON_W
    push dword [app_py]
    push dword [app_px]
    call gfx_sprite
    add esp, 24
    push dword C_LTGRAY
    push dword C_BLACK
    imul eax, ebx, FSFILE_SIZE
    add eax, fs_files
    mov eax, [eax + FSFILE.name]
    push eax
    push dword [app_py]
    push dword 8
    mov eax, [app_px]
    add eax, ICON_W + 4
    push eax
    call gfx_text
    add esp, 20
    add dword [app_py], 14
    inc ebx
    jmp .entry

; --- calculator -------------------------------------------------------------
.calc:
    call fill_client_light
    mov eax, [wmb_ay]
    add eax, 4
    push dword C_BLACK
    push dword 15
    push dword [wmb_ah]
    sub eax, 26
    push eax
    mov eax, [wmb_cw]
    sub eax, 10
    push eax
    mov eax, [wmb_cx]
    add eax, 5
    push eax
    call gfx_fill
    add esp, 20
    ; right aligned value
    push dword C_BLACK              ; bg
    push dword C_GREEN              ; fg
    push calc_value                 ; str
    mov eax, [wmb_ay]
    add eax, 7
    push eax                        ; y
    mov eax, [wmb_cx]
    add eax, 9
    push eax                        ; x
    call text_right
    add esp, 20
    ; keypad
    mov eax, [wmb_ay]
    add eax, [wmb_ah]
    sub eax, 86
    mov [app_py], eax
    xor ebx, ebx
.key:
    cmp ebx, CALC_KEYS
    jae .out
    mov eax, ebx
    and eax, 3
    imul eax, 22
    add eax, 5
    add eax, [wmb_cx]
    mov [calc_kx], eax
    mov eax, ebx
    shr eax, 2
    imul eax, 21
    add eax, [app_py]
    mov [calc_ky], eax
    mov edx, [calc_kx]
    mov ecx, [calc_ky]
    push dword C_WHITE
    push dword C_GRAY
    push dword 18
    push dword 20
    push ecx
    push edx
    call gfx_bevel
    add esp, 24
    push dword ebx
    call calc_label
    add esp, 4
    inc ebx
    jmp .key

; --- paint ------------------------------------------------------------------
.paint:
    call fill_client_light
    mov eax, [wmb_ah]
    add eax, [wmb_ay]
    sub eax, 22
    push dword 3
    push dword [wmb_cw]
    sub dword [esp], 8
    push eax
    mov eax, [wmb_cx]
    add eax, 4
    push eax
    call gfx_fill
    add esp, 20
    ; palette
    mov eax, [wmb_ah]
    add eax, [wmb_ay]
    sub eax, 14
    mov [app_py], eax
    xor ebx, ebx
.sw:
    cmp ebx, PAINT_PAL
    jae .out
    mov eax, [wmb_cx]
    add eax, 4
    lea eax, [eax + ebx * 2]
    add eax, ebx
    mov ecx, eax
    push dword C_BLACK
    push ebx
    push dword 10
    push dword 10
    push dword [app_py]
    push ecx
    call gfx_fill
    add esp, 20
    inc ebx
    jmp .sw

; --- about ------------------------------------------------------------------
.about:
    call fill_client_dark
    push dword 2
    push dword icon_about
    push dword ICON_H
    push dword ICON_W
    mov eax, [wmb_ay]
    add eax, 4
    push eax
    mov eax, [wmb_cx]
    add eax, 8
    push eax
    call gfx_sprite
    add esp, 24
    push dword C_BLACK
    push dword C_GOLD
    push ab_name
    mov eax, [wmb_ay]
    add eax, 6
    push eax
    mov eax, [wmb_cx]
    add eax, 32
    push eax
    call gfx_text
    add esp, 20
    push dword C_BLACK
    push dword C_LTGRAY
    push ab_ver
    mov eax, [wmb_ay]
    add eax, 18
    push eax
    mov eax, [wmb_cx]
    add eax, 32
    push eax
    call gfx_text
    add esp, 20
.out:
    pop ebx
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  fill_client_dark / fill_client_light -- the two common backgrounds
; ---------------------------------------------------------------------------
fill_client_dark:
    push dword C_BLACK
    push dword [wmb_ah]
    push dword [wmb_cw]
    push dword [wmb_ay]
    push dword [wmb_cx]
    call gfx_fill
    add esp, 20
    ret

fill_client_light:
    push dword C_LTGRAY
    push dword [wmb_ah]
    push dword [wmb_cw]
    push dword [wmb_ay]
    push dword [wmb_cx]
    call gfx_fill
    add esp, 20
    ret

; ---------------------------------------------------------------------------
;  text_right(x, y, str, fg, bg) -- same as gfx_text but right aligned on x
; ---------------------------------------------------------------------------
text_right:
    push ebp
    mov ebp, esp
    push eax
    push ecx
    push edx
    push esi
    mov esi, [ebp + 16]             ; str
    push esi
    call gfx_len
    add esp, 4
    mov ecx, eax
    mov eax, [ebp + 8]              ; x
    sub eax, ecx
    sub eax, 3
    push dword [ebp + 24]           ; bg
    push dword [ebp + 20]           ; fg
    push esi                        ; str
    push dword [ebp + 12]           ; y
    push eax                        ; x
    call gfx_text
    add esp, 20
    pop esi
    pop edx
    pop ecx
    pop eax
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  calc_label(n) -- centre the glyph of keypad key n inside calc_kx/calc_ky
; ---------------------------------------------------------------------------
calc_label:
    push ebp
    mov ebp, esp
    push eax
    push ecx
    mov eax, [ebp + 8]
    cmp eax, CALC_KEYS
    jae .out
    mov ecx, [calc_kx]
    add ecx, 7
    mov [app_px], ecx
    mov edx, [calc_ky]
    add edx, 5
    mov [app_py], edx
    movzx eax, byte [calc_chars + eax * 4]
    push dword C_BLACK
    push dword C_BLACK
    push eax
    push dword [app_py]
    push dword [app_px]
    call gfx_char
    add esp, 20
.out:
    pop ecx
    pop eax
    pop ebp
    ret

; ============================================================================
;  key handling
; ---------------------------------------------------------------------------
; ---------------------------------------------------------------------------
;  app_key(w, ev) -> eax = 1 when handled
; ---------------------------------------------------------------------------
app_key:
    push ebp
    mov ebp, esp
    push eax
    push ebx
    push ecx
    push edx
    mov ebx, [ebp + 8]
    mov ecx, [ebp + 12]
    mov eax, [ebx + WINDOW.app]
    cmp eax, APP_TERMINAL
    je .terminal
    cmp eax, APP_NOTEPAD
    je .notepad
    cmp eax, APP_CALC
    je .calc
    xor eax, eax
    jmp .out

; --- terminal ---------------------------------------------------------------
.terminal:
    mov al, [ecx + KEYEV.type]
    test al, al
    jnz .no
    mov al, [ecx + KEYEV.code]
    cmp al, 8                       ; backspace
    je .backspace
    cmp al, 13                      ; enter
    je .enter
    cmp al, 27                      ; escape clears the line
    je .clear
    cmp al, 32
    jb .no
    cmp al, 126
    ja .no
    lea edx, [aterm_input]
    add edx, [ebx + WINDOW.state]
    cmp edx, aterm_input + ATERM_COLS - 1
    jae .no
    mov [edx], al
    mov byte [edx + 1], 0
    inc dword [ebx + WINDOW.state]
    jmp .yes
.backspace:
    mov edx, [ebx + WINDOW.state]
    test edx, edx
    jz .no
    dec dword [ebx + WINDOW.state]
    lea edx, [aterm_input]
    add edx, [ebx + WINDOW.state]
    mov byte [edx], 0
    jmp .yes
.clear:
    mov byte [aterm_input], 0
    mov dword [ebx + WINDOW.state], 0
    jmp .yes
.enter:
    mov byte [aterm_input], 0
    mov dword [ebx + WINDOW.state], 0
    push ebx
    call aterm_run
    add esp, 4
    jmp .yes

; --- notepad ----------------------------------------------------------------
.notepad:
    mov al, [ecx + KEYEV.type]
    test al, al
    jnz .no
    mov al, [ecx + KEYEV.code]
    cmp al, 8
    je .npback
    cmp al, 32
    jb .no
    cmp al, 126
    ja .no
    lea edx, [np_body]
    add edx, [ebx + WINDOW.state]
    cmp edx, np_body + 150
    jae .no
    mov [edx], al
    mov byte [edx + 1], 0
    inc dword [ebx + WINDOW.state]
    jmp .yes
.npback:
    mov edx, [ebx + WINDOW.state]
    test edx, edx
    jz .no
    dec dword [ebx + WINDOW.state]
    lea edx, [np_body]
    add edx, [ebx + WINDOW.state]
    mov byte [edx], 0
    jmp .yes

; --- calculator -------------------------------------------------------------
.calc:
    mov al, [ecx + KEYEV.type]
    test al, al
    jnz .no
    mov al, [ecx + KEYEV.code]
    cmp al, '0'
    jb .cbop
    cmp al, '9'
    jbe .cbdig
.cbop:
    cmp al, '+'
    je .cbopset
    cmp al, '-'
    je .cbopset
    cmp al, '*'
    je .cbopset
    cmp al, '/'
    je .cbopset
    jmp .no
.cbopset:
    movzx edx, al
    mov [ebx + WINDOW.state6], edx
    mov eax, [ebx + WINDOW.state4]
    mov [ebx + WINDOW.state5], eax
    mov dword [ebx + WINDOW.state4], 0
    mov dword [ebx + WINDOW.state3], 0
    jmp .cbshow
.cbdig:
    cmp dword [ebx + WINDOW.state3], 10
    jae .no
    mov edx, [ebx + WINDOW.state4]
    imul edx, 10
    movzx eax, al
    sub eax, '0'
    add edx, eax
    mov [ebx + WINDOW.state4], edx
    inc dword [ebx + WINDOW.state3]
.cbshow:
    mov eax, [ebx + WINDOW.state4]
    push ebx
    call calc_apply
    add esp, 4
    jmp .yes

.no:
    xor eax, eax
    jmp .out
.yes:
    mov eax, 1
.out:
    pop edx
    pop ecx
    pop ebx
    pop eax
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  calc_apply(w) -- finish a pending operation, then render the display
; ---------------------------------------------------------------------------
calc_apply:
    push ebp
    mov ebp, esp
    push eax
    push ebx
    push ecx
    push edx
    mov ebx, [ebp + 8]
    movzx ecx, byte [ebx + WINDOW.state6]
    test ecx, ecx
    jz .render
    mov eax, [ebx + WINDOW.state4]     ; right hand side
    mov edx, [ebx + WINDOW.state5]     ; left hand side
    cmp cl, '+'
    je .add
    cmp cl, '-'
    je .sub
    cmp cl, '*'
    je .mul
    test eax, eax
    jz .divzero
    xor edx, edx
    div ecx
    jmp .store
.divzero:
    mov dword [ebx + WINDOW.state4], 0
    jmp .clearop
.add:
    add eax, edx
    jmp .store
.sub:
    sub edx, eax
    mov eax, edx
    jmp .store
.mul:
    imul eax, edx
    jmp .store
.store:
    mov [ebx + WINDOW.state4], eax
.clearop:
    mov byte [ebx + WINDOW.state6], 0
    mov dword [ebx + WINDOW.state3], 0
.render:
    mov eax, [ebx + WINDOW.state4]
    call calc_render
    pop edx
    pop ecx
    pop ebx
    pop eax
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  calc_render(eax = value) -- decimal text for the display
; ---------------------------------------------------------------------------
calc_render:
    push ecx
    push edx
    push esi
    push edi
    mov byte [calc_value + 15], 0
    mov ecx, 10
    mov edx, calc_value + 14
.div:
    xor ebx, ebx
    div ecx
    add bl, '0'
    mov [edx], bl
    dec edx
    test eax, eax
    jnz .div
    mov esi, edx
    mov edi, calc_value
.cp:
    mov al, [esi]
    mov [edi], al
    inc esi
    inc edi
    cmp byte [esi - 1], 0
    jne .cp
    pop edi
    pop esi
    pop edx
    pop ecx
    ret

; ---------------------------------------------------------------------------
;  aterm_run(w) -- run the command that was typed
; ---------------------------------------------------------------------------
aterm_run:
    push ebp
    mov ebp, esp
    push eax
    push ebx
    push ecx
    push edx
    push esi
    mov ebx, [ebp + 8]
    mov esi, aterm_input
    lea eax, [acmd_help]
    call strsame
    test eax, eax
    jnz .help
    lea eax, [acmd_about]
    call strsame
    test eax, eax
    jnz .about
    lea eax, [acmd_dir]
    call strsame
    test eax, eax
    jnz .dir
    lea eax, [acmd_ver]
    call strsame
    test eax, eax
    jnz .ver
    lea eax, [acmd_echo]
    call strsame
    test eax, eax
    jnz .echo
    mov esi, amsg_unknown
    jmp .build
.help:
    mov esi, msg_help
    jmp .build
.about:
    mov esi, msg_about
    jmp .build
.dir:
    mov esi, msg_dir
    jmp .build
.ver:
    mov esi, msg_ver
    jmp .build
.echo:
    lea esi, [aterm_input + 5]
.build:
    lea edi, [aterm_out]
    call strcopy
    ; store into the ring
    mov eax, [ebx + WINDOW.state2]
    and eax, TERM_HIST - 1
    imul eax, ATERM_COLS + 1
    lea edi, [term_hist]
    add edi, eax
    push edi
    lea esi, [aterm_out]
    call strcopy
    pop edi
    inc dword [ebx + WINDOW.state2]
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  strsame(eax = a, esi = b) -> eax = 1 when equal, case insensitive
; ---------------------------------------------------------------------------
strsame:
    push ebx
    push ecx
    push edx
    mov edx, eax
.l:
    movzx ebx, byte [edx]
    movzx ecx, byte [esi]
    cmp bl, 'a'
    jb .a
    cmp bl, 'z'
    ja .a
    sub bl, 32
.a:
    cmp cl, 'a'
    jb .b
    cmp cl, 'z'
    ja .b
    sub cl, 32
.b:
    cmp bl, cl
    jne .no
    test bl, bl
    jz .yes
    inc edx
    inc esi
    jmp .l
.yes:
    mov eax, 1
    jmp .out
.no:
    xor eax, eax
.out:
    pop edx
    pop ecx
    pop ebx
    ret

; ============================================================================
align 4
aterm_input:  times ATERM_COLS + 4 db 0
aterm_out:    times ATERM_COLS + 4 db 0
term_hist:   times TERM_HIST * (ATERM_COLS + 1) db 0
calc_value:  times 17 db 0
calc_chars:  db '7','8','9','/'
            db '4','5','6','*'
            db '1','2','3','-'
            db 'C','0','=','+'
calc_kx:     dd 0
calc_ky:     dd 0
app_px:      dd 0
app_py:      dd 0
app_h0:      dd 0
np_body:     times 160 db 0
aterm_prompt: db "> ", 0

acmd_help:    db "help", 0
acmd_about:   db "about", 0
acmd_dir:     db "dir", 0
acmd_ver:     db "ver", 0
acmd_echo:    db "echo ", 0

msg_help:    db "cmds: help dir ver about echo", 0
msg_about:   db "DektopOS 0.1 - 32 bit asm", 0
msg_dir:     db "DOCS/ GFX/ README.TXT ABOUT.TXT", 0
msg_ver:     db "DektopOS 0.1", 0
amsg_unknown: db "unknown command", 0
ab_name:     db "DektopOS", 0
ab_ver:      db "version 0.1", 0

; ---------------------------------------------------------------------------
;  app_mouse(w) -- react to a click inside the client area of w.
;  wmx_cx/cy/cw/ch describe the client rectangle.
; ---------------------------------------------------------------------------
app_mouse:
    push ebp
    mov ebp, esp
    push eax
    push ebx
    push ecx
    push edx
    mov ebx, [ebp + 8]
    mov eax, [ebx + WINDOW.app]
    cmp eax, APP_CALC
    je .calc
    cmp eax, APP_PAINT
    je .paint
    jmp .out
; --- calculator: which key was hit? ---------------------------------------
.calc:
    mov eax, [wmx_ch]
    add eax, [wmx_cy]
    sub eax, 86
    mov [calc_ky], eax
    mov eax, [wmx_cx]
    add eax, 5
    mov [calc_kx], eax
    xor ecx, ecx
.key:
    cmp ecx, CALC_KEYS
    jae .out
    mov edx, ecx
    and edx, 3
    imul edx, 22
    add edx, [wmx_cx]
    add edx, 5
    mov eax, ecx
    shr eax, 2
    imul eax, 21
    add eax, [calc_ky]
    cmp [mouse_x], edx
    jb .nextkey
    add edx, 20
    cmp [mouse_x], edx
    jae .nextkey
    cmp [mouse_y], eax
    jb .nextkey
    add eax, 18
    cmp [mouse_y], eax
    jae .nextkey
    ; found: turn the key press into the matching character
    mov eax, [calc_chars + ecx * 4]
    mov [calc_key], al
    cmp al, '='
    je .equals
    cmp al, 'C'
    je .clear
    jmp .keyed
.equals:
    mov al, '+'
    jmp .keyed
.clear:
    mov al, 27
.keyed:
    movzx eax, al
    mov [calc_key], al
    push ebx
    push eax
    call calc_keypress
    add esp, 8
    jmp .out
.nextkey:
    inc ecx
    jmp .key
; --- paint: pick a colour or draw on the canvas ---------------------------
.paint:
    ; the swatch strip at the bottom
    mov eax, [wmx_ch]
    add eax, [wmx_cy]
    sub eax, 14
    cmp [mouse_y], eax
    jl .canvas
    mov eax, [mouse_x]
    sub eax, [wmx_cx]
    sub eax, 4
    cmp eax, PAINT_PAL * 3
    jae .out
    shr eax, 1                        ; 3 px per swatch
    cmp eax, PAINT_PAL
    jae .out
    mov [ebx + WINDOW.state], eax
    jmp .out
.canvas:
    mov eax, [wmx_cx]
    add eax, [wmx_cw]
    cmp [mouse_x], eax
    jae .out
    mov edx, [wmx_cy]
    add edx, [wmx_ch]
    sub edx, 22
    cmp [mouse_y], edx
    jge .out
    call paint_dot
.out:
    pop edx
    pop ecx
    pop ebx
    pop eax
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  calc_keypress(w, ch) -- feed one calculator key to the window
; ---------------------------------------------------------------------------
calc_keypress:
    push ebp
    mov ebp, esp
    push eax
    push ecx
    push edx
    mov eax, [ebp + 12]
    movzx ecx, al
    cmp cl, 'C'
    je .clr
    cmp cl, 27
    je .clr
    mov edx, [ebp + 8]
    cmp cl, '='
    je .finish
    cmp cl, '+'
    je .op
    cmp cl, '-'
    je .op
    cmp cl, '*'
    je .op
    cmp cl, '/'
    je .op
    ; a digit
    cmp dword [edx + WINDOW.state3], 10
    jae .out
    mov eax, [edx + WINDOW.state4]
    imul eax, 10
    movzx ecx, al
    sub ecx, '0'
    add eax, ecx
    mov [edx + WINDOW.state4], eax
    inc dword [edx + WINDOW.state3]
    jmp .show
.op:
    movzx eax, cl
    mov [edx + WINDOW.state6], al
    mov eax, [edx + WINDOW.state4]
    mov [edx + WINDOW.state5], eax
    mov dword [edx + WINDOW.state4], 0
    mov dword [edx + WINDOW.state3], 0
    jmp .show
.finish:
    mov al, '+'                      ; apply the pending operator
.finish2:
    movzx ecx, al
    movzx eax, byte [edx + WINDOW.state6]
    test eax, eax
    jz .show
    mov [edx + WINDOW.state6], al
    push edx
    call calc_apply
    add esp, 4
    jmp .out
.clr:
    mov dword [edx + WINDOW.state4], 0
    mov dword [edx + WINDOW.state5], 0
    mov dword [edx + WINDOW.state3], 0
    mov byte [edx + WINDOW.state6], 0
.show:
    push edx
    call calc_apply
    add esp, 4
.out:
    pop edx
    pop ecx
    pop eax
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  paint_dot  -- draw with the current colour while the button is held
; ---------------------------------------------------------------------------
paint_dot:
    push eax
    push ecx
    mov ecx, [wm_focus]
    cmp ecx, 0
    jl .out
    imul ecx, ecx, WINDOW_SIZE
    add ecx, wm_windows
    mov eax, [ecx + WINDOW.state]
    push eax
    push dword [mouse_y]
    push dword [mouse_x]
    call gfx_px
    add esp, 12
.out:
    pop ecx
    pop eax
    ret
align 4
calc_key:    db 0
