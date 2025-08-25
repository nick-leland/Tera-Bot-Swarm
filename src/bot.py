import interception
from interception import beziercurve
import time
import math

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
    interception.write("/8 pos", 0.1)
    interception.press('enter')


if __name__ == "__main__":
    # interception.auto_capture_devices()
    # while True:
    #     interception.move_to(resolution[0] // 2, resolution[1] // 2)
    #     print(f"Moved to center: {resolution[0] // 2}, {resolution[1] // 2}")
    #     time.sleep(1)
    #     move_circle(100, 1)
    #     print("Moved in a circle")
    #     time.sleep(1)

    print("Starting bot")
    beziercurve.set_default_params(curve_params)
    time.sleep(10)
    print("Current position: ", interception.mouse_position())

    print("Trial 1")
    print_position_log()
    interception.move_relative(100, 0)
    interception.press('w')
    interception.press('s')

    print("Trial 2")
    print_position_log()
    interception.move_relative(100, 0)
    interception.press('w')
    interception.press('s')

    print("Trials complet")
