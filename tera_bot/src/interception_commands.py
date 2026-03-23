import os
import sys
import ctypes
import math
import time

DLL_DIR = r"C:\Tools\Interception\library\x64"

if not os.path.exists(os.path.join(DLL_DIR, "interception.dll")):
    sys.exit(f"interception.dll not found in {DLL_DIR}")
else:
    os.add_dll_directory(DLL_DIR)

    ctypes.WinDLL(os.path.join(DLL_DIR, "interception.dll"))

    import interception
    from interception import beziercurve

    interception.auto_capture_devices()
    curve_params = beziercurve.BezierCurveParams()


def move_mouse_to(x, y):
    interception.move_to(x, y)


def move_circle(radius, speed):
    current_position = interception.mouse_position()
    for i in range(0, 360, speed):
        x = int(radius * math.cos(i))
        y = int(radius * math.sin(i))
        move_mouse_to(current_position[0] + x, current_position[1] + y)
        time.sleep(0.1)


def print_position_log():
    interception.write("/8 savepos", 0.1)
    interception.press('enter')


def zoom_out():
    """Scroll out the maximum distance"""
    for i in range(25):
        interception.scroll("down")


def toggle_hud(mode=True):
    if mode is True:
        with interception.hold_key("ctrl"):
            interception.press("z")
        print("HUD disabled")
    else:
        with interception.hold_key("ctrl"):
            interception.press("z")
        with interception.hold_key("ctrl"):
            interception.press("z")
        zoom_out()
        print("HUD enabled")
