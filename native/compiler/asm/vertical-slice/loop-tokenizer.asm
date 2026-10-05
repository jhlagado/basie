; Tokenizer subset for the scalar-local, counted-loop, and array proofs.

.routine out carry,zero clobbers sign,parity,halfCarry,A,DE,HL
TokenRecordStart:
            LD   HL,(SourceOffset)
            LD   (TokenStartOffset),HL
            LD   HL,(SourceLine)
            LD   (TokenStartLine),HL
            LD   HL,(SourceColumn)
            LD   (TokenStartColumn),HL
            LD   HL,(SourceCursor)
            LD   (TokenLexemePointer),HL
            RET

.routine in A out A,carry,zero clobbers sign,parity,halfCarry,D
TokenFinish:
            LD   D,A
            LD   A,1
            LD   (SourceLineHasToken),A
            LD   A,D
            OR   A
            RET

.routine out carry,zero clobbers sign,parity,halfCarry,A,DE,HL
TokenLexicalFailure:
            CALL SetDiagInline
            .db  DiagnosticLexical

.routine in A out A,carry clobbers zero,sign,parity,halfCarry,C
TokenIsLetter:
            LD   C,A
            OR   $20
            SUB  "a"
            CP   26
            LD   A,C
            RET

.routine in A out A,carry clobbers zero,sign,parity,halfCarry,C
TokenIsNameByte:
            CALL TokenIsLetter
            RET  C
            CP   "0"
            JR   C,TokenIsNameByteUnderscore
            CP   "9"+1
            JR   C,TokenIsNameByteYes
TokenIsNameByteUnderscore:
            CP   "_"
            JR   Z,TokenIsNameByteYes
            OR   A
            RET
TokenIsNameByteYes:
            SCF
            RET

.routine in B,HL out A,carry,zero clobbers sign,parity,halfCarry,B,DE,HL
TokenNameEquals:
            LD   A,(TokenLength)
            CP   B
            JR   NZ,TokenNameEqualsNo
            LD   DE,(TokenLexemePointer)
TokenNameEqualsLoop:
            LD   A,(DE)
            CP   (HL)
            JR   NZ,TokenNameEqualsNo
            INC  DE
            INC  HL
            DJNZ TokenNameEqualsLoop
            SCF
            RET
TokenNameEqualsNo:
            OR   A
            RET

; Compare the current NAME token with the retained name record at HL. The
; record begins with a pointer word followed by a one-byte length.
.routine in BC,HL out A,carry,zero clobbers sign,parity,halfCarry,DE
TokenNameRecordEquals:
            PUSH BC
            PUSH HL
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            INC  HL
            LD   A,(HL)
            LD   B,A
            EX   DE,HL
            CALL TokenNameEquals
            POP  HL
            POP  BC
            RET

; Store the current NAME token's pointer and length in the three-byte record
; at HL. HL returns at the length byte, matching the former inline sequences.
.routine in HL out A,BC,HL clobbers carry,zero,sign,parity,halfCarry
TokenRetainNameAtHL:
            LD   BC,(TokenLexemePointer)
            LD   (HL),C
            INC  HL
            LD   (HL),B
            INC  HL
            LD   A,(TokenLength)
            LD   (HL),A
            RET

.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
TokenScanName:
            LD   B,0
TokenScanNameLoop:
            CALL SourcePeek
            JR   C,TokenScanNameDone
            CALL TokenIsNameByte
            JR   NC,TokenScanNameDone
            CALL SourceTake
            INC  B
            JR   Z,TokenLexicalFailure
            JR   TokenScanNameLoop
TokenScanNameDone:
            LD   A,B
            LD   (TokenLength),A
            LD   HL,KeywordTable
            LD   C,KeywordCount
TokenScanKeyword:
            LD   B,(HL)
            INC  HL
            LD   A,(TokenLength)
            CP   B
            JR   NZ,TokenScanKeywordSkip
            LD   DE,(TokenLexemePointer)
TokenScanKeywordByte:
            LD   A,(DE)
            CP   (HL)
            JR   NZ,TokenScanKeywordSkip
            INC  DE
            INC  HL
            DJNZ TokenScanKeywordByte
            LD   A,(HL)
            JP   TokenFinish
TokenScanKeywordSkip:
            LD   E,B
            LD   D,0
            ADD  HL,DE
            INC  HL
            DEC  C
            JR   NZ,TokenScanKeyword
            LD   A,TokenName
            JP   TokenFinish

; Scan one or more decimal digits and reject a value above 65535. BC carries
; the exact unsigned literal payload to the predictive parser.
.routine out A,carry,zero clobbers sign,parity,halfCarry,B,C,D,DE,HL
TokenScanNumber:
            LD   HL,0
TokenScanNumberLoop:
            PUSH HL
            CALL SourcePeek
            POP  HL
            JR   C,TokenScanNumberEof
            CP   "0"
            JR   C,TokenScanNumberDone
            CP   "9"+1
            JR   NC,TokenScanNumberDone
            SUB  "0"
            LD   C,A
            LD   A,H
            CP   $19
            JR   C,TokenScanNumberAccumulate
            JR   NZ,TokenScanCharacterFailure
            LD   A,L
            CP   $99
            JR   C,TokenScanNumberAccumulate
            JR   NZ,TokenScanCharacterFailure
            LD   A,C
            CP   6
            JR   NC,TokenScanCharacterFailure
TokenScanNumberAccumulate:
            LD   D,0
            LD   E,C
            ADD  HL,HL
            LD   B,H
            LD   C,L
            ADD  HL,HL
            ADD  HL,HL
            ADD  HL,BC
            ADD  HL,DE
            PUSH HL
            CALL SourceTake
            POP  HL
            JR   TokenScanNumberLoop
TokenScanNumberDone:
            ; An integer token cannot be followed immediately by a name byte.
            ; Reject forms such as 0x2a and 12u8 as one malformed number rather
            ; than exposing a misleading number/name token pair to the parser.
            CALL TokenIsNameByte
            JP   C,TokenLexicalFailure
TokenScanNumberEof:
            LD   B,H
            LD   C,L
            LD   A,TokenNumber
            JP   TokenFinish

.routine out A,carry,zero clobbers sign,parity,halfCarry,BC,DE,HL
TokenScanCharacter:
            CALL SourceTake
            JR   C,TokenScanCharacterFailure
            CALL SourceTake
            JR   C,TokenScanCharacterFailure
            CP   $20
            JR   C,TokenScanCharacterFailure
            CP   $7F
            JR   NC,TokenScanCharacterFailure
            CP   "'"
            JR   Z,TokenScanCharacterFailure
            CP   "\\"
            JR   Z,TokenScanCharacterFailure
            LD   C,A
            CALL SourceTake
            JR   C,TokenScanCharacterFailure
            CP   "'"
            JR   NZ,TokenScanCharacterFailure
            LD   A,TokenCharacter
            JP   TokenFinish
TokenScanCharacterFailure:
            JP   TokenLexicalFailure

; Return carry and the decoded nibble for one hexadecimal digit. Tokenization
; needs only the validity flag; the static-image decoder reuses the value.
.routine in A out A,carry,zero clobbers sign,parity,halfCarry
TokenIsHexDigit:
            CP   "0"
            JR   C,TokenHexNo
            CP   "9"+1
            JR   C,TokenHexDecimal
            OR   $20
            SUB  "a"
            CP   6
            JR   NC,TokenHexNo
            ADD  A,10
            SCF
            RET
TokenHexDecimal:
            SUB  "0"
            SCF
            RET
TokenHexNo:
            OR   A
            RET

; Scan and validate a bounded-string literal. BC returns the decoded byte
; length. TokenLexemePointer continues to identify the opening quote so the
; declaration parser can decode the bytes directly into the static image.
.routine out A,BC,carry,zero clobbers sign,parity,halfCarry,D,DE,HL
TokenScanString:
            CALL SourceTake
            JR   C,TokenScanCharacterFailure
            LD   C,0
TokenScanStringNext:
            CALL SourceTake
            JR   C,TokenScanCharacterFailure
            CP   '"'
            JR   Z,TokenScanStringDone
            CP   $20
            JR   C,TokenScanCharacterFailure
            CP   $7F
            JR   NC,TokenScanCharacterFailure
            CP   "\\"
            JR   Z,TokenScanStringEscape
TokenScanStringCount:
            INC  C
            JR   Z,TokenScanCharacterFailure
            JR   TokenScanStringNext
TokenScanStringEscape:
            CALL SourceTake
            JR   C,TokenScanCharacterFailure
            CP   "x"
            JR   Z,TokenScanStringHex
            LD   HL,StringEscapeTable
            LD   B,StringEscapeCount
TokenScanStringEscapeLoop:
            CP   (HL)
            JR   Z,TokenScanStringCount
            INC  HL
            DJNZ TokenScanStringEscapeLoop
            JR   TokenScanCharacterFailure
TokenScanStringHex:
            CALL SourceTake
            JR   C,TokenScanCharacterFailure
            CALL TokenIsHexDigit
            JR   NC,TokenScanCharacterFailure
            CALL SourceTake
            JR   C,TokenScanCharacterFailure
            CALL TokenIsHexDigit
            JR   NC,TokenScanCharacterFailure
            JR   TokenScanStringCount
TokenScanStringDone:
            LD   B,0
            LD   A,C
            LD   (TokenLength),A
            LD   A,TokenStringLiteral
            JP   TokenFinish

.routine out carry,zero clobbers sign,parity,halfCarry,A,DE,HL
TokenSkipComment:
TokenSkipCommentLoop:
            CALL SourcePeek
            RET  C
            CP   10
            RET  Z
            CP   13
            RET  Z
            CALL SourceTake
            JR   TokenSkipCommentLoop

.routine out A,BC,carry,zero clobbers sign,parity,halfCarry,D,DE,HL
TokenizerNext:
TokenizerNextLoop:
            CALL TokenRecordStart
            CALL SourcePeek
            JP   C,TokenizerAtEof

            CP   " "
            JR   Z,TokenizerSkipByte
            CP   9
            JR   Z,TokenizerSkipByte
            CP   10
            JP   Z,TokenizerLf
            CP   13
            JP   Z,TokenizerCrLf
            CP   "/"
            JR   Z,TokenizerSlash
            CP   "("
            JP   Z,TokenizerLeftParen
            CP   ")"
            JP   Z,TokenizerRightParen
            CP   "["
            JP   Z,TokenizerLeftBracket
            CP   "]"
            JP   Z,TokenizerRightBracket
            CP   "<"
            JR   Z,TokenizerLess
            CP   ">"
            JR   Z,TokenizerGreater
            LD   HL,PunctuationTable
            LD   B,PunctuationCount
TokenizerTryPunctuation:
            CP   (HL)
            INC  HL
            JP   Z,TokenizerPunctuation
            INC  HL
            DJNZ TokenizerTryPunctuation
            CP   "'"
            JP   Z,TokenScanCharacter
            CP   '"'
            JP   Z,TokenScanString
            CP   "0"
            JR   C,TokenizerTryName
            CP   "9"+1
            JP   C,TokenScanNumber
TokenizerTryName:
            CALL TokenIsLetter
            JP   C,TokenScanName
            JR   TokenizerLexicalFailure

TokenizerSkipByte:
            CALL SourceTake
            JR   TokenizerNextLoop

TokenizerSlash:
            CALL SourceTake
            CALL SourcePeek
            JR   C,TokenizerSlashToken
            CP   "/"
            JR   NZ,TokenizerSlashToken
            CALL SourceTake
            CALL TokenSkipComment
            JR   TokenizerNextLoop
TokenizerSlashToken:
            LD   A,TokenSlash
            JP   TokenFinish

TokenizerLess:
            CALL SourceTake
            CALL SourcePeek
            JR   C,TokenizerLessToken
            CP   "="
            JR   Z,TokenizerLessEqual
            CP   ">"
            JR   Z,TokenizerNotEqual
TokenizerLessToken:
            LD   A,TokenLess
            JP   TokenFinish
TokenizerLessEqual:
            LD   C,TokenLessEqual
            JR   TokenizerSimpleToken
TokenizerNotEqual:
            LD   C,TokenNotEqual
            JR   TokenizerSimpleToken

TokenizerGreater:
            CALL SourceTake
            CALL SourcePeek
            JR   C,TokenizerGreaterToken
            CP   "="
            JR   Z,TokenizerGreaterEqual
TokenizerGreaterToken:
            LD   A,TokenGreater
            JP   TokenFinish
TokenizerGreaterEqual:
            LD   C,TokenGreaterEqual
            JR   TokenizerSimpleToken

TokenizerLeftParen:
            LD   C,TokenLeftParen
            JR   TokenizerLeftDelimiter

TokenizerRightParen:
            LD   C,TokenRightParen
            JR   TokenizerRightDelimiter

TokenizerLeftBracket:
            LD   C,TokenLeftBracket
TokenizerLeftDelimiter:
            CALL SourceTake
            LD   A,(SourceDelimiterDepth)
            INC  A
            JR   Z,TokenizerLexicalFailure
            LD   (SourceDelimiterDepth),A
            LD   A,C
            JP   TokenFinish

TokenizerRightBracket:
            LD   C,TokenRightBracket
TokenizerRightDelimiter:
            LD   A,(SourceDelimiterDepth)
            OR   A
            JR   Z,TokenizerLexicalFailure
            DEC  A
            LD   (SourceDelimiterDepth),A
            CALL SourceTake
            LD   A,C
            JP   TokenFinish

TokenizerLexicalFailure:
            JP   TokenLexicalFailure

TokenizerPunctuation:
            LD   C,(HL)
            BIT  7,C
            JR   NZ,TokenizerBasedNumber
TokenizerSimpleToken:
            CALL SourceTake
            LD   A,C
            JP   TokenFinish
TokenizerBasedNumber:
            RES  7,C
            LD   B,C
            JR   TokenScanBasedNumber

TokenizerLf:
            CALL SourceTake
            JR   TokenizerFinishLine
TokenizerCrLf:
            CALL SourceTake
            CALL SourcePeek
            JR   C,TokenizerLexicalFailure
            CP   10
            JR   NZ,TokenizerLexicalFailure
            CALL SourceTake
TokenizerFinishLine:
            CALL SourceFinishLine
            LD   A,(SourceDelimiterDepth)
            OR   A
            JP   NZ,TokenizerNextLoop
            LD   A,(SourceLineHasToken)
            OR   A
            JP   Z,TokenizerNextLoop
            XOR  A
            LD   (SourceLineHasToken),A
            LD   A,TokenNewline
            OR   A
            RET

TokenizerAtEof:
            LD   A,(SourceDelimiterDepth)
            OR   A
            JR   NZ,TokenizerLexicalFailure
.if AggregateCallSlices
            LD   A,(SourcePartsRemaining)
            BIT  7,A
            JR   NZ,TokenizerAdvancePart
.if TargetStreamingOutput
            AND  SourcePartsRemainingMask
.endif
            OR   A
            JR   Z,TokenizerAtCompilationEof
            LD   A,(SourceLineHasToken)
            OR   A
            JR   Z,TokenizerAdvancePart
            XOR  A
            LD   (SourceLineHasToken),A
            LD   HL,SourcePartsRemaining
            SET  7,(HL)
            LD   A,TokenNewline
            OR   A
            RET
TokenizerAdvancePart:
            LD   HL,SourcePartsRemaining
.if TargetStreamingOutput
            LD   A,(HL)
            AND  $7F
            ADD  A,SourcePartOrdinalStep-1
            LD   (HL),A
.else
            RES  7,(HL)
            DEC  (HL)
.endif
            LD   HL,(SourcePartDescriptorCursor)
            CALL SourceLoadPart
            JP   TokenizerNextLoop
TokenizerAtCompilationEof:
.endif
            LD   A,(SourceLineHasToken)
            OR   A
            JR   Z,TokenizerEmitEof
            XOR  A
            LD   (SourceLineHasToken),A
            LD   A,TokenNewline
            OR   A
            RET
TokenizerEmitEof:
            LD   A,TokenEof
            OR   A
            RET

.routine in BC out A,BC,carry,zero clobbers sign,parity,halfCarry,D,DE,HL
TokenScanBasedNumber:
            CALL SourceTake
            LD   HL,0
TokenScanBasedLoop:
            LD   D,0
            PUSH HL
            CALL SourcePeek
            POP  HL
            JR   C,TokenScanBasedDone
            LD   D,A
            BIT  4,C
            JR   NZ,TokenScanBinaryDigit
            CALL TokenIsHexDigit
            JR   C,TokenScanBasedDigit
            JR   TokenScanBasedDone
TokenScanBinaryDigit:
            SUB  "0"
            JR   C,TokenScanBasedDone
            CP   2
            JR   C,TokenScanBasedDigit
            JR   TokenScanBasedDone
TokenScanBasedDigit:
            DEC  B
            JR   Z,TokenNumberFailure
            LD   E,A
            BIT  4,C
            JR   NZ,TokenScanBasedShift
            ADD  HL,HL
            ADD  HL,HL
            ADD  HL,HL
TokenScanBasedShift:
            ADD  HL,HL
            LD   A,E
            OR   L
            LD   L,A
            PUSH HL
            CALL SourceTake
            POP  HL
            JR   TokenScanBasedLoop
TokenScanBasedDone:
            LD   A,B
            CP   C
            JR   Z,TokenNumberFailure
            LD   A,D
            OR   A
            JP   Z,TokenScanNumberEof
            JP   TokenScanNumberDone
TokenNumberFailure:
            JP   TokenLexicalFailure

StringEscapeTable:      .db "0nrt",$27,$22,"\\"
StringEscapeCount       .equ 7
