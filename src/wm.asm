; ============================================================================
;  wm.asm -- a very small window manager.
;
;  Windows live in a fixed table.  Each has a frame (bevel plus a title bar)
;  and a content area that the owning application draws into.  The manager
;  handles focus, dragging by the title bar, the close box and the taskbar
;  buttons; everything else is left to the application.
; ============================================================================

WM_MAX         equ 4
WM_BTN_W       equ 12
WM_PAD         equ 2                 ; frame thickness around the client area
WM_MIN_W       equ 60
WM_MIN_H       equ 40

struc WINDOW
  .x           resd 1
  .y           resd 1
  .w           resd 1
  .h           resd 1
  .app         resd 1                 ; APP_* id
  .flags       resd 1                 ; WIN_*
  .title       resd 1                 ; -> title text
  .state       resd 1                 ; per application scratch
  .state2      resd 1
  .state3      resd 1
  .state4      resd 1
  .state5      resd 1
  .state6      resd 1
endstruc
WINDOW_SIZE   equ 52

align 4
wm_windows:    times WM_MAX * WINDOW_SIZE db 0
wm_count:      dd 0
wm_focus:      dd -1
wm_drag:       dd -1                  ; window being dragged, -1 when idle
wm_dragx:      dd 0
wm_dragy:      dd 0

; ---------------------------------------------------------------------------
;  wm_open(app, title, x, y, w, h) -> eax = WINDOW *
; ---------------------------------------------------------------------------
wm_open:
    push ebp
    mov ebp, esp
    push ebx
    mov eax, [wm_count]
    cmp eax, WM_MAX
    jae .full
    imul eax, WINDOW_SIZE
    add eax, wm_windows
    mov ebx, [ebp + 8]
    mov [eax + WINDOW.app], ebx
    mov ebx, [ebp + 12]
    mov [eax + WINDOW.title], ebx
    mov ebx, [ebp + 16]
    mov [eax + WINDOW.x], ebx
    mov ebx, [ebp + 20]
    mov [eax + WINDOW.y], ebx
    mov ebx, [ebp + 24]
    mov [eax + WINDOW.w], ebx
    mov ebx, [ebp + 28]
    mov [eax + WINDOW.h], ebx
    mov dword [eax + WINDOW.flags], WIN_VISIBLE | WIN_FOCUSED
    mov dword [eax + WINDOW.state], 0
    mov dword [eax + WINDOW.state2], 0
    mov dword [eax + WINDOW.state3], 0
    mov dword [eax + WINDOW.state4], 0
    mov dword [eax + WINDOW.state5], 0
    mov dword [eax + WINDOW.state6], 0
    inc dword [wm_count]
    mov ecx, [wm_count]
    dec ecx
    mov [wm_focus], ecx
    jmp .out
.full:
    xor eax, eax
.out:
    pop ebx
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  wm_focus_set(n)
; ---------------------------------------------------------------------------
wm_focus_set:
    push eax
    push ecx
    mov ecx, [esp + 12]             ; argument, not the return address
    mov [wm_focus], ecx
    xor eax, eax
.focus_loop:
    cmp eax, [wm_count]
    jae .focus_done
    imul ecx, eax, WINDOW_SIZE
    add ecx, wm_windows
    test dword [ecx + WINDOW.flags], WIN_VISIBLE
    jz .focus_next
    cmp eax, [wm_focus]
    je .focus_set
    and dword [ecx + WINDOW.flags], ~WIN_FOCUSED
    jmp .focus_next
.focus_set:
    or dword [ecx + WINDOW.flags], WIN_FOCUSED
.focus_next:
    inc eax
    jmp .focus_loop
.focus_done:
    pop ecx
    pop eax
    ret

; ---------------------------------------------------------------------------
;  wm_hit(mx, my) -> eax = WINDOW * (topmost) or 0
; ---------------------------------------------------------------------------
wm_hit:
    push ebp
    mov ebp, esp
    push ebx
    push ecx
    push edx
    mov ecx, [wm_count]
    dec ecx
.scan:
    test ecx, ecx
    js .none
    imul eax, ecx, WINDOW_SIZE
    add eax, wm_windows
    push eax
    test dword [eax + WINDOW.flags], WIN_VISIBLE
    jz .skip
    mov ebx, [eax + WINDOW.x]
    cmp ebx, [ebp + 8]
    jg .skip
    mov ebx, [eax + WINDOW.w]
    add ebx, [eax + WINDOW.x]
    cmp ebx, [ebp + 8]
    jl .skip
    mov ebx, [eax + WINDOW.y]
    cmp ebx, [ebp + 12]
    jg .skip
    mov ebx, [eax + WINDOW.h]
    add ebx, [eax + WINDOW.y]
    cmp ebx, [ebp + 12]
    jl .skip
    pop eax
    jmp .out
.skip:
    pop eax
    dec ecx
    jmp .scan
.none:
    xor eax, eax
.out:
    pop edx
    pop ecx
    pop ebx
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  wm_close(w)  -- hide the window and drop it out of the focus chain
; ---------------------------------------------------------------------------
wm_close:
    push eax
    and dword [eax + WINDOW.flags], ~WIN_VISIBLE
    call wm_index_of
    mov ecx, eax
    cmp ecx, [wm_focus]
    jne .done
    mov eax, [wm_count]
    dec eax
    cmp ecx, eax
    jle .keep
    mov [wm_focus], eax
    jmp .apply
.keep:
    mov eax, -1
.apply:
    push eax
    call wm_focus_set
    add esp, 4
.done:
    pop eax
    ret

; ---------------------------------------------------------------------------
;  wm_index_of(w) -> eax = index of w, or -1
; ---------------------------------------------------------------------------
wm_index_of:
    push ecx
    push edx
    xor ecx, ecx
.loop:
    cmp ecx, [wm_count]
    jae .none
    mov edx, ecx
    imul edx, WINDOW_SIZE
    add edx, wm_windows
    cmp edx, [esp + 12]
    je .found
    inc ecx
    jmp .loop
.found:
    mov eax, ecx
    jmp .out
.none:
    mov eax, -1
.out:
    pop edx
    pop ecx
    ret

; ---------------------------------------------------------------------------
;  wm_draw  -- taskbar first, then every visible window back to front
; ---------------------------------------------------------------------------
wm_draw:
    push eax
    push ebx
    push ecx
    xor ecx, ecx
.loop:
    cmp ecx, [wm_count]
    jae .done
    imul eax, ecx, WINDOW_SIZE
    add eax, wm_windows
    test dword [eax + WINDOW.flags], WIN_VISIBLE
    jz .next
    push eax
    call wm_draw_one
    add esp, 4
.next:
    inc ecx
    jmp .loop
.done:
    call draw_panel               ; after the windows, so nothing paints over it
    call draw_start_menu          ; the popup sits on top of the panel
    call draw_cursor
    pop ecx
    pop ebx
    pop eax
    ret

; ---------------------------------------------------------------------------
;  wm_draw_one(w)  -- frame, title bar, then hand over to the application
; ---------------------------------------------------------------------------
wm_draw_one:
    push ebp
    mov ebp, esp
    push eax
    push ebx
    mov eax, [ebp + 8]
    mov ebx, [eax + WINDOW.x]
    mov ecx, [eax + WINDOW.y]
    mov edx, [eax + WINDOW.w]
    mov esi, [eax + WINDOW.h]
    test dword [eax + WINDOW.flags], WIN_FOCUSED
    jz .unfocused
    mov dword [wmb_light], C_WHITE
    mov dword [wmb_face], C_GRAY
    jmp .frame
.unfocused:
    mov dword [wmb_light], C_LTGRAY
    mov dword [wmb_face], C_DKGRAY
.frame:
    push dword [wmb_light]
    push dword [wmb_face]
    push esi
    push edx
    push ecx
    push ebx
    call gfx_bevel
    add esp, 24
    ; client area
    lea eax, [ebx + WM_PAD]
    mov [wmb_cx], eax
    lea eax, [ecx + WM_PAD]
    mov [wmb_cy], eax
    mov eax, edx
    sub eax, WM_PAD * 2
    mov [wmb_cw], eax
    mov eax, esi
    sub eax, WM_PAD * 2
    mov [wmb_ch], eax
    push dword C_DKGRAY
    push dword [wmb_ch]
    push dword [wmb_cw]
    push dword [wmb_cy]
    push dword [wmb_cx]
    call gfx_fill
    add esp, 20
    ; the application gets the area below the title bar
    mov eax, [wmb_cy]
    add eax, TITLE_H
    mov [wmb_ay], eax
    mov eax, [wmb_ch]
    sub eax, TITLE_H
    mov [wmb_ah], eax
    ; title bar
    mov eax, [wmb_cx]
    mov ecx, [wmb_cy]
    mov edx, [wmb_cw]
    mov ebx, TITLE_H
    push dword [wmb_face]
    push ebx
    push edx
    push ecx
    push eax
    call gfx_fill
    add esp, 20
    ; title text
    mov eax, [ebp + 8]
    mov eax, [eax + WINDOW.title]
    mov ebx, [wmb_cx]
    add ebx, 3
    mov ecx, [wmb_cy]
    add ecx, (TITLE_H - 8) / 2
    push dword C_BLACK
    push dword C_WHITE
    push eax
    push ecx
    push ebx
    call gfx_text
    add esp, 20
    ; close box
    mov eax, [wmb_cx]
    mov ecx, [wmb_cw]
    add eax, ecx
    sub eax, WM_BTN_W - 2
    mov ecx, [wmb_cy]
    add ecx, 2
    push dword C_LTGRAY
    push dword C_RED
    push dword 8
    push dword 8
    push ecx
    push eax
    call gfx_bevel
    add esp, 24
    mov eax, [wmb_cx]
    mov ecx, [wmb_cw]
    add eax, ecx
    sub eax, WM_BTN_W - 3
    mov [wmb_bx], eax
    mov eax, [wmb_cy]
    add eax, 3
    mov [wmb_by], eax
    ; content
    mov eax, [ebp + 8]
    push dword [ebp + 8]
    call app_draw
    add esp, 4
    pop ebx
    pop eax
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  draw_panel -- Plasma-style bottom panel: a vertical gradient background
;  with a top highlight, a Menu button, one task button per window showing
;  its icon and a short title, and a clock/date block on the right.
; ---------------------------------------------------------------------------
draw_panel:
    push ebp
    mov ebp, esp
    push ebx
    push ecx
    push edx
    ; ---- background gradient
    push dword RAMP_DARK + 10
    push dword RAMP_DARK + 2
    push dword PANEL_H
    push dword SCRW
    push dword PANEL_Y
    push dword 0
    call gfx_vgrad
    add esp, 24
    ; ---- 1px highlight along the top edge
    push dword RAMP_DARK + 15
    push dword SCRW
    push dword PANEL_Y
    push dword 0
    call gfx_hline
    add esp, 16
    ; ---- Menu button
    push dword RAMP_BLUE + 13
    push dword RAMP_BLUE + 5
    push dword PBTN_H
    push dword 38
    push dword PBTN_Y
    push dword 1
    call gfx_vgrad
    add esp, 24
    push dword RAMP_DARK + 2
    push dword PBTN_H
    push dword 38
    push dword PBTN_Y
    push dword 1
    call gfx_corners
    add esp, 20
    push dword RAMP_DARK + 2
    push dword C_WHITE
    push dword pmenu_lbl
    push dword PBTN_Y + 4
    push dword 5
    call gfx_text
    add esp, 20
    ; ---- separator
    push dword RAMP_DARK + 14
    push dword PBTN_H
    push dword PBTN_Y
    push dword 41
    call gfx_vline
    add esp, 16
    ; ---- one task button per window
    mov dword [pan_x], 44
    xor ecx, ecx
.btn:
    cmp ecx, [wm_count]
    jae .btndone
    mov eax, ecx
    imul eax, WINDOW_SIZE
    add eax, wm_windows
    mov [pan_win], eax
    test dword [eax + WINDOW.flags], WIN_VISIBLE
    jz .btnnext
    test dword [pan_win + WINDOW.flags], WIN_FOCUSED
    jz .unfoc
    push dword RAMP_BLUE + 12
    push dword RAMP_BLUE + 6
    mov dword [pan_tbg], RAMP_BLUE + 9
    jmp .face
.unfoc:
    push dword RAMP_DARK + 9
    push dword RAMP_DARK + 3
    mov dword [pan_tbg], RAMP_DARK + 6
.face:
    push dword PBTN_H
    push dword PBTN_W
    push dword PBTN_Y
    mov eax, [pan_x]
    push eax
    call gfx_vgrad
    add esp, 24
    ; icon
    mov eax, [pan_win]
    mov edx, [eax + WINDOW.app]
    imul edx, 4
    add edx, app_icons
    mov edx, [edx]
    push dword 1
    push edx
    push dword ICON_H
    push dword ICON_W
    push dword PBTN_Y + 2
    mov eax, [pan_x]
    add eax, 3
    push eax
    call gfx_sprite
    add esp, 24
    ; short title
    mov eax, [pan_win]
    mov edx, [eax + WINDOW.app]
    imul edx, 4
    add edx, app_short
    mov edx, [edx]
    push dword [pan_tbg]
    push dword C_WHITE
    push edx
    push dword PBTN_Y + 4
    mov eax, [pan_x]
    add eax, 18
    push eax
    call gfx_text
    add esp, 20
.btnnext:
    mov eax, [pan_x]
    add eax, PBTN_DX
    mov [pan_x], eax
    inc ecx
    jmp .btn
.btndone:
    ; ---- clock
    call rtc_read
    mov al, [rtc_hour]
    call two_digits
    mov [wm_clk_buf], al
    mov [wm_clk_buf + 1], ah
    mov byte [wm_clk_buf + 2], ':'
    mov al, [rtc_min]
    call two_digits
    mov [wm_clk_buf + 3], al
    mov [wm_clk_buf + 4], ah
    mov byte [wm_clk_buf + 5], 0
    push dword RAMP_DARK + 6
    push dword C_WHITE
    push dword wm_clk_buf
    push dword PANEL_Y + 3
    push dword 272
    call gfx_text
    add esp, 20
    ; ---- date
    mov al, [rtc_day]
    call two_digits
    mov [dte_buf], al
    mov [dte_buf + 1], ah
    mov byte [dte_buf + 2], '/'
    mov al, [rtc_mon]
    call two_digits
    mov [dte_buf + 3], al
    mov [dte_buf + 4], ah
    mov byte [dte_buf + 5], 0
    push dword RAMP_DARK + 6
    push dword C_LTGRAY
    push dword dte_buf
    push dword PANEL_Y + 11
    push dword 272
    call gfx_text
    add esp, 20
    pop edx
    pop ecx
    pop ebx
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  wm_menu_rect(mx, my) -> eax = 1 when the point is inside the start menu
; ---------------------------------------------------------------------------
wm_menu_rect:
    push ebp
    mov ebp, esp
    push dword [ebp + 8]
    push dword [ebp + 12]
    mov eax, [ebp + 12]
    cmp eax, SM_X
    jb .out0
    add eax, SM_W
    cmp [ebp + 8], eax
    jae .out0
    mov eax, [ebp + 12]
    cmp eax, SM_Y
    jb .out0
    add eax, SM_H
    cmp [ebp + 8], eax
    jae .out0
    mov eax, 1
    jmp .out
.out0:
    xor eax, eax
.out:
    pop edx
    pop ecx
    lea esp, [ebp - 8]
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  wm_menu_click -- a click happened while the start menu was open
; ---------------------------------------------------------------------------
wm_menu_click:
    push ebp
    mov ebp, esp
    push dword [mouse_x]
    push dword [mouse_y]
    call wm_menu_rect
    add esp, 8
    test eax, eax
    jz .dismiss
    ; which row?
    mov eax, [mouse_y]
    sub eax, SM_Y
    sub eax, SM_PAD
    xor ecx, ecx
    cmp eax, 0
    jl .dismiss
.row:
    cmp ecx, APP_COUNT
    jae .dismiss
    mov edx, ecx
    imul edx, SM_ITEM_H
    cmp eax, edx
    jb .launch
    add edx, SM_ITEM_H
    cmp eax, edx
    jae .next
.launch:
    mov dword [sm_open], 0
    push ecx
    call wm_open_app
    add esp, 4
    jmp .out
.next:
    inc ecx
    jmp .row
.dismiss:
    mov dword [sm_open], 0
.out:
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  draw_start_menu -- the launcher popup, drawn over everything else
; ---------------------------------------------------------------------------
draw_start_menu:
    cmp dword [sm_open], 0
    je .out
    push dword C_WHITE               ; light
    push dword C_GRAY                ; face
    push dword SM_H
    push dword SM_W
    push dword SM_Y
    push dword SM_X
    call gfx_bevel
    add esp, 24
    push dword RAMP_DARK + 1
    push dword SM_ITEM_H * APP_COUNT
    push dword SM_W - 4
    push dword SM_Y + 2 + SM_PAD
    push dword SM_X + 2
    call gfx_fill
    add esp, 20
    push dword [mouse_x]
    push dword [mouse_y]
    call wm_menu_rect
    add esp, 8
    mov [sm_hover], eax
    xor ecx, ecx
    mov ebx, SM_Y + 2 + SM_PAD
.item:
    cmp ecx, APP_COUNT
    jae .out
    ; row background: highlight the one under the pointer
    xor eax, eax
    cmp dword [sm_hover], 0
    je .nohl
    imul edx, ecx, SM_ITEM_H
    add edx, ebx
    cmp [mouse_y], edx
    jb .nohl
    add edx, SM_ITEM_H
    cmp [mouse_y], edx
    jae .nohl
    mov eax, RAMP_BLUE + 7
.nohl:
    push dword eax
    push dword SM_ITEM_H - 1
    push dword SM_W - 4
    push dword ebx
    push dword SM_X + 2
    call gfx_fill
    add esp, 20
    ; icon
    mov eax, ecx
    imul eax, 4
    add eax, app_icons
    mov eax, [eax]
    push dword 1
    push dword eax
    push dword ICON_H
    push dword ICON_W
    mov eax, ebx
    add eax, 3
    push dword eax
    push dword SM_X + 5
    call gfx_sprite
    add esp, 24
    ; label
    mov eax, ecx
    imul eax, 4
    add eax, app_titles
    mov eax, [eax]
    push dword C_NAVY                ; fg
    push dword C_WHITE               ; bg
    push dword eax
    mov eax, ebx
    add eax, 4
    push dword eax
    push dword SM_X + 20
    call gfx_text
    add esp, 20
    add ebx, SM_ITEM_H
    inc ecx
    jmp .item
.out:
    ret

; ---------------------------------------------------------------------------
;  two_digits: al = value -> al = tens char, ah = units char
; ---------------------------------------------------------------------------
two_digits:
    push ecx
    mov ah, al
    shr ah, 4
    and al, 0x0F
    add al, '0'
    add ah, '0'
    pop ecx
    ret

; ---------------------------------------------------------------------------
;  draw_cursor -- a small arrow at the mouse position
; ---------------------------------------------------------------------------
draw_cursor:
    push dword 1                    ; zoom
    push dword icon_cursor
    push dword 8                    ; rows
    push dword 6                    ; bytes per row
    push dword [mouse_y]
    push dword [mouse_x]
    call gfx_sprite
    add esp, 24
    ret

align 4
wmb_light: dd 0
wmb_face:  dd 0
wmb_cx:    dd 0
wmb_cy:    dd 0
wmb_cw:    dd 0
wmb_ch:    dd 0
wmb_ay:    dd 0                  ; top of the app content area (below the title bar)
wmb_ah:    dd 0                  ; height of the app content area
wmb_bx:    dd 0
wmb_by:    dd 0
sm_open:   dd 0
sm_hover:  dd 0

align 4
tb_brand:  db "DektopOS", 0
pmenu_lbl: db "Menu", 0
app_short:
    dd sh_term, sh_note, sh_file, sh_calc, sh_paint, sh_about
sh_term:   db "Term", 0
sh_note:   db "Note", 0
sh_file:   db "File", 0
sh_calc:   db "Calc", 0
sh_paint:  db "Pain", 0
sh_about:  db "Info", 0
dte_buf:   db "00/00", 0
wm_clk_buf:   db "00:00", 0
pan_x:     dd 0
pan_win:   dd 0
pan_tbg:   dd 0

; ---------------------------------------------------------------------------
;  wm_events  -- mouse handling: taskbar buttons, focus, close, drag, icons
; ---------------------------------------------------------------------------
wm_events:
    call wm_drag_move
    call mouse_consume              ; eax = button edge flags
    mov edx, [mouse_buttons]
    test edx, 1
    jz .out                        ; only act while a button is down
    ; --- the open start menu takes every click first ---
    cmp dword [sm_open], 0
    je .nopopup
    call wm_menu_click
    jmp .out
.nopopup:
    ; --- the panel ---
    mov eax, [mouse_y]
    cmp eax, PANEL_Y
    jae .client
    ; Menu button
    cmp dword [mouse_x], MENU_X
    jb .tb
    mov eax, MENU_X
    add eax, MENU_W
    cmp [mouse_x], eax
    jae .tb
    mov dword [sm_open], 1
    jmp .out
    ; one task button per window
.tb:
    mov ebx, TBTN_X0
    xor ecx, ecx
.tbloop:
    cmp ecx, [wm_count]
    jae .out
    mov eax, ebx
    add eax, PBTN_W
    cmp [mouse_x], ebx
    jb .tbnext
    cmp [mouse_x], eax
    jae .tbnext
    cmp dword [mouse_y], PBTN_Y
    jb .tbnext
    mov eax, PBTN_Y
    add eax, PBTN_H
    cmp [mouse_y], eax
    jae .tbnext
    imul edx, ecx, WINDOW_SIZE
    add edx, wm_windows
    test dword [edx + WINDOW.flags], WIN_VISIBLE
    jz .tbnext
    push ecx
    call wm_focus_set
    add esp, 4
    jmp .out
.tbnext:
    add ebx, PBTN_DX
    inc ecx
    jmp .tbloop
    ; --- a window ---
.client:
    push dword [mouse_y]
    push dword [mouse_x]
    call wm_hit
    add esp, 8
    test eax, eax
    jz .icon
    mov ebx, eax
    push eax
    call wm_index_of
    add esp, 4
    mov [wm_last], eax
    cmp eax, [wm_focus]
    je .havesel
    push eax
    call wm_focus_set
    add esp, 4
.havesel:
    ; close box?
    mov eax, [ebx + WINDOW.x]
    add eax, [ebx + WINDOW.w]
    sub eax, 12
    cmp [mouse_x], eax
    jb .title
    add eax, 8
    cmp [mouse_x], eax
    jae .title
    mov eax, [ebx + WINDOW.y]
    add eax, 4
    cmp [mouse_y], eax
    jb .title
    add eax, 8
    cmp [mouse_y], eax
    jae .title
    push ebx
    call wm_close
    add esp, 4
    jmp .out
.title:
    ; start dragging?
    mov eax, [ebx + WINDOW.y]
    add eax, 2 + TITLE_H
    cmp [mouse_y], eax
    jae .content
    mov eax, [wm_last]
    mov [wm_drag], eax
    mov eax, [mouse_x]
    sub eax, [ebx + WINDOW.x]
    mov [wm_dragx], eax
    mov eax, [mouse_y]
    sub eax, [ebx + WINDOW.y]
    mov [wm_dragy], eax
    jmp .out
.content:
    call app_click
    jmp .out
    ; --- a desktop icon ---
.icon:
    xor ecx, ecx
    mov edx, DESK_X
    mov ebx, DESK_Y0
.iloop:
    cmp ecx, APP_COUNT
    jae .out
    mov eax, ebx
    add eax, ICON_H
    cmp [mouse_y], ebx
    jb .inext
    cmp [mouse_y], eax
    jae .inext
    mov eax, edx
    add eax, ICON_W
    cmp [mouse_x], edx
    jb .inext
    cmp [mouse_x], eax
    jae .inext
    push ecx
    call wm_open_app
    add esp, 4
    jmp .out
.inext:
    add ebx, DESK_DY
    inc ecx
    jmp .iloop
.out:
    ret

; ---------------------------------------------------------------------------
;  app_click  -- a click inside the focused window's client area
; ---------------------------------------------------------------------------
app_click:
    push eax
    mov eax, [wm_focus]
    cmp eax, 0
    jl .out
    imul eax, eax, WINDOW_SIZE
    add eax, wm_windows
    mov ebx, eax
    lea eax, [ebx + WINDOW.x]
    add eax, WM_PAD
    mov [wmx_cx], eax
    lea eax, [ebx + WINDOW.y]
    add eax, WM_PAD + TITLE_H
    mov [wmx_cy], eax
    mov eax, [ebx + WINDOW.w]
    sub eax, WM_PAD * 2
    mov [wmx_cw], eax
    mov eax, [ebx + WINDOW.h]
    sub eax, WM_PAD * 2
    mov [wmx_ch], eax
    push ebx
    call app_mouse
    add esp, 4
.out:
    pop eax
    ret

; ---------------------------------------------------------------------------
;  wm_drag_move  -- follow the mouse while a window is being dragged
; ---------------------------------------------------------------------------
wm_drag_move:
    cmp dword [wm_drag], -1
    je .out
    mov eax, [mouse_buttons]
    test eax, 1
    jz .end
    imul eax, [wm_drag], WINDOW_SIZE
    add eax, wm_windows
    ; x
    mov ecx, [mouse_x]
    sub ecx, [wm_dragx]
    cmp ecx, 0
    jge .xok
    xor ecx, ecx
.xok:
    mov edx, [eax + WINDOW.w]
    neg edx
    add ecx, edx
    cmp ecx, 0
    jge .xset
    xor ecx, ecx
.xset:
    mov [eax + WINDOW.x], ecx
    ; y
    mov ecx, [mouse_y]
    sub ecx, [wm_dragy]
    cmp ecx, 0
    jge .yok
    xor ecx, ecx
.yok:
    mov edx, [eax + WINDOW.y]
    add edx, [eax + WINDOW.h]
    sub edx, SCRH - PANEL_H - 2
    cmp ecx, edx
    jle .yset
    mov ecx, edx
.yset:
    mov [eax + WINDOW.y], ecx
    jmp .out
.end:
    mov dword [wm_drag], -1
.out:
    ret

; ---------------------------------------------------------------------------
;  wm_open_app(app)
; ---------------------------------------------------------------------------
wm_open_app:
    push ebp
    mov ebp, esp
    push eax
    push dword 150                  ; h
    push dword 200                  ; w
    push dword 24                   ; y
    push dword 60                   ; x
    mov eax, [ebp + 8]
    cmp eax, APP_ABOUT
    jne .go
    add esp, 16                     ; drop the default x,y,w,h ...
.small:
    push dword 70                   ; h
    push dword 150                  ; w
    push dword 110                  ; y
    push dword 60                   ; x
.go:
    mov eax, [ebp + 8]
    shl eax, 2
    add eax, app_titles
    mov eax, [eax]
    push eax
    mov eax, [ebp + 8]
    push eax
    call wm_open
    add esp, 24
    pop eax
    pop ebp
    ret

; ---------------------------------------------------------------------------
;  wm_desk_icons  -- the launcher icons on the desktop
; ---------------------------------------------------------------------------
wm_desk_icons:
    push eax
    push ebx
    push ecx
    push edx
    xor ecx, ecx
    mov edx, DESK_X
    mov ebx, DESK_Y0
.loop:
    cmp ecx, APP_COUNT
    jae .out
    mov eax, ecx
    imul eax, 4
    add eax, app_icons
    mov eax, [eax]
    push dword 1
    push eax
    push dword ICON_H
    push dword ICON_W
    push ebx
    push edx
    call gfx_sprite
    add esp, 24                     ; 6 args
    ; label
    mov eax, ecx
    imul eax, 4
    add eax, app_titles
    mov eax, [eax]
    push dword C_WHITE              ; bg
    push dword C_NAVY               ; fg
    push eax                        ; the title string
    push dword ebx
    add dword [esp], 13
    push edx                        ; cx
    call gfx_textc
    add esp, 20                     ; 5 args: cx, y, str, fg, bg
    add ebx, DESK_DY
    inc ecx
    jmp .loop
.out:
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

DESK_X       equ 8
DESK_Y0      equ 24
DESK_DY      equ 26

align 4
wm_last:     dd 0

align 4
app_titles:
    dd term_title, np_title, fs_title, calc_title, paint_title, about_title
term_title:  db "Terminal", 0
np_title:    db "Notepad", 0
fs_title:    db "Files", 0
calc_title:  db "Calculator", 0
paint_title: db "Paint", 0
about_title: db "About", 0
align 4
wmx_cx:     dd 0
wmx_cy:     dd 0
wmx_cw:     dd 0
wmx_ch:     dd 0
