Hi.

These are some fun programs to play with.  Mostly, this is an example of how to use WebSockets to put device data onto the web.

The .asm files you need to complile with gavrasm and flash with avrdude. I use an Arduino Micro as an ISP programmer

The wiring is simmilar to the Adafruit tutorial about the PN532 and an Arduino.
  Use the avr MOSI to MOSI
     MISO to MISO
     SCK to SCK
     PB2 to NSS (pin 16 on the atmega168 to NSS on PN532)

Then, connect the atmega168 RX to TX on the pi, TX to RX.

Make sure to pull 5v from RaspberryPi and then convert to 3.3v with a power regulator.  Pulling only 3.3v from the pi will screw up the serial.

The RaspberryPi will fry if you use 5v logic.  I ran the PN532 and the atmega168 both at 3.3v so I didn't need a level shifter.

Put the darby.html into your /var/www/ folder if your going to use the pi as a web server.

Thanks Adafruit for all the tips and tools!

Adafruit rules \\o/ !
