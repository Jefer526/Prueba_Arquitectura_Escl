#!/bin/bash
# ============================================
# AI Ecosystem - Stack Manager
# Usage: ./stack-manager.sh {start|stop|restart|status|logs|backup|health}
# ============================================
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/opt/ai-ecosystem}"
cd "${PROJECT_DIR}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; }

case "${1:-help}" in
  start)
    log "Starting AI Ecosystem stack..."
    docker compose up -d --remove-orphans
    sleep 10
    log "Stack started. Current status:"
    docker compose ps
    ;;

  stop)
    warn "Stopping stack..."
    docker compose down
    log "Stack stopped."
    ;;

  restart)
    warn "Restarting stack..."
    docker compose down
    docker compose up -d --remove-orphans
    sleep 10
    log "Stack restarted."
    docker compose ps
    ;;

  status)
    echo "═══════════════════════════════════════════"
    echo "  📊 AI Ecosystem - Stack Status"
    echo "═══════════════════════════════════════════"
    echo ""
    docker compose ps
    echo ""
    echo "── Memory Usage ──────────────────────────"
    docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.CPUPerc}}"
    echo ""
    echo "── System Memory ─────────────────────────"
    free -h
    echo ""
    echo "── Disk Usage ────────────────────────────"
    df -h / | tail -1
    echo ""
    echo "── Docker Volumes ────────────────────────"
    docker system df -v 2>/dev/null | head -20 || docker system df
    ;;

  logs)
    SERVICE="${2:-}"
    if [ -n "$SERVICE" ]; then
      docker compose logs -f --tail=100 "$SERVICE"
    else
      docker compose logs -f --tail=50
    fi
    ;;

  backup)
    BACKUP_DIR="${PROJECT_DIR}/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "${BACKUP_DIR}"
    log "Backing up databases to ${BACKUP_DIR}..."

    # PostgreSQL
    if docker exec postgres pg_dump -U chatwoot chatwoot_production > "${BACKUP_DIR}/postgres.sql" 2>/dev/null; then
      log "PostgreSQL backup: OK ($(du -sh "${BACKUP_DIR}/postgres.sql" | cut -f1))"
    else
      err "PostgreSQL backup: FAILED"
    fi

    # MongoDB
    if docker exec mongodb mongodump --archive --gzip > "${BACKUP_DIR}/mongo.archive.gz" 2>/dev/null; then
      log "MongoDB backup: OK ($(du -sh "${BACKUP_DIR}/mongo.archive.gz" | cut -f1))"
    else
      err "MongoDB backup: FAILED"
    fi

    # Environment
    cp "${PROJECT_DIR}/.env" "${BACKUP_DIR}/env.backup"
    log "Environment backup: OK"
    log "Backup complete: ${BACKUP_DIR}"
    ;;

  health)
    echo "── Health Checks ─────────────────────────"
    SERVICES=("nginx-proxy:80/health" "n8n:5678" "chatwoot-web:3000" "librechat:3080" "jupyter-connector:8888")
    for svc in "${SERVICES[@]}"; do
      NAME=$(echo "$svc" | cut -d: -f1)
      PORT_PATH=$(echo "$svc" | cut -d: -f2)
      if docker exec "$NAME" wget -qO- "http://localhost:${PORT_PATH}" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} $NAME"
      else
        # Try simple TCP check
        if docker exec "$NAME" sh -c "echo > /dev/tcp/localhost/$(echo $PORT_PATH | cut -d/ -f1)" 2>/dev/null; then
          echo -e "  ${YELLOW}~${NC} $NAME (running, no HTTP health endpoint)"
        else
          echo -e "  ${RED}✗${NC} $NAME"
        fi
      fi
    done
    echo ""
    echo "── Database Checks ───────────────────────"
    docker exec postgres pg_isready -U chatwoot >/dev/null 2>&1 && echo -e "  ${GREEN}✓${NC} PostgreSQL" || echo -e "  ${RED}✗${NC} PostgreSQL"
    docker exec mongodb mongosh --eval "db.adminCommand('ping')" --quiet >/dev/null 2>&1 && echo -e "  ${GREEN}✓${NC} MongoDB" || echo -e "  ${RED}✗${NC} MongoDB"
    docker exec redis redis-cli ping >/dev/null 2>&1 && echo -e "  ${GREEN}✓${NC} Redis" || echo -e "  ${RED}✗${NC} Redis"
    ;;

  update)
    warn "Pulling latest images..."
    docker compose pull
    warn "Recreating containers..."
    docker compose up -d --remove-orphans
    log "Update complete."
    docker compose ps
    ;;

  *)
    echo "AI Ecosystem - Stack Manager"
    echo ""
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  start    - Start all services"
    echo "  stop     - Stop all services"
    echo "  restart  - Restart all services"
    echo "  status   - Show service status & resource usage"
    echo "  logs     - Tail logs (optional: logs <service>)"
    echo "  backup   - Backup PostgreSQL & MongoDB"
    echo "  health   - Check health of all services"
    echo "  update   - Pull latest images and recreate"
    ;;
esac
