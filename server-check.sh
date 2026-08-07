#!/usr/bin/env bash

# ==============================================================================
# AmneziaWG Easy (AWG) - Скрипт диагностики сервера, модуля ядра и Docker
# ==============================================================================
# Возможности скрипта:
#   1. Проверка модуля ядра (amneziawg / wireguard)
#   2. Установка модуля ядра AmneziaWG в зависимости от ОС (DKMS / PPA / Исходники)
#   3. Проверка конфигурации Docker и Docker Compose
#   4. Проверка параметров хоста (sysctl forwarding, доступность портов, фаервол)
#   5. Управление жизненным циклом проекта (запуск, остановка, перезапуск, пересборка)
#   6. Глубокая проверка здоровья запущенного контейнера и Web UI
# ==============================================================================

set -uo pipefail

# Цвета и стили вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # Без цвета

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
CONTAINER_NAME="wg-easy"
WEB_PORT=51821
VPN_PORT=51820

# ------------------------------------------------------------------------------
# Вспомогательные функции вывода
# ------------------------------------------------------------------------------

print_banner() {
  echo -e "${CYAN}${BOLD}"
  echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
  echo "┃       AmneziaWG Easy (AWG) - Управление сервером и диагностика         ┃"
  echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
  echo -e "${NC}"
}

log_info() {
  echo -e "${BLUE}[ИНФО]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[УСПЕХ]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[ВНИМАНИЕ]${NC} $1"
}

log_error() {
  echo -e "${RED}[ОШИБКА]${NC} $1"
}

log_section() {
  echo ""
  echo -e "${BOLD}${MAGENTA}▶ $1${NC}"
  echo -e "${MAGENTA}------------------------------------------------------------------------${NC}"
}

show_help() {
  echo -e "${BOLD}Использование:${NC} $0 [ОПЦИЯ]"
  echo ""
  echo -e "${BOLD}Доступные опции:${NC}"
  echo "  --all              (По умолчанию) Полная диагностика, предложение установки модуля, запуск и чек здоровья"
  echo "  --check            Запустить полную диагностику (ядро, docker, хост, sysctl) без изменения системы"
  echo "  --install-module   Определить ОС и установить модуль ядра AmneziaWG (DKMS/PPA)"
  echo "  --start            Запустить проект через Docker Compose"
  echo "  --stop             Остановить проект"
  echo "  --restart          Перезапустить контейнеры проекта"
  echo "  --rebuild          Подтянуть/пересобрать образ и запустить проект"
  echo "  --health           Проверить статус контейнера, интерфейса awg и доступность Web UI"
  echo "  --npm              Проверить статус и настройки Nginx Proxy Manager (SSL / Reverse Proxy)"
  echo "  --start-npm        Запустить / развернуть Nginx Proxy Manager (порт 81)"
  echo "  --logs             Показать последние логи контейнера в реальном времени"
  echo "  --fix-sysctl       Применить и сохранить рекомендуемые sysctl параметры форвардинга на хосте"
  echo "  -h, --help         Показать эту справку"
  echo ""
  echo -e "${BOLD}Примеры использования:${NC}"
  echo "  sudo $0                     # Полная настройка, проверка, запуск и чек здоровья"
  echo "  $0 --check                  # Только диагностика окружения"
  echo "  $0 --npm                    # Проверка веб-панели Nginx Proxy Manager (:81) и SSL"
  echo "  sudo $0 --install-module    # Установка модуля ядра AmneziaWG на сервере"
  echo "  $0 --health                 # Чек здоровья запущенного контейнера и Web UI"
  echo "  $0 --logs                   # Просмотр логов контейнера"
  exit 0
}

# Поиск команды docker compose (поддержка плагина 'docker compose' и 'docker-compose')
get_docker_compose_cmd() {
  if docker compose version &> /dev/null; then
    echo "docker compose"
  elif command -v docker-compose &> /dev/null; then
    echo "docker-compose"
  else
    echo ""
  fi
}

# ------------------------------------------------------------------------------
# 1. Проверка модуля ядра AmneziaWG и WireGuard
# ------------------------------------------------------------------------------

check_kernel_module() {
  log_section "1. Проверка модуля ядра"
  
  local kernel_version
  kernel_version="$(uname -r 2>/dev/null || echo 'неизвестно')"
  log_info "Текущее ядро Linux: ${BOLD}${kernel_version}${NC}"

  local awg_loaded=false
  local wg_loaded=false

  # Проверка загруженности модуля amneziawg в ядре
  if lsmod 2>/dev/null | grep -q "^amneziawg\b"; then
    awg_loaded=true
    log_success "Модуль ядра AmneziaWG (${BOLD}amneziawg${NC}) ${BOLD}ЗАГРУЖЕН${NC} в ядро!"
  else
    # Попытка modprobe при наличии root прав
    if [ "$(id -u)" -eq 0 ]; then
      if modprobe amneziawg 2>/dev/null; then
        awg_loaded=true
        log_success "Модуль ядра AmneziaWG (${BOLD}amneziawg${NC}) успешно загружен через modprobe!"
      fi
    fi
  fi

  if [ "$awg_loaded" = false ]; then
    # Проверка наличия модуля в файловой системе /lib/modules
    if modinfo amneziawg &> /dev/null; then
      log_warn "Модуль ядра AmneziaWG установлен в /lib/modules, но сейчас не загружен."
      log_info "Выполните команду '${BOLD}sudo modprobe amneziawg${NC}' для загрузки."
    else
      log_warn "Модуль ядра AmneziaWG (${BOLD}amneziawg${NC}) НЕ установлен на хосте."
      log_info "Примечание: В контейнере есть userspace-реализация (amneziawg-go),"
      log_info "            однако нативный модуль ядра обеспечивает наивысшую скорость и минимальную нагрузку на CPU."
    fi
  fi

  # Проверка стандартного WireGuard
  if lsmod 2>/dev/null | grep -q "^wireguard\b"; then
    wg_loaded=true
    log_info "Стандартный модуль ядра WireGuard (wireguard) также присутствует."
  fi

  return 0
}

# ------------------------------------------------------------------------------
# 2. Установка модуля ядра под конкретный дистрибутив ОС
# ------------------------------------------------------------------------------

detect_os() {
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION_ID="${VERSION_ID:-}"
    OS_NAME="${NAME:-Linux}"
  elif command -v lsb_release &> /dev/null; then
    OS_ID="$(lsb_release -si | tr '[:upper:]' '[:lower:]')"
    OS_VERSION_ID="$(lsb_release -sr)"
    OS_NAME="$(lsb_release -sd)"
  else
    OS_ID="$(uname -s | tr '[:upper:]' '[:lower:]')"
    OS_VERSION_ID=""
    OS_NAME="Generic Linux"
  fi
}

install_kernel_module() {
  log_section "2. Установка модуля ядра AmneziaWG"

  if [ "$(id -u)" -ne 0 ]; then
    log_error "Для установки модуля ядра требуются права root. Запустите через sudo:"
    echo -e "      ${BOLD}sudo $0 --install-module${NC}"
    return 1
  fi

  detect_os
  log_info "Определена операционная система: ${BOLD}${OS_NAME} (${OS_ID} ${OS_VERSION_ID})${NC}"
  log_info "Версия ядра: ${BOLD}$(uname -r)${NC}"

  # Если модуль уже загружен, запрашиваем подтверждение
  if lsmod | grep -q "^amneziawg\b"; then
    log_success "Модуль amneziawg уже загружен в ядро!"
    read -r -p "Хотите переустановить/пересобрать модуль заново? [y/N]: " rechoice
    if [[ ! "$rechoice" =~ ^[Yy]$ ]]; then
      log_info "Переустановка модуля пропущена."
      return 0
    fi
  fi

  case "${OS_ID}" in
    ubuntu)
      log_info "Установка AmneziaWG через официальный PPA репозиторий для Ubuntu..."
      apt-get update -y
      apt-get install -y software-properties-common linux-headers-"$(uname -r)" dkms git build-essential
      
      # Добавление репозитория Amnezia PPA
      if ! grep -q "amnezia/ppa" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        add-apt-repository -y ppa:amnezia/ppa || true
        apt-get update -y
      fi

      if apt-get install -y amneziawg-dkms amneziawg-tools 2>/dev/null; then
        log_success "Пакет amneziawg-dkms успешно установлен из PPA репозитория."
      else
        log_warn "Пакет из PPA недоступен для текущей версии Ubuntu. Сборка из исходников через DKMS..."
        install_module_from_source_dkms
      fi
      ;;

    debian)
      log_info "Установка AmneziaWG для Debian..."
      apt-get update -y
      apt-get install -y linux-headers-"$(uname -r)" dkms git build-essential sudo curl
      
      # Сборка через DKMS
      install_module_from_source_dkms
      ;;

    centos|rhel|almalinux|rocky|fedora)
      log_info "Установка AmneziaWG для семейств RHEL / Fedora..."
      if command -v dnf &> /dev/null; then
        dnf install -y epel-release || true
        dnf install -y "kernel-devel-$(uname -r)" "kernel-headers-$(uname -r)" dkms git gcc make
      else
        yum install -y epel-release || true
        yum install -y "kernel-devel-$(uname -r)" "kernel-headers-$(uname -r)" dkms git gcc make
      fi
      install_module_from_source_dkms
      ;;

    arch|manjaro|endeavouros)
      log_info "Установка AmneziaWG для Arch Linux..."
      pacman -Sy --noconfirm linux-headers dkms git base-devel
      install_module_from_source_dkms
      ;;

    alpine)
      log_info "Обнаружен Alpine Linux. Установка зависимостей для сборки..."
      apk add --no-cache linux-headers build-base git dkms
      install_module_from_source_dkms
      ;;

    *)
      log_warn "Неизвестный дистрибутив (${OS_ID}). Попытка универсальной сборки DKMS из исходников..."
      install_module_from_source_dkms
      ;;
  esac

  # Загрузка модуля в память
  log_info "Загрузка модуля ядра amneziawg..."
  modprobe amneziawg || {
    log_error "Не удалось загрузить модуль amneziawg с помощью modprobe."
    return 1
  }

  # Добавление в автозагрузку при старте ОС
  if [ -d /etc/modules-load.d ]; then
    echo "amneziawg" > /etc/modules-load.d/amneziawg.conf
    log_success "Настроена автозагрузка модуля в /etc/modules-load.d/amneziawg.conf"
  elif [ -f /etc/modules ]; then
    if ! grep -q "^amneziawg" /etc/modules; then
      echo "amneziawg" >> /etc/modules
      log_success "Настроена автозагрузка модуля в /etc/modules"
    fi
  fi

  log_success "Модуль ядра AmneziaWG успешно установлен и активирован!"
  return 0
}

install_module_from_source_dkms() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  log_info "Клонирование официального репозитория модуля AmneziaWG в ${tmp_dir}..."

  git clone --depth 1 https://github.com/amnezia-vpn/amneziawg-linux-kernel-module.git "${tmp_dir}/amneziawg"
  
  local module_version="1.0.0"
  if [ -f "${tmp_dir}/amneziawg/version.h" ]; then
    module_version="$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "${tmp_dir}/amneziawg/version.h" | head -n 1 || echo '1.0.0')"
  fi

  local dkms_dest="/usr/src/amneziawg-${module_version}"
  mkdir -p "${dkms_dest}"
  cp -r "${tmp_dir}/amneziawg/src/"* "${dkms_dest}/"

  # Создание конфигурации dkms.conf
  if [ ! -f "${dkms_dest}/dkms.conf" ]; then
    cat << 'EOF' > "${dkms_dest}/dkms.conf"
PACKAGE_NAME="amneziawg"
PACKAGE_VERSION="1.0.0"
BUILT_MODULE_NAME[0]="amneziawg"
DEST_MODULE_LOCATION[0]="/kernel/net/wireguard"
AUTOINSTALL="yes"
EOF
    sed -i "s/PACKAGE_VERSION=\"1.0.0\"/PACKAGE_VERSION=\"${module_version}\"/" "${dkms_dest}/dkms.conf"
  fi

  # Сборка и установка через DKMS
  if command -v dkms &> /dev/null; then
    dkms remove "amneziawg/${module_version}" --all 2>/dev/null || true
    dkms add "amneziawg/${module_version}"
    dkms build "amneziawg/${module_version}"
    dkms install "amneziawg/${module_version}" --force
    log_success "DKMS модуль amneziawg/${module_version} успешно собран и установлен."
  else
    log_info "DKMS не найден, выполняем прямую сборку через make..."
    cd "${tmp_dir}/amneziawg/src"
    make
    make install
    depmod -a
    cd "${SCRIPT_DIR}"
  fi

  rm -rf "${tmp_dir}"
}

# ------------------------------------------------------------------------------
# 3. Проверка Docker и Docker Compose
# ------------------------------------------------------------------------------

check_docker_environment() {
  log_section "3. Проверка окружения Docker и Docker Compose"

  # Проверка наличия утилиты docker
  if ! command -v docker &> /dev/null; then
    log_error "Docker не установлен в системе."
    log_info "Установите Docker официальным скриптом: curl -fsSL https://get.docker.com | sh"
    return 1
  fi
  log_success "Утилита Docker установлена: $(docker --version)"

  # Проверка запущенного Docker демона
  if ! docker info &> /dev/null; then
    log_error "Демон Docker не запущен или у текущего пользователя нет прав."
    log_info "Запустите службу: '${BOLD}sudo systemctl start docker${NC}'"
    log_info "Или добавьте пользователя в группу docker: '${BOLD}sudo usermod -aG docker $USER${NC}'"
    return 1
  fi
  log_success "Демон Docker запущен и доступен."

  # Проверка Docker Compose
  local compose_cmd
  compose_cmd="$(get_docker_compose_cmd)"
  if [ -z "$compose_cmd" ]; then
    log_error "Docker Compose не найден (нет ни 'docker compose', ни 'docker-compose')."
    log_info "Установите плагин: 'sudo apt-get install docker-compose-plugin' или через ваш менеджер пакетов."
    return 1
  fi
  log_success "Docker Compose доступен: ${BOLD}${compose_cmd}${NC} ($(${compose_cmd} version 2>/dev/null || true))"

  # Проверка наличия docker-compose.yml
  if [ ! -f "${COMPOSE_FILE}" ]; then
    log_error "Файл docker-compose.yml не найден по пути: ${COMPOSE_FILE}"
    return 1
  fi
  log_success "Файл docker-compose.yml найден."

  return 0
}

# ------------------------------------------------------------------------------
# 4. Проверка параметров хоста, сетевых sysctl и фаервола
# ------------------------------------------------------------------------------

check_host_sysctls() {
  log_section "4. Проверка сетевых параметров хоста и sysctl"

  local v4_fwd
  local v6_fwd
  v4_fwd="$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo '0')"
  v6_fwd="$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null || echo '0')"

  if [ "$v4_fwd" = "1" ]; then
    log_success "IPv4 форвардинг (net.ipv4.ip_forward) ${BOLD}ВКЛЮЧЕН${NC} (1)."
  else
    log_warn "IPv4 форвардинг ${BOLD}ОТКЛЮЧЕН${NC} (0). Маршрутизация VPN требует включенного форвардинга."
    log_info "Выполните '${BOLD}sudo $0 --fix-sysctl${NC}', чтобы автоматически применить и сохранить параметры."
  fi

  if [ "$v6_fwd" = "1" ]; then
    log_success "IPv6 форвардинг (net.ipv6.conf.all.forwarding) ${BOLD}ВКЛЮЧЕН${NC} (1)."
  else
    log_warn "IPv6 форвардинг ${BOLD}ОТКЛЮЧЕН${NC} (0). (Требуется только при использовании IPv6 VPN)."
  fi

  # Проверка занятости портов на хосте
  log_info "Проверка доступности портов на хосте..."
  if command -v ss &> /dev/null; then
    if ss -tlpn | grep -q ":${WEB_PORT}\b"; then
      log_warn "Порт ${WEB_PORT}/tcp (Web UI) уже занят на хосте."
    else
      log_success "Порт ${WEB_PORT}/tcp (Web UI) свободен."
    fi

    if ss -ulpn | grep -q ":${VPN_PORT}\b"; then
      log_warn "Порт ${VPN_PORT}/udp (AmneziaWG VPN) уже занят на хосте."
    else
      log_success "Порт ${VPN_PORT}/udp (AmneziaWG VPN) свободен."
    fi
  elif command -v netstat &> /dev/null; then
    if netstat -tlpn 2>/dev/null | grep -q ":${WEB_PORT}\b"; then
      log_warn "Порт ${WEB_PORT}/tcp занят."
    fi
  fi

  # Проверка активных фаерволов (UFW / Firewalld)
  if command -v ufw &> /dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    log_warn "Фаервол UFW АКТИВЕН. Убедитесь, что нужные порты открыты:"
    log_info "  sudo ufw allow ${VPN_PORT}/udp comment 'AmneziaWG VPN'"
    log_info "  sudo ufw allow ${WEB_PORT}/tcp comment 'AmneziaWG Web UI'"
  elif command -v firewall-cmd &> /dev/null && firewall-cmd --state &>/dev/null; then
    log_warn "Фаервол Firewalld АКТИВЕН. Убедитесь, что нужные порты открыты:"
    log_info "  sudo firewall-cmd --add-port=${VPN_PORT}/udp --permanent"
    log_info "  sudo firewall-cmd --add-port=${WEB_PORT}/tcp --permanent"
    log_info "  sudo firewall-cmd --reload"
  fi

  return 0
}

apply_sysctl_fixes() {
  log_section "Применение и сохранение сетевых параметров sysctl на хосте"

  if [ "$(id -u)" -ne 0 ]; then
    log_error "Применение настроек sysctl требует прав root. Запустите: sudo $0 --fix-sysctl"
    return 1
  fi

  sysctl -w net.ipv4.ip_forward=1
  sysctl -w net.ipv4.conf.all.src_valid_mark=1
  sysctl -w net.ipv6.conf.all.forwarding=1 2>/dev/null || true

  # Сохранение в файл конфигурации /etc/sysctl.d/99-wireguard.conf
  cat << 'EOF' > /etc/sysctl.d/99-wireguard.conf
net.ipv4.ip_forward=1
net.ipv4.conf.all.src_valid_mark=1
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
EOF

  log_success "Параметры успешно применены и сохранены в /etc/sysctl.d/99-wireguard.conf"
}

# ------------------------------------------------------------------------------
# 5. Управление проектом (запуск, остановка, перезапуск)
# ------------------------------------------------------------------------------

start_project() {
  log_section "5. Запуск проекта AmneziaWG Easy"
  local compose_cmd
  compose_cmd="$(get_docker_compose_cmd)"

  if [ -z "$compose_cmd" ]; then
    log_error "Docker Compose не найден."
    return 1
  fi

  cd "${SCRIPT_DIR}"
  log_info "Выполнение команды: ${BOLD}${compose_cmd} up -d${NC}"
  ${compose_cmd} up -d

  log_info "Ожидание инициализации сервисов (5 сек)..."
  sleep 5

  check_health
}

stop_project() {
  log_section "Остановка проекта AmneziaWG Easy"
  local compose_cmd
  compose_cmd="$(get_docker_compose_cmd)"
  cd "${SCRIPT_DIR}"
  ${compose_cmd} down
  log_success "Проект успешно остановлен."
}

restart_project() {
  log_section "Перезапуск проекта AmneziaWG Easy"
  local compose_cmd
  compose_cmd="$(get_docker_compose_cmd)"
  cd "${SCRIPT_DIR}"
  ${compose_cmd} restart
  log_info "Ожидание перезапуска (5 сек)..."
  sleep 5
  check_health
}

rebuild_project() {
  log_section "Пересборка / обновление и запуск проекта"
  local compose_cmd
  compose_cmd="$(get_docker_compose_cmd)"
  cd "${SCRIPT_DIR}"
  ${compose_cmd} pull || true
  ${compose_cmd} up -d --build --force-recreate
  log_info "Ожидание запуска (5 сек)..."
  sleep 5
  check_health
}

show_logs() {
  local compose_cmd
  compose_cmd="$(get_docker_compose_cmd)"
  cd "${SCRIPT_DIR}"
  ${compose_cmd} logs -f --tail=100
}

# ------------------------------------------------------------------------------
# 6. Проверка Nginx Proxy Manager (Reverse Proxy / HTTPS SSL)
# ------------------------------------------------------------------------------

check_npm_status() {
  log_section "Проверка Nginx Proxy Manager (SSL / Reverse Proxy)"

  local npm_id
  npm_id="$(docker ps -q -f "name=nginx-proxy-manager" | head -n 1)"

  if [ -n "$npm_id" ]; then
    log_success "Nginx Proxy Manager ${BOLD}ЗАПУЩЕН${NC} (Контейнер: ${npm_id:0:12})."
    echo ""
    echo -e "${GREEN}${BOLD}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
    echo -e "${GREEN}${BOLD}┃             ИНТЕРФЕЙС И ДОСТУП NGINX PROXY MANAGER                    ┃${NC}"
    echo -e "${GREEN}${BOLD}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
    echo -e "${GREEN}┃ Веб-панель управления:  ${CYAN}http://<IP_СЕРВЕРА>:81${GREEN}                               ┃"
    echo -e "${GREEN}┃ Логин по умолчанию:     ${CYAN}admin@example.com${GREEN}                                    ┃"
    echo -e "${GREEN}┃ Пароль по умолчанию:    ${CYAN}changeme${GREEN}                                             ┃"
    echo -e "${GREEN}┃ Публичный HTTP (порт):  ${CYAN}80/tcp (Let's Encrypt challenge & redirect)${GREEN}          ┃"
    echo -e "${GREEN}┃ Публичный HTTPS (порт): ${CYAN}443/tcp (SSL/TLS трафик)${GREEN}                             ┃"
    echo -e "${GREEN}${BOLD}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
    echo -e "${GREEN}┃ ${BOLD}Как подключить wg-easy в веб-панели NPM:${NC}${GREEN}                              ┃"
    echo -e "${GREEN}┃ 1. Зайдите в Hosts -> Proxy Hosts -> Add Proxy Host                    ┃"
    echo -e "${GREEN}┃ 2. Domain Names:        ${CYAN}ваш_домен (например, vpn.example.com)${GREEN}          ┃"
    echo -e "${GREEN}┃ 3. Forward Scheme:      ${CYAN}http${GREEN}                                                 ┃"
    echo -e "${GREEN}┃ 4. Forward Hostname/IP: ${CYAN}wg-easy${GREEN} (или 10.42.42.42)                            ┃"
    echo -e "${GREEN}┃ 5. Forward Port:        ${CYAN}51821${GREEN}                                                ┃"
    echo -e "${GREEN}┃ 6. Вкладка SSL:         ${CYAN}Request a new SSL Certificate (Let's Encrypt)${GREEN}        ┃"
    echo -e "${GREEN}┃                         ${CYAN}Включите 'Force SSL' и 'HTTP/2 Support'${GREEN}              ┃"
    echo -e "${GREEN}${BOLD}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
  else
    log_warn "Контейнер 'nginx-proxy-manager' сейчас не запущен."
    log_info "Для запуска Nginx Proxy Manager выполните: '${BOLD}$0 --start-npm${NC}'"
  fi
}

start_npm() {
  log_section "Запуск Nginx Proxy Manager"
  local compose_cmd
  compose_cmd="$(get_docker_compose_cmd)"
  cd "${SCRIPT_DIR}"
  log_info "Запуск контейнера nginx-proxy-manager..."
  ${compose_cmd} up -d npm
  sleep 3
  check_npm_status
}

# ------------------------------------------------------------------------------
# 7. Глубокий чек здоровья запущенного проекта (Health Check)
# ------------------------------------------------------------------------------

check_health() {
  log_section "7. Проверка здоровья и статуса сервисов"

  # Поиск контейнера wg-easy
  local container_id
  container_id="$(docker ps -q -f "name=${CONTAINER_NAME}" | head -n 1)"

  if [ -z "$container_id" ]; then
    # Проверка, существует ли остановленный контейнер
    local stopped_id
    stopped_id="$(docker ps -a -q -f "name=${CONTAINER_NAME}" | head -n 1)"
    if [ -n "$stopped_id" ]; then
      local status
      status="$(docker inspect --format='{{.State.Status}}' "$stopped_id" 2>/dev/null || echo 'unknown')"
      log_error "Контейнер '${CONTAINER_NAME}' существует, но НЕ запущен! Текущий статус: ${BOLD}${status}${NC}"
      log_info "Последние строки логов контейнера:"
      docker logs --tail=20 "$stopped_id"
    else
      log_error "Контейнер с именем '${CONTAINER_NAME}' не найден. Запустите проект командой: '$0 --start'"
    fi
    return 1
  fi

  # Детали контейнера
  local container_status
  local health_status
  local ip_addr
  local created_at

  container_status="$(docker inspect --format='{{.State.Status}}' "$container_id")"
  health_status="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container_id")"
  ip_addr="$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$container_id")"
  created_at="$(docker inspect --format='{{.Created}}' "$container_id")"

  log_success "Контейнер '${CONTAINER_NAME}' работает: ${BOLD}${container_status^^}${NC} (ID: ${container_id:0:12})"
  log_info "  - Внутренний IP:   ${ip_addr:-Н/Д}"
  log_info "  - Docker Health:   ${health_status}"
  log_info "  - Время создания:  ${created_at}"

  # Проверка интерфейса AmneziaWG внутри контейнера
  log_info "Проверка интерфейса AmneziaWG внутри контейнера..."
  if docker exec "$container_id" awg show &> /dev/null; then
    log_success "Интерфейс AmneziaWG (${BOLD}awg show${NC}) активен и отвечает внутри контейнера!"
    local iface_dump
    iface_dump="$(docker exec "$container_id" awg show 2>/dev/null || true)"
    if [ -n "$iface_dump" ]; then
      echo -e "${CYAN}--- Состояние интерфейса ---${NC}"
      echo "$iface_dump" | sed 's/^/  /'
      echo -e "${CYAN}----------------------------${NC}"
    fi
  elif docker exec "$container_id" wg show &> /dev/null; then
    log_success "Интерфейс WireGuard (${BOLD}wg show${NC}) активен внутри контейнера."
  else
    log_warn "Интерфейс WireGuard пока не инициализирован или находится в процессе запуска."
  fi

  # Проверка отклика Web UI (HTTP проба)
  log_info "Проверка доступности Web UI по адресу http://127.0.0.1:${WEB_PORT}..."
  local http_code
  http_code="$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 4 "http://127.0.0.1:${WEB_PORT}/" || echo "failed")"

  if [[ "$http_code" =~ ^(200|302|301|307|308|401)$ ]]; then
    log_success "HTTP-проба Web UI вернула статус ${BOLD}${http_code}${NC} (Успешно)."
  else
    log_warn "HTTP-проба Web UI вернула код: ${BOLD}${http_code}${NC} (панель может еще загружаться)."
  fi

  # Итоговая сводка
  echo ""
  echo -e "${GREEN}${BOLD}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
  echo -e "${GREEN}${BOLD}┃                СВОДКА ПРОВЕРКИ ЗДОРОВЬЯ: СЕРВИС РАБОТАЕТ               ┃${NC}"
  echo -e "${GREEN}${BOLD}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
  echo -e "${GREEN}┃ Адрес Web UI:       ${CYAN}http://<IP_СЕРВЕРА>:${WEB_PORT}${GREEN}                               ┃"
  echo -e "${GREEN}┃ Порт AmneziaWG VPN: ${CYAN}${VPN_PORT}/udp${GREEN}                                            ┃"
  echo -e "${GREEN}┃ Статус контейнера:  ${CYAN}Запущен (${container_id:0:12})${GREEN}                                ┃"
  echo -e "${GREEN}${BOLD}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

  # Также проверяем статус Nginx Proxy Manager, если он активен
  local npm_check
  npm_check="$(docker ps -q -f "name=nginx-proxy-manager" | head -n 1)"
  if [ -n "$npm_check" ]; then
    check_npm_status
  fi

  return 0
}

# ------------------------------------------------------------------------------
# Основной поток выполнения
# ------------------------------------------------------------------------------

main() {
  local action="${1:---all}"

  print_banner

  case "$action" in
    --check)
      check_kernel_module
      check_docker_environment
      check_host_sysctls
      check_health || true
      ;;

    --install-module)
      install_kernel_module
      ;;

    --fix-sysctl)
      apply_sysctl_fixes
      ;;

    --start)
      start_project
      ;;

    --npm|--npm-status)
      check_npm_status
      ;;

    --start-npm)
      start_npm
      ;;

    --stop)
      stop_project
      ;;

    --restart)
      restart_project
      ;;

    --rebuild)
      rebuild_project
      ;;

    --health)
      check_health
      ;;

    --logs)
      show_logs
      ;;

    -h|--help)
      show_help
      ;;

    --all|"")
      # Полный стандартный сценарий
      check_kernel_module
      
      # Если модуль ядра отсутствует и скрипт запущен под root, предлагаем установить
      if ! lsmod 2>/dev/null | grep -q "^amneziawg\b"; then
        echo ""
        if [ "$(id -u)" -eq 0 ]; then
          read -r -p "Модуль ядра AmneziaWG не загружен. Хотите установить его прямо сейчас? [y/N]: " inst_choice
          if [[ "$inst_choice" =~ ^[Yy]$ ]]; then
            install_kernel_module || log_warn "Продолжаем работу через userspace fallback..."
          fi
        else
          log_info "Подсказка: Для установки нативного модуля ядра запустите '${BOLD}sudo $0 --install-module${NC}'."
        fi
      fi

      check_docker_environment
      check_host_sysctls

      # Запуск проекта
      start_project
      ;;

    *)
      log_error "Неизвестный параметр: $action"
      show_help
      ;;
  esac
}

main "${@:-}"
