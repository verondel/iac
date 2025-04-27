TFVARS_PATH := ./config/terraform.tfvars.json

# Пути до фаз
CLOUD_DIR=infra
SERVICES_DIR=services
CONFIG=config/terraform.tfvars.json
KUBECONFIG=$(SERVICES_DIR)/vera-infra-kubeconfig.yaml
TOKEN_FILE := ./secrets/yc-token.txt

# Получение имени кластера из terraform output
CLOUD_ID := $(shell jq -r '.cloud_id' $(TFVARS_PATH))
FOLDER_NAME := $(shell jq -r '.folder_name' $(TFVARS_PATH))
CLUSTER_NAME=$(shell terraform -chdir=$(CLOUD_DIR) output -raw cluster_name)
FOLDER_ID=$(shell terraform -chdir=$(CLOUD_DIR) output -raw folder_id)

# CLUSTER_NAME := zonal-infra-cluster

.PHONY: all cloud services clean kubeconfig clean destroy-services clean-state

# -------------------------
# Полный запуск
# -------------------------
all: cloud kubeconfig services

# -------------------------
# Фаза 1: инфраструктура
# -------------------------
cloud:
	@echo "🚀 [CLOUD] Создание инфраструктуры..."
	cd $(CLOUD_DIR) && terraform init
	cd $(CLOUD_DIR) && terraform apply -auto-approve -var-file=../$(CONFIG)

cloud-only:
	cd $(CLOUD_DIR) && terraform apply -auto-approve -var-file=../$(CONFIG)

# -------------------------
# Генерация kubeconfig
# -------------------------

kubeconfig:
	@echo "📡 [KUBECONFIG] Получаем kubeconfig для кластера $(CLUSTER_NAME)..."
	@echo "$(KUBECONFIG)"
	@if [ ! -f $(TOKEN_FILE) ]; then \
		echo "❌ Файл с токеном не найден: $(TOKEN_FILE)"; \
		echo "   Положи OAuth токен в этот файл и повтори."; \
		exit 1; \
	fi
	@if [ ! -f $(KUBECONFIG) ]; then \
		TOKEN=$$(cat $(TOKEN_FILE)); \
		CLOUD_ID=$(CLOUD_ID); \
		FOLDER_NAME=$(FOLDER_NAME); \
		FOLDER_ID=$$(yc --token=$$TOKEN --cloud-id=$$CLOUD_ID resource-manager folder list --format json | jq -r '.[] | select(.name=="'$$FOLDER_NAME'") | .id'); \
		if [ -z "$$FOLDER_ID" ]; then \
			echo "❌ Не удалось получить FOLDER_ID по имени $$FOLDER_NAME"; \
			exit 1; \
		fi; \
		echo "📄 kubeconfig не найден. Генерируем..."; \
		yc --token=$$TOKEN --cloud-id=$$CLOUD_ID --folder-id=$$FOLDER_ID managed-kubernetes cluster get-credentials $(CLUSTER_NAME) --external --force; \
		cp $$HOME/.kube/config $(KUBECONFIG); \
		echo "✅ kubeconfig сохранён в $(KUBECONFIG)"; \
	else \
		echo "✅ kubeconfig уже существует."; \
	fi



# export KUBECONFIG=./vera-infra-kubeconfig.yaml

# -------------------------
# Фаза 2: Установка GitLab и сервисов
# -------------------------
# services:
# 	@echo "📦 [SERVICES] Установка GitLab и других сервисов..."
# 	cd $(SERVICES_DIR) && terraform init
# 	cd $(SERVICES_DIR) && terraform apply -auto-approve -var-file=../$(CONFIG)


services: kubeconfig
	@echo "📦 [SERVICES] Установка GitLab и других сервисов..."

	@if [ ! -f $(TOKEN_FILE) ]; then \
		echo "❌ Файл с токеном не найден: $(TOKEN_FILE)"; \
		echo "   Положи OAuth токен в $(TOKEN_FILE) и повтори."; \
		exit 1; \
	fi

	@TOKEN=$$(cat $(TOKEN_FILE)); \
	if ! yc config get cloud-id > /dev/null 2>&1; then \
		echo "⚙️  Устанавливаем cloud-id из terraform.tfvars.json..."; \
		yc config set cloud-id $(CLOUD_ID); \
	else \
		echo "✅ cloud-id уже установлен."; \
	fi; \
	echo "🔐 Используем YC_TOKEN из $(TOKEN_FILE)"; \
	export YC_TOKEN=$$TOKEN; \

	# ⬇️ Обновляем terraform.tfvars.json с актуальным folder_id
	@echo "🛠️  Обновляем folder_id в $(TFVARS_PATH)..."
	@jq ".folder_id = \"$(FOLDER_ID)\"" $(TFVARS_PATH) > $(TFVARS_PATH).tmp && mv $(TFVARS_PATH).tmp $(TFVARS_PATH)

	cd $(SERVICES_DIR) && terraform init
	cd $(SERVICES_DIR) && terraform apply -auto-approve -var-file=../$(CONFIG)


# -------------------------
# Удаление всех ресурсов
# -------------------------
clean:
	@echo "🔥 Удаляем phase1_infra..."
	cd $(CLOUD_DIR) && terraform destroy -auto-approve -var-file=../$(CONFIG) || true
	@echo "🧹 Удаляем временные файлы..."
	rm -f $(KUBECONFIG)


destroy-services:
	@echo "🔥 Удаляем services..."
	cd services && terraform destroy -auto-approve -var-file=../config/terraform.tfvars.json

clean-state:
	@echo "🧹 Удаляем файлы стейта терраформа..."
	cd infra && rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
	cd services && rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
	@echo "🧹 Удаляем kubeconfig файлы..."
	rm -f $(KUBECONFIG)


# @echo "🔥 Удаляем phase2_services..."
# cd $(SERVICES_DIR) && terraform destroy -auto-approve -var-file=../$(CONFIG) || true