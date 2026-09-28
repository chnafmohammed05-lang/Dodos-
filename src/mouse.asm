; ============================================================================
;  mouse.asm -- PS/2 mouse on IRQ12.  The handler only records deltas and
;  button edges; the shell consumes them once per frame.
; ============================================================================

mouse_init:
    mov dword [irq_table + 48], mouse_irq     ; IRQ12
    call mi_wait_in
    mov al, 0xA8
    out 0x64, al                              ; enable the aux port
    call mi_wait_in
    mov al, 0x20
    out 0x64, al                              ; read the command byte
    call mi_wait_out
    in al, 0x60
    or al, 0x02                               ; aux interrupt on
    and al, 0xDF                              ; aux clock on
    mov [mouse_cmd], al
    call mi_wait_in
    mov al, 0x60
    out 0x64, al
    call mi_wait_out
    mov al, [mouse_cmd]
    out 0x60, al
    mov al, 0xF6
    call mi_mouse_cmd
    mov al, 0xEA
    call mi_mouse_cmd
    mov al, 0xF4
    call mi_mouse_cmd
    mov dword [mouse_x], 160
    mov dword [mouse_y], 100
    mov dword [mouse_buttons], 0
    ; unmask IRQ12
    in al, 0x21
    and al, 0xEF
    out 0x21, al
    in al, 0xA1
    and al, 0xFE
    out 0xA1, al
    ret

mi_mouse_cmd:                       ; al = command for the aux device
    push ax
    call mi_wait_in
    mov al, 0xD4                      ; controller: next data byte -> mouse
    out 0x64, al
    call mi_wait_in
    pop ax
    out 0x60, al
    call mi_wait_out
    in al, 0x60                       ; drain the acknowledge
    ret

mi_wait_in:
    mov cx, 0x4000
.wi:
    in al, 0x64
    test al, 2
    jz .done
    loop .wi
.done:
    ret

mi_wait_out:
    mov cx, 0x4000
.wo:
    in al, 0x64
    test al, 1                      ; OBF must be set before reading port 60
    jnz .done
    loop .wo
.done:
    ret

; ---------------------------------------------------------------------------
mouse_irq:
    push eax
    push ebx
    push ecx
    push edx
    mov al, 0x20
    out 0x64, al                              ; command byte -> bit 3 marks the
    call mi_wait_out                          ; first byte of a packet
    in al, 0x60
    test al, 8
    jz .out
    call mi_wait_out
    in al, 0x60
    mov [mp_flags], al
    call mi_wait_out
    in al, 0x60
    movzx ebx, al                             ; dx
    call mi_wait_out
    in al, 0x60
    movzx ecx, al                             ; dy
    ; --- x delta ------------------------------------------------------
    mov eax, ebx
    and eax, 0x0F
    test bl, 0x10
    jz .xp
    neg eax
    jmp .xd
.xp:
    test bl, 0x20
    jz .xd
    neg eax
.xd:
    add [mouse_x], eax
    ; --- y delta (up is positive) ---------------------------------------
    mov eax, ecx
    and eax, 0x0F
    test cl, 0x10
    jz .yp
    neg eax
    jmp .yd
.yp:
    test cl, 0x20
    jz .yd
    neg eax
.yd:
    sub [mouse_y], eax
    ; --- buttons --------------------------------------------------------
    movzx ebx, byte [mp_flags]
    and ebx, 7
    mov ecx, [mouse_buttons]
    mov edx, ebx
    not edx
    and edx, ecx                              ; released this packet
    mov [mouse_up], edx
    mov edx, ecx
    not edx
    and edx, ebx                              ; pressed this packet
    mov [mouse_down], edx
    mov [mouse_buttons], ebx
    ; --- clamp ----------------------------------------------------------
    cmp dword [mouse_x], 0
    jge .xok
    mov dword [mouse_x], 0
.xok:
    cmp dword [mouse_x], 319
    jle .yok
    mov dword [mouse_x], 319
.yok:
    cmp dword [mouse_y], 0
    jge .yok2
    mov dword [mouse_y], 0
.yok2:
    cmp dword [mouse_y], 199
    jle .out
    mov dword [mouse_y], 199
.out:
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ---------------------------------------------------------------------------
;  mouse_consume: clear the edge flags, returning them in eax
;  bit0 left pressed   bit1 left released
;  bit2 right pressed  bit3 right released
;  bit4 middle pressed bit5 middle released
; ---------------------------------------------------------------------------
mouse_consume:
    xor ecx, ecx                  ; accumulator
    mov eax, [mouse_down]
    mov edx, [mouse_up]
    mov ebx, eax
    and ebx, 1
    or ecx, ebx                   ; bit0 left down
    mov ebx, edx
    and ebx, 1
    shl ebx, 1
    or ecx, ebx                   ; bit1 left up
    mov ebx, eax
    shr ebx, 1
    and ebx, 1
    shl ebx, 2
    or ecx, ebx                   ; bit2 right down
    mov ebx, edx
    shr ebx, 1
    and ebx, 1
    shl ebx, 3
    or ecx, ebx                   ; bit3 right up
    mov ebx, eax
    shr ebx, 2
    and ebx, 1
    shl ebx, 4
    or ecx, ebx                   ; bit4 middle down
    mov ebx, edx
    shr ebx, 2
    and ebx, 1
    shl ebx, 5
    or ecx, ebx                   ; bit5 middle up
    mov eax, ecx
    mov dword [mouse_down], 0
    mov dword [mouse_up], 0
    ret

mouse_cmd:    db 0
mp_flags:     db 0
mouse_x:      dd 160
mouse_y:      dd 100
mouse_buttons: dd 0
mouse_down:   dd 0
mouse_up:     dd 0
