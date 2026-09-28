; ============================================================================
;  kbd.asm -- PS/2 keyboard (IRQ1) with a small event ring
; ============================================================================

K_UP      equ 0x81
K_DOWN    equ 0x82
K_LEFT    equ 0x83
K_RIGHT   equ 0x84
K_HOME    equ 0x85
K_END     equ 0x86
K_PGUP    equ 0x87
K_PGDN    equ 0x88
K_DEL     equ 0x89
K_INS     equ 0x8A
K_F1      equ 0x8B
K_F2      equ 0x8C
K_F3      equ 0x8D
K_F4      equ 0x8E
K_F5      equ 0x8F
K_F6      equ 0x90

kbd_init:
    mov dword [irq_table + 4], kbd_irq    ; IRQ1
    xor dword [kbd_mods], 0
    mov dword [kbd_head], 0
    mov dword [kbd_tail], 0
    ret

; ---------------------------------------------------------------------------
kbd_irq:
    push eax
    push ebx
    push ecx
    push edx
    in al, 0x60
    ; extended prefix?
    cmp al, 0xE0
    jne .noext
    mov byte [kbd_ext], 1
    jmp .out
.noext:
    movzx ebx, al
    ; Modifier releases also arrive with bit 7 set, so they have to be
    ; recognised before the generic "ignore every release" branch below --
    ; otherwise shift/ctrl/alt latch on and never come back up.
    cmp bl, 0xAA
    je .lshiftu
    cmp bl, 0xB6
    je .rshiftu
    cmp bl, 0x9D
    je .ctrlu
    cmp bl, 0xB8
    je .altu
    cmp bl, 0xBA
    je .keyup                  ; caps lock release changes nothing
    test bl, 0x80
    jnz .keyup
    ; --- key down ---------------------------------------------------
    cmp byte [kbd_ext], 0
    jne .extended
    ; modifiers
    cmp bl, 0x2A
    je .lshift
    cmp bl, 0x36
    je .rshift
    cmp bl, 0x1D
    je .ctrl
    cmp bl, 0x38
    je .alt
    cmp bl, 0x3A
    je .capslk
    ; ordinary key: unshifted char, shifted char, then caps lock toggles case
    movzx ecx, bl
    mov cl, byte [kbd_map + ecx]
    movzx esi, cl
    test byte [kbd_mods], K_SHIFT
    jz .cappest
    movzx ecx, bl
    mov cl, byte [kbd_map_sh + ecx]
    movzx esi, cl
.cappest:
    test byte [kbd_mods], K_CAPS
    jz .emit
    cmp cl, 'a'
    jb .emit
    cmp cl, 'z'
    ja .emit
    xor cl, 0x20
    movzx esi, cl                     ; the toggled case is the one we emit
    jmp .emit                         ; ordinary key: do not fall into .extended
.extended:
    xor byte [kbd_ext], 0
    mov cl, byte [kbd_map_ext + ebx]
    test cl, cl
    jz .out
    movzx esi, cl
    ; ctrl+alt+del
    cmp cl, K_DEL
    jne .emit
    mov al, [kbd_mods]
    and al, K_CTRL | K_ALT
    cmp al, K_CTRL | K_ALT
    jne .emit
    jmp reboot
.emit:
    mov eax, [kbd_head]
    mov ecx, [kbd_tail]
    lea edx, [key_ring + ecx * 8]
    inc ecx
    and ecx, KEY_RING - 1
    cmp eax, ecx
    je .out                    ; ring full, drop the event
    mov eax, esi
    mov byte [edx + KEYEV.code], al
    movzx eax, bl
    mov [edx + KEYEV.scan], al
    mov al, [kbd_mods]
    mov [edx + KEYEV.mod], al
    mov byte [edx + KEYEV.type], 0
    mov [kbd_head], ecx
    jmp .out
; --- modifier flags ----------------------------------------------------
.lshift:
    or byte [kbd_mods], K_SHIFT
    jmp .out
.rshift:
    or byte [kbd_mods], K_SHIFT
    jmp .out
.lshiftu:
.rshiftu:
    and byte [kbd_mods], 0xFE
    jmp .out
.ctrl:
    or byte [kbd_mods], K_CTRL
    jmp .out
.ctrlu:
    and byte [kbd_mods], 0xFD
    jmp .out
.alt:
    or byte [kbd_mods], K_ALT
    jmp .out
.altu:
    and byte [kbd_mods], 0xFB
    jmp .out
.capslk:
    xor byte [kbd_mods], K_CAPS
    jmp .out
.keyup:
    jmp .out
.out:
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ---------------------------------------------------------------------------
;  kbd_pop -> eax = pointer to the next event, or 0 if the ring is empty
; ---------------------------------------------------------------------------
kbd_pop:
    mov eax, [kbd_tail]
    mov ecx, [kbd_head]
    cmp eax, ecx
    je .empty
    mov edx, [kbd_tail]
    add edx, 1
    and edx, KEY_RING - 1
    mov [kbd_tail], edx
    imul eax, 8
    add eax, key_ring
    ret
.empty:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
reboot:
    mov al, 0xFE
    out 0x64, al
    mov eax, 0x1234
    jmp reboot

%include "kbdmap.inc"

align 4
kbd_map_ext:
    db 0,0,0,0,0,0,0,0                 ; 00-07
    db 0,0,0,0,0,0,0,0                 ; 08-0F
    db 0,0,0,0,0,0,0,0                 ; 10-17
    db 0,0,0,0,0,0,0,0                 ; 18-1F
    db 0,0,0,0,0,0,0,0                 ; 20-27
    db 0,0,0,0,0,0,0,0                 ; 28-2F
    db 0,0,0,0,0,0,0,0                 ; 30-37
    db 0,0,0,0,0,0,0,0                 ; 38-3F
    db 0,0,0,0,0,0,0,0                 ; 40-47
    db K_UP,0,0,K_PGUP,0,K_LEFT,0,K_RIGHT  ; 48-4F
    db 0,K_DOWN,0,K_PGDN,0,K_END,0,K_INS   ; 50-57
    db 0,0,0,K_DEL,0,K_F1,K_F2,K_F3       ; 58-5F
    db K_F4,K_F5,K_F6,0,0,0,0,0            ; 60-67

kbd_mods:  db 0
kbd_ext:   db 0
kbd_head:  dd 0
kbd_tail:  dd 0
key_ring:  times KEY_RING * 8 db 0
