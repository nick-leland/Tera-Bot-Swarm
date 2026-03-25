import time
import os
from pathlib import Path
import numpy as np
from PIL import Image
from captcha_recognizer.slider import Slider

from interception_commands import move_mouse_to
from interception_init import interception

# Assuming Resolution is 1920x1080
image_left = 820
image_top = 536
image_right = 1110
image_bottom = 730


def solve_captcha(max_attempts: int = 3):
    attempts = 0

    move_mouse_to(0, 0)  # Move mouse to a corner
    # Take a screenshot of the screen with the captcha present
    interception.key_down("win")
    interception.press("printscreen")
    interception.key_up("win")
    time.sleep(0.3)  # let Windows write the file

    # Crop the screenshot to the size of the captcha
    screenshots_dir = Path.home() / "Pictures" / "Screenshots"
    latest = max(screenshots_dir.glob("*.png"), key=os.path.getmtime)
    img = Image.open(str(latest)).crop((image_left, image_top, image_right, image_bottom))

    # Pass the screenshot to the Captcha Solving Model
    image_array = np.array(img.convert('RGB'))
    Image.fromarray(image_array).save(screenshots_dir / "captcha.png")
    box, confidence = Slider().identify(source=image_array)
    print(f"Box: {box}, Confidence: {confidence}")

    if confidence < 0.5:
        print("Failed to solve captcha")
        return False

    # Compute the distance to drag the captcha square slider
    center_x = (box[0] + box[2]) / 2
    center_y = (box[1] + box[3]) / 2
    submission_arrow = (3, 140, 45, 182)
    center_x_base = (submission_arrow[0] + submission_arrow[2]) / 2
    center_y_base = (submission_arrow[1] + submission_arrow[3]) / 2
    pixel_movement = center_x_base - center_x

    # Convert from cropped captcha image to full screen size
    new_x_base = image_left + center_x_base
    new_y_base = image_top + center_y_base
    start_point = (new_x_base, new_y_base)
    end_point = (new_x_base - pixel_movement, new_y_base)

    # Drag with LMB (key_down("left") is the keyboard left-arrow key).
    move_mouse_to(start_point[0], start_point[1])
    time.sleep(1.0)
    with interception.hold_mouse("left"):
        time.sleep(0.05)
        move_mouse_to(end_point[0], end_point[1])
        time.sleep(0.05)

    # Optional: Screenshot and crop again
    # if model returns anything, this means that we failed the captcha
    # Repeat until pass
    pass


if __name__ == "__main__":
    solve_captcha()
