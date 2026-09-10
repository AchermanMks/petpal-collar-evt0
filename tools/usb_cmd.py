#!/usr/bin/env python3
"""Send one command to the board's USB console (console_app.lua on uart.VUART_0) and print the reply.

Usage:
    usb_cmd.py ping
    usb_cmd.py get
    usb_cmd.py set gsensor 1        # then: usb_cmd.py reboot
    usb_cmd.py status
    usb_cmd.py --port /dev/cu.usbmodem0000000000017 status
Without --port every usbmodem port is pinged and the one answering "pong" is used.
The log port (…13) and the CP trace port (…15) ignore the ping, so probing is harmless.
"""
import argparse, glob, sys, time

def talk(serial, port, line, wait=1.5):
    s = serial.Serial(port, 115200, timeout=0.2)
    s.reset_input_buffer()
    s.write((line + "\n").encode())
    t0 = time.time(); out = b""
    while time.time() - t0 < wait:
        out += s.read(4096)
        if b"\n" in out and (out.startswith(b"ok") or out.startswith(b"err") or out.startswith(b"pong")): break
    s.close()
    return out.decode("utf-8", "replace").strip()

def find_console(serial):
    for p in sorted(glob.glob("/dev/cu.usbmodem*") + glob.glob("/dev/ttyACM*")):
        try:
            r = talk(serial, p, "ping", wait=1.0)
        except Exception:
            continue
        if "pong" in r: return p
    return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port")
    ap.add_argument("words", nargs="+")
    a = ap.parse_args()
    try:
        import serial
    except ImportError:
        sys.exit("pip install pyserial")
    port = a.port or find_console(serial)
    if not port: sys.exit("no port answered ping; is console_app.lua flashed and the board running?")
    reply = talk(serial, port, " ".join(a.words))
    print(reply if reply else "(no reply)")
    sys.exit(0 if reply.startswith(("ok", "pong")) else 1)

if __name__ == "__main__":
    main()
