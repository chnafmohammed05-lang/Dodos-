; ============================================================================
;  isr.asm -- interrupt service routines
; ============================================================================

%macro ISR_NOERR 1
global isr%1
isr%1:
    push dword 0
    push dword %1
    jmp isr_common
%endmacro

%macro ISR_ERR 1
global isr%1
isr%1:
    push dword %1
    jmp isr_common
%endmacro

isr_ptrs:
    dd isr0,  isr1,  isr2,  isr3,  isr4,  isr5,  isr6,  isr7
    dd isr8,  isr9,  isr10, isr11, isr12, isr13, isr14, isr15
    dd isr16, isr17, isr18, isr19, isr20, isr21, isr22, isr23
    dd isr24, isr25, isr26, isr27, isr28, isr29, isr30, isr31
    dd isr32, isr33, isr34, isr35, isr36, isr37, isr38, isr39
    dd isr40, isr41, isr42, isr43, isr44, isr45, isr46, isr47
    times 256 - 48 dd isr_spurious

isr_stub:
ISR_NOERR 0
ISR_NOERR 1
ISR_NOERR 2
ISR_NOERR 3
ISR_NOERR 4
ISR_NOERR 5
ISR_NOERR 6
ISR_NOERR 7
ISR_ERR   8
ISR_NOERR 9
ISR_ERR   10
ISR_ERR   11
ISR_ERR   12
ISR_ERR   13
ISR_ERR   14
ISR_NOERR 15
ISR_NOERR 16
ISR_ERR   17
ISR_NOERR 18
ISR_NOERR 19
ISR_NOERR 20
ISR_ERR   21
ISR_NOERR 22
ISR_NOERR 23
ISR_NOERR 24
ISR_NOERR 25
ISR_NOERR 26
ISR_NOERR 27
ISR_NOERR 28
ISR_ERR   29
ISR_ERR   30
ISR_NOERR 31
ISR_NOERR 32
ISR_NOERR 33
ISR_NOERR 34
ISR_NOERR 35
ISR_NOERR 36
ISR_NOERR 37
ISR_NOERR 38
ISR_NOERR 39
ISR_NOERR 40
ISR_NOERR 41
ISR_NOERR 42
ISR_NOERR 43
ISR_NOERR 44
ISR_NOERR 45
ISR_NOERR 46
ISR_NOERR 47
isr_spurious:                         ; catch-all for vectors 32..255
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ebp
    mov ax, ds
    mov es, ax
    mov al, 0x20
    out 0xA0, al
    out 0x20, al
    pop ebp
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    add esp, 4                     ; drop the interrupt number the CPU pushed
    iret

; ---------------------------------------------------------------------------
;  isr_common:  [esp+0] eax [4] ebx [8] ecx [12] edx [16] esi [20] edi
;               [24] ebp [28] int number [32] error code [36] eip ...
; ---------------------------------------------------------------------------
isr_common:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ebp
    mov ax, ds
    mov es, ax
    mov eax, [esp+28]
    cmp eax, 32
    jae .irq
    call exc_handler
    jmp .out
.irq:
    sub eax, 32
    cmp eax, 16
    jae .eoi
    call [irq_table + eax * 4]
.eoi:
    mov eax, [esp+28]
    cmp eax, 40
    jb .m1
    mov al, 0x20
    out 0xA0, al
.m1:
    mov al, 0x20
    out 0x20, al
.out:
    pop ebp
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    add esp, 8
    iret

; ---------------------------------------------------------------------------
;  hardware interrupts
; ---------------------------------------------------------------------------
isr_timer:
    inc dword [ticks]
    ret

isr_kbd:                           ; wired through irq_table
    jmp kbd_irq
