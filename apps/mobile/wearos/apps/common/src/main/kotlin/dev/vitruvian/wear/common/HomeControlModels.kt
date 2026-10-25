// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

package dev.vitruvian.wear.common

/**
 * Speaker broadcast room targets and Roborock vacuum actions for `home-control`.
 *
 * Maps wrist selections directly to the CLI/bridge contracts used by `speaker-broadcast`
 * (`~/.gemini/speaker_broadcast.json`) and `apps/mcp/roborock`.
 */
public enum class SpeakerRoom(
    public val targetId: String,
    public val displayName: String,
    public val shortCode: String,
) {
  LAKE_OFFICE("lake_office", "Lake Office", "OFC"),
  MASTER_BEDROOM("master_bedroom", "Master Bedroom", "MBR"),
  LIVING_ROOM("living_room", "Living Room", "LIV"),
  KITCHEN("kitchen", "Kitchen", "KIT"),
  DINING_ROOM("dining_room", "Dining Room", "DIN"),
  GUEST_ROOM("guest_room", "Guest Room", "GST"),
  ALL_SPEAKERS("all", "All Speakers", "ALL"),
  MUTE("mute", "Quiet / Off", "OFF");

  public fun toSpeakerBroadcastCliCommand(): String =
      if (this == MUTE) {
        "speaker-broadcast --disable"
      } else {
        "speaker-broadcast --enable --set-target $targetId"
      }
}

public enum class RoborockAction(
    public val actionId: String,
    public val label: String,
    public val roomSegmentId: Int? = null,
) {
  CLEAN_OFFICE("clean_room_office", "Clean Office", 16),
  CLEAN_KITCHEN("clean_room_kitchen", "Clean Kitchen", 17),
  CLEAN_LIVING_ROOM("clean_room_living", "Clean Living", 18),
  START_FULL_CLEAN("start_clean", "Full Clean", null),
  WASH_MOP("wash_mop", "Wash Mop", null),
  PAUSE("pause", "Pause", null),
  RETURN_TO_DOCK("return_to_dock", "Dock", null);

  public fun toJsonPayload(): String = buildString {
    append("""{"tool":"roborock","action":"""")
    append(RemoteWireCodec.escapeJson(actionId))
    append('"')
    if (roomSegmentId != null) {
      append(""","segmentId":""")
      append(roomSegmentId)
    }
    append('}')
  }
}
