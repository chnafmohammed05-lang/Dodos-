; ============================================================================
;  DektopOS 1.0 -- kernel
;  32 bit protected mode, flat memory map, VGA mode 13h desktop.
; ============================================================================
[bits 32]
[org 0x00010000]

; --- memory map ------------------------------------------------------------
%define BACKBUF    0x00020000     ; 320x200 back buffer
%define WALLBUF    0x00030000     ; cached wallpaper
%define PAINTBUF   0x00040000     ; paint canvas
%define WINTAB     0x00050000     ; window structures
%define HEAP       0x00060000     ; consoles, text buffers, disk image
%define STACKTOP   0x00078000

; --- window system ---------------------------------------------------------
MAXWIN         equ 8
WINSTATE_SIZE  equ 2048

struc WIN
  .used      resb 1               ; 0 free, 1 open
  .app       resb 1               ; application id
  .flags     resb 1               ; bit0 visible  bit1 focused
                                   ; bit2 minimised bit3 maximised
  .icon      resb 1
  .x         resw 1
  .y         resw 1
  .w         resw 1
  .h         resw 1
  .rx        resw 1               ; restore geometry when maximised
  .ry        resw 1
  .rw        resw 1
  .rh        resw 1
  .cx        resw 1               ; content rect (recomputed on draw)
  .cy        resw 1
  .cw        resw 1
  .ch        resw 1
  .title     resb 24
  .state     resb WINSTATE_SIZE
endstruc
WIN_SIZE       equ WIN - 1
OFF_USED       equ WIN.used
OFF_APP        equ WIN.app
OFF_FLAGS      equ WIN.flags
OFF_X          equ WIN.x
OFF_Y          equ WIN.y
OFF_W          equ WIN.w
OFF_H          equ WIN.h
OFF_RX         equ WIN.rx
OFF_RY         equ WIN.ry
OFF_RW         equ WIN.rw
OFF_RH         equ WIN.rh
OFF_CX         equ WIN.cx
OFF_CY         equ WIN.cy
OFF_CW         equ WIN.cw
OFF_CH         equ WIN.ch
OFF_TITLE      equ WIN.title
OFF_STATE      equ WIN.state

WIN_VISIBLE    equ 1
WIN_FOCUSED    equ 2
WIN_MIN        equ 4
WIN_MAX        equ 8

; --- colour ramps; see build_ramps / ramp_defs in gfx.asm ---------------
RAMP_BLUE      equ 16
RAMP_TEAL      equ 32
RAMP_GREEN     equ 48
RAMP_GOLD      equ 64
RAMP_ORANGE    equ 80
RAMP_RED       equ 96
RAMP_PINK      equ 112
RAMP_PURPLE    equ 128
RAMP_LIGHT     equ 144
RAMP_DARK      equ 160

; --- bottom panel geometry ----------------------------------------------
PANEL_H        equ 20
PANEL_Y        equ 180
PBTN_Y         equ 182
PBTN_H         equ 16
PBTN_W         equ 54
PBTN_DX        equ 56
TITLE_H        equ 14
MENU_W         equ 38                   ; the Menu button is 1..38 wide
MENU_X         equ 1
TBTN_X0        equ 44                   ; first task button

; --- applications ----------------------------------------------------------
APP_TERMINAL   equ 0
APP_NOTEPAD    equ 1
APP_FILES      equ 2
APP_CALC       equ 3
APP_PAINT      equ 4
APP_ABOUT      equ 5
APP_COUNT      equ 6
; --- start menu geometry ---------------------------------------------------
SM_ITEM_H      equ 18
SM_PAD         equ 5
SM_W           equ 110
SM_H           equ SM_PAD * 2 + SM_ITEM_H * APP_COUNT
SM_X           equ 1
SM_Y           equ PANEL_Y - SM_H


; --- key events ------------------------------------------------------------
struc KEYEV
  .code  resb 1                   ; ascii code
  .scan  resb 1                   ; scancode
  .mod   resb 1                   ; bit0 shift bit1 ctrl bit2 alt bit3 caps
  .type  resb 1                   ; 0 down 1 up
endstruc

KEY_RING       equ 64
K_SHIFT        equ 1
K_CTRL         equ 2
K_ALT          equ 4
K_CAPS         equ 8

; ---------------------------------------------------------------------------
kmain:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, STACKTOP
    cld

    call serial_init
    mov al, '['
    call serial_putc
    mov al, 'k'
    call serial_putc
    mov al, ']'
    call serial_putc
    mov al, ' '
    call serial_putc
    mov eax, 0x10000
    call serial_hex32
    mov al, 0x0A
    call serial_putc

    call idt_init
    mov al, '1'
    call serial_putc
    call pic_init
    mov al, '2'
    call serial_putc
    call timer_init
    mov al, '3'
    call serial_putc
    call kbd_init
    mov al, '4'
    call serial_putc
    call mouse_init
    mov al, '5'
    call serial_putc
    call rtc_init
    mov al, '6'
    call serial_putc
    call gfx_init
    mov al, '7'
    call serial_putc

    ; the minimal build boots straight into the terminal
    call shell_init
    mov al, '8'
    call serial_putc

    mov al, '['
    call serial_putc
    mov al, 'o'
    call serial_putc
    mov al, 'k'
    call serial_putc
    mov al, ']'
    call serial_putc
    mov al, 0x0A
    call serial_putc

    sti
.main:
    cmp dword [desk_mode], 0
    je .term
    call shell_desk                  ; the windowed desktop owns the screen
    jmp .present
.term:
    call shell_input                 ; drain the keyboard into the shell
    call shell_draw                  ; repaint the terminal
.present:
    call gfx_present
    hlt
    jmp .main

; ---------------------------------------------------------------------------
panic:
    cli
    mov al, '!'
    call serial_putc
    mov al, 0x0A
    call serial_putc
.h: hlt
    jmp .h

; ===========================================================================
;  serial debug console (COM1)
; ===========================================================================
serial_init:
    push dx
    push ax
    mov dx, 0x03F8 + 1
    xor al, al
    out dx, al                      ; no interrupts
    mov dx, 0x03F8 + 3
    mov al, 0x80
    out dx, al                      ; DLAB
    mov dx, 0x03F8 + 0
    xor al, al
    out dx, al                      ; divisor lo
    mov dx, 0x03F8 + 1
    out dx, al
    mov dx, 0x03F8 + 3
    mov al, 0x03
    out dx, al
    mov dx, 0x03F8 + 2
    mov al, 0xC7
    out dx, al
    pop ax
    pop dx
    ret

serial_putc:                       ; al = char
    pushad
    mov bl, al                      ; stash the character
    mov ecx, 0x4000
.wait:
    mov dx, 0x03F8 + 5              ; line status register
    in al, dx
    test al, 0x20                   ; transmit holding register empty?
    jnz .send
    loop .wait
.send:
    mov al, bl
    mov edx, 0x03F8
    out dx, al                      ; send it even if we gave up waiting
    popad
    ret

serial_puts:                       ; esi = string
    push esi
    push ax
.lp:
    lodsb
    test al, al
    jz .done
    call serial_putc
    jmp .lp
.done:
    pop ax
    pop esi
    ret

serial_hex8:                       ; al
    push eax
    push ebx
    mov bl, al
    mov al, bl
    shr al, 4
    call .nib
    mov al, bl
    and al, 0x0F
    call .nib
    pop ebx
    pop eax
    ret
.nib:
    cmp al, 10
    jb .dig
    add al, 'a' - 10 - '0'
.dig:
    add al, '0'
    call serial_putc
    ret

serial_hex32:                      ; eax
    push esi
    push ebx
    mov esi, eax
    mov ebx, eax
    shr ebx, 24
    mov al, bl
    call serial_hex8
    mov ebx, esi
    shr ebx, 16
    mov al, bl
    call serial_hex8
    mov ebx, esi
    shr ebx, 8
    mov al, bl
    call serial_hex8
    mov ebx, esi
    mov al, bl
    call serial_hex8
    pop ebx
    pop esi
    ret
serial_dec:                        ; eax
    pushfd
    cli                             ; the div chain needs EDX to survive
    push esi
    push edi
    push ebx
    push ecx
    push edx
    mov edi, numbuf + 15
    mov byte [edi], 0
    mov ecx, 0
    test eax, eax
    jnz .digits
    mov al, '0'
    call serial_putc
    jmp .out
.digits:
    xor edx, edx
    mov ebx, 10
.div:
    div ebx
    add dl, '0'
    dec edi
    mov [edi], dl
    inc ecx
    test eax, eax
    jnz .div
.flush:
    dec edi
    mov al, [edi]
    call serial_putc
    dec ecx
    jnz .flush
.out:
    pop edx
    pop ecx
    pop ebx
    pop edi
    pop esi
    popfd
    ret

; ===========================================================================
;  interrupt infrastructure
; ===========================================================================
idt_init:
    push eax
    push ebx
    push ecx
    push edi
    push esi
    mov edi, idt
    mov esi, isr_ptrs
    mov ecx, 256
.lp:
    mov ebx, [esi]
    mov eax, ebx
    and eax, 0xFFFF
    or eax, 0x00080000              ; gate: offset 15..0 | selector 0x0008
    mov [edi], eax
    mov eax, ebx
    and eax, 0xFFFF0000             ; gate: offset 31..16
    or eax, 0x8E00                  ; IST = 0, present, DPL 0, 32-bit int gate
    mov [edi+4], eax
    add edi, 8
    add esi, 4
    dec ecx
    jnz .lp
    mov word [idt_limit], 256 * 8 - 1
    mov dword [idt_base], idt
    lidt [idt_limit]                ; idt_limit + idt_base form the 6-byte operand
    pop esi
    pop edi
    pop ecx
    pop ebx
    pop eax
    ret

pic_init:
    mov al, 0x11
    out 0x20, al
    out 0xA0, al
    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xA1, al
    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xA1, al
    mov al, 0xFC                     ; timer + keyboard only
    out 0x21, al
    mov al, 0xEF                     ; unmask IRQ12 (mouse) on the slave
    out 0xA1, al
    ; default handler table, then install the real IRQ0 vector
    mov edi, irq_table
    mov ecx, 16
    mov eax, irq_default
    rep stosd
    mov dword [irq_table], isr_timer
    ret

timer_init:
    mov al, 0x36
    out 0x43, al
    mov al, 1193 & 0xFF              ; 1193180/1193 = 1000 Hz
    out 0x40, al
    mov al, 1193 >> 8
    out 0x40, al
    ret

irq_default:
    ret                             ; called via `call`, not an interrupt gate

; ---------------------------------------------------------------------------
;  exception screen
; ---------------------------------------------------------------------------
exc_handler:
    ; entered via `call` from isr_common, so the CPU frame sits behind the
    ; return address and the seven registers isr_common pushed:
    ;   [esp+0] esi [4] edi [8] ebp [12] retaddr [16] eax [20] ebx [24] ecx
    ;   [28] edx [32] esi [36] edi [40] ebp [44] intnum [48] errcode [52] eip
    push ebp
    push edi
    push esi
    mov ebp, [esp+64]               ; faulting eip
    mov esi, exc_msg                ; serial_puts takes esi
    call serial_puts
    mov al, ' '
    call serial_putc
    mov eax, [esp+56]               ; int number
    call serial_dec
    mov al, ' '
    call serial_putc
    mov eax, ebp
    call serial_hex32
    mov al, 0x0A
    call serial_putc
    ; paint a red screen
    push dword C_RED
    push dword 20
    push dword 320
    push dword 0
    push dword 0
    call gfx_fill
    add esp, 20
    push dword C_WHITE
    push dword C_RED
    push dword exc_title
    push dword 96
    push dword 60
    call gfx_textc
    add esp, 20
    push dword C_WHITE
    push dword C_RED
    push exc_line1
    push dword 20
    push dword 100
    call gfx_text
    add esp, 20
    push dword C_WHITE
    push dword C_RED
    push exc_line2
    push dword 20
    push dword 116
    call gfx_text
    add esp, 20
    call gfx_present
    pop esi
    pop edi
    pop ebp
    jmp panic

; ---------------------------------------------------------------------------
;  RTC (CMOS) time
; ---------------------------------------------------------------------------
rtc_init:
    ret

rtc_read:                          ; fills rtc_time/rtc_date (BCD decoded)
    push eax
    push ecx
    push edx
.uip:                              ; register A bit 7 = update in progress
    mov al, 0x0A
    call rtc_raw
    test al, 0x80
    jnz .uip
    mov al, 0x00
    call rtc_read_reg
    mov [rtc_sec], al
    mov al, 0x02
    call rtc_read_reg
    mov [rtc_min], al
    mov al, 0x04
    call rtc_read_reg
    mov [rtc_hour], al
    ; --- date layout -----------------------------------------------------
    ; Standard CMOS keeps day/wday/month/year at 0x05/0x06/0x07/0x08, but some
    ; emulators expose day at 0x07 with month/year at 0x08/0x09 and leave
    ; 0x05 empty. Pick whichever layout yields a valid day of month.
    mov al, 0x05
    call rtc_read_reg
    cmp al, 1
    jb .shift
    jg .std
    cmp al, 31
    ja .shift
.std:
    mov al, 0x05
    call rtc_read_reg
    mov [rtc_day], al
    mov al, 0x06
    call rtc_read_reg
    mov [rtc_wday], al
    mov al, 0x07
    call rtc_read_reg
    mov [rtc_mon], al
    mov al, 0x08
    call rtc_read_reg
    mov [rtc_year], al
    jmp .done
.shift:
    mov al, 0x07
    call rtc_read_reg
    mov [rtc_day], al
    mov al, 0x08
    call rtc_read_reg
    mov [rtc_mon], al
    mov al, 0x09
    call rtc_read_reg
    mov [rtc_year], al
    mov al, 0x06
    call rtc_read_reg
    mov [rtc_wday], al
.done:
    pop edx
    pop ecx
    pop eax
    ret

rtc_raw:                           ; al = register -> al = raw CMOS byte
    push ecx
    push edx
    out 0x70, al                     ; select CMOS register
    in al, 0x71                      ; read it back
    pop edx
    pop ecx
    ret

rtc_read_reg:                      ; al = register -> al = binary value
    call rtc_raw
    call bcd2bin
    ret

bcd2bin:                          ; al = bcd -> al = binary
    push ecx
    push edx
    movzx ecx, al
    mov eax, ecx
    and eax, 0x0F
    mov edx, ecx
    and edx, 0xF0
    shr edx, 4
    imul edx, edx, 10
    add eax, edx
    mov al, al
    pop edx
    pop ecx
    ret

; ---------------------------------------------------------------------------
;  boot splash
; ---------------------------------------------------------------------------
%macro MARK 1
    push eax
    push ecx
    push edx
    mov al, %1
    call serial_putc
    pop edx
    pop ecx
    pop eax
%endmacro

boot_splash:
    push esi
    push edi
    call wallpaper_build
    MARK 'b'
    MARK 'a'
    push dword 64000
    push dword WALLBUF
    push dword BACKBUF
    call gfx_copy
    MARK 'c'
    add esp, 12
    ; panel  (gfx_bevel x, y, w, h, light, face)
    push dword C_DKGRAY
    push dword C_LTGRAY
    push dword 6
    push dword 84
    push dword 60
    push dword 200
    call gfx_bevel
    MARK 'd'
    add esp, 24
    push dword C_WHITE
    push dword C_DKGRAY
    push dword splash_name
    push dword 160
    push dword 84
    call gfx_textc
    MARK 'e'
    add esp, 20
    push dword C_LTGRAY
    push dword C_DKGRAY
    push dword splash_ver
    push dword 160
    push dword 100
    call gfx_textc
    MARK 'f'
    add esp, 20
    push dword C_GRAY
    push dword C_DKGRAY
    push splash_msg
    push dword 160
    push dword 124
    call gfx_textc
    MARK 'g'
    add esp, 20
    ; progress bar
    push dword C_DKGRAY
    push dword C_BLACK
    push dword 14
    push dword 124
    push dword 126
    push dword 100
    call gfx_sunken
    MARK 'h'
    add esp, 24
    mov esi, 0
.lp:
    mov eax, esi
    shl eax, 1
    push dword C_TEAL
    push dword 10
    push eax
    push dword 128
    push dword 102
    call gfx_fill
    MARK 'i'
    add esp, 20
    call gfx_present
    push dword 40                 ; progress bar step delay (ms)
    call sleep_ms
    add esp, 4
    inc esi
    cmp esi, 118
    jl .lp
    mov esi, 0
.msg:
    push dword C_LTGRAY
    push dword C_DKGRAY
    push dword splash_ok
    push dword 160
    push dword 124
    call gfx_textc
    add esp, 20
    call gfx_present
    push dword 500                ; splash hold before desktop (ms)
    call sleep_ms
    add esp, 4
    pop edi
    pop esi
    ret

; ---------------------------------------------------------------------------
;  sleep_ms -- [ebp+8] = milliseconds; `ticks` counts IRQ0 at 1 kHz
; ---------------------------------------------------------------------------
sleep_ms:
    push ebp
    mov ebp, esp
    push ebx
    mov ebx, [ebp+8]
    mov eax, [ticks]
    add eax, ebx
    mov ebx, eax
.lp:
    sti
    hlt                             ; wake on the next IRQ0 tick
    cmp dword [ticks], ebx
    jb .lp
.l:
    pop ebx
    pop ebp
    ret

; ===========================================================================
;  data
; ===========================================================================
align 4
idt:            times 256 dq 0
idt_limit:      dw 0
idt_base:       dd 0

align 4
irq_table:      times 16 dd 0

wallpaper_style: dd 0
ticks:          dd 0
desk_mode:      dd 0                ; 0 = terminal owns the screen, 1 = desktop

numbuf:         times 16 db 0
rtc_sec:        dd 0
rtc_min:        dd 0
rtc_hour:       dd 0
rtc_day:        dd 0
rtc_wday:       dd 0
rtc_mon:        dd 0
rtc_year:       dd 0

tmp1:           dd 0
tmp2:           dd 0
tmp3:           dd 0
tmp4:           dd 0
wp_r:           dd 0
wp_g:           dd 0
wp_b:           dd 0
xpos:           dd 0

splash_name:    db 'D e k t o p O S', 0
splash_ver:     db 'version 1.0  -  32 bit protected mode', 0
splash_msg:     db 'starting desktop...', 0
splash_ok:      db 'ready.', 0
exc_msg:        db 'EXCEPTION', 0
exc_title:      db 'KERNEL PANIC', 0
exc_line1:      db 'The system has been halted.', 0
exc_line2:      db 'Reboot the machine to continue.', 0

%include "font8x8.inc"
%include "icons.inc"
%include "gfx.asm"
%include "wall.asm"
%include "isr.asm"
%include "kbd.asm"
%include "mouse.asm"
%include "fs.inc"
%include "term.asm"
%include "shell.asm"
%include "wm.asm"
%include "apps.asm"
