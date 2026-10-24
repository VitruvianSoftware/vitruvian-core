# Rolex Cosmograph Daytona Platinum (`Ref. 126506`) — Wear OS Watch Face

A Declarative Watch Face Format (WFF v2) watch face for the **Pixel Watch 4 (`kenari_lte`)**, modeled after the **Rolex Cosmograph Daytona in 950 Platinum (`Ref. 126506`)** with its signature Ice Blue sunray dial, Chestnut Brown Cerachrom tachymeter bezel, snailed chestnut-brown chronograph registers, and baguette-cut diamond hour markers.

## Preserved Pixel Watch 4 Functions & Complications

Every function from the original **Expedition (Vermillion, Layout 4)** watch face is integrated into the Daytona's chronograph architecture:

| Original Expedition Function | Provider / Source | Daytona Platinum Integration |
|---|---|---|
| **World Clock (AMS / UTC)** | `WorldClockProviderService` (`SHORT_TEXT`) | Curved 12 o'clock Oyster Perpetual aperture (`slotId="1"`) below `"COSMOGRAPH"` |
| **Heart Rate (`75 bpm`)** | Fitbit `OffloadableHeartRateComplicationDataSourceService` (`RANGED_VALUE`) | 9 o'clock snailed chronograph subdial (`slotId="2"`) with live analog needle (`[HEART_RATE]`) + digital BPM |
| **Watch Battery (`83%`)** | `[BATTERY_PERCENT]` WFF expression | Crimson lower register readout (`♥ 83%`) inside the 9 o'clock subdial |
| **Current Weather (`56°`)** | Pixel Weather `CWComplicationService` (`RANGED_VALUE`) | 3 o'clock snailed chronograph subdial (`slotId="3"`) with crimson gauge arc + temperature readout |
| **Daily Steps (`GOAL_PROGRESS`)** | Fitbit `OffloadableStepsComplicationDataSourceService` | 6 o'clock snailed chronograph subdial (`slotId="4"`) with analog progress needle (`[STEP_COUNT] / 10000`) + digital step count |
| **Sunrise / Sunset (`7:03 AM`)** | Pixel Weather `SolarComplicationService` (`SHORT_TEXT`) | 7:30 chestnut-framed solar capsule (`slotId="5"`) |
| **Day of Week + Date (`SAT 24`)** | `[DAY_OF_WEEK_S] [DAY]` WFF expression | 4:30 platinum-framed Cyclops calendar aperture |

## Build, Test, and Install

```sh
# Validate WFF XML schema, complication slots, and PNG asset dimensions:
bazel test //apps/mobile/wearos/faces/daytona-platinum:watchface_test

# Connect to Pixel Watch 4 over Wireless ADB and install the WFF APK:
bazel run //tools/adb-connect -- --device watch
bazel run //apps/mobile/wearos/faces/daytona-platinum:install
```
