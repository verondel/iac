# Пути до фаз
CLOUD_DIR=infra
SERVICES_DIR=services
CONFIG=config/terraform.tfvars.json
KUBECONFIG=$(SERVICES_DIR)/vera-infra-kubeconfig.yaml

# Получение имени кластера из terraform output
CLUSTER_NAME=$(shell terraform -chdir=$(CLOUD_DIR) output -raw cluster_name)
FOLDER_ID=$(shell terraform -chdir=$(CLOUD_DIR) output -raw folder_id)

.PHONY: all cloud services clean kubeconfig

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
# kubeconfig:
# 	@echo "📡 [KUBECONFIG] Получаем kubeconfig для кластера..."
# 	@if [ ! -f $(KUBECONFIG) ]; then \
# 		echo "📄 kubeconfig не найден. Генерируем..."; \
# 		yc managed-kubernetes cluster get-credentials $$CLUSTER_NAME --external --folder-id $$FOLDER_ID --config $(KUBECONFIG); \
# 	else \
# 		echo "✅ kubeconfig уже существует."; \
# 	fi


TFVARS_PATH := ./config/terraform.tfvars.json
TOKEN_FILE := ./secrets/yc-token.txt

CLOUD_ID := $(shell jq -r '.cloud_id' $(TFVARS_PATH))
FOLDER_NAME := $(shell jq -r '.folder_name' $(TFVARS_PATH))
CLUSTER_NAME := zonal-infra-cluster

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
services:
	@echo "📦 [SERVICES] Установка GitLab и других сервисов..."
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

# @echo "🔥 Удаляем phase2_services..."
# cd $(SERVICES_DIR) && terraform destroy -auto-approve -var-file=../$(CONFIG) || true