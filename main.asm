; TODO INSERT CONFIG CODE HERE USING CONFIG BITS GENERATOR
     LIST P=16F887
    #INCLUDE "p16f887.inc"

RES_VECT  CODE    0x0000            ; processor reset vector
    GOTO    MAIN                   ; go to beginning of program
    ORG 0x04
	GOTO RUTINA_INTERR;

; TODO ADD INTERRUPTS HERE IF USED
CBLOCK 0x20
	CANAL_ACT
	ADCON0_TEMP
	
VALOR_ADC_L EQU 0x70
VALOR_ADC_H EQU 0x71
MAIN_PROG CODE                      ; let linker place main program
 
CONFIG_UART:
    ;necesito poner laa uart en modo transmision con una vel de 300 baudios.
    ; SPBRG = INT(CLOCK/(F*V_DESEADA)-1)
    ; BRobt = CLOCK/(Fx(SPBRG+1))
    ; SPBRG = INT(1M/(64*10417)-1)= 51
    ; SPBRG = INT(1M/(16*10417)-1)= 207
    ; BRobt = 1M/(16x(207+1))= 300.5
    ; BRobt = 1M/(64x(51+1))= 300.5
    ; F=64 BRGH=0, F=16 BRGH=1 
    BSF TXSTA,BRGH; F=16
    BCF TXSTA,SYNC; ASINCRONO
    BSF RCSTA,SPEN; HABILITA el puerto serie
    BSF TXSTA,TXEN; HABILITA la transmision
    BCF TXSTA,TX9; Solo voy a mandar de a 8 bits
    MOVLW .207;
    MOVWF SPBRG;
    BSF INTCON, GIE;
    BSF INTCON, PEIE;
    BSF PIE1, TXIE;
    RETURN;

CONFIG_ADC:
   BANKSEL TRISA
   MOVLW B'00001111';PONE RA0,RA1,RA2,RA3 COMO ENTRADA
   IORWF TRISA; solamente cambian los bits que quiero poner a 1 todo lo demás queda como venía.
   MOVLW B'10010000';UNO JUSTIFICA A LA DERECHA y vref a gnd y v+ pin
   MOVWF ADCON1;
   ;HABILITO LA INTERRUPCION POR ADC
   BSF PIE1, ADIE;
   BCF PIE1, ADIF;
   BSF INTCON, PEIE;
   BSF INTCON, GIE;
   BANKSEL ADCON0;
   MOVLW B'00010001'; 11 CLOCK FOSC/2, 0100 CANAL 4, 1 ENCENDIDO
   MOVWF ADCON0
   CLRF ANSELH;//Pone cero en todos los pines para habilitarlos como entrada analogica
   CALL ESPERA_11_5US; TIEMPO MINIMO DESDE LA CONFIG HSATA QUE PUEDE CONVERTIR
   ;BSF ADCON0, GO; QUE ARRANQUE A CONVERTIR
   RETURN
   
CONFIG_TIMER0:
    ;CALCULOS PARA OSCILADOR EN 1MHZ
    BANKSEL STATUS;
    MOVLW B'00101111';MODO CONTADOR,FLACO DE SUBIDA,PRESCALER EN 256
    MOVWF OPTION_REG;
    BANKSEL INTCON;
    ;HABILITAMOS LAS INTERRUPCIONES PARA EL TIMER0
    BSF INTCON, T0IE;
    BSF INTCON, GIE;
    MOVLW .14;VALOR CALCULADO PARA CONSEGUIR INTERRUPCIONES CADA 250MILIS
    MOVWF TMR0;
    MOVLW .240;
    MOVWF REGRE_DE_240;
    RETURN;

CONFIGURACION:
    MOVLW .4;
    MOVWF CANAL_ACT;
    MOVLW 0x70;
    MOVWF FSR;
    
    CALL CONFIG_ADC;
    CALL CONFIG_TMR0;
    RETURN;
    
RUTINA_INTERR:
    MOVWF TEMP_W
    SWAPF STATUS, W
    MOVWF TEMP_STATUS
    
    BTFSC PIR1, ADIF;SALTO EL ADC?
    BSF BANDERAS, BAN_ADC;LEVANTO MI BANDERA ADC
    BTFSC INTCON, T0IF;
    BSF BANDERAS, MI_TMR0;LEVANTO MI BANDERA TMR0
    BTFSC PIR1, TXIF;terminó la transmision de 8bits
    BSF BANDERAS, MI_ENVIO8B;LEVANTO MI BANDERA DE ENVIO DE 8bits TERMINADO
    
    SWAPF TEMP_STATUS, W
    MOVWF STATUS
    SWAPF TEMP_W, F
    SWAPF TEMP_W, W
    RETFIE;
    
ENVIAR_PROX_8BITS:
    ;0x70 [0 1 1 1 0 0 0 0]
    ;0x01 [0 0 0 0 0 0 0 1] XOR
    ;0x71 [0 1 1 1 0 0 0 1]
    MOVFW INDF;
    MOVWF TXREG;
    MOVFW FSR; Fijarse si puedo hacer el toggle en menos instrucciones
    XORLW .1;
    MOVWF FSR;
    BTFSS FSR,0;
    BCF BANDERAS, ENVIAR_8BITS;
    RETURN
    
  
 CONVERSION_DISP:
    MOVF ADRESL,W;
    MOVWF VALOR_ADC_L;
    MOVF ADRESH,W;
    MOVWF VALOR_ADC_H;
    BCF PIR1, ADIF; LIMPIO EL FLAG DE INT DEL ADC PORQ HAY QUE HACER LO MINIMO POSIBLE EN LA RUTINA DE INT.
    ;BSF ADCON0, GO; YA TE LEÍ ARRANCA A CONVERTIR EL PROXIMO VALOR
    BCF BANDERAS,BAN_ADC;BAJO MI BANDERA DEL ADC, limpio la bandera que me trajo aqui.
    INCF CANAL_ACT;
    CALL REEMPLAZAR_CANAL;
    BSF BANDERAS, ENVIAR8BITS;
    RETURN;
    
 PASARON_250M:
    MOVLW .14;
    MOVWF TMR0;
    DECFSZ REGRE_DE_240, F;
    RETURN
    BSF BANDERAS, MI_1MIN;LEVANTO MI BANDERA DE QUE PASÓ UN MINUTO
    MOVLW .240;
    MOVWF REGRE_DE_240;resestablecwr el valor del regresivo sino no puedo contar el proximo minuto
    BCF INTCON, T0IF;bajando la bandera de la interr de tmr0
    BCF BANDERAS, MI_TMR0;parar que el main no se quede atrapado en el tmr0
    RETURN;
    
 REEMPLAZAR_CANAL:
    ;canal 4 [0 0 0 0 0 1 0 0]
    ;canal 5 [0 0 0 0 0 1 0 1]
    ;canal 6 [0 0 0 0 0 1 1 0]
    ;canal 7 [0 0 0 0 0 1 1 1]
    ;canal 8 [0 0 0 0 1 0 0 0]?????
    BTFSC CANAL_ACT,3;Si el bit 3 del canal está en 1 tengo que reestablecer el valor a 4.
    RRF CANAL_ACT,1;uso la rotacion a la derecha para convertir el 8 en un 4
    MOVFW CANAL_ACT;
    MOVWF NUEVO_CANAL;
    RLF NUEVO_CANAL,1;
    RLF NUEVO_CANAL,1;
    ;tengo que enmascarar ADCON0 para no modificar los dos bits mas sig ni los dos menos sig.
    MOVFW ADCON0;
    ANDLW B'11000011';
    IORWF NUEVO_CANAL,0;[00011100]
    MOVWF ADCON0;
    RETURN;
    
 PASO_UN_MIN:
    BCF ADCON0,GO;
    ;TODO donde tengo que poner la espera de 11.5us para inciar la conversion en el nuevo canal?
    ;TODO como se implementa la espera para el ADC recordar que tenemos 1MHZ de clock!

    ;TODO QUE COMPILE!!
MAIN
    CALL CONFIGURACION;
LOOP
    BTFSC BANDERAS, BAN_ADC;SI SALTO LA BANDERA DEL ADC ENTONCES REVISO LA CONVERSION
    CALL CONVERSION_DISP;
    
    BTFSC BANDERAS, BAN_TMR0;SI SALTO LA BANDERA DEL TIMER CADA 250 MILISEC
    CALL PASARON_250M;
    
    BTFSC BANDERAS, BAN_1MIN;SI SALTO LA BANDERA CUANDO PASO 1 MIN.
    CALL PASO_UN_MIN;
    
    BTFSC BANDERAS, ENVIAR8BITS;SI SALTO LA BANDERA DE QUE EL BUFER ESTA COMPLETO.
    CALL ENVIAR_PROX_8BITS;
    
    GOTO LOOP;

    END
    
    ;TODO fabricar un machetito con los registros para cada disp
    ;REG config ADC
    ;REG config tmr0