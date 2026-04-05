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

block=auto
is_slot_device=auto
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=1

. "$AKHOME/tools/ak3-core.sh"

detect_key_press() {
    ui_print "选项: $1"
    ui_print "音量上键: $2 | 音量下键: $3"
    while true; do
        key=$(getevent -qlc 1 2>/dev/null | awk '{print $3}')
        case "$key" in
            "KEY_VOLUMEUP") sleep 1; return 0 ;;
            "KEY_VOLUMEDOWN") sleep 1; return 1 ;;
        esac
        sleep 0.2
    done
}

process_boot() {
    case "$(basename "$block")" in
        init_boot*)
            ui_print "检测到 init_boot 分区..."
            ;;
        *)
            ui_print "检测到 boot 分区..."
            ;;
    esac
    dump_boot
}

install_module() {
    local module_file="$1"
    local module_name
    local module_desc
    module_name="$(basename "$module_file" .zip)"
    module_desc="$module_name"

    [ -f "$module_file" ] || {
        ui_print "未找到 ${module_name} 模块文件"
        return 1
    }

    if command -v unzip >/dev/null 2>&1; then
        module_desc="$(unzip -p "$module_file" module.prop 2>/dev/null | sed -n 's/^description=//p' | head -n 1)"
    fi
    [ -n "$module_desc" ] || module_desc="$module_name"

    ui_print "──────────────────"
    ui_print "模块: ${module_name}"
    ui_print "介绍: ${module_desc}"
    if ! detect_key_press "是否安装 ${module_name} 模块？" "安装" "跳过"; then
        ui_print "已跳过 ${module_name} 模块"
        return 0
    fi

    ui_print "正在安装 ${module_name} 模块..."
    KSUD="/data/adb/ksud"
    if [ -x "$KSUD" ]; then
        "$KSUD" module install "$module_file" && \
        ui_print "${module_name} 模块安装成功" || \
        ui_print "${module_name} 模块安装失败"
    else
        ui_print "错误: 找不到ksud可执行文件"
        return 1
    fi
}

main() {
    ui_print "──────────────────"
    ui_print "  KernelSU by KernelSU Developers      "
    ui_print "  AnyKernel3 by osm0sis @ xda-developers"
    ui_print "  Anykernel3 was modified by Frost_Dog"
    ui_print "  Custom kernel by Frost_Bai           "
    ui_print ""
    ui_print "▶ Installing..."
    ui_print "──────────────────"

    process_boot

    cp "$AK_IMG" "$split_img/kernel"

    case "$(basename "$block")" in
        init_boot*)
            flash_boot || abort "init_boot刷入失败"
            ;;
        *)
            write_boot || abort "boot刷入失败"
            ;;
    esac

    for module_file in "$AKHOME"/module/*.zip; do
        [ -f "$module_file" ] || continue
        install_module "$module_file"
    done

    ui_print "刷写完成"
    ui_print "请重启设备以应用更改"
}

main
