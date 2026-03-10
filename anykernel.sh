#!/system/bin/sh

AKHOME="$(dirname "$(readlink -f "$0")")"
AK_IMG="$AKHOME/Image/Image"
AK_MODULE="$AKHOME/module/Corona.zip"
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

detect_key_press() {
    ui_print "选项: $1"
    ui_print "音量上键: $2 | 音量下键: $3"
    while true; do
        key=$(getevent -qlc 1 2>/dev/null | awk '{print $3}')
        case "$key" in
            "KEY_VOLUMEUP") return 0 ;;
            "KEY_VOLUMEDOWN") return 1 ;;
        esac
        sleep 0.2
    done
}

process_boot() {
    if [ -L "/dev/block/bootdevice/by-name/init_boot_a" ] || [ -L "/dev/block/by-name/init_boot_a" ]; then
        ui_print "检测到 init_boot 分区..."
        split_boot
    else
        ui_print "检测到 boot 分区..."
        dump_boot
    fi
}

install_module() {
    local module_name="$1"
    local module_file="$2"
    
    [ -f "$module_file" ] || {
        ui_print "未找到 ${module_name} 模块文件"
        return 1
    }
    
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

install_Corona() {
    [ -f "$AK_MODULE" ] || {
        ui_print "──────────────────"
        ui_print "未找到Corona内核系统设置模块文件"
        return
    }
    
    ui_print "──────────────────"
    ui_print "正在检查Corona内核系统设置模块安装选项..."
    ui_print "没需求不需要安装🌝"
    if detect_key_press "是否安装Corona内核系统设置模块？" "安装" "跳过"; then
        install_module "Corona" "$AK_MODULE"
    else
        ui_print "已跳过Corona内核系统设置模块安装"
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
    
    if [ -L "/dev/block/bootdevice/by-name/init_boot_a" ] || [ -L "/dev/block/by-name/init_boot_a" ]; then
        flash_boot || abort "init_boot刷入失败"
    else
        write_boot || abort "boot刷入失败"
    fi
    
    install_Corona
    ui_print ""
    ui_print "刷写完成"
    ui_print "请重启设备以应用更改"
}

main