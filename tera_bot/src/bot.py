import time
import math

from interception_init import interception, beziercurve, curve_params


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
    print_position_log()

    # Scroll out the maximum distance
    for i in range(20):
        interception.scroll("down")

    print("Trial 1")
    interception.move_relative(100, 0)
    interception.press('s')
    interception.press('w')
    print("Current position: ", interception.mouse_position())
    print_position_log()

    print("Trial 2")
    interception.move_relative(100, 0)
    interception.press('s')
    interception.press('w')
    print("Current position: ", interception.mouse_position())
    print_position_log()

    print("Trials complete")
