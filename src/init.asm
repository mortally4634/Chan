; =============================================================================
;  Chan Linux  --  /init  (PID 1, the entire userland)
; -----------------------------------------------------------------------------
;  A freestanding x86-64 Linux executable in pure assembly. No libc, no linker:
;  the ELF64 header below is emitted by hand, so `nasm -f bin` alone produces a
;  ready-to-run static Linux binary.
;
;  The kernel execs this as /init (PID 1). It:
;    1. calls uname() to read the real kernel release + machine
;    2. prints a four-leaf-clover logo + a fastfetch-style info panel
;    3. loops forever: read a line from the console, echo it back
;
;  PID 1 must never exit (the kernel panics if it does), so there is no exit
;  syscall anywhere -- the echo loop is infinite.
;
;  Build:  nasm -f bin src/init.asm -o build/init
; =============================================================================

BITS 64
org 0x400000                      ; virtual load address (identity-mapped file)

; -----------------------------------------------------------------------------
;  ELF64 header (64 bytes) -- hand-written
; -----------------------------------------------------------------------------
ehdr:
    db 0x7F, "ELF"                ; e_ident: magic
    db 2                          ; EI_CLASS   = ELFCLASS64
    db 1                          ; EI_DATA    = little-endian
    db 1                          ; EI_VERSION = current
    db 0                          ; EI_OSABI   = System V
    times 8 db 0                  ; EI_PAD
    dw 2                          ; e_type      = ET_EXEC
    dw 0x3E                       ; e_machine   = AMD x86-64
    dd 1                          ; e_version
    dq _start                     ; e_entry
    dq phdr - $$                  ; e_phoff
    dq 0                          ; e_shoff
    dd 0                          ; e_flags
    dw ehdrsize                   ; e_ehsize
    dw phdrsize                   ; e_phentsize
    dw 1                          ; e_phnum
    dw 0                          ; e_shentsize
    dw 0                          ; e_shnum
    dw 0                          ; e_shstrndx
ehdrsize equ $ - ehdr

; -----------------------------------------------------------------------------
;  Program header (56 bytes) -- one RWX segment covering the whole file
; -----------------------------------------------------------------------------
phdr:
    dd 1                          ; p_type   = PT_LOAD
    dd 7                          ; p_flags  = R | W | X  (W: buffers are written)
    dq 0                          ; p_offset
    dq $$                         ; p_vaddr  = 0x400000
    dq $$                         ; p_paddr
    dq filesize                   ; p_filesz
    dq filesize                   ; p_memsz
    dq 0x1000                     ; p_align
phdrsize equ $ - phdr

; -----------------------------------------------------------------------------
;  Convenience: write a fixed buffer to stdout (fd 1)
; -----------------------------------------------------------------------------
%macro WRITE 2                    ; WRITE ptr, len
    mov     rax, 1                ; sys_write
    mov     rdi, 1                ; fd = stdout
    mov     rsi, %1
    mov     rdx, %2
    syscall
%endmacro

; -----------------------------------------------------------------------------
;  Code
; -----------------------------------------------------------------------------
_start:
    ; --- read real system info: uname() fills the utsname struct -------------
    mov     rax, 63               ; sys_uname
    mov     rdi, uts
    syscall

    ; --- fastfetch-style panel, spliced around the two dynamic fields --------
    WRITE   fetch1, fetch1_len    ; clover rows 0-3 + labels, up to "Kernel:   "
    mov     rsi, uts_release      ; -> kernel version string (NUL-terminated)
    call    print_cstr
    WRITE   fetch_mid, fetch_mid_len  ; newline + clover row 4 + "Arch:     "
    mov     rsi, uts_machine      ; -> machine string, e.g. "x86_64"
    call    print_cstr
    WRITE   fetch2, fetch2_len    ; newline + clover rows 5-7 + rest of panel

.loop:
    WRITE   prompt, prompt_len

    mov     rax, 0                ; sys_read
    mov     rdi, 0                ; fd = stdin (/dev/console)
    mov     rsi, buf
    mov     rdx, buflen
    syscall

    test    rax, rax              ; EOF/error -> just prompt again (never exit)
    jle     .loop

    mov     rdx, rax              ; echo exactly the bytes we read
    mov     rax, 1                ; sys_write
    mov     rdi, 1
    mov     rsi, buf
    syscall

    jmp     .loop

; -----------------------------------------------------------------------------
;  print_cstr: write the NUL-terminated string at rsi to stdout.
;  There is no strlen here -- we compute the length by scanning for the 0 byte.
; -----------------------------------------------------------------------------
print_cstr:
    xor     rdx, rdx              ; rdx = length counter
.scan:
    cmp     byte [rsi + rdx], 0
    je      .emit
    inc     rdx
    jmp     .scan
.emit:
    mov     rax, 1                ; sys_write  (rsi=ptr, rdx=len already set)
    mov     rdi, 1
    syscall
    ret

; -----------------------------------------------------------------------------
;  Data
; -----------------------------------------------------------------------------
; ESC = 0x1B.  Colors: [32m green, [1m bold, [0m reset, [40m..[47m bg bars.

fetch1:
    db 0x1B, "[2J", 0x1B, "[H"                 ; clear screen, cursor home
    ; row 0 : two top leaves + title
    db 0x1B, "[32m", "   .-. .-.   ", 0x1B, "[0m", "  "
    db 0x1B, "[1m", "root@chan", 0x1B, "[0m", 10
    ; row 1
    db 0x1B, "[32m", "  (   V   )  ", 0x1B, "[0m", "  ", "---------", 10
    ; row 2
    db 0x1B, "[32m", "   '-. .-'   ", 0x1B, "[0m", "  ", "OS:       Chan Linux x86_64", 10
    ; row 3 (dynamic value follows: kernel release)
    db 0x1B, "[32m", "   .-'V'-.   ", 0x1B, "[0m", "  ", "Kernel:   "
fetch1_len equ $ - fetch1

fetch_mid:
    db 10                                       ; end the kernel-release line
    ; row 4 (dynamic value follows: machine / arch)
    db 0x1B, "[32m", "  (   ^   )  ", 0x1B, "[0m", "  ", "Arch:     "
fetch_mid_len equ $ - fetch_mid

fetch2:
    db 10                                       ; end the arch line
    ; row 5
    db 0x1B, "[32m", "   '-' '-'   ", 0x1B, "[0m", "  ", "Init:     /init (PID 1, asm)", 10
    ; row 6
    db 0x1B, "[32m", "      |      ", 0x1B, "[0m", "  ", "Userland: x86-64 assembly", 10
    ; row 7
    db 0x1B, "[32m", "      |      ", 0x1B, "[0m", "  ", "Shell:    none (echo loop)", 10
    ; overflow info lines (logo done, pad 15 cols)
    db "               Packages: 0", 10
    db "               Uptime:   fresh boot", 10
    ; color bar, neofetch-style
    db "               "
    db 0x1B, "[40m", "   ", 0x1B, "[41m", "   ", 0x1B, "[42m", "   ", 0x1B, "[43m", "   "
    db 0x1B, "[44m", "   ", 0x1B, "[45m", "   ", 0x1B, "[46m", "   ", 0x1B, "[47m", "   "
    db 0x1B, "[0m", 10, 10
    db "  Type something and press Enter -- /init echoes it back.", 10
    db "  (Quit the VM: Ctrl-A then X.)", 10, 10
fetch2_len equ $ - fetch2

prompt:
    db "chan> "
prompt_len equ $ - prompt

; utsname buffer filled by uname(); fields are 65 bytes each, NUL-terminated.
;   [0]   sysname   [65]  nodename  [130] release
;   [195] version   [260] machine   [325] domainname
uts:
    times 390 db 0
uts_release equ uts + 130
uts_machine equ uts + 260

; line buffer for the echo loop (kernel writes into it, hence RWX segment)
buf:
    times 256 db 0
buflen equ $ - buf

filesize equ $ - $$
