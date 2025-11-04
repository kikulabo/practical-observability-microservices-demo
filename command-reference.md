# コマンドリファレンス

このドキュメントは、書籍『国産サービスで実践するオブザーバビリティ入門 [第二弾]』で実行するコマンドの一覧です。各章で必要なコマンドを順番に記載しています。

---

# 第2章 さくらのクラウドにKubernetesクラスタを構築

## 2-2. ネットワーク設定

### SSH接続

```bash
$ ssh -i /path/to/your/private_key ubuntu@your_server_ip
```

### ネットワーク設定の適用

```bash
# サポートリポジトリをクローン
$ git clone https://github.com/kikulabo/practical-observability-microservices-demo

# リポジトリのディレクトリに移動
$ cd practical-observability-microservices-demo

# パッケージリストを更新
$ sudo apt update

# makeコマンドをインストール
$ sudo apt install -y make

# ネットワーク設定ファイル（netplan）を生成
$ make network-config

# ネットワーク設定をOSに適用
$ make network-apply
```

### 疎通確認

```bash
$ ping -c 3 192.168.10.101
$ ping -c 3 192.168.10.102
$ ping -c 3 192.168.10.103
```

## 2-3. Kubernetes をセットアップ

### Kubernetes のセットアップ

```bash
$ make k8s-set-up
```

### Kubernetes クラスタの初期化

```bash
# マスターノード（microservices-demo-01）で実行
$ sudo kubeadm init \
    --pod-network-cidr=10.244.0.0/16 \
    --apiserver-advertise-address=192.168.10.101 \
    --kubernetes-version=v1.34.1
```

### kubeconfigファイルをセットアップ

```bash
# マスターノード（microservices-demo-01）で実行
$ mkdir -p $HOME/.kube
$ sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
$ sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### ノードの状態を確認

```bash
$ kubectl get nodes
NAME                    STATUS     ROLES           AGE     VERSION
microservices-demo-01   NotReady   control-plane   5m23s   v1.34.1
```

### Flannel をクラスタに適用

```bash
# マスターノード（microservices-demo-01）で実行
$ kubectl apply -f https://github.com/flannel-io/flannel/releases/download/v0.27.4/kube-flannel.yml
```

### Flannel Pod の状態を確認

```bash
# マスターノード（microservices-demo-01）で実行
$ kubectl get pod -n kube-flannel
NAME                    READY   STATUS    RESTARTS   AGE
kube-flannel-ds-269qc   1/1     Running   0          70s
```

### ワーカーノードをクラスタに参加させる

```bash
# ワーカーノード（microservices-demo-02 〜 03）で実行
$ sudo kubeadm join 192.168.10.101:6443 \
--token xxx \
--discovery-token-ca-cert-hash yyy
```

### ノードの状態を確認

```bash
$ kubectl get nodes
NAME                    STATUS   ROLES           AGE     VERSION
microservices-demo-01   Ready    control-plane   23m     v1.34.1
microservices-demo-02   Ready    <none>          9m19s   v1.34.1
microservices-demo-03   Ready    <none>          8m51s   v1.34.1
```

# 第3章 マイクロサービスの分散トレーシング実装

## 3-1. 計装済みデモアプリケーションのデプロイ


### Mackerel API キーの Kubernetes シークレット登録

```bash
# マスターノード（microservices-demo-01）で実行
$ kubectl create secret generic mackerel-apikey \
    --from-literal=apikey='YOUR_MACKEREL_API_KEY' \
    --namespace=default
```

### さくらのクラウドのモニタリングスイートの Kubernetes シークレット登録

```bash
# マスターノード（microservices-demo-01）で実行
$ kubectl create secret generic sakura-monitoring-suite \
    --from-literal=logs-host='YOUR_LOGS_HOST' \
    --from-literal=logs-api-key='YOUR_LOGS_API_KEY' \
    --namespace=default
```

### シークレットの確認

```bash
# マスターノード（microservices-demo-01）で実行
$ kubectl get secret
NAME                      TYPE     DATA   AGE
mackerel-apikey           Opaque   1      78s
sakura-monitoring-suite   Opaque   2      6s
```

### Helm のインストール

```bash
$ curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash -s -- --version v3.19.0
```

### Fluent Bit Helm リポジトリを追加

```bash
# マスターノード（microservices-demo-01）で実行
## Fluent Helmチャートリポジトリを追加
$ helm repo add fluent https://fluent.github.io/helm-charts

## リポジトリを更新
$ helm repo update

## チャートが追加されたことを確認
$ helm search repo fluent
NAME                    CHART VERSION   APP VERSION     DESCRIPTION
fluent/fluent-bit       0.54.0          4.1.0           Fast and lightweight log processor and forwarde...
fluent/fluent-operator  3.5.0           3.5.0           Fluent Operator provides great flexibility in b...
fluent/fluentd          0.5.3           v1.17.1         A Helm chart for Kubernetes
```

### Fluent Bit をクラスタに適応

```bash
## practical-observability-microservices-demo ディレクトリに移動
$ cd practical-observability-microservices-demo

## リポジトリを更新
$ helm upgrade --install fluent-bit fluent/fluent-bit \
    --values fluent-bit-values.yaml \
    --version 0.54.0 \
    --namespace default
```

### デモアプリケーションををクラスタに適応

```bash
## マスターノード（microservices-demo-01）で実行
$ kubectl apply -k kubernetes-manifests/

## 数分後に実行
$ kubectl get pod
NAME                                     READY   STATUS    RESTARTS       AGE
adservice-88b6cfc77-wqv85                2/2     Running   2 (121m ago)   11h
cartservice-5b8f784886-vm5fl             2/2     Running   3 (120m ago)   11h
checkoutservice-6778f95f85-9lrlv         2/2     Running   2 (120m ago)   16h
currencyservice-64bf664f95-q68ml         2/2     Running   2 (120m ago)   11h
emailservice-7dfff7f4c5-bdxwq            2/2     Running   2 (120m ago)   10h
fluent-bit-c88m7                         1/1     Running   2 (120m ago)   13h
fluent-bit-jxgp8                         1/1     Running   1 (120m ago)   13h
fluent-bit-z5bjq                         1/1     Running   2 (120m ago)   13h
frontend-57c86684fb-qznls                2/2     Running   2 (120m ago)   16h
loadgenerator-645dcc4d68-db42r           1/1     Running   1 (121m ago)   16h
otel-collector-59fb784549-fk4z6          1/1     Running   1 (121m ago)   13h
paymentservice-5d7d98dfff-56gsw          2/2     Running   2 (120m ago)   10h
productcatalogservice-76dd84858f-b47w4   2/2     Running   2 (121m ago)   16h
recommendationservice-7bc576698f-dwzx5   2/2     Running   2 (121m ago)   10h
redis-cart-c8ff86559-25c8g               1/1     Running   1 (121m ago)   16h
shippingservice-77979d75fc-2dqqn         2/2     Running   2 (120m ago)   10h
```

### Pod の詳細情報とログの確認

```bash
# マスターノード（microservices-demo-01）で実行
## Podの状態を確認する
$ kubectl describe pod <pod_name>

## Podのログを確認する
$ kubectl logs <pod_name>
```
