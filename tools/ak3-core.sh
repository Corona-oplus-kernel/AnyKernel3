### AnyKernel methods (DO NOT CHANGE)
## osm0sis @ xda-developers

[ "$OUTFD" ] || OUTFD=$1;
[ "$AKHOME" ] && home=$AKHOME;
[ "$home" ] || home=$PWD;
bootimg=$home/boot.img;
bin=$home/tools;
patch=$home/patch;
ramdisk=$home/ramdisk;
split_img=$home/split_img;

ui_print() {
  until [ ! "$1" ]; do
    echo "ui_print $1
      ui_print" >> /proc/self/fd/$OUTFD;
    shift;
  done;
}
abort() { ui_print " " "$@"; exit 1; }

# find block device: find_blk <name> [name...]
find_blk() {
  local p f;
  for p in /dev/block/mapper /dev/block/by-name /dev/block/bootdevice/by-name /dev/block/platform/*/by-name /dev/block/platform/*/*/by-name /dev; do
    for f in "$@"; do
      [ -e $p/$f ] && { echo $p/$f; return 0; };
    done;
  done;
  return 1;
}

split_boot() {
  [ -e "$block" ] || abort "Invalid partition.";
  dd if=$block of=$bootimg bs=1048576;
  [ $? != 0 ] && abort "Dumping image failed.";
  mkdir -p $split_img; cd $split_img;
  (set -o pipefail; $bin/magiskboot unpack -h $bootimg 2>&1 | tee infotmp >&2);
  [ $? != 0 ] && abort "Splitting image failed.";
  cd $home;
}

unpack_ramdisk() {
  local comp;
  cd $split_img;
  [ -f ramdisk.cpio.gz ] && mv -f ramdisk.cpio.gz ramdisk.cpio;
  [ -f ramdisk.cpio ] || abort "No ramdisk found.";
  comp=$($bin/magiskboot decompress ramdisk.cpio 2>&1 | grep -v 'raw' | sed -n 's;.*\[\(.*\)\];\1;p');
  if [ "$comp" ]; then
    mv -f ramdisk.cpio ramdisk.cpio.$comp;
    $bin/magiskboot decompress ramdisk.cpio.$comp ramdisk.cpio;
    [ $? != 0 ] && $comp -dc ramdisk.cpio.$comp > ramdisk.cpio 2>/dev/null;
  fi;
  [ -d $ramdisk ] && mv -f $ramdisk $home/rdtmp;
  mkdir -p $ramdisk; chmod 755 $ramdisk;
  cd $ramdisk;
  EXTRACT_UNSAFE_SYMLINKS=1 cpio -d -F $split_img/ramdisk.cpio -i;
  [ $? != 0 -o ! "$(ls)" ] && abort "Unpacking ramdisk failed.";
  [ -d "$home/rdtmp" ] && cp -af $home/rdtmp/* .;
}

dump_boot() { split_boot; unpack_ramdisk; }

repack_ramdisk() {
  local comp;
  cd $home;
  comp=$(ls $split_img/ramdisk.cpio.* 2>/dev/null | rev | cut -d. -f1 | rev);
  cd $ramdisk;
  find . | cpio -H newc -o > $home/ramdisk-new.cpio;
  [ $? != 0 ] && abort "Repacking ramdisk failed.";
  cd $home;
  if [ "$comp" ]; then
    $bin/magiskboot compress=$comp ramdisk-new.cpio;
    if [ $? != 0 ] && $comp --help 2>/dev/null; then
      $comp -9c ramdisk-new.cpio > ramdisk-new.cpio.$comp;
      [ $? != 0 ] && abort "Repacking ramdisk failed.";
      rm -f ramdisk-new.cpio;
    fi;
  fi;
}

flash_boot() {
  local i kernel rd fdt nocompflag;
  cd $home;
  for i in zImage zImage-dtb Image Image-dtb Image.gz Image.gz-dtb Image.bz2 Image.bz2-dtb Image.lzo Image.lzo-dtb Image.lzma Image.lzma-dtb Image.xz Image.xz-dtb Image.lz4 Image.lz4-dtb Image.fit; do
    [ -f $i ] && { kernel=$home/$i; break; };
  done;
  [ "$kernel" ] || kernel=$(ls $split_img/kernel* 2>/dev/null | grep -v kernel_dtb | tail -n1);
  rd=$(ls $home/ramdisk-new.cpio* 2>/dev/null | tail -n1);
  [ "$rd" ] || rd=$(ls $split_img/ramdisk.cpio* 2>/dev/null | tail -n1);
  for fdt in dt recovery_dtbo dtb; do
    for i in $home/$fdt $home/$fdt.img $split_img/$fdt; do
      [ -f $i ] && { eval local $fdt=$i; break; };
    done;
  done;
  cd $split_img;
  [ "$kernel" ] && cp -f $kernel kernel;
  [ "$rd" ] && cp -f $rd ramdisk.cpio;
  [ "$dt" -a -f extra ] && cp -f $dt extra;
  for i in dtb recovery_dtbo; do
    [ "$(eval echo \$$i)" -a -f $i ] && cp -f $(eval echo \$$i) $i;
  done;
  case $kernel in *Image*) case $kernel in *-dtb) rm -f kernel_dtb;; esac;; esac;
  case $ramdisk_compression in none|cpio) nocompflag="-n";; esac;
  [ "$PATCHVBMETAFLAG" ] || export PATCHVBMETAFLAG=false;
  $bin/magiskboot repack $nocompflag $bootimg $home/boot-new.img;
  [ $? != 0 ] && abort "Repacking image failed.";
  unset PATCHVBMETAFLAG;
  cd $home;
  [ -f boot-new.img ] || abort "No repacked image found.";
  [ "$(wc -c < boot-new.img)" -gt "$(wc -c < boot.img)" ] && abort "New image larger than partition.";
  blockdev --setrw $block 2>/dev/null;
  cat boot-new.img /dev/zero > $block 2>/dev/null || true;
  [ $? != 0 ] && abort "Flashing image failed.";
}

flash_generic() {
  local avb avbblock file flags img imgblock imgsz isro isunmounted path;
  cd $home;
  for file in $1 $1.img; do [ -f $file ] && { img=$file; break; }; done;
  [ "$img" -a ! -f ${1}_flashed ] || return 0;
  imgblock=$(find_blk $1$slot $1) || abort "$1 partition not found.";
  path=$(dirname $imgblock);
  ui_print " " "$imgblock";
  if [ "$path" == "/dev/block/mapper" ]; then
    avb=$($bin/httools_static avb $1) || abort "Failed to parse fstab for $1.";
    if [ "$avb" ]; then
      flags=$($bin/httools_static disable-flags) || abort "Failed to parse vbmeta.";
      if [ "$flags" == "enabled" ]; then
        ui_print " " "dm-verity detected! Patching $avb...";
        avbblock=$(find_blk $avb$slot $avb) || true;
        [ "$avbblock" ] && { cd $bin; $bin/httools_static patch $1 $home/$img $avbblock || abort "Failed to patch $1."; cd $home; }
      fi
    fi
    imgsz=$(wc -c < $img);
    if [ "$imgsz" != "$(wc -c < $imgblock)" ]; then
      if [ -d /postinstall/tmp -a "$slot_select" == "inactive" ]; then
        $bin/snapshotupdater_static update $1 $imgsz || abort "Resizing $1$slot snapshot failed.";
      else
        $bin/lptools_static remove $1_ak3;
        $bin/lptools_static clear-cow;
        if $bin/lptools_static create $1_ak3 $imgsz; then
          $bin/lptools_static unmap $1_ak3 || abort "Unmapping $1_ak3 failed.";
          $bin/lptools_static map $1_ak3 || abort "Mapping $1_ak3 failed.";
          $bin/lptools_static replace $1_ak3 $1$slot || abort "Replacing $1$slot failed.";
          imgblock=/dev/block/mapper/$1_ak3;
          ui_print " " "Warning: $1$slot replaced in super.";
        else
          $bin/httools_static umount $1 || abort "Unmounting $1 failed.";
          [ -e $path/$1-verity ] && { $bin/lptools_static unmap $1-verity || abort "Unmapping $1-verity failed."; }
          $bin/lptools_static unmap $1$slot || abort "Unmapping $1$slot failed.";
          $bin/lptools_static resize $1$slot $imgsz || abort "Resizing $1$slot failed.";
          $bin/lptools_static map $1$slot || abort "Mapping $1$slot failed.";
          isunmounted=1;
        fi
      fi
    fi
  elif [ "$(wc -c < $img)" -gt "$(wc -c < $imgblock)" ]; then
    abort "New $1 image larger than partition.";
  fi;
  isro=$(blockdev --getro $imgblock 2>/dev/null);
  blockdev --setrw $imgblock 2>/dev/null;
  cat $img /dev/zero > $imgblock 2>/dev/null || true;
  [ $? != 0 ] && abort "Flashing $1 failed.";
  [ "$isro" != 0 ] && blockdev --setro $imgblock 2>/dev/null;
  [ "$isunmounted" ] && { $bin/httools_static mount $1 || abort "Mounting $1 failed."; }
  touch ${1}_flashed;
}

write_boot() {
  repack_ramdisk; flash_boot;
  for p in vendor_boot vendor_kernel_boot vendor_dlkm system_dlkm dtbo; do flash_generic $p; done;
}

setup_ak() {
  local blockfiles parttype name part target;
  case $is_slot_device in
    1|auto)
      slot=$(getprop ro.boot.slot_suffix 2>/dev/null);
      [ "$slot" ] || slot=$(grep -o 'androidboot.slot_suffix=.*$' /proc/cmdline | cut -d\  -f1 | cut -d= -f2);
      if [ ! "$slot" ]; then
        slot=$(getprop ro.boot.slot 2>/dev/null);
        [ "$slot" ] || slot=$(grep -o 'androidboot.slot=.*$' /proc/cmdline | cut -d\  -f1 | cut -d= -f2);
        [ "$slot" ] && slot=_$slot;
      fi;
      [ "$slot" == "normal" ] && unset slot;
      if [ "$slot" ]; then
        [ -d /postinstall/tmp -a ! "$slot_select" ] && slot_select=inactive;
        case $slot_select in inactive) case $slot in _a) slot=_b;; _b) slot=_a;; esac;; esac;
      fi;
      [ ! "$slot" -a "$is_slot_device" == 1 ] && abort "Unable to determine active slot.";
    ;;
  esac;
  cd $home;
  rm -f modules/system/lib/modules/placeholder patch/placeholder ramdisk/placeholder;
  rmdir -p modules patch ramdisk 2>/dev/null;
  if [ -e "/dev/block/bootdevice/by-name/init_boot$slot" -a ! -f init_v4_setup ] && [ -f dtb -o -d vendor_ramdisk -o -d vendor_patch ]; then
    (mkdir boot-files; mv -f Image* boot-files;
    mkdir init_boot-files; mv -f ramdisk patch init_boot-files;
    mkdir vendor_kernel_boot-files; mv -f dtb vendor_kernel_boot-files;
    mv -f vendor_ramdisk vendor_kernel_boot-files/ramdisk;
    mv -f vendor_patch vendor_kernel_boot-files/patch) 2>/dev/null;
    touch init_v4_setup;
  elif [ -e "/dev/block/bootdevice/by-name/vendor_boot$slot" -a ! -f vendor_v3_setup ] && [ -f dtb -o -d vendor_ramdisk -o -d vendor_patch ]; then
    (mkdir boot-files; mv -f Image* ramdisk patch boot-files;
    mkdir vendor_boot-files; mv -f dtb vendor_boot-files;
    mv -f vendor_ramdisk vendor_boot-files/ramdisk;
    mv -f vendor_patch vendor_boot-files/patch) 2>/dev/null;
    touch vendor_v3_setup;
  fi;
  case $block in
    /dev/*)
      [ "$slot" ] && [ -e "$block$slot" ] && target=$block$slot;
      [ "$target" ] || [ -e "$block" ] && target=$block;
    ;;
    *)
      case $block in
        auto) parttype="init_boot ramdisk boot BOOT LNX android_boot bootimg KERN-A kernel KERNEL";;
        boot|kernel) parttype="boot BOOT LNX android_boot bootimg KERN-A kernel KERNEL";;
        recovery|recovery_ramdisk) parttype="recovery RECOVERY SOS android_recovery recovery_ramdisk";;
        init_boot|ramdisk) parttype="init_boot ramdisk";;
        *) parttype=$block;;
      esac;
      for name in $parttype; do
        for part in $name$slot $name; do
          target=$(find_blk $part) && break 2;
        done;
      done;
    ;;
  esac;
  [ "$target" ] && block=$(ls $target 2>/dev/null) || abort "Unable to determine $block partition.";
  ui_print "$block";
  name=$(basename $block | sed -e 's/_a$//' -e 's/_b$//');
  if [ "$block" ] && [ ! -d "$ramdisk" -a ! -d "$patch" ]; then
    blockfiles=$home/$name-files;
    [ "$(ls $blockfiles 2>/dev/null)" ] && cp -af $blockfiles/* $home || mkdir $blockfiles;
    touch $blockfiles/current;
  fi;
  type attributes >/dev/null 2>&1 && attributes;
  type ${name}_attributes >/dev/null 2>&1 && ${name}_attributes;
}

setup_ak;
