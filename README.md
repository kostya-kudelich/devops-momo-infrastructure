# Общее устройство

Пельменная - https://www.kudelich-store.site.<br>
ArgoCD - https://argocd.kudelich-store.site

Сервисы пельменной крутятся в k8s-кластере Яндекс Cloud.

Для развёртывания кластера используется Terraform.

При сборке сервисов мы получаеми их Docker-образы, далее эти образы описываются в helm-чартах бэкэнд и фронтенд сервисах пельменной.

Развёрнутый в кластере ArgoCD подключен к nexus-репозиторию, где хранятся helm-чарты сервисов, он же и разворачивает наши сервисы в k8s.

# Развёртывание инфраструктуры и приложения.

- устанавливаем terraform (https://developer.hashicorp.com/terraform/downloads)
- устанавливаем консоль яндекса (https://cloud.yandex.ru/docs/cli/operations/install-cli), настраиваем свой профиль в яндекс облаке.
- инициализируем профиль ``yc init``. 
- получение данных о профиле - `yc config list`
- создаём yc токен `yc iam create-token`
- записываем значение токена(и другие параметры облака если нужно) в **momo-store-infrastructure/terraform-s3-backend/terraform.tvars** и **momo-store-infrastructure/terraform/terraform.tvars**
- создаём бакет для хранения состояния основного terraform. выполняем `terraform appply` в **momo-store-infrastructure/terraform-s3-backend**, затем выполняем команды `terraform output s3-access-key`, `terraform output s3-access-key`. полученные секреты записываем в **momo-store-infrastructure/terraform/backend.conf**
- заполняем секреты в **momo-store-infrastructure/terraform/terraform.tvars**
- инициализируем terraform: выполняем в папке  *momo-store-infrastructure/terraform* команду ``terraform init -backend-config=backend.conf``
- выполняем `terraform apply`. ждём завершения и... - сервис поднят!
<br />


Скрипт терраформа создаёт: 
- k8s-кластер
- сеть и подсети
- статический адрес
- настраивает сетевые правила
- создаёт сервисных пользователей и настраивает их права
- создаёт s3 object storage и заливает туда статику
- поднимает в кластеры группу нод
- создает доменную зоны и записи в ней
- устанавливает в кластер vpa, nginx-ingress, cert-manager и настроенный argocd, который подтягивает чарты пельменной и разворчавает её в кластере
<br />

Подключение к k8s-кластеру:
- ``yc managed-kubernetes cluster get-credentials momo-store --external --force``
- ``kubectl cluster-info``
<br />

Получение пароля ArgoCD:
- ``kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d``

# Обновления приложения и инфраструктуры
- сервисы пельменной обновляются автоматически при попадании кода в главную ветку main
- вся инфраструктура описана в коде, при необходимости изменения следует вносить в ***.tf** файлы или ***.yaml** файлы сервисов(**momo-store-infrastructure/kubernetes/argocd|certamanger**) которые используются в скрипте terraform. после выполнить ``terraform apply``.

# Мониторинг, логирование и дашборд
В будущем
