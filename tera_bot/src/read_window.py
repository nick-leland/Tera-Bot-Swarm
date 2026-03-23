import win32gui
import win32con
import win32api
import win32process
import win32event
import win32clipboard
import win32ui
import win32com.client
import pythoncom
from win32con import EVENT_SYSTEM_FOREGROUND
import time
import threading

from ctypes import windll, WINFUNCTYPE, c_void_p, c_int, c_uint, c_ulong
from ctypes.wintypes import MSG


def is_tera_window(window_title):
    """Check if the window title is related to TERA"""
    tera_windows = ["TERA"]
    return any(tera in window_title for tera in tera_windows)


def get_window_size(hwnd):
    """Get the window size (width and height)"""
    try:
        rect = win32gui.GetWindowRect(hwnd)
        width = rect[2] - rect[0]  # right - left
        height = rect[3] - rect[1]  # bottom - top
        return width, height
    except Exception as e:
        print(f"Error getting window size: {e}")
        return 0, 0


def get_window_info(hwnd):
    """Get comprehensive window information including title, class, and type"""
    try:
        title = win32gui.GetWindowText(hwnd)
        class_name = win32gui.GetClassName(hwnd)

        # Get window style to determine window type
        style = win32gui.GetWindowLong(hwnd, win32con.GWL_STYLE)
        ex_style = win32gui.GetWindowLong(hwnd, win32con.GWL_EXSTYLE)

        # Determine window type based on styles
        window_type = "Unknown"
        if style & win32con.WS_POPUP:
            window_type = "Popup"
        elif style & win32con.WS_CHILD:
            window_type = "Child"
        elif style & win32con.WS_OVERLAPPED:
            window_type = "Overlapped"
        elif style & win32con.WS_DLGFRAME:
            window_type = "Dialog"
        elif ex_style & win32con.WS_EX_TOOLWINDOW:
            window_type = "Tool Window"
        elif ex_style & win32con.WS_EX_APPWINDOW:
            window_type = "Application Window"
        else:
            window_type = "Standard Window"

        # Check if it's visible
        is_visible = win32gui.IsWindowVisible(hwnd)

        return {
            'hwnd': hwnd,
            'title': title,
            'class': class_name,
            'type': window_type,
            'visible': is_visible,
            'style': style,
            'ex_style': ex_style
        }
    except Exception as e:
        return {
            'hwnd': hwnd,
            'title': f"Error: {str(e)}",
            'class': "Unknown",
            'type': "Error",
            'visible': False,
            'style': 0,
            'ex_style': 0
        }


def get_window_name(hwnd):
    return win32gui.GetWindowText(hwnd)


def print_window_info(window_info):
    """Print formatted window information"""
    print(f"Window: {window_info['title']}")
    print(f"  Class: {window_info['class']}")
    print(f"  Type: {window_info['type']}")
    print(f"  Visible: {window_info['visible']}")
    print(f"  Handle: {window_info['hwnd']}")
    print("-" * 50)


def callback(hWinEventHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime):
    """Event-based callback for window changes"""
    if hwnd:
        window_title = get_window_name(hwnd)
        width, height = get_window_size(hwnd)
        print(f"Current: {window_title} ({width}x{height})")


def poll_active_window():
    """Polling function to continuously check active window"""
    last_hwnd = None
    last_tera_status = None

    while True:
        try:
            current_hwnd = win32gui.GetForegroundWindow()

            if current_hwnd != last_hwnd and current_hwnd:
                window_title = get_window_name(current_hwnd)
                current_tera_status = is_tera_window(window_title)

                # Only print if status changed
                if current_tera_status != last_tera_status:
                    width, height = get_window_size(current_hwnd)
                    if current_tera_status:
                        print(f"Now in TERA ({width}x{height})")
                    else:
                        print(f"Not in Tera - Current: {window_title} ({width}x{height})")
                    last_tera_status = current_tera_status

                last_hwnd = current_hwnd

            time.sleep(0.5)  # Poll every 500ms

        except Exception as e:
            print(f"Polling error: {e}")
            time.sleep(1)


if __name__ == "__main__":
    print("TERA Window Monitor Started")
    print("Press Ctrl+C to exit")
    print("==================================================")

    # Check initial window status
    current_hwnd = win32gui.GetForegroundWindow()
    current_window = get_window_name(current_hwnd)
    width, height = get_window_size(current_hwnd)
    print(f"Current: {current_window} ({width}x{height})")

    # Start polling thread poll_thread = threading.Thread(target=poll_active_window, daemon=True) poll_thread.start()
    user32 = windll.user32

    WinEventProcType = WINFUNCTYPE(
        None,  # Return type (void)
        c_void_p,  # hWinEventHook
        c_uint,    # event
        c_void_p,  # hwnd
        c_int,     # idObject
        c_int,     # idChild
        c_uint,    # dwEventThread
        c_ulong    # dwmsEventTime
    )

    # Create the callback function
    callback_func = WinEventProcType(callback)

    hook = user32.SetWinEventHook(
        EVENT_SYSTEM_FOREGROUND,
        EVENT_SYSTEM_FOREGROUND,
        0,
        callback_func,
        0,
        0,
        win32con.WINEVENT_OUTOFCONTEXT
    )

    # Main loop
    try:
        while True:
            time.sleep(1)  # Keep the main thread alive
            compare_hwnd = win32gui.GetForegroundWindow()
            compare_window = get_window_name(compare_hwnd)
            if current_window != compare_window:
                current_window = get_window_name(compare_hwnd)
                width, height = get_window_size(compare_hwnd)
                print(f"Current: {current_window} ({width}x{height})")

    except KeyboardInterrupt:
        print("\nShutting down...")
        if hook:
            user32.UnhookWinEvent(hook)
