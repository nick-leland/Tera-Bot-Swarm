import time
import os
import cv2
import numpy as np

from interception_init import interception, beziercurve, curve_params
from interception_commands import zoom_out, toggle_hud


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


# --- Tunables (keep consistent with your previous helpers) ---
SIM_THRESHOLD      = 0.995
CONSEC_REQUIRED    = 5
FRAME_DELAY        = 0.10     # wait after move before screenshot
WRITE_WAIT         = 0.15     # wait after printscreen for file write
MAX_STEPS_PER_SWEEP = 200000  # safety cap

TERA_SS_DIR = r"C:\Users\user\Pictures\TERA_ScreenShots"


def grab_new(prev_path):
    interception.press("printscreen")
    time.sleep(WRITE_WAIT)
    new_path = wait_for_new_file(TERA_SS_DIR, prev_path, timeout=3.0)
    return new_path, cv2.imread(new_path)


def steps_to_bottom_from_current(restore=False, cleanup=True):
    """
    From *current* camera pitch, step downward (dy=-1) until bottom clamp.
    Returns the effective number of counts ("interception pixels") from neutral to bottom.
    If restore=True, moves back up by that many counts to return to the starting pitch.
    """
    # Ensure we have a baseline frame
    cur_path = latest_file(TERA_SS_DIR)
    if not cur_path:
        interception.press("printscreen")
        time.sleep(WRITE_WAIT)
        cur_path = latest_file(TERA_SS_DIR)
    cur_img = cv2.imread(cur_path)

    steps = 0
    streak = 0
    last_path, last_img = cur_path, cur_img

    while steps < MAX_STEPS_PER_SWEEP:
        # One-count step downward
        interception.move_relative(0, -1)
        steps += 1

        time.sleep(FRAME_DELAY)
        new_path, new_img = grab_new(last_path)

        score = compare_frames(last_img, new_img)
        if score >= SIM_THRESHOLD:
            streak += 1
            if streak >= CONSEC_REQUIRED:
                effective = max(steps - CONSEC_REQUIRED, 0)

                if restore and effective > 0:
                    # Go back to the exact starting pitch
                    interception.move_relative(0, +effective)
                    time.sleep(0.05)

                # Optional: clean up older screenshot
                if cleanup:
                    try:
                        if last_path and last_path != new_path and os.path.exists(last_path):
                            os.remove(last_path)
                    except Exception:
                        pass

                return effective
        else:
            streak = 0

        # Advance & clean up
        if cleanup:
            try:
                if last_path and last_path != new_path and os.path.exists(last_path):
                    os.remove(last_path)
            except Exception:
                pass

        last_path, last_img = new_path, new_img

    raise RuntimeError("Bottom clamp not detected; adjust SIM_THRESHOLD/CONSEC_REQUIRED or timing.")


if __name__ == "__main__":
    print("Starting bot")
    beziercurve.set_default_params(curve_params)
    time.sleep(10)

    zoom_out()
    toggle_hud(mode=True)   # keep visuals stable

    # Single-direction measure: neutral -> bottom only
    distance_to_bottom = steps_to_bottom_from_current(restore=False)

    print(f"Distance from current (neutral) to bottom clamp: {distance_to_bottom} counts")

    toggle_hud(mode=False)
