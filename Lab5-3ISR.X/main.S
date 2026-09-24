    ; Abel Doyle
    ; RCET3373
    ; Lab5-3ISR
    ; https://github.com/abeldoyl/Lab-05-ISRs/tree/main/Lab5-3ISR.X
    
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
  W_TEMP EQU 0x70
  STATUS_TEMP EQU 0x71
  PORTB_OLD EQU 0x72
  PORTB_NEW EQU 0x73
  CHANGED EQU 0x74
; Reset Vector at 0000h. Execution starts here after reset.
PSECT resetVect,class=CODE,delta=2
ResetVector: 
    goto Setup

; Interrupt Vector at 0004h. Execution starts here after an interrupt.
PSECT isrVect,class=CODE,delta=2
InterruptVector:
    goto ISRHandler

; Main code section starts at 0008h. User code goes here.
PSECT code,class=CODE,delta=2
 
Setup:
    ; add device setup here
    ; Bank 0
    BCF 0x03,6      ;Set Bank 0
    BCF 0x03,5      ;"
    CLRF PORTA      ;Clearing PORTA on reset
    CLRF PORTB      ;Clearing PORTB on reset
    CLRF PORTC	    ;Clearing PORTC on reset
 
    ; Bank 1
    BCF 0x03,6	    ;Set Bank 1
    BSF 0x03,5	    ;"
    CLRF TRISA	    ;PORTA input
    CLRF TRISC	    ;PORTC input
    MOVLW 0xFF
    MOVWF TRISB     ;PORTB inputs
    MOVWF WPUB      ;weak pull-ups on all pins
    MOVWF IOCB      ;interrupt-on-change on RB0-RB7
    BCF OPTION_REG,7;Pull-ups enabled
 
    ; Bank 3
    BSF 0x03,6      ;Set Bank 3
    BSF 0x03,5      ;"
    CLRF ANSEL      ;Making PORTA digital I/O
    CLRF ANSELH     ;Making PORTB digital I/O
 
    ;Interrupts
    BCF 0x03,6      ;Set Bank 1
    BSF 0x03,5	    ;"
    BCF OPTION_REG,6;Allows for interrupt on falling edge
    BCF INTCON,0
    BSF INTCON,3    ;Enables the INT external Interrupt bit
    BCF INTCON,4    ;INT disabled
    BSF INTCON,7    ;Enables global interrupts
    
    BCF 0x03,6      ;Set Bank 0
    BCF 0x03,5      ;"
    goto Main
    
Main:
    ; main code goes here
    goto Main
    
ISRHandler:
    MOVWF W_TEMP ;Copy W to TEMP register
    SWAPF STATUS,W ;Swap status to be saved into W
    ;Swaps are used because they do not affect the status bits
    MOVWF STATUS_TEMP ;Save status to bank zero STATUS_TEMP register
    
    ;Compare current PORTB vs. previous PORTB
    MOVF PORTB,W
    MOVWF PORTB_NEW
    XORWF PORTB_OLD,W
    MOVWF CHANGED
    
    ;Save current PORTB for next comparison
    MOVF PORTB_NEW,W
    MOVWF PORTB_OLD

    ;Code block for what value on the LEDs is displayed based on what PORTB pin caused the interrupt
    BTFSC   CHANGED,0     
    goto    Display0             
    BTFSC   CHANGED,1     
    goto    Display1           
    BTFSC   CHANGED,2     
    goto    Display2            
    BTFSC   CHANGED,3     
    goto    Display3             
    BTFSC   CHANGED,4     
    goto    Display4         
    BTFSC   CHANGED,5     
    goto    Display5         
    BTFSC   CHANGED,6     
    goto    Display6         
    BTFSC   CHANGED,7     
    goto    Display7         
    goto    IOC_Flag         

Display0:   
    MOVLW   0x00             ;Display 000 on PortA
    goto    SetDisplay
Display1:   
    MOVLW   0x01             ;Display 001 on PortA
    goto    SetDisplay
Display2:
    MOVLW   0x02             ;Display 010 on PortA
    goto    SetDisplay
Display3:
    MOVLW   0x03             ;Display 011 on PortA
    goto    SetDisplay
Display4:
    MOVLW   0x04             ;Display 100 on PortA
    goto    SetDisplay
Display5:
    MOVLW   0x05             ;Display 101 on PortA
    goto    SetDisplay
Display6:
    MOVLW   0x06             ;Display 110 on PortA
    goto    SetDisplay
Display7:
    MOVLW   0x07             ;Display 111 on PortA

SetDisplay:
    MOVWF   PORTA            ;Display the selected value on PORTA

IOC_Flag:
    BCF     INTCON,0         ;Clear the RBIF flag after PORTB was reread
    
LeaveISR:
    SWAPF STATUS_TEMP,W ;Swap STATUS_TEMP register into W
    ;(sets bank to original state)
    MOVWF STATUS ;Move W into STATUS register
    SWAPF W_TEMP,F ;Swap W_TEMP
    SWAPF W_TEMP,W ;Swap W_TEMP into W
    RETFIE
  
End