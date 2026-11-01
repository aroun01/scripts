#!/bin/sh
# Keenetic + Entware: исключения из VPN для выбранных IPv4-подсетей.
# Читает /opt/etc/amnezia-routes.txt и управляет маршрутами в таблице 4096.
# Назначения из списка идут через провайдера; маршрут по умолчанию остаётся VPN.
# Перед применением проверьте GW, IFACE и TABLE под свою конфигурацию.
# Добавляет маршруты для российских сервисов в таблицу 4096,
# чтобы они шли через провайдера, минуя VPN.
#
# Использование:
#   ./amnezia-add-routes.sh          — добавить маршруты
#   ./amnezia-add-routes.sh del      — удалить маршруты
#   ./amnezia-add-routes.sh check    — проверить маршруты

ROUTES_FILE="/opt/etc/amnezia-routes.txt"
LOG_FILE="/opt/var/log/amnezia-routes.log"

# Параметры вашей сети
GW="YOUR_ISP_GATEWAY"
IFACE="eth2.6"
TABLE="4096"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

[ -f "$ROUTES_FILE" ] || { log "ERROR: $ROUTES_FILE not found"; exit 1; }

ACTION="${1:-add}"

case "$ACTION" in

	add)
    COUNT_OK=0
    COUNT_FAIL=0
    COUNT_SKIP=0
    while read -r cidr; do
        # Пропускаем пустые строки и комментарии
        case "$cidr" in
            ''|\#*) continue ;;
        esac
        cidr=$(echo "$cidr" | tr -d ' \t\r')
        [ -z "$cidr" ] && continue

        # Проверяем, есть ли уже такой маршрут
        if ip route show table "$TABLE" exact "$cidr" 2>/dev/null | grep -q .; then
            COUNT_SKIP=$((COUNT_SKIP + 1))
            continue
        fi

        # Пытаемся добавить
        if ip route add "$cidr" via "$GW" dev "$IFACE" table "$TABLE" 2>/tmp/route_err; then
            COUNT_OK=$((COUNT_OK + 1))
        else
            COUNT_FAIL=$((COUNT_FAIL + 1))
            ERR=$(cat /tmp/route_err)
            echo "$(date '+%Y-%m-%d %H:%M:%S') FAIL $cidr: $ERR" >> "$LOG_FILE"
        fi
    done < "$ROUTES_FILE"
    log "ADD: ok=$COUNT_OK skip=$COUNT_SKIP fail=$COUNT_FAIL"
    echo "Добавлено: $COUNT_OK, пропущено: $COUNT_SKIP, ошибок: $COUNT_FAIL"
    ;;


    del)
        COUNT_OK=0
        while read -r cidr; do
            case "$cidr" in
                ''|\#*) continue ;;
            esac
            cidr=$(echo "$cidr" | tr -d ' \t\r')
            [ -z "$cidr" ] && continue

            if ip route del "$cidr" via "$GW" dev "$IFACE" table "$TABLE" 2>/dev/null; then
                COUNT_OK=$((COUNT_OK + 1))
            fi
        done < "$ROUTES_FILE"
        log "DEL: ok=$COUNT_OK"
        echo "Удалено: $COUNT_OK"
        ;;

    check)
        echo "=== Маршруты в таблице $TABLE ==="
        ip route show table "$TABLE" | grep -v '^default' | grep -v 'dev nwg0' | head -50
        echo ""
        echo "=== Всего не-default маршрутов ==="
        ip route show table "$TABLE" | grep -cv '^default'
        ;;

    *)
        echo "Использование: $0 [add|del|check]"
        exit 1
        ;;
esac
