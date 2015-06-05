# python websocket program to run with the pn532 connected to serial

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

    if wshandshake(conn) is False:
      print("handshake failed")
      return

    on = False
    while True:
      conn.setblocking(0)
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
          result = getIncomming(recbuf)
          print result
          if result[0] == 0:
            print("Bye!")
            done = True
            break 

  # check opcodes and update
          if result[0] == 0x20:
            on = True
            print("run = true")

      except:		# need this for non-blocking errors
        pass

    if done: break
  conn.close()
  return

def wshandshake(conn):
  global resource
  MAXLEN = 4096
  magicGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  headers = {}
  try:
    buf = conn.recv(MAXLEN).decode("UTF-8")
  except:
    print("conn.recv() error")
    return -1
  lines = buf.splitlines()
  for line in lines:
    if line.find(':') >= 0:
      header = line.split(':', 2)
      key = header[0].strip().lower()
      headers[key] = header[1].strip()
    elif line.find('get') >= 0:
      getline = line.split(' ')
      headers['get'] = getline[1] 


  if headers.get('get'):
    resource = headers['get']


  if headers.get('sec-websocket-version') != '13':
    handshakeResponse = "HTTP/1.1 426 Upgrade Required\r\nSec-WebSocketVersion: 13"
    conn.send(bytes(handshakeResponse))
    return False

  websocketKeyHash = hashlib.sha1(headers.get('sec-websocket-key') + magicGUID).hexdigest()
  rawToken = ""

  for i in range(0, 20):
    rawToken += chr(int(websocketKeyHash[i*2:(i*2)+2], 16))

  handshakeToken = base64.b64encode(rawToken)

  handshakeResponse = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + handshakeToken + "\r\n\r\n"

  conn.send(bytes(handshakeResponse))
  
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
  # print inbuf
  decoded = []
  uparg = "!{0}B".format(len(inbuf))
  arrayBuffer = struct.unpack(uparg, inbuf)
  opcode = int(arrayBuffer[0]) & int('0F', 16)
  paylen = int(arrayBuffer[1]) & int('7F', 16)
  maskbit = int(arrayBuffer[1]) & int('80', 16)

  if opcode == 0x08:
    decoded[0] = 0
    return decoded

  if maskbit > 0:
    mask = (int(arrayBuffer[2]), int(arrayBuffer[3]), int(arrayBuffer[4]), int(arrayBuffer[5]))
    for i in range(0,paylen):
      decoded.append(arrayBuffer[6+i] ^ mask[i % 4])

  return decoded

if __name__ == '__main__':
    main()
