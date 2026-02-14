; Example assembly file demonstrating the macro system
; 
; Usage:
;   python3 py6502/cli_asm6502.py example_macros.asm -m -b output.bin
;   python3 py6502/cli_asm6502.py example_macros.asm -e expanded.asm

; Register macros from the examples library
.macro text_string = py6502.macros_examples.text_string
.macro pascal_string = py6502.macros_examples.pascal_string
.macro byte_table = py6502.macros_examples.byte_table
.macro word_table = py6502.macros_examples.word_table
.macro repeat_byte = py6502.macros_examples.repeat_byte

org $0800

; Simple program entry point
start:
    jsr print_hello
    jsr print_table
    rts

; Subroutine: print hello message
print_hello:
    ldx #0
    lda #<hello_msg
    sta $20
    lda #>hello_msg
    sta $21
    rts

; Subroutine: print lookup table
print_table:
    ldx #0
loop:
    lda lookup_table,x
    beq done
    jsr $ffd2          ; CHROUT on C64
    inx
    bne loop
done:
    rts

; Data section with macro-generated content
hello_msg:
    @text_string "Hello World"

greeting:
    @pascal_string "Welcome to 6502"

; Lookup table using macro
lookup_table:
    @byte_table $41, $42, $43, $00    ; "ABC" + null terminator

; Address table using macro
addresses:
    @word_table start, print_hello, print_table

; Padding using macro
padding:
    @repeat_byte $FF, 16
