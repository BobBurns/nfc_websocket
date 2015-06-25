import socket
import struct
import sys
from struct import *
import hashlib
import base64
import time
import serial

def main():
  MAXLEN = 4096
  server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
  server_socket.bind(("",2342))
  port = "/dev/ttyAMA0"
  avr_serial = serial.Serial(port, 9600)
  avr_serial.flushInput()
  inString = ""

  print("Listening for connection...")

  while True:
    server_socket.listen(10)
    try:
      conn, address = server_socket.accept()
    except IOError:
      print("error: server_socket.accept")
      return

    if verifyPass(conn) is False:
      print("password failed")
      return

    on = False
    conn.setblocking(0)
    print "connected."
    unlocked = False
    while True:
    # poll serial
      if on:
        inString = ""
        while True:
          myinput = avr_serial.read(1)
          if myinput:
            upb = struct.unpack('!B', myinput)
            # print upb[0]
            if upb[0] == 4:
              break
            inString += myinput

        outString = ""
        byteStream = struct.unpack("!{0}B".format(len(inString)), inString)
        
        cmd = 0xA0	#send name for now
        for i in range(1,16):
          outString += chr(byteStream[i])

	dataframe = setupPacket(outString)
        print dataframe
        try:
          conn.send(bytes(dataframe))
        except IOError:
          print("error conn.send dataframe")
          return

        cmd = 0xA1
        valL = int(chr(byteStream[19])+chr(byteStream[20]), 16)
        valH = int(chr(byteStream[21])+chr(byteStream[22]), 16)
        dataframe = setupValue(cmd, valL, valH)
        print dataframe
        try:
          conn.send(bytes(dataframe))
        except IOError:
          print("error conn.send dataframe")
          return
        on = False	#turn off scan so we can receive

      # check for incomming
      try:
        recbuf = conn.recv(MAXLEN)
        if recbuf:
          if unlocked:
            result = getIncomming(recbuf)
            print result
            if result[0] == 0x80:
              print("Bye!")
              done = True
              break 

  # check opcodes and update
            if result[0] == 0x20:
              on = True
              print("run = true")
          else:
            if recbuf == "password":
              print "it worked"
              unlocked = True
            else:
              cmd = 0xF0
              valL = 0xFF
              valH = 0xFF
              dataframe = setupValue(cmd, valL, valH)
              try:
                conn.send(bytes(dataframe))
              except IOError:
                print("error conn.send pass")
                return

      except:		# need this for non-blocking errors
        pass

    if done: break
  conn.close()
  server_socket.close()
  return

def verifyPass(conn):
  MAXLEN = 256
  try:
    buf = conn.recv(MAXLEN)
  except:
    print("conn.recv() error")
    return False

  print buf

  if buf == "password":
    print "yay!"

  return True

def setupState(cmd, state):
  opcode = 0x82
  dlen = 0x02

  return chr(opcode) + chr(dlen) + chr(cmd) + chr(state)

def setupValue(cmd, valL, valH):
  # send lsb first
  opcode = 0x82
  dlen = 0x03
  value = chr(opcode) + chr(dlen) + chr(cmd) + chr(valL) + chr(valH)
  return value

def setupPacket(message):
  opcode = 0x81		# to send text
  length = len(message)

  if length < 126:
    dlen = length	#probably don't need to convert to hex
  else:
    print("message must be under 126 characters for now")
    return -1

  return chr(opcode) + chr(dlen) + message

def setupName(cmd, byteStream):
  opcode = 0x81
  length = 0x11
  outString = ""
  for i in range(1, 16):
    outString += chr(byteStream[i])

  value = chr(opcode) + chr(length) + chr(cmd) + outString
  return value

def getIncomming(inbuf):
  print inbuf
  decoded = []
  uparg = "!{0}B".format(len(inbuf))
  arrayBuffer = struct.unpack(uparg, inbuf)
  print arrayBuffer
  opcode = int(arrayBuffer[0])
  paylen = int(arrayBuffer[1])


  for i in range(0,paylen):
    decoded.append(arrayBuffer[2+i])

  return decoded

if __name__ == '__main__':
    main()
