#!/usr/bin/env bash

# ==============================================================================
# AmneziaWG / WireGuard - Скрипт автоматического определения оптимального MTU
# ==============================================================================
# Возможности:
#   1. Определение MTU активных сетевых интерфейсов хоста (eth0, ens3, en0 и др.)
#   2. Точный замер Path MTU (PMTU) через ICMP пинг с флагом Don't Fragment (DF)
#   3. Автоматическое считывание ICMP Fragmentation Needed ответов маршрутизаторов
#   4. Быстрый бинарный поиск максимального нефрагментированного размера пакета
#   5. Расчет оптимального MTU для WireGuard (IPv4: PMTU-60, IPv6: PMTU-80)
#   6. Расчет оптимального и безопасного MTU для AmneziaWG (1360 - 1420)
#   7. Возможность автоматической записи параметра INIT_MTU в docker-compose.yml (--apply)
# ==============================================================================

set -uo pipefail

# Цветовая палитра
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

# Целевые публичные хосты для проверки
DEFAULT_TARGETS=("1.1.1.1" "8.8.8.8" "77.88.8.8" "9.9.9.9")
CUSTOM_TARGET=""
AUTO_APPLY=false
QUIET_MODE=false
RAW_MODE=false
PING_FLAVOR="linux"

print_banner() {
  if [ "$RAW_MODE" = true ] || [ "$QUIET_MODE" = true ]; then
    return 0
  fi
  echo -e "${CYAN}${BOLD}" >&2
  echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓" >&2
  echo "┃       AmneziaWG / WireGuard - Автоматический замер и расчет MTU       ┃" >&2
  echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛" >&2
  echo -e "${NC}" >&2
}

log_info() {
  if [ "$RAW_MODE" = false ]; then
    echo -e "${BLUE}[ИНФО]${NC} $1" >&2
  fi
}

log_success() {
  if [ "$RAW_MODE" = false ]; then
    echo -e "${GREEN}[УСПЕХ]${NC} $1" >&2
  fi
}

log_warn() {
  if [ "$RAW_MODE" = false ]; then
    echo -e "${YELLOW}[ВНИМАНИЕ]${NC} $1" >&2
  fi
}

log_error() {
  if [ "$RAW_MODE" = false ]; then
    echo -e "${RED}[ОШИБКА]${NC} $1" >&2
  fi
}

log_section() {
  if [ "$RAW_MODE" = false ]; then
    echo "" >&2
    echo -e "${BOLD}${MAGENTA}▶ $1${NC}" >&2
    echo -e "${MAGENTA}------------------------------------------------------------------------${NC}" >&2
  fi
}

show_help() {
  echo -e "${BOLD}Использование:${NC} $0 [ОПЦИИ]"
  echo ""
  echo -e "${BOLD}Описание:${NC}"
  echo "  Скрипт определяет Path MTU (максимальный размер нефрагментированного пакета)"
  echo "  до внешней сети и вычисляет оптимальные значения MTU для WireGuard и AmneziaWG."
  echo ""
  echo -e "${BOLD}Доступные опции:${NC}"
  echo "  -t, --target <IP/HOST>   Указать конкретный IP или домен для замера MTU (по умолчанию: 1.1.1.1, 8.8.8.8)"
  echo "  -a, --apply              Автоматически прописать рассчитанный INIT_MTU в docker-compose.yml"
  echo "  -r, --raw                Вывести только рассчитанное число MTU (удобно для скриптов/CI)"
  echo "  -q, --quiet              Минималистичный вывод"
  echo "  -h, --help               Показать эту справку"
  echo ""
  echo -e "${BOLD}Примеры использования:${NC}"
  echo "  $0                       # Стандартный тест и вывод рекомендаций"
  echo "  $0 --target 1.1.1.1      # Тест до Cloudflare DNS"
  echo "  $0 --apply               # Замер и автоматическая запись INIT_MTU в docker-compose.yml"
  echo "  $0 --raw                 # Получить только число (например: 1420)"
  exit 0
}

# Определение типа ОС и утилиты ping
detect_ping_flavor() {
  local os_type
  os_type="$(uname -s 2>/dev/null || echo 'Linux')"

  if [ "$os_type" = "Darwin" ] || [ "$os_type" = "FreeBSD" ] || [ "$os_type" = "OpenBSD" ]; then
    PING_FLAVOR="bsd"
  elif ping -c 1 -M do 127.0.0.1 &>/dev/null || ping -c 1 -M do -s 56 127.0.0.1 2>&1 | grep -qv "invalid"; then
    PING_FLAVOR="linux"
  else
    PING_FLAVOR="generic"
  fi
}

# Проверка локальных сетевых интерфейсов
check_local_interfaces() {
  log_section "1. Локальные сетевые интерфейсы хоста"

  local detected=false

  # Linux (утилита ip)
  if command -v ip &>/dev/null; then
    local default_iface=""
    default_iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n 1 || true)

    while IFS= read -r line; do
      local ifname
      local ifmtu
      local ifstate
      ifname=$(echo "$line" | awk '{print $2}' | tr -d ':')
      ifmtu=$(echo "$line" | grep -oE 'mtu [0-9]+' | awk '{print $2}')
      ifstate=$(echo "$line" | grep -oE 'state [A-Z]+' | awk '{print $2}')

      # Фильтруем петлю и виртуальные интерфейсы
      if [ -n "$ifname" ] && [ -n "$ifmtu" ] && [ "$ifname" != "lo" ] && [[ ! "$ifname" =~ ^(docker|veth|br-|tun|wg) ]]; then
        detected=true
        if [ "$ifname" = "$default_iface" ]; then
          log_info "Основной интерфейс (${BOLD}${ifname}${NC}, шлюз по умолчанию): MTU = ${BOLD}${GREEN}${ifmtu}${NC} [${ifstate:-UP}]"
        else
          log_info "Сетевой интерфейс ${ifname}: MTU = ${ifmtu} [${ifstate:-UP}]"
        fi
      fi
    done < <(ip -o link show 2>/dev/null || true)
  fi

  # macOS / BSD (route get default + ifconfig)
  if [ "$detected" = false ] && command -v route &>/dev/null && command -v ifconfig &>/dev/null; then
    local def_if=""
    def_if=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}' || true)
    
    if [ -n "$def_if" ]; then
      local def_mtu=""
      local def_ip=""
      def_mtu=$(ifconfig "$def_if" 2>/dev/null | grep -oE 'mtu [0-9]+' | awk '{print $2}' || echo "1500")
      def_ip=$(ifconfig "$def_if" 2>/dev/null | awk '/inet / {print $2}' | head -n 1 || true)
      detected=true
      log_info "Основной интерфейс (${BOLD}${def_if}${NC}): MTU = ${BOLD}${GREEN}${def_mtu}${NC} (IP: ${def_ip:-DHCP})"
    fi
  fi

  if [ "$detected" = false ]; then
    log_info "Интерфейс по умолчанию: стандартный физический MTU = 1500"
  fi
}

# Отправка тестового ICMP пакета заданного размера с флагом DF (Don't Fragment)
# Возвращает 0, если пакет дошел без фрагментации; 1, если пакет фрагментируется или потерян.
probe_ping() {
  local target="$1"
  local payload_size="$2"
  local output=""
  local exit_code=1

  case "${PING_FLAVOR}" in
    bsd)
      # macOS / FreeBSD: -D включает DF, -t таймаут в сек, -s размер полезной нагрузки ICMP
      output=$(ping -c 1 -t 1 -D -s "$payload_size" "$target" 2>&1)
      exit_code=$?
      if [ $exit_code -eq 0 ] && echo "$output" | grep -qE "bytes from|icmp_seq"; then
        if ! echo "$output" | grep -qiE "frag needed|message too long"; then
          return 0
        fi
      fi
      # Проверяем, сообщил ли маршрутизатор точный MTU в сообщении frag needed
      local icmp_reported_mtu=""
      icmp_reported_mtu=$(echo "$output" | grep -oE '(MTU|mtu) [0-9]+' | head -n 1 | awk '{print $2}' || true)
      if [ -n "$icmp_reported_mtu" ] && [ "$icmp_reported_mtu" -ge 1200 ] 2>/dev/null; then
        LAST_REPORTED_MTU="$icmp_reported_mtu"
      fi
      return 1
      ;;

    linux)
      # Linux iputils-ping: -M do запрещает фрагментацию (DF), -W таймаут в сек
      output=$(ping -c 1 -W 1 -M do -s "$payload_size" "$target" 2>&1)
      exit_code=$?
      if [ $exit_code -eq 0 ] && echo "$output" | grep -qE "bytes from|icmp_seq"; then
        if ! echo "$output" | grep -qiE "frag needed|message too long"; then
          return 0
        fi
      fi
      local icmp_reported_mtu=""
      icmp_reported_mtu=$(echo "$output" | grep -oE '(MTU|mtu)=[0-9]+|(MTU|mtu) [0-9]+' | head -n 1 | grep -oE '[0-9]+' || true)
      if [ -n "$icmp_reported_mtu" ] && [ "$icmp_reported_mtu" -ge 1200 ] 2>/dev/null; then
        LAST_REPORTED_MTU="$icmp_reported_mtu"
      fi
      return 1
      ;;

    *)
      output=$(ping -c 1 -W 1 -s "$payload_size" "$target" 2>&1)
      exit_code=$?
      if [ $exit_code -eq 0 ] && echo "$output" | grep -qE "bytes from|icmp_seq"; then
        return 0
      fi
      return 1
      ;;
  esac
}

LAST_REPORTED_MTU=""

# Быстрый поиск максимального нефрагментированного размера полезной нагрузки ICMP
find_max_icmp_payload() {
  local target="$1"
  LAST_REPORTED_MTU=""

  # 1. Проверяем базовую доступность хоста стандартным маленьким пакетом
  if ! probe_ping "$target" 56; then
    return 1
  fi

  # 2. Быстрая проверка стандартного Ethernet MTU 1500 (1472 байта payload + 28 байт IP/ICMP)
  if probe_ping "$target" 1472; then
    echo "1472"
    return 0
  fi

  # 3. Если маршрутизатор сразу прислал ICMP Fragmentation Needed с указанием точного MTU
  if [ -n "$LAST_REPORTED_MTU" ] && [ "$LAST_REPORTED_MTU" -le 1500 ] && [ "$LAST_REPORTED_MTU" -ge 1200 ]; then
    local test_payload=$((LAST_REPORTED_MTU - 28))
    if probe_ping "$target" "$test_payload"; then
      echo "$test_payload"
      return 0
    fi
  fi

  # 4. Проверка стандартного PPPoE MTU 1492 (1464 байта payload)
  if probe_ping "$target" 1464; then
    echo "1464"
    return 0
  fi

  # 5. Проверка стандартного облачного VPS MTU 1420 / 1440 (Hetzner / GCP / AWS Cloud)
  if probe_ping "$target" 1392; then
    # Пробуем проверить диапазон между 1392 и 1464 бинарным поиском
    local low=1392
    local high=1464
    local optimal=1392

    while [ "$low" -le "$high" ]; do
      local mid=$(( (low + high) / 2 ))
      if probe_ping "$target" "$mid"; then
        optimal=$mid
        low=$(( mid + 1 ))
      else
        high=$(( mid - 1 ))
      fi
    done
    echo "$optimal"
    return 0
  fi

  # 6. Полный бинарный поиск от 1200 до 1472
  local low=1200
  local high=1472
  local optimal=0

  while [ "$low" -le "$high" ]; do
    local mid=$(( (low + high) / 2 ))
    if probe_ping "$target" "$mid"; then
      optimal=$mid
      low=$(( mid + 1 ))
    else
      high=$(( mid - 1 ))
    fi
  done

  if [ "$optimal" -gt 0 ]; then
    echo "$optimal"
    return 0
  fi

  return 1
}

# Замер Path MTU до внешних хостов
measure_path_mtu() {
  log_section "2. Замер Path MTU (PMTUD) до внешней сети"

  local targets=()
  if [ -n "$CUSTOM_TARGET" ]; then
    targets=("$CUSTOM_TARGET")
  else
    targets=("${DEFAULT_TARGETS[@]}")
  fi

  local best_pmtu=0
  local tested_target=""

  for target in "${targets[@]}"; do
    log_info "Тестирование канала до ${BOLD}${target}${NC} (ICMP DF probe)..."
    
    local payload
    if payload=$(find_max_icmp_payload "$target"); then
      # Заголовок IPv4 (20 байт) + ICMP заголовок (8 байт) = 28 байт
      local calculated_pmtu=$((payload + 28))
      log_success "Хост ${target}: макс. пакет без фрагментации = ${payload} B ➔ Path MTU = ${BOLD}${GREEN}${calculated_pmtu}${NC}"
      best_pmtu=$calculated_pmtu
      tested_target="$target"
      break
    else
      log_warn "Хост ${target} не ответил или ICMP DF заблокирован фаерволом."
    fi
  done

  if [ "$best_pmtu" -eq 0 ]; then
    log_warn "Не удалось замерить Path MTU автоматически (ICMP эхо заблокировано провайдером)."
    log_info "Используется стандартный эталонный MTU проводного канала: 1500"
    best_pmtu=1500
  fi

  echo "$best_pmtu"
}

# Расчет всех производных значений MTU
calculate_recommendations() {
  local pmtu="$1"

  # WireGuard IPv4 оверхед: 20B IPv4 + 8B UDP + 32B WireGuard = 60 байт
  local wg_ipv4_mtu=$((pmtu - 60))
  # WireGuard IPv6 оверхед: 40B IPv6 + 8B UDP + 32B WireGuard = 80 байт
  local wg_ipv6_mtu=$((pmtu - 80))

  # Для AmneziaWG (AWG) с учетом мусорных пакетов и обфускационных заголовков (H1-H4, I1-I5, S1-S4):
  # Если PMTU = 1500, оптимальный рабочий MTU = 1420 (или 1360 при двойном туннелировании)
  local awg_recommended_mtu=$wg_ipv4_mtu
  if [ "$awg_recommended_mtu" -gt 1420 ]; then
    awg_recommended_mtu=1420
  fi

  # Консервативный безопасный MTU для мобильных сетей (LTE/5G) и роуминга
  local safe_mobile_mtu=1280
  if [ "$awg_recommended_mtu" -lt 1280 ]; then
    safe_mobile_mtu=$awg_recommended_mtu
  fi

  if [ "$RAW_MODE" = true ]; then
    echo "$awg_recommended_mtu"
    return 0
  fi

  log_section "3. Результаты расчета оптимального MTU"

  echo -e "  • ${BOLD}Обнаруженный Path MTU канала:${NC}      ${CYAN}${BOLD}${pmtu}${NC} байт"
  if [ "$pmtu" -eq 1500 ]; then
    echo -e "    ${GREEN}✔ Стандартный Ethernet канал (1500)${NC}"
  elif [ "$pmtu" -eq 1492 ]; then
    echo -e "    ${YELLOW}ℹ Обнаружен канал PPPoE / DSL (1492)${NC}"
  elif [ "$pmtu" -le 1450 ]; then
    echo -e "    ${YELLOW}ℹ Обнаружен облачный VPS (Hetzner / GCP / AWS / OpenStack: ${pmtu})${NC}"
  fi

  echo ""
  echo -e "  • ${BOLD}Оптимальный MTU для WireGuard (IPv4):${NC}  ${BOLD}${GREEN}${wg_ipv4_mtu}${NC} (PMTU - 60)"
  echo -e "  • ${BOLD}Оптимальный MTU для WireGuard (IPv6):${NC}  ${BOLD}${GREEN}${wg_ipv6_mtu}${NC} (PMTU - 80)"
  echo -e "  • ${BOLD}Рекомендуемый MTU для AmneziaWG (AWG):${NC} ${BOLD}${MAGENTA}${awg_recommended_mtu}${NC} (наилучшая скорость и стабильность)"
  echo -e "  • ${BOLD}Консервативный MTU (Mobile LTE / Роуминг):${NC} ${BOLD}${safe_mobile_mtu}${NC} (100% защита от фрагментации)"

  log_section "4. Как применить актуальный MTU в проекте"

  echo -e "${BOLD}1. В файле docker-compose.yml:${NC}"
  echo -e "   Добавьте или обновите параметр в блоке ${CYAN}environment:${NC}"
  echo -e "   ${GREEN}   - INIT_MTU=${awg_recommended_mtu}${NC}"
  echo ""
  echo -e "${BOLD}2. В Web-панели AmneziaWG Easy:${NC}"
  echo -e "   Перейдите в ${CYAN}Настройки (Settings)${NC} ➔ ${CYAN}Интерфейс / MTU${NC}"
  echo -e "   Укажите: ${GREEN}${awg_recommended_mtu}${NC}"
  echo ""
  echo -e "${BOLD}3. В клиентских файлах конфигураций (*.conf):${NC}"
  echo -e "   В блоке ${CYAN}[Interface]${NC}:"
  echo -e "   ${GREEN}MTU = ${awg_recommended_mtu}${NC}"
  echo ""

  if [ "$AUTO_APPLY" = true ]; then
    apply_mtu_to_compose "$awg_recommended_mtu"
  else
    echo -e "💡 ${BOLD}Совет:${NC} Чтобы автоматически прописать это значение в ${BOLD}docker-compose.yml${NC}, запустите:"
    echo -e "   ${BOLD}$0 --apply${NC}"
  fi
}

# Автоматическое применение MTU в docker-compose.yml
apply_mtu_to_compose() {
  local target_mtu="$1"

  log_section "5. Применение MTU в docker-compose.yml"

  if [ ! -f "$COMPOSE_FILE" ]; then
    log_error "Файл ${COMPOSE_FILE} не найден по пути: ${COMPOSE_FILE}"
    return 1
  fi

  # 1. Если строка - INIT_MTU=... уже раскомментирована
  if grep -qE "^[[:space:]]*-[[:space:]]*INIT_MTU=" "$COMPOSE_FILE"; then
    if sed -i.bak -E "s/^[[:space:]]*-[[:space:]]*INIT_MTU=[0-9]+/      - INIT_MTU=${target_mtu}/" "$COMPOSE_FILE" 2>/dev/null || \
       sed -i '' -E "s/^[[:space:]]*-[[:space:]]*INIT_MTU=[0-9]+/      - INIT_MTU=${target_mtu}/" "$COMPOSE_FILE" 2>/dev/null; then
      rm -f "${COMPOSE_FILE}.bak"
      log_success "Значение ${BOLD}INIT_MTU=${target_mtu}${NC} успешно обновлено в docker-compose.yml!"
      return 0
    fi
  fi

  # 2. Если строка закомментирована
  if grep -qE "^[[:space:]]*#[[:space:]]*-[[:space:]]*INIT_MTU=" "$COMPOSE_FILE"; then
    if sed -i.bak -E "s/^[[:space:]]*#[[:space:]]*-[[:space:]]*INIT_MTU=[0-9]*/      - INIT_MTU=${target_mtu}/" "$COMPOSE_FILE" 2>/dev/null || \
       sed -i '' -E "s/^[[:space:]]*#[[:space:]]*-[[:space:]]*INIT_MTU=[0-9]*/      - INIT_MTU=${target_mtu}/" "$COMPOSE_FILE" 2>/dev/null; then
      rm -f "${COMPOSE_FILE}.bak"
      log_success "Строка ${BOLD}INIT_MTU=${target_mtu}${NC} активирована в docker-compose.yml!"
      return 0
    fi
  fi

  # 3. Вставка после INIT_ALLOWED_IPS
  if grep -q "INIT_ALLOWED_IPS" "$COMPOSE_FILE"; then
    if sed -i.bak "/INIT_ALLOWED_IPS/a\\
      # MTU для сервера WireGuard и клиентских профилей\\
      - INIT_MTU=${target_mtu}
" "$COMPOSE_FILE" 2>/dev/null || \
       sed -i '' "/INIT_ALLOWED_IPS/a\\
      # MTU для сервера WireGuard и клиентских профилей\\
      - INIT_MTU=${target_mtu}
" "$COMPOSE_FILE" 2>/dev/null; then
      rm -f "${COMPOSE_FILE}.bak"
      log_success "Параметр ${BOLD}INIT_MTU=${target_mtu}${NC} успешно добавлен в docker-compose.yml!"
      return 0
    fi
  fi

  log_warn "Не удалось автоматически изменить docker-compose.yml. Добавьте '- INIT_MTU=${target_mtu}' в блок environment."
  return 1
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|--target)
        CUSTOM_TARGET="$2"
        shift 2
        ;;
      -a|--apply)
        AUTO_APPLY=true
        shift
        ;;
      -r|--raw)
        RAW_MODE=true
        shift
        ;;
      -q|--quiet)
        QUIET_MODE=true
        shift
        ;;
      -h|--help)
        show_help
        ;;
      *)
        echo "Неизвестный параметр: $1"
        show_help
        ;;
    esac
  done
}

main() {
  parse_arguments "$@"

  detect_ping_flavor
  print_banner

  if [ "$RAW_MODE" = false ]; then
    check_local_interfaces
  fi

  local pmtu
  pmtu=$(measure_path_mtu)

  calculate_recommendations "$pmtu"
}

main "$@"
