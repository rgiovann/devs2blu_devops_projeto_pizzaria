#!/usr/bin/env bash
# ============================================================
# INSTALADOR AUTOMATIZADO - PIZZARIA DEVOPS
# Instala e configura deploy automatizado do projeto pizzaria
# ============================================================

set -euo pipefail  # Fail fast: para em qualquer erro

# Configurações
readonly INSTALL_DIR="/opt/pizzaria"
readonly REPO_URL="https://github.com/rgiovann/devs2blu_devops_projeto_pizzaria.git"
readonly BRANCH="main"
readonly WEB_PORT="8080"
readonly CHANGED_FILE="/tmp/pizzaria-changed"

# Cores para output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Função de log com timestamp e cores
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        "INFO")  echo -e "${BLUE}[INFO]${NC} [$timestamp] $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} [$timestamp] $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} [$timestamp] $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} [$timestamp] $message" ;;
    esac
}

# Verificar se está rodando como root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "Este script deve ser executado como root"
        log "INFO" "Execute: sudo $0"
        exit 1
    fi
    log "SUCCESS" "Executando como root"
}

# Instalar dependências do sistema
install_system_dependencies() {
    log "INFO" "Atualizando repositórios do sistema..."
    apt-get update -qq

    log "INFO" "Instalando dependências: docker.io, docker-compose, git, curl..."

    # Instalar pacotes essenciais
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        docker.io \
        docker-compose \
        git \
        curl \
        ca-certificates \
        gnupg \
        lsb-release \
        util-linux \
        cron

    # Habilitar e iniciar Docker
    systemctl enable docker
    systemctl start docker

    # Habilitar cron
    systemctl enable cron
    systemctl start cron

    log "SUCCESS" "Dependências instaladas com sucesso"
}

# Verificar se Docker está funcionando
verify_docker() {
    log "INFO" "Verificando instalação do Docker..."

    if ! docker --version >/dev/null 2>&1; then
        log "ERROR" "Docker não está funcionando corretamente"
        exit 1
    fi

    if ! docker-compose --version >/dev/null 2>&1; then
        log "ERROR" "Docker Compose não está funcionando corretamente"
        exit 1
    fi

    # Teste básico do Docker
    if ! docker run --rm hello-world >/dev/null 2>&1; then
        log "ERROR" "Docker não consegue executar containers"
        exit 1
    fi

    log "SUCCESS" "Docker configurado e funcionando"
}

# Criar estrutura de diretórios
create_directory_structure() {
    log "INFO" "Criando estrutura de diretórios em $INSTALL_DIR..."

    # Criar diretórios necessários
    mkdir -p "$INSTALL_DIR"/{scripts,logs,app}

    # Definir permissões adequadas
    chmod 755 "$INSTALL_DIR"
    chmod 755 "$INSTALL_DIR/scripts"
    chmod 755 "$INSTALL_DIR/logs"

    log "SUCCESS" "Estrutura de diretórios criada"
}

# Criar arquivo de configuração
create_config_file() {
    log "INFO" "Criando arquivo de configuração..."

    cat > "$INSTALL_DIR/.env" << EOF
# Configurações do Deploy Automatizado - Pizzaria
REPO_URL=$REPO_URL
BRANCH=$BRANCH
APP_DIR=$INSTALL_DIR/app
WEB_PORT=$WEB_PORT
FORCE_REBUILD=false
INSTALL_DIR=$INSTALL_DIR
CHANGED_FILE=$CHANGED_FILE
EOF

    chmod 644 "$INSTALL_DIR/.env"
    log "SUCCESS" "Arquivo de configuração criado em $INSTALL_DIR/.env"
}

# Criar script de deploy
create_deploy_script() {
    log "INFO" "Criando script de deploy automatizado..."

    cat > "$INSTALL_DIR/scripts/deploy.sh" << 'DEPLOY_SCRIPT_EOF'
#!/usr/bin/env bash
# Script de Deploy Automatizado - Pizzaria
set -euo pipefail

# Carregar configurações
source /opt/pizzaria/.env

# Lock file para evitar execuções simultâneas
LOCK_FILE="/tmp/pizzaria-deploy.lock"
LOG_FILE="$INSTALL_DIR/logs/deploy.log"

# Função de log
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Limpeza do lock file
cleanup() {
    rm -f "$LOCK_FILE"
    log "Deploy finalizado - lock removido"
}
trap cleanup EXIT

# Verificar se já está executando
if [[ -f "$LOCK_FILE" ]]; then
    log "Deploy já em execução. Pulando..."
    exit 0
fi

# Criar lock
touch "$LOCK_FILE"
log "=== INICIANDO DEPLOY AUTOMATIZADO ==="

# Função para clonar/atualizar repositório
update_repository() {
    log "Verificando repositório..."

    if [[ ! -d "$APP_DIR" ]] || [[ ! -d "$APP_DIR/.git" ]]; then
        log "Clonando repositório pela primeira vez..."
        git clone -b "$BRANCH" "$REPO_URL" "$APP_DIR"
    else
        log "Atualizando repositório existente..."
        cd "$APP_DIR"

        # Salvar hash atual
        OLD_HASH=$(git rev-parse HEAD 2>/dev/null || echo "none")

        # Fazer pull forçado (sobrescrever mudanças locais)
        git fetch origin "$BRANCH"
        git reset --hard "origin/$BRANCH"
        git clean -fd

        # Verificar se houve mudanças
        NEW_HASH=$(git rev-parse HEAD)

        if [[ "$OLD_HASH" != "$NEW_HASH" ]]; then
            log "Mudanças detectadas: $OLD_HASH -> $NEW_HASH"
            echo "true" > $CHANGED_FILE
        else
            log "Nenhuma mudança detectada"
            echo "false" > $CHANGED_FILE
        fi
    fi
}

# Função para fazer deploy
deploy_application() {
    cd "$APP_DIR"

	if [[ ! -f "$APP_DIR/docker-compose.yml" ]]; then
		log "ERROR" "Arquivo docker-compose.yml não encontrado em $APP_DIR"
		exit 1
	fi

	# Verificar se houve mudanças (ou forçar rebuild)
	CHANGED="true"
	if [[ -f "$CHANGED_FILE" ]] && [[ "$FORCE_REBUILD" != "true" ]]; then
		CHANGED=$(cat $CHANGED_FILE)
		# Forçar deploy se não houver containers rodando (primeira execução)
		if [[ -z "$(docker-compose -f $APP_DIR/docker-compose.yml ps -q)" ]]; then
			log "Nenhum container rodando, forçando deploy"			
			CHANGED="true"
		fi
	fi

    if [[ "$CHANGED" == "true" ]] || [[ "$FORCE_REBUILD" == "true" ]]; then
        log "Realizando deploy da aplicação..."

        # Parar containers existentes
        log "Parando containers existentes..."
        docker-compose down --remove-orphans >/dev/null 2>&1 || true

        # Rebuild forçado (sempre reconstrói imagens)
        log "Construindo imagens (rebuild forçado)..."
        docker-compose build --no-cache --pull

        # Subir aplicação
        log "Iniciando aplicação..."
        docker-compose up -d

        # Aguardar containers ficarem prontos
        sleep 15

        # Verificar se containers estão rodando
        if docker-compose ps | grep -q "Up"; then
            local server_ip=$(hostname -I | awk '{print $1}')
            log "✅ DEPLOY REALIZADO COM SUCESSO!"
            log "🌐 Aplicação disponível em: http://$server_ip:$WEB_PORT"
        else
            log "❌ ERRO: Containers não iniciaram corretamente"
            docker-compose logs
            exit 1
        fi

        # Limpeza de imagens não utilizadas
        log "Limpando imagens Docker não utilizadas..."
        docker image prune -f >/dev/null 2>&1 || true

    else
        log "Nenhuma mudança detectada. Deploy não necessário."
    fi
}

# Execução principal
main() {
    log "Iniciando verificação de atualizações..."
    update_repository
    deploy_application
    log "=== DEPLOY FINALIZADO ==="
}

main "$@"
DEPLOY_SCRIPT_EOF

    chmod +x "$INSTALL_DIR/scripts/deploy.sh"
    log "SUCCESS" "Script de deploy criado em $INSTALL_DIR/scripts/deploy.sh"
}

# Configurar crontab
setup_crontab() {
    log "INFO" "Configurando execução automática (cron a cada 5 minutos)..."

    # Entrada do crontab
    local cron_entry="*/5 * * * * $INSTALL_DIR/scripts/deploy.sh >> $INSTALL_DIR/logs/cron.log 2>&1"

    # Verificar se já existe
    if crontab -l 2>/dev/null | grep -Fq "$INSTALL_DIR/scripts/deploy.sh"; then
        log "INFO" "Crontab já configurado"
    else
        # Adicionar entrada preservando crontab existente
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        log "SUCCESS" "Crontab configurado - execução a cada 5 minutos"
    fi
}

# Executar primeiro deploy
run_initial_deploy() {
    log "INFO" "Executando primeiro deploy..."

    # Executar deploy inicial
    if "$INSTALL_DIR/scripts/deploy.sh"; then
        log "SUCCESS" "Deploy inicial executado com sucesso"
    else
        log "ERROR" "Falha no deploy inicial"
        exit 1
    fi
}

# Mostrar informações finais
show_summary() {
    local server_ip=$(hostname -I | awk '{print $1}')

    echo
    echo "=============================================="
    echo -e "${GREEN}🎉 INSTALAÇÃO CONCLUÍDA COM SUCESSO!${NC}"
    echo "=============================================="
    echo -e "${BLUE}📍 Diretório de instalação:${NC} $INSTALL_DIR"
    echo -e "${BLUE}🌐 URL da aplicação:${NC} http://$server_ip:$WEB_PORT"
    echo -e "${BLUE}📋 Logs de deploy:${NC} $INSTALL_DIR/logs/"
    echo -e "${BLUE}⏰ Atualização automática:${NC} A cada 5 minutos"
    echo -e "${BLUE}📦 Repositório:${NC} $REPO_URL"
    echo "=============================================="
    echo
    echo -e "${YELLOW}Comandos úteis:${NC}"
    echo "  • Ver logs em tempo real: tail -f $INSTALL_DIR/logs/deploy.log"
    echo "  • Deploy manual: $INSTALL_DIR/scripts/deploy.sh"
    echo "  • Ver containers: cd $INSTALL_DIR/app && docker-compose ps"
    echo "  • Ver crontab: crontab -l"
    echo
}

# Função principal
main() {
    log "INFO" "Iniciando instalação do sistema de deploy automatizado..."
	# Limpar arquivo de mudanças antes de iniciar
	CHANGED_DIR=$(dirname "$CHANGED_FILE")
	if [[ -d "$CHANGED_DIR" ]]; then
		rm -f "$CHANGED_FILE"
		log "Arquivo de mudanças $CHANGED_FILE limpo"
	else
		log "WARN" "Diretório $CHANGED_DIR não existe, pulando limpeza de $CHANGED_FILE"
	fi
    check_root
    install_system_dependencies
    verify_docker
    create_directory_structure
    create_config_file
    create_deploy_script
    setup_crontab
    run_initial_deploy
    show_summary

    log "SUCCESS" "Instalação finalizada com sucesso!"
}

# Executar se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
