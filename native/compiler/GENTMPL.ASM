;==========================================================================
;  Code templates
;==========================================================================
;
;  Fixed byte sequences that the generators copy into the program with
;  EM_BYTES, EM_PAIR and the EM_THREE family. A template holds only Z80
;  machine code; a generator that needs an operand, such as an IX
;  displacement or an address, emits it after the template's bytes.
;
;  Templates overlap wherever one sequence is the head or tail of another,
;  so many names are offsets into a longer row (GT_NEW8, GT_STLO, GT_STHI,
;  GT_LTOHL, GT_ZEROH), and a row may run on into the next: RG_GET8 copies
;  six bytes from GT_GETA, through GT_ATOHL. Some rows begin in other
;  files: GT_ADD16 is the last two bytes of GENCALL's GT_ADDA, and the
;  short-circuit rows serve GC_IFNOT (GENCTRL) and TG_TEST (TARGET) too.
;  Reordering or editing a row therefore changes every sequence that
;  shares its bytes.
;
;  Conventions of the emitted code: the right operand of a binary operator
;  is in DE and the left in HL; a result is left in HL for GX_PUSH; a u8
;  result ends with LD H,0 so that its carrier is canonical.
;
;  Principal rows:
;    GT_GETA   byte load through an address carrier
;    GT_ATOHL  widen A to a carrier and push it
;    GT_STSP   save of the root SP and IX
;    GT_LDSP   restore of the root SP and IX
;    GT_NEW16  copy of the value routine's argument into its frame
;    GT_ARGS   the operand pops of a binary operator
;    GT_ADD8 .. GT_XOR16  operator bodies
;    GT_ANDIF, GT_ORIF  short-circuit tests

; RG_GET8's head; GENCALL's GT_PASS precedes it and GT_ATOHL follows.
GT_GETA: DB   $E1,$7E          ; POP HL; LD A,(HL): read the addressed byte.
; LD L,A; LD H,0; PUSH HL: the byte in A becomes a pushed u8 carrier.
GT_ATOHL: DB   $6F,$26,$00,$E5 ; Ends GX_LD8, RG_GET8, RG_CATCH, service results.
GT_STSP: DB   $ED,$73          ; LD (nn),SP: save the root stack pointer.
.STIX: DB   $DD,$22            ; LD (nn),IX: save the root frame pointer.
GT_LDSP: DB   $ED,$7B          ; LD SP,(nn): restore the root stack pointer.
.LDIX: DB   $DD,$2A            ; LD IX,(nn): restore the root frame pointer.
; DEC SP; DEC SP; LD (IX-1),L; LD (IX-2),H: reserve a u16 parameter and copy
; HL into it, low byte at the higher address as every local keeps it.
GT_NEW16: DB   $3B,$3B,$DD,$75,$FF,$DD,$74,$FE ; GX_ENTER's u16 parameter copy.
GT_NEW8 EQU  GT_NEW16+1        ; DEC SP; LD (IX-1),L: the u8 parameter copy.
GT_LDLO: DB   $DD,$6E          ; LD L,(IX+d): a local's low byte.
GT_LDHI: DB   $DD,$66          ; LD H,(IX+d): a local's high byte.
GT_STLO EQU  GT_NEW16+2        ; LD (IX+d),L: store a local's low byte.
GT_STHI EQU  GT_NEW16+5        ; LD (IX+d),H: store a local's high byte.
GT_LTOHL EQU  GT_ATOHL+1       ; LD H,0; PUSH HL: push L as a u8 carrier.
GT_ZEROH EQU  GT_ATOHL+1       ; LD H,0, as a pair: GC_LOAD's u8 counter.
GT_ARGS: DB   $D1,$E1          ; POP DE; POP HL: right into DE, left into HL.
    DB   $E5,$D5                   ; PUSH HL; PUSH DE: RG_COPY and OS_ARG re-push them.
; LD A,L; ADD A,E; LD L,A; LD H,0: the u8 sum modulo 256.
GT_ADD8: DB   $7D,$83,$6F,$26,$00 ; GX_ADD8's body.
GT_ADD16 EQU  GT_ADDA+3        ; ADD HL,DE: GX_ADD16's body, inside GT_ADDA.
; LD A,L; SUB E; LD L,A; LD H,0: the u8 difference modulo 256.
GT_SUB8: DB   $7D,$93,$6F,$26,$00 ; GX_SUB8's body.
GT_SUB16: DB   $AF,$ED,$52     ; XOR A; SBC HL,DE: carry cleared for SBC.
; POP HL; XOR A; SUB L; LD L,A; LD H,0: 0-L modulo 256.
GT_NEG8: DB   $E1,$AF,$95,$6F,$26,$00 ; GX_NEG8's body, its pop included.
; POP HL; XOR A; SUB L; LD L,A; LD A,0; SBC A,H; LD H,A: 0-HL, the borrow
; from the low byte carried into the high (LD A,0 keeps the carry).
GT_NEG16: DB   $E1,$AF,$95,$6F,$3E,$00,$9C,$67 ; GX_NEG16's body.
; POP HL; LD A,L; CPL; LD L,A; LD H,0: the u8 complement.
GT_NOT8: DB   $E1,$7D,$2F,$6F,$26,$00 ; GX_NOT8's body, its pop included.
; POP HL; LD A,L; CPL; LD L,A; LD A,H; CPL; LD H,A: the u16 complement.
GT_NOT16: DB   $E1,$7D,$2F,$6F,$7C,$2F,$67 ; GX_NOT16's body.
; POP HL; LD A,L; XOR 1; LD L,A; LD H,0: boolean NOT of a 0/1 carrier.
GT_FLIP: DB   $E1,$7D,$EE,$01,$6F,$26,$00 ; GX_FLIP's body.
; LD A,L; AND E; LD L,A; LD H,0: the u8 AND.
GT_AND8: DB   $7D,$A3,$6F,$26,$00 ; GX_AND8's body.
; LD A,L; AND E; LD L,A; LD A,H; AND D; LD H,A: the u16 AND, byte by byte.
GT_AND16: DB   $7D,$A3,$6F,$7C,$A2,$67 ; GX_AND16's body.
; LD A,L; OR E; LD L,A; LD H,0: the u8 OR.
GT_OR8: DB   $7D,$B3,$6F,$26,$00 ; GX_OR8's body.
; LD A,L; OR E; LD L,A; LD A,H; OR D; LD H,A: the u16 OR, byte by byte.
GT_OR16: DB   $7D,$B3,$6F,$7C,$B2,$67 ; GX_OR16's body.
; LD A,L; XOR E; LD L,A; LD H,0: the u8 exclusive OR.
GT_XOR8: DB   $7D,$AB,$6F,$26,$00 ; GX_XOR8's body.
; LD A,L; XOR E; LD L,A; LD A,H; XOR D; LD H,A: the u16 exclusive OR.
GT_XOR16: DB   $7D,$AB,$6F,$7C,$AA,$67 ; GX_XOR16's body.
; POP HL; LD A,L; OR A; JR NZ/Z,+3; PUSH HL. The +3 skips PUSH HL and the
; two-byte JR to the join that GX_SHORT emits after the row. GC_IFNOT takes
; the first three bytes as its test; TG_TEST takes JR NZ,+3 to skip a JP.
GT_ANDIF: DB   $E1,$7D,$B7,$20,$03,$E5 ; AND: a true left operand falls through.
GT_ORIF: DB   $E1,$7D,$B7,$28,$03,$E5 ; OR: a false left operand falls through.
