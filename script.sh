#!/bin/bash
# Функция для создания резервной копии файла
backup_file() {
    if [ -e "$1" ]; then
        cp "$1" "$1.old"
        echo "Создана резервная копия файла: $1.old"
    fi
}

# Проверка и установка пакета preload
if ! dpkg -s preload &> /dev/null; then
    echo "Установка пакета preload"
    apt-get install -y preload
fi

# Создание резервных копий для файлов конфигурации
backup_file "/etc/sysctl.conf"
backup_file "/etc/default/grub"
backup_file "/etc/script.config"

# Настройка параметров sysctl.conf
if ! grep -qE "vm\.swappiness = 10|vm\.dirty_bytes = 2097152|vm\.vfs_cache_pressure = 50" /etc/sysctl.conf; then
    echo "Добавление параметров в /etc/sysctl.conf"
    sh -c 'cat <<EOF >> /etc/sysctl.conf
vm.swappiness = 10
vm.dirty_bytes = 2097152
vm.vfs_cache_pressure = 50
EOF'
    sysctl -p
fi

# Настройка параметров grub
GRUB_CONFIG_FILE="/etc/default/grub"
NEW_GRUB_CMDLINE_VALUE="quiet libahci.ignore_sss=1 raid=noautodetect plymouth.enable=0 nopti pti=off spectre_v2=off l1tf=off nospec_store_bypass_disable no_stf_barrier"

if ! grep -q "$NEW_GRUB_CMDLINE_VALUE" $GRUB_CONFIG_FILE; then
    echo "Изменение параметров в /etc/default/grub"
    backup_file "$GRUB_CONFIG_FILE"
    sed -i "s/\(GRUB_CMDLINE_LINUX_DEFAULT=\"\)\(.*\)\"/\1$NEW_GRUB_CMDLINE_VALUE\"/" $GRUB_CONFIG_FILE
    update-grub
fi

# Установка sysvinit-core, если установлен systemd
if dpkg -s systemd &> /dev/null; then
    echo "Установка sysvinit-core и переключение на sysvinit"
    backup_file "/etc/inittab"
    cp /usr/share/sysvinit/inittab /etc/inittab
    echo "SYSTEMD_STATS=0" > /etc/script.config
    echo "ЧТОБЫ ВНЕСТИ ИЗМЕНЕНИЯ, НЕОБХОДИМО ПЕРЕЗАГРУЗИТЬСЯ, ВВЕДЯ reboot."
    exit 0
fi

# Удаление systemd, если переменная SYSTEMD_STATS=0
if [ -e "/etc/script.config" ] && grep -q "SYSTEMD_STATS=0" /etc/script.config; then
    echo "Удаление systemd"
    apt-get remove --purge --auto-remove systemd
    echo -e 'Package: *systemd*\nPin: release *\nPin-Priority: -1\n' > /etc/apt/preferences.d/systemd
    apt-get purge systemd*
    echo "SYSTEMD_STATS=0" >> /etc/script.config
    echo "ЧТОБЫ ВНЕСТИ ИЗМЕНЕНИЯ, НЕОБХОДИМО ПЕРЕЗАГРУЗИТЬСЯ, ВВЕДЯ reboot."
    exit 0
fi

# Отключение служб Avahi-daemon, cups, cups-browsed и rsyslog в sysvinit
if [ -e /etc/init.d/avahi-daemon ] || [ -e /etc/init.d/cups ] || [ -e /etc/init.d/cups-browsed ] || [ -e /etc/init.d/rsyslog ]; then
    echo "Отключение служб Avahi-daemon, cups, cups-browsed и rsyslog в sysvinit"
    update-rc.d -f avahi-daemon remove
    service avahi-daemon stop

    update-rc.d -f cups remove
    service cups stop

    update-rc.d -f cups-browsed remove
    service cups-browsed stop

    update-rc.d -f rsyslog remove
    service rsyslog stop
fi

# Установка пакетов alsa-utils, firefox-esr и flameshot, если их нет
if ! dpkg -s alsa-utils firefox-esr flameshot &> /dev/null; then
    echo "Установка пакетов alsa-utils, firefox-esr и flameshot"
    apt-get install -y alsa-utils firefox-esr flameshot
fi

# Очистка и перезагрузка
echo "Выполнение очистки и перезагрузка"
apt-get clean
apt-get autoremove
apt-get autoclean
echo "ЧТОБЫ ВНЕСТИ ИЗМЕНЕНИЯ, НЕОБХОДИМО ПЕРЕЗАГРУЗИТЬСЯ, ВВЕДЯ reboot."
exit 0