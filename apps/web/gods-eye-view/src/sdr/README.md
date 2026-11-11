# Sdr

## Overview
Component package providing implementation for `apps/web/gods-eye-view/src/sdr`.

## Interface
- `[adsbDecoder.js:LOCAL_ADSB_STALE_MS]`
- `[adsbDecoder.js:modeSChecksum]`
- `[adsbDecoder.js:decodeAdsbMessage]`
- `[adsbDecoder.js:updateAircraftTrack]`
- `[adsbDecoder.js:pruneAircraftTracks]`
- `[adsbDecoder.js:extractAdsbMessages]`
- `[adsbDecoder.js:AdsbStreamDecoder]`
- `[controller.js:SDR_RECEIVER_PRESETS]`
- `[controller.js:SdrController]`
- `[gain.js:R820T_GAIN_STEPS_DB]`
- `[gain.js:SDR_GAIN_DEFAULTS]`
- `[gain.js:SDR_GAIN_STORAGE_KEY]`
- `[gain.js:normalizeSdrGain]`
- `[gain.js:readSdrGainSettings]`
- `[gain.js:writeSdrGainSettings]`
- `[gain.js:tunerGainValue]`
- `[spectrum.js:analyzeSpectrum]`
- `[spectrum.js:findDirectionalFmPeak]`
- `[usbDevices.js:SDR_DEVICE_STORAGE_KEY]`
- `[usbDevices.js:RTL_SDR_USB_FILTERS]`

## Invariants
- [adsbDecoder.test.mjs:24]: `import assert from 'node:assert/strict';`
- [adsbDecoder.test.mjs:70]: `assert.equal(callsign.callsign, 'KLM1023');`
- [adsbDecoder.test.mjs:71]: `assert.equal(callsign.icao, '4840D6');`
- [controller.test.mjs:23]: `import assert from 'node:assert/strict';`
- [controller.test.mjs:151]: `assert.equal(await controller.connect('fm'), true);`
- [controller.test.mjs:152]: `assert.ok(events.indexOf('audio:resume') < events.indexOf('usb:get'));`
- [decoderDiagnostics.test.mjs:23]: `import assert from 'node:assert/strict';`
- [decoderDiagnostics.test.mjs:165]: `assert.equal(forwarded, 20, 'every block of audio forwarded immediately');`
- [decoderDiagnostics.test.mjs:166]: `assert.equal(`
- [gain.test.mjs:24]: `import assert from 'node:assert/strict';`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/web/gods-eye-view/src/sdr/...`
