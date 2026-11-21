#!/system/bin/sh
# CamX Full-Size QCFA
#
# Rebuilds the patched camera config from the stock files at boot and exposes it
# only to the camera stack. cameraserver and the QTI/vivo providers run in
# init's mount namespace; every app gets a slave copy of that namespace from
# zygote. Making /vendor private before the bind mounts therefore keeps the
# patch visible to the HAL while leaving app mountinfo exactly stock.

MODDIR=${0%/*}
CAMERA=/vendor/etc/camera
OUT=$MODDIR/patched
CAMX=camxoverridesettings.txt
SELECTOR=sensormode-selector/PD2454.json
PACKAGES="com.android.camera com.particlesdevs.photoncamera net.sourceforge.opencamera"
PROP_LIMIT=92

log() { echo "camx_fullsize: $*"; }

# Drop bind mounts from a previous run so the next read is the stock file.
# The lazy fallback handles a target that is momentarily busy.
umount "$CAMERA/$CAMX" "$CAMERA/$SELECTOR" 2>/dev/null || \
    umount -l "$CAMERA/$CAMX" "$CAMERA/$SELECTOR" 2>/dev/null

# Keep new mounts under /vendor out of the app (slave) namespaces. Without
# this the bind mounts below are visible in every app's /proc/self/mountinfo,
# which is a root/tamper marker for RASP layers such as DexGuard ThreatCast.
# On toolboxes without propagation support we keep working, just with the old
# app-visible behaviour.
mount -o private none /vendor 2>/dev/null || \
    log "warning: could not make /vendor private"

mkdir -p "$OUT"
chmod 755 "$OUT"

# --- camxoverridesettings.txt ------------------------------------------------
# Advertise the full-size Quad Bayer outputs (ULTRA_HIGH_RESOLUTION_SENSOR and
# the maximum-resolution stream map).
sed 's/^exposeFullSizeForQCFA=.*/exposeFullSizeForQCFA=TRUE/' \
    "$CAMERA/$CAMX" > "$OUT/camxoverridesettings.txt" || exit 1
grep -q '^exposeFullSizeForQCFA=TRUE' "$OUT/camxoverridesettings.txt" || \
    echo 'exposeFullSizeForQCFA=TRUE' >> "$OUT/camxoverridesettings.txt"

# --- sensormode-selector/PD2454.json ----------------------------------------
if grep -q 'camx_fullsize' "$CAMERA/$SELECTOR" 2>/dev/null; then
    # The previous bind mount is still in place (umount failed), so this file
    # already contains our rules. Patching it again would duplicate them.
    log "selector still mounted from a previous run; skipping selector patch"
    rm -f "$OUT/PD2454.json"
else
    # Insert the remosaic rules at the top of the "!vivo" (third-party app)
    # branch. Without them the HAL streams a binned frame into the corner of
    # the full-size buffer.
    awk -v rules="$MODDIR/remosaic-rules.json" '
        { print }
        /"Condition": \["string", "!vivo"\]/ { branch = 1 }
        branch && /"UsecaseSelector": \[/ {
            while ((getline line < rules) > 0) print line
            branch = 0; done = 1
        }
        END { if (!done) exit 1 }
    ' "$CAMERA/$SELECTOR" > "$OUT/PD2454.json" || rm -f "$OUT/PD2454.json"
fi

# --- bind the patched files into the camera stack ----------------------------
for pair in "$OUT/camxoverridesettings.txt:$CAMERA/$CAMX" \
            "$OUT/PD2454.json:$CAMERA/$SELECTOR"; do
    patched=${pair%%:*}
    target=${pair#*:}
    [ -s "$patched" ] || continue
    chmod 644 "$patched"
    context=$(stat -c %C "$target" 2>/dev/null)
    [ -n "$context" ] && chcon "$context" "$patched"
    mount -o bind "$patched" "$target" || log "failed to mount $target"
    # Do not let the bind inherit the backing filesystem's shared subtree.
    mount -o private none "$target" 2>/dev/null
done

# --- hidden physical cameras -------------------------------------------------
# Append our apps to whatever the vendor already published instead of
# replacing it. The HAL property is capped at 92 characters.
base=$(getprop vendor.camera.aux.packagelist)
for pkg in $PACKAGES; do
    case ",$base," in
        *",$pkg,"*) ;;
        *) base=${base:+$base,}$pkg ;;
    esac
done
if [ ${#base} -le $PROP_LIMIT ]; then
    resetprop vendor.camera.aux.packagelist "$base"
else
    log "package list is ${#base} chars (limit $PROP_LIMIT); keeping the existing value"
fi

# --- restart readers ---------------------------------------------------------
# camxoverridesettings.txt is parsed when the provider starts, and cameraserver
# reads the package list at startup. Restart via init so service state and
# SELinux domains stay consistent.
for svc in cameraserver vendor.camera-provider camera3rd-provider-1-0; do
    if [ "$(getprop "init.svc.$svc")" = "running" ]; then
        setprop ctl.restart "$svc"
    fi
done

log "applied"
