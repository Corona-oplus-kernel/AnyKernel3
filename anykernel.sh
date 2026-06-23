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

prepare_boot_image() {
    split_boot
    if [ -f "$split_img/ramdisk.cpio" ] || [ -f "$split_img/ramdisk.cpio.gz" ]; then
        ui_print "检测到 boot 分区..."
        unpack_ramdisk
        BOOT_WRITE_METHOD=write_boot
    else
        ui_print "检测到 init_boot 分区..."
        BOOT_WRITE_METHOD=flash_boot
    fi
}

flash_selected_boot() {
    case "$BOOT_WRITE_METHOD" in
        flash_boot)
            flash_boot
            ;;
        *)
            write_boot
            ;;
    esac
}

apply_kpn() {
    local kptools="$AKHOME/patch/kptools"
    local kpimg="$AKHOME/patch/kpimg"

    ui_print "使用修补工具: KP-N"
    ui_print "──────────────────"

    for retry in $(seq 1 3); do
        ui_print "KP-N补丁尝试 ($retry/3)"
        ui_print "没需求不需要安装🙄"

        if detect_key_press "应用KP-N补丁？" "是" "否"; then
            TMPD=$(mktemp -d) || continue
            cp "$AK_IMG" "$kptools" "$kpimg" "$TMPD/" && cd "$TMPD" || {
                rm -rf "$TMPD"
                continue
            }

            chmod +x kptools
            if ./kptools -p -i "$(basename "$AK_IMG")" -k kpimg -o oImage && [ -f "oImage" ]; then
                mv oImage "$split_img/kernel"
                ui_print "KP-N补丁应用成功"
                rm -rf "$TMPD"
                return 0
            fi
            rm -rf "$TMPD"
        else
            return 1
        fi
    done
    ui_print "警告: KP-N补丁应用失败"
    return 1
}

apply_kpm() {
    local patch_bin="$AKHOME/patch/patch"

    ui_print "使用修补工具: KPM (5_15+)"
    ui_print "──────────────────"

    for retry in $(seq 1 3); do
        ui_print "KPM补丁尝试 ($retry/3)"
        ui_print "没需求不需要安装🙄"

        if detect_key_press "应用KPM补丁？" "是" "否"; then
            TMPD=$(mktemp -d) || continue
            cp "$AK_IMG" "$patch_bin" "$TMPD/" && cd "$TMPD" || {
                rm -rf "$TMPD"
                continue
            }

            chmod +x patch
            if ./patch && [ -f "oImage" ]; then
                mv oImage "$split_img/kernel"
                ui_print "KPM补丁应用成功"
                rm -rf "$TMPD"
                return 0
            fi
            rm -rf "$TMPD"
        else
            return 1
        fi
    done
    ui_print "警告: KPM补丁应用失败"
    return 1
}

apply_patch() {
    ui_print "内核版本: $(uname -r)"

    if [ -f "$AKHOME/patch/kptools" ] && [ -f "$AKHOME/patch/kpimg" ]; then
        apply_kpn && return
    elif [ -f "$AKHOME/patch/patch" ]; then
        apply_kpm && return
    else
        ui_print "使用修补工具: 原始内核镜像"
    fi

    cp "$AK_IMG" "$split_img/kernel"
    ui_print "使用原始内核镜像"
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

    prepare_boot_image
    apply_patch

    flash_selected_boot

    for module_file in "$AKHOME"/module/*.zip; do
        [ -f "$module_file" ] || continue
        install_module "$module_file"
    done

    ui_print "刷写完成"
    ui_print "请重启设备以应用更改"
}

main
