#!/system/bin/sh

AKHOME="$(dirname "$(readlink -f "$0")")"
AK_IMG="$AKHOME/Image/Image"
properties() { '
kernel.string=KernelSU by KernelSU Developers
do.devicecheck=0
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=
device.name2=
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; }

block=boot
is_slot_device=auto
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=1

. "$AKHOME/tools/ak3-core.sh"

CAN_INTERACT=false
if getevent -il 2>/dev/null | grep -q "KEY_VOLUMEUP"; then
    CAN_INTERACT=true
fi

detect_key_press() {
    ui_print "选项: $1"
    ui_print "音量上键: $2 | 音量下键: $3"
    while true; do
        case $(getevent -qlc 1 2>/dev/null) in
            *KEY_VOLUMEUP*)   sleep 0.3; return 0 ;;
            *KEY_VOLUMEDOWN*) sleep 0.3; return 1 ;;
        esac
    done
}

apply_patch() {
    local patch_name=""

    if [ -f "$AKHOME/patch/kptools" ] && [ -f "$AKHOME/patch/kpimg" ]; then
        patch_name="KP-N"
    elif [ -f "$AKHOME/patch/patch" ]; then
        patch_name="KPM"
    fi

    if [ -z "$patch_name" ]; then
        ui_print "修补工具: 无"
        cp "$AK_IMG" "$split_img/kernel"
        return
    fi

    ui_print "修补工具: $patch_name"
    ui_print "──────────────────"
    ui_print "没需求不需要安装🙄"

    if [ "$CAN_INTERACT" = "false" ]; then
        ui_print "无法检测音量键，跳过补丁"
        cp "$AK_IMG" "$split_img/kernel"
        return
    fi

    if ! detect_key_press "应用${patch_name}补丁？" "是" "否"; then
        ui_print "跳过补丁，使用原始内核镜像"
        cp "$AK_IMG" "$split_img/kernel"
        return
    fi

    local success=false
    for retry in $(seq 1 3); do
        ui_print "${patch_name}补丁尝试 ($retry/3)..."
        TMPD=$(mktemp -d) || continue
        cp "$AK_IMG" "$TMPD/" || { rm -rf "$TMPD"; continue; }

        if [ "$patch_name" = "KP-N" ]; then
            cp "$AKHOME/patch/kptools" "$AKHOME/patch/kpimg" "$TMPD/"
            cd "$TMPD" && chmod +x kptools
            ./kptools -p -i Image -k kpimg -o oImage
        else
            cp "$AKHOME/patch/patch" "$TMPD/"
            cd "$TMPD" && chmod +x patch
            ./patch
        fi

        if [ -f "$TMPD/oImage" ]; then
            mv "$TMPD/oImage" "$split_img/kernel"
            ui_print "${patch_name}补丁应用成功"
            success=true
            rm -rf "$TMPD"
            break
        fi
        rm -rf "$TMPD"
    done

    if [ "$success" != "true" ]; then
        ui_print "警告: ${patch_name}补丁失败，使用原始内核镜像"
        cp "$AK_IMG" "$split_img/kernel"
    fi
}

install_module() {
    local module_file="$1"
    local module_name
    local module_desc
    module_name="$(basename "$module_file" .zip)"
    module_desc="$module_name"

    [ -f "$module_file" ] || return 1

    if command -v unzip >/dev/null 2>&1; then
        module_desc="$(unzip -p "$module_file" module.prop 2>/dev/null | sed -n 's/^description=//p' | head -n 1)"
    fi
    [ -n "$module_desc" ] || module_desc="$module_name"

    ui_print "──────────────────"
    ui_print "模块: ${module_name}"
    ui_print "介绍: ${module_desc}"
    if ! detect_key_press "是否安装 ${module_name} 模块？" "安装" "跳过"; then
        ui_print "已跳过 ${module_name}"
        return 0
    fi

    ui_print "正在安装 ${module_name}..."
    KSUD="/data/adb/ksud"
    if [ -x "$KSUD" ]; then
        "$KSUD" module install "$module_file" && \
            ui_print "${module_name} 安装成功" || \
            ui_print "${module_name} 安装失败"
    else
        ui_print "错误: 找不到ksud"
        return 1
    fi
}

main() {
    ui_print "──────────────────"
    ui_print "  KernelSU by KernelSU Developers"
    ui_print "  AnyKernel3 by osm0sis @ xda-developers"
    ui_print "  Modified by Frost_Dog"
    ui_print "  Custom kernel by Frost_Bai"
    ui_print "──────────────────"
    ui_print ""
    ui_print "内核版本: $(uname -r)"

    split_boot

    if [ -f "$split_img/ramdisk.cpio" ] || [ -f "$split_img/ramdisk.cpio.gz" ]; then
        ui_print "检测到 boot (ramdisk)"
        unpack_ramdisk
        apply_patch
        write_boot
    else
        ui_print "检测到 init_boot"
        apply_patch
        flash_boot
    fi

    if [ "$CAN_INTERACT" = "false" ]; then
        ui_print "无法检测音量键，跳过模块安装"
    else
        for module_file in "$AKHOME"/module/*.zip; do
            [ -f "$module_file" ] || continue
            install_module "$module_file"
        done
    fi

    ui_print "──────────────────"
    ui_print "刷写完成，请重启设备"
}

main
