"""Load interception.dll, then import and initialize the interception package.

Import this module before any code that imports `interception`, or use:

    from interception_init import interception, beziercurve, curve_params
"""

import os
import sys
import ctypes

DLL_DIR = r"C:\Tools\Interception\library\x64"
_dll_path = os.path.join(DLL_DIR, "interception.dll")

if not os.path.exists(_dll_path):
    sys.exit(f"interception.dll not found in {DLL_DIR}")

os.add_dll_directory(DLL_DIR)
ctypes.WinDLL(_dll_path)

import interception  # noqa: E402
from interception import beziercurve  # noqa: E402

interception.auto_capture_devices()
curve_params = beziercurve.BezierCurveParams()
