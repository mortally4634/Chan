; =============================================================================
;  Chan Linux  --  /init  (PID 1): shell + 'four' package manager
; -----------------------------------------------------------------------------
;  A freestanding x86-64 Linux executable in pure assembly. No libc, no linker:
;  the ELF64 header is emitted by hand, so `nasm -f bin` produces a ready-to-run
;  static Linux binary on its own.
;
;  As PID 1 the kernel execs this. It:
;    1. mounts /proc (best effort) and reads real kernel info via uname()
;    2. prints a four-leaf-clover logo + fastfetch-style panel
;    3. runs an interactive shell: help, clear, echo, fetch, uname,
;       poweroff, reboot, and 'four' (the package manager)
;
;  'four' manages packages as files under /var/four:
;       available/<pkg>   the repository
;       installed/<pkg>   installed state (real on-disk database)
;  four list | installed | install <p> | remove <p> | info <p> | help
;
;  PID 1 must never exit (the kernel panics), so the shell loop is infinite
;  and only the explicit poweroff/reboot commands end the session.
;
;  Build:  nasm -f bin src/init.asm -o build/init
; =============================================================================

BITS 64
org 0x400000

; ----- ELF64 header (hand-written) -------------------------------------------
ehdr:
    db 0x7F, "ELF", 2, 1, 1, 0
    times 8 db 0
    dw 2                      ; ET_EXEC
    dw 0x3E                   ; x86-64
    dd 1
    dq _start                 ; e_entry
    dq phdr - $$              ; e_phoff
    dq 0
    dd 0
    dw ehdrsize
    dw phdrsize
    dw 1
    dw 0, 0, 0
ehdrsize equ $ - ehdr
phdr:
    dd 1                      ; PT_LOAD
    dd 7                      ; RWX
    dq 0
    dq $$
    dq $$
    dq filesize
    dq filesize
    dq 0x1000
phdrsize equ $ - phdr

; ----- syscall numbers -------------------------------------------------------
%define SYS_read      0
%define SYS_write     1
%define SYS_close     3
%define SYS_uname     63
%define SYS_mount     165
%define SYS_reboot    169
%define SYS_openat    257
%define SYS_getdents64 217
%define SYS_unlinkat  263

%define AT_FDCWD      -100
%define O_RDONLY      0
%define O_WRONLY      1
%define O_CREAT       0x40
%define O_TRUNC       0x200
%define O_DIRECTORY   0x10000

; write a fixed buffer (ptr,len) to stdout
%macro WRITE 2
    mov     rax, SYS_write
    mov     rdi, 1
    mov     rsi, %1
    mov     rdx, %2
    syscall
%endmacro

; =============================================================================
;  Entry
; =============================================================================
_start:
    ; mount /proc (ignore failure)
    mov     rax, SYS_mount
    mov     rdi, s_proc
    mov     rsi, s_procdir
    mov     rdx, s_proc
    xor     r10, r10
    xor     r8, r8
    syscall

    ; uname() -> real kernel release + machine
    mov     rax, SYS_uname
    mov     rdi, uts
    syscall

    call    do_fetch

.repl:
    WRITE   prompt, prompt_len
    mov     rax, SYS_read
    mov     rdi, 0
    mov     rsi, linebuf
    mov     rdx, 255
    syscall
    test    rax, rax
    jle     .repl                 ; EOF/err -> loop (never exit)

    mov     byte [linebuf + rax], 0   ; NUL-terminate
    dec     rax                        ; strip a trailing newline if present
    cmp     byte [linebuf + rax], 10
    jne     .nostrip
    mov     byte [linebuf + rax], 0
.nostrip:
    call    handle_line
    jmp     .repl

; =============================================================================
;  Command dispatch
; =============================================================================
handle_line:
    call    tokenize
    cmp     qword [tokn], 0
    je      .done

    mov     rsi, [toks]
    mov     rdi, c_help
    call    streq
    je      .help
    mov     rsi, [toks]
    mov     rdi, c_clear
    call    streq
    je      .clear
    mov     rsi, [toks]
    mov     rdi, c_echo
    call    streq
    je      .echo
    mov     rsi, [toks]
    mov     rdi, c_fetch
    call    streq
    je      .fetch
    mov     rsi, [toks]
    mov     rdi, c_uname
    call    streq
    je      .uname
    mov     rsi, [toks]
    mov     rdi, c_four
    call    streq
    je      .four
    mov     rsi, [toks]
    mov     rdi, c_poweroff
    call    streq
    je      .poweroff
    mov     rsi, [toks]
    mov     rdi, c_reboot
    call    streq
    je      .reboot

    ; unknown
    WRITE   m_nf, m_nf_len
    mov     rsi, [toks]
    call    print_cstr
    WRITE   nl, 1
.done:
    ret

.help:
    WRITE   m_help, m_help_len
    ret
.clear:
    WRITE   clrseq, clrseq_len
    ret
.fetch:
    call    do_fetch
    ret
.uname:
    WRITE   m_uname, m_uname_len
    mov     rsi, uts_release
    call    print_cstr
    WRITE   spc, 1
    mov     rsi, uts_machine
    call    print_cstr
    WRITE   nl, 1
    ret
.echo:
    ; print tokens 1..n-1 separated by spaces
    mov     r8, [tokn]
    mov     rbx, 1
.echo_loop:
    cmp     rbx, r8
    jae     .echo_end
    mov     rsi, [toks + rbx*8]
    call    print_cstr
    inc     rbx
    cmp     rbx, r8
    jae     .echo_end
    WRITE   spc, 1
    jmp     .echo_loop
.echo_end:
    WRITE   nl, 1
    ret
.poweroff:
    WRITE   m_bye, m_bye_len
    mov     rax, SYS_reboot
    mov     rdi, 0xfee1dead
    mov     rsi, 0x28121969
    mov     rdx, 0x4321fedc       ; LINUX_REBOOT_CMD_POWER_OFF
    xor     r10, r10
    syscall
    jmp     $
.reboot:
    WRITE   m_bye, m_bye_len
    mov     rax, SYS_reboot
    mov     rdi, 0xfee1dead
    mov     rsi, 0x28121969
    mov     rdx, 0x01234567       ; LINUX_REBOOT_CMD_RESTART
    xor     r10, r10
    syscall
    jmp     $

; ---- four <sub> [pkg] -------------------------------------------------------
.four:
    cmp     qword [tokn], 1
    je      .four_help
    mov     rsi, [toks + 8]
    mov     rdi, s_list
    call    streq
    je      .four_list
    mov     rsi, [toks + 8]
    mov     rdi, s_installed
    call    streq
    je      .four_installed
    mov     rsi, [toks + 8]
    mov     rdi, s_install
    call    streq
    je      .four_install
    mov     rsi, [toks + 8]
    mov     rdi, s_remove
    call    streq
    je      .four_remove
    mov     rsi, [toks + 8]
    mov     rdi, s_info
    call    streq
    je      .four_info
.four_help:
    WRITE   m_fourhelp, m_fourhelp_len
    ret
.four_list:
    mov     rdi, p_avail_dir
    call    list_dir
    ret
.four_installed:
    mov     rdi, p_inst_dir
    call    list_dir
    ret
.four_install:
    cmp     qword [tokn], 3
    jb      .four_needname
    call    build_paths            ; pbuf_av <- avail/<pkg>, pbuf_in <- inst/<pkg>
    mov     rdi, pbuf_av           ; src
    mov     rsi, pbuf_in           ; dst
    call    copy_file
    jc      .four_nopkg
    WRITE   m_installed, m_installed_len
    mov     rsi, [toks + 16]
    call    print_cstr
    WRITE   nl, 1
    ret
.four_nopkg:
    WRITE   m_nopkg, m_nopkg_len
    mov     rsi, [toks + 16]
    call    print_cstr
    WRITE   nl, 1
    ret
.four_remove:
    cmp     qword [tokn], 3
    jb      .four_needname
    call    build_paths
    mov     rax, SYS_unlinkat
    mov     rdi, AT_FDCWD
    mov     rsi, pbuf_in
    xor     rdx, rdx
    syscall
    test    rax, rax
    js      .four_notinst
    WRITE   m_removed, m_removed_len
    mov     rsi, [toks + 16]
    call    print_cstr
    WRITE   nl, 1
    ret
.four_notinst:
    WRITE   m_notinst, m_notinst_len
    mov     rsi, [toks + 16]
    call    print_cstr
    WRITE   nl, 1
    ret
.four_info:
    cmp     qword [tokn], 3
    jb      .four_needname
    call    build_paths
    mov     rdi, pbuf_av
    call    cat_file
    ret
.four_needname:
    WRITE   m_needname, m_needname_len
    ret

; =============================================================================
;  Helpers
; =============================================================================

; print NUL-terminated string at rsi (computes length by scanning for 0)
print_cstr:
    xor     rdx, rdx
.scan:
    cmp     byte [rsi + rdx], 0
    je      .emit
    inc     rdx
    jmp     .scan
.emit:
    mov     rax, SYS_write
    mov     rdi, 1
    syscall
    ret

; compare NUL-terminated strings rsi, rdi; returns ZF=1 if equal
streq:
.l:
    mov     al, [rsi]
    mov     dl, [rdi]
    cmp     al, dl
    jne     .d                     ; ZF=0, not equal
    test    al, al
    jz      .d                     ; ZF=1, both hit NUL -> equal
    inc     rsi
    inc     rdi
    jmp     .l
.d:
    ret

; copy bytes incl NUL from rsi to rdi; returns rdi pointing AT the NUL written
strcpy:
.l:
    mov     al, [rsi]
    mov     [rdi], al
    test    al, al
    jz      .d
    inc     rsi
    inc     rdi
    jmp     .l
.d:
    ret

; pbuf_av = "/var/four/available/" + toks[2];  pbuf_in = "/var/four/installed/" + toks[2]
build_paths:
    mov     rdi, pbuf_av
    mov     rsi, pfx_av
    call    strcpy
    mov     rsi, [toks + 16]
    call    strcpy
    mov     rdi, pbuf_in
    mov     rsi, pfx_in
    call    strcpy
    mov     rsi, [toks + 16]
    call    strcpy
    ret

; copy file: rdi=src path, rsi=dst path. CF=1 on failure (src missing).
copy_file:
    mov     r14, rdi
    mov     r15, rsi
    mov     rax, SYS_openat
    mov     rdi, AT_FDCWD
    mov     rsi, r14
    xor     rdx, rdx               ; O_RDONLY
    xor     r10, r10
    syscall
    test    rax, rax
    js      .fail
    mov     r12, rax               ; src fd
    mov     rax, SYS_openat
    mov     rdi, AT_FDCWD
    mov     rsi, r15
    mov     rdx, O_WRONLY | O_CREAT | O_TRUNC
    mov     r10, 0o644
    syscall
    test    rax, rax
    js      .fail_closesrc
    mov     r13, rax               ; dst fd
.cp:
    mov     rax, SYS_read
    mov     rdi, r12
    mov     rsi, iobuf
    mov     rdx, iobuflen
    syscall
    test    rax, rax
    jle     .cp_done
    mov     rdx, rax
    mov     rax, SYS_write
    mov     rdi, r13
    mov     rsi, iobuf
    syscall
    jmp     .cp
.cp_done:
    mov     rax, SYS_close
    mov     rdi, r13
    syscall
    mov     rax, SYS_close
    mov     rdi, r12
    syscall
    clc
    ret
.fail_closesrc:
    mov     rax, SYS_close
    mov     rdi, r12
    syscall
.fail:
    stc
    ret

; cat file to stdout: rdi=path
cat_file:
    mov     r14, rdi
    mov     rax, SYS_openat
    mov     rdi, AT_FDCWD
    mov     rsi, r14
    xor     rdx, rdx
    xor     r10, r10
    syscall
    test    rax, rax
    js      .err
    mov     r12, rax
.l:
    mov     rax, SYS_read
    mov     rdi, r12
    mov     rsi, iobuf
    mov     rdx, iobuflen
    syscall
    test    rax, rax
    jle     .d
    mov     rdx, rax
    mov     rax, SYS_write
    mov     rdi, 1
    mov     rsi, iobuf
    syscall
    jmp     .l
.d:
    mov     rax, SYS_close
    mov     rdi, r12
    syscall
    ret
.err:
    WRITE   m_nofile, m_nofile_len
    ret

; list a directory's entries (one per line): rdi=path. Uses getdents64.
list_dir:
    mov     r14, rdi
    mov     rax, SYS_openat
    mov     rdi, AT_FDCWD
    mov     rsi, r14
    mov     rdx, O_RDONLY | O_DIRECTORY
    xor     r10, r10
    syscall
    test    rax, rax
    js      .err
    mov     r12, rax               ; dir fd
.read:
    mov     rax, SYS_getdents64
    mov     rdi, r12
    mov     rsi, dbuf
    mov     rdx, dbuflen
    syscall
    test    rax, rax
    jle     .done
    mov     r13, rax               ; bytes in dbuf
    xor     rbx, rbx               ; offset
.each:
    cmp     rbx, r13
    jae     .read
    lea     r14, [dbuf + rbx]      ; dirent
    movzx   r15, word [r14 + 16]   ; d_reclen (preserved across syscalls)
    lea     rsi, [r14 + 19]        ; d_name
    ; skip "." and ".."
    cmp     byte [rsi], '.'
    jne     .print
    cmp     byte [rsi + 1], 0
    je      .next
    cmp     byte [rsi + 1], '.'
    jne     .print
    cmp     byte [rsi + 2], 0
    je      .next
.print:
    call    print_cstr             ; rsi already = d_name
    WRITE   nl, 1
.next:
    add     rbx, r15
    jmp     .each
.done:
    mov     rax, SYS_close
    mov     rdi, r12
    syscall
    ret
.err:
    WRITE   m_nodir, m_nodir_len
    ret

; split linebuf into toks[0..7], store count in tokn
tokenize:
    xor     r8, r8                 ; count
    mov     rsi, linebuf
.scan:
    mov     al, [rsi]              ; skip spaces
    cmp     al, ' '
    jne     .maybe
    inc     rsi
    jmp     .scan
.maybe:
    test    al, al
    jz      .done
    cmp     r8, 8
    jae     .done
    mov     [toks + r8*8], rsi
    inc     r8
.tok:
    mov     al, [rsi]
    test    al, al
    jz      .done
    cmp     al, ' '
    je      .cut
    inc     rsi
    jmp     .tok
.cut:
    mov     byte [rsi], 0
    inc     rsi
    jmp     .scan
.done:
    mov     [tokn], r8
    ret

; print the clover logo + fastfetch panel (uses uts fields)
do_fetch:
    WRITE   fetch1, fetch1_len
    mov     rsi, uts_release
    call    print_cstr
    WRITE   fetch_mid, fetch_mid_len
    mov     rsi, uts_machine
    call    print_cstr
    WRITE   fetch2, fetch2_len
    ret

; =============================================================================
;  Data
; =============================================================================
nl          db 10
spc          db " "
clrseq      db 0x1B, "[2J", 0x1B, "[H"
clrseq_len  equ $ - clrseq

prompt      db "chan> "
prompt_len  equ $ - prompt

; command words
c_help      db "help", 0
c_clear     db "clear", 0
c_echo      db "echo", 0
c_fetch     db "fetch", 0
c_uname     db "uname", 0
c_four      db "four", 0
c_poweroff  db "poweroff", 0
c_reboot    db "reboot", 0

; four subcommands
s_list      db "list", 0
s_installed db "installed", 0
s_install   db "install", 0
s_remove    db "remove", 0
s_info      db "info", 0

; paths
p_avail_dir db "/var/four/available", 0
p_inst_dir  db "/var/four/installed", 0
pfx_av      db "/var/four/available/", 0
pfx_in      db "/var/four/installed/", 0
s_proc      db "proc", 0
s_procdir   db "/proc", 0

; messages
m_help:
    db "Chan Linux commands:", 10
    db "  help              this help", 10
    db "  clear             clear the screen", 10
    db "  echo <text>       print text", 10
    db "  fetch             show the clover system panel", 10
    db "  uname             show kernel release and arch", 10
    db "  four <args>       package manager (try: four help)", 10
    db "  poweroff          power off the machine", 10
    db "  reboot            restart the machine", 10
m_help_len  equ $ - m_help

m_fourhelp:
    db "four - the Chan Linux package manager", 10
    db "  four list              available packages", 10
    db "  four installed         installed packages", 10
    db "  four install <pkg>     install a package", 10
    db "  four remove <pkg>      remove a package", 10
    db "  four info <pkg>        show package contents", 10
    db "  four help              this help", 10
m_fourhelp_len equ $ - m_fourhelp

m_uname     db "Chan Linux "
m_uname_len equ $ - m_uname
m_nf        db "chan: command not found: "
m_nf_len    equ $ - m_nf
m_installed db "installed: "
m_installed_len equ $ - m_installed
m_removed   db "removed: "
m_removed_len equ $ - m_removed
m_nopkg     db "four: no such package: "
m_nopkg_len equ $ - m_nopkg
m_notinst   db "four: not installed: "
m_notinst_len equ $ - m_notinst
m_needname  db "four: missing package name", 10
m_needname_len equ $ - m_needname
m_nofile    db "four: cannot read package", 10
m_nofile_len equ $ - m_nofile
m_nodir     db "four: cannot open directory", 10
m_nodir_len equ $ - m_nodir
m_bye       db "Chan Linux: shutting down. Bye!", 10
m_bye_len   equ $ - m_bye

; ----- fetch panel (clover logo spliced around the dynamic uname fields) -----
fetch1:
    db 0x1B, "[2J", 0x1B, "[H"
    db 0x1B, "[32m", "   .-. .-.   ", 0x1B, "[0m", "  "
    db 0x1B, "[1m", "root@chan", 0x1B, "[0m", 10
    db 0x1B, "[32m", "  (   V   )  ", 0x1B, "[0m", "  ", "---------", 10
    db 0x1B, "[32m", "   '-. .-'   ", 0x1B, "[0m", "  ", "OS:       Chan Linux x86_64", 10
    db 0x1B, "[32m", "   .-'V'-.   ", 0x1B, "[0m", "  ", "Kernel:   "
fetch1_len  equ $ - fetch1
fetch_mid:
    db 10
    db 0x1B, "[32m", "  (   ^   )  ", 0x1B, "[0m", "  ", "Arch:     "
fetch_mid_len equ $ - fetch_mid
fetch2:
    db 10
    db 0x1B, "[32m", "   '-' '-'   ", 0x1B, "[0m", "  ", "Init:     /init (PID 1, asm)", 10
    db 0x1B, "[32m", "      |      ", 0x1B, "[0m", "  ", "Userland: x86-64 assembly", 10
    db 0x1B, "[32m", "      |      ", 0x1B, "[0m", "  ", "Pkgmgr:   four", 10
    db "               Shell:    chan (builtin)", 10
    db "               "
    db 0x1B, "[40m", "   ", 0x1B, "[41m", "   ", 0x1B, "[42m", "   ", 0x1B, "[43m", "   "
    db 0x1B, "[44m", "   ", 0x1B, "[45m", "   ", 0x1B, "[46m", "   ", 0x1B, "[47m", "   "
    db 0x1B, "[0m", 10, 10
    db "  Type 'help' for commands, 'four help' for packages.", 10, 10
fetch2_len  equ $ - fetch2

; ----- buffers (writable; kernel writes into them) ---------------------------
uts:        times 390 db 0
uts_release equ uts + 130
uts_machine equ uts + 260

linebuf:    times 256 db 0
iobuf:      times 4096 db 0
iobuflen    equ 4096
dbuf:       times 1024 db 0
dbuflen     equ 1024
pbuf_av:    times 160 db 0
pbuf_in:    times 160 db 0
toks:       times 8 dq 0
tokn:       dq 0

filesize    equ $ - $$
