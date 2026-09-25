    ; Abel Doyle
    ; RCET3373
    ; Lab5-4ISR
    ; https://github.com/abeldoyl/Lab-05-ISRs/tree/main/Lab5-4ISR.X
    
; PIC16F883 Configuration Bit Settings

; Assembly source line config statements

; CONFIG1
  CONFIG  FOSC = XT             ; Oscillator Selection bits (XT oscillator: Crystal/resonator on RA6/OSC2/CLKOUT and RA7/OSC1/CLKIN)
  CONFIG  WDTE = OFF            ; Watchdog Timer Enable bit (WDT disabled and can be enabled by SWDTEN bit of the WDTCON register)
  CONFIG  PWRTE = OFF           ; Power-up Timer Enable bit (PWRT disabled)
  CONFIG  MCLRE = ON            ; RE3/MCLR pin function select bit (RE3/MCLR pin function is MCLR)
  CONFIG  CP = OFF              ; Code Protection bit (Program memory code protection is disabled)
  CONFIG  CPD = OFF             ; Data Code Protection bit (Data memory code protection is disabled)
  CONFIG  BOREN = OFF           ; Brown Out Reset Selection bits (BOR disabled)
  CONFIG  IESO = OFF            ; Internal External Switchover bit (Internal/External Switchover mode is disabled)
  CONFIG  FCMEN = OFF           ; Fail-Safe Clock Monitor Enabled bit (Fail-Safe Clock Monitor is disabled)
  CONFIG  LVP = OFF             ; Low Voltage Programming Enable bit (RB3 pin has digital I/O, HV on MCLR must be used for programming)

; CONFIG2
  CONFIG  BOR4V = BOR40V        ; Brown-out Reset Selection bit (Brown-out Reset set to 4.0V)
  CONFIG  WRT = OFF             ; Flash Program Memory Self Write Enable bits (Write protection off)

; config statements should precede project file includes.
#include <xc.inc>
 outCount EQU 0x20
 midCount EQU 0x21
 inCount EQU 0x22
  
 D_ONE   EQU 0x31
 D_SIX   EQU 0x36
 D_SEVEN EQU 0x37
 
; ---- common RAM (0x70-0x7F), reachable from any bank without BANKSEL ----
 W_TEMP1      EQU 0x70   ; saved W      - context interrupted directly from Main
 STATUS_TEMP1 EQU 0x71   ; saved STATUS - "
 SIXACTIVE    EQU 0x72   ; bit0: 1 while 6 is running (nested entry test)
 W_TEMP2      EQU 0x73   ; saved W      - 7's context when nested inside 6
 STATUS_TEMP2 EQU 0x74   ; saved STATUS - "
 
 DCNT1        EQU 0x75   ; delay: inner loop counter
 DCNT2        EQU 0x76   ; delay: middle loop counter
 D2SCNT       EQU 0x77   ; delay: outer (2-second) loop counter
 DCNT1_SAVE   EQU 0x78   ; snapshot of DCNT1 while a 7 nests inside 6
 DCNT2_SAVE   EQU 0x79   ; snapshot of DCNT2   "
 D2SCNT_SAVE  EQU 0x7A   ; snapshot of D2SCNT  "
 
PSECT resetVect,class=CODE,delta=2
ResetVector:
    goto Setup
 
PSECT isrVect,class=CODE,delta=2
InterruptVector:
    goto ISRHandler
 
PSECT code,class=CODE,delta=2
Setup:
    BANKSEL PORTB
    CLRF PORTB
    BANKSEL PORTC
    CLRF PORTC
    CLRF SIXACTIVE
 
    BANKSEL TRISB
    MOVLW 0xFF
    MOVWF TRISB         ; RB0, RB1 inputs
    BANKSEL TRISC
    CLRF TRISC          ; PORTC all outputs -> DLG7137
 
    BANKSEL WPUB
    MOVLW 0x03
    MOVWF WPUB          ; weak pull-ups on RB0 and RB1
 
    BANKSEL IOCB
    MOVLW 0x02
    MOVWF IOCB          ; interrupt-on-change on RB1 only
 
    BANKSEL OPTION_REG
    BCF OPTION_REG,7    ; RBPU = 0 -> pull-ups enabled globally
    BCF OPTION_REG,6	; INTEDG = 0 -> RB0/INT on FALLING edge
 
    BANKSEL ANSEL
    CLRF ANSEL
    BANKSEL ANSELH
    CLRF ANSELH
 
    BANKSEL PORTB
    MOVF PORTB,W        ; establish the IOC mismatch reference
    BCF INTCON,0        ; clear stale RBIF
    BCF INTCON,1        ; clear stale INTF
    BSF INTCON,3        ; RBIE = 1 (7 armed)
    BSF INTCON,4        ; INTE = 1 (6 armed)
    BSF INTCON,7        ; GIE  = 1
 
    goto Main
    
Main:
    MOVLW D_ONE
    MOVWF PORTC
    goto Main
 
; ISR ENTRY -- SIXACTIVE tells us, with a single bit test, whether this
; is a fresh entry from idle or a 7 nesting inside an already-running 6.
; While 6 is active, INTE is held off (see Service6), so a nested entry
; can only ever be caused by RBIE/RBIF -- i.e. it can only be a 7.
ISRHandler:
    BTFSC SIXACTIVE,0
    goto SaveNested
    goto SaveNormal
 
SaveNormal:
    MOVWF W_TEMP1
    SWAPF STATUS,W
    MOVWF STATUS_TEMP1
    BTFSC INTCON,0            ; RBIF set? 7 outranks 6 -- check it first
    goto CheckSeven_Normal
    goto Service6
 
SaveNested:
    MOVWF W_TEMP2
    SWAPF STATUS,W
    MOVWF STATUS_TEMP2
    ; 6's delay routine and 7's delay routine share counters -- protect
    ; 6's in-progress count before letting 7 reuse them
    MOVF outCount,W
    MOVWF D2SCNT_SAVE
    MOVF midCount,W
    MOVWF DCNT2_SAVE
    MOVF inCount,W
    MOVWF DCNT1_SAVE
 
; Both entry paths funnel here to tell a real RB1 press apart from a
; release (IOC fires on either edge).
CheckSeven_Normal:
    MOVF PORTB,W          ; dummy read - required to end the mismatch
    BCF INTCON,0          ; clear RBIF
    BTFSS PORTB,1         ; still LOW (pressed)?
    goto Service7
    BTFSC INTCON,1        ; release -- was a 6 also pending?
    goto Service6
    goto LeaveNormal
 
CheckSeven_Nested:
    MOVF PORTB,W
    BCF INTCON,0
    BTFSS PORTB,1
    goto Service7
    goto LeaveNested               ; release while nested -- just resume 6
 
; SERVICE 6 (low priority). GIE is re-armed for the whole delay so 7
; can preempt at any point. INTE stays off for the duration so a
; second RB0 edge can't re-trigger 6 on top of itself.
Service6:
    BCF INTCON,1          ; clear INTF
    BCF INTCON,4          ; INTE off -- ignore further RB0 edges while 6 runs
    BSF SIXACTIVE,0       ; mark 6 active (enables nested-entry detection)
    MOVLW D_SIX
    MOVWF PORTC           ; display 6
    BSF INTCON,7          ; GIE back on -- 7 may now preempt this delay
    CALL Delay2Sec        ; interruptible 2-second delay
 
    BCF INTCON,7          ; GIE off again while wrapping up (atomic finish)
    BCF SIXACTIVE,0       ; 6 no longer active
    BCF INTCON,1          ; discard any 6-request that arrived during 6 itself
    MOVLW D_ONE
    MOVWF PORTC           ; 6 is done -> normal state is 1
    BSF INTCON,4          ; INTE back on -- fully idle again
    goto LeaveNormal
 
; SERVICE 7 (absolute priority) -- ONE shared copy, used whether 7 was
; triggered from idle or nested inside 6. GIE is left OFF the entire
; time, so nothing (not even another 7) can preempt it.
Service7:
    BCF INTCON,3          ; RBIE off -- nothing may preempt 7
    BCF INTCON,4          ; INTE off -- nothing may preempt 7 (GIE already off)
    MOVLW D_SEVEN
    MOVWF PORTC           ; display 7
    CALL Delay2Sec        ; UN-interruptible 2-second delay
 
    MOVF PORTB,W          ; resync the IOC reference and discard anything
    BCF INTCON,0          ; that happened to occur during 7
    BSF INTCON,3          ; RBIE back on
 
    BTFSC SIXACTIVE,0
    goto Service7_ResumeSix
 
    BCF INTCON,1           ; discard a stray 6-request that arrived during 7
    BSF INTCON,4           ; INTE back on -- fully idle
    MOVLW D_ONE
    MOVWF PORTC
    goto LeaveNormal
 
Service7_ResumeSix:
    MOVLW D_SIX
    MOVWF PORTC             ; 6 resumes -- redisplay 6 immediately
                            ; (INTE intentionally stays off; 6 itself turns
                            ; it back on when IT finally completes)
    goto LeaveNested
 
; CONTEXT RESTORE (datasheet SWAPF method)
LeaveNormal:
    SWAPF STATUS_TEMP1,W
    MOVWF STATUS
    SWAPF W_TEMP1,F
    SWAPF W_TEMP1,W
    RETFIE
 
LeaveNested:
    MOVF D2SCNT_SAVE,W
    MOVWF outCount
    MOVF DCNT2_SAVE,W
    MOVWF midCount
    MOVF DCNT1_SAVE,W
    MOVWF inCount
    SWAPF STATUS_TEMP2,W
    MOVWF STATUS
    SWAPF W_TEMP2,F
    SWAPF W_TEMP2,W
    RETFIE
 
; DELAY -- ONE level of CALL nesting on purpose (Delay2Sec -> Delay500ms).
; Delay500ms itself uses GOTO-based nested loops, not CALL, so it never
; adds a second level. Keeping this flat is what keeps the worst-case
; hardware stack safely under the 8-level limit.
Delay2Sec:
    MOVLW 0X04      ;1 TCY
    MOVWF outCount  ;1 TCY
    CALL OutDelay
    MOVLW 0X04      ;1 TCY
    MOVWF outCount  ;1 TCY
    CALL OutDelay
    MOVLW 0X04      ;1 TCY
    MOVWF outCount  ;1 TCY
    CALL OutDelay
    MOVLW 0X04      ;1 TCY
    MOVWF outCount  ;1 TCY
    CALL OutDelay
    RETURN

OutDelay:
    MOVLW 0XC0      ;1 TCY 192 in decimal
    MOVWF midCount  ;1 TCY
    NOP
    NOP
    NOP
    NOP
    NOP
    goto MidDelay       ;2 TCY

MidDelay:
    MOVLW 0xD7          ;1 TCY 215 in decimal
    MOVWF inCount       ;1 TCY
    goto InDelay        ;2 TCY

InDelay:
    DECFSZ inCount      ;1 (2) TCY
    goto InDelay        ;2 TCY

    DECFSZ midCount     ;1 (2) TCY
    goto MidDelay       ;2 TCY

    DECFSZ outCount     ;1 (2) TCY
    goto OutDelay	;2 TCY
    RETURN ;2 TCY
End
    