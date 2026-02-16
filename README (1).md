# 🚀 AI & Automation Ecosystem — Atención al Cliente Aumentada por IA

## Índice

- [Visión General](#visión-general)
- [Diagrama de Arquitectura](#diagrama-de-arquitectura)
- [Stack Tecnológico](#stack-tecnológico)
- [Despliegue Rápido](#despliegue-rápido)
- [Estructura del Repositorio](#estructura-del-repositorio)
- [Configuración Detallada](#configuración-detallada)
- [Análisis de Recursos (Stress Test)](#análisis-de-recursos-stress-test)
- [Estrategia de Producción (HA)](#estrategia-de-producción-ha)
- [Operación y Mantenimiento](#operación-y-mantenimiento)
- [Seguridad](#seguridad)
- [Troubleshooting](#troubleshooting)

---

## Visión General

Este proyecto despliega un MVP (Sandbox) funcional de un ecosistema de **Atención al Cliente Aumentada por IA** en AWS, orquestando cuatro servicios principales mediante contenedores Docker:

| Servicio | Función | Base de Datos |
|----------|---------|---------------|
| **N8n** | Orquestador de workflows | SQLite (embebida) |
| **Chatwoot** | Plataforma de chat omnicanal | PostgreSQL + Redis |
| **LibreChat** | Interfaz unificada multi-LLM | MongoDB |
| **Jupyter Connector** | Puente de datos para Deepnote | — (consume las demás) |

El despliegue es **100% automatizado** mediante AWS CloudFormation y diseñado con patrones de producción desde el día uno.

---

## Diagrama de Arquitectura

### Sandbox (Monolito en EC2)

```
                        ┌─────────────────────────────────┐
                        │          INTERNET                │
                        └──────────────┬──────────────────┘
                                       │
                               ┌───────▼───────┐
                               │   Security    │
                               │    Groups     │
                               │  :80 :443 :22 │
                               └───────┬───────┘
                                       │
                    ┌──────────────────▼──────────────────────┐
                    │        EC2 Instance (t3.micro)          │
                    │        VPC: 10.0.0.0/16                 │
                    │        Subnet: 10.0.1.0/24 (public-a)  │
                    │                                         │
                    │  ┌────────────────────────────────────┐ │
                    │  │     NGINX Reverse Proxy (:80)      │ │
                    │  │   /n8n  /chatwoot  /chat  /data    │ │
                    │  └──┬────────┬─────────┬────────┬────┘ │
                    │     │        │         │        │       │
                    │  ┌──▼──┐ ┌──▼──────┐ ┌▼─────┐ ┌▼────┐ │
                    │  │ N8n │ │Chatwoot │ │Libre │ │Jupy │ │
                    │  │:5678│ │Web :3000│ │Chat  │ │ter  │ │
                    │  └──┬──┘ │Sidekiq  │ │:3080 │ │:8888│ │
                    │     │    └──┬──┬───┘ └──┬───┘ └──┬──┘ │
                    │     │       │  │        │        │     │
                    │  ┌──▼───────▼──▼────────▼────────▼──┐  │
                    │  │      BACKEND NETWORK (internal)   │  │
                    │  │                                    │  │
                    │  │ ┌──────────┐ ┌───────┐ ┌───────┐  │  │
                    │  │ │PostgreSQL│ │MongoDB│ │ Redis │  │  │
                    │  │ │  :5432   │ │ :27017│ │ :6379 │  │  │
                    │  │ └────┬─────┘ └───┬───┘ └───┬───┘  │  │
                    │  │      │           │         │       │  │
                    │  │   [Volume]    [Volume]   [memory]  │  │
                    │  └────────────────────────────────────┘  │
                    │                                          │
                    │  SWAP: 4GB  │  DISK: 30GB gp3 (enc.)   │
                    └──────────────────────────────────────────┘
```

### Diseño de Red VPC (Preparado para Producción)

```
    VPC 10.0.0.0/16
    ├── Public Subnet A  (10.0.1.0/24)  ─── AZ-a  ← EC2 instance aquí
    ├── Public Subnet B  (10.0.2.0/24)  ─── AZ-b  ← Preparada para ALB
    ├── Private Subnet A (10.0.10.0/24) ─── AZ-a  ← Futuro: RDS, ElastiCache
    └── Private Subnet B (10.0.11.0/24) ─── AZ-b  ← Futuro: RDS replica
```

### Flujo de Datos entre Servicios

```
    Usuario
      │
      ▼
    Nginx ─────► N8n ──────────┐
      │                        │  (webhooks, API calls)
      ├────────► Chatwoot ◄────┘
      │            │
      │            ├──► PostgreSQL (conversaciones, contactos)
      │            └──► Redis (cache, colas Sidekiq)
      │
      ├────────► LibreChat ──► MongoDB (historial AI chats)
      │            │
      │            └──► APIs externas (OpenAI, Anthropic, etc.)
      │
      └────────► Jupyter Connector
                   │
                   ├──► PostgreSQL (lectura de datos Chatwoot)
                   ├──► MongoDB (lectura de datos LibreChat)
                   └──► Deepnote (consumo externo vía API)
```

---

## Stack Tecnológico

| Componente | Imagen Docker | Versión | Puerto Interno |
|------------|--------------|---------|----------------|
| Nginx | `nginx:1.25-alpine` | 1.25.x | 80, 443 |
| N8n | `n8nio/n8n:latest` | Latest | 5678 |
| Chatwoot Web | `chatwoot/chatwoot:latest` | Latest | 3000 |
| Chatwoot Sidekiq | `chatwoot/chatwoot:latest` | Latest | — |
| LibreChat | `ghcr.io/danny-avila/librechat:latest` | Latest | 3080 |
| Jupyter | `jupyter/minimal-notebook:latest` | Latest | 8888 |
| PostgreSQL | `postgres:15-alpine` | 15.x | 5432 |
| MongoDB | `mongo:6.0` | 6.0.x | 27017 |
| Redis | `redis:7-alpine` | 7.x | 6379 |

---

## Despliegue Rápido

### Prerrequisitos

1. Cuenta AWS con acceso a la consola
2. Un **Key Pair** existente en la región objetivo
3. AWS CLI configurado (opcional, para despliegue por CLI)

### Opción A: Despliegue via AWS Console

1. Navegar a **CloudFormation → Create Stack → Upload template**
2. Subir `cloudformation.yaml`
3. Configurar parámetros:
   - `KeyPairName`: seleccionar tu key pair
   - `SSHAllowedCIDR`: tu IP pública (ej: `203.0.113.50/32`)
   - `InstanceType`: `t3.micro` (Free Tier) o `t3.small` (recomendado)
4. Crear stack y esperar ~10 minutos
5. Revisar **Outputs** para obtener URLs

### Opción B: Despliegue via CLI

```bash
aws cloudformation create-stack \
  --stack-name ai-ecosystem-sandbox \
  --template-body file://cloudformation.yaml \
  --parameters \
    ParameterKey=KeyPairName,ParameterValue=my-key \
    ParameterKey=SSHAllowedCIDR,ParameterValue=$(curl -s ifconfig.me)/32 \
    ParameterKey=InstanceType,ParameterValue=t3.micro \
    ParameterKey=SwapSizeGB,ParameterValue=4 \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# Monitorear progreso
aws cloudformation wait stack-create-complete --stack-name ai-ecosystem-sandbox

# Obtener URLs
aws cloudformation describe-stacks --stack-name ai-ecosystem-sandbox \
  --query 'Stacks[0].Outputs' --output table
```

### Verificación Post-Despliegue

```bash
# SSH a la instancia
ssh -i my-key.pem ec2-user@<PUBLIC_IP>

# Verificar estado del stack
ecosystem status

# Ver logs en tiempo real
ecosystem logs

# Verificar salud de servicios
ecosystem health
```

---

## Estructura del Repositorio

```
ai-ecosystem/
├── cloudformation.yaml      # IaC - Infraestructura completa AWS
├── docker-compose.yml       # Orquestación de contenedores
├── .env.example             # Variables de entorno (plantilla)
├── .gitignore
│
├── configs/
│   ├── nginx.conf           # Reverse proxy con rate limiting
│   ├── librechat.yaml       # Configuración de endpoints LLM
│   └── index.html           # Landing page / dashboard
│
├── scripts/
│   └── stack-manager.sh     # CLI de gestión (start/stop/backup)
│
└── README.md                # Esta documentación
```

---

## Configuración Detallada

### Nginx Reverse Proxy

El proxy implementa las siguientes medidas de seguridad y rendimiento:

- **Path-based routing**: `/n8n/`, `/chatwoot/`, `/chat/`, `/data/`
- **Rate limiting**: 10 req/s general, 30 req/s para APIs
- **WebSocket support**: para N8n, Chatwoot y LibreChat
- **Security headers**: X-Frame-Options, X-Content-Type-Options, CSP, XSS Protection
- **Gzip compression**: para reducir transferencia de datos
- **Bloqueo de rutas sensibles**: `.env`, `.git`, `.htaccess`

### Docker Networking

Se implementan **dos redes aisladas**:

- `frontend` (bridge): conecta Nginx con los servicios web (N8n, Chatwoot, LibreChat, Jupyter)
- `backend` (bridge, **internal**): conecta servicios con bases de datos. **No tiene acceso a internet**, lo cual impide que las bases de datos sean accesibles desde fuera del host.

### Persistencia de Datos

Cada base de datos utiliza **named Docker volumes**:

| Volume | Servicio | Contenido |
|--------|----------|-----------|
| `ai-eco-postgres` | PostgreSQL | Datos de Chatwoot |
| `ai-eco-mongo` | MongoDB | Historial de LibreChat |
| `ai-eco-n8n` | N8n | Workflows y credenciales |
| `ai-eco-librechat` | LibreChat | Imágenes subidas |
| `ai-eco-jupyter` | Jupyter | Notebooks de trabajo |

### Jupyter como Puente para Deepnote

El contenedor Jupyter actúa como **API Gateway seguro** con las siguientes características:

1. Tiene acceso a la red `backend` donde residen las bases de datos
2. Expone un endpoint en `/data/` a través de Nginx
3. Incluye pre-instalados: `psycopg2`, `pymongo`, `pandas`, `requests`
4. Deepnote se conecta vía REST API al endpoint público, **sin exponer puertos de base de datos**

---

## Análisis de Recursos (Stress Test)

### Presupuesto de Memoria — t3.micro (1GB RAM + 4GB Swap)

| Servicio | Límite Docker | RSS Estimado Real | Notas |
|----------|:------------:|:-----------------:|-------|
| PostgreSQL | 200 MB | 80-120 MB | Tuned: shared_buffers=64MB, max_conn=50 |
| MongoDB | 256 MB | 120-180 MB | WiredTiger cache limitado a 100MB |
| Redis | 64 MB | 15-30 MB | maxmemory=50MB, sin persistencia |
| N8n | 300 MB | 100-180 MB | Node.js max-old-space=256MB |
| Chatwoot Web | 400 MB | 250-350 MB | Rails: WEB_CONCURRENCY=1, 3 threads |
| Chatwoot Sidekiq | 300 MB | 150-250 MB | MALLOC_ARENA_MAX=2 |
| LibreChat | 350 MB | 120-200 MB | Node.js max-old-space=256MB |
| Jupyter | 256 MB | 80-150 MB | Minimal notebook, pip packages |
| Nginx | 64 MB | 5-15 MB | Alpine, worker_connections=512 |
| **TOTAL** | **2,190 MB** | **920-1,475 MB** | |

### Estrategia de Optimización Implementada

#### 1. Swap Agresivo (4GB)
El swap file de 4GB proporciona un colchón para picos de memoria. Con `vm.swappiness=60`, el kernel empezará a paginar procesos inactivos al swap antes de alcanzar OOM.

#### 2. Límites de Memoria Docker
Cada contenedor tiene `deploy.resources.limits.memory` configurado. Si un contenedor excede su límite, Docker lo reinicia en lugar de afectar a otros servicios (fail-fast pattern).

#### 3. Tuning de Bases de Datos
- **PostgreSQL**: `shared_buffers=64MB` (vs default 128MB), `max_connections=50` (vs 100), `work_mem=2MB` (vs 4MB)
- **MongoDB**: `--wiredTigerCacheSizeGB 0.1` (100MB vs default que toma 50% de RAM)
- **Redis**: `--maxmemory 50mb`, sin persistencia a disco, evicción LRU

#### 4. Optimización de Application Servers
- Chatwoot: `WEB_CONCURRENCY=1` (1 worker vs default 2), `MALLOC_ARENA_MAX=2` (limita fragmentación glibc)
- N8n y LibreChat: `NODE_OPTIONS="--max-old-space-size=256"` limita el heap de V8
- Logs Docker: `max-size=10m, max-file=3` previene crecimiento de logs

### Veredicto Realista

> **⚠️ La t3.micro (1GB) puede arrancar el stack completo, pero NO es estable para uso continuado.**

Con el swap de 4GB, los 9 contenedores **arrancan exitosamente** y pueden responder a peticiones individuales durante testing. Sin embargo, bajo carga concurrente (>2-3 usuarios simultáneos), el exceso de swapping causa:
- Latencias de 5-30 segundos en respuestas
- Timeouts intermitentes en Chatwoot/LibreChat
- Riesgo de OOM-killer matando Sidekiq o MongoDB

### Dimensionamiento Recomendado

| Entorno | Instancia | RAM | Notas |
|---------|-----------|-----|-------|
| **Sandbox (demo personal)** | t3.micro | 1 GB | Funcional con swap, no para carga |
| **MVP mínimo viable** | t3.small | 2 GB | ✅ **Mínimo recomendado** — estable para 3-5 usuarios |
| **Staging/QA** | t3.medium | 4 GB | Cómodo para testing con carga |
| **Producción (monolito)** | t3.large | 8 GB | Headroom para picos, no HA |

---

## Estrategia de Producción (HA)

### "¿Cómo separar este monolito en Alta Disponibilidad?"

La migración a producción implica descomponer el stack en servicios gestionados de AWS y contenedores orquestados:

### Arquitectura Objetivo

```
                         ┌─────────────┐
                         │  Route 53   │
                         │  (DNS)      │
                         └──────┬──────┘
                                │
                         ┌──────▼──────┐
                         │ CloudFront  │
                         │  (CDN+SSL)  │
                         └──────┬──────┘
                                │
                    ┌───────────▼───────────┐
                    │   Application Load    │
                    │   Balancer (ALB)      │
                    │   Multi-AZ            │
                    └───┬────┬────┬────┬───┘
                        │    │    │    │
              ┌─────────▼┐ ┌▼────▼┐ ┌▼─────────┐
              │   ECS    │ │ ECS  │ │   ECS    │
              │ Fargate  │ │Fargat│ │ Fargate  │
              │ ─────────│ │──────│ │──────────│
              │ Chatwoot │ │ N8n  │ │LibreChat │
              │ (2 tasks)│ │(1-2) │ │ (2 tasks)│
              └────┬─────┘ └──┬───┘ └────┬─────┘
                   │          │          │
          ┌────────▼──────────▼──────────▼────────┐
          │              VPC Private Subnets       │
          │                                        │
          │ ┌──────────┐ ┌──────────┐ ┌─────────┐ │
          │ │  RDS     │ │DocumentDB│ │Elasti-  │ │
          │ │PostgreSQL│ │(MongoDB) │ │Cache    │ │
          │ │Multi-AZ  │ │Replica   │ │(Redis)  │ │
          │ │          │ │Set       │ │Cluster  │ │
          │ └──────────┘ └──────────┘ └─────────┘ │
          └────────────────────────────────────────┘
```

### Plan de Migración por Capas

#### Capa 1 — Bases de Datos Gestionadas (Prioridad Alta)

| Servicio Actual | Migración AWS | Beneficio |
|----------------|---------------|-----------|
| PostgreSQL container | **Amazon RDS PostgreSQL** (Multi-AZ) | Backups automáticos, failover, encryption at rest |
| MongoDB container | **Amazon DocumentDB** | Compatibilidad MongoDB API, réplicas automáticas |
| Redis container | **Amazon ElastiCache** (Redis) | Cluster mode, persistence, no memory management |

**Justificación**: Las bases de datos son el componente más crítico. Delegarlas a servicios gestionados elimina el riesgo de pérdida de datos por fallos del host y proporciona backups automáticos.

#### Capa 2 — Cómputo Orquestado (Prioridad Media)

| Componente | Migración AWS | Configuración |
|------------|---------------|---------------|
| Docker Compose | **ECS Fargate** | Sin gestión de servidores |
| Cada servicio | **ECS Service** con auto-scaling | Min 2 tasks para HA |
| Nginx | **Application Load Balancer** | Health checks, SSL termination |

**Justificación**: ECS Fargate elimina la gestión de instancias EC2 para contenedores. Cada servicio escala independientemente.

#### Capa 3 — Networking y Seguridad (Prioridad Alta)

- **VPC**: Mantener el diseño actual (ya tiene subnets multi-AZ)
- **ALB**: Reemplaza Nginx como punto de entrada (SSL termination, health checks nativos)
- **Security Groups**: Refinar para que solo ALB alcance ECS, y solo ECS alcance RDS/ElastiCache
- **AWS WAF**: Protección contra ataques comunes (SQL injection, XSS)
- **ACM**: Certificados SSL gratuitos gestionados

#### Capa 4 — Observabilidad

| Necesidad | Servicio AWS |
|-----------|-------------|
| Logs centralizados | CloudWatch Logs + Log Insights |
| Métricas | CloudWatch Metrics + Custom dashboards |
| Alertas | CloudWatch Alarms → SNS → Email/Slack |
| Tracing distribuido | AWS X-Ray |

### Estimación de Costos Mensuales (Producción)

| Componente | Especificación | Costo Estimado/mes |
|------------|---------------|:------------------:|
| ECS Fargate (4 services) | 0.5 vCPU, 1GB cada uno | ~$60 |
| RDS PostgreSQL | db.t3.micro, Multi-AZ | ~$30 |
| DocumentDB | db.t3.medium | ~$60 |
| ElastiCache Redis | cache.t3.micro | ~$15 |
| ALB | 1 LB + reglas | ~$20 |
| Data Transfer | ~50 GB/mes | ~$5 |
| CloudWatch | Logs + metrics | ~$10 |
| **Total** | | **~$200/mes** |

### Decisiones de Diseño para Producción

1. **Stateless services**: Chatwoot, LibreChat y N8n no guardan estado local → escalan horizontalmente
2. **Blue/Green deployments**: ECS soporta rolling updates sin downtime
3. **Secrets Manager**: Migrar `.env` a AWS Secrets Manager con rotación automática
4. **ECR privado**: Almacenar imágenes custom en Amazon ECR (vs Docker Hub rate limits)
5. **CI/CD**: GitHub Actions → ECR → ECS (pipeline automatizado)

---

## Operación y Mantenimiento

### Comandos del Stack Manager

```bash
# Tras SSH a la instancia:
ecosystem start     # Iniciar todos los servicios
ecosystem stop      # Detener todos los servicios
ecosystem restart   # Reiniciar stack completo
ecosystem status    # Ver estado, memoria, disco
ecosystem logs      # Logs en tiempo real (todos)
ecosystem logs n8n  # Logs de un servicio específico
ecosystem health    # Health check de todos los servicios
ecosystem backup    # Backup de PostgreSQL y MongoDB
```

### URLs de Acceso

| Servicio | URL | Credenciales |
|----------|-----|-------------|
| Dashboard | `http://<IP>/` | — |
| N8n | `http://<IP>/n8n/` | Ver `.env` (N8N_BASIC_AUTH_*) |
| Chatwoot | `http://<IP>/chatwoot/` | Crear en primer acceso |
| LibreChat | `http://<IP>/chat/` | Registrarse en primer acceso |
| Jupyter | `http://<IP>/data/` | Token en `.env` (JUPYTER_TOKEN) |

### Backups

Los backups se ejecutan manualmente con `ecosystem backup` y se almacenan en `/opt/ai-ecosystem/backups/`. Para producción, se recomienda automatizar con cron:

```bash
# Agregar a /etc/cron.d/ai-ecosystem-backup
0 2 * * * root /opt/ai-ecosystem/scripts/stack-manager.sh backup
```

---

## Seguridad

### Medidas Implementadas

| Capa | Medida | Detalle |
|------|--------|---------|
| Red | VPC aislada | Subnets privadas para futuras DBs gestionadas |
| Red | Security Groups | Solo puertos 80, 443, 22 abiertos |
| Red | Docker internal network | Backend network sin acceso externo |
| Aplicación | Nginx rate limiting | 10-30 req/s por IP |
| Aplicación | Security headers | X-Frame, CSP, XSS protection |
| Aplicación | Bloqueo de rutas | .env, .git, .htaccess bloqueados |
| Datos | EBS encryption | Disco cifrado por defecto |
| Datos | Passwords autogenerados | openssl rand para cada secreto |
| Datos | .env con chmod 600 | Solo root puede leer credenciales |
| Acceso | SSH restringido | CIDR configurable en CloudFormation |
| Acceso | IAM role | SSM habilitado (alternativa a SSH) |

### Recomendaciones para Producción

1. **Restringir SSH CIDR** a la IP específica del equipo
2. **Habilitar SSL** con Let's Encrypt (Certbot) o AWS ACM
3. **Configurar MFA** para acceso a la consola AWS
4. **Rotación de secretos** periódica o vía AWS Secrets Manager
5. **Habilitar VPC Flow Logs** para auditoría de red
6. **AWS GuardDuty** para detección de amenazas

---

## Troubleshooting

### El stack no arranca completamente

```bash
# Ver qué contenedores fallaron
docker compose ps

# Ver logs del servicio que falló
docker compose logs <servicio> --tail=100

# Verificar memoria disponible
free -h

# Si hay OOM, verificar cuál fue matado
dmesg | grep -i "out of memory" | tail -5
```

### Chatwoot muestra error de migración

```bash
# Ejecutar migraciones manualmente
docker exec chatwoot-web bundle exec rails db:prepare
docker compose restart chatwoot-web chatwoot-sidekiq
```

### MongoDB no arranca (WiredTiger error)

```bash
# Limpiar lock files
docker compose stop mongodb
docker volume rm ai-eco-mongo
docker compose up -d mongodb
```

### Rendimiento muy lento

```bash
# Verificar uso de swap
ecosystem status

# Si swap > 50%, considerar:
# 1. Parar servicios no esenciales temporalmente
docker compose stop jupyter-connector

# 2. O migrar a t3.small
# Cambiar InstanceType en CloudFormation y hacer Update Stack
```

### Verificar logs del UserData (primer despliegue)

```bash
# El script de inicialización guarda log en:
cat /var/log/user-data.log

# Verificar si completó exitosamente
tail -5 /var/log/user-data.log
# Debe mostrar: "=== Setup Complete: ... ==="
```

---

## Licencia

Este proyecto es una prueba técnica. Los servicios individuales (N8n, Chatwoot, LibreChat) mantienen sus respectivas licencias open-source.

---

