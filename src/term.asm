; ============================================================================
;  term.asm -- the whole userland: a fullscreen terminal with a small shell.
;
;  Screen layout (320x200, 8x8 font, 40 columns):
;      y =   0 .. 183   23 rows of scrollback output
;      y = 184 .. 191   the input line: prompt + what you are typing
;      y = 192 .. 199   the status bar
;
;  Function contracts (registers a function may destroy are listed):
;    term_line(esi)             destroys nothing
;    term_puts(esi)             preserves esi
;    term_putc(al)              preserves eax
;    term_eol()                 preserves eax
;    utoa(esi = dst, eax)       -> esi, destroys edi
;    pfx(eax = cand, edi = pre) -> eax = 1/0, preserves edi
;    fs_find is called with the name pushed as a stack argument
; ============================================================================

TERM_COLS       equ 40
TERM_ROWS       equ 23               ; output rows above the input line
TERM_LINE       equ 44               ; bytes kept per stored line
TERM_LINES      equ 128              ; scrollback ring
TERM_IN_MAX     equ 27               ; 40 - 13, so the input cannot overflow
IN_Y            equ 184
STATUS_Y        equ 192
PROMPT_X        equ 104              ; 13 characters * 8 px

; colours
T_BG            equ C_BLACK
T_FG            equ C_LTGRAY
T_HI            equ C_WHITE
T_PROMPT        equ C_GREEN
T_ACCENT        equ C_TEAL
T_ERR           equ C_RED
T_STATUS_BG     equ C_DKGRAY

; ===========================================================================
;  string helper
; ===========================================================================
; ---------------------------------------------------------------------------
;  strcopy(edi = dst, esi = src)
; ---------------------------------------------------------------------------
strcopy:
    push esi
    push edi
.l:
    mov al, [esi]
    mov [edi], al
    test al, al
    jz .d
    inc esi
    inc edi
    jmp .l
.d:
    pop edi
    pop esi
    ret

; ===========================================================================
;  term_init
; ===========================================================================
term_init:
    call fs_init
    mov dword [term_head], 0
    mov dword [term_count], 0
    mov byte [term_out], 0
    mov dword [term_outn], 0
    mov byte [term_input], 0
    mov dword [term_cur], 0
    mov dword [term_cmds], 0
    lea esi, [msg_boot]
    call term_line
    lea esi, [msg_hint]
    call term_line
    ret

; ===========================================================================
;  output primitives
; ===========================================================================
; ---------------------------------------------------------------------------
;  term_eol -- commit term_out into the scrollback ring
; ---------------------------------------------------------------------------
term_eol:
    push eax
    push edi
    push esi
    mov eax, [term_head]
    imul eax, TERM_LINE
    lea edi, [term_buf + eax]
    lea esi, [term_out]
    call strcopy
    mov byte [term_out], 0
    mov dword [term_outn], 0
    inc dword [term_head]
    cmp dword [term_head], TERM_LINES
    jb .ok
    mov dword [term_head], 0
.ok:
    inc dword [term_count]
    cmp dword [term_count], TERM_LINES
    jbe .fin
    mov dword [term_count], TERM_LINES
.fin:
    pop esi
    pop edi
    pop eax
    ret

; ---------------------------------------------------------------------------
;  term_putc(al) -- one character, wrapping at the right margin
; ---------------------------------------------------------------------------
term_putc:
    push eax
    push ecx
    push edx
.r:
    mov ecx, [term_outn]
    cmp ecx, TERM_COLS
    jb .put
    call term_eol
    jmp .r
.put:
    lea edx, [term_out]
    add edx, ecx
    mov [edx], al
    mov byte [edx + 1], 0
    inc dword [term_outn]
    pop edx
    pop ecx
    pop eax
    ret

; ---------------------------------------------------------------------------
;  term_puts(esi) -- a string
; ---------------------------------------------------------------------------
term_puts:
    push eax
    push esi
.l:
    mov al, [esi]
    test al, al
    jz .d
    inc esi
    call term_putc
    jmp .l
.d:
    pop esi
    pop eax
    ret

; ---------------------------------------------------------------------------
;  term_line(esi) -- a whole line
; ---------------------------------------------------------------------------
term_line:
    push eax
    push esi
    call term_puts
    call term_eol
    pop esi
    pop eax
    ret

; ---------------------------------------------------------------------------
;  utoa(esi = scratch, eax = value) -> esi = the digits
; ---------------------------------------------------------------------------
utoa:
    push eax
    push ebx
    push ecx
    push edx
    push edi
    mov edi, esi
    add edi, 11
    mov byte [edi], 0
    mov ecx, 10
.l:
    xor edx, edx
    div ecx
    add dl, '0'
    dec edi
    mov [edi], dl
    test eax, eax
    jnz .l
    mov esi, edi
    pop edi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ---------------------------------------------------------------------------
;  term_put_num(eax) -- append a decimal number
; ---------------------------------------------------------------------------
term_put_num:
    push eax
    push esi
    mov esi, num_buf
    call utoa
    call term_puts
    pop esi
    pop eax
    ret

; ---------------------------------------------------------------------------
;  pad2(edi = dst, eax = 0..99) -> edi advanced by 2, two digits
; ---------------------------------------------------------------------------
pad2:
    push eax
    push ebx
    push ecx
    push edx
    mov ecx, 2
.l:
    xor edx, edx
    mov ebx, 10
    div ebx
    add dl, '0'
    mov [edi], dl
    inc edi
    dec ecx
    jnz .l
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ---------------------------------------------------------------------------
;  term_put_pad2(eax) -- append a zero padded two digit number
; ---------------------------------------------------------------------------
term_put_pad2:
    push eax
    push esi
    push ecx
    push edx
    mov esi, num_buf
    call utoa
    mov ecx, esi
.len:
    cmp byte [ecx], 0
    je .lend
    inc ecx
    jmp .len
.lend:
    mov edx, ecx
    sub edx, esi
    cmp edx, 2
    jge .go
    mov eax, ecx
.ins:
    cmp eax, esi
    jb .insd
    mov dl, [eax]
    mov [eax + 1], dl
    dec eax
    jmp .ins
.insd:
    mov byte [esi], '0'
.go:
    call term_puts
    pop edx
    pop ecx
    pop esi
    pop eax
    ret

; ===========================================================================
;  drawing
; ===========================================================================
term_draw:
    push eax
    push ebx
    push ecx
    push edx
    ; ---- background
    push dword T_BG
    push dword SCRH
    push dword SCRW
    push dword 0
    push dword 0
    call gfx_fill
    add esp, 20
    ; ---- which ring slot is the topmost visible one?
    mov ecx, [term_count]
    xor eax, eax
    cmp ecx, TERM_ROWS - 1
    jbe .small
    mov eax, [term_head]
    sub eax, TERM_ROWS - 1
    jns .have
    add eax, TERM_LINES
.have:
    mov [term_first], eax
    jmp .got
.small:
    mov dword [term_first], 0
.got:
    ; ---- the 22 committed rows
    mov dword [term_row], 0
.row:
    mov ebx, [term_row]
    cmp ebx, TERM_ROWS - 1
    jae .live
    mov eax, [term_first]
    add eax, ebx
    cmp eax, TERM_LINES
    jb .nosub
    sub eax, TERM_LINES
.nosub:
    imul eax, TERM_LINE
    lea esi, [term_buf + eax]
    mov eax, ebx
    imul eax, 8
    mov edx, T_FG
    mov ecx, T_BG
    call term_text_at
    inc dword [term_row]
    jmp .row
.live:
    ; ---- the line being printed right now
    lea esi, [term_out]
    mov eax, [term_row]
    imul eax, 8
    mov edx, T_FG
    mov ecx, T_BG
    call term_text_at
    ; ---- the input line: prompt then what you typed
    push dword T_BG
    push dword 8
    push dword SCRW
    push dword IN_Y
    push dword 0
    call gfx_fill
    add esp, 20
    push dword T_BG
    push dword T_PROMPT
    push dword term_prompt
    push dword IN_Y
    push dword 0
    call gfx_text
    add esp, 20
    push dword T_BG
    push dword T_HI
    push dword term_input
    push dword IN_Y
    push dword PROMPT_X
    call gfx_text
    add esp, 20
    ; ---- the cursor
    mov eax, [term_cur]
    imul eax, 8
    add eax, PROMPT_X
    push dword T_BG
    push dword T_ACCENT
    push dword term_cursor
    push dword IN_Y
    push eax
    call gfx_text
    add esp, 20
    ; ---- the status bar
    call term_status
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ---------------------------------------------------------------------------
;  term_text_at(esi = str, eax = y, edx = fg, ecx = bg) at x = 0
; ---------------------------------------------------------------------------
term_text_at:                      ; esi = str, eax = y, edx = fg, ecx = bg
    push eax
    push edx
    push ecx
    push esi
    ; erase the row first: gfx_text stops at the NUL, so a short line drawn
    ; over a longer one would otherwise leave the old tail on screen
    push ecx                    ; colour
    push dword 8                ; h
    push dword SCRW             ; w
    push eax                    ; y
    push dword 0                ; x
    call gfx_fill
    add esp, 20
    pop esi
    pop ecx
    pop edx
    pop eax
    push ecx                    ; bg
    push edx                    ; fg
    push esi                    ; str
    push eax                    ; y
    push dword 0                ; x
    call gfx_text
    add esp, 20
    ret

; ---------------------------------------------------------------------------
;  term_status -- the bottom bar
; ---------------------------------------------------------------------------
term_status:
    push ebp
    mov ebp, esp
    push eax
    push ebx
    push ecx
    push edx
    push edi
    push dword T_STATUS_BG
    push dword 8
    push dword SCRW
    push dword STATUS_Y
    push dword 0
    call gfx_fill
    add esp, 20
    push dword T_STATUS_BG
    push dword T_FG
    push dword st_left
    push dword STATUS_Y
    push dword 1
    call gfx_text
    add esp, 20
    ; the clock on the right
    call rtc_read
    lea edi, [clk_buf]
    mov eax, [rtc_hour]
    call pad2
    mov byte [edi], ':'
    inc edi
    mov eax, [rtc_min]
    call pad2
    mov byte [edi], 0
    push dword T_STATUS_BG
    push dword T_HI
    push dword clk_buf
    push dword STATUS_Y
    push dword 291
    call gfx_text
    add esp, 20
    pop edi
    pop edx
    pop ecx
    pop ebx
    pop eax
    pop ebp
    ret

; ===========================================================================
;  input
; ===========================================================================
; ---------------------------------------------------------------------------
;  term_key(eax = KEYEV *) -- one key event
; ---------------------------------------------------------------------------
term_key:
    push ebp
    mov ebp, esp
    push eax
    push ebx
    push ecx
    push edx
    mov ecx, eax
    mov al, [ecx + KEYEV.type]
    test al, al
    jnz .out                     ; ignore key releases
    ; ctrl+alt+q reboots
    mov al, [ecx + KEYEV.mod]
    and al, K_CTRL | K_ALT
    cmp al, K_CTRL | K_ALT
    jne .nomod
    mov al, [ecx + KEYEV.code]
    cmp al, 'q'
    je .reboot
.nomod:
    mov al, [ecx + KEYEV.code]
    cmp al, 8                    ; backspace
    je .bs
    cmp al, 13                   ; enter (the scancode map yields LF)
    je .enter
    cmp al, 10
    je .enter
    cmp al, 9                    ; tab
    je .tab
    cmp al, 27                   ; escape clears the line
    je .clr
    cmp al, 32
    jb .out
    cmp al, 126
    ja .out
    mov ebx, [term_cur]
    cmp ebx, TERM_IN_MAX - 1
    jae .out
    lea edx, [term_input]
    add edx, ebx
    mov [edx], al
    mov byte [edx + 1], 0
    inc dword [term_cur]
    jmp .out
.reboot:
    call reboot
    jmp .out
.bs:
    mov ebx, [term_cur]
    test ebx, ebx
    jz .out
    dec dword [term_cur]
    lea edx, [term_input]
    add edx, ebx
    mov byte [edx], 0
    jmp .out
.clr:
    mov byte [term_input], 0
    mov dword [term_cur], 0
    jmp .out
.tab:
    call term_complete
    jmp .out
.enter:
    call term_echo
    call term_run
    mov byte [term_input], 0
    mov dword [term_cur], 0
    jmp .out
.out:
    pop edx
    pop ecx
    pop ebx
    pop eax
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  term_echo -- copy the prompt line into the scrollback
; ---------------------------------------------------------------------------
term_echo:
    push eax
    push esi
    mov esi, term_prompt
    call term_puts
    mov esi, term_input
    call term_puts
    call term_eol
    pop esi
    pop eax
    ret

; ---------------------------------------------------------------------------
;  pfx(eax = candidate, edi = prefix) -> eax = 1 when it starts with it
; ---------------------------------------------------------------------------
pfx:
    push ebx
    push ecx
    push edx
    mov ecx, edi
.l:
    mov dl, [ecx]
    test dl, dl
    jz .yes
    movzx ebx, byte [eax]
    cmp bl, 'A'
    jb .a
    cmp bl, 'Z'
    ja .a
    add bl, 32
.a:
    cmp dl, 'A'
    jb .b
    cmp dl, 'Z'
    ja .b
    add dl, 32
.b:
    cmp bl, dl
    jne .no
    inc eax
    inc ecx
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

; ---------------------------------------------------------------------------
;  term_complete -- TAB completes the first word against the command table
; ---------------------------------------------------------------------------
term_complete:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov esi, term_input
    mov edi, esi
.scan:
    mov al, [edi]
    test al, al
    jz .word
    cmp al, ' '
    je .fin
    inc edi
    jmp .scan
.word:
    mov [term_end], edi
    mov byte [edi], 0            ; the prefix is now NUL terminated
    xor ebx, ebx                ; match counter
    mov dword [term_hit], 0
    xor ecx, ecx                ; index of the command being tested
.c2:
    mov eax, [cmd_strs + ecx]
    test eax, eax
    jz .cdone
    call pfx                    ; pfx(eax = name, edi = prefix)
    test eax, eax
    jz .cnext
    mov [term_hit], ecx
    inc ebx
.cnext:
    add ecx, 4
    jmp .c2
.cdone:
    test ebx, ebx
    jz .fin
    cmp ebx, 1
    jne .many
    ; ---- a unique match: complete it
    mov ecx, [term_hit]
    mov esi, [cmd_strs + ecx]
    mov edi, term_input
    call strcopy
    call term_len
    jmp .fin
.many:
    ; ---- more than one match: list them
    xor ecx, ecx
.m2:
    mov eax, [cmd_strs + ecx]
    test eax, eax
    jz .fin
    call pfx
    test eax, eax
    jz .m3
    mov esi, eax
    call term_line
.m3:
    add ecx, 4
    jmp .m2
.fin:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ---------------------------------------------------------------------------
;  term_len -- refresh term_cur from the length of term_input
; ---------------------------------------------------------------------------
term_len:
    push eax
    push ecx
    xor ecx, ecx
.l:
    mov al, [term_input + ecx]
    test al, al
    jz .d
    inc ecx
    jmp .l
.d:
    mov [term_cur], ecx
    pop ecx
    pop eax
    ret

; ===========================================================================
;  the shell
; ===========================================================================
; ---------------------------------------------------------------------------
;  term_run -- run the command sitting in term_input
; ---------------------------------------------------------------------------
term_run:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov esi, term_input
    call skip_spc
    cmp byte [esi], 0
    je .out
    inc dword [term_cmds]
    mov edi, esi
.fw:
    mov al, [edi]
    test al, al
    jz .fwend
    cmp al, ' '
    je .fwend
    inc edi
    jmp .fw
.fwend:
    mov byte [edi], 0            ; the command word is now NUL terminated
    xor ebx, ebx
.look:
    mov eax, [cmd_strs + ebx]    ; the name to compare the input against
    test eax, eax
    jz .nocmd
    push esi
    call strcmp                 ; strcmp(eax = a, esi = b) -> 0 when equal
    pop esi
    jz .hit
    add ebx, 4
    jmp .look
.nocmd:
    lea esi, [msg_unknown]
    call term_line
    jmp .out
.hit:
    lea esi, [edi + 1]
    call skip_spc
    mov [term_arg], esi
    mov eax, [cmds + ebx]
    call eax
.out:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ---------------------------------------------------------------------------
;  skip_spc -- esi = the first non-space at or after esi
; ---------------------------------------------------------------------------
skip_spc:
    mov al, [esi]
    test al, al
    jz .d
    cmp al, ' '
    jne .d
    inc esi
    jmp skip_spc
.d:
    ret

; ===========================================================================
;  commands
; ===========================================================================
cmd_help:
    push eax
    push ebx
    push esi
    xor ebx, ebx
.hl:
    mov esi, [help_lines + ebx]
    test esi, esi
    jz .hd
    call term_line
    add ebx, 4
    jmp .hl
.hd:
    pop esi
    pop ebx
    pop eax
    ret

cmd_clear:
    mov dword [term_head], 0
    mov dword [term_count], 0
    mov byte [term_out], 0
    mov dword [term_outn], 0
    ret

cmd_echo:
    push esi
    mov esi, [term_arg]
    call term_puts
    call term_eol
    pop esi
    ret

cmd_whoami:
    push esi
    lea esi, [msg_user]
    call term_line
    pop esi
    ret

cmd_pwd:
    push eax
    push esi
    mov eax, [fs_cwd]
    imul eax, FSFILE_SIZE
    add eax, fs_files
    mov esi, [eax + FSFILE.name]
    call term_line
    pop esi
    pop eax
    ret

cmd_ls:
    push ebp
    mov ebp, esp
    push eax
    push ebx
    push ecx
    push edx
    push esi
    xor ebx, ebx
.l:
    cmp ebx, [fs_count]
    jae .done
    cmp ebx, [fs_cwd]               ; a directory is never its own child
    je .next
    mov eax, ebx
    call fs_ptr
    mov ecx, [eax + FSFILE.parent]
    cmp ecx, [fs_cwd]
    jne .next
    mov esi, [eax + FSFILE.name]
    call term_puts
    mov al, [eax + FSFILE.isdir]
    test al, al
    jz .nl
    mov al, '/'
    call term_putc
.nl:
    call term_eol
.next:
    inc ebx
    jmp .l
.done:
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    pop ebp
    ret

cmd_cat:
    push ebp
    mov ebp, esp
    push eax
    push ecx
    push edx
    push esi
    push dword [term_arg]
    call fs_find                ; the name is a stack argument
    add esp, 4
    test eax, eax
    jnz .found
    lea esi, [msg_nosuch]
    call term_line
    jmp .out
.found:
    mov cl, [eax + FSFILE.isdir]
    test cl, cl
    jz .plain
    mov esi, [eax + FSFILE.name]
    call term_puts
    lea esi, [msg_isdir]
    call term_eol
    jmp .out
.plain:
    mov esi, [eax + FSFILE.data]
    cld
.lp:
    lodsb
    test al, al
    jz .lend
    cmp al, 13
    je .lp                  ; CRLF: let the LF end the line, not both
    cmp al, 10
    je .nl
    call term_putc
    jmp .lp
.nl:
    call term_eol
    jmp .lp
.lend:
    cmp byte [term_out], 0
    je .out
    call term_eol
.out:
    pop esi
    pop edx
    pop ecx
    pop eax
    pop ebp
    ret

cmd_cd:
    push ebp
    mov ebp, esp
    push eax
    push ecx
    push edx
    push esi
    mov esi, [term_arg]
    mov al, [esi]
    test al, al
    jz .out                     ; no argument: stay where we are
    cmp al, '/'
    je .root
    cmp al, '.'
    jne .lookup
    cmp byte [esi + 1], '.'
    jne .lookup
    ; ---- ".." climbs one level
    mov eax, [fs_cwd]
    call fs_ptr
    mov ecx, [eax + FSFILE.parent]
    cmp ecx, FS_NONE
    je .out
    mov [fs_cwd], ecx
    jmp .out
.root:
    mov dword [fs_cwd], 0
    jmp .out
.lookup:
    push dword [term_arg]
    call fs_find
    add esp, 4
    test eax, eax
    jnz .found
    lea esi, [msg_nosuch]
    call term_line
    jmp .out
.found:
    mov cl, [eax + FSFILE.isdir]
    test cl, cl
    jnz .isdir
    lea esi, [msg_notdir]
    call term_line
    jmp .out
.isdir:
    call fs_index                 ; pointer -> index
    mov [fs_cwd], eax
.out:
    pop esi
    pop edx
    pop ecx
    pop eax
    pop ebp
    ret

cmd_uname:
    push esi
    mov esi, [term_arg]
    mov al, [esi]
    cmp al, '-'
    jne .plain
    lea esi, [msg_uname_a]
    jmp .p
.plain:
    lea esi, [msg_uname]
.p:
    call term_line
    pop esi
    ret

cmd_date:
    push ebp
    mov ebp, esp
    push eax
    push ecx
    call rtc_read
    mov eax, [rtc_year]
    add eax, 2000
    call term_put_num
    mov al, '-'
    call term_putc
    mov eax, [rtc_mon]
    call term_put_pad2
    mov al, '-'
    call term_putc
    mov eax, [rtc_day]
    call term_put_pad2
    mov al, ' '
    call term_putc
    mov eax, [rtc_hour]
    call term_put_pad2
    mov al, ':'
    call term_putc
    mov eax, [rtc_min]
    call term_put_pad2
    mov al, ':'
    call term_putc
    mov eax, [rtc_sec]
    call term_put_pad2
    call term_eol
    pop ecx
    pop eax
    pop ebp
    ret

cmd_uptime:
    push esi
    call term_uptime
    lea esi, [up_buf]
    call term_line
    pop esi
    ret

cmd_free:
    push ebp
    mov ebp, esp
    push eax
    push ecx
    push esi
    call term_mem
    lea esi, [msg_free_h]
    call term_line
    lea esi, [msg_free_c]
    call term_line
    lea esi, [msg_free_b]
    call term_puts
    mov esi, mem_buf
    call term_line
    pop esi
    pop ecx
    pop eax
    pop ebp
    ret

cmd_reboot:
    cli
    call reboot
    ret

; ---------------------------------------------------------------------------
;  app launchers -- each hands the screen to the windowed desktop
; ---------------------------------------------------------------------------
cmd_apps:
    lea esi, [msg_apps]
    call term_line
    lea esi, [msg_apps2]
    call term_line
    ret

cmd_notepad:
    mov eax, APP_NOTEPAD
    jmp desk_launch

cmd_about:
    mov eax, APP_ABOUT
    jmp desk_launch

; ---------------------------------------------------------------------------
;  term_uptime -- fill up_buf with H:MM:SS
; ---------------------------------------------------------------------------
term_uptime:
    push ebp
    mov ebp, esp
    push eax
    push ebx
    push ecx
    push edx
    push edi
    mov eax, [ticks]
    mov ebx, 1000
    xor edx, edx
    div ebx                     ; eax = seconds
    mov [u_sec], eax
    mov ebx, 60
    xor edx, edx
    div ebx
    mov [u_min], eax
    mov [u_sec], edx
    mov ebx, 60
    xor edx, edx
    div ebx
    mov [u_hrs], eax
    mov [u_min], edx
    lea edi, [up_buf]
    mov eax, [u_hrs]
    call pad2
    mov byte [edi], ':'
    inc edi
    mov eax, [u_min]
    call pad2
    mov byte [edi], ':'
    inc edi
    mov eax, [u_sec]
    call pad2
    mov byte [edi], 0
    pop edi
    pop edx
    pop ecx
    pop ebx
    pop eax
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  term_mem -- fill mem_buf with the memory report
; ---------------------------------------------------------------------------
term_mem:
    push ebp
    mov ebp, esp
    push eax
    push ecx
    push edx
    push edi
    push esi
    ; the CMOS base memory size in kilobytes. The index register must be
    ; rewritten before every read: port 70h selects, port 71h delivers.
    cli
    mov al, 0x16
    out 0x70, al
    in al, 0x71
    mov ch, al
    mov al, 0x17
    out 0x70, al
    in al, 0x71
    mov cl, al
    sti
    movzx eax, cx
    mov [mem_kb], eax
    ; "<kb>K". utoa digits backwards from the end of the buffer and returns
    ; esi = the first digit, so compact them to the front before appending.
    mov esi, mem_buf
    mov eax, [mem_kb]
    call utoa
    lea edi, [mem_buf]
    call strcopy               ; esi = digits, edi = the front of the buffer
    mov esi, mem_buf
.ap:
    cmp byte [esi], 0          ; walk to the end of the digits
    je .apd
    inc esi
    jmp .ap
.apd:
    mov byte [esi], 'K'
    inc esi
    mov byte [esi], 0
    pop esi
    pop edi
    pop edx
    pop ecx
    pop eax
    pop ebp
    ret

; ===========================================================================
;  fastfetch
; ===========================================================================
cmd_fastfetch:
    push ebp
    mov ebp, esp
    push eax
    push ebx
    push ecx
    push edx
    push edi
    push esi
    ; ---- the logo, one line per row
    xor ebx, ebx
.lg:
    mov esi, [logo_lines + ebx]
    test esi, esi
    jz .lgdone
    call term_line
    add ebx, 4
    jmp .lg
.lgdone:
    ; ---- a rule across the screen
    mov ecx, TERM_COLS
    lea edi, [rule_buf]
.rl:
    mov byte [edi], '-'
    inc edi
    dec ecx
    jnz .rl
    mov byte [edi], 0
    lea esi, [rule_buf]
    call term_line
    ; ---- who
    mov esi, term_user
    call term_line
    ; ---- the facts
    lea esi, [ff_os]
    call term_line
    lea esi, [ff_kern]
    call term_line
    lea esi, [ff_shell]
    call term_line
    lea esi, [ff_host]
    call term_line
    call cpu_ident
    lea esi, [ff_cpu]
    call term_puts
    lea esi, [cpu_name]
    call term_line
    lea esi, [ff_up]
    call term_puts
    call term_uptime
    lea esi, [up_buf]
    call term_line
    lea esi, [ff_mem]
    call term_puts
    call term_mem
    mov esi, mem_buf
    call term_puts
    lea esi, [msg_kbsuf]
    call term_line
    lea esi, [ff_res]
    call term_line
    lea esi, [ff_fs]
    call term_puts
    mov eax, [fs_count]
    call term_put_num
    call term_eol
    lea esi, [ff_cmds]
    call term_puts
    mov eax, [term_cmds]
    call term_put_num
    call term_eol
    pop ebx
    pop esi
    pop edi
    pop edx
    pop ecx
    pop eax
    pop ebp
    ret

cmd_neofetch:
    jmp cmd_fastfetch

; ---------------------------------------------------------------------------
;  cpu_ident -- fill cpu_name from the CPUID vendor string
; ---------------------------------------------------------------------------
cpu_ident:
    push eax
    push ebx
    push ecx
    push edx
    mov eax, 1
    cpuid
    test edx, 1 << 4             ; the FPU bit
    jz .fallback
    mov eax, 0
    cpuid
    mov dword [cpu_name + 0], ebx
    mov dword [cpu_name + 4], edx
    mov dword [cpu_name + 8], ecx
    jmp .term
.fallback:
    mov dword [cpu_name + 0], '386i'
    mov dword [cpu_name + 4], 0
.term:
    lea edi, [cpu_name]
    xor ecx, ecx
.len:
    mov al, [edi + ecx]
    test al, al
    jz .fold
    inc ecx
    cmp ecx, 15
    jb .len
    mov byte [edi + ecx], 0
.fold:
    xor ecx, ecx
.f:
    mov al, [edi + ecx]
    test al, al
    jz .done
    cmp al, 'A'
    jb .n
    cmp al, 'Z'
    ja .n
    add al, 32
    mov [edi + ecx], al
.n:
    inc ecx
    jmp .f
.done:
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ===========================================================================
;  data
; ===========================================================================
term_prompt:  db "user@dodos:~$ ", 0
term_user:    db "user@dodos", 0
term_cursor:  db "_", 0
st_left:      db "Tab compl  ESC clr  ^C-^A-^Q reboot", 0

term_input:   times TERM_IN_MAX + 2 db 0
term_out:     times TERM_LINE db 0
rule_buf:     times TERM_COLS + 2 db 0
num_buf:      times 16 db 0
clk_buf:      times 8 db 0
up_buf:       times 12 db 0
mem_buf:      times 24 db 0
cpu_name:     times 20 db 0
u_hrs:        dd 0
u_min:        dd 0
u_sec:        dd 0
mem_kb:       dd 0

align 4
term_head:    dd 0
term_count:   dd 0
term_first:   dd 0
term_row:     dd 0
term_cur:     dd 0
term_outn:    dd 0
term_cmds:    dd 0
term_arg:     dd 0
term_end:     dd 0
term_hit:     dd 0
term_tl:      dd 0
term_buf:     times TERM_LINES * TERM_LINE db 0

msg_boot:     db "DektopOS 1.0 -- minimal terminal build", 0
msg_hint:     db "type 'help', then try 'fastfetch'", 0

hl_0: db "commands:", 0
hl_1: db "  help        this list", 0
hl_2: db "  fastfetch   logo and system info", 0
hl_3: db "  clear       wipe the screen", 0
hl_4: db "  echo <t>    print text", 0
hl_5: db "  ls          list the volume", 0
hl_6: db "  cat <file>  print a file", 0
hl_7: db "  pwd         current directory", 0
hl_8: db "  cd <dir>    change directory", 0
hl_9: db "  uname [-a]  kernel name", 0
hl_10: db "  date        the RTC time", 0
hl_11: db "  uptime      time since boot", 0
hl_12: db "  whoami      current user", 0
hl_13: db "  free        memory", 0
hl_14: db "  reboot      restart", 0
hl_15: db "", 0
hl_16: db "desktop apps:", 0
hl_17: db "  apps        list them", 0
hl_18: db "  notepad     open notepad", 0
hl_19: db "  about       open about", 0
hl_23: db "", 0
hl_24: db "press Esc in an app to come back here", 0
align 4
help_lines:
    dd hl_0, hl_1, hl_2, hl_3, hl_4, hl_5, hl_6, hl_7
    dd hl_8, hl_9, hl_10, hl_11, hl_12, hl_13, hl_14, hl_15
    dd hl_16, hl_17, hl_18, hl_19, hl_23, hl_24, 0

msg_apps:     db "apps: notepad  about", 0
msg_apps2:    db "type one to open it, Esc to come back", 0
msg_user:     db "user", 0
msg_uname:    db "DektopOS", 0
msg_uname_a:  db "DektopOS dodos 1.0.0 i386", 0
msg_unknown:  db "sh: command not found", 0
msg_nosuch:   db "sh: no such file", 0
msg_notdir:   db "sh: not a directory", 0
msg_isdir:    db ": is a directory", 0
msg_free_h:   db "               total    used    free", 0
msg_free_c:   db "  conventional    640K      -    640K", 0
msg_free_b:   db "  cmos base      ", 0
msg_kbsuf:    db " (CMOS base memory)", 0

ff_os:        db "OS:       DektopOS 1.0 (i386)", 0
ff_kern:      db "Kernel:   dosk 0.1.0", 0
ff_shell:     db "Shell:    sh 1.0", 0
ff_host:      db "Host:     QEMU / Bochs (pc)", 0
ff_cpu:       db "CPU:      ", 0
ff_up:        db "Uptime:   ", 0
ff_mem:       db "Memory:   ", 0
ff_res:       db "Display:  320x200", 0
ff_fs:        db "Files:    ", 0
ff_cmds:      db "Commands: ", 0

lg0:  db "  ___  _  _  ___   ___   _   _ ", 0
lg1:  db " |   \| || || _ ) | _ \| | | |", 0
lg2:  db " | |) | || || _ \| |/ | | |_| |", 0
lg3:  db " |___/ \_/ |_||_|  |_|_| \___/ ", 0
lg4:  db "                              ", 0
align 4
logo_lines:
    dd lg0, lg1, lg2, lg3, lg4, 0

align 4
; ---- command names, index-parallel to the cmds table below ----
n_help:      db "help", 0
n_fastfetch:  db "fastfetch", 0
n_neofetch:   db "neofetch", 0
n_clear:     db "clear", 0
n_echo:      db "echo", 0
n_ls:        db "ls", 0
n_cat:       db "cat", 0
n_pwd:       db "pwd", 0
n_cd:        db "cd", 0
n_uname:     db "uname", 0
n_date:      db "date", 0
n_uptime:    db "uptime", 0
n_whoami:    db "whoami", 0
n_free:    db "free", 0
n_reboot:    db "reboot", 0
n_apps:      db "apps", 0
n_notepad:   db "notepad", 0
n_about:     db "about", 0
cmd_strs:
    dd n_help, n_fastfetch, n_neofetch, n_clear
    dd n_echo, n_ls, n_cat, n_pwd, n_cd, n_uname
    dd n_date, n_uptime, n_whoami, n_free, n_reboot
    dd n_apps, n_notepad, n_about
    dd 0                        ; end-of-table sentinel
cmds:
    dd cmd_help, cmd_fastfetch, cmd_neofetch, cmd_clear
    dd cmd_echo, cmd_ls, cmd_cat, cmd_pwd, cmd_cd, cmd_uname
    dd cmd_date, cmd_uptime, cmd_whoami, cmd_free, cmd_reboot
    dd cmd_apps, cmd_notepad, cmd_about
cmds_end:
