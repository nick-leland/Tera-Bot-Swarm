import math
import time

from interception_init import interception

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
