#!/system/bin/sh
# Patches the stock camera config at boot and bind-mounts the result over /vendor, so the module
# follows whatever OriginOS version is installed instead of carrying copies of vivo's files.
MODDIR=${0%/*}
CAMERA=/vendor/etc/camera
OUT=$MODDIR/patched
CAMX=camxoverridesettings.txt
SELECTOR=sensormode-selector/PD2454.json

until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done

# Read the stock files even if a previous run already mounted over them.
umount $CAMERA/$CAMX $CAMERA/$SELECTOR 2>/dev/null
mkdir -p $OUT

# Advertise the full-size Quad Bayer outputs (ULTRA_HIGH_RESOLUTION_SENSOR and the max-resolution stream map).
sed 's/^exposeFullSizeForQCFA=.*/exposeFullSizeForQCFA=TRUE/' $CAMERA/$CAMX > $OUT/camxoverridesettings.txt
grep -q '^exposeFullSizeForQCFA=TRUE' $OUT/camxoverridesettings.txt || echo 'exposeFullSizeForQCFA=TRUE' >> $OUT/camxoverridesettings.txt

# Make full-size requests from third-party apps use on-sensor remosaic. Without these rules the HAL
# streams a binned frame into the corner of the 50 MP buffer. The rules go first in the "!vivo" branch.
awk -v rules="$MODDIR/remosaic-rules.json" '
    { print }
    /"Condition": \["string", "!vivo"\]/ { branch = 1 }
    branch && /"UsecaseSelector": \[/ { while ((getline line < rules) > 0) print line; branch = 0; done = 1 }
    END { if (!done) exit 1 }
' $CAMERA/$SELECTOR > $OUT/PD2454.json || rm -f $OUT/PD2454.json

for pair in "$OUT/camxoverridesettings.txt:$CAMERA/$CAMX" "$OUT/PD2454.json:$CAMERA/$SELECTOR"; do
    patched=${pair%%:*}; target=${pair#*:}
    [ -s "$patched" ] || continue
    chmod 644 "$patched"
    chcon "$(ls -Z "$target" | cut -d" " -f1)" "$patched"
    mount -o bind "$patched" "$target"
done

# Let third-party camera apps see the hidden physical cameras (the HP9 periscope among them).
resetprop vendor.camera.aux.packagelist com.android.camera,com.particlesdevs.photoncamera,net.sourceforge.opencamera

# The provider reads the config and cameraserver reads the package list only when they start.
kill $(pidof vendor.qti.camera.provider-service_64) $(pidof cameraserver) 2>/dev/null
