from __future__ import annotations

import json
import math
import threading
import time
from dataclasses import dataclass
from typing import Dict, Optional, Tuple

try:
    import zmq  # type: ignore
    HAS_ZMQ = True
except Exception:
    HAS_ZMQ = False

from vpython import canvas, sphere, arrow, vector, color  # type: ignore
from vpython import button  # type: ignore


# =========================
# Configuration
# =========================
USE_LIVE_FEED = False  # Toggle ZeroMQ live stream
ZMQ_ENDPOINT = "tcp://127.0.0.1:3000"

# Core timing (simulation tick, aligned to game packet cadence)
PACKET_DT_SECONDS = 0.05  # 50 ms

# Control constraint: map max mouse px/sec
# to a yaw rate (rad/sec)
# Start with a direct cap (rad/sec); later, map from px/sec via sensitivity.
MAX_YAW_RATE_RAD_PER_SEC = math.pi  # tune me

# Scale factor used elsewhere in the project
TERA_UNITS_PER_METER = 16.49


# =========================
# Data structures
# =========================
@dataclass
class Position3D:
    x: float
    y: float
    z: float

    def to_v(self) -> vector:
        return vector(self.x, self.y, self.z)


@dataclass
class Entity:
    name: str
    type: str
    position: Position3D


@dataclass
class PlayerState:
    position: Position3D
    yaw_radians: float
    pitch_radians: float


def clamp(value: float, min_value: float, max_value: float) -> float:
    if value < min_value:
        return min_value
    if value > max_value:
        return max_value
    return value


def angle_diff(current: float, target: float) -> float:
    # Smallest signed difference in (-pi, pi]
    d = (target - current + math.pi) % (2 * math.pi) - math.pi
    return d if d != -math.pi else math.pi


def forward_from_angles(yaw: float, pitch: float) -> vector:
    # Standard spherical mapping: yaw around Y, pitch about XZ plane
    cp = math.cos(pitch)
    return vector(math.cos(yaw) * cp, math.sin(pitch), math.sin(yaw) * cp)


def clamp_canvas_zoom(
    c: canvas,
    min_range: float = 0.5,
    max_range: float = 200.0,
) -> None:
    """Clamp canvas.range to avoid near-plane clipping when zooming.

    If range is a vector, clamp by its minimum component and set scalar range.
    """
    r = c.range
    try:
        # r may be a vector or a scalar
        if hasattr(r, "x"):
            scalar = min(float(r.x), float(r.y), float(r.z))
        else:
            scalar = float(r)
    except Exception:
        scalar = 1.0
    scalar = clamp(scalar, min_range, max_range)
    c.range = scalar


#############################
# Controllers & Scenarios   #
#############################

class Controller:
    """Compute next yaw given current and desired yaw.

    Implementations may keep internal state (e.g., yaw rate).
    """

    def update(self, current: float, desired: float, dt: float) -> float:
        raise NotImplementedError


class RateLimitedPController(Controller):
    """Simple P controller with step rate limit.

    step = clamp(kp * angle_error, +/- max_rate * dt)
    """

    def __init__(self, kp: float = 1.0, max_rate: float = None) -> None:
        self.kp = kp
        self.max_rate = (
            MAX_YAW_RATE_RAD_PER_SEC if max_rate is None else max_rate
        )

    def update(self, current: float, desired: float, dt: float) -> float:
        err = angle_diff(current, desired)
        cmd = self.kp * err
        max_step = self.max_rate * dt
        step = clamp(cmd, -max_step, max_step)
        return current + step


class SmoothPDController(Controller):
    """Critically damped PD-like controller with internal yaw rate.

    yaw_rate_dot = w^2 * err - 2*z*w * yaw_rate
    yaw_rate     = yaw_rate + yaw_rate_dot * dt
    current      = current + yaw_rate * dt
    """

    def __init__(
        self,
        natural_freq: float = 8.0,
        damping_ratio: float = 1.0,
        max_rate: float = None,
    ) -> None:
        self.wn = natural_freq
        self.zeta = damping_ratio
        self.yaw_rate = 0.0
        self.max_rate = (
            MAX_YAW_RATE_RAD_PER_SEC if max_rate is None else max_rate
        )

    def update(self, current: float, desired: float, dt: float) -> float:
        err = angle_diff(current, desired)
        yaw_rate_dot = (
            (self.wn * self.wn) * err
            - 2.0 * self.zeta * self.wn * self.yaw_rate
        )
        self.yaw_rate += yaw_rate_dot * dt
        self.yaw_rate = clamp(self.yaw_rate, -self.max_rate, self.max_rate)
        return current + self.yaw_rate * dt


class Scenario:
    """Provide enemy position (and optionally player motion) over time."""

    def reset(self) -> None:
        pass

    def enemy_position(self, t: float) -> Position3D:
        raise NotImplementedError


class CircleEnemyScenario(Scenario):
    def __init__(
        self,
        radius: float = 10.0,
        angular_speed: float = 0.5,
    ) -> None:
        self.radius = radius
        self.omega = angular_speed

    def enemy_position(self, t: float) -> Position3D:
        return Position3D(
            self.radius * math.cos(self.omega * t),
            0.0,
            self.radius * math.sin(self.omega * t),
        )


class KeyframedEnemyScenario(Scenario):
    """Linearly interpolate between time-keyed waypoints.

    waypoints: list of (time_seconds, Position3D)
    If loop is True, wraps time around the last key.
    """

    def __init__(
        self,
        waypoints: Tuple[Tuple[float, Position3D], ...],
        loop: bool = True,
    ) -> None:
        assert len(waypoints) >= 2
        self.waypoints = tuple(sorted(waypoints, key=lambda p: p[0]))
        self.loop = loop
        self.total = self.waypoints[-1][0]

    def enemy_position(self, t: float) -> Position3D:
        if self.loop and self.total > 0.0:
            t = t % self.total
        # find segment
        for i in range(len(self.waypoints) - 1):
            t0, p0 = self.waypoints[i]
            t1, p1 = self.waypoints[i + 1]
            if t0 <= t <= t1:
                u = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
                x = p0.x + (p1.x - p0.x) * u
                y = p0.y + (p1.y - p0.y) * u
                z = p0.z + (p1.z - p0.z) * u
                return Position3D(x, y, z)
        # out of range: clamp to last
        return self.waypoints[-1][1]


class HelixEnemyScenario(Scenario):
    """3D helix motion for vertical testing."""

    def __init__(
        self,
        radius: float = 8.0,
        angular_speed: float = 0.6,
        vertical_speed: float = 1.0,
    ) -> None:
        self.radius = radius
        self.omega = angular_speed
        self.vy = vertical_speed

    def enemy_position(self, t: float) -> Position3D:
        return Position3D(
            self.radius * math.cos(self.omega * t),
            self.vy * t,
            self.radius * math.sin(self.omega * t),
        )


# Example scripts: pair a scenario with a controller and parameters
SELECTED_SCRIPT = "circle_p"

SCRIPTS: Dict[str, Dict[str, object]] = {
    "circle_p": {
        "scenario": CircleEnemyScenario(radius=12.0, angular_speed=0.5),
        "controller_yaw": RateLimitedPController(kp=1.0),
        "controller_pitch": RateLimitedPController(
            kp=1.0,
            max_rate=math.pi / 2,
        ),
    },
    "keyframe_smooth": {
        "scenario": KeyframedEnemyScenario(
            waypoints=(
                (0.0, Position3D(8.0, 0.0, -6.0)),
                (2.0, Position3D(6.0, 0.0, 6.0)),
                (5.0, Position3D(-10.0, 0.0, 0.0)),
                (8.0, Position3D(8.0, 0.0, -6.0)),
            ),
            loop=True,
        ),
        "controller_yaw": SmoothPDController(
            natural_freq=9.0, damping_ratio=1.0
        ),
        "controller_pitch": SmoothPDController(
            natural_freq=6.0, damping_ratio=1.0, max_rate=math.pi / 2
        ),
    },
    "helix_smooth": {
        "scenario": HelixEnemyScenario(
            radius=8.0, angular_speed=0.6, vertical_speed=1.0
        ),
        "controller_yaw": SmoothPDController(
            natural_freq=9.0, damping_ratio=1.0
        ),
        "controller_pitch": SmoothPDController(
            natural_freq=7.0, damping_ratio=1.0, max_rate=math.pi / 2
        ),
    },
}


class HelixEnemyScenario(Scenario):
    """3D helix motion for vertical testing."""

    def __init__(
        self,
        radius: float = 8.0,
        angular_speed: float = 0.6,
        vertical_speed: float = 1.0,
    ) -> None:
        self.radius = radius
        self.omega = angular_speed
        self.vy = vertical_speed

    def enemy_position(self, t: float) -> Position3D:
        return Position3D(
            self.radius * math.cos(self.omega * t),
            self.vy * t,
            self.radius * math.sin(self.omega * t),
        )


class LiveFeed:
    """Background ZeroMQ subscriber updating shared state for visualization.

    Expects JSON messages with at least keys:
      - player: { position: {x, y, z}, direction?: float }
      - entities: [ { name, type, position: {x, y, z} }, ... ]
    """

    def __init__(self, endpoint: str) -> None:
        if not HAS_ZMQ:
            raise RuntimeError("pyzmq not installed but USE_LIVE_FEED=True")
        self.endpoint = endpoint
        self._lock = threading.Lock()
        self._latest: Dict[str, object] = {}
        self._running = False
        self._thread: Optional[threading.Thread] = None

    def start(self) -> None:
        if self._running:
            return
        self._running = True
        self._thread = threading.Thread(
            target=self._run,
            name="LiveFeedThread",
            daemon=True,
        )
        self._thread.start()

    def stop(self) -> None:
        self._running = False
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=1.0)

    def snapshot(self) -> Dict[str, object]:
        with self._lock:
            return dict(self._latest)

    def _run(self) -> None:
        context = zmq.Context.instance()
        socket = context.socket(zmq.SUB)
        socket.connect(self.endpoint)
        socket.setsockopt(zmq.SUBSCRIBE, b"")
        socket.RCVTIMEO = 250  # ms

        while self._running:
            try:
                msg = socket.recv_string()
            except zmq.error.Again:
                continue
            except Exception:
                # Backoff briefly on unexpected errors
                time.sleep(0.05)
                continue

            try:
                data = json.loads(msg)
            except Exception:
                continue

            with self._lock:
                self._latest = data


def find_nearest_enemy(
    player_pos: Position3D,
    entities: Tuple[Entity, ...],
) -> Optional[Entity]:
    best: Optional[Tuple[float, Entity]] = None
    for e in entities:
        dx = e.position.x - player_pos.x
        dy = e.position.y - player_pos.y
        dz = e.position.z - player_pos.z
        dist_sq = dx * dx + dy * dy + dz * dz
        if best is None or dist_sq < best[0]:
            best = (dist_sq, e)
    return best[1] if best else None


def setup_canvases() -> Tuple[canvas, canvas]:
    world = canvas(
        title="World (Top-Down)",
        width=700,
        height=700,
        background=color.gray(0.1),
    )
    fpv = canvas(
        title="FPV (Player View)",
        width=700,
        height=420,
        background=color.black,
    )

    world.camera.pos = vector(0.0, 30.0, 0.0)
    world.camera.axis = vector(0.0, -1.0, 0.0)
    world.up = vector(0.0, 0.0, -1.0)

    return world, fpv


def main() -> None:
    # Initial simulated state
    player = PlayerState(
        position=Position3D(0.0, 0.0, 0.0),
        yaw_radians=0.0,
        pitch_radians=0.0,
    )
    # Create scenario & controller for scripted mode
    script_cfg = SCRIPTS.get(SELECTED_SCRIPT, SCRIPTS["circle_p"])
    scenario: Scenario = script_cfg["scenario"]  # type: ignore
    controller_yaw: Controller = script_cfg["controller_yaw"]  # type: ignore
    controller_pitch: Controller = script_cfg[
        "controller_pitch"
    ]  # type: ignore
    enemy = Entity(
        name="enemy",
        type="mob",
        position=scenario.enemy_position(0.0),
    )

    # Optional ZeroMQ live feed
    live: Optional[LiveFeed] = None
    if USE_LIVE_FEED:
        if not HAS_ZMQ:
            raise RuntimeError(
                "USE_LIVE_FEED=True but pyzmq is not installed in this env"
            )
        live = LiveFeed(ZMQ_ENDPOINT)
        live.start()

    # Visuals
    world, fpv = setup_canvases()
    player_s = sphere(
        canvas=world,
        pos=player.position.to_v(),
        radius=0.35,
        color=color.cyan,
        shininess=0.6,
    )
    enemy_s = sphere(
        canvas=world,
        pos=enemy.position.to_v(),
        radius=0.35,
        color=color.red,
        shininess=0.6,
    )
    # FPV canvas objects: don't render the player body to avoid occlusion
    enemy_s_fpv = sphere(
        canvas=fpv,
        pos=enemy.position.to_v(),
        radius=0.35,
        color=color.red,
        shininess=0.6,
    )
    p_fwd = arrow(
        canvas=world,
        pos=player_s.pos,
        axis=forward_from_angles(player.yaw_radians, player.pitch_radians),
        color=color.yellow,
        shaftwidth=0.06,
    )
    e_fwd = arrow(
        canvas=world,
        pos=enemy_s.pos,
        axis=forward_from_angles(0.0, 0.0),
        color=color.orange,
        shaftwidth=0.06,
    )

    def update_fpv_camera() -> None:
        eye_h = 1.6
        fwd = forward_from_angles(player.yaw_radians, player.pitch_radians)
        fpv.camera.pos = player_s.pos + vector(0.0, eye_h, 0.0)
        # Look several units ahead to avoid near-plane/zero-length axis issues
        fpv.camera.axis = fwd * 6.0
        fpv.center = fpv.camera.pos + fwd * 6.0
        fpv.up = vector(0.0, 1.0, 0.0)

    update_fpv_camera()

    # UI: camera snap buttons (attached to the `world` canvas)
    def snap_top_down() -> None:
        world.camera.pos = player_s.pos + vector(0.0, 30.0, 0.0)
        world.camera.axis = vector(0.0, -1.0, 0.0)
        world.up = vector(0.0, 0.0, -1.0)

    def snap_xz() -> None:
        # Side view (XZ plane), looking along +Z
        world.camera.pos = player_s.pos + vector(0.0, 10.0, -25.0)
        world.camera.axis = vector(0.0, -0.4, 1.0)
        world.up = vector(0.0, 1.0, 0.0)

    def snap_xy() -> None:
        # Front view (XY plane), looking along +Y
        world.camera.pos = player_s.pos + vector(0.0, -25.0, 0.0)
        world.camera.axis = vector(0.0, 1.0, 0.0)
        world.up = vector(0.0, 0.0, 1.0)

    def snap_yz() -> None:
        # Right view (YZ plane), looking along +X
        world.camera.pos = player_s.pos + vector(-25.0, 0.0, 0.0)
        world.camera.axis = vector(1.0, 0.0, 0.0)
        world.up = vector(0.0, 1.0, 0.0)

    # VPython buttons render on the most recently activated canvas
    world.append_to_caption("\nCamera snaps: ")
    button(bind=lambda: snap_top_down(), text="Top-Down")
    world.append_to_caption("  ")
    button(bind=lambda: snap_xz(), text="XZ")
    world.append_to_caption("  ")
    button(bind=lambda: snap_xy(), text="XY")
    world.append_to_caption("  ")
    button(bind=lambda: snap_yz(), text="YZ")
    world.append_to_caption("\n\n")

    t = 0.0
    try:
        while True:
            # Rate limit to the game packet cadence
            from vpython import rate  # local import
            rate(int(1.0 / PACKET_DT_SECONDS))

            # Live feed snapshot → update player/enemy if available
            if live is not None:
                snap = live.snapshot()
                # player
                p = snap.get("player") if isinstance(snap, dict) else None
                if isinstance(p, dict):
                    pos = p.get("position")
                    if isinstance(pos, dict):
                        player.position = Position3D(
                            float(pos.get("x", 0.0)),
                            float(pos.get("y", 0.0)),
                            float(pos.get("z", 0.0)),
                        )
                    if "direction" in p:
                        try:
                            player.yaw_radians = float(
                                p.get("direction") or 0.0
                            )
                        except Exception:
                            pass
                    if "pitch" in p:
                        try:
                            player.pitch_radians = float(p.get("pitch") or 0.0)
                        except Exception:
                            pass
                # enemies → pick nearest
                ents_list = []
                entities_raw = (
                    snap.get("entities") if isinstance(snap, dict) else None
                )
                for ed in (entities_raw or []):
                    if not isinstance(ed, dict):
                        continue
                    pos = ed.get("position") or {}
                    try:
                        e = Entity(
                            name=str(ed.get("name", "enemy")),
                            type=str(ed.get("type", "mob")),
                            position=Position3D(
                                float(pos.get("x", 0.0)),
                                float(pos.get("y", 0.0)),
                                float(pos.get("z", 0.0)),
                            ),
                        )
                        ents_list.append(e)
                    except Exception:
                        continue
                if ents_list:
                    target = find_nearest_enemy(
                        player.position,
                        tuple(ents_list),
                    )
                    if target is not None:
                        enemy = target

            else:
                # Scripted scenario
                t += PACKET_DT_SECONDS
                enemy.position = scenario.enemy_position(t)

            # Desired yaw/pitch to face enemy in 3D
            dx = enemy.position.x - player.position.x
            dy = enemy.position.y - player.position.y
            dz = enemy.position.z - player.position.z
            desired_yaw = math.atan2(dz, dx)
            dist_xz = math.hypot(dx, dz)
            desired_pitch = math.atan2(dy, dist_xz)

            # Apply controllers (yaw and pitch)
            player.yaw_radians = controller_yaw.update(
                player.yaw_radians, desired_yaw, PACKET_DT_SECONDS
            )
            player.pitch_radians = controller_pitch.update(
                player.pitch_radians, desired_pitch, PACKET_DT_SECONDS
            )
            # Clamp pitch to avoid flipping (±89°)
            player.pitch_radians = clamp(
                player.pitch_radians,
                -math.radians(89.0),
                math.radians(89.0),
            )

            # Optional: simulate player movement here if desired
            # player.position.x += (
            #     math.cos(player.yaw_radians) * 0.0 * PACKET_DT_SECONDS
            # )
            # player.position.z += (
            #     math.sin(player.yaw_radians) * 0.0 * PACKET_DT_SECONDS
            # )

            # Update visuals
            player_s.pos = player.position.to_v()
            new_enemy_pos_v = enemy.position.to_v()
            enemy_s.pos = new_enemy_pos_v
            p_fwd.pos = player_s.pos
            p_fwd.axis = forward_from_angles(
                player.yaw_radians, player.pitch_radians
            )
            e_fwd.pos = enemy_s.pos
            e_fwd.axis = forward_from_angles(0.0, 0.0)

            update_fpv_camera()

            # Sync FPV scene objects
            enemy_s_fpv.pos = new_enemy_pos_v

            # Keep world view centered and clamp zoom to avoid disappearance
            world.center = player_s.pos
            clamp_canvas_zoom(world, min_range=0.6, max_range=300.0)
            clamp_canvas_zoom(fpv, min_range=0.6, max_range=50.0)

    except KeyboardInterrupt:
        pass
    finally:
        if live is not None:
            live.stop()


if __name__ == "__main__":
    main()
