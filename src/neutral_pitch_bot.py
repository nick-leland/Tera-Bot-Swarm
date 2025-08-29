import time
import os
import cv2
import numpy as np
import sys
import ctypes

from interception_commands import zoom_out, toggle_hud

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


try:
    from skimage.metrics import structural_similarity as ssim
except ImportError:
    ssim = None  # we’ll fall back to a simpler metric


def latest_file(path):
    files = [os.path.join(path, f) for f in os.listdir(path)]
    files = [f for f in files if os.path.isfile(f)]
    return max(files, key=os.path.getmtime) if files else None


def wait_for_new_file(path, prev_path, timeout=5.0, poll=0.05):
    """Wait until a file newer than prev_path appears; return its path."""
    start = time.time()
    prev_mtime = os.path.getmtime(prev_path) if prev_path and os.path.exists(prev_path) else 0
    while time.time() - start < timeout:
        cand = latest_file(path)
        if cand and os.path.getmtime(cand) > prev_mtime:
            return cand
        time.sleep(poll)
    # fallback: return whatever is latest even if mtime didn’t advance (rare)
    return latest_file(path)


def preprocess(img):
    # central crop to avoid HUD/noise; tune these as needed
    h, w = img.shape[:2]
    y1, y2 = int(0.30 * h), int(0.70 * h)
    x1, x2 = int(0.30 * w), int(0.70 * w)
    roi = img[y1:y2, x1:x2]

    gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (5, 5), 1.0)
    gray = cv2.resize(gray, (320, 180), interpolation=cv2.INTER_AREA)
    return gray


def compare_frames(img_a, img_b):
    """Return similarity score in [0,1], higher = more similar."""
    A = preprocess(img_a)
    B = preprocess(img_b)
    if ssim is not None:
        score = ssim(A, B, data_range=255)
        return float(score)
    # fallback: normalized cross-correlation on zero-mean arrays
    A = A.astype(np.float32)
    B = B.astype(np.float32)
    A -= A.mean()
    B -= B.mean()
    denom = (A.std() * B.std()) + 1e-6
    return float((A * B).mean() / denom)


def at_clamp(cur_img, make_step_fn, grab_img_fn, CONSEC_REQUIRED, FRAME_DELAY, WRITE_WAIT, SIM_THRESHOLD):
    """
    Nudge in the 'current' direction and see if additional input keeps the
    similarity high for CONSEC_REQUIRED frames. Return True if clamped.
    make_step_fn(): applies one small step in the intended direction.
    grab_img_fn(): returns (path, image) of latest screenshot.
    """
    streak = 0
    last = cur_img
    for _ in range(CONSEC_REQUIRED + 2):
        make_step_fn()
        time.sleep(FRAME_DELAY)
        interception.press("printscreen")
        time.sleep(WRITE_WAIT)
        _, img = grab_img_fn()
        score = compare_frames(last, img)
        if score >= SIM_THRESHOLD:
            streak += 1
            if streak >= CONSEC_REQUIRED:
                return True, img
        else:
            return False, img
        last = img
    return True, last  # very stable → clamped


def measure_pitch_range_counts(grab_img_fn, CONSEC_REQUIRED, FRAME_DELAY, WRITE_WAIT, SIM_THRESHOLD):
    """
    Returns total vertical range in 'interception pixels' (counts) between top and bottom clamps.
    Assumes big move to rough top already happened. Confirms top, then walks down to bottom.
    """

    # 1) Ensure at (or snap to) TOP clamp
    # First screenshot baseline
    interception.press("printscreen")
    time.sleep(WRITE_WAIT)
    cur_path, cur_img = grab_img_fn()

    # Try nudging upward (+dy) to confirm we're clamped at top.
    def nudge_up():
        interception.move_relative(0, +1)   # +dy = up
    clamped, cur_img = at_clamp(cur_img, nudge_up, grab_img_fn, CONSEC_REQUIRED, FRAME_DELAY, WRITE_WAIT, SIM_THRESHOLD)
    if not clamped:
        # Not yet clamped: push farther up hard, then confirm again
        interception.move_relative(0, +500)  # shove up
        time.sleep(0.1)
        clamped, cur_img = at_clamp(cur_img, nudge_up, grab_img_fn, CONSEC_REQUIRED, FRAME_DELAY, WRITE_WAIT, SIM_THRESHOLD)

    # 2) Walk DOWN step-by-step until we hit BOTTOM clamp
    total_steps = 0
    nochange_streak = 0

    while True:
        # step down by one "interception pixel"
        interception.move_relative(0, STEP_DY)  # STEP_DY = -1
        total_steps += 1

        time.sleep(FRAME_DELAY)
        interception.press("printscreen")
        time.sleep(WRITE_WAIT)
        new_path, new_img = grab_img_fn()

        score = compare_frames(cur_img, new_img)
        if score >= SIM_THRESHOLD:
            nochange_streak += 1
            if nochange_streak >= CONSEC_REQUIRED:
                # We've been clamped for a few frames: subtract the overshoot
                effective_range = total_steps - CONSEC_REQUIRED
                return max(effective_range, 0)
        else:
            nochange_streak = 0

        # advance
        cur_img = new_img


def _latest_path_and_image():
    p = latest_file(TERA_SS_DIR)
    return p, cv2.imread(p)


# Tunables (same as before; adjust if needed)
SIM_THRESHOLD = 0.995
CONSEC_REQUIRED = 5
FRAME_DELAY = 0.10   # time between move and screenshot
WRITE_WAIT = 0.15   # after printscreen, let the file land
MAX_STEPS_PER_SWEEP = 200000  # safety cap
TERA_SS_DIR = r"C:\Users\user\Pictures\TERA_ScreenShots"


def grab_new(cur_path):
    interception.press("printscreen")
    time.sleep(WRITE_WAIT)
    new_path = wait_for_new_file(TERA_SS_DIR, cur_path, timeout=3.0)
    img = cv2.imread(new_path)
    return new_path, img


def reach_clamp(cur_path, cur_img, step_dy):
    """
    From the current position, walk in 'step_dy' (+1 up, -1 down) until the clamp is detected.
    Returns: (effective_steps_to_clamp, new_path, new_img)
    'effective_steps_to_clamp' subtracts the debounce streak so you don't overcount overshoot.
    """
    streak = 0
    steps = 0
    last_img = cur_img
    last_path = cur_path

    while steps < MAX_STEPS_PER_SWEEP:
        interception.move_relative(0, step_dy)
        steps += 1
        time.sleep(FRAME_DELAY)

        new_path, new_img = grab_new(last_path)
        score = compare_frames(last_img, new_img)

        if score >= SIM_THRESHOLD:
            streak += 1
            if streak >= CONSEC_REQUIRED:
                effective = steps - CONSEC_REQUIRED
                # cleanup the last old file if it’s different
                try:
                    if last_path and last_path != new_path and os.path.exists(last_path):
                        os.remove(last_path)
                except Exception:
                    pass
                return max(effective, 0), new_path, new_img
        else:
            streak = 0

        # progress state & cleanup
        try:
            if last_path and last_path != new_path and os.path.exists(last_path):
                os.remove(last_path)
        except Exception:
            pass
        last_img = new_img
        last_path = new_path

    raise RuntimeError("Clamp not found within MAX_STEPS_PER_SWEEP; adjust thresholds or step timing.")


def measure_start_offset_and_range():
    """
    Measures:
      - starting_offset_from_top: counts from current position up to top clamp (no hidden shove)
      - total_range: counts from top to bottom clamp
    """
    # Baseline screenshot (if none exists yet, take one)
    cur_path = latest_file(TERA_SS_DIR)
    if not cur_path:
        interception.press("printscreen")
        time.sleep(WRITE_WAIT)
        cur_path = latest_file(TERA_SS_DIR)
    cur_img = cv2.imread(cur_path)

    # 1) From current position, go UP to the top clamp
    up_eff, cur_path, cur_img = reach_clamp(cur_path, cur_img, step_dy=+1)
    starting_offset_from_top = up_eff

    # 2) From top clamp, go DOWN to the bottom clamp
    down_eff, cur_path, cur_img = reach_clamp(cur_path, cur_img, step_dy=-1)
    total_range = down_eff

    return starting_offset_from_top, total_range


if __name__ == "__main__":
    print("Starting bot")
    beziercurve.set_default_params(curve_params)
    time.sleep(10)

    zoom_out()
    toggle_hud(mode=True)

    # IMPORTANT: no shove here; we start exactly where the camera is now.

    start_from_top, total_range = measure_start_offset_and_range()
    start_from_bottom = max(total_range - start_from_top, 0)
    pct = (start_from_top / total_range * 100.0) if total_range > 0 else float('nan')

    print(f"Starting position: {start_from_top} counts from TOP "
          f"({pct:.2f}% of total range).")
    print(f"Starting position from BOTTOM: {start_from_bottom} counts.")
    print(f"Total vertical (pitch) range: {total_range} counts.")

    toggle_hud(mode=False)
