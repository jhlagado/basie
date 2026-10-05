; The CP/M shell (toolchain §2, §5): read the source parts named on the
; command line into memory, compile them, and report a diagnostic. Options
; in brackets are accepted and not yet read. A diagnostic is printed as
; NAME.BSI LINE:COLUMN Error N, with the forked compiler's number, until the
; message file replaces it (step 66).

BdosEntry       .equ $0005
CommandTail     .equ $0080
BdosConsoleOut  .equ 2
BdosOpenFile    .equ 15
BdosDeleteFile  .equ 19
BdosReadSequential .equ 20
BdosSetDma      .equ 26
FcbSize         .equ 36
PartNameSize    .equ 11

; The shell's workspace, after the compiler's and below the source.
BasieSourceLimit .equ BasieWorkBase
BasieLoadCursor  .equ BasieSourceLimit+2
BasiePartStart   .equ BasieLoadCursor+2
BasiePartCount   .equ BasiePartStart+2
BasieFcb         .equ BasiePartCount+1
BasieParts       .equ BasieFcb+FcbSize
BasiePartNames   .equ BasieParts+SourcePartCapacity*5
BasieWorkEnd     .equ BasiePartNames+SourcePartCapacity*PartNameSize

BasieStart:
            LD   HL,(BdosEntry+1)
            LD   SP,HL
            LD   DE,-BasieStackRoom
            ADD  HL,DE
            LD   (BasieSourceLimit),HL
            LD   HL,SourceBase
            LD   (BasieLoadCursor),HL
            XOR  A
            LD   (BasiePartCount),A
            LD   HL,CommandTail           ; zero-terminate the tail
            LD   E,(HL)
            LD   D,A
            INC  HL
            PUSH HL
            ADD  HL,DE
            LD   (HL),D
            POP  HL
BasieNextPart:
            CALL BasieSkipSpaces
            OR   A
            JR   Z,BasieTailDone
            CP   "["
            JR   Z,BasieTailDone
            CALL BasieLoadPart
            CALL BasieSkipSpaces
            INC  HL
            CP   ","
            JR   Z,BasieNextPart
            OR   A
            JR   Z,BasieTailDone
            CP   "["
            JP   NZ,BasieUsage
BasieTailDone:
            LD   A,(BasiePartCount)
            OR   A
            JP   Z,BasieUsage
            LD   HL,BasieParts
            LD   IX,BasieTargetDescriptor
            CALL CompileTargetAggregateCallParts
            JP   C,BasieReportDiagnostic
            JP   0

; A = the byte at HL, after skipping spaces.
.routine in HL out A,HL
BasieSkipSpaces:
            LD   A,(HL)
            CP   " "
            RET  NZ
            INC  HL
            JR   BasieSkipSpaces

; Parse [d:]name[.type] at HL into the FCB, load the part after the parts
; already loaded, and append its descriptor. HL is left after the name.
.routine in HL out HL clobbers A,BC,DE,IX,IY
BasieLoadPart:
            LD   A,(BasiePartCount)
            CP   SourcePartCapacity
            JP   NC,BasieTooManyParts
            CALL BasieClearFcb
            INC  HL
            LD   A,(HL)
            DEC  HL
            CP   ":"
            JR   NZ,BasieParseName
            LD   A,(HL)
            SUB  "A"-1                    ; A: is 1
            JP   Z,BasieUsage
            CP   17
            JP   NC,BasieUsage
            LD   (BasieFcb),A
            INC  HL
            INC  HL
BasieParseName:
            LD   DE,BasieFcb+1
            LD   B,8
            CALL BasieParseField
            LD   A,(BasieFcb+1)
            CP   " "
            JP   Z,BasieUsage
            LD   A,(HL)
            CP   "."
            JR   NZ,BasieDefaultType
            INC  HL
            LD   DE,BasieFcb+9
            LD   B,3
            CALL BasieParseField
            JR   BasieOpenPart
BasieDefaultType:
            PUSH HL
            LD   HL,BasieSourceType
            LD   DE,BasieFcb+9
            LD   BC,3
            LDIR
            POP  HL
BasieOpenPart:
            LD   A,(HL)                   ; the name ends the part
            OR   A
            JR   Z,BasieNameEnded
            CP   " "
            JR   Z,BasieNameEnded
            CP   ","
            JR   Z,BasieNameEnded
            CP   "["
            JP   NZ,BasieUsage
BasieNameEnded:
            PUSH HL
            LD   A,(BasiePartCount)       ; keep the name for diagnostics
            CALL BasiePartName
            EX   DE,HL
            LD   HL,BasieFcb+1
            LD   BC,PartNameSize
            LDIR
            LD   DE,BasieFcb
            LD   C,BdosOpenFile
            CALL BdosEntry
            INC  A
            JP   Z,BasieNotFound
            LD   HL,(BasieLoadCursor)
            LD   (BasiePartStart),HL
BasieReadRecord:
            LD   HL,(BasieLoadCursor)     ; room for another record?
            LD   DE,128
            ADD  HL,DE
            EX   DE,HL
            LD   HL,(BasieSourceLimit)
            OR   A
            SBC  HL,DE
            JP   C,BasieTooLarge
            LD   DE,(BasieLoadCursor)
            LD   C,BdosSetDma
            CALL BdosEntry
            LD   DE,BasieFcb
            LD   C,BdosReadSequential
            CALL BdosEntry
            OR   A
            JR   NZ,BasiePartLoaded
            LD   HL,(BasieLoadCursor)
            LD   DE,128
            ADD  HL,DE
            LD   (BasieLoadCursor),HL
            JR   BasieReadRecord
BasiePartLoaded:
            LD   HL,(BasiePartStart)      ; the part ends at its first $1A
            LD   DE,(BasieLoadCursor)
BasieFindEnd:
            LD   A,L
            CP   E
            JR   NZ,BasieFindEndByte
            LD   A,H
            CP   D
            JR   Z,BasieEndFound
BasieFindEndByte:
            LD   A,(HL)
            CP   $1A
            JR   Z,BasieEndFound
            INC  HL
            JR   BasieFindEnd
BasieEndFound:
            LD   (BasieLoadCursor),HL
            EX   DE,HL
            LD   A,(BasiePartCount)       ; the descriptor: id, start, end
            LD   L,A
            INC  A
            LD   (BasiePartCount),A
            LD   H,0
            LD   B,H
            LD   C,L
            ADD  HL,HL
            ADD  HL,HL
            ADD  HL,BC
            LD   BC,BasieParts
            ADD  HL,BC
            LD   (HL),A
            INC  HL
            LD   BC,(BasiePartStart)
            LD   (HL),C
            INC  HL
            LD   (HL),B
            INC  HL
            LD   (HL),E
            INC  HL
            LD   (HL),D
            POP  HL
            RET

; Set the FCB to the current drive, a blank name and zeros. Preserves HL.
.routine clobbers A,B,DE
BasieClearFcb:
            LD   DE,BasieFcb
            XOR  A
            LD   (DE),A
            INC  DE
            LD   B,PartNameSize
BasieClearName:
            LD   A," "
            LD   (DE),A
            INC  DE
            DJNZ BasieClearName
            LD   B,FcbSize-PartNameSize-1
            XOR  A
BasieClearRest:
            LD   (DE),A
            INC  DE
            DJNZ BasieClearRest
            RET

; Copy name characters from HL to DE, at most B of them.
.routine in B,DE,HL out HL clobbers A,B,DE
BasieParseField:
            LD   A,(HL)
            CALL BasieNameChar
            RET  C
            INC  B
            DEC  B
            JP   Z,BasieUsage
            LD   (DE),A
            INC  DE
            INC  HL
            DEC  B
            JR   BasieParseField

; Carry unless A may appear in a CP/M name (services §4.1).
.routine in A out carry
BasieNameChar:
            CP   "A"
            JR   C,BasieNameDigit
            CP   "Z"+1
            CCF
            RET  NC
BasieNameDigit:
            CP   "0"
            JR   C,BasieNamePunctuation
            CP   "9"+1
            CCF
            RET  NC
BasieNamePunctuation:
            PUSH HL
            PUSH BC
            LD   HL,BasieNameSet
            LD   BC,16
            CPIR
            POP  BC
            POP  HL
            SCF
            RET  NZ
            CCF
            RET

; HL = the saved name of part A (0-based).
.routine in A out HL clobbers DE
BasiePartName:
            LD   L,A
            LD   H,0
            LD   D,H
            LD   E,L
            ADD  HL,HL
            ADD  HL,HL
            ADD  HL,DE
            ADD  HL,HL
            ADD  HL,DE
            LD   DE,BasiePartNames
            ADD  HL,DE
            RET

; ---- diagnostics and failure ------------------------------------------------

BasieReportDiagnostic:
            LD   A,(DiagnosticPartId)
            OR   A
            JR   Z,BasieReportNumber
            DEC  A
            CALL BasiePartName
            CALL BasiePrintName
            LD   A," "
            CALL BasiePutChar
            LD   HL,(DiagnosticLine)
            CALL BasiePrintDecimal
            LD   A,":"
            CALL BasiePutChar
            LD   HL,(DiagnosticColumn)
            CALL BasiePrintDecimal
            LD   A," "
            CALL BasiePutChar
BasieReportNumber:
            LD   HL,BasieErrorText
            CALL BasiePrintText
            LD   A,(DiagnosticCode)
            LD   L,A
            LD   H,0
            CALL BasiePrintDecimal
            JR   BasieFailLine

BasieNotFound:
            LD   A,(BasiePartCount)
            CALL BasiePartName
            CALL BasiePrintName
            LD   HL,BasieNotFoundText
            JR   BasieFailText
BasieTooManyParts:
            LD   HL,BasieTooManyText
            JR   BasieFailText
BasieTooLarge:
            LD   HL,BasieTooLargeText
            JR   BasieFailText
BasieUsage:
            LD   HL,BasieUsageText
BasieFailText:
            CALL BasiePrintText
BasieFailLine:
            LD   A,13
            CALL BasiePutChar
            LD   A,10
            CALL BasiePutChar
; A failed build deletes A:$$$.SUB, stopping a SUBMIT job (toolchain §5.4).
            CALL BasieClearFcb
            LD   HL,BasieSubmitName
            LD   DE,BasieFcb
            LD   BC,PartNameSize+1
            LDIR
            LD   DE,BasieFcb
            LD   C,BdosDeleteFile
            CALL BdosEntry
            JP   0

; ---- console ----------------------------------------------------------------

; Print the 11-character name at HL as NAME.TYP, without padding.
.routine in HL clobbers A,B,HL
BasiePrintName:
            LD   B,8
            CALL BasiePrintField
            LD   A,"."
            CALL BasiePutChar
            LD   B,3
BasiePrintField:
            LD   A,(HL)
            INC  HL
            CP   " "
            CALL NZ,BasiePutChar
            DJNZ BasiePrintField
            RET

; Print the zero-terminated text at HL.
.routine in HL clobbers A,HL
BasiePrintText:
            LD   A,(HL)
            OR   A
            RET  Z
            CALL BasiePutChar
            INC  HL
            JR   BasiePrintText

; Print HL in decimal, without leading zeros.
.routine in HL clobbers A,B,DE,HL
BasiePrintDecimal:
            LD   B,0                      ; nonzero once a digit is printed
            LD   DE,10000
            CALL BasieDigit
            LD   DE,1000
            CALL BasieDigit
            LD   DE,100
            CALL BasieDigit
            LD   DE,10
            CALL BasieDigit
            LD   A,L
            ADD  A,"0"
            JR   BasiePutChar

; Print the digit of HL for the power DE, unless it is a leading zero, and
; leave the remainder in HL.
.routine in B,DE,HL out B,HL clobbers A
BasieDigit:
            LD   A,"0"-1
BasieDigitCount:
            INC  A
            OR   A
            SBC  HL,DE
            JR   NC,BasieDigitCount
            ADD  HL,DE
            CP   "0"
            JR   NZ,BasieDigitPrint
            INC  B
            DEC  B
            RET  Z
BasieDigitPrint:
            LD   B,1
; Print A. Preserves every register but F.
.routine in A
BasiePutChar:
            PUSH AF
            PUSH BC
            PUSH DE
            PUSH HL
            LD   E,A
            LD   C,BdosConsoleOut
            CALL BdosEntry
            POP  HL
            POP  DE
            POP  BC
            POP  AF
            RET

; ---- output ----------------------------------------------------------------

; The forked compiler's output sinks. Placed output is discarded until blob
; output replaces it (native compiler plan, 65.4): every call succeeds.
.routine out carry
TargetSinkBegin:
TargetSinkImageByte:
TargetSinkPatchByte:
TargetSinkPatchWord:
TargetSinkRuntimeImage:
TargetSinkRuntimeInitialImage:
TargetSinkMapFlat:
TargetSinkMapBanked:
TargetSinkCommit:
TargetSinkAbort:
            OR   A
            RET

; ---- data -------------------------------------------------------------------

BasieTargetDescriptor:                    ; the forked flat proof target
            .dw NucleusRuntimeIdentity
            .dw $8000,$1000
            .dw $4000,$1000
            .db 1
            .db 1,0
            .dw BasiePartBanks
BasiePartBanks:
            .db 0,0,0,0,0,0,0,0
BasieNameSet:
            .db "!#$%&'()-@^_`{}~"
BasieSourceType:
            .db "BSI"
BasieSubmitName:
            .db 1,"$$$     SUB"
BasieErrorText:
            .db "Error ",0
BasieNotFoundText:
            .db " not found",0
BasieTooManyText:
            .db "More than 8 source parts",0
BasieTooLargeText:
            .db "Source too large",0
BasieUsageText:
            .db "Usage: BASIE PART[,PART...] [OPTIONS]",0

