; ============================================================================
;  DektopOS  --  boot sector
;  Loaded by the BIOS at 0000:7C00.  Loads the kernel with INT 13h into
;  linear 0x10000, enables protected mode and jumps to it.
; ============================================================================
[bits 16]
[org 0x7C00]

KERNEL_LBA     equ 1            ; first sector after the MBR
; Must cover the whole kernel. Load address 0x10000 .. BACKBUF 0x20000 gives
; 128 sectors max. build.sh fails the build if kernel.bin outgrows this.
KERNEL_SECTORS equ 128          ; 64 KB ceiling, ends exactly at BACKBUF (0x20000)
KERNEL_ADDR    equ 0x00010000   ; linear load address

start:
    call com_init
    mov al, '1'
    call com_putc
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    cld
    sti

    mov si, msg_boot
    call puts16

    ; ---- read the kernel with the LBA extended read (works on floppy, HD, USB)
    mov word [dap_count], KERNEL_SECTORS
    mov dword [dap_lba], KERNEL_LBA

    mov dl, 0x80
    call try_lba
    jnc .loaded
    mov dl, 0x00
    call try_lba
    jnc .loaded

    ; ---- CHS fallback (ancient BIOSes without int13h extensions)
    mov dl, 0x80
    call try_chs
    jnc .loaded
    mov dl, 0x00
    call try_chs
    jnc .loaded

    mov si, err_disk
    call puts16
.hang: jmp .hang

.loaded:
    mov al, 'L'
    call com_putc
    mov ax, KERNEL_ADDR >> 4
    mov es, ax
    mov al, [es:0x0000]
    call com_hex
    mov al, [es:0x0003]
    call com_hex
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ax, 0x2400                 ; motor off
    int 0x13

    mov si, msg_pm
    call puts16

    mov al, 'P'
    call com_putc
    mov ax, 0x0013                 ; standard VGA 320x200x256 (mode 13h)
    int 0x10
    cli
    lgdt [gdt_desc]
    mov eax, cr0
    or eax, 1                      ; PE
    mov cr0, eax
    jmp dword 0x08:KERNEL_ADDR

; ---------------------------------------------------------------------------
try_lba:                             ; in: dl = drive      out: CF clear on ok
    mov si, dap                      ; DS = 0, labels are linear addresses
    mov ah, 0x42
    int 0x13
    ret

; ---------------------------------------------------------------------------
try_chs:                             ; in: dl = drive      out: CF clear on ok
    mov ax, KERNEL_ADDR >> 4
    mov es, ax
    xor bx, bx
    xor dx, dx
    mov dl, 0x00                   ; force floppy drive 0 (DL), head 0 (DH)
    mov cx, 0x0002                 ; cylinder 0, sector 2
    mov bp, KERNEL_SECTORS
.next:
    push cx
    push dx
    mov ax, 0x0201
    int 0x13
    pop dx
    pop cx
    jc .fail
    add bx, 512
    jnc .nobx
    call .es_para
    jmp .cont
.nobx:
    cmp bx, 0xF000
    jb .cont
    call .es_para
    jmp .cont
.es_para:                           ; BX = 0, ES += 0x1000
    mov bx, 0
    push ax
    mov ax, es
    add ax, 0x1000
    mov es, ax
    pop ax
    ret
.cont:
    inc cl
    cmp cl, 19                     ; 18 sectors per track
    jb .step
    mov cl, 1
    inc dh                         ; next head
    cmp dh, 2                      ; 2 heads
    jb .step
    xor dh, dh
    inc ch                         ; next cylinder
.step:
    dec bp
    jnz .next
    clc
    ret
.fail:
    stc
    ret

; ---------------------------------------------------------------------------
com_init:
    mov dx, 0x03F9
    xor al, al
    out dx, al
    mov dx, 0x03FB
    mov al, 0x80
    out dx, al
    mov dx, 0x03F8
    mov al, 12
    out dx, al
    mov dx, 0x03F9
    out dx, al
    mov dx, 0x03FB
    mov al, 3
    out dx, al
    ret

com_putc:
    push ax
    push dx
    mov dx, 0x03FD
.w:
    in al, dx
    test al, 0x20
    jz .w
    pop dx
    pop ax
    mov dx, 0x03F8
    out dx, al
    ret

com_hex:
    push ax
    push bx
    mov bl, al
    mov al, bl
    shr al, 4
    call .nib
    mov al, bl
    and al, 0x0F
    call .nib
    pop bx
    pop ax
    ret
.nib:
    cmp al, 10
    jb .dig
    add al, 'a' - 10 - '0'
.dig:
    add al, '0'
    call com_putc
    ret

; ---------------------------------------------------------------------------
puts16:                              ; in: si = 0-terminated string
    push ax
    push si
.loop:
    lodsb
    test al, al
    jz .done
    mov ah, 0x0E
    mov bx, 0x0007
    int 0x10
    jmp .loop
.done:
    pop si
    pop ax
    ret

; ---------------------------------------------------------------------------
msg_boot:  db 0x0D, 0x0A, 'DektopOS 1.0  --  loading kernel', 0x0D, 0x0A, 0
msg_pm:    db '  entering protected mode', 0x0D, 0x0A, 0
err_disk:  db 0x0D, 0x0A, 'DISK ERROR', 0

; ---------------------------------------------------------------------------
;  INT 13h/AH=42h disk address packet (must be a 16 byte paragraph-aligned
;  structure; BIOS requires DS:SI to point at it)
; ---------------------------------------------------------------------------
align 4
dap:
    db 0x10                        ; size
    db 0x00                        ; reserved
dap_count:
    dw KERNEL_SECTORS
dap_off:
    dw 0x0000
dap_seg:
    dw 0x1000                      ; -> linear 0x10000
dap_lba:
    dq KERNEL_LBA

; ---------------------------------------------------------------------------
align 8
gdt_start:
    dq 0x0000000000000000          ; null
    ; code: base 0, limit 4G, 32 bit, exec/read
    dw 0xFFFF
    dw 0x0000
    db 0x00                        ; base 16-23
    db 0x9A                        ; present, ring 0, code, exec/read
    db 0xCF                        ; granularity 4K, 32 bit, limit hi = F
    db 0x00                        ; base 24-31
    ; data: base 0, limit 4G, 32 bit, read/write
    dw 0xFFFF
    dw 0x0000
    db 0x00                        ; base 16-23
    db 0x92                        ; present, ring 0, data, read/write
    db 0xCF
    db 0x00                        ; base 24-31
gdt_end:

align 4
gdt_desc:
    dw gdt_end - gdt_start - 1
    dd gdt_start

times 510 - ($ - $$) db 0
dw 0xAA55
