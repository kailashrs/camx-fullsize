# CamX Full-Size QCFA

A KernelSU / Magisk module that unlocks **50 MP capture for third-party camera apps** on the
vivo X200 Ultra. It works on the main and ultrawide cameras (LYT-818) and the HP9 periscope. It also
makes the hidden physical cameras visible to PhotonCamera and Open Camera.

By default, the Qualcomm camera HAL (CamX) on OriginOS only exposes binned 12.5 MP outputs to apps
other than vivo's own camera. This module switches on the HAL's full-size Quad Bayer outputs and adds
the sensor-mode rules needed to fill them correctly.

> [!IMPORTANT]
> The HAL side alone is not enough. Apps written for other phones get the Camera2 pixel-mode rules wrong, and cameraserver rejects their requests. Use this module together with the **Full resolution in camera apps** feature of **[OriTweaks](https://github.com/kailashrs/OriTweaks)**, which fixes those requests inside the camera app.

## Compatibility

| | |
| --- | --- |
| Device | vivo X200 Ultra (PD2454), China firmware |
| OS | OriginOS 6 (Android 16) and OriginOS 7 (Android 17, checked on 17.2.10.6) |
| Root | KernelSU (developed on 3.3 LKM), Magisk or APatch: anything that runs `service.sh` and provides `resetprop` |
| Camera apps | PhotonCamera (verified 50 MP on main, ultrawide and HP9); Open Camera (scoped, not yet verified) |

## What it changes

The module ships no copies of vivo's files. At every boot, `service.sh` does the following:

1. Reads the stock files from `/vendor/etc/camera/`, so it adapts to whatever OriginOS version is installed.
2. Writes patched copies into the module's `patched/` folder:
   - `camxoverridesettings.txt`: sets `exposeFullSizeForQCFA=TRUE`. The HAL then advertises `ULTRA_HIGH_RESOLUTION_SENSOR`, plus the maximum-resolution stream configurations: 8192×6144 on the LYT-818 sensors and 8160×6144 on the HP9.
   - `sensormode-selector/PD2454.json`: inserts the rules from [`remosaic-rules.json`](remosaic-rules.json) at the top of the `"!vivo"` (third-party app) branch. Full-width requests then pick the `HWREMOSAIC` sensor mode: 8192 on any camera, and 8160 only on camera IDs 3 and 4 (the HP9; the front camera is also 8160 wide). Without these rules, the HAL streams a binned frame into the corner of the 50 MP buffer.
3. Bind-mounts the patched files over the originals, keeping their SELinux label (`vendor_configs_file`).
4. Sets `vendor.camera.aux.packagelist` to `com.android.camera,com.particlesdevs.photoncamera,net.sourceforge.opencamera`, so those apps can see the hidden physical cameras, including the HP9 as camera 5. The property is limited to 92 characters.
5. Restarts the QTI camera provider and `cameraserver` so they read the new configuration.

Nothing is written to `/vendor`. Uninstalling or disabling the module and rebooting restores stock behaviour.

## Installation

1. Download `camx_fullsize-*.zip` from [Releases](https://github.com/kailashrs/camx-fullsize/releases).
2. Install it from the KernelSU or Magisk manager. Or from a computer:
   ```bash
   adb push camx_fullsize-v0.3.zip /data/local/tmp/
   adb shell su -c /data/adb/ksud module install /data/local/tmp/camx_fullsize-v0.3.zip
   ```
3. Reboot.
4. Install [OriTweaks](https://github.com/kailashrs/OriTweaks), scope it to your camera app and enable **Full resolution in camera apps**.
5. In PhotonCamera, turn on the **Quad Bayer** option.

## Checking that it works

```bash
adb shell su -c "grep exposeFullSizeForQCFA /vendor/etc/camera/camxoverridesettings.txt"
adb shell su -c "grep -c camx_fullsize /vendor/etc/camera/sensormode-selector/PD2454.json"
adb shell su -c "dumpsys media.camera | grep -c ULTRA_HIGH_RESOLUTION_SENSOR"
```

The first should print `exposeFullSizeForQCFA=TRUE`, the second `2`, and the third a non-zero count.
Right after a boot, `cameraserver` may list 0 devices for a few seconds while the provider restarts.

## Known limits

- **200 MP on the HP9** (16320×12288) does not work: CamX aborts in `CNodeImpl::PostPipelineCreate`. vivo's own camera produces 200 MP with an offline remosaic.
- **DCG / HDR sensor modes** are not available to third-party apps through this module.
- Full-size RAW frames are about 100 MB each. OriTweaks caps full-size bursts at about 800 MB to avoid running out of memory.

## Debugging the HAL

CamX logcat output is compiled out on vivo builds. To get HAL logs:

```bash
adb shell su -c "setprop persist.sys.camera.log yes"
adb shell su -c "for m in error warn config corecfg info; do setprop persist.vendor.logmask.\$m 0xFFFFFFFF; done"
```

Restart the camera provider. Logs land in `/data/bbklog/camera_log/cam_log_0.txt`, and older ones rotate into zips. The active sensor mode is visible in `dmesg` as `cam_sensor_handle_res_info`. Remove the properties afterwards with `resetprop -p -d <name>`.

## License

GPL-3.0 (see [LICENSE](LICENSE)). Not affiliated with vivo or Qualcomm.
