/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import * as Cesium from 'cesium';

export const WINDOW_DAYS = 30;

export const ROCKET_MISSION_AMBIENT_OVERLAY_SOURCE_ID = 'rocket-missions';

export const ROCKET_MISSION_SELECTED_OVERLAY_SOURCE_ID =
  'rocket-mission-selected';

export const ROCKET_MISSION_AMBIENT_OVERLAY_COHORT_LIMIT = 48;

export const ROCKET_MISSION_AMBIENT_OVERLAY_COLLISION_CAPACITY = 24;

export const ROCKET_MISSION_SELECTED_OVERLAY_SOURCE_OPTIONS = Object.freeze({
  cohortLimit: 12,
  collisionCapacity: 0,
  moving: true,
  solveIntervalMs: 0,
});

export const ROCKET_MISSION_AMBIENT_OVERLAY_SOURCE_OPTIONS = Object.freeze({
  cohortLimit: ROCKET_MISSION_AMBIENT_OVERLAY_COHORT_LIMIT,
  collisionCapacity: ROCKET_MISSION_AMBIENT_OVERLAY_COLLISION_CAPACITY,
  moving: false,
});

export const REPLAY_ASCENT_FALLBACK_SEC = 12;

export const REPLAY_ASCENT_MIN_SEC = 8;

export const REPLAY_ASCENT_MAX_SEC = 36;

export const REPLAY_ORBIT_DURATION_SEC = 28;

export const REPLAY_COUNTDOWN_DURATION_SEC = 10;

export const REPLAY_TILE_SETTLE_DELAY_SEC = 5;

export const REPLAY_INITIAL_RANGE_M = 3500;

export const REPLAY_LOCAL_MAX_RANGE_M = 900000;

export const REPLAY_CONTEXT_MAX_RANGE_M = 2400000;

export const REPLAY_CONTEXT_ALTITUDE_END_M = 420000;

export const REPLAY_ORBIT_GLOBE_RANGE_M = 18000000;

export const REPLAY_ORBIT_PULLBACK_FRACTION = 0.2;

export const REPLAY_ASCENT_CAMERA_OFFSET_RAD = Cesium.Math.toRadians(30);

export const REPLAY_ORBIT_CAMERA_OFFSET_RAD = Cesium.Math.toRadians(45);

export const REPLAY_ORBIT_FRAME_CENTER_BLEND = 0.45;

export const REPLAY_SPEED_MIN = 0.25;

export const REPLAY_SPEED_MAX = 4;

export const REPLAY_SPEED_STEP = 0.25;

export const MAX_POST_TLE_RETRIES = 1;

export const POST_TLE_RETRY_DELAY_MS = 1500;

export const EARTH_ROTATION_RAD_PER_SEC = Cesium.Math.TWO_PI / 86164.0905;

export const PROJECTED_ASCENT_ROTATION_SEC = 600;

export const STAGE_REENTRY_ALTITUDE_M = 100000;

export const MISSION_CLOSE_VIEW_RANGE_M = 180000;

export const MISSION_GLOBE_VIEW_RANGE_M = 5000000;

export const MISSION_FOCUS_RANGE_M = 12000;

export const SATELLITE_STANDALONE_DEFAULTS = {
  catalog: 'core',
  showPoints: true,
  showOrbits: true,
};

export const MISSION_ORBIT_PATTERN_GROUPS = 4;

export const MISSION_ORBIT_DASHES_PER_GROUP = 100;

export const LAUNCH_PAD_ZONE_RADIUS_M = 500;

export const LAUNCH_PAD_ZONE_MAX_CAMERA_HEIGHT_M = 120000;

export const LAUNCH_PAD_ZONE_MAX_CAMERA_DISTANCE_M = 180000;

export const TRAJECTORY_STAGE_COLORS = [
  '#ff9f43',
  '#ff66c4',
  '#a78bfa',
  '#7bed9f',
  '#ffd166',
  '#60a5fa',
];
