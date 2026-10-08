;==========================================================================
;  Tokenizer
;==========================================================================
;
;  Turn the bytes of the current source part into tokens, one per call to
;  TK_NEXT. The parser is the only client: PR_PEEK holds one token of
;  lookahead, and the grammar actions read the current token's fields as
;  they append operations to the semantic transcript. Source bytes arrive
;  only through the source adapter (SRC_PEEK, SRC_TAKE, SRC_EOL, SRC_BODY).
;  The source stays resident until compilation ends, so a name is reported
;  as a pointer into it rather than copied, and name records keep that
;  pointer.
;
;  Principal entries:
;    TK_NEXT   return the next token: A=kind, BC=payload, ZERO at the end
;    TK_MARK   record the source cursor as the start of a token
;    TK_MATCH  compare the current name with the B bytes at HL
;    TK_SAME   compare the current name with a retained name record
;    TK_KEEP   retain the current name in a three-byte name record
;    TK_HEX    classify and decode one hexadecimal digit
;
;  Token kinds are the TK_* equates in STATE.ASM; the keyword and
;  punctuation tables are KW_TAB and KW_PUNCT in KEYWORDS.ASM. TK_NEXT
;  returns with carry clear, and the payload depends on the kind:
;
;    TK_NAME, keyword  TK_PTR = first byte in the source, TK_LEN = length
;    TK_NUM            BC = value's low word, TK_NHI its high word
;    TK_TYPE           BC = the type's ID (SY_U8...)
;    TK_CHAR           BC = character code
;    TK_TEXT           BC = TK_LEN = decoded length, TK_PTR = opening quote
;
;  Every token leaves its start in TK_POS, TK_LINE and TK_COL, the six-byte
;  offset/line/column record that PR_COPY moves into diagnostics and
;  declarations.
;
;  Lexical rules. Spaces and tabs separate tokens, and // begins a comment
;  that runs to the line end. A line ends with LF or CR LF; a bare CR is an
;  error. A name begins with a letter and continues with letters, digits and
;  underscores, up to 255 bytes; case is significant and the keywords are
;  lower case. A number is decimal (at most 4,294,967,295), $ hexadecimal
;  (at most eight digits) or % binary (at most 32 digits), and may not run
;  straight into a name byte. A character literal is one printable byte,
;  other than an apostrophe or backslash, between apostrophes. A string
;  literal holds printable bytes and the escapes \0 \n \r \t \' \" \\ and
;  \xHH, at most 255 bytes once decoded, and cannot cross a line end.
;
;  Line boundaries. A line yields TK_EOL only if it produced a token, so
;  blank and comment-only lines are invisible to the parser. Line ends
;  inside ( ) or [ ] are whitespace: TK_NEST counts the open brackets of
;  both kinds, and the parser checks which kind closes. The end of every
;  source part acts as a line end, with a synthetic TK_EOL when its last
;  line has no terminator, so tokens never join across parts. TK_EOF
;  follows the last part and repeats on every later call.
;
;  Errors. Every lexical error reaches TK_BAD, which raises DG_LEX at the
;  token's start (TK_POS). DG_RAISE does not return: it unwinds to the stack
;  saved by the compile entry. No routine here returns an error status.
;
;  State. TK_POS, TK_LINE, TK_COL, TK_PTR and TK_LEN describe the current
;  token. TK_LIVE is nonzero once the current line has produced a token, and
;  TK_NEST is the bracket depth; SRC_INIT clears both for each part.
;  TK_ATEND also steps to the stream's next part. SRC_PEEK and SRC_TAKE
;  clobber DE and HL but keep BC, so the scanners hold counts and payloads
;  in B and C, and save an accumulator in HL around each source call.

;@ROUTINE CLOBBERS BC,DE,HL,PARITY,HALFCARRY
; Record the source cursor as the start of the next token: the position
; for diagnostics and the byte pointer for names and literals.

TK_MARK:                       ; Copy the four cursor words.
    LD   HL,SRC_POS                ; The offset, line and column, in a row,
    LD   DE,TK_POS                 ; become the token's, in the same order
    LD   BC,6                      ; (TK_POS, TK_LINE and TK_COL):
    LDIR                           ; three words.
    LD   HL,(SRC_PTR)              ; Address of the token's first byte.
    LD   (TK_PTR),HL               ; Names and literals are read from here.
    RET                            ; Carry, zero and sign survive.

;@ROUTINE IN A OUT A,CARRY,ZERO CLOBBERS D,SIGN,PARITY,HALFCARRY
; Common return for a token of kind A. Mark the line as live, so that its
; end yields TK_EOL, and return carry clear with the payload in BC intact.

TK_DONE:                       ; A: the token kind.
    LD   D,A                       ; Hold the kind; BC carries the payload.
    LD   A,1                       ; Any nonzero value marks the line.
    LD   (TK_LIVE),A               ; This line now owes the parser a TK_EOL.
    LD   A,D                       ; Return the token kind.
    OR   A                         ; Carry clear; ZERO clear, as no kind here is TK_EOF.
    RET                            ; Back to the parser with the token.

;@ROUTINE NORETURN
; Raise the lexical diagnostic at the start of the current token. DG_RAISE
; takes its code from the byte after the call and unwinds the compilation.

TK_BAD:                        ; Every malformed token ends here.
    CALL DG_RAISE                  ; Never returns; the next byte is its argument.
    DB   DG_LEX                    ; Diagnostic: malformed token.

;@ROUTINE IN A OUT A,CARRY CLOBBERS C,ZERO,SIGN,PARITY,HALFCARRY
; Carry reports whether the byte in A is an ASCII letter of either case.
; A is returned unchanged.

TK_ALPHA:                      ; A: the byte to classify.
    LD   C,A                       ; Keep the byte while A is folded.
    OR   $20                       ; Fold capitals onto lower case.
    SUB  'a'                       ; Letters now lie in 0..25.
    CP   26                        ; Carry: a letter; other bytes are above 25 or wrapped.
    LD   A,C                       ; Restore the byte; LD leaves carry alone.
    RET                            ; Carry is the answer.

;@ROUTINE IN A OUT A,CARRY CLOBBERS C,ZERO,SIGN,PARITY,HALFCARRY
; Carry reports whether the byte in A can continue a name: a letter, a
; digit or an underscore. A is returned unchanged.

TK_ALNUM:                      ; A: the byte to classify.
    CALL TK_ALPHA                  ; Letters are the common case.
    RET  C                         ; A letter continues the name.
    CP   '0'                       ; Digits begin at '0'.
    JR   C,.UNDER                  ; Below the digits, so the underscore test fails.
    CP   '9'+1                     ; Digits end at '9'.
    JR   C,.YES                    ; A decimal digit continues the name.
.UNDER:                        ; Not a letter or a digit: only '_' remains.
    CP   '_'                       ; The one punctuation byte allowed in names.
    JR   Z,.YES                    ; An underscore continues the name.
    OR   A                         ; Carry clear: the byte ends the name.
    RET                            ; Report the byte as no part of a name.
.YES:                          ; The byte belongs to the name.
    SCF                            ; Carry set: continue the name.
    RET                            ; Report the byte as part of a name.

;@ROUTINE IN B,HL OUT CARRY,ZERO CLOBBERS A,B,DE,HL,SIGN,PARITY,HALFCARRY
; Compare the current name, TK_LEN bytes at TK_PTR, with the B bytes at
; HL. Carry reports an exact, case-sensitive match; ZERO agrees while the
; current token is a name, as it always is for the callers.

TK_MATCH:                      ; B: candidate length; HL: its bytes.
    LD   A,(TK_LEN)                ; Length of the current name.
    CP   B                         ; Names of different lengths never match.
    JR   NZ,.NO                    ; Lengths differ.
    LD   DE,(TK_PTR)               ; DE walks the name in the resident source.
.LOOP:                         ; B bytes remain; DE and HL step together.
    LD   A,(DE)                    ; Next byte of the name.
    CP   (HL)                      ; Against the same byte of the candidate.
    JR   NZ,.NO                    ; The first difference ends the comparison.
    INC  DE                        ; Next byte of the name.
    INC  HL                        ; Next byte of the candidate.
    DJNZ .LOOP                     ; Until all B bytes agree.
    SCF                            ; Match: carry set, ZERO still set by the last compare.
    RET                            ; Report the match.
.NO:                           ; The lengths or the bytes differ.
    OR   A                         ; Carry clear; A is a nonzero length or byte, so NZ.
    RET                            ; Report the mismatch.

;@ROUTINE IN HL OUT CARRY,ZERO CLOBBERS A,DE,SIGN,PARITY,HALFCARRY
; Compare the current name with the retained name record at HL: a pointer
; word and a one-byte length, as TK_KEEP writes it. Carry and ZERO report a
; match. BC and HL are preserved, so callers can walk a table of records.

TK_SAME:                       ; HL: the name record to compare.
    PUSH BC                        ; Callers keep a loop count in BC.
    PUSH HL                        ; And the record address in HL.
    CALL WD_GET                    ; DE is the retained name's address; HL its length.
    LD   A,(HL)                    ; Length of the retained name.
    LD   B,A                       ; TK_MATCH takes the length in B.
    EX   DE,HL                     ; And the bytes in HL.
    CALL TK_MATCH                  ; Carry and ZERO report the comparison.
    POP  HL                        ; Restore the record address.
    POP  BC                        ; Restore the caller's count.
    RET                            ; The flags from TK_MATCH survive the pops.

;@ROUTINE IN HL OUT A,BC,HL
; Retain the current name in the three-byte record at HL: its spelling's
; address in the name heap, then its length. A spelling not yet in the
; heap is copied below its bottom (NH_ALLOC; DG_ROOM when the free memory
; is full); TK_PTR stays the source's. HL returns at the length byte, so
; that callers step on to the fields that follow. DE and the flags are
; preserved.

TK_KEEP:                       ; HL: the record to fill.
    PUSH DE                        ; DE,
    PUSH AF                        ; the flags,
    PUSH HL                        ; and the record, kept.
    LD   HL,(TK_PTR)               ; The spelling:
    LD   DE,(NH_PTR)               ; at or above
    CALL CP_HLDE                   ; the heap's bottom, it is in it
    JR   NC,.HEAP                  ; already.
    LD   A,(TK_LEN)                ; Otherwise
    LD   C,A                       ; its
    LD   B,0                       ; length, BC,
    CALL NH_ALLOC                  ; is taken below the heap, at DE:
    LD   HL,(TK_PTR)               ; The spelling
    PUSH DE                        ; copied
    LDIR                           ; there
    POP  HL                        ; and kept.
.HEAP:                         ; HL is the spelling in the heap.
    LD   B,H                       ; BC
    LD   C,L                       ; is it.
    POP  HL                        ; The record:
    POP  AF                        ; (the flags)
    LD   (HL),C                    ; Address, low byte.
    INC  HL                        ; Step to the high byte.
    LD   (HL),B                    ; Address, high byte.
    INC  HL                        ; Step to the length byte.
    LD   A,(TK_LEN)                ; Length of the name.
    LD   (HL),A                    ; Completes the record.
    POP  DE                        ; DE again.
    RET                            ; A is the length and BC the address.

;@ROUTINE IN BC OUT DE CLOBBERS A,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Take BC bytes below the name heap's bottom, which becomes theirs (NH_PTR),
; from the end of the free memory (BL_SPAN; when it would pass the start,
; a blob's bytes spill, BL_SPILL, then DG_ROOM), the log of the blob being
; built moving down with it: DE returns their address. What is above the
; bottom never moves. BC is kept.

NH_ALLOC:                      ; BC is the bytes.
    PUSH BC                        ; (the bytes kept)
.AGAIN:                        ; Is there room?
    CALL BL_SPAN                   ; They are taken from the free memory's
    PUSH DE                        ; end (kept),
    EX   DE,HL                     ; below
    OR   A                         ; which
    SBC  HL,BC                     ; the new end
    PUSH HL                        ; (kept)
    SBC  HL,DE                     ; must stay
    POP  HL                        ; above its
    JR   NC,.ROOM                  ; start;
    POP  DE                        ; if not, a blob's
    CALL BL_FLUSH                  ; bytes spill,
    JP   C,MM_FULL                 ; if any (DG_ROOM),
    JR   .AGAIN                    ; and it is tried again.
.ROOM:                         ; HL is the new end.
    LD   (BL_LBOT),HL              ; A blob's log ends there,
    EX   DE,HL                     ; moved down
    POP  BC                        ; from the old end
    LD   HL,(NH_PTR)               ; to the heap's
    OR   A                         ; bottom;
    SBC  HL,BC                     ; HL is
    PUSH HL                        ; its bytes,
    LD   H,B                       ; none
    LD   L,C                       ; without
    POP  BC                        ; a blob.
    LD   A,B                       ; Any
    OR   C                         ; are
    JR   Z,.MOVED                  ; moved
    LDIR                           ; down.
.MOVED:                        ; DE is the heap's new bottom,
    LD   (NH_PTR),DE               ; the bytes below the old:
    POP  BC                        ; BC again.
    RET                            ; DE is their address.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY
; Scan a name whose first byte, a letter, is current, then look it up in
; KW_TAB, among the entries of its first letter (KW_IDX). A returns the
; keyword's kind, or TK_NAME; TK_PTR and TK_LEN
; locate the name either way. Reached by a jump from TK_NEXT.

TK_WORD:                       ; The current byte is a letter.
    LD   B,0                       ; B counts the name's bytes.
.NAMELOOP:                     ; Scan while the next byte continues the name.
    CALL SRC_PEEK                  ; Next byte, not yet consumed.
    JR   C,.DONE                   ; The end of the part ends the name.
    CALL TK_ALNUM                  ; Carry if a letter, digit or underscore.
    JR   NC,.DONE                  ; Any other byte ends the name, unconsumed.
    CALL SRC_TAKE                  ; Consume it; B survives.
    INC  B                         ; One more byte in the name.
    JP   Z,TK_BAD                  ; 256 bytes: too long for TK_LEN.
    JR   .NAMELOOP                 ; Scan the next byte.
.DONE:                         ; B is the name's length.
    LD   A,B                       ; Publish the length for the parser.
    LD   (TK_LEN),A                ; TK_PTR already holds its address.
    LD   C,B                       ; C keeps the length.
    LD   HL,(TK_PTR)               ; Its first
    LD   A,(HL)                    ; byte,
    SUB  'a'                       ; a letter
    CP   26                        ; a to z,
    JR   NC,.NAME                  ; or no keyword begins so;
    LD   E,A                       ; its
    LD   D,0                       ; entries
    LD   HL,KW_IDX                 ; begin
    ADD  HL,DE                     ; at
    LD   E,(HL)                    ; KW_TAB
    LD   HL,KW_TAB                 ; plus
    ADD  HL,DE                     ; its offset.
.KEYLOOP:                      ; HL is at an entry's first byte.
    LD   DE,(TK_PTR)               ; DE walks the name.
    LD   A,(DE)                    ; An entry
    CP   (HL)                      ; of another letter
    JR   NZ,.NAME                  ; ends them.
    LD   B,C                       ; B counts its bytes.
.CHAR:                         ; HL and DE step together.
    LD   A,(DE)                    ; The name's byte
    XOR  (HL)                      ; is zero against an equal byte, $80 an equal last.
    INC  HL                        ; Step the keyword
    INC  DE                        ; and the name.
    ADD  A,A                       ; Carry for the last; anything else but zero differs.
    JR   NZ,.MISS                  ; A different byte: not this keyword.
    JR   C,.LAST                   ; The keyword's last byte agrees.
    DJNZ .CHAR                     ; The name is shorter than the keyword:
.MISS:                         ; HL is past the byte that settled it.
    DEC  HL                        ; Back to that byte,
.SKIP:                         ; then past the keyword's last byte
    BIT  7,(HL)                    ; (bit 7)
    INC  HL                        ; to its kind,
    JR   Z,.SKIP                   ; and past
    INC  HL                        ; the kind to the next entry.
    JR   .KEYLOOP                  ; Try the next keyword.
.NAME:                         ; No keyword matched:
    LD   A,TK_NAME                 ; an ordinary name.
    JP   TK_DONE                   ; Return the name.
.LAST:                         ; HL is at the kind; the name must end too.
    DJNZ .MISS                     ; The name is longer than the keyword.
    LD   A,(HL)                    ; The keyword's kind.
    OR   A                         ; A type keyword's
    JP   M,.TYPE                   ; has bit 7 set.
    CP   TK_END                    ; An `end`
    JP   NZ,TK_DONE                ; (any other keyword returns now)
    LD   HL,(TK_POS)               ; keeps its offset, where the end of a
    LD   (TK_ENDP),HL              ; routine is reported (AC_END).
    JP   TK_DONE                   ; Return the keyword's kind.
.TYPE:                         ; KW_TYPE plus the type's ID.
    AND  $7F                       ; The ID
    LD   C,A                       ; is the payload, B being zero,
    LD   A,TK_TYPE                 ; of a type keyword.
    JP   TK_DONE                   ; Return it.

;@ROUTINE OUT A,BC,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Scan a decimal literal whose first digit is current and return TK_NUM
; with its value's low word in BC and its high word in TK_NHI. Every digit
; is read, as the reference reads them, before a value beyond 32 bits
; (TK_WIDE), or a name byte straight after the digits, is found
; malformed: a decimal point and a digit, or an exponent, make it a
; floating-point literal first, its f32 the value and TK_WIDE SY_F32.
; Reached by a jump from TK_NEXT.

TK_DIGIT:                      ; The current byte is a decimal digit.
    LD   HL,(SRC_PTR)              ; Its place, where a floating-point
    LD   (TK_NBEG),HL              ; literal's digits are read again.
    CALL TK_ZERO                   ; No value and no carry yet.
.LOOP:                         ; TK_NLO and TK_NHI are the digits so far.
    CALL SRC_PEEK                  ; Next byte, not yet consumed.
    JR   C,TK_NUMOK                ; The end of the part ends the literal.
    SUB  '0'                       ; A digit's value,
    CP   10                        ; 0..9?
    JR   NC,.END                   ; Not a digit: the literal ends here.
    CALL TK_LOAD                   ; DEHL is the value so far.
    CALL TK_TEN                    ; Ten times it, plus the digit.
    CALL TK_SAVE                   ; Kept.
    CALL SRC_TAKE                  ; Consume the digit.
    JR   .LOOP                     ; Scan the next byte.
.END:                          ; A is the byte less '0'.
    ADD  A,'0'                     ; The byte after the digits:
    CP   '.'                       ; a decimal point?
    JR   Z,.POINT                  ; A float, or malformed.
    PUSH AF                        ; (kept)
    OR   $20                       ; An exponent,
    CP   'e'                       ; e or E,
    JR   Z,.FLOAT                  ; makes a float.
    POP  AF                        ; Otherwise
    JR   TK_TRAIL                  ; no name byte may follow.
.POINT:                        ; A decimal point follows the digits.
    LD   DE,(SRC_PTR)              ; The byte
    INC  DE                        ; after it:
    LD   A,(DE)                    ; a digit
    SUB  '0'                       ; makes
    CP   10                        ; a float;
    JR   NC,TK_ENUM                ; anything else is malformed.
    PUSH AF                        ; (balanced below)
.FLOAT:                        ; A floating-point literal:
    POP  AF                        ; (the byte)
    CALL OV_FSCAN                  ; its fraction and exponent, and f32
    JR   TK_YIELD                  ; (FLOAT.ASM), TK_WIDE SY_F32.

; The literal has ended at the byte in A, which is not consumed. A number
; cannot be followed immediately by a name byte: forms such as 0x2a and
; 12u8 are one malformed number, not a misleading number and name
; (malformed-number). TK_RADIX joins here; a decimal literal after its
; point and exponent are ruled out.

TK_TRAIL:                      ; A: the byte after the literal.
    CALL TK_ALNUM                  ; Carry if a letter, digit or underscore.
    JR   NC,TK_NUMOK               ; Anything else ends the number.
TK_ENUM:                       ; A malformed number.
    CALL DG_RAISE                  ; Raise the diagnostic below.
    DB   DG_FORM                   ; malformed-number, at the number.
TK_NUMOK:                      ; TK_NLO and TK_NHI are the value.
    LD   A,(TK_WIDE)               ; Past 32 bits
    OR   A                         ; is beyond
    JR   NZ,TK_ENUM                ; a u32: malformed.
TK_YIELD:                      ; Return the number, f32 too:
    LD   BC,(TK_NLO)               ; BC: the low word.
    LD   A,TK_NUM                  ; The token kind.
    JP   TK_DONE                   ; Return the number.

;@ROUTINE OUT A,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Start a number's value at zero, not past 32 bits (TK_WIDE): A and HL
; return zero.

TK_ZERO:                       ; A number begins.
    XOR  A                         ; Zero:
    LD   (TK_WIDE),A               ; not past 32 bits,
    LD   H,A                       ; and the value
    LD   L,A                       ; so far,
    LD   (TK_NLO),HL               ; low word
    LD   (TK_NHI),HL               ; and high word.
    RET                            ; Scanning may begin.

;@ROUTINE OUT DE,HL
; Load the value scanned so far, TK_NHI and TK_NLO, into DEHL. Flags and
; A are kept.

TK_LOAD:                       ; The value into DEHL.
    LD   HL,(TK_NLO)               ; Its low word,
    LD   DE,(TK_NHI)               ; its high word.
    RET                            ; DEHL.

;@ROUTINE IN DE,HL
; Keep DEHL as the value scanned so far. Flags and A are kept.

TK_SAVE:                       ; DEHL is the value.
    LD   (TK_NLO),HL               ; Its low word,
    LD   (TK_NHI),DE               ; its high word.
    RET                            ; Kept.

;@ROUTINE IN A,DE,HL OUT DE,HL CLOBBERS A,BC,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; DEHL becomes ten times DEHL plus the digit A, modulo 2^32: eight times
; plus twice. A carry out of any step marks the value past 32 bits
; (TK_WIDE).

TK_TEN:                        ; A is the digit.
    PUSH AF                        ; Keep it.
    CALL TK_DBL                    ; Twice the value,
    PUSH DE                        ; kept:
    PUSH HL                        ; its two words.
    CALL TK_DBL                    ; Four times,
    CALL TK_DBL                    ; eight times.
    POP  BC                        ; Twice's low word
    ADD  HL,BC                     ; is added,
    EX   DE,HL                     ; then
    POP  BC                        ; its high word
    ADC  HL,BC                     ; with the carry:
    CALL C,TK_OVER                 ; out of the top, past 32 bits.
    EX   DE,HL                     ; DEHL is ten times the value.
    POP  AF                        ; The digit
    LD   C,A                       ; as
    LD   B,0                       ; a word
    ADD  HL,BC                     ; is added
    RET  NC                        ; to the low word,
    INC  DE                        ; its carry to the high word,
    LD   A,D                       ; which
    OR   E                         ; passes 32 bits
    RET  NZ                        ; only when it wraps to zero.

;@ROUTINE CLOBBERS A
; The decimal number scanned has passed 32 bits (TK_WIDE).

TK_OVER:                       ; A carry left the top.
    LD   A,1                       ; Mark it.
    LD   (TK_WIDE),A               ; It is malformed once complete.
    RET                            ; Scanning goes on.

;@ROUTINE IN DE,HL OUT DE,HL CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Double DEHL, marking a carry out of the top (TK_WIDE).

TK_DBL:                        ; DEHL is the value.
    ADD  HL,HL                     ; The low word doubles,
    RL   E                         ; its carry
    RL   D                         ; into the high word.
    RET  NC                        ; Nothing left the top,
    JR   TK_OVER                   ; or something did.

;@ROUTINE OUT A,BC,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Scan a character literal: its body scanned as a string's, escapes
; included (TK_QBODY), then exactly one decoded byte (empty-character, or
; long-character, at its start), returned as TK_CHAR with the byte in C
; and B zero, which makes BC the whole payload.

TK_APOS:                       ; The current byte is the opening apostrophe.
    LD   A,'\''                    ; Its body, to the
    CALL TK_QBODY                  ; closing apostrophe: C bytes.
    LD   A,C                       ; None
    OR   A                         ; is
    LD   E,DG_NONE                 ; empty-character;
    JR   Z,TK_ECODE                ; more
    DEC  A                         ; than one
    LD   E,DG_LONGC                ; is
    JR   NZ,TK_ECODE               ; long-character.
    LD   HL,(TK_PTR)               ; The byte,
    INC  HL                        ; after the apostrophe,
    CALL AG_CHAR                   ; decoded,
    LD   C,A                       ; is the payload.
    LD   A,TK_CHAR                 ; The token kind:
    JR   TK_QEND                   ; return the character.

; Literal failures, within JR range of the scanners, each raised at the
; literal's start: E is the code (TK_ECODE). A control byte is bad-byte,
; but a line end leaves the literal unterminated, as the reference finds.

TK_ECTL:                       ; A control byte in a literal.
    CP   10                        ; A line end
    JR   Z,TK_EOPEN                ; ends it unterminated;
    CP   13                        ; so does
    JR   Z,TK_EOPEN                ; a CR.
TK_EBYTE:                      ; A byte no literal may hold.
    LD   E,DG_LEXB                 ; bad-byte.
    JR   TK_ECODE                  ; Raise it.
TK_EOPEN:                      ; The part or the line ended inside it.
    LD   E,DG_OPEN                 ; unterminated-literal.
TK_ECODE:                      ; E is the diagnostic.
    LD   A,E                       ; At the literal's start,
    JP   DG_ISSUE                  ; raise it.

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Carry reports whether A is a hexadecimal digit of either case, and A then
; holds its value, 0..15; with carry clear A may be altered. TK_RADIX uses
; the value and the string scan the flag; AGGR decodes \xHH with it.

TK_HEX:                        ; A: the byte to classify.
    SUB  '0'                       ; '0'..'9' now lie in 0..9; others wrap above.
    CP   10                        ; A decimal digit?
    RET  C                         ; Carry: A is its value.
    ADD  A,'0'                     ; The byte again.
    OR   $20                       ; Fold capitals onto lower case.
    SUB  'a'                       ; 'a'..'f' now lie in 0..5; others above.
    CP   6                         ; Six letter digits.
    RET  NC                        ; Not 'a'..'f': carry clear.
    ADD  A,10                      ; Value 10..15; this add leaves carry clear.
    SCF                            ; Carry set: a hexadecimal digit.
    RET                            ; A is its value.

;@ROUTINE OUT A,BC,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Scan and validate a string literal, returning TK_TEXT with the decoded
; length in BC and TK_LEN. TK_PTR still points at the opening quote, so the
; declaration parser can decode the bytes straight into the static image.

TK_QUOTE:                      ; The current byte is the opening quote.
    LD   A,'"'                     ; Its body, to the
    CALL TK_QBODY                  ; closing quote: C bytes.
    LD   A,C                       ; The decoded length,
    LD   (TK_LEN),A                ; kept for the declaration parser.
    LD   A,TK_TEXT                 ; The token kind.
TK_QEND:                       ; A is the kind, C the payload:
    LD   B,0                       ; BC.
    JP   TK_DONE                   ; Return the token.

;@ROUTINE IN A OUT C CLOBBERS A,B,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Scan a literal's body after its opening quote, the current byte, to the
; closing quote A: printable bytes and the escapes \0 \n \r \t \' \" \\ and
; \xHH, each counted as one decoded byte in C (the reference's literal);
; anything else is raised at the literal's start.

TK_QBODY:                      ; A is the closing quote.
    LD   (TK_QCH),A                ; Kept.
    CALL SRC_TAKE                  ; The opening one consumed.
    LD   C,0                       ; C counts the decoded bytes.
TK_QNEXT:                      ; Take the next byte of the body.
    CALL SRC_TAKE                  ; Consume it; C survives.
    JR   C,TK_EOPEN                ; The part ended: unterminated.
    LD   HL,TK_QCH                 ; The closing quote
    CP   (HL)                      ; ends the body.
    RET  Z                         ; The literal is complete; C its length.
    CP   $20                       ; Printable bytes begin at space;
    JR   C,TK_ECTL                 ; a line end leaves it unterminated.
    CP   $7F                       ; And end before DEL.
    JR   NC,TK_EBYTE               ; DEL and the bytes above are refused.
    CP   '\\'                      ; A backslash begins an escape.
    JR   Z,TK_QESC                 ; An escape follows.
TK_QCNT:                       ; One more decoded byte.
    INC  C                         ; Count it.
    JR   NZ,TK_QNEXT               ; Take the next byte.
    LD   A,DG_RANGE                ; 256 bytes: too long for TK_LEN,
    JP   DG_ISSUE                  ; and for any string (out-of-range).
TK_QESC:                       ; The backslash is consumed; the escape follows.
    LD   HL,(SRC_POS)              ; The backslash's
    DEC  HL                        ; offset,
    PUSH HL                        ; where a bad one is reported.
    CALL SRC_TAKE                  ; The escape letter.
    JR   C,.BAD                    ; The part ended: incomplete.
    CP   'x'                       ; \x takes two hexadecimal digits.
    JR   Z,.HEX                    ; Check them.
    LD   HL,TK_ESC                 ; The single-letter escapes.
    LD   B,TK_ECNT                 ; B counts the letters left.
.LOOP:                         ; B letters remain at HL.
    CP   (HL)                      ; Compare with this escape letter.
    JR   Z,.ONE                    ; A known escape decodes to one byte.
    INC  HL                        ; Next letter.
    DJNZ .LOOP                     ; Until the table is exhausted.
.BAD:                          ; An unknown or incomplete escape:
    POP  HL                        ; bad-escape,
    LD   A,DG_ESC                  ; at the
    JP   DG_HERE                   ; backslash.
.HEX:                          ; Exactly two digits must follow.
    LD   B,2                       ; B counts them.
.DIGIT:                        ; B digits remain.
    CALL SRC_TAKE                  ; The next digit; B survives.
    CALL TK_HEX                    ; Only its validity matters here.
    JR   NC,.BAD                   ; Not a hexadecimal digit.
    DJNZ .DIGIT                    ; Until both are taken.
.ONE:                          ; One decoded byte:
    POP  HL                        ; the offset dropped.
    JR   TK_QCNT                   ; Count it.

;@ROUTINE OUT CARRY CLOBBERS A,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Skip the rest of a // comment, leaving its line end unconsumed for
; TK_NEXT. Carry is set if the part ended first.

TK_REM:                        ; Both slashes are consumed.
.LOOP:                         ; Every byte up to the line end is commentary.
    CALL SRC_PEEK                  ; Next byte, not yet consumed.
    RET  C                         ; The end of the part ends the comment.
    CP   10                        ; LF ends the comment.
    RET  Z                         ; Ends the comment, left for TK_NEXT.
    CP   13                        ; So does CR.
    RET  Z                         ; Ends the comment, left for TK_NEXT.
    CALL SRC_TAKE                  ; Discard the commentary byte.
    JR   .LOOP                     ; Examine the next byte.

;@ROUTINE OUT A,BC,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Return the next token: A is its kind, ZERO is set only for TK_EOF and
; carry is always clear. BC carries the value of TK_NUM, TK_CHAR and
; TK_TEXT; the module header lists the other token fields.

TK_NEXT:                       ; The parser's entry.
TK_AGAIN:                      ; Rescan after whitespace, a comment or a line end.
    CALL TK_MARK                   ; The token, if any, starts here.
    CALL SRC_PEEK                  ; Its first byte, not yet consumed.
    JP   C,TK_ATEND                ; The current part is exhausted.

    CP   ' '                       ; A space separates tokens.
    JR   Z,.SKIP                   ; Whitespace separates tokens.
    CP   9                         ; So does a tab.
    JR   Z,.SKIP                   ; Also whitespace.
    CP   10                        ; LF ends a line.
    JP   Z,TK_LF                   ; Ends the line.
    CP   13                        ; CR begins a CR LF line end.
    JP   Z,TK_CRLF                 ; Must begin CR LF.
    CP   '/'                       ; A slash is division or a comment.
    JR   Z,.SLASH                  ; Division, or a // comment.
    CP   '('                       ; Brackets also track the nesting depth.
    JP   Z,.LPAR                   ; Open a parenthesis.
    CP   ')'                       ; A closing parenthesis.
    JP   Z,.RPAR                   ; Close a parenthesis.
    CP   '['                       ; An opening bracket.
    JP   Z,.LBRAC                  ; Open a bracket.
    CP   ']'                       ; A closing bracket.
    JP   Z,.RBRAC                  ; Close a bracket.
    CP   '<'                       ; Less than, or a two-byte relation.
    JR   Z,.LESS                   ; <, <= or <>.
    CP   '>'                       ; Greater than, or greater or equal.
    JR   Z,.GREATER                ; > or >=.
    LD   HL,KW_PUNCT               ; Pairs: a byte, then its kind or descriptor.
    LD   B,KW_PCNT                 ; B counts the pairs left.
.PUNCT:                        ; HL is at a pair's byte.
    CP   (HL)                      ; Compare with this pair's byte.
    INC  HL                        ; HL at the pair's kind; ZERO survives.
    JP   Z,TK_PUNCT                ; A one-byte token, or a $ or % prefix.
    INC  HL                        ; HL at the next pair.
    DJNZ .PUNCT                    ; B is zero once the table is exhausted.
    CP   '\''                      ; An apostrophe opens a character.
    JP   Z,TK_APOS                 ; A character literal; B is zero.
    CP   '"'                       ; A quote opens a string.
    JP   Z,TK_QUOTE                ; A string literal.
    CP   '0'                       ; Digits begin at '0'.
    JR   C,.NAME                   ; Below the digits: not a number.
    CP   '9'+1                     ; Digits end at '9'.
    JP   C,TK_DIGIT                ; A decimal literal.
.NAME:                         ; Only a name remains possible.
    CALL TK_ALPHA                  ; Names begin with a letter.
    JP   C,TK_WORD                 ; A name or a keyword.
    CP   $20                       ; A control byte,
    JR   C,.FAULT                  ; or DEL
    CP   $7F                       ; and above,
    JR   NC,.FAULT                 ; is bad-byte;
    JP   TK_BAD                    ; any other begins no token.
.FAULT:                        ; A byte the source may not contain.
    LD   B,DG_LEXB                 ; bad-byte, at it.
.SHUT:                         ; B is the diagnostic.
    LD   A,B                       ; Raise it
    JP   DG_ISSUE                  ; at the token.

.SKIP:                         ; A: a space or a tab.
    CALL SRC_TAKE                  ; Discard it.
    JR   TK_AGAIN                  ; Mark the next token's start.

.SLASH:                        ; A: the first '/'.
    CALL SRC_TAKE                  ; Consume it.
    CALL SRC_PEEK                  ; A second '/' makes a comment.
    JR   C,.DIVIDE                 ; The part ended: a division sign.
    CP   '/'                       ; A second slash begins a comment.
    JR   NZ,.DIVIDE                ; No: a division sign.
    CALL SRC_TAKE                  ; Consume the second '/'.
    CALL TK_REM                    ; Skip to the line end.
    JP   TK_AGAIN                  ; The line end is scanned next.
.DIVIDE:                       ; A lone '/', already consumed.
    LD   A,TK_SLASH                ; The token kind.
    JP   TK_DONE                   ; Return the division sign.

.LESS:                         ; A: '<'.
    CALL SRC_TAKE                  ; Consume it.
    CALL SRC_PEEK                  ; A second byte may extend it.
    JR   C,.LT                     ; The part ended: a lone '<'.
    CP   '='                       ; '=' makes less or equal.
    JR   Z,.LE                     ; <=.
    CP   '>'                       ; '>' makes not equal.
    JR   Z,.NE                     ; <>.
.LT:                           ; A lone '<', already consumed.
    LD   A,TK_LT                   ; The token kind.
    JP   TK_DONE                   ; Return less than.
.LE:                           ; '=' is current.
    LD   C,TK_LE                   ; The token kind.
    JR   TK_TAKE                   ; Consume the '=' and return C.
.NE:                           ; '>' is current.
    LD   C,TK_NE                   ; The token kind.
    JR   TK_TAKE                   ; Consume the '>' and return C.

.GREATER:                      ; A: '>'.
    CALL SRC_TAKE                  ; Consume it.
    CALL SRC_PEEK                  ; A second byte may extend it.
    JR   C,.GT                     ; The part ended: a lone '>'.
    CP   '='                       ; '=' makes greater or equal.
    JR   Z,.GE                     ; >=.
.GT:                           ; A lone '>', already consumed.
    LD   A,TK_GT                   ; The token kind.
    JP   TK_DONE                   ; Return greater than.
.GE:                           ; '=' is current.
    LD   C,TK_GE                   ; The token kind.
    JR   TK_TAKE                   ; Consume the '=' and return C.

.LPAR:                         ; A: '('.
    LD   C,TK_LPAR                 ; The token kind.
    JR   .OPEN                     ; Count the level.

.RPAR:                         ; A: ')'.
    LD   C,TK_RPAR                 ; The token kind.
    JR   .CLOSE                    ; Uncount the level.

.LBRAC:                        ; A: '['.
    LD   C,TK_LBRAC                ; The token kind; fall into the open path.
.OPEN:                         ; C: the kind of the opening bracket.
    CALL SRC_TAKE                  ; Consume it; C survives.
    LD   A,(TK_NEST)               ; The current depth.
    INC  A                         ; One level deeper.
    JR   Z,TK_DEEP                 ; 256 open brackets: refused.
    LD   (TK_NEST),A               ; Line ends are whitespace while nonzero.
    LD   A,C                       ; Return the bracket's kind.
    JP   TK_DONE                   ; Return the opening bracket.

.RBRAC:                        ; A: ']'.
    LD   C,TK_RBRAC                ; The token kind; fall into the close path.
.CLOSE:                        ; C: the kind of the closing bracket.
    LD   A,(TK_NEST)               ; The current depth.
    SUB  1                         ; One level out; the parser checks the kind.
    LD   B,DG_SHUT                 ; Below zero: an unbalanced close,
    JR   C,.SHUT                   ; unmatched-delimiter.
    LD   (TK_NEST),A               ; Line ends count again at depth zero.
    CALL SRC_TAKE                  ; Consume the bracket; C survives.
    LD   A,C                       ; Return the bracket's kind.
    JP   TK_DONE                   ; Return the closing bracket.

TK_DEEP:                       ; Brackets open 256 deep:
    LD   A,DG_NEST                 ; this compiler's capacity,
    JP   DG_ISSUE                  ; nesting.

; HL is at the KW_PUNCT descriptor for the byte in A, not yet consumed. Bit
; 7 of a descriptor introduces a based number, and its low seven bits are
; one more than that base's digit limit.

TK_PUNCT:                      ; HL: the matched pair's second byte.
    LD   C,(HL)                    ; A token kind or a based-number descriptor.
    BIT  7,C                       ; Bit 7 marks a based-number descriptor.
    JR   NZ,TK_BASED               ; $ or %: a based number.
TK_TAKE:                       ; C: the kind of a token ending at the current byte.
    CALL SRC_TAKE                  ; Consume that byte; C survives.
    LD   A,C                       ; The token kind.
    JP   TK_DONE                   ; Return the token.
TK_BASED:                      ; C: the descriptor of $ or %.
    RES  7,C                       ; C: digit limit plus one; bit 5 set for binary.
    LD   B,C                       ; B counts down the digits allowed.
    JR   TK_RADIX                  ; Scan the based number.

; Line ends. TK_LF and TK_CRLF consume LF or CR LF; TK_BREAK then counts the
; line and decides whether the parser sees it as a token.

TK_ECR:                        ; A carriage return without a line feed.
    LD   A,DG_CR                   ; lone-cr,
    JP   DG_ISSUE                  ; at the line's end.

TK_LF:                         ; A: LF.
    CALL SRC_TAKE                  ; Consume it.
    JR   TK_BREAK                  ; Count the line.
TK_CRLF:                       ; A: CR.
    CALL SRC_TAKE                  ; Consume it.
    CALL SRC_PEEK                  ; Only LF may follow.
    JR   C,TK_ECR                  ; A bare CR at the end of the part.
    CP   10                        ; Only LF completes CR LF.
    JR   NZ,TK_ECR                 ; A bare CR within the text.
    CALL SRC_TAKE                  ; Consume the LF.
TK_BREAK:                      ; The line end is consumed.
    CALL SRC_EOL                   ; Next line; the column returns to one.
    LD   A,(TK_NEST)               ; The bracket depth.
    OR   A                         ; Nonzero inside brackets.
    JP   NZ,TK_AGAIN               ; Then the line end is whitespace.
    LD   A,(TK_LIVE)               ; Nonzero if the line produced a token.
    OR   A                         ; Test the flag.
    JP   Z,TK_AGAIN                ; Blank or comment-only: no TK_EOL.
TK_EOLR:                       ; Return a line end; the next line starts empty.
    XOR  A                         ; The next line starts empty.
    LD   (TK_LIVE),A               ; Clear the flag.
    LD   A,TK_EOL                  ; The token kind; TK_POS marks the line end.
    OR   A                         ; Carry clear; ZERO clear.
    RET                            ; Return the line end.

; The current part is exhausted. Before a later part, a live last line first
; yields a synthetic TK_EOL and sets SRC_OWE, so that the next call steps
; to the next part. After the last part, TK_EOF repeats. While the START
; overlay reads a part's include lines, SRC_NUM is one less than SRC_PCNT,
; so that every part is the last.

TK_ATEND:                      ; SRC_PEEK reported the end of the part.
    LD   A,(TK_NEST)               ; The bracket depth.
    OR   A                         ; Nonzero if a bracket is still open:
    LD   A,DG_AJAR                 ; open-delimiter,
    JP   NZ,DG_ISSUE               ; at the part's end.
    LD   HL,SRC_OWE                ; Was the boundary line end returned?
    LD   A,(HL)                    ; Then
    OR   A                         ; move on
    JR   NZ,.NEXTPART              ; to the next part.
    LD   A,(SRC_NUM)               ; Is this
    INC  A                         ; the stream's
    LD   DE,SRC_PCNT               ; last
    EX   DE,HL                     ; part?
    CP   (HL)                      ; Its number plus one is the count:
    JR   Z,.LAST                   ; then nothing follows.
    LD   A,(TK_LIVE)               ; Nonzero if the last line produced a token.
    OR   A                         ; Test the flag.
    JR   Z,.NEXTPART               ; No: no TK_EOL is owed.
    EX   DE,HL                     ; HL is SRC_OWE:
    INC  (HL)                      ; step to the next part on the next call.
    JR   TK_EOLR                   ; A synthetic line end; TK_LIVE cleared.
.NEXTPART:                     ; Step to the next source part.
    XOR  A                         ; No line end
    LD   (SRC_OWE),A               ; is owed there.
    LD   A,(SRC_NUM)               ; The next number
    INC  A                         ; in the stream:
    CALL SRC_BODY                  ; its body, its line, TK_LIVE and TK_NEST.
    JP   TK_AGAIN                  ; Scan from the body's first byte.
.LAST:                         ; No later part.
    LD   A,(TK_LIVE)               ; Nonzero if the last line produced a token.
    OR   A                         ; Test the flag.
    JR   Z,.EOF                    ; No: nothing is owed.
    JR   TK_EOLR                   ; End an unterminated last line; TK_EOF follows.
.EOF:                          ; The source is finished.
    LD   A,TK_EOF                  ; The token kind, zero.
    OR   A                         ; ZERO set marks the end; carry clear.
    RET                            ; TK_LIVE stays clear, so TK_EOF repeats.

;@ROUTINE IN BC OUT A,BC,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Scan a $ hexadecimal or % binary literal whose prefix is current. B and C
; are one more than the digit limit, 9 for hexadecimal and 33 for binary,
; and bit 5 of C selects binary. Returns TK_NUM with the value's low word
; in BC and its high word in TK_NHI. A bare prefix, or more digits than
; 32 bits hold, is malformed.

TK_RADIX:                      ; B, C: the digit limit plus one.
    CALL SRC_TAKE                  ; Consume the prefix.
    CALL TK_ZERO                   ; No value and no carry yet.
.LOOP:                         ; B-1 digits are still allowed.
    CALL SRC_PEEK                  ; Next byte, not yet consumed.
    JR   C,.END                    ; The end of the part ends the literal.
    PUSH AF                        ; Keep the byte.
    BIT  5,C                       ; 33 has bit 5 set and 9 does not.
    JR   NZ,.BINARY                ; Binary digits are tested apart.
    CALL TK_HEX                    ; Carry and its value for a hex digit.
    JR   .KIND                     ; Decide.
.BINARY:                       ; Only 0 and 1 are binary digits.
    SUB  '0'                       ; The digit's value, if any:
    CP   2                         ; carry for 0 and 1.
.KIND:                         ; Carry if A is a digit's value.
    JR   NC,.STOP                  ; Any other byte ends the literal.
    POP  DE                        ; The byte is not needed.
    DEC  B                         ; One fewer digit allowed:
    JP   Z,TK_ENUM                 ; more than 32 bits hold is malformed.
    PUSH BC                        ; Keep the counts
    PUSH AF                        ; and the digit.
    CALL TK_LOAD                   ; DEHL is the value so far.
    LD   B,1                       ; One shift for binary,
    BIT  5,C                       ; whose bit
    JR   NZ,.SHIFT                 ; is set,
    LD   B,4                       ; four for hexadecimal.
.SHIFT:                        ; B shifts remain.
    CALL TK_DBL                    ; Shift one bit.
    DJNZ .SHIFT                    ; The low bits are now clear.
    POP  AF                        ; The digit
    OR   L                         ; joins
    LD   L,A                       ; them.
    CALL TK_SAVE                   ; The new value is kept.
    CALL SRC_TAKE                  ; Consume the digit.
    POP  BC                        ; The counts.
    JR   .LOOP                     ; Scan the next byte.
.STOP:                         ; The byte after the digits is pushed.
    POP  DE                        ; D is it.
    CALL .SOME                     ; A digit must have been taken.
    LD   A,D                       ; The byte after the literal:
    JP   TK_TRAIL                  ; no name byte may follow.
.END:                          ; The part ends.
    CALL .SOME                     ; A digit must have been taken;
    JP   TK_NUMOK                  ; nothing follows.
.SOME:                         ; B is C when no digit was taken.
    LD   A,B                       ; Digits still allowed, plus one:
    CP   C                         ; equal to the limit, the prefix
    RET  NZ                        ; is bare
    JP   TK_ENUM                   ; and malformed.

; The single-letter string escapes \0 \n \r \t \' \" and \\, searched by
; TK_QESC. AGGR's decoder translates them separately.

TK_ESC: DB   "0nrt",$27,$22,"\\" ; Escape letters after a backslash.
TK_ECNT EQU  7                 ; Number of single-letter escapes.
