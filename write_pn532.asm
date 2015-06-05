;new program to set up and test the PN532 chip reader 
;compile with gavrasm write_pn532.asm ;flash with avrdude -c avrisp -p m168 -P /dev/tty.usbmodem1411 -b 19200 -U flash:w:write_pn532.asm
;
; I/O pins:
;	** use PORTB except RDYN on PORTD **
;	** SCK on pin 5 configured as output **
;	** MISO on pin 4 configured as input with pullup **
;	** MOSI on pin 3 configured as output **
;	** NSS on pin 2 configured as output **
;	** NSS on pin 2 not selected (high)
;	** IRQ	on PB1 configured as input with pullup **
;---- defines ----
.device atmega168
.equ HAL_PORT = 0x05		;PORTB
.equ HAL_DDR = 0x04		;DDRB
.equ HAL_PIN = 0x03		;PINB
.equ HAL_SCK = 5
.equ HAL_MISO = 4
.equ HAL_MOSI = 3
.equ HAL_NSS = 2
; not using IRQ
;
.equ MSG_FLG = 0
.equ RD_FLG = 1
;
;UBBR value for USART from f_cpu 1000000
.equ UBBRvalue = 12
;*** some opcodes for PN532 ***
.equ C_TEST = 0x00
;*** delay constant
.equ dlp_init = 50000
;---- registers
.def temp = r16
.def count = r17
.def temp2 = r18
.def r_dcs = r19
.def delayL = r24
.def delayH = r25
.def xL = r26
.def xH = r27
.def yL = r28
.def yH	= r29
.def zL = r30
.def zH = r31
.cseg
;---- Interrupt Vector ---
.org 0
	rjmp	reset
	rjmp	RDYN_L			;INT0 vector
RDYN_L:
; I'm not going to use this yet
	reti
reset:
;Initialize Stack
	ldi	temp,low(RAMEND)
	out	SPL,temp
	ldi	temp,high(RAMEND)
	out 	SPH,temp
;Init SPI
;** don't have to set phase or polarity. PN532 uses mode 0
	in	temp,SPCR
	sbr	temp,(1 << SPR0)	;divide f_cpu by 16, better for breadboards
	sbr	temp,(1 << MSTR)	;set AVR to SPI Master mode
	sbr	temp,(1 << DORD)	;use LSB bit order
	sbr	temp,(1 << SPE)		;enable SPI
	out	SPCR,temp
;
;*** set ddr and output on pin lines
;
	sbi	HAL_DDR,HAL_NSS		;output on NSS
	cbi	HAL_PORT,HAL_NSS	;lower NSS to wake up pn532
	sbi	HAL_DDR,HAL_SCK		;output on SCK
	sbi	HAL_PORT,HAL_MISO	;set pullup on MISO // confg as input
	sbi	HAL_DDR,HAL_MOSI	;output on MOSI
; wait to set pullup on IRQ line sbi	HAL_PORT,HAL_IRQ	;set pullup on IRQ line
;
;initialize USART
        ldi     temp,high(UBBRvalue)    ;baud rate param
        sts     UBRR0H,temp
        ldi     temp,low(UBBRvalue)
        sts     UBRR0L,temp
        lds     temp,UCSR0A
        ori     temp,(1 << U2X0)        ;set use 2x because %error actual baud > .5
        sts     UCSR0A,temp
;--- USART register values
        ldi     temp,(1 << TXEN0) | (1 << RXEN0) ;enable transmit and receive
        sts     UCSR0B,temp
        ldi     temp,(1 << UCSZ01) | (1 << UCSZ00) ;8 data bits, 1 stop bit
	sts	UCSR0C,temp
;********* Main Program **********
;
; wake up pn532
	ldi	count,5			;one second
	rcall	delay			;delay after startup
start:	
	ldi	zH,high(gfv << 1)	;call get firmware version to sync?
	ldi	zL,low(gfv << 1)
	rcall	snd_cmd
	sbi	HAL_PORT,HAL_NSS	;snd_cmd doesn't raise NSS when finished
	rcall	ack_resp
	ldi	zH,high(samc << 1)	;next configure SAM normal 14 01
	ldi	zL,low(samc << 1)
	rcall	snd_cmd
	sbi	HAL_PORT,HAL_NSS
	rcall	ack_resp
	ldi	zH,high(ilpt << 1)
	ldi	zL,low(ilpt << 1)
	rcall	snd_cmd			;send inListPassiveTarget command
	sbi	HAL_PORT,HAL_NSS
	rcall	ack_resp		;get response
	ldi	xL,low(in_buf)
	ldi	xH,high(in_buf)
	adiw	xH:xL,9
	ld	temp,X+
	cpi	temp,4			;make sure NFCID is MiFare1
	brne	error
	ldi	zH,high(ide_a << 1)
	ldi	zL,low(ide_a << 1)
 	rcall	snd_cmd			;send first part of command
	ldi	count,4
	ldi	r_dcs,0x76		;dcs before NFCID
auth_end:
	ld	temp,X+
	add	r_dcs,temp
	rcall	SPI_tradeByte
	dec	count
	brne	auth_end	
	mov 	byte_tx,r_dcs
	rcall	transmit	
	neg	r_dcs
	mov 	byte_tx,r_dcs
	rcall	transmit
	mov 	temp,r_dcs
	rcall	SPI_tradeByte
	ldi	temp,0x00
	rcall	SPI_tradeByte
	sbi	HAL_PORT,HAL_NSS
	rcall	ack_resp
	ldi	xL,low(in_buf)
	ldi	xH,high(in_buf)
	adiw	xH:xL,4			;check response status
	ld	temp,X
	cpi	temp,0x00
	brne	error
	ldi	zH,high(cmd_head << 1)
	ldi	zL,low(cmd_head << 1)
	rcall	snd_cmd
	ldi	zH,high(wr_name << 1)		;write data block 'Darby Crash'
	ldi	zL,low(wr_name << 1)
	rcall	snd_dcs
	sbi	HAL_PORT,HAL_NSS
	rcall	ack_resp
	ldi	zH,high(cmd_head << 1)
	ldi	zL,low(cmd_head << 1)
	rcall	snd_cmd
	ldi	zH,high(credit_blk << 1)	;write value block 667
	ldi	zL,low(credit_blk << 1)
	rcall	snd_dcs
	sbi	HAL_PORT,HAL_NSS
	rcall	ack_resp
	ldi	zH,high(cmd_head << 1)
	ldi	zL,low(cmd_head << 1)
	rcall	snd_cmd
	ldi	zH,high(read_st7 << 1)		;read sector trailer access bits
	ldi	zL,low(read_st7 << 1)
	rcall	snd_dcs
	sbi	HAL_PORT,HAL_NSS
	rcall	ack_resp
;done
	ldi	zH,high(succ_str << 1)
	ldi	zL,low(succ_str << 1)
	rcall	print_s			;print success
	rjmp	exit_lp	
error: 	ldi 	byte_tx,0xEE
	rcall	transmit
	rcall	transmit		;EE EE on error
exit_lp:
	nop
	rjmp exit_lp
;****** Subroutines ******
;print out message
prt_m:
	push	count
	ldi	xL,low(in_buf)
	ldi	xH,high(in_buf)		;load x reg with pointer to message
	ld	count,X+
	mov	byte_tx,count
	rcall	transmit
p_lp:	ld	byte_tx,X+
	rcall	transmit
	dec	count
	brne	p_lp
	pop	count
	ret
.def byte_tx = r19
;---- function to transmit byte ----
;transmit byte from r19 over usart
transmit:
        lds     temp,UCSR0A
        sbrs    temp,UDRE0
        rjmp    transmit
        sts     UDR0,byte_tx
        ret
;print string function
;takes Z loaded with pointer to string with first byte being length
;uses r16,r17,r19
print_s:
        lpm     count,Z+
for1:   lpm     byte_tx,Z+
wait:   lds     temp,UCSR0A
        sbrs    temp,UDRE0      ;wait for Tx buffer to be empty
        rjmp    wait            ;not ready
        sts     UDR0,byte_tx;
        dec     count
        brne    for1
        ret
;
;-------- delay subroutines ------------
;takes count in reg r17 * 200 milliseconds
delay:
	ldi     delayH,high(dlp_init)   
        ldi     delayL,low(dlp_init)
dlp:    sbiw    delayH:delayL,1
	nop				;makes 4 clock cycles
        brne    dlp 
        dec     count
        brne    delay
        ret 
;millisecond delay *** takes count (r17) as msecond value
m_delay:
	ldi	temp,0xfa
md_lp:	nop
	nop
	dec	temp
	brne	md_lp			;4 clock cycles times 250 = 1000us (1000000 f_cpu)
	dec	count
	brne	m_delay
	ret
;----- SPI routines -----
;uses temp r16 as tx byte and returns with rx byte in temp
SPI_tradeByte:
	out	SPDR,temp
lp1:	in	temp2,SPSR
	sbrs	temp2,SPIF
	rjmp 	lp1
	in	temp,SPDR
	ret
;send ascii representation of one byte over serial
;byte to convert in r24
;uses r24 as low nibble to send and r25 for high nibble
t_htoa:
        lds     temp,UCSR0A
        sbrs	temp,UDRE0
        rjmp	t_htoa
	ldi	temp,0x30	;ascii offset
	mov	r25,r24
	lsr	r25
	lsr	r25
	lsr	r25
	lsr	r25
	cpi	r25,0x0A
	brlt	no_e
	ldi	temp,0x37	;extended hex
no_e:	add	r25,temp
        sts     UDR0,r25
t_2:	lds	temp,UCSR0A
	sbrs	temp,UDRE0
	rjmp	t_2
	ldi	temp,0x30	;ascii offset
	andi	r24,0x0f	;low nibble
	cpi	r24,0x0a
	brlt	no_e2
	ldi	temp,0x37
no_e2:	add	r24,temp	;add 0x30 to get ascii representation
	sts	UDR0,r24
	ret
;print message from inbuf
p_mess:
	ldi	xL,low(in_buf)
	ldi	xH,high(in_buf)
	ld	count,X+
mess_lp:
	ld	byte_tx,X+		;reprint data
	rcall 	transmit
	dec 	count
	brne	mess_lp
	ret
;send command routine
;Z reg points to command string with first byte being length
snd_cmd:
	cbi	HAL_PORT,HAL_NSS
	lpm	count,Z+
snd_for:
	lpm	temp,Z+
	rcall	SPI_tradeByte
	dec	count
	brne	snd_for
	ret
; send routine with data checksum
snd_dcs:
	lpm	count,Z+
	mov	temp,count
	rcall	SPI_tradeByte
	mov	temp,count		;count is same as length byte
	neg	temp
	rcall	SPI_tradeByte		;send length byte and length checksum
	lpm	temp,Z+
	mov	r_dcs,temp		;first byte to add to (TFI)
	rcall	SPI_tradeByte
	dec	count
sdcs_for:
	lpm	temp,Z+
	add	r_dcs,temp
	rcall	SPI_tradeByte
	dec	count
	brne	sdcs_for
	mov	temp,r_dcs
	neg	temp
	rcall	SPI_tradeByte
	ldi	temp,0x00
	rcall	SPI_tradeByte
	ret
;ack routine
;
ack_resp:
	ldi	xL,low(in_buf)		;set up pointer to storage buffer
	ldi	xH,high(in_buf)
	cbi	HAL_PORT,HAL_NSS
sr_lp: 	ldi	temp,0x02		;status reading SR
	rcall 	SPI_tradeByte
	ldi	temp,0x00
	rcall 	SPI_tradeByte
	mov 	byte_tx,temp
;	rcall	transmit
	sbrs	byte_tx,0		;ready bit
	rjmp	sr_lp
	sbi	HAL_PORT,HAL_NSS
;get ack and print for now
	ldi	count,0x06		;6 bytes
	cbi	HAL_PORT,HAL_NSS
	ldi	temp,0x03		;data reading
	rcall 	SPI_tradeByte
ack_p:	ldi	temp,0x00
	rcall	SPI_tradeByte
	mov 	byte_tx,temp
	rcall	transmit
	dec 	count
	brne	ack_p
	sbi	HAL_PORT,HAL_NSS
	ldi	byte_tx,0xAC
	rcall	transmit
 	cbi	HAL_PORT,HAL_NSS
rec:	ldi	temp,0x02		;status reading
	rcall 	SPI_tradeByte
	ldi	temp,0x00
	rcall	SPI_tradeByte
	sbrs	temp,0
	rjmp	rec
	sbi	HAL_PORT,HAL_NSS
	ldi	count,0x03		;first three bytes preamble +  start code
	cbi	HAL_PORT,HAL_NSS
	ldi	temp,0x03
	rcall 	SPI_tradeByte		;data reading
out_p:	ldi	temp,0x00
	rcall	SPI_tradeByte
	mov	byte_tx,temp
	rcall	transmit		;print 
	dec	count
	brne	out_p
	ldi	temp,0x00
	rcall	SPI_tradeByte
	mov	byte_tx,temp
	rcall	transmit
	cpi	byte_tx,0x01		;length byte 1 on error
	breq	app_err
	mov	count,byte_tx
	inc	count
	inc	count
	inc	count
	st	X+,count		;store length first
rec_end:
	ldi	temp,0x00
	rcall	SPI_tradeByte
	st	X+,temp			;store rec mess
	mov	byte_tx,temp
	rcall	transmit
	dec 	count
	brne	rec_end
	sbi	HAL_PORT,HAL_NSS
	ret
app_err:
	ldi	count,0x04
err_lp:	ldi	temp,0x00
	rcall	SPI_tradeByte
	mov	byte_tx,temp
	rcall	transmit
	dec	count
	brne	err_lp	
	sbi	HAL_PORT,HAL_NSS
end:	nop				;dont return
	rjmp	end
;****** Subroutines ******
succ_str: .db 20,0x0d,0x0a,"*** Success! ***",0x0d,0x0a,0x00
cre_str: .db 24,"command response event: ",0x00
mode_str: .db 5,"mode:"
buff_str: .db 8,"buffers:",0x00
hello: .db "hello world!"
brd_str: .db 22,"*** we are live! ***",0x0d,0x0a,0x00
setup_str: .db 32,"Setup mode! starting set up...",0x0d,0x0a,0x00
;********************************************************************
;some commands to send
gfv: .db 0x0A,0x01,0x00,0x00,0xFF,0x02,0xFE,0xD4,0x02,0x2A,0x00,0x00
samc: .db 0x0D,0x01,0x00,0x00,0xFF,0x05,0xFB,0xD4,0x14,0x01,0x00,0x01,0x16,0x00
ilpt: .db 0x0C,0x01,0x00,0x00,0xFF,0x04,0xFC,0xD4,0x4A,0x01,0x00,0xE1,0x00,0x00
ide_a: .db 0x11,0x01,0x00,0x00,0xFF,0x0F,0xF1,0xD4,0x40,0x01,0x60,0x07,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF
cmd_head: .db 0x04,0x01,0x00,0x00,0xFF,0x00
wr_name: .db 0x15,0xD4,0x40,0x01,0xA0,0x04,0x44,0x61,0x72,0x62,0x79,0x20,0x43,0x72,0x61,0x73,0x68,0x00,0x00,0x00,0x00,0x00
credit_blk: .db 0x15,0xD4,0x40,0x01,0xA0,0x05,0x9B,0x02,0x00,0x00,0x64,0xFD,0xFF,0xFF,0x9B,0x02,0x00,0x00,0x05,0xFA,0x05,0xFA
read_st7: .db 0x05,0xD4,0x40,0x01,0x30,0x07
.dseg
;**** in_buf starts with a length byte
in_buf: .byte 0x40
