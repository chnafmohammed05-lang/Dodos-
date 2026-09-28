; ============================================================================
;  shell.asm -- bring-up and the main loop for the minimal terminal build.
;
;  The terminal owns the screen by default. Typing an app name (notepad,
;  files, calc, paint, about) switches to the windowed desktop; Esc switches
;  back. Both modes are drawn by the same main loop in kernel.asm.
; ============================================================================

; ---------------------------------------------------------------------------
;  shell_init
; ---------------------------------------------------------------------------
shell_init:
    call term_init
    ret

; ---------------------------------------------------------------------------
;  shell_input -- drain the keyboard ring
; ---------------------------------------------------------------------------
shell_input:
.keys:
    call kbd_pop                  ; eax = KEYEV pointer or 0
    test eax, eax
    jz .out
    push eax
    call term_key
    pop eax
    jmp .keys
.out:
    ret

; ---------------------------------------------------------------------------
;  shell_draw
; ---------------------------------------------------------------------------
shell_draw:
    call term_draw
    ret

; ---------------------------------------------------------------------------
;  shell_desk -- one frame of the windowed desktop
; ---------------------------------------------------------------------------
shell_desk:
    call desk_background             ; wallpaper + launcher icons
    call wm_events                   ; mouse: drag, clicks, taskbar, menu
    call desk_keys                   ; keyboard: Esc hands back the screen
    call wm_draw
    ret

; ---------------------------------------------------------------------------
;  desk_background -- repaint the wallpaper, then the icons on top of it
; ---------------------------------------------------------------------------
desk_background:
    push eax
    push dword 64000
    push dword WALLBUF
    push dword BACKBUF
    call gfx_copy
    add esp, 12
    call wm_desk_icons
    pop eax
    ret

; ---------------------------------------------------------------------------
;  desk_keys -- Esc returns to the terminal
; ---------------------------------------------------------------------------
desk_keys:
    push eax
    push ebx
    push ecx
    push edx
    push esi
.keys:
    call kbd_pop                     ; eax = KEYEV pointer or 0
    test eax, eax
    jz .out
    mov esi, eax                     ; the event has to outlive the pop
    cmp byte [esi + KEYEV.type], 0
    jne .keys                        ; act on the press, ignore the release
    cmp byte [esi + KEYEV.scan], 0x01 ; Esc (kbd_map has no ascii for it)
    jne .send
    mov dword [desk_mode], 0
    call kbd_drain                   ; don't leak the Esc release into the shell
    jmp .out
.send:
    ; give the focused window first refusal on the event
    mov eax, [wm_focus]
    test eax, eax
    js .keys                         ; nothing focused
    cmp eax, [wm_count]
    jae .keys
    imul eax, eax, WINDOW_SIZE
    add eax, wm_windows
    mov ebx, eax                     ; ebx = the focused window
    ; cdecl: the last value pushed is the first argument, so ev goes first
    push esi                         ; ev  -> [ebp + 12]
    push ebx                         ; w   -> [ebp + 8]
    call app_key                     ; dispatches on WINDOW.app itself
    add esp, 8
    jmp .keys                        ; keys never fall through to the shell
.out:
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ---------------------------------------------------------------------------
;  kbd_drain -- throw away every key event still queued
; ---------------------------------------------------------------------------
kbd_drain:
.keys:
    call kbd_pop
    test eax, eax
    jz .out
    jmp .keys
.out:
    ret

; ---------------------------------------------------------------------------
;  desk_launch(eax = app id) -- open an app and switch to the desktop
; ---------------------------------------------------------------------------
desk_launch:
    push eax
    call kbd_drain                   ; the Enter that ran this is still queued
    pop eax
    push eax
    call wm_open_app
    add esp, 4
    mov dword [desk_mode], 1
    ret
