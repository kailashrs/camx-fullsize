#!/system/bin/sh
# Remove the bind mounts and put /vendor back into a shared subtree so normal
# mount propagation resumes. A reboot is still the cleanest way to drop any
# copies that older module versions left in app namespaces.
umount /vendor/etc/camera/camxoverridesettings.txt \
       /vendor/etc/camera/sensormode-selector/PD2454.json 2>/dev/null
mount -o shared none /vendor 2>/dev/null
rm -rf "${0%/*}/patched"
