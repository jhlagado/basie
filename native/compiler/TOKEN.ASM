;==========================================================================
;  Tokenizer
;==========================================================================
;
;  Turn the bytes of the current source part into tokens, one per call to
;  TK_NEXT. The parser is the only client: PR_PEEK holds one token of
;  lookahead, and the grammar actions read the current token's fields as
;  they append operations to the semantic transcript. Source bytes arrive
;  only through the source adapter (SRC_PEEK, SRC_TAKE, SRC_EOL, SRC_LOAD).
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
;    TK_NUM            BC = value, 0..65535
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
;  lower case. A number is decimal (at most 65535), $ hexadecimal (at most
;  four digits) or % binary (at most sixteen digits), and may not run
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
;  TK_ATEND also advances the multipart byte SRC_LEFT. SRC_PEEK and SRC_TAKE
;  clobber DE and HL but keep BC, so the scanners hold counts and payloads
;  in B and C, and save an accumulator in HL around each source call.

;@ROUTINE CLOBBERS HL
; Record the source cursor as the start of the next token: the position
; for diagnostics and the byte pointer for names and literals.

TK_MARK:                       ; Copy the four cursor words.
    LD   HL,(SRC_POS)              ; Byte offset within the current part.
    LD   (TK_POS),HL               ; Becomes the token's diagnostic offset.
    LD   HL,(SRC_LINE)             ; Current line, counted from one.
    LD   (TK_LINE),HL              ; Becomes the token's line.
    LD   HL,(SRC_COL)              ; Current byte column, counted from one.
    LD   (TK_COL),HL               ; Becomes the token's column.
    LD   HL,(SRC_PTR)              ; Address of the token's first byte.
    LD   (TK_PTR),HL               ; Names and literals are read from here.
    RET                            ; Flags and the other registers survive.

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
    LD   E,(HL)                    ; Low byte of the retained name's address.
    INC  HL                        ; Step to its high byte.
    LD   D,(HL)                    ; DE: the retained name in the source.
    INC  HL                        ; Step to the length byte.
    LD   A,(HL)                    ; Length of the retained name.
    LD   B,A                       ; TK_MATCH takes the length in B.
    EX   DE,HL                     ; And the bytes in HL.
    CALL TK_MATCH                  ; Carry and ZERO report the comparison.
    POP  HL                        ; Restore the record address.
    POP  BC                        ; Restore the caller's count.
    RET                            ; The flags from TK_MATCH survive the pops.

;@ROUTINE IN HL OUT A,BC,HL
; Retain the current name in the three-byte record at HL: its source
; address, then its length. HL returns at the length byte, so that callers
; step on to the fields that follow. The flags are preserved.

TK_KEEP:                       ; HL: the record to fill.
    LD   BC,(TK_PTR)               ; The name stays in the resident source.
    LD   (HL),C                    ; Address, low byte.
    INC  HL                        ; Step to the high byte.
    LD   (HL),B                    ; Address, high byte.
    INC  HL                        ; Step to the length byte.
    LD   A,(TK_LEN)                ; Length of the name.
    LD   (HL),A                    ; Completes the record.
    RET                            ; A is the length and BC the address.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY
; Scan a name whose first byte, a letter, is current, then look it up in
; KW_TAB. A returns the keyword's kind, or TK_NAME; TK_PTR and TK_LEN
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
    JR   Z,TK_BAD                  ; 256 bytes: too long for TK_LEN.
    JR   .NAMELOOP                 ; Scan the next byte.
.DONE:                         ; B is the name's length.
    LD   A,B                       ; Publish the length for the parser.
    LD   (TK_LEN),A                ; TK_PTR already holds its address.
    LD   HL,KW_TAB                 ; Entries: length, bytes, kind.
    LD   C,KW_CNT                  ; C counts the entries left.
.KEYLOOP:                      ; HL is at an entry's length byte.
    LD   B,(HL)                    ; Keyword length.
    INC  HL                        ; HL at the keyword's first byte.
    LD   A,(TK_LEN)                ; Length of the name.
    CP   B                         ; Only equal lengths need a byte compare.
    JR   NZ,.SKIP                  ; Lengths differ: B bytes remain to pass.
    LD   DE,(TK_PTR)               ; DE walks the name in the source.
.BYTELOOP:                     ; B keyword bytes remain at HL.
    LD   A,(DE)                    ; Next byte of the name.
    CP   (HL)                      ; Keywords match exactly: case counts.
    JR   NZ,.SKIP                  ; B bytes of the keyword remain at HL.
    INC  DE                        ; Next byte of the name.
    INC  HL                        ; Next byte of the keyword.
    DJNZ .BYTELOOP                 ; Until the whole keyword agrees.
    LD   A,(HL)                    ; HL is at the kind byte after the keyword.
    JP   TK_DONE                   ; Return the keyword's kind.
.SKIP:                         ; B bytes of this keyword remain at HL.
    LD   E,B                       ; DE: the bytes still to pass.
    LD   D,0                       ; Keywords are under 256 bytes.
    ADD  HL,DE                     ; HL at the kind byte.
    INC  HL                        ; HL at the next entry.
    DEC  C                         ; One entry fewer to try.
    JR   NZ,.KEYLOOP               ; Try the next keyword.
    LD   A,TK_NAME                 ; No keyword matched: an ordinary name.
    JP   TK_DONE                   ; Return the name.

;@ROUTINE OUT A,BC,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Scan a decimal literal whose first digit is current and return TK_NUM
; with its value in BC. A value above 65535, or a name byte straight after
; the digits, is a lexical error. Reached by a jump from TK_NEXT.

TK_DIGIT:                      ; The current byte is a decimal digit.
    LD   HL,0                      ; HL accumulates the value.
.LOOP:                         ; HL is the value of the digits so far.
    PUSH HL                        ; The source adapter clobbers HL.
    CALL SRC_PEEK                  ; Next byte, not yet consumed.
    POP  HL                        ; Recover the value.
    JR   C,TK_NUMOK                ; The end of the part ends the literal.
    CP   '0'                       ; Digits begin at '0'.
    JR   C,TK_TRAIL                ; Not a digit: the literal ends here.
    CP   '9'+1                     ; Digits end at '9'.
    JR   NC,TK_TRAIL               ; Not a digit: the literal ends here.
    SUB  '0'                       ; The digit's value, 0..9.
    LD   C,A                       ; C keeps the digit through the range test.
    LD   A,H                       ; HL*10+C fits only up to HL = 6553 ($1999).
    CP   $19                       ; Compare the high byte with $19.
    JR   C,.APPEND                 ; HL below $1900: always fits.
    JR   NZ,TK_ERR                 ; HL $1A00 or more: too large.
    LD   A,L                       ; The high byte is $19: the low byte decides.
    CP   $99                       ; Compare the low byte with $99.
    JR   C,.APPEND                 ; HL below $1999: fits.
    JR   NZ,TK_ERR                 ; HL above $1999: too large.
    LD   A,C                       ; HL is 6553: the result is 65530 plus the digit.
    CP   6                         ; Digits 0..5 stay within 65535.
    JR   NC,TK_ERR                 ; 65536 or more: too large.
.APPEND:                       ; HL*10+C cannot overflow now.
    LD   D,0                       ; DE: the digit, as a word.
    LD   E,C                       ; C is free once the digit is in E.
    ADD  HL,HL                     ; HL*2.
    LD   B,H                       ; BC: HL*2, kept for the sum.
    LD   C,L                       ; Completes the copy.
    ADD  HL,HL                     ; HL*4.
    ADD  HL,HL                     ; HL*8.
    ADD  HL,BC                     ; HL*8 + HL*2 = HL*10.
    ADD  HL,DE                     ; Plus the digit.
    PUSH HL                        ; Keep the value across the adapter.
    CALL SRC_TAKE                  ; Consume the digit.
    POP  HL                        ; Recover the value.
    JR   .LOOP                     ; Scan the next byte.

; The literal has ended at the byte in A, which is not consumed. An integer
; cannot be followed immediately by a name byte: forms such as 0x2a and
; 12u8 are one malformed number, not a misleading number and name. TK_RADIX
; joins here too.

TK_TRAIL:                      ; A: the byte after the literal; HL: its value.
    CALL TK_ALNUM                  ; Carry if a letter, digit or underscore.
    JP   C,TK_BAD                  ; Then the literal is malformed.
TK_NUMOK:                      ; HL is a complete, valid value.
    LD   B,H                       ; BC: the payload.
    LD   C,L                       ; Completes the copy.
    LD   A,TK_NUM                  ; The token kind.
    JP   TK_DONE                   ; Return the number.

;@ROUTINE IN B OUT A,BC,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Scan a character literal: one printable byte between apostrophes, with no
; escapes, returned as TK_CHAR with the byte in C. B arrives zero from the
; punctuation scan in TK_NEXT, which makes BC the whole payload.

TK_APOS:                       ; The current byte is the opening apostrophe.
    CALL SRC_TAKE                  ; Consume it.
    JR   C,TK_ERR                  ; Cannot fail: TK_NEXT has seen the byte.
    CALL SRC_TAKE                  ; The character itself.
    JR   C,TK_ERR                  ; The part ended: unterminated.
    CP   $20                       ; Printable bytes begin at space.
    JR   C,TK_ERR                  ; Control bytes, line ends included, are refused.
    CP   $7F                       ; And end before DEL.
    JR   NC,TK_ERR                 ; DEL and the bytes above are refused.
    CP   '\''                      ; An apostrophe here would close an empty literal.
    JR   Z,TK_ERR                  ; Then the literal is empty.
    CP   '\\'                      ; A backslash would begin an escape.
    JR   Z,TK_ERR                  ; Character literals have no escapes.
    LD   C,A                       ; C: the payload byte; B is already zero.
    CALL SRC_TAKE                  ; The closing apostrophe.
    JR   C,TK_ERR                  ; The part ended: unterminated.
    CP   '\''                      ; Exactly one byte is allowed.
    JR   NZ,TK_ERR                 ; More than one byte, or unclosed.
    LD   A,TK_CHAR                 ; The token kind.
    JP   TK_DONE                   ; Return the character.
TK_ERR:                        ; Error exit within JR range of the scanners.
    JP   TK_BAD                    ; Raise the lexical diagnostic.

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Carry reports whether A is a hexadecimal digit of either case, and A then
; holds its value, 0..15; with carry clear A may be altered. TK_RADIX uses
; the value and the string scan the flag; AGGR decodes \xHH with it.

TK_HEX:                        ; A: the byte to classify.
    CP   '0'                       ; Digits begin at '0'.
    JR   C,.NO                     ; Below the digits.
    CP   '9'+1                     ; Decimal digits end at '9'.
    JR   C,.DECIMAL                ; '0'..'9'.
    OR   $20                       ; Fold capitals onto lower case.
    SUB  'a'                       ; 'a'..'f' now lie in 0..5.
    CP   6                         ; Six letter digits.
    JR   NC,.NO                    ; Not 'a'..'f'.
    ADD  A,10                      ; Value 10..15; this add leaves carry clear.
    SCF                            ; Carry set: a hexadecimal digit.
    RET                            ; A is its value.
.DECIMAL:                      ; A is '0'..'9'.
    SUB  '0'                       ; Value 0..9.
    SCF                            ; Carry set: a hexadecimal digit.
    RET                            ; A is its value.
.NO:                           ; Not a hexadecimal digit.
    OR   A                         ; Carry clear; A may have been folded.
    RET                            ; Report no digit.

;@ROUTINE OUT A,BC,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Scan and validate a string literal, returning TK_TEXT with the decoded
; length in BC and TK_LEN. TK_PTR still points at the opening quote, so the
; declaration parser can decode the bytes straight into the static image.

TK_QUOTE:                      ; The current byte is the opening quote.
    CALL SRC_TAKE                  ; Consume it.
    JR   C,TK_ERR                  ; Cannot fail: TK_NEXT has seen the byte.
    LD   C,0                       ; C counts the decoded bytes.
TK_QNEXT:                      ; Take the next byte of the body.
    CALL SRC_TAKE                  ; Consume it; C survives.
    JR   C,TK_ERR                  ; The part ended: unterminated.
    CP   '"'                       ; The closing quote ends the body.
    JR   Z,TK_QDONE                ; The literal is complete.
    CP   $20                       ; Printable bytes begin at space.
    JR   C,TK_ERR                  ; Control bytes: a string cannot cross a line end.
    CP   $7F                       ; And end before DEL.
    JR   NC,TK_ERR                 ; DEL and the bytes above are refused.
    CP   '\\'                      ; A backslash begins an escape.
    JR   Z,TK_QESC                 ; An escape follows.
TK_QCNT:                       ; One more decoded byte.
    INC  C                         ; Count it.
    JR   Z,TK_ERR                  ; 256 bytes: too long for TK_LEN.
    JR   TK_QNEXT                  ; Take the next byte.
TK_QESC:                       ; The backslash is consumed; the escape follows.
    CALL SRC_TAKE                  ; The escape letter.
    JR   C,TK_ERR                  ; The part ended: unterminated.
    CP   'x'                       ; \x takes two hexadecimal digits.
    JR   Z,.HEX                    ; Check them.
    LD   HL,TK_ESC                 ; The single-letter escapes.
    LD   B,TK_ECNT                 ; B counts the letters left.
.LOOP:                         ; B letters remain at HL.
    CP   (HL)                      ; Compare with this escape letter.
    JR   Z,TK_QCNT                 ; A known escape decodes to one byte.
    INC  HL                        ; Next letter.
    DJNZ .LOOP                     ; Until the table is exhausted.
    JR   TK_ERR                    ; An unknown escape.
.HEX:                          ; Exactly two digits must follow.
    CALL SRC_TAKE                  ; The first digit.
    JR   C,TK_ERR                  ; The part ended: unterminated.
    CALL TK_HEX                    ; Only its validity matters here.
    JR   NC,TK_ERR                 ; Not a hexadecimal digit.
    CALL SRC_TAKE                  ; The second digit.
    JR   C,TK_ERR                  ; The part ended: unterminated.
    CALL TK_HEX                    ; Only its validity matters here.
    JR   NC,TK_ERR                 ; Not a hexadecimal digit.
    JR   TK_QCNT                   ; \xHH decodes to one byte.
TK_QDONE:                      ; The closing quote is consumed; C is the length.
    LD   B,0                       ; BC: the payload; B was the escape count.
    LD   A,C                       ; The decoded length.
    LD   (TK_LEN),A                ; Kept for the declaration parser.
    LD   A,TK_TEXT                 ; The token kind.
    JP   TK_DONE                   ; Return the string.

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
    JR   TK_FAULT                  ; No token begins with this byte.

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
    JR   TK_AGAIN                  ; The line end is scanned next.
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
    JR   Z,TK_FAULT                ; 256 open brackets: refused.
    LD   (TK_NEST),A               ; Line ends are whitespace while nonzero.
    LD   A,C                       ; Return the bracket's kind.
    JP   TK_DONE                   ; Return the opening bracket.

.RBRAC:                        ; A: ']'.
    LD   C,TK_RBRAC                ; The token kind; fall into the close path.
.CLOSE:                        ; C: the kind of the closing bracket.
    LD   A,(TK_NEST)               ; The current depth.
    OR   A                         ; Zero when nothing is open.
    JR   Z,TK_FAULT                ; No: an unbalanced close.
    DEC  A                         ; One level out; the parser checks the kind.
    LD   (TK_NEST),A               ; Line ends count again at depth zero.
    CALL SRC_TAKE                  ; Consume the bracket; C survives.
    LD   A,C                       ; Return the bracket's kind.
    JP   TK_DONE                   ; Return the closing bracket.

TK_FAULT:                      ; Error exit within JR range of TK_NEXT.
    JP   TK_BAD                    ; Raise the lexical diagnostic.

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
    RES  7,C                       ; C: digit limit plus one; bit 4 set for binary.
    LD   B,C                       ; B counts down the digits allowed.
    JR   TK_RADIX                  ; Scan the based number.

; Line ends. TK_LF and TK_CRLF consume LF or CR LF; TK_BREAK then counts the
; line and decides whether the parser sees it as a token.

TK_LF:                         ; A: LF.
    CALL SRC_TAKE                  ; Consume it.
    JR   TK_BREAK                  ; Count the line.
TK_CRLF:                       ; A: CR.
    CALL SRC_TAKE                  ; Consume it.
    CALL SRC_PEEK                  ; Only LF may follow.
    JR   C,TK_FAULT                ; A bare CR at the end of the part.
    CP   10                        ; Only LF completes CR LF.
    JR   NZ,TK_FAULT               ; A bare CR within the text.
    CALL SRC_TAKE                  ; Consume the LF.
TK_BREAK:                      ; The line end is consumed.
    CALL SRC_EOL                   ; Next line; the column returns to one.
    LD   A,(TK_NEST)               ; The bracket depth.
    OR   A                         ; Nonzero inside brackets.
    JP   NZ,TK_AGAIN               ; Then the line end is whitespace.
    LD   A,(TK_LIVE)               ; Nonzero if the line produced a token.
    OR   A                         ; Test the flag.
    JP   Z,TK_AGAIN                ; Blank or comment-only: no TK_EOL.
    XOR  A                         ; The next line starts empty.
    LD   (TK_LIVE),A               ; Clear the flag.
    LD   A,TK_EOL                  ; The token kind; TK_POS marks the line end.
    OR   A                         ; Carry clear; ZERO clear.
    RET                            ; Return the line end.

; The current part is exhausted. Before a later part, a live last line first
; yields a synthetic TK_EOL and sets bit 7 of SRC_LEFT, so that the next
; call loads the next part. After the last part, TK_EOF repeats.

TK_ATEND:                      ; SRC_PEEK reported the end of the part.
    LD   A,(TK_NEST)               ; The bracket depth.
    OR   A                         ; Nonzero if a bracket is still open.
    JR   NZ,TK_FAULT               ; A bracket is left open at the end of a part.
    LD   A,(SRC_LEFT)              ; Pending flag, ordinal and count of later parts.
    BIT  7,A                       ; Set once the boundary line end is returned.
    JR   NZ,.NEXTPART              ; Yes: move on to the next part.
    AND  SRC_CNT                   ; The number of later parts.
    OR   A                         ; Redundant: AND has already set ZERO.
    JR   Z,.LAST                   ; This is the last part.
    LD   A,(TK_LIVE)               ; Nonzero if the last line produced a token.
    OR   A                         ; Test the flag.
    JR   Z,.NEXTPART               ; No: no TK_EOL is owed.
    XOR  A                         ; The next part starts with an empty line.
    LD   (TK_LIVE),A               ; Clear the flag.
    LD   HL,SRC_LEFT               ; The multipart byte.
    SET  7,(HL)                    ; Load the next part on the next call.
    LD   A,TK_EOL                  ; A synthetic line end.
    OR   A                         ; Carry clear; ZERO clear.
    RET                            ; Return the line end.
.NEXTPART:                     ; Step to the next source part.
    LD   HL,SRC_LEFT               ; The multipart byte.
    LD   A,(HL)                    ; Pending flag, ordinal and count.
    AND  $7F                       ; Drop the pending flag.
    ADD  A,SRC_STEP-1              ; Ordinal plus one and count minus one, at once.
    LD   (HL),A                    ; Record the new part.
    LD   HL,(SRC_DESC)             ; The next part's descriptor.
    CALL SRC_LOAD                  ; Resets the cursor, the line, TK_LIVE and TK_NEST.
    JP   TK_AGAIN                  ; Scan from the part's first byte.
.LAST:                         ; No later part.
    LD   A,(TK_LIVE)               ; Nonzero if the last line produced a token.
    OR   A                         ; Test the flag.
    JR   Z,.EOF                    ; No: nothing is owed.
    XOR  A                         ; So that the next call reaches TK_EOF.
    LD   (TK_LIVE),A               ; Clear the flag.
    LD   A,TK_EOL                  ; End an unterminated last line.
    OR   A                         ; Carry clear; ZERO clear.
    RET                            ; Return the line end.
.EOF:                          ; The source is finished.
    LD   A,TK_EOF                  ; The token kind, zero.
    OR   A                         ; ZERO set marks the end; carry clear.
    RET                            ; TK_LIVE stays clear, so TK_EOF repeats.

;@ROUTINE IN BC OUT A,BC,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Scan a $ hexadecimal or % binary literal whose prefix is current. B and C
; are one more than the digit limit, 5 for hexadecimal and 17 for binary,
; and bit 4 of C selects binary. Returns TK_NUM with the value in BC.

TK_RADIX:                      ; B, C: the digit limit plus one.
    CALL SRC_TAKE                  ; Consume the prefix.
    LD   HL,0                      ; HL accumulates the value.
.LOOP:                         ; HL: value so far; B-1: digits still allowed.
    LD   D,0                       ; D: the stopping byte, zero for end of part.
    PUSH HL                        ; The source adapter clobbers HL.
    CALL SRC_PEEK                  ; Next byte, not yet consumed.
    POP  HL                        ; Recover the value.
    JR   C,.DONE                   ; The end of the part ends the literal.
    LD   D,A                       ; Keep the byte for the trailing test.
    BIT  4,C                       ; 17 has bit 4 set and 5 does not.
    JR   NZ,.BINARY                ; Binary digits are tested apart.
    CALL TK_HEX                    ; A: the digit's value, if carry.
    JR   C,.DIGIT                  ; A hexadecimal digit.
    JR   .DONE                     ; Any other byte ends the literal.
.BINARY:                       ; A: the byte; only 0 and 1 are digits.
    SUB  '0'                       ; The digit's value, if any.
    JR   C,.DONE                   ; Below '0': the literal ends.
    CP   2                         ; Only 0 and 1 are binary digits.
    JR   C,.DIGIT                  ; A binary digit.
    JR   .DONE                     ; Any other byte ends the literal.
.DIGIT:                        ; A: the digit's value.
    DEC  B                         ; One fewer digit allowed.
    JR   Z,.BAD                    ; More digits than sixteen bits hold.
    LD   E,A                       ; Keep the digit; A is needed for the merge.
    BIT  4,C                       ; Set for binary.
    JR   NZ,.SHIFT                 ; Binary shifts by one bit.
    ADD  HL,HL                     ; Hexadecimal: the first of four shifts.
    ADD  HL,HL                     ; The second shift.
    ADD  HL,HL                     ; The third shift.
.SHIFT:                        ; The fourth shift is shared with binary.
    ADD  HL,HL                     ; The low bits are now clear for the digit.
    LD   A,E                       ; The digit.
    OR   L                         ; Merged into the cleared low bits.
    LD   L,A                       ; HL: the value with the new digit.
    PUSH HL                        ; Keep the value across the adapter.
    CALL SRC_TAKE                  ; Consume the digit.
    POP  HL                        ; Recover the value.
    JR   .LOOP                     ; Scan the next byte.
.DONE:                         ; D: the stopping byte, or zero.
    LD   A,B                       ; Digits still allowed, plus one.
    CP   C                         ; B equals C if no digit was taken.
    JR   Z,.BAD                    ; Then no digit followed the prefix.
    LD   A,D                       ; The stopping byte.
    OR   A                         ; Zero for the end of the part.
    JP   Z,TK_NUMOK                ; Nothing follows, so nothing can trail.
    JP   TK_TRAIL                  ; Refuse a name byte straight after.
.BAD:                          ; A bare prefix, or too many digits.
    JP   TK_BAD                    ; Raise the lexical diagnostic.

; The single-letter string escapes \0 \n \r \t \' \" and \\, searched by
; TK_QESC. AGGR's decoder translates them separately.

TK_ESC: DB   "0nrt",$27,$22,"\\" ; Escape letters after a backslash.
TK_ECNT EQU  7                 ; Number of single-letter escapes.
