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

# common write helper: write image data to a block device
do_flash() {
  local src=$1 dst=$2;
  blockdev --setrw $dst 2>/dev/null;
  if [ "$customdd" ]; then
    dd if=/dev/zero of=$dst $customdd 2>/dev/null;
    dd if=$src of=$dst $customdd;
  else
    cat $src /dev/zero > $dst 2>/dev/null || true;
  fi;
  [ $? != 0 ] && return 1;
  return 0;
}

split_boot() {
  local splitfail;
  if [ ! -e "$(echo $block | cut -d\  -f1)" ]; then
    abort "Invalid partition. Aborting...";
  fi;
  if [ "$(echo $block | grep ' ')" ]; then
    block=$(echo $block | cut -d\  -f1);
    customdd=$(echo $block | cut -d\  -f2-);
  elif [ ! "$customdd" ]; then
    local customdd="bs=1048576";
  fi;
  dd if=$block of=$bootimg $customdd;
  [ $? != 0 ] && abort "Dumping image failed. Aborting...";

  mkdir -p $split_img;
  cd $split_img;
  (set -o pipefail; $bin/magiskboot unpack -h $bootimg 2>&1 | tee infotmp >&2);
  case $? in
    1) splitfail=1;;
    2) touch chromeos;;
  esac;
  if [ $? != 0 -o "$splitfail" ]; then
    abort "Splitting image failed. Aborting...";
  fi;
  cd $home;
}

unpack_ramdisk() {
  local comp;
  cd $split_img;
  if [ -f ramdisk.cpio.gz ]; then
    mv -f ramdisk.cpio.gz ramdisk.cpio;
  fi;
  if [ -f ramdisk.cpio ]; then
    comp=$($bin/magiskboot decompress ramdisk.cpio 2>&1 | grep -v 'raw' | sed -n 's;.*\[\(.*\)\];\1;p');
  else
    abort "No ramdisk found to unpack. Aborting...";
  fi;
  if [ "$comp" ]; then
    mv -f ramdisk.cpio ramdisk.cpio.$comp;
    $bin/magiskboot decompress ramdisk.cpio.$comp ramdisk.cpio;
    if [ $? != 0 ] && $comp --help 2>/dev/null; then
      $comp -dc ramdisk.cpio.$comp > ramdisk.cpio;
    fi;
  fi;
  [ -d $ramdisk ] && mv -f $ramdisk $home/rdtmp;
  mkdir -p $ramdisk;
  chmod 755 $ramdisk;
  cd $ramdisk;
  EXTRACT_UNSAFE_SYMLINKS=1 cpio -d -F $split_img/ramdisk.cpio -i;
  if [ $? != 0 -o ! "$(ls)" ]; then
    abort "Unpacking ramdisk failed. Aborting...";
  fi;
  [ -d "$home/rdtmp" ] && cp -af $home/rdtmp/* .;
}

dump_boot() { split_boot; unpack_ramdisk; }

repack_ramdisk() {
  local comp packfail;
  cd $home;
  if [ "$ramdisk_compression" != "auto" ] && [ "$(grep HEADER_VER $split_img/infotmp | sed -n 's;.*\[\(.*\)\];\1;p')" -gt 3 ]; then
    ui_print " " "Warning: Only lz4-l ramdisk compression is allowed with hdr v4+ images. Resetting to auto...";
    ramdisk_compression=auto;
  fi;
  case $ramdisk_compression in
    auto|"") comp=$(ls $split_img/ramdisk.cpio.* 2>/dev/null | grep -v 'mtk' | rev | cut -d. -f1 | rev);;
    none|cpio) comp="";;
    gz) comp=gzip;; lzo) comp=lzop;; bz2) comp=bzip2;; lz4-l) comp=lz4_legacy;;
    *) comp=$ramdisk_compression;;
  esac;
  cd $ramdisk;
  find . | cpio -H newc -o > $home/ramdisk-new.cpio;
  [ $? != 0 ] && packfail=1;
  cd $home;
  if [ "$comp" ]; then
    $bin/magiskboot compress=$comp ramdisk-new.cpio;
    if [ $? != 0 ] && $comp --help 2>/dev/null; then
      $comp -9c ramdisk-new.cpio > ramdisk-new.cpio.$comp;
      [ $? != 0 ] && packfail=1;
      rm -f ramdisk-new.cpio;
    fi;
  fi;
  [ "$packfail" ] && abort "Repacking ramdisk failed. Aborting...";
}

flash_boot() {
  local i kernel ramdisk fdt nocompflag;
  cd $home;
  for i in zImage zImage-dtb Image Image-dtb Image.gz Image.gz-dtb Image.bz2 Image.bz2-dtb Image.lzo Image.lzo-dtb Image.lzma Image.lzma-dtb Image.xz Image.xz-dtb Image.lz4 Image.lz4-dtb Image.fit; do
    [ -f $i ] && { kernel=$home/$i; break; };
  done;
  [ "$kernel" ] || kernel=$(ls $split_img/kernel* 2>/dev/null | grep -v 'kernel_dtb' | tail -n1);
  if [ "$(ls ramdisk-new.cpio* 2>/dev/null)" ]; then
    ramdisk=$home/$(ls ramdisk-new.cpio* | tail -n1);
  else
    ramdisk=$(ls $split_img/ramdisk.cpio* 2>/dev/null | tail -n1);
  fi;
  for fdt in dt recovery_dtbo dtb; do
    for i in $home/$fdt $home/$fdt.img $split_img/$fdt; do
      [ -f $i ] && { eval local $fdt=$i; break; };
    done;
  done;

  cd $split_img;
  [ "$kernel" ] && cp -f $kernel kernel;
  [ "$ramdisk" ] && cp -f $ramdisk ramdisk.cpio;
  [ "$dt" -a -f extra ] && cp -f $dt extra;
  for i in dtb recovery_dtbo; do
    [ "$(eval echo \$$i)" -a -f $i ] && cp -f $(eval echo \$$i) $i;
  done;
  case $kernel in
    *Image*)
      case $kernel in *-dtb) rm -f kernel_dtb;; esac;
      unset magisk_patched KEEPVERITY KEEPFORCEENCRYPT RECOVERYMODE PREINITDEVICE SHA1 RANDOMSEED;
    ;;
  esac;
  case $ramdisk_compression in none|cpio) nocompflag="-n";; esac;
  case $patch_vbmeta_flag in
    auto|"") [ "$PATCHVBMETAFLAG" ] || export PATCHVBMETAFLAG=false;;
    1) export PATCHVBMETAFLAG=true;;
    *) export PATCHVBMETAFLAG=false;;
  esac;
  $bin/magiskboot repack $nocompflag $bootimg $home/boot-new.img;
  [ $? != 0 ] && abort "Repacking image failed. Aborting...";
  [ "$PATCHVBMETAFLAG" ] && unset PATCHVBMETAFLAG;

  cd $home;
  if [ ! -f boot-new.img ]; then
    abort "No repacked image found to flash. Aborting...";
  elif [ "$(wc -c < boot-new.img)" -gt "$(wc -c < boot.img)" ]; then
    abort "New image larger than target partition. Aborting...";
  fi;
  do_flash boot-new.img $block || abort "Flashing image failed. Aborting...";
}

flash_generic() {
  local avb avbblock avbpath file flags img imgblock imgsz isro isunmounted path;
  cd $home;
  for file in $1 $1.img; do
    [ -f $file ] && { img=$file; break; };
  done;
  if [ "$img" -a ! -f ${1}_flashed ]; then
    for path in /dev/block/mapper /dev/block/by-name /dev/block/bootdevice/by-name; do
      for file in $1 $1$slot; do
        [ -e $path/$file ] && { imgblock=$path/$file; break 2; };
      done;
    done;
    [ "$imgblock" ] || abort "$1 partition could not be found. Aborting...";
    [ "$no_block_display" ] || ui_print " " "$imgblock";
    if [ "$path" == "/dev/block/mapper" ]; then
      avb=$($bin/httools_static avb $1);
      [ $? == 0 ] || abort "Failed to parse fstab entry for $1. Aborting...";
      if [ "$avb" ]; then
        flags=$($bin/httools_static disable-flags);
        [ $? == 0 ] || abort "Failed to parse top-level vbmeta. Aborting...";
        if [ "$flags" == "enabled" ]; then
          ui_print " " "dm-verity detected! Patching $avb...";
          for avbpath in /dev/block/mapper /dev/block/by-name /dev/block/bootdevice/by-name; do
            for file in $avb $avb$slot; do
              [ -e $avbpath/$file ] && { avbblock=$avbpath/$file; break 2; };
            done;
          done;
          cd $bin;
          $bin/httools_static patch $1 $home/$img $avbblock || abort "Failed to patch $1 on $avb. Aborting...";
          cd $home;
        fi
      fi
      imgsz=$(wc -c < $img);
      if [ "$imgsz" != "$(wc -c < $imgblock)" ]; then
        if [ -d /postinstall/tmp -a "$slot_select" == "inactive" ]; then
          $bin/snapshotupdater_static update $1 $imgsz || abort "Resizing $1$slot snapshot failed. Aborting...";
        else
          $bin/lptools_static remove $1_ak3;
          $bin/lptools_static clear-cow;
          if $bin/lptools_static create $1_ak3 $imgsz; then
            $bin/lptools_static unmap $1_ak3 || abort "Unmapping $1_ak3 failed. Aborting...";
            $bin/lptools_static map $1_ak3 || abort "Mapping $1_ak3 failed. Aborting...";
            $bin/lptools_static replace $1_ak3 $1$slot || abort "Replacing $1$slot failed. Aborting...";
            imgblock=/dev/block/mapper/$1_ak3;
            ui_print " " "Warning: $1$slot replaced in super. Reboot before further logical partition operations.";
          else
            $bin/httools_static umount $1 || abort "Unmounting $1 failed. Aborting...";
            [ -e $path/$1-verity ] && { $bin/lptools_static unmap $1-verity || abort "Unmapping $1-verity failed. Aborting..."; }
            $bin/lptools_static unmap $1$slot || abort "Unmapping $1$slot failed. Aborting...";
            $bin/lptools_static resize $1$slot $imgsz || abort "Resizing $1$slot failed. Aborting...";
            $bin/lptools_static map $1$slot || abort "Mapping $1$slot failed. Aborting...";
            isunmounted=1;
          fi
        fi
      fi
    elif [ "$(wc -c < $img)" -gt "$(wc -c < $imgblock)" ]; then
      abort "New $1 image larger than $1 partition. Aborting...";
    fi;
    isro=$(blockdev --getro $imgblock 2>/dev/null);
    do_flash $img $imgblock || abort "Flashing $1 failed. Aborting...";
    [ "$isro" != 0 ] && blockdev --setro $imgblock 2>/dev/null;
    [ "$isunmounted" -a "$path" == "/dev/block/mapper" ] && { $bin/httools_static mount $1 || abort "Mounting $1 failed. Aborting..."; }
    touch ${1}_flashed;
  fi;
}

write_boot() {
  repack_ramdisk;
  flash_boot;
  for p in vendor_boot vendor_kernel_boot vendor_dlkm system_dlkm dtbo; do
    flash_generic $p;
  done;
}

setup_ak() {
  local blockfiles plistboot plistinit plistreco parttype name part mtdmount mtdpart mtdname target;
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
        case $slot_select in
          inactive) case $slot in _a) slot=_b;; _b) slot=_a;; esac;;
        esac;
      fi;
      [ ! "$slot" -a "$is_slot_device" == 1 ] && abort "Unable to determine active slot. Aborting...";
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
      if [ "$slot" ] && [ -e "$block$slot" ]; then target=$block$slot;
      elif [ -e "$block" ]; then target=$block; fi;
    ;;
    *)
      plistboot="boot BOOT LNX android_boot bootimg KERN-A kernel KERNEL";
      plistreco="recovery RECOVERY SOS android_recovery recovery_ramdisk";
      plistinit="init_boot ramdisk";
      case $block in
        auto) parttype="$plistinit $plistboot";; boot|kernel) parttype=$plistboot;;
        recovery|recovery_ramdisk) parttype=$plistreco;; init_boot|ramdisk) parttype=$plistinit;;
        *) parttype=$block;;
      esac;
      for name in $parttype; do
        for part in $name$slot $name; do
          if [ "$(grep -w "$part" /proc/mtd 2>/dev/null)" ]; then
            mtdmount=$(grep -w "$part" /proc/mtd);
            mtdpart=$(echo $mtdmount | cut -d\" -f2);
            if [ "$mtdpart" == "$part" ]; then
              mtdname=$(echo $mtdmount | cut -d: -f1);
            else
              abort "Unable to determine mtd $block partition. Aborting...";
            fi;
            [ -e /dev/mtd/$mtdname ] && target=/dev/mtd/$mtdname;
          elif [ -e /dev/block/by-name/$part ]; then target=/dev/block/by-name/$part;
          elif [ -e /dev/block/bootdevice/by-name/$part ]; then target=/dev/block/bootdevice/by-name/$part;
          elif [ -e /dev/block/platform/*/by-name/$part ]; then target=/dev/block/platform/*/by-name/$part;
          elif [ -e /dev/block/platform/*/*/by-name/$part ]; then target=/dev/block/platform/*/*/by-name/$part;
          elif [ -e /dev/$part ]; then target=/dev/$part;
          fi;
          [ "$target" ] && break 2;
        done;
      done;
    ;;
  esac;
  if [ "$target" ]; then block=$(ls $target 2>/dev/null);
  else abort "Unable to determine $block partition. Aborting..."; fi;
  [ "$no_block_display" ] || ui_print "$block";
  name=$(basename $block | sed -e 's/_a$//' -e 's/_b$//');
  if [ "$block" ] && [ ! -d "$ramdisk" -a ! -d "$patch" ]; then
    blockfiles=$home/$name-files;
    if [ "$(ls $blockfiles 2>/dev/null)" ]; then cp -af $blockfiles/* $home;
    else mkdir $blockfiles; fi;
    touch $blockfiles/current;
  fi;
  type attributes >/dev/null 2>&1 && attributes;
  type ${name}_attributes >/dev/null 2>&1 && ${name}_attributes;
}

setup_ak;
