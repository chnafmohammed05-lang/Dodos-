; ============================================================================
;  fs.inc -- a small read/write volume held in RAM between HEAP and STACKTOP.
;  It is populated at boot with a handful of files so the desktop has
;  something to show; there is no on-disk format yet.
; ============================================================================

FS_MAX         equ 12
FS_STRSZ       equ 32

struc FSFILE
  .name        resd 1                 ; -> NUL terminated name
  .data        resd 1                 ; -> contents, NUL terminated
  .size        resd 1                 ; length in bytes
  .icon        resd 1                 ; -> icon bitmap
  .isdir       resd 1
  .parent      resd 1                 ; index of the containing directory
endstruc
FSFILE_SIZE   equ 24
FS_NONE       equ 0xFFFFFFFF           ; "no parent" sentinel

align 4
fs_files:      times FS_MAX * FSFILE_SIZE db 0
fs_count:      dd 0
fs_cwd:        dd 0                   ; index of the current directory

; ---------------------------------------------------------------------------
;  fs_add(name, data, icon, isdir, parent)
; ---------------------------------------------------------------------------
fs_add:
    push eax
    push ebx
    push ecx
    push edx
    mov ecx, [fs_count]
    cmp ecx, FS_MAX
    jae .done
    imul eax, ecx, FSFILE_SIZE
    add eax, fs_files
    mov ebx, [esp + 20]
    mov [eax + FSFILE.name], ebx
    mov ebx, [esp + 24]
    mov [eax + FSFILE.data], ebx
    mov ebx, [esp + 28]
    mov [eax + FSFILE.icon], ebx
    mov ebx, [esp + 32]
    mov [eax + FSFILE.isdir], ebx
    mov ebx, [esp + 36]
    mov [eax + FSFILE.parent], ebx
    mov edx, [esp + 24]              ; measure the payload
    xor ecx, ecx
.len:
    mov bl, [edx + ecx]
    test bl, bl
    je .lend
    inc ecx
    jmp .len
.lend:
    mov [eax + FSFILE.size], ecx
    inc dword [fs_count]
.done:
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ---------------------------------------------------------------------------
;  fs_ptr(index) -> eax = FSFILE pointer
; ---------------------------------------------------------------------------
fs_ptr:
    imul eax, FSFILE_SIZE
    add eax, fs_files
    ret

; ---------------------------------------------------------------------------
;  fs_index(eax = FSFILE pointer) -> eax = index
; ---------------------------------------------------------------------------
fs_index:
    sub eax, fs_files
    xor edx, edx
    mov ecx, FSFILE_SIZE
    div ecx
    ret

; ---------------------------------------------------------------------------
;  fs_find(name) -> eax = FSFILE pointer for a child of fs_cwd, or 0
;  The name arrives as a stack argument. It is copied out before any push so
;  the frame offsets stay trivial. strcmp destroys eax and esi, so the loop
;  index lives in ebx and the pointer is rebuilt from it on a match.
; ---------------------------------------------------------------------------
fs_find:
    mov edi, [esp + 4]               ; the name we seek, grabbed first
    push ebx
    push ecx
    push edx
    xor ebx, ebx
.next:
    cmp ebx, [fs_count]
    jae .none
    cmp ebx, [fs_cwd]               ; a directory is never its own child
    je .skip
    mov eax, ebx
    call fs_ptr
    mov ecx, [eax + FSFILE.parent]
    cmp ecx, [fs_cwd]
    jne .skip
    mov esi, [eax + FSFILE.name]    ; esi = the candidate
    mov eax, edi                    ; eax = the name we seek
    call strcmp                     ; 0 when they match
    test eax, eax
    jz .found
.skip:
    inc ebx
    jmp .next
.none:
    xor eax, eax
    jmp .out
.found:
    mov eax, ebx
    call fs_ptr
.out:
    pop edx
    pop ecx
    pop ebx
    ret

; ---------------------------------------------------------------------------
;  strcmp(eax = a, esi = b) -> eax = 0 when equal (case insensitive)
; ---------------------------------------------------------------------------
strcmp:
    push ebx
    push ecx
.loop:
    movzx ebx, byte [eax]
    movzx ecx, byte [esi]
    ; fold to upper case
    cmp bl, 'a'
    jb .a1
    cmp bl, 'z'
    ja .a1
    sub bl, 32
.a1:
    cmp cl, 'a'
    jb .a2
    cmp cl, 'z'
    ja .a2
    sub cl, 32
.a2:
    cmp bl, cl
    jne .diff
    test bl, bl
    jz .same
    inc eax
    inc esi
    jmp .loop
.same:
    xor eax, eax
    jmp .out
.diff:
    mov eax, 1
.out:
    pop ecx
    pop ebx
    ret

; ---------------------------------------------------------------------------
;  fs_init -- build the initial volume. Index 0 is always the root, so that
;  fs_cwd = 0 is a sane starting point and every entry has a parent.
; ---------------------------------------------------------------------------
fs_init:
    ; --- "/" the root. Its parent is the sentinel so it is nobody's child.
    push dword FS_NONE
    push dword 1
    push dword icon_folder
    push dword dir_root
    push dword n_root
    call fs_add
    add esp, 20

    ; --- DOCS
    push dword 0
    push dword 1
    push dword icon_folder
    push dword dir_docs
    push dword n_docs
    call fs_add
    add esp, 20

    ; --- GFX
    push dword 0
    push dword 1
    push dword icon_folder
    push dword dir_gfx
    push dword n_gfx
    call fs_add
    add esp, 20

    ; --- README.TXT
    push dword 0
    push dword 0
    push dword icon_file
    push dword txt_readme
    push dword n_readme
    call fs_add
    add esp, 20

    ; --- TODO.TXT
    push dword 0
    push dword 0
    push dword icon_file
    push dword txt_todo
    push dword n_todo
    call fs_add
    add esp, 20

    ; --- ABOUT.TXT
    push dword 0
    push dword 0
    push dword icon_file
    push dword txt_about
    push dword n_about_txt
    call fs_add
    add esp, 20
    ret

n_root:     db "/", 0
n_docs:     db "DOCS", 0
n_gfx:      db "GFX", 0
n_readme:   db "README.TXT", 0
n_todo:     db "TODO.TXT", 0
n_about_txt:    db "ABOUT.TXT", 0

dir_root:   db "The root directory.", 0
dir_docs:   db "System documents.", 0
dir_gfx:   db "Graphics and fonts.", 0
txt_readme:
    db "DektopOS", 13, 10
    db "=========", 13, 10, 13, 10
    db "Welcome to DektopOS.", 13, 10, 13, 10
    db "Type HELP at the prompt for", 13, 10
    db "the list of commands.", 0
txt_todo:
    db "TODO", 13, 10, 13, 10
    db "- window dragging", 13, 10
    db "- on disk filesystem", 13, 10
    db "- more colours", 0
txt_about:
    db "DektopOS 0.1", 13, 10
    db "A 32 bit protected mode", 13, 10
    db "desktop written in x86 asm.", 0
